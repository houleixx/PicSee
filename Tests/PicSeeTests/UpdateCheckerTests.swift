import XCTest
@testable import PicSee

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "PicSee.UpdateCheckerTests"

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testShowsAvailableUpdateWhenLatestIsNewer() async throws {
        let current = try XCTUnwrap(AppVersion("0.2.11"))
        let latest = release("0.2.13")
        let checker = UpdateChecker(
            currentVersion: current,
            defaults: defaults,
            fetchLatestRelease: { latest },
            downloadAndOpen: { _, _ in }
        )

        await checker.checkForUpdates()

        XCTAssertEqual(checker.availableUpdate?.version, latest.version)
        XCTAssertEqual(checker.status, .available)
    }

    func testFailedManualCheckReportsErrorAndCanRetryWithoutFalseSuccess() async throws {
        var shouldFail = true
        let latest = release("0.2.11")
        let checker = UpdateChecker(
            currentVersion: latest.version, defaults: defaults,
            fetchLatestRelease: {
                if shouldFail { throw URLError(.notConnectedToInternet) }
                return latest
            }, downloadAndOpen: { _, _ in }
        )
        let firstResult = await checker.checkForUpdatesManually()
        XCTAssertFalse(firstResult)
        XCTAssertNotNil(checker.checkError)

        shouldFail = false
        let secondResult = await checker.checkForUpdatesManually()
        XCTAssertTrue(secondResult)
        XCTAssertNil(checker.checkError)
    }

    func testConcurrentManualCheckDoesNotStartAnotherRequest() async throws {
        var continuation: CheckedContinuation<GitHubRelease, any Error>?
        var fetchCount = 0
        let started = expectation(description: "Check started")
        let latest = release("0.2.11")
        let checker = UpdateChecker(
            currentVersion: latest.version, defaults: defaults,
            fetchLatestRelease: {
                fetchCount += 1
                return try await withCheckedThrowingContinuation {
                    continuation = $0
                    started.fulfill()
                }
            }, downloadAndOpen: { _, _ in }
        )
        let firstCheck = Task { await checker.checkForUpdatesManually() }
        await fulfillment(of: [started], timeout: 2)
        let duplicateResult = await checker.checkForUpdatesManually()
        XCTAssertFalse(duplicateResult)
        XCTAssertEqual(checker.status, .checking)
        XCTAssertEqual(fetchCount, 1)
        continuation?.resume(returning: latest)
        let result = await firstCheck.value
        XCTAssertTrue(result)
    }

    func testDoesNotShowSameOrOlderRelease() async throws {
        let current = try XCTUnwrap(AppVersion("0.2.11"))
        let checker = UpdateChecker(
            currentVersion: current,
            defaults: defaults,
            fetchLatestRelease: { self.release("0.2.11") },
            downloadAndOpen: { _, _ in }
        )

        await checker.checkForUpdates()

        XCTAssertNil(checker.availableUpdate)
        XCTAssertEqual(checker.status, .idle)
    }

    func testIgnoresSpecificReleaseVersion() async throws {
        let current = try XCTUnwrap(AppVersion("0.2.11"))
        let latest = release("0.2.13")
        let checker = UpdateChecker(
            currentVersion: current,
            defaults: defaults,
            fetchLatestRelease: { latest },
            downloadAndOpen: { _, _ in }
        )

        await checker.checkForUpdates()
        checker.ignoreAvailableUpdate()
        await checker.checkForUpdates()

        XCTAssertNil(checker.availableUpdate)
        XCTAssertEqual(defaults.string(forKey: UpdateChecker.ignoredVersionDefaultsKey), "0.2.13")
    }

    func testManualCheckBypassesIgnoredReleaseVersion() async throws {
        defaults.set("0.2.13", forKey: UpdateChecker.ignoredVersionDefaultsKey)
        let current = try XCTUnwrap(AppVersion("0.2.11"))
        let latest = release("0.2.13")
        let checker = UpdateChecker(
            currentVersion: current,
            defaults: defaults,
            fetchLatestRelease: { latest },
            downloadAndOpen: { _, _ in }
        )

        await checker.checkForUpdatesManually()

        XCTAssertEqual(checker.availableUpdate?.version, latest.version)
        XCTAssertEqual(checker.status, .available)
    }

    func testNewerReleaseOverridesIgnoredOlderRelease() async throws {
        defaults.set("0.2.13", forKey: UpdateChecker.ignoredVersionDefaultsKey)
        let current = try XCTUnwrap(AppVersion("0.2.11"))
        let latest = release("0.2.14")
        let checker = UpdateChecker(
            currentVersion: current,
            defaults: defaults,
            fetchLatestRelease: { latest },
            downloadAndOpen: { _, _ in }
        )

        await checker.checkForUpdates()

        XCTAssertEqual(checker.availableUpdate?.version, latest.version)
        XCTAssertEqual(checker.status, .available)
    }

    func testChecksForUpdatesAtMostOncePerDay() async throws {
        let current = try XCTUnwrap(AppVersion("0.2.11"))
        let latest = release("0.2.14")
        var fetchCount = 0
        var now = date("2026-06-04T09:00:00Z")
        let checker = UpdateChecker(
            currentVersion: current,
            defaults: defaults,
            fetchLatestRelease: {
                fetchCount += 1
                return latest
            },
            downloadAndOpen: { _, _ in },
            now: { now }
        )

        await checker.checkForUpdatesIfNeeded()
        await checker.checkForUpdatesIfNeeded()
        now = date("2026-06-05T09:00:00Z")
        await checker.checkForUpdatesIfNeeded()

        XCTAssertEqual(fetchCount, 2)
        XCTAssertEqual(checker.availableUpdate?.version, latest.version)
    }

    func testManualCheckBypassesDailyThrottle() async throws {
        let current = try XCTUnwrap(AppVersion("0.2.11"))
        let latest = release("0.2.14")
        var fetchCount = 0
        let checker = UpdateChecker(
            currentVersion: current,
            defaults: defaults,
            fetchLatestRelease: {
                fetchCount += 1
                return latest
            },
            downloadAndOpen: { _, _ in },
            now: { self.date("2026-06-04T09:00:00Z") }
        )

        await checker.checkForUpdatesIfNeeded()
        await checker.checkForUpdatesManually()

        XCTAssertEqual(fetchCount, 2)
        XCTAssertEqual(checker.availableUpdate?.version, latest.version)
    }

    func testFailedAutomaticCheckCoolsDownWithoutConsumingPeriod() async throws {
        struct TestError: Error {}
        let latest = release("0.2.14")
        var fetchCount = 0
        var now = date("2026-06-04T09:00:00Z")
        let checker = UpdateChecker(
            currentVersion: try XCTUnwrap(AppVersion("0.2.11")), defaults: defaults,
            fetchLatestRelease: {
                fetchCount += 1
                if fetchCount == 1 { throw TestError() }
                return latest
            }, downloadAndOpen: { _, _ in }, now: { now }
        )
        await checker.checkForUpdatesIfNeeded()
        XCTAssertNil(defaults.object(forKey: UpdateChecker.lastCheckDateDefaultsKey))
        now = date("2026-06-04T09:59:59Z")
        await checker.checkForUpdatesIfNeeded()
        XCTAssertEqual(fetchCount, 1)
        now = date("2026-06-04T10:00:00Z")
        await checker.checkForUpdatesIfNeeded()
        XCTAssertEqual(fetchCount, 2)
        XCTAssertEqual(checker.availableUpdate?.version, latest.version)
        XCTAssertNil(defaults.object(forKey: UpdateChecker.lastAutomaticFailureDefaultsKey))
    }

    func testNaturalPeriodsUseLocalTimeAndMondayWeeks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        calendar.firstWeekday = 1 // Frequency must still use Monday.
        let cases: [(UpdateCheckFrequency, String, String, Bool)] = [
            (.daily, "2026-06-04T15:59:59Z", "2026-06-04T16:00:00Z", true),
            (.daily, "2026-06-04T16:00:00Z", "2026-06-05T15:59:59Z", false),
            (.weekly, "2026-06-06T16:00:00Z", "2026-06-07T15:59:59Z", false),
            (.weekly, "2026-06-07T15:59:59Z", "2026-06-07T16:00:00Z", true),
            (.weekly, "2026-12-31T16:00:00Z", "2027-01-03T15:59:59Z", false),
            (.weekly, "2027-01-03T15:59:59Z", "2027-01-03T16:00:00Z", true),
            (.monthly, "2026-06-01T00:00:00Z", "2026-06-30T15:59:59Z", false),
            (.monthly, "2026-06-30T15:59:59Z", "2026-06-30T16:00:00Z", true),
            (.monthly, "2026-12-31T15:59:59Z", "2026-12-31T16:00:00Z", true)
        ]
        for (frequency, last, now, expected) in cases {
            XCTAssertEqual(frequency.isDue(lastCheck: date(last), now: date(now), calendar: calendar), expected,
                           "\(frequency): \(last) → \(now)")
        }
        for frequency in UpdateCheckFrequency.allCases {
            XCTAssertEqual(frequency.isDue(lastCheck: nil, now: Date(), calendar: calendar), frequency != .never)
        }
    }

    func testFrequencyPersistsAndManualCheckCountsTowardsPeriod() async throws {
        let latest = release("0.2.14")
        var fetchCount = 0
        let makeChecker = {
            UpdateChecker(currentVersion: latest.version, defaults: self.defaults,
                          fetchLatestRelease: { fetchCount += 1; return latest },
                          downloadAndOpen: { _, _ in })
        }
        let checker = makeChecker()
        XCTAssertEqual(checker.frequency, .daily)
        checker.setFrequency(.never)
        XCTAssertEqual(makeChecker().frequency, .never)
        await checker.checkForUpdatesIfNeeded()
        XCTAssertEqual(fetchCount, 0)
        let upToDate = await checker.checkForUpdatesManually()
        XCTAssertTrue(upToDate)
        XCTAssertEqual(fetchCount, 1)
        XCTAssertNotNil(defaults.object(forKey: UpdateChecker.lastCheckDateDefaultsKey))
        checker.setFrequency(.monthly)
        await checker.checkForUpdatesIfNeeded()
        XCTAssertEqual(fetchCount, 1)
        checker.setFrequency(.weekly)
        XCTAssertEqual(makeChecker().frequency, .weekly)
    }

    func testManualCheckBypassesAutomaticFailureCooldown() async throws {
        struct TestError: Error {}
        let latest = release("0.2.14")
        var fetchCount = 0
        let checker = UpdateChecker(currentVersion: latest.version, defaults: defaults,
            fetchLatestRelease: {
                fetchCount += 1
                if fetchCount == 1 { throw TestError() }
                return latest
            }, downloadAndOpen: { _, _ in })
        await checker.checkForUpdatesIfNeeded()
        let upToDate = await checker.checkForUpdatesManually()
        XCTAssertTrue(upToDate)
        await checker.checkForUpdatesIfNeeded()
        XCTAssertEqual(fetchCount, 2)
    }

    func testDownloadUsesAvailableReleaseURL() async throws {
        let current = try XCTUnwrap(AppVersion("0.2.11"))
        let latest = release("0.2.13")
        var downloadedURL: URL?
        var reportedProgress: [Double] = []
        var didPrepareInstall = false
        let checker = UpdateChecker(
            currentVersion: current,
            defaults: defaults,
            fetchLatestRelease: { latest },
            downloadAndOpen: { url, progress in
                downloadedURL = url
                progress(0.42)
                reportedProgress.append(0.42)
            },
            prepareInstall: { didPrepareInstall = true }
        )

        await checker.checkForUpdates()
        await checker.downloadAvailableUpdate()

        XCTAssertEqual(downloadedURL, latest.dmgURL)
        XCTAssertEqual(reportedProgress, [0.42])
        XCTAssertTrue(didPrepareInstall)
        XCTAssertEqual(checker.downloadProgress, 1)
        XCTAssertEqual(checker.status, .downloaded)
    }

    func testInstallTargetUsesCurrentAppContainer() {
        let executableURL = URL(fileURLWithPath: "/Users/holly/Applications/PicSee.app/Contents/MacOS/PicSee")

        let installTargetURL = UpdateChecker.installTargetDirectory(forExecutableURL: executableURL)

        XCTAssertEqual(installTargetURL.path, "/Users/holly/Applications")
    }

    func testAppBundleURLUsesCurrentExecutableContainer() {
        let executableURL = URL(fileURLWithPath: "/Users/holly/Applications/PicSee.app/Contents/MacOS/PicSee")

        let appURL = UpdateChecker.currentAppBundleURL(forExecutableURL: executableURL)

        XCTAssertEqual(appURL.path, "/Users/holly/Applications/PicSee.app")
    }

    func testDownloadFailureDoesNotExitAndAllowsRetry() async throws {
        let latest = release("0.2.13")
        var fail = true
        var exited = false
        let checker = UpdateChecker(currentVersion: try XCTUnwrap(AppVersion("0.2.11")), defaults: defaults,
            fetchLatestRelease: { latest }, downloadAndOpen: { _, _ in
                if fail { throw UpdateInstaller.Failure.invalidResponse }
            }, prepareInstall: { exited = true })
        await checker.checkForUpdates()
        await checker.downloadAvailableUpdate()
        XCTAssertEqual(checker.status, .failed)
        XCTAssertNotNil(checker.downloadError)
        XCTAssertFalse(exited)
        XCTAssertEqual(checker.availableUpdate, latest)
        fail = false
        await checker.downloadAvailableUpdate()
        XCTAssertEqual(checker.status, .downloaded)
        XCTAssertNil(checker.downloadError)
        XCTAssertTrue(exited)
    }

    private func release(_ versionString: String) -> GitHubRelease {
        let version = AppVersion(versionString)!
        return GitHubRelease(
            tagName: "v\(version.displayString)",
            version: version,
            dmgURL: GitHubReleaseClient.dmgDownloadURL(for: version)
        )
    }

    private func date(_ isoString: String) -> Date {
        ISO8601DateFormatter().date(from: isoString)!
    }
}
