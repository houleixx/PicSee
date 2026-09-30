import AppKit
import Testing
@testable import PicSee

@MainActor
@Suite(.serialized)
struct ImageCanvasCursorZoomTests {
    @Test(arguments: [0, 90, 180, 270], [false, true])
    func wheelAndPinchUseEventLocationInNestedCanvas(rotation: Int, pinch: Bool) {
        let (window, view) = canvas(rotation: rotation)
        defer { window.close() }
        let point = CGPoint(x: 280, y: 210)
        let before = geometry(view)
        let pixel = sourcePixel(at: point, geometry: before)
        let event = CursorZoomEvent(point: view.convert(point, to: nil))
        var reportedZoom: CGFloat?
        var reportedPan: CGSize?
        view.onZoomChanged = { reportedZoom = $0 }
        view.onPanChanged = { reportedPan = $0 }
        if pinch { view.magnify(with: event) } else { view.scrollWheel(with: event) }
        let after = sourcePixel(at: point, geometry: geometry(view))
        #expect(abs(pixel.x - after.x) < 0.0001)
        #expect(abs(pixel.y - after.y) < 0.0001)
        #expect(abs(view.zoomScale - before.zoomScale * (pinch ? 1.2 : exp(0.018))) < 0.0001)
        #expect(reportedZoom == view.zoomScale)
        #expect(reportedPan == view.panOffset)
    }

    @Test func toolbarStillUsesViewportCenter() {
        let (window, view) = canvas(rotation: 0)
        defer { window.close() }
        let center = CGPoint(x: 200, y: 150)
        let pixel = sourcePixel(at: center, geometry: geometry(view))
        view.applyToolbarZoom(request: ImageZoomRequest(id: 1, multiplier: 1.25))
        let after = sourcePixel(at: center, geometry: geometry(view))
        #expect(abs(pixel.x - after.x) < 0.0001)
        #expect(abs(pixel.y - after.y) < 0.0001)
    }

    @Test func trackpadScrollingStillPansWithoutZooming() {
        let (window, view) = canvas(rotation: 0)
        defer { window.close() }
        let zoom = view.zoomScale
        let event = CursorZoomEvent(point: view.convert(CGPoint(x: 280, y: 210), to: nil), trackpad: true)
        view.scrollWheel(with: event)
        #expect(view.zoomScale == zoom)
        #expect(view.panOffset == CGSize(width: 28, height: -25))
    }

    private func canvas(rotation: Int) -> (NSWindow, CanvasNSView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = CanvasNSView(frame: CGRect(x: 40, y: 35, width: 400, height: 300), backend: .vision)
        view.motionPreference = { true }
        view.image = NSImage(size: CGSize(width: 1000, height: 800))
        view.zoomScale = 3
        view.panOffset = CGSize(width: 20, height: -15)
        view.rotationDegrees = rotation
        window.contentView?.addSubview(view)
        view.layoutSubtreeIfNeeded()
        return (window, view)
    }

    private func geometry(_ view: CanvasNSView) -> ImageDisplayGeometry {
        ImageDisplayGeometry(imageSize: view.image?.size ?? .zero, viewportSize: view.bounds.size,
            zoomScale: view.zoomScale, panOffset: view.panOffset, rotationDegrees: view.rotationDegrees)
    }
}

private final class CursorZoomEvent: NSEvent {
    let point: CGPoint
    let trackpad: Bool
    init(point: CGPoint, trackpad: Bool = false) {
        self.point = point
        self.trackpad = trackpad
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override var locationInWindow: CGPoint { point }
    override var magnification: CGFloat { 0.2 }
    override var scrollingDeltaY: CGFloat { trackpad ? 10 : 1 }
    override var scrollingDeltaX: CGFloat { trackpad ? 8 : 0 }
    override var hasPreciseScrollingDeltas: Bool { trackpad }
    override var phase: NSEvent.Phase { trackpad ? .changed : [] }
    override var momentumPhase: NSEvent.Phase { [] }
}
