import AppKit

@MainActor
enum TransparencyBackground {
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
