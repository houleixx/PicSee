import AppKit
import XCTest
@testable import PicSee

@MainActor
final class ImageCanvasPixelScaleTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "PicSee.PixelScaleTests.\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testFullScreenModesRespectBackingPixelsAndAutomaticLimits() throws {
        for scale in [CGFloat(1), 2] {
            for mode in FullScreenSmallImageMode.allCases {
                FullScreenSmallImagePreference.setMode(mode, in: defaults)
                for limit in FullScreenSmallImagePreference.scaleOptions {
                    FullScreenSmallImagePreference.setMaximumScale(limit, in: defaults)
                    let (window, view) = canvas(scale: scale)
                    defer { window.close() }
                    view.image = try image(pixels: CGSize(width: 400, height: 300), dpi: 350)
                    view.debugCancelTextRecognition()
                    view.layoutSubtreeIfNeeded()
                    XCTAssertEqual(view.debugGeometry.pixelDisplayScale, 1, accuracy: 0.001,
                                   "Ordinary windows must keep small images at 100%")
                    window.toggleFullScreen(nil)
                    view.layoutSubtreeIfNeeded()
                    let fit = 1080 * scale / 300
                    let expected: CGFloat = switch mode {
                    case .original: 1
                    case .fitScreen: fit
                    case .smart: min(CGFloat(limit), fit)
                    }
                    XCTAssertEqual(view.debugGeometry.pixelDisplayScale, expected, accuracy: 0.001)
                    XCTAssertLessThanOrEqual(view.debugGeometry.imageRect.width, view.bounds.width)
                    XCTAssertLessThanOrEqual(view.debugGeometry.imageRect.height, view.bounds.height)
                    window.toggleFullScreen(nil)
                    view.layoutSubtreeIfNeeded()
                    XCTAssertEqual(view.debugGeometry.pixelDisplayScale, 1, accuracy: 0.001)
                }
            }
        }
    }

    func testAutomaticEnlargementDoesNotBlockSecondDoubleClickFromExitingFullScreen() throws {
        for mode in FullScreenSmallImageMode.allCases {
            FullScreenSmallImagePreference.setMode(mode, in: defaults)
            let (window, view) = canvas(scale: 2)
            defer { window.close() }
            view.image = try image(pixels: CGSize(width: 400, height: 300), dpi: 180)
            view.debugCancelTextRecognition()
            view.layoutSubtreeIfNeeded()
            let event = try doubleClick(in: view)
            view.mouseDown(with: event)
            view.layoutSubtreeIfNeeded()
            XCTAssertTrue(window.testIsFullScreen)
            XCTAssertEqual(view.zoomScale, 1)
            view.mouseDown(with: event)
            XCTAssertFalse(window.testIsFullScreen)
            XCTAssertEqual(window.fullScreenToggleCount, 2)
        }
    }

    func testDoubleClickAfterManualZoomRestoresSelectedModeBeforeExitingFullScreen() throws {
        for mode in FullScreenSmallImageMode.allCases {
            FullScreenSmallImagePreference.setMode(mode, in: defaults)
            let (window, view) = canvas(scale: 2)
            defer { window.close() }
            view.image = try image(pixels: CGSize(width: 400, height: 300), dpi: 350)
            view.debugCancelTextRecognition()
            window.toggleFullScreen(nil)
            view.layoutSubtreeIfNeeded()
            let automaticScale = view.debugGeometry.pixelDisplayScale
            view.zoomScale = 2
            view.panOffset = CGSize(width: 15, height: 20)
            view.layoutSubtreeIfNeeded()
            let event = try doubleClick(in: view)
            view.mouseDown(with: event)
            view.layoutSubtreeIfNeeded()
            XCTAssertTrue(window.testIsFullScreen)
            XCTAssertEqual(window.fullScreenToggleCount, 1)
            XCTAssertEqual(view.zoomScale, 1)
            XCTAssertEqual(view.panOffset, .zero)
            XCTAssertEqual(view.debugGeometry.pixelDisplayScale, automaticScale, accuracy: 0.001)
            view.mouseDown(with: event)
            XCTAssertFalse(window.testIsFullScreen)
            XCTAssertEqual(window.fullScreenToggleCount, 2)
        }
    }

    func testTinyImageCanReturnToActualPixelsAndZoomSmoothlyFromThere() throws {
        FullScreenSmallImagePreference.setMode(.fitScreen, in: defaults)
        let (window, view) = canvas(scale: 2)
        defer { window.close() }
        view.image = try image(pixels: CGSize(width: 16, height: 16), dpi: 350)
        view.debugCancelTextRecognition()
        window.toggleFullScreen(nil)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.debugGeometry.pixelDisplayScale, 135, accuracy: 0.001)
        view.applyToolbarZoom(request: ImageZoomRequest(id: 1, multiplier: 1 / view.debugGeometry.pixelDisplayScale))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.debugGeometry.pixelDisplayScale, 1, accuracy: 0.001)
        XCTAssertEqual(view.debugGeometry.imageRect.width * window.backingScaleFactor, 16, accuracy: 0.001)
        view.applyToolbarZoom(request: ImageZoomRequest(id: 2, multiplier: 1.25))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.debugGeometry.pixelDisplayScale, 1.25, accuracy: 0.001)
    }

    func testChangingPreferencesRefreshesExistingFullScreenCanvasAndPersists() async throws {
        let (window, view) = canvas(scale: 2)
        defer { window.close() }
        view.image = try image(pixels: CGSize(width: 400, height: 300), dpi: 350)
        view.debugCancelTextRecognition()
        window.toggleFullScreen(nil)
        view.layoutSubtreeIfNeeded()
        let preferences = ViewerPreferences(defaults: defaults)
        preferences.setFullScreenSmallImageMode(.smart)
        preferences.setMaximumSmallImageScale(3)
        try await Task.sleep(for: .milliseconds(20))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.debugGeometry.pixelDisplayScale, 3, accuracy: 0.001)
        let nextLaunch = ViewerPreferences(defaults: defaults)
        XCTAssertEqual(nextLaunch.snapshot.fullScreenSmallImageMode, .smart)
        XCTAssertEqual(nextLaunch.snapshot.maximumSmallImageScale, 3)
    }

    private func doubleClick(in view: NSView) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: view.window?.windowNumber ?? 0,
            context: nil, eventNumber: 1, clickCount: 2, pressure: 1))
    }

    func testLargeHighDPIImagesFitFullScreenOnStandardAndRetinaDisplays() throws {
        for scale in [CGFloat(1), 2] {
            for size in [CGSize(width: 5184, height: 3888), CGSize(width: 6000, height: 4000)] {
                for dpi in [CGFloat(72), 180, 350] {
                    try autoreleasepool {
                        let (window, view) = canvas(scale: scale)
                        defer { window.close() }
                        view.image = try image(pixels: size, dpi: dpi)
                        view.debugCancelTextRecognition()
                        view.layoutSubtreeIfNeeded()
                        let geometry = view.debugGeometry
                        XCTAssertEqual(geometry.imageRect.height, 1080, accuracy: 0.001,
                                       "DPI \(dpi), backing \(scale), pixels \(size)")
                        XCTAssertEqual(geometry.imageRect.width, 1080 * size.width / size.height, accuracy: 0.001)
                    }
                }
            }
        }
    }

    func testSmallImagesUseOneSourcePixelPerBackingPixel() throws {
        for scale in [CGFloat(1), 2] {
            let (window, view) = canvas(scale: scale)
            defer { window.close() }
            view.image = try image(pixels: CGSize(width: 400, height: 300), dpi: 350)
            view.debugCancelTextRecognition()
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.debugGeometry.imageRect.width * scale, 400, accuracy: 0.001)
            XCTAssertEqual(view.debugGeometry.imageRect.height * scale, 300, accuracy: 0.001)
        }
    }

    func testActualSizeReportsOneBackingPixelPerSourcePixel() async throws {
        for scale in [CGFloat(1), 2] {
            let (window, view) = canvas(scale: scale)
            defer { window.close() }
            view.image = try image(pixels: CGSize(width: 6000, height: 4000), dpi: 180)
            view.debugCancelTextRecognition()
            var reported: CGFloat?
            view.onDisplayScaleChanged = { reported = $0 }
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
            let fit = 1080 * scale / 4000
            XCTAssertEqual(try XCTUnwrap(reported), fit, accuracy: 0.001)
            view.debugApplyToolbarZoom(multiplier: 1 / fit)
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
            XCTAssertEqual(try XCTUnwrap(reported), 1, accuracy: 0.001)
            XCTAssertEqual(view.debugGeometry.imageRect.width * scale, 6000, accuracy: 0.001)
            XCTAssertEqual(view.debugGeometry.imageRect.height * scale, 4000, accuracy: 0.001)
        }
    }

    func testMovingBetweenDisplaysUpdatesGeometryAndReportedPercentage() async throws {
        let (window, view) = canvas(scale: 2)
        defer { window.close() }
        view.image = try image(pixels: CGSize(width: 400, height: 300), dpi: 350)
        view.debugCancelTextRecognition()
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.debugGeometry.imageRect.width, 200, accuracy: 0.001)
        window.testScale = 1
        view.viewDidChangeBackingProperties()
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.debugGeometry.imageRect.width, 400, accuracy: 0.001)
        view.image = try image(pixels: CGSize(width: 6000, height: 4000), dpi: 180)
        view.debugCancelTextRecognition()
        var reported: CGFloat?
        view.onDisplayScaleChanged = { reported = $0 }
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(try XCTUnwrap(reported), 0.27, accuracy: 0.001)
        window.testScale = 2
        view.viewDidChangeBackingProperties()
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(try XCTUnwrap(reported), 0.54, accuracy: 0.001)
        XCTAssertEqual(view.debugGeometry.imageRect.height, 1080, accuracy: 0.001)
    }

    func testHighDPIImageFitsAfterViewportResizeAndRotation() throws {
        let (window, view) = canvas(scale: 2)
        defer { window.close() }
        view.image = try image(pixels: CGSize(width: 5184, height: 3888), dpi: 350)
        view.debugCancelTextRecognition()
        view.frame.size = CGSize(width: 800, height: 600)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.debugGeometry.imageRect.size, CGSize(width: 800, height: 600))
        view.rotationDegrees = 90
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.debugGeometry.imageRect.width, 450, accuracy: 0.001)
        XCTAssertEqual(view.debugGeometry.imageRect.height, 600, accuracy: 0.001)
    }

    private func canvas(scale: CGFloat) -> (PixelScaleWindow, CanvasNSView) {
        _ = NSApplication.shared
        let window = PixelScaleWindow(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        window.testScale = scale
        window.isReleasedWhenClosed = false
        let view = CanvasNSView(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), backend: .vision, defaults: defaults)
        view.motionPreference = { true }
        window.contentView = view
        return (window, view)
    }

    private func image(pixels: CGSize, dpi: CGFloat) throws -> NSImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height), bitsPerSample: 8,
            samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let logical = CGSize(width: pixels.width * 72 / dpi, height: pixels.height * 72 / dpi)
        bitmap.size = logical
        let result = NSImage(size: logical)
        result.addRepresentation(bitmap)
        return result
    }
}

@MainActor
private final class PixelScaleWindow: NSWindow {
    var testScale: CGFloat = 1
    var testIsFullScreen = false
    var fullScreenToggleCount = 0
    override var backingScaleFactor: CGFloat { testScale }
    override var styleMask: NSWindow.StyleMask {
        get { testIsFullScreen ? super.styleMask.union(.fullScreen) : super.styleMask }
        set { super.styleMask = newValue }
    }
    override func toggleFullScreen(_ sender: Any?) {
        testIsFullScreen.toggle()
        fullScreenToggleCount += 1
        NotificationCenter.default.post(name: testIsFullScreen ? NSWindow.didEnterFullScreenNotification
                                        : NSWindow.didExitFullScreenNotification, object: self)
    }
}
