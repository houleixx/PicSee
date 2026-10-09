// Older SDKs do not annotate NSImage as Sendable. This immutable snapshot is
// decoded on one worker and never mutated there after handing it to the viewer.
@preconcurrency import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

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
            let transparent = TransparencyBackground.containsTransparency(image)
            let displayImage = decoded.flatMap { preparedPNG(image, bitmap: $0, url: url) } ?? image
            return LoadedImage(image: displayImage, metadata: ImageParameterMetadata(url: url), pixelSize: pixels, byteCount: size.map(Int64.init),
                               containsTransparency: transparent)
        }
    }

    /// A large PNG's file-backed representation can decode again on the main
    /// thread when AppKit draws it. Keep source pixels for zoom/export, and add
    /// a smaller representation that AppKit can select for fitted viewing.
    private static func preparedPNG(_ image: NSImage, bitmap: CGImage, url: URL) -> NSImage? {
        let previewEdge = 2048
        guard max(bitmap.width, bitmap.height) > previewEdge,
              bitmap.bitsPerComponent == 8, !bitmap.isMask,
              let colorSpace = bitmap.colorSpace, colorSpace.model == .rgb,
              (try? ImageRenderBudget.dimensions(for: CGSize(width: bitmap.width, height: bitmap.height))) != nil,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceGetCount(source) == 1,
              let data = bitmap.dataProvider?.data,
              let provider = CGDataProvider(data: data),
              let fullResolution = CGImage(width: bitmap.width, height: bitmap.height,
                bitsPerComponent: bitmap.bitsPerComponent, bitsPerPixel: bitmap.bitsPerPixel,
                bytesPerRow: bitmap.bytesPerRow, space: colorSpace, bitmapInfo: bitmap.bitmapInfo,
                provider: provider, decode: bitmap.decode, shouldInterpolate: bitmap.shouldInterpolate,
                intent: bitmap.renderingIntent) else { return nil }
        let ratio = CGFloat(previewEdge) / CGFloat(max(bitmap.width, bitmap.height))
        let width = max(1, Int((CGFloat(bitmap.width) * ratio).rounded()))
        let height = max(1, Int((CGFloat(bitmap.height) * ratio).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        context.draw(fullResolution, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let preview = context.makeImage() else { return nil }
        let prepared = NSImage(size: image.size)
        // Keep original pixels authoritative for export sizing, including high-DPI files.
        let originalRepresentation = NSBitmapImageRep(cgImage: fullResolution)
        originalRepresentation.size = image.size
        prepared.addRepresentation(originalRepresentation)
        let representation = NSBitmapImageRep(cgImage: preview)
        representation.size = image.size
        prepared.addRepresentation(representation)
        return prepared
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
