import Foundation

/// Prepare and authenticate the replacement before the viewer exits. Staging
/// lives beside the target, so installation is a rename on the same volume.
enum UpdateInstaller {
    enum Failure: LocalizedError {
        case invalidResponse
        case invalidApplication
        case command(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: L10n.text("更新下载不完整或服务器响应无效，请重试。")
            case .invalidApplication: L10n.text("更新应用未通过身份或签名验证，请从发布页面手动安装。")
            case .command(let details): L10n.text("更新安装失败，原版本已保留。\n%1$@", details)
            }
        }
    }

    static func validateResponse(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              response.url?.scheme == "https" else { throw Failure.invalidResponse }
    }

    static func validateLength(downloaded: Int64, expected: Int64) throws {
        guard downloaded > 0, expected <= 0 || downloaded == expected else { throw Failure.invalidResponse }
    }

    static func prepare(dmg: URL, target: URL) async throws -> URL {
        let worker = Task.detached(priority: .userInitiated) {
            try prepareSynchronously(dmg: dmg, target: target)
        }
        return try await withTaskCancellationHandler {
            let staging = try await worker.value
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: staging)
                throw CancellationError()
            }
            return staging
        } onCancel: { worker.cancel() }
    }

    private static func prepareSynchronously(dmg: URL, target: URL) throws -> URL {
        let files = FileManager.default
        let mount = files.temporaryDirectory.appendingPathComponent("picsee-update-\(UUID().uuidString)", isDirectory: true)
        let staging = target.deletingLastPathComponent().appendingPathComponent(".PicSee.app.updating-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: mount, withIntermediateDirectories: false)
        var prepared = false
        defer {
            _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"])
            try? files.removeItem(at: mount)
            if !prepared { try? files.removeItem(at: staging) }
        }
        try Task.checkCancellation()
        _ = try run("/usr/bin/hdiutil", ["verify", dmg.path])
        _ = try run("/usr/bin/hdiutil", ["attach", dmg.path, "-mountpoint", mount.path, "-nobrowse", "-readonly", "-quiet"])
        let source = mount.appendingPathComponent("PicSee.app", isDirectory: true)
        guard let installed = Bundle(url: target), let incoming = Bundle(url: source),
              installed.bundleIdentifier == "local.picsee.viewer",
              incoming.bundleIdentifier == installed.bundleIdentifier,
              let oldVersion = installed.infoDictionary?["CFBundleShortVersionString"] as? String,
              let newVersion = incoming.infoDictionary?["CFBundleShortVersionString"] as? String,
              let old = AppVersion(oldVersion), let new = AppVersion(newVersion), new > old else {
            throw Failure.invalidApplication
        }
        let identity = try run("/usr/bin/codesign", ["-dv", "--verbose=4", target.path])
        guard let teamLine = identity.split(separator: "\n").first(where: { $0.hasPrefix("TeamIdentifier=") }) else {
            throw Failure.invalidApplication
        }
        let team = String(teamLine.dropFirst("TeamIdentifier=".count))
        guard team.count == 10, team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw Failure.invalidApplication
        }
        _ = try run("/usr/bin/codesign", verificationArguments(application: source, team: team))
        _ = try run("/usr/sbin/spctl", ["--assess", "--type", "execute", source.path])
        try Task.checkCancellation()
        _ = try run("/usr/bin/ditto", [source.path, staging.path])
        _ = try run("/usr/bin/codesign", verificationArguments(application: staging, team: team))
        try Task.checkCancellation()
        prepared = true
        return staging
    }

    static func verificationArguments(application: URL, team: String) -> [String] {
        let requirement = "identifier \"local.picsee.viewer\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        // Without '=', codesign interprets the requirement as a filename.
        return ["--verify", "--deep", "--strict", "-R", "=" + requirement, application.path]
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw Failure.command(text) }
        return text
    }

    /// No application is deleted before its replacement is ready. EXIT restores
    /// the backup if either the final rename or launch fails.
    static let script = """
    #!/bin/zsh
    set -euo pipefail
    PATH=/usr/bin:/bin:/usr/sbin:/sbin
    STAGED_APP="$1"
    TARGET_APP="$2"
    STATUS_FILE="$3"
    VIEWER_PID="$4"
    BACKUP_APP="${TARGET_APP}.previous.$$"
    installed=false
    cleanup() {
      result=$?
      trap - EXIT
      if [ "$installed" != true ]; then
        if [ -d "$BACKUP_APP" ]; then
          rm -rf "$TARGET_APP"
          mv "$BACKUP_APP" "$TARGET_APP" || true
        fi
        printf 'failed\\n' > "$STATUS_FILE"
        open "$TARGET_APP" || true
      else
        printf 'success\\n' > "$STATUS_FILE"
        rm -rf "$BACKUP_APP"
      fi
      rmdir "${TARGET_APP:h}/.PicSee-update-lock" 2>/dev/null || true
      rm -rf "$STAGED_APP"
      rm -f "$0"
      exit "$result"
    }
    trap cleanup EXIT
    # Wait for the requesting viewer to actually exit rather than guessing a delay.
    for attempt in {1..100}; do
      if ! kill -0 "$VIEWER_PID" 2>/dev/null; then break; fi
      sleep 0.1
    done
    if kill -0 "$VIEWER_PID" 2>/dev/null; then exit 1; fi
    codesign --verify --deep --strict "$STAGED_APP"
    spctl --assess --type execute "$STAGED_APP"
    mv "$TARGET_APP" "$BACKUP_APP"
    mv "$STAGED_APP" "$TARGET_APP"
    open "$TARGET_APP"
    installed=true
    """
}
