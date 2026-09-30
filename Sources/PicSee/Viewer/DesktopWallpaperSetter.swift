import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Retains wallpaper files outside the temporary directory: macOS may need them
/// again after logout, and another screen or Space may still use an older file.
actor DesktopWallpaperStore {
    private let directory: URL

    init(directory: URL = URL.applicationSupportDirectory
        .appendingPathComponent("PicSee/Wallpapers", isDirectory: true)) {
        self.directory = directory
    }

    func save(_ image: CGImage) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        do {
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
            ) else { throw ImageExporterError.invalidDestination }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw ImageExporterError.failedToFinalize }
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

@MainActor
struct DesktopWallpaperSetter {
    private let store: DesktopWallpaperStore

    init(store: DesktopWallpaperStore = DesktopWallpaperStore()) {
        self.store = store
    }

    func set(_ image: NSImage, apply: (URL) throws -> Void) async throws {
        guard let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageExporterError.missingCGImage
        }
        let url = try await store.save(pixels)
        do {
            try apply(url)
        } catch {
            await store.discard(url)
            throw error
        }
    }
}
