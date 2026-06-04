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

    @discardableResult
    private func performUpdateCheck() async -> Bool {
        status = .checking
        downloadProgress = nil

        do {
            let release = try await fetchLatestRelease()
            guard shouldShow(release: release) else {
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
        guard let availableUpdate else { return }
        status = .downloading
        downloadProgress = 0

        do {
            try await downloadAndOpen(availableUpdate.dmgURL) { [weak self] progress in
                self?.downloadProgress = min(max(progress, 0), 1)
            }
            downloadProgress = 1
            self.availableUpdate = nil
            status = .downloaded
            prepareInstall()
        } catch {
            status = .failed
        }
    }

    private func shouldShow(release: GitHubRelease) -> Bool {
        guard release.version > currentVersion else { return false }
        return defaults.string(forKey: Self.ignoredVersionDefaultsKey) != release.version.displayString
    }

    private static func downloadAndOpenDMG(
        from sourceURL: URL,
        progress: @MainActor @Sendable @escaping (Double) -> Void
    ) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: sourceURL)
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
                    progress(currentProgress)
                    lastReportedProgress = currentProgress
                }
            }
        }

        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: buffer)
        }
        progress(1)

        let destinationURL = try updateDownloadDestination(for: sourceURL)
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destinationURL)
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        try startInstaller(forDMG: destinationURL, targetAppURL: currentAppBundleURL())
    }

    static func installTargetDirectory(
        forExecutableURL executableURL: URL = Bundle.main.executableURL ?? URL(fileURLWithPath: "/Applications/PicSee.app/Contents/MacOS/PicSee")
    ) -> URL {
        currentAppBundleURL(forExecutableURL: executableURL).deletingLastPathComponent()
    }

    static func currentAppBundleURL(
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

    static func installerScript() -> String {
        """
        #!/bin/zsh
        set -euo pipefail

        DMG_PATH="$1"
        TARGET_APP="$2"
        TARGET_DIR="$(dirname "$TARGET_APP")"
        MOUNT_DIR="$(mktemp -d /tmp/picsee-update.XXXXXX)"
        TEMP_APP="$TARGET_DIR/.PicSee.app.updating.$$"

        cleanup() {
          hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
          rm -rf "$MOUNT_DIR" "$TEMP_APP"
          rm -f "$0"
        }
        trap cleanup EXIT

        sleep 1
        hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -quiet

        SOURCE_APP="$MOUNT_DIR/PicSee.app"
        if [ ! -d "$SOURCE_APP" ]; then
          exit 1
        fi

        rm -rf "$TEMP_APP"
        ditto "$SOURCE_APP" "$TEMP_APP"
        rm -rf "$TARGET_APP"
        mv "$TEMP_APP" "$TARGET_APP"
        xattr -dr com.apple.quarantine "$TARGET_APP" >/dev/null 2>&1 || true
        open "$TARGET_APP"
        """
    }

    private static func startInstaller(forDMG dmgURL: URL, targetAppURL: URL) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("picsee-install-\(UUID().uuidString)")
            .appendingPathExtension("zsh")
        try installerScript().write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path, dmgURL.path, targetAppURL.path]
        try process.run()
    }

    private static func updateDownloadDestination(for sourceURL: URL) throws -> URL {
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
