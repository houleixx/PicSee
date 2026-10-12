@preconcurrency import AppKit
import CoreImage
import ImageIO
import QuartzCore

private enum LargeImageAssociation {
    // A stable Objective-C association key, never read or changed as a value.
    nonisolated(unsafe) static var key: UInt8 = 0
}

extension NSImage {
    var largeImageSource: LargeImageSource? {
        objc_getAssociatedObject(self, &LargeImageAssociation.key) as? LargeImageSource
    }

    /// Attach immutable source metadata without advertising an oversized bitmap
    /// representation to AppKit. Ordinary NSImage instances remain unchanged.
    static func largeImage(source: LargeImageSource) -> NSImage {
        let image = NSImage(size: source.pixelSize)
        let rep = NSBitmapImageRep(cgImage: source.preview)
        rep.size = source.pixelSize
        image.addRepresentation(rep)
        objc_setAssociatedObject(image, &LargeImageAssociation.key, source, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return image
    }
}

/// ImageIO decoding and the optional full-size cache are serialized. CATiledLayer
/// may draw on several background threads; none of them touches an NSImage.
final class LargeImageSource: @unchecked Sendable {
    static let previewEdge = 2048
    let url: URL
    let pixelSize: CGSize
    let preview: CGImage
    let hasAlpha: Bool
    private let orientation: Int32
    private let lock = NSLock()
    private var detailImage: CGImage?

    static func needsPreview(source: CGImageSource, properties: [CFString: Any]) -> Bool {
        guard CGImageSourceGetCount(source) == 1,
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return false }
        return max(width, height) > 8192 || Double(width) * Double(height) > 64_000_000
    }

    init?(url: URL, source: CGImageSource, properties: [CFString: Any]) {
        guard CGImageSourceGetCount(source) == 1,
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0,
              max(width, height) > 8192 || Double(width) * Double(height) > 64_000_000,
              let preview = Self.thumbnail(source, edge: Self.previewEdge) else { return nil }
        self.url = url
        orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
        pixelSize = orientation >= 5 && orientation <= 8
            ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        self.preview = preview
        hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool ?? false
    }

    private static func thumbnail(_ source: CGImageSource, edge: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    func thumbnail(edge: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return Self.thumbnail(source, edge: max(1, edge))
    }

    private func originalLocked() -> CGImage? {
        if let detailImage { return detailImage }
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(source, 0,
                [kCGImageSourceShouldCache: true] as CFDictionary) else { return nil }
        detailImage = image
        return image
    }

    func discardDetailCache() {
        // A tile can be decoding. Never make a reset/page turn wait for its lock.
        DispatchQueue.global(qos: .utility).async { [self] in
            lock.withLock { detailImage = nil }
        }
    }

    /// A lazy CGImage; decoding is deferred until pixels are actually consumed.
    /// Rotated sources need an upright bitmap for consumers without orientation.
    func fullResolutionImage() -> CGImage? {
        lock.withLock {
            guard let image = originalLocked() else { return nil }
            if orientation == 1 { return image }
            guard let dimensions = try? ImageRenderBudget.dimensions(for: pixelSize),
                  let context = CGContext(data: nil, width: dimensions.width, height: dimensions.height,
                    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            drawLocked(image, in: context)
            return context.makeImage()
        }
    }

    /// Render only the visible source rectangle into a small tile/output bitmap.
    /// This avoids uploading the full-size image as a single GPU texture.
    @discardableResult
    func draw(in context: CGContext, isCurrent: @Sendable () -> Bool = { true }) -> Bool {
        lock.withLock {
            guard isCurrent(), let image = originalLocked() else { return false }
            drawLocked(image, in: context)
            return true
        }
    }

    private func drawLocked(_ image: CGImage, in context: CGContext) {
        let transform = CIImage(cgImage: image).orientationTransform(forExifOrientation: orientation)
        let sourceBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        // Neighbor pixels prevent interpolation seams at fractional tile scales.
        let visible = context.boundingBoxOfClipPath.applying(transform.inverted())
            .insetBy(dx: -2, dy: -2).integral.intersection(sourceBounds)
        guard !visible.isEmpty,
              let crop = image.cropping(to: CGRect(x: visible.minX, y: CGFloat(image.height) - visible.maxY,
                width: visible.width, height: visible.height)) else { return }
        context.saveGState()
        context.concatenate(transform)
        context.interpolationQuality = .high
        context.draw(crop, in: visible)
        context.restoreGState()
    }
}

private final class LargeImageTileActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var active = false
    var isActive: Bool {
        get { lock.withLock { active } }
        set { lock.withLock { active = newValue } }
    }
}

/// Tiles keep native-pixel zoom sharp without a giant layer contents bitmap.
/// A preview stays beneath the tiles while their asynchronous draws complete.
final class LargeImageTileLayer: CATiledLayer {
    let source: LargeImageSource?
    private let activity: LargeImageTileActivity

    init(source: LargeImageSource) {
        self.source = source
        activity = LargeImageTileActivity()
        super.init()
        isHidden = true
        zPosition = 1 // Above NSImageView's private preview sublayer.
        tileSize = CGSize(width: 512, height: 512)
        needsDisplayOnBoundsChange = true
        levelsOfDetail = 8
        levelsOfDetailBias = 0
    }

    override init(layer: Any) {
        source = (layer as? LargeImageTileLayer)?.source
        activity = (layer as? LargeImageTileLayer)?.activity ?? LargeImageTileActivity()
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        source = nil
        activity = LargeImageTileActivity()
        super.init(coder: coder)
    }

    func setActive(_ active: Bool) { activity.isActive = active }

    override class func fadeDuration() -> CFTimeInterval { 0 }

    override func draw(in context: CGContext) {
        guard activity.isActive, let source else { return }
        // Stale low-resolution draws must never start a full decode after reset.
        let scale = hypot(context.ctm.a, context.ctm.c)
        if scale <= CGFloat(source.preview.width) / source.pixelSize.width {
            context.draw(source.preview, in: CGRect(origin: .zero, size: source.pixelSize))
        } else {
            let activity = activity
            source.draw(in: context, isCurrent: { activity.isActive })
        }
    }
}
