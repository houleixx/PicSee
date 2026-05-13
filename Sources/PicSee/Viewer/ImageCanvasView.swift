import AppKit
import SwiftUI

struct ImageCanvasView: NSViewRepresentable {
    let image: NSImage
    @Binding var zoomScale: CGFloat
    @Binding var panOffset: CGSize
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onReset: () -> Void

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        view.image = image
        view.onPrevious = onPrevious
        view.onNext = onNext
        view.onReset = onReset
        view.onZoomChanged = { zoomScale = $0 }
        view.onPanChanged = { panOffset = $0 }
        return view
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.image = image
        nsView.zoomScale = zoomScale
        nsView.panOffset = panOffset
        nsView.onPrevious = onPrevious
        nsView.onNext = onNext
        nsView.onReset = onReset
        nsView.needsDisplay = true
    }
}

final class CanvasNSView: NSView {
    var image: NSImage? {
        didSet {
            if oldValue !== image {
                zoomScale = 1
                panOffset = .zero
            }
            needsDisplay = true
        }
    }

    var zoomScale: CGFloat = 1 {
        didSet { needsDisplay = true }
    }

    var panOffset: CGSize = .zero {
        didSet { needsDisplay = true }
    }

    var onZoomChanged: ((CGFloat) -> Void)?
    var onPanChanged: ((CGSize) -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onReset: (() -> Void)?
    private var dragStartPoint: NSPoint?
    private var dragStartOffset: CGSize = .zero

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()

        guard let image, image.size.width > 0, image.size.height > 0 else { return }

        let geometry = ImageDisplayGeometry(
            imageSize: image.size,
            viewportSize: bounds.size,
            zoomScale: zoomScale,
            panOffset: panOffset
        )
        let rect = NSRect(origin: geometry.imageRect.origin, size: geometry.imageRect.size)

        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [
            .interpolation: NSImageInterpolation.high.rawValue
        ])
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY == 0 ? -event.scrollingDeltaX : event.scrollingDeltaY
        guard delta != 0 else { return }

        let multiplier: CGFloat = delta > 0 ? 1.08 : 0.92
        let nextZoom = min(20, max(1, zoomScale * multiplier))
        zoomScale = nextZoom
        onZoomChanged?(nextZoom)

        if nextZoom == 1 {
            panOffset = .zero
            onPanChanged?(.zero)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            zoomScale = 1
            panOffset = .zero
            onZoomChanged?(1)
            onPanChanged?(.zero)
            onReset?()
            return
        }

        if zoomScale > 1 {
            dragStartPoint = convert(event.locationInWindow, from: nil)
            dragStartOffset = panOffset
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard zoomScale > 1 else {
            window?.performDrag(with: event)
            return
        }

        guard let dragStartPoint else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)
        let nextOffset = CGSize(
            width: dragStartOffset.width + currentPoint.x - dragStartPoint.x,
            height: dragStartOffset.height + currentPoint.y - dragStartPoint.y
        )
        let geometry = ImageDisplayGeometry(
            imageSize: image?.size ?? .zero,
            viewportSize: bounds.size,
            zoomScale: zoomScale,
            panOffset: panOffset
        )
        panOffset = geometry.constrainedPan(nextOffset)
        onPanChanged?(panOffset)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartPoint = nil
        super.mouseUp(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch KeyboardNavigation.action(for: event.keyCode) {
        case .previous:
            onPrevious?()
        case .next:
            onNext?()
        case .quit:
            NSApp.terminate(nil)
        case .none:
            super.keyDown(with: event)
        }
    }
}
