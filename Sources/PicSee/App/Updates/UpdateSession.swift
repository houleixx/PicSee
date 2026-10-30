import AppKit

/// A one-shot handoff to the process launched by the installer, never a normal-launch preference.
struct UpdateSession: Codable, Equatable {
    struct Viewer: Codable, Equatable {
        var url: URL
        var frame: CGRect
        var zoom: CGFloat
        var pan: CGSize
        var rotation: Int
        var fullScreen: Bool
        var desktopFullScreen: Bool
        var minimized: Bool
    }

    var viewer: Viewer?
    var settingsPage: String?
    var settingsFrame: CGRect?
    var settingsMinimized = false
    var settingsInFront = false

    func write() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("picsee-update-session-\(UUID().uuidString).json")
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        return url
    }

    static func consume(arguments: [String]) -> Self? {
        guard let index = arguments.firstIndex(of: "--picsee-update-session"),
              arguments.indices.contains(index + 1) else { return nil }
        let url = URL(fileURLWithPath: arguments[index + 1])
        // Only consume files created for this handoff in our temporary directory.
        guard url.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL,
              url.lastPathComponent.hasPrefix("picsee-update-session-"), url.pathExtension == "json" else { return nil }
        guard let data = try? Data(contentsOf: url), let session = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return session
    }
}
