import AppKit
import Foundation
import ImageIO

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
    private static let prefetchWorker = ImageLoadWorker()

    /// One speculative decoder, separate from foreground reads. Never decode
    /// animations or images larger than the cache can retain speculatively.
    nonisolated static func prefetch(_ url: URL, byteLimit: Int) async -> LoadedImage? {
        await prefetchWorker.readPrefetch(url, byteLimit: byteLimit)
    }

    private func readPrefetch(_ url: URL, byteLimit: Int) -> LoadedImage? {
        guard !Task.isCancelled,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 8)
        let fileBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let (total, totalOverflow) = bytes.addingReportingOverflow(fileBytes)
        guard !pixelOverflow, !byteOverflow, !totalOverflow, total <= byteLimit, !Task.isCancelled else { return nil }
        return LoadedImage.read(url)
    }

    nonisolated static func load(_ url: URL) async -> LoadedImage? {
        await shared.read(url)
    }

    func read(_ url: URL) -> LoadedImage? {
        guard !Task.isCancelled else { return nil }
        return LoadedImage.read(url)
    }
}
