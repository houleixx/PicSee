import XCTest
@testable import PicSee

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "PicSee.UpdateCheckerTests"

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try await super.tearDown()
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

    func testInstallerScriptInstallsIntoCurrentAppPath() {
        let script = UpdateChecker.installerScript()

        XCTAssertTrue(script.contains("hdiutil attach"))
        XCTAssertTrue(script.contains("ditto \"$SOURCE_APP\" \"$TEMP_APP\""))
        XCTAssertTrue(script.contains("mv \"$TEMP_APP\" \"$TARGET_APP\""))
        XCTAssertTrue(script.contains("open \"$TARGET_APP\""))
    }

    private func release(_ versionString: String) -> GitHubRelease {
        let version = AppVersion(versionString)!
        return GitHubRelease(
            tagName: "v\(version.displayString)",
            version: version,
            dmgURL: GitHubReleaseClient.dmgDownloadURL(for: version)
        )
    }
}
