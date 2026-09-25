import AppKit

@MainActor
enum TransparencyBackground {
    // Images are immutable while displayed. Weak keys avoid retaining decoded
    // images, and share the one-time check with the minimap and other canvases.
    private static let transparencyCache = NSMapTable<NSImage, NSNumber>(
        keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory
    )

    static func needsCheckerboard(for image: NSImage) -> Bool {
        if let cached = transparencyCache.object(forKey: image) {
            return cached.boolValue
        }
        let result = containsTransparency(image)
        transparencyCache.setObject(NSNumber(value: result), forKey: image)
        return result
    }

    private static func containsTransparency(_ image: NSImage) -> Bool {
        // If AppKit cannot supply a bitmap, preserve the background for content
        // whose opacity is unknown rather than lose transparent details.
        guard let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return true }
        if !bitmap.isMask {
            switch bitmap.alphaInfo {
            case .none, .noneSkipFirst, .noneSkipLast: return false
            default: break
            }
        }
        // Read common decoded formats directly. Converting RGB to an alpha-only
        // context is surprisingly expensive on large images.
        if let result = transparencyInPixelData(bitmap) { return result }
        // Normalize uncommon formats at source resolution, never a thumbnail
        // (which could miss a tiny transparent region).
        guard let context = CGContext(
            data: nil, width: bitmap.width, height: bitmap.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ), let data = context.data else { return true }
        context.setBlendMode(.copy)
        context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        return withExtendedLifetime(context) {
            scanAlpha(data.assumingMemoryBound(to: UInt8.self), width: bitmap.width, height: bitmap.height,
                      bytesPerRow: context.bytesPerRow, bytesPerPixel: 4, alphaOffset: 3)
        }
    }

    private static func transparencyInPixelData(_ bitmap: CGImage) -> Bool? {
        guard !bitmap.isMask, bitmap.bitsPerComponent == 8 else { return nil }
        let bytesPerPixel: Int
        switch (bitmap.colorSpace?.model, bitmap.bitsPerPixel) {
        case (.rgb, 32): bytesPerPixel = 4
        case (.monochrome, 16): bytesPerPixel = 2
        default: return nil
        }
        let alphaFirst = bitmap.alphaInfo == .first || bitmap.alphaInfo == .premultipliedFirst
        let order = bitmap.bitmapInfo.intersection(.byteOrderMask)
        let littleEndian = order == .byteOrder32Little || order == .byteOrder16Little
        let alphaOffset = alphaFirst != littleEndian ? 0 : bytesPerPixel - 1
        guard let data = bitmap.dataProvider?.data,
              bitmap.bytesPerRow >= bitmap.width * bytesPerPixel,
              bitmap.height <= CFDataGetLength(data) / bitmap.bytesPerRow,
              let pixels = CFDataGetBytePtr(data) else { return nil }
        return withExtendedLifetime(data) {
            scanAlpha(pixels, width: bitmap.width, height: bitmap.height,
                      bytesPerRow: bitmap.bytesPerRow, bytesPerPixel: bytesPerPixel, alphaOffset: alphaOffset)
        }
    }

    private static func scanAlpha(_ pixels: UnsafePointer<UInt8>, width: Int, height: Int,
                                  bytesPerRow: Int, bytesPerPixel: Int, alphaOffset: Int) -> Bool {
        for row in 0..<height {
            let start = row * bytesPerRow + alphaOffset
            for column in 0..<width where pixels[start + column * bytesPerPixel] < 255 { return true }
        }
        return false
    }

    static func draw(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let visible = rect.intersection(context.boundingBoxOfClipPath)
        guard !visible.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        context.clip(to: visible)
        // A raster pattern image can leave dark tile seams when AppKit chooses
        // a representation at a fractional scale. Draw opaque, adjoining cells
        // directly instead, with no antialiased tile edges or cached tile size.
        context.setShouldAntialias(false)
        NSColor.white.setFill()
        context.fill(visible)
        NSColor(white: 0.8, alpha: 1).setFill()
        let cellSize: CGFloat = 8
        let firstColumn = Int(floor(visible.minX / cellSize))
        let lastColumn = Int(ceil(visible.maxX / cellSize))
        let firstRow = Int(floor(visible.minY / cellSize))
        let lastRow = Int(ceil(visible.maxY / cellSize))
        for row in firstRow..<lastRow {
            for column in firstColumn..<lastColumn where (row + column).isMultiple(of: 2) {
                context.fill(CGRect(x: CGFloat(column) * cellSize, y: CGFloat(row) * cellSize,
                                    width: cellSize, height: cellSize))
            }
        }
    }
}

/// Only the image-shaped mask moves and scales. The checkerboard backing stays
/// viewport-sized, while NSImageView retains its native source-pixel rendering.
final class TransparencyBackgroundView: NSView {
    let motionMask = CALayer()
    let imageMask = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureMask()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureMask()
    }

    private func configureMask() {
        wantsLayer = true
        layer?.mask = motionMask
        motionMask.addSublayer(imageMask)
        imageMask.backgroundColor = NSColor.black.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func synchronize(imageLayer: CALayer, motionLayer: CALayer? = nil) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        motionMask.anchorPoint = motionLayer?.anchorPoint ?? CGPoint(x: 0.5, y: 0.5)
        motionMask.bounds = motionLayer?.bounds ?? bounds
        motionMask.position = motionLayer?.position ?? CGPoint(x: bounds.midX, y: bounds.midY)
        motionMask.transform = motionLayer?.transform ?? CATransform3DIdentity
        motionMask.opacity = motionLayer?.opacity ?? 1
        imageMask.anchorPoint = imageLayer.anchorPoint
        imageMask.bounds = imageLayer.bounds
        imageMask.position = imageLayer.position
        imageMask.transform = imageLayer.transform
        imageMask.opacity = imageLayer.opacity
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = frame.size != newSize
        super.setFrameSize(newSize)
        if changed { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        TransparencyBackground.draw(in: bounds.intersection(dirtyRect))
    }
}
