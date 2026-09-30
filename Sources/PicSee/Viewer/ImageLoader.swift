import AppKit
import Foundation

/// The image is built and validated on one worker, then handed to the main
/// actor. Neither the worker nor this immutable snapshot mutates it afterward.
struct LoadedImage: Sendable {
    let image: NSImage
    let metadata: ImageParameterMetadata?
    let pixelSize: CGSize?
    let byteCount: Int64?
    let containsTransparency: Bool

    static func read(_ url: URL) -> LoadedImage? {
        autoreleasepool {
            guard let image = NSImage(contentsOf: url), image.isValid else { return nil }
            // Warm the representation before presentation/OCR asks for pixels.
            let decoded = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            let pixels = decoded.map { CGSize(width: $0.width, height: $0.height) } ?? ImageExporter.pixelSize(of: image)
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            return LoadedImage(image: image, metadata: ImageParameterMetadata(url: url), pixelSize: pixels, byteCount: size.map(Int64.init),
                               containsTransparency: TransparencyBackground.containsTransparency(image))
        }
    }
}

/// Injectable execution policy keeps deterministic model tests synchronous;
/// the application uses background file reads and image validation.
enum ImageLoadingMode: Sendable {
    case immediate, background
}

/// Serialize decoding so rapidly cancelled requests cannot fan out large image
/// allocations. Cancellation is checked again when a queued request gets a turn.
actor ImageLoadWorker {
    static let shared = ImageLoadWorker()

    nonisolated static func load(_ url: URL) async -> LoadedImage? {
        await shared.read(url)
    }

    func read(_ url: URL) -> LoadedImage? {
        guard !Task.isCancelled else { return nil }
        return LoadedImage.read(url)
    }
}
