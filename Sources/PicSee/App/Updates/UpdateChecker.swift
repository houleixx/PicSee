import AppKit
import Foundation

enum UpdateStatus: Equatable {
    case idle
    case checking
    case available
    case downloading
    case downloaded
    case failed
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let ignoredVersionDefaultsKey = "PicSee.IgnoredUpdateVersion"
    static let lastCheckDateDefaultsKey = "PicSee.LastUpdateCheckDate"

    @Published private(set) var availableUpdate: GitHubRelease?
    @Published private(set) var status: UpdateStatus = .idle
    @Published private(set) var downloadProgress: Double?
    @Published private var checkFailed = false
    var checkError: String? { checkFailed ? L10n.text("检查更新失败，请检查网络后重试。") : nil }

    @Published private var downloadFailure: (any Error)?
    var downloadError: String? { downloadFailure.map(L10n.errorDescription) }

    private let currentVersion: AppVersion
    private let defaults: UserDefaults
    private let fetchLatestRelease: () async throws -> GitHubRelease
    private let downloadAndOpen: (URL, @MainActor @Sendable @escaping (Double) -> Void) async throws -> Void
    private let prepareInstall: () -> Void
    private let now: () -> Date
    private let calendar: Calendar

    init?(
        bundleInfo: [String: Any],
        defaults: UserDefaults = .standard,
        releaseClient: GitHubReleaseClient = GitHubReleaseClient()
    ) {
        guard
            let versionString = bundleInfo["CFBundleShortVersionString"] as? String,
            let currentVersion = AppVersion(versionString)
        else {
            return nil
        }

        self.currentVersion = currentVersion
        self.defaults = defaults
        self.fetchLatestRelease = { try await releaseClient.fetchLatestRelease() }
        self.downloadAndOpen = { try await Self.downloadAndOpenDMG(from: $0, progress: $1) }
        self.prepareInstall = { NSApp.terminate(nil) }
        self.now = Date.init
        self.calendar = .current
    }

    init(
        currentVersion: AppVersion,
        defaults: UserDefaults,
        fetchLatestRelease: @escaping () async throws -> GitHubRelease,
        downloadAndOpen: @escaping (URL, @MainActor @Sendable @escaping (Double) -> Void) async throws -> Void,
        prepareInstall: @escaping () -> Void = {},
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.fetchLatestRelease = fetchLatestRelease
        self.downloadAndOpen = downloadAndOpen
        self.prepareInstall = prepareInstall
        self.now = now
        self.calendar = calendar
    }

    func checkForUpdatesIfNeeded() async {
        let currentDate = now()
        if let lastCheckDate = defaults.object(forKey: Self.lastCheckDateDefaultsKey) as? Date,
           calendar.isDate(lastCheckDate, inSameDayAs: currentDate) {
            return
        }

        if await performUpdateCheck() {
            defaults.set(currentDate, forKey: Self.lastCheckDateDefaultsKey)
        }
    }

    func checkForUpdates() async {
        _ = await performUpdateCheck()
    }

    /// Returns whether the check succeeded and the app is already up to date.
    @discardableResult
    func checkForUpdatesManually() async -> Bool {
        let succeeded = await performUpdateCheck(ignoresSkippedVersion: true)
        return succeeded && availableUpdate == nil
    }

    @discardableResult
    private func performUpdateCheck(ignoresSkippedVersion: Bool = false) async -> Bool {
        guard status != .checking, status != .downloading else { return false }
        checkFailed = false
        status = .checking
        downloadProgress = nil

        do {
            let release = try await fetchLatestRelease()
            guard shouldShow(release: release, ignoresSkippedVersion: ignoresSkippedVersion) else {
                availableUpdate = nil
                status = .idle
                return true
            }

            availableUpdate = release
            status = .available
            return true
        } catch {
            availableUpdate = nil
            status = .idle
            checkFailed = true
            return false
        }
    }

    func ignoreAvailableUpdate() {
        guard let availableUpdate else { return }
        defaults.set(availableUpdate.version.displayString, forKey: Self.ignoredVersionDefaultsKey)
        self.availableUpdate = nil
        status = .idle
        downloadProgress = nil
    }

    func downloadAvailableUpdate() async {
        guard let availableUpdate, status != .checking, status != .downloading else { return }
        status = .downloading
        downloadProgress = 0
        downloadFailure = nil

        do {
            try await downloadAndOpen(availableUpdate.dmgURL) { [weak self] progress in
                self?.downloadProgress = min(max(progress, 0), 1)
            }
            downloadProgress = 1
            self.availableUpdate = nil
            status = .downloaded
            prepareInstall()
        } catch {
            downloadFailure = error
            status = .failed
        }
    }

    private func shouldShow(release: GitHubRelease, ignoresSkippedVersion: Bool) -> Bool {
        guard release.version > currentVersion else { return false }
        guard !ignoresSkippedVersion else { return true }
        return defaults.string(forKey: Self.ignoredVersionDefaultsKey) != release.version.displayString
    }

    nonisolated private static func downloadAndOpenDMG(
        from sourceURL: URL,
        progress: @MainActor @Sendable @escaping (Double) -> Void
    ) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: sourceURL)
        try UpdateInstaller.validateResponse(response)
        let expectedContentLength = response.expectedContentLength
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(sourceURL.pathExtension)
        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)

        let fileHandle = try FileHandle(forWritingTo: temporaryURL)
        defer {
            try? fileHandle.close()
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        var downloadedBytes: Int64 = 0
        var lastReportedProgress = 0.0
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)

        for try await byte in bytes {
            buffer.append(byte)
            downloadedBytes += 1

            if buffer.count >= 64 * 1024 {
                try fileHandle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }

            if expectedContentLength > 0 {
                let currentProgress = Double(downloadedBytes) / Double(expectedContentLength)
                if currentProgress - lastReportedProgress >= 0.01 {
                    await progress(currentProgress)
                    lastReportedProgress = currentProgress
                }
            }
        }

        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: buffer)
        }
        try UpdateInstaller.validateLength(downloaded: downloadedBytes, expected: expectedContentLength)
        try fileHandle.close()
        await progress(1)

        let destinationURL = try updateDownloadDestination(for: sourceURL)
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destinationURL)
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        let target = currentAppBundleURL()
        let staging = try await UpdateInstaller.prepare(dmg: destinationURL, target: target)
        do {
            try startInstaller(staging: staging, targetAppURL: target)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    static func installTargetDirectory(
        forExecutableURL executableURL: URL = Bundle.main.executableURL ?? URL(fileURLWithPath: "/Applications/PicSee.app/Contents/MacOS/PicSee")
    ) -> URL {
        currentAppBundleURL(forExecutableURL: executableURL).deletingLastPathComponent()
    }

    nonisolated static func currentAppBundleURL(
        forExecutableURL executableURL: URL = Bundle.main.executableURL ?? URL(fileURLWithPath: "/Applications/PicSee.app/Contents/MacOS/PicSee")
    ) -> URL {
        let pathComponents = executableURL.standardizedFileURL.pathComponents
        guard let appIndex = pathComponents.lastIndex(where: { $0.hasSuffix(".app") }), appIndex > 0 else {
            return URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Applications", isDirectory: true)
                .appendingPathComponent("PicSee.app", isDirectory: true)
        }

        let appComponents = pathComponents.prefix(appIndex + 1)
        return URL(fileURLWithPath: "/" + appComponents.dropFirst().joined(separator: "/"), isDirectory: true)
    }

    nonisolated static func installerScript() -> String { UpdateInstaller.script }

    nonisolated private static func startInstaller(staging: URL, targetAppURL: URL) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("picsee-install-\(UUID().uuidString).zsh")
        try installerScript().write(to: scriptURL, atomically: true, encoding: .utf8)
        let directory = staging.deletingLastPathComponent()
        let statusURL = directory.appendingPathComponent(".PicSee-update-status")
        let logURL = directory.appendingPathComponent(".PicSee-update.log")
        let lock = directory.appendingPathComponent(".PicSee-update-lock", isDirectory: true)
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
        var started = false
        defer { if !started { try? FileManager.default.removeItem(at: lock) } }
        try? FileManager.default.removeItem(at: statusURL)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path, staging.path, targetAppURL.path, statusURL.path,
                             String(ProcessInfo.processInfo.processIdentifier)]
        process.standardOutput = log
        process.standardError = log
        do {
            try process.run()
            started = true
        } catch {
            try? FileManager.default.removeItem(at: scriptURL)
            throw error
        }
    }

    nonisolated private static func updateDownloadDestination(for sourceURL: URL) throws -> URL {
        let cachesURL = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let updatesDirectory = cachesURL.appendingPathComponent("PicSee/Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: updatesDirectory, withIntermediateDirectories: true)
        return updatesDirectory.appendingPathComponent(sourceURL.lastPathComponent)
    }
}
