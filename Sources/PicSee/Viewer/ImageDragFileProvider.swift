import AppKit
import Darwin

/// Local files keep their original representation. Transient files and in-memory
/// images get a private, leased-by-process directory that survives the drop.
final class ImageDragFileProvider {
    static let retentionInterval: TimeInterval = 24 * 60 * 60
    static let defaultRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("PicSee-DragExports", isDirectory: true)

    private let root: URL
    private let temporaryResourceRoots: [URL]
    private let fileManager = FileManager.default

    init(
        root: URL = ImageDragFileProvider.defaultRoot,
        temporaryResourceRoots: [URL] = [FileManager.default.temporaryDirectory, URL(fileURLWithPath: "/tmp")]
    ) {
        self.root = root
        self.temporaryResourceRoots = temporaryResourceRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
    }

    func fileURL(sourceURL: URL?, image: NSImage) throws -> URL {
        cleanupExpiredFiles()
        let resolved = sourceURL.flatMap { $0.isFileURL ? $0.resolvingSymlinksInPath().standardizedFileURL : nil }
        if let resolved,
           (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
           fileManager.isReadableFile(atPath: resolved.path) {
            let isTemporary = temporaryResourceRoots.contains { resolved.path.hasPrefix($0.path + "/") }
            if !isTemporary { return resolved }

            // A temporary source may disappear independently of our drag session.
            return try makeTemporaryFile(named: resolved.lastPathComponent) { destination in
                try fileManager.copyItem(at: resolved, to: destination)
            }
        }

        // There is no original byte stream in this fallback. Always use a real
        // PNG extension, even when a remote/missing source URL ends in .gif/.jpg.
        let name = sourceURL?.deletingPathExtension().lastPathComponent ?? "PicSee-image"
        return try makeTemporaryFile(named: name + ".png") { destination in
            try ImageExporter.export(image, to: destination, options: .init(format: .png, pixelSize: nil))
        }
    }

    func cleanupExpiredFiles(
        now: Date = Date(),
        processIsRunning: (Int32) -> Bool = { kill($0, 0) == 0 || errno == EPERM }
    ) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let directories = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
        ) else { return }
        for directory in directories {
            let parts = directory.lastPathComponent.split(separator: "-")
            guard parts.count >= 3, parts[0] == "export", let pid = Int32(parts[1]), pid > 0,
                  let values = try? directory.resourceValues(forKeys: keys),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) > Self.retentionInterval,
                  !processIsRunning(pid)
            else { continue }
            try? fileManager.removeItem(at: directory)
        }
    }

    private func makeTemporaryFile(named suggestedName: String, write: (URL) throws -> Void) throws -> URL {
        let directory = root.appendingPathComponent("export-\(getpid())-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:\\"))
        let sanitized = suggestedName.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = sanitized.isEmpty || sanitized == "." || sanitized == ".." ? "PicSee-image.png" : sanitized
        let destination = directory.appendingPathComponent(name)
        do {
            try write(destination)
            return destination
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }
}
