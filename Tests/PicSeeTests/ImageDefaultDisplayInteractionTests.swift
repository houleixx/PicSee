import AppKit
import XCTest
@testable import PicSee

@MainActor
final class ImageDefaultDisplayInteractionTests: XCTestCase {
    func testToolbarActualSizeAlsoStartsAtTopAndKeepsItsZoomAnimation() throws {
        let (window, canvas) = fixture()
        defer { window.close() }
        canvas.image = try bitmapImage(width: 100, height: 600)
        canvas.debugCancelTextRecognition()
        canvas.motionPreference = { false }
        canvas.layoutSubtreeIfNeeded()
        canvas.updateTransform(zoom: 1, pan: .zero, rotation: 0, animationID: 1, imageChanged: false,
                               displayMode: .actualSize, defaultDisplayRequestID: 1)
        canvas.layoutSubtreeIfNeeded()
        XCTAssertEqual(canvas.debugGeometry.pixelDisplayScale, 1, accuracy: 0.001)
        XCTAssertEqual(canvas.debugGeometry.imageRect.maxY, canvas.bounds.height, accuracy: 0.001)
        XCTAssertNotNil(canvas.debugMotionLayer?.animation(forKey: "PicSee.ZoomAnimation"))
    }

    func testLongImageWindowSizingFollowsModeButRespectsFixedAndManualWindows() async throws {
        let defaults = UserDefaults.standard
        let keys = [ImageDisplayPreference.defaultsKey, AutomaticWindowSizePreference.defaultsKey,
                    AutomaticWindowResizeAnimationPreference.defaultsKey, "PicSee.FixedWindowFrameEnabled",
                    "PicSee.FixedWindowFrame", WindowFramePreference.defaultsKey,
                    "PicSee.TemporaryDesktopFullScreenRestoreFrame"]
        let originals = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, originals) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
            ViewerPreferences.shared.reload()
        }
        let image = try bitmapImage(width: 1279, height: 6826)
        let bitmap = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("long-window-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        for loadingMode in [ImageLoadingMode.immediate, .background] {
            defaults.set(ImageDisplayMode.actualSize.rawValue, forKey: ImageDisplayPreference.defaultsKey)
            defaults.set(true, forKey: AutomaticWindowSizePreference.defaultsKey)
            defaults.set(false, forKey: AutomaticWindowResizeAnimationPreference.defaultsKey)
            defaults.set(false, forKey: "PicSee.FixedWindowFrameEnabled")
            ViewerPreferences.shared.reload()
            let manager = WindowManager(updateChecker: nil, finderOrderProvider: FilenameFolderOrderProvider(),
                loadingMode: loadingMode, screenGeometryOverride: (NSRect(x: 0, y: 0, width: 1440, height: 900), 2))
            manager.openViewer(for: url, presentsWindow: false)
            let window = try XCTUnwrap(manager.currentWindow)
            defer { window.close() }
            let deadline = Date().addingTimeInterval(3)
            while (manager.currentViewModel?.image == nil || findCanvas(window.contentView) == nil) && Date() < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            try await settle()
            let canvas = try XCTUnwrap(findCanvas(window.contentView))
            canvas.debugCancelTextRecognition()
            // Native windows may round their content dimensions to whole points.
            XCTAssertEqual(window.contentView!.bounds.width, 639.5, accuracy: 1)
            XCTAssertEqual(canvas.debugGeometry.imageRect.maxY, canvas.bounds.height, accuracy: 0.01)
            defaults.set(ImageDisplayMode.fitWidth.rawValue, forKey: ImageDisplayPreference.defaultsKey)
            ViewerPreferences.shared.reload()
            try await settle()
            XCTAssertEqual(window.contentView!.bounds.width, 800, accuracy: 0.01)
            assertWidthAndTop(canvas)
            WindowFramePreference.saveFixedFrame(window.frame)
            defaults.set(true, forKey: "PicSee.FixedWindowFrameEnabled")
            ViewerPreferences.shared.reload()
            let fixedFrame = window.frame
            defaults.set(ImageDisplayMode.actualSize.rawValue, forKey: ImageDisplayPreference.defaultsKey)
            ViewerPreferences.shared.reload()
            try await settle()
            XCTAssertEqual(window.frame, fixedFrame)
            XCTAssertEqual(canvas.debugGeometry.pixelDisplayScale, 1, accuracy: 0.001)
            defaults.set(false, forKey: AutomaticWindowSizePreference.defaultsKey)
            defaults.set(false, forKey: "PicSee.FixedWindowFrameEnabled")
            ViewerPreferences.shared.reload()
            defaults.set(ImageDisplayMode.fitWidth.rawValue, forKey: ImageDisplayPreference.defaultsKey)
            ViewerPreferences.shared.reload()
            try await settle()
            XCTAssertEqual(window.frame, fixedFrame)
            manager.currentViewModel?.rotateRight()
            defaults.set(true, forKey: AutomaticWindowSizePreference.defaultsKey)
            defaults.set(ImageDisplayMode.actualSize.rawValue, forKey: ImageDisplayPreference.defaultsKey)
            ViewerPreferences.shared.reload()
            try await settle()
            XCTAssertEqual(window.contentView!.bounds.width, 1296, accuracy: 0.01)
            XCTAssertEqual(window.contentView!.bounds.height, 639.5, accuracy: 1)
        }
    }

    func testActualSizeStartsTallImagesAtTopButKeepsSmallImagesCentered() throws {
        let suite = "PicSee.ActualSizeTop.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        MouseWheelPreference.setBehavior(.scroll, in: defaults)
        let (window, canvas) = fixture(defaults: defaults)
        defer { window.close() }
        canvas.displayMode = .actualSize
        canvas.setImage(try bitmapImage(width: 100, height: 600), url: URL(fileURLWithPath: "/tmp/tall.png"))
        canvas.debugCancelTextRecognition()
        canvas.layoutSubtreeIfNeeded()
        XCTAssertEqual(canvas.debugGeometry.pixelDisplayScale, 1, accuracy: 0.001)
        XCTAssertEqual(canvas.debugGeometry.imageRect.maxY, canvas.bounds.height, accuracy: 0.001)
        XCTAssertEqual(canvas.debugGeometry.imageRect.midX, canvas.bounds.midX, accuracy: 0.001)
        let top = canvas.panOffset.height
        canvas.scrollWheel(with: DefaultDisplayScrollEvent())
        canvas.layoutSubtreeIfNeeded()
        XCTAssertEqual(canvas.panOffset.height, top + 16, accuracy: 0.001)
        canvas.setImage(try bitmapImage(width: 100, height: 100), url: URL(fileURLWithPath: "/tmp/small.png"))
        canvas.debugCancelTextRecognition()
        canvas.layoutSubtreeIfNeeded()
        XCTAssertEqual(canvas.debugGeometry.imageRect.midX, canvas.bounds.midX, accuracy: 0.001)
        XCTAssertEqual(canvas.debugGeometry.imageRect.midY, canvas.bounds.midY, accuracy: 0.001)
    }

    func testChoosingDefaultDisplayWhileZoomingRemovesTheOldAnimation() throws {
        let (window, canvas) = fixture()
        defer { window.close() }
        canvas.motionPreference = { false }
        canvas.image = try bitmapImage(width: 100, height: 600)
        canvas.debugCancelTextRecognition()
        canvas.layoutSubtreeIfNeeded()
        canvas.applyToolbarZoom(request: ImageZoomRequest(id: 1, multiplier: 1.25))
        XCTAssertNotNil(canvas.debugMotionLayer?.animation(forKey: "PicSee.ZoomAnimation"))
        canvas.updateTransform(zoom: 1, pan: .zero, rotation: 0, animationID: 0, imageChanged: false,
                               displayMode: .fitWidth, defaultDisplayRequestID: 1)
        canvas.layoutSubtreeIfNeeded()
        XCTAssertNil(canvas.debugMotionLayer?.animation(forKey: "PicSee.ZoomAnimation"))
        assertWidthAndTop(canvas)
    }

    func testFitWidthStartsAtTopFollowsResizeAndKeepsUserScroll() throws {
        let suite = "PicSee.DefaultDisplayCanvas.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        MouseWheelPreference.setBehavior(.scroll, in: defaults)
        let (window, canvas) = fixture(defaults: defaults)
        defer { window.close() }
        canvas.displayMode = .fitWidth
        let image = try bitmapImage(width: 100, height: 600)
        canvas.setImage(image, url: URL(fileURLWithPath: "/tmp/first.png"))
        canvas.debugCancelTextRecognition()
        canvas.layoutSubtreeIfNeeded()
        assertWidthAndTop(canvas)
        window.setContentSize(CGSize(width: 600, height: 400))
        canvas.layoutSubtreeIfNeeded()
        assertWidthAndTop(canvas)

        let top = canvas.panOffset.height
        canvas.scrollWheel(with: DefaultDisplayScrollEvent())
        canvas.layoutSubtreeIfNeeded()
        XCTAssertEqual(canvas.zoomScale, 1)
        XCTAssertEqual(canvas.panOffset.height, top + 16, accuracy: 0.001)
        // A cached image can be reused for a new URL; it must still start at the top.
        canvas.setImage(image, url: URL(fileURLWithPath: "/tmp/second.png"))
        canvas.debugCancelTextRecognition()
        canvas.layoutSubtreeIfNeeded()
        assertWidthAndTop(canvas)
    }

    func testTrackpadPansAtWidthFitEvenWithRelativeZoomOne() throws {
        let (window, canvas) = fixture()
        defer { window.close() }
        canvas.displayMode = .fitWidth
        canvas.image = try bitmapImage(width: 100, height: 600)
        canvas.debugCancelTextRecognition()
        canvas.layoutSubtreeIfNeeded()
        let top = canvas.panOffset.height
        canvas.scrollWheel(with: DefaultDisplayScrollEvent(trackpad: true))
        canvas.layoutSubtreeIfNeeded()
        XCTAssertEqual(canvas.zoomScale, 1)
        XCTAssertEqual(canvas.panOffset.height, top + 1, accuracy: 0.001)
    }

    func testLargeImageDefaultsUseDetailTilesAtRelativeZoomOne() throws {
        let image = try bitmapImage(width: 100, height: 10000)
        let bitmap = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("default-display-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        let loaded = try XCTUnwrap(LoadedImage.read(url))
        XCTAssertNotNil(loaded.image.largeImageSource)
        let (window, canvas) = fixture()
        defer { window.close() }
        canvas.image = loaded.image
        canvas.debugCancelTextRecognition()
        func tiles(in root: NSView) -> CALayer? {
            root.layer?.sublayers?.first { $0 is LargeImageTileLayer }
                ?? root.subviews.lazy.compactMap { tiles(in: $0) }.first
        }
        for mode in [ImageDisplayMode.fitWidth, .actualSize] {
            canvas.displayMode = mode
            canvas.layoutSubtreeIfNeeded()
            XCTAssertEqual(canvas.zoomScale, 1)
            XCTAssertFalse(try XCTUnwrap(tiles(in: canvas)).isHidden)
        }
    }

    func testTransparentLargeImageRetainsNavigationTransitionInDefaultModes() throws {
        let image = try bitmapImage(width: 100, height: 10000)
        let bitmap = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("transparent-navigation-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        let loaded = try XCTUnwrap(LoadedImage.read(url))
        XCTAssertTrue(try XCTUnwrap(loaded.image.largeImageSource).hasAlpha)
        for mode in [ImageDisplayMode.fitWidth, .actualSize] {
            let (window, canvas) = fixture()
            defer { window.close() }
            canvas.motionPreference = { false }
            canvas.displayMode = mode
            canvas.setImage(loaded.image, url: url)
            canvas.debugCancelTextRecognition()
            canvas.layoutSubtreeIfNeeded()
            canvas.navigationDirection = 1
            canvas.setImage(try bitmapImage(width: 100, height: 600),
                            url: URL(fileURLWithPath: "/tmp/after-transparent.png"))
            canvas.debugCancelTextRecognition()
            canvas.updateTransform(zoom: 1, pan: .zero, rotation: 0, animationID: 0, imageChanged: true,
                                   displayMode: mode, defaultDisplayRequestID: 1)
            canvas.layoutSubtreeIfNeeded()
            XCTAssertNotNil(canvas.debugOutgoingImage, "\(mode)")
            XCTAssertNotNil(canvas.debugMotionLayer?.animation(forKey: "PicSee.NavigationAnimation"), "\(mode)")
        }
    }

    func testExplicitModesKeepTheirScaleAcrossFullScreenAndScreenDensityChanges() throws {
        let suite = "PicSee.DefaultDisplayFullScreen.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        FullScreenSmallImagePreference.setMode(.fitScreen, in: defaults)
        let (window, canvas) = fixture(defaults: defaults)
        defer { window.close() }
        canvas.image = try bitmapImage(width: 100, height: 600)
        canvas.debugCancelTextRecognition()
        for mode in [ImageDisplayMode.fitWidth, .actualSize] {
            canvas.displayMode = mode
            for scale: CGFloat in [1, 2] {
                window.testScale = scale
                for fullScreen in [false, true] {
                    window.testFullScreen = fullScreen
                    window.setContentSize(fullScreen ? CGSize(width: 800, height: 600) : CGSize(width: 400, height: 300))
                    canvas.needsLayout = true
                    canvas.layoutSubtreeIfNeeded()
                    if mode == .fitWidth { assertWidthAndTop(canvas) }
                    else {
                        XCTAssertEqual(canvas.debugGeometry.pixelDisplayScale, 1, accuracy: 0.001)
                        if canvas.debugGeometry.displaySize.height > canvas.bounds.height {
                            XCTAssertEqual(canvas.debugGeometry.imageRect.maxY, canvas.bounds.height, accuracy: 0.001)
                        }
                    }
                }
            }
        }
    }

    func testDefaultModesWorkWithFixedAndAutomaticWindowsAndTemporaryFit() async throws {
        let defaults = UserDefaults.standard
        let keys = [ImageDisplayPreference.defaultsKey, AutomaticWindowSizePreference.defaultsKey,
                    "PicSee.FixedWindowFrameEnabled", "PicSee.FixedWindowFrame", WindowFramePreference.defaultsKey,
                    "PicSee.TemporaryDesktopFullScreenRestoreFrame"]
        let originals = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, originals) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
            ViewerPreferences.shared.reload()
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("01.png")
        let second = directory.appendingPathComponent("02.png")
        for (url, size) in [(first, CGSize(width: 100, height: 600)), (second, CGSize(width: 4000, height: 1000))] {
            let image = try bitmapImage(width: Int(size.width), height: Int(size.height))
            let bitmap = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        }
        for mode in ImageDisplayMode.allCases {
            for fixed in [false, true] {
                for automatic in [false, true] {
                    defaults.set(mode.rawValue, forKey: ImageDisplayPreference.defaultsKey)
                    defaults.set(fixed, forKey: "PicSee.FixedWindowFrameEnabled")
                    defaults.set(automatic, forKey: AutomaticWindowSizePreference.defaultsKey)
                    WindowFramePreference.saveFixedFrame(NSRect(x: 100, y: 100, width: 900, height: 650))
                    ViewerPreferences.shared.reload()
                    let manager = WindowManager(updateChecker: nil, finderOrderProvider: FilenameFolderOrderProvider(),
                        loadingMode: .immediate, screenGeometryOverride: (NSRect(x: 0, y: 0, width: 1440, height: 900), 2))
                    manager.openViewer(for: first, presentsWindow: false)
                    let window = try XCTUnwrap(manager.currentWindow)
                    let model = try XCTUnwrap(manager.currentViewModel)
                    try await settle()
                    let canvas = try XCTUnwrap(findCanvas(window.contentView))
                    XCTAssertEqual(model.displayMode, mode)
                    assertMode(mode, canvas: canvas)
                    let frame = window.frame
                    canvas.applyToolbarZoom(request: ImageZoomRequest(id: 1, multiplier: 1.25))
                    model.startSlideshow()
                    model.slideshow.pause()
                    try await settle()
                    assertMode(mode, canvas: canvas)
                    model.fitToWindow()
                    try await settle()
                    XCTAssertEqual(canvas.displayMode, .fitWindow)
                    XCTAssertEqual(ImageDisplayPreference.mode(), mode)
                    if mode == .fitWidth {
                        let item = NSMenuItem()
                        item.representedObject = mode.rawValue
                        canvas.selectImageDisplayModeForMenu(item)
                        try await settle()
                        assertMode(mode, canvas: canvas)
                    }
                    model.navigate(to: second)
                    try await settle()
                    assertMode(mode, canvas: canvas)
                    if fixed || !automatic { XCTAssertEqual(window.frame, frame) }
                    else { XCTAssertNotEqual(window.frame.size, frame.size) }
                    window.close()
                }
            }
        }
    }

    private func assertMode(_ mode: ImageDisplayMode, canvas: CanvasNSView,
                            file: StaticString = #filePath, line: UInt = #line) {
        canvas.layoutSubtreeIfNeeded()
        XCTAssertEqual(canvas.displayMode, mode, file: file, line: line)
        switch mode {
        case .fitWidth: assertWidthAndTop(canvas, file: file, line: line)
        case .actualSize: XCTAssertEqual(canvas.debugGeometry.pixelDisplayScale, 1, accuracy: 0.001, file: file, line: line)
        case .fitWindow:
            XCTAssertLessThanOrEqual(canvas.debugGeometry.displaySize.width, canvas.bounds.width + 0.001, file: file, line: line)
            XCTAssertLessThanOrEqual(canvas.debugGeometry.displaySize.height, canvas.bounds.height + 0.001, file: file, line: line)
        }
    }

    private func assertWidthAndTop(_ canvas: CanvasNSView, file: StaticString = #filePath, line: UInt = #line) {
        let geometry = canvas.debugGeometry
        XCTAssertEqual(geometry.imageRect.width, canvas.bounds.width, accuracy: 0.001, file: file, line: line)
        if geometry.canPan {
            XCTAssertEqual(geometry.imageRect.maxY, canvas.bounds.height, accuracy: 0.001, file: file, line: line)
        }
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(350)) }

    private func findCanvas(_ root: NSView?) -> CanvasNSView? {
        guard let root else { return nil }
        return root as? CanvasNSView ?? root.subviews.lazy.compactMap { self.findCanvas($0) }.first
    }

    private func fixture(defaults: UserDefaults = .standard) -> (DefaultDisplayTestWindow, CanvasNSView) {
        _ = NSApplication.shared
        let window = DefaultDisplayTestWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let canvas = CanvasNSView(frame: window.contentView!.bounds, backend: .vision, defaults: defaults)
        canvas.motionPreference = { true }
        window.contentView = canvas
        return (window, canvas)
    }

    private func bitmapImage(width: Int, height: Int) throws -> NSImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = NSImage(size: CGSize(width: width, height: height))
        image.addRepresentation(bitmap)
        return image
    }
}

@MainActor
private final class DefaultDisplayTestWindow: NSWindow {
    var testScale: CGFloat = 1
    var testFullScreen = false
    override var backingScaleFactor: CGFloat { testScale }
    override var styleMask: NSWindow.StyleMask {
        get { testFullScreen ? super.styleMask.union(.fullScreen) : super.styleMask }
        set { super.styleMask = newValue }
    }
}

private final class DefaultDisplayScrollEvent: NSEvent {
    let trackpad: Bool
    init(trackpad: Bool = false) { self.trackpad = trackpad; super.init() }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override var scrollingDeltaY: CGFloat { -1 }
    override var scrollingDeltaX: CGFloat { 0 }
    override var hasPreciseScrollingDeltas: Bool { trackpad }
    override var phase: NSEvent.Phase { trackpad ? .changed : [] }
    override var momentumPhase: NSEvent.Phase { [] }
}
