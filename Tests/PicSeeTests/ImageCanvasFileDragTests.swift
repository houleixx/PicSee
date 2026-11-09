import AppKit
import XCTest
@testable import PicSee

@MainActor
final class ImageCanvasFileDragTests: XCTestCase {
    private var window: FileDragTestWindow!
    private var canvas: CanvasNSView!
    private var startedURLs: [URL] = []
    private var previewFrames: [CGRect] = []
    private var suiteName: String!
    private var savedWindowPreference: Any?

    override func setUp() async throws {
        suiteName = "PicSee-file-drag-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        savedWindowPreference = UserDefaults.standard.object(forKey: WindowFramePreference.defaultsKey)
        canvas = CanvasNSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), backend: .vision, defaults: defaults)
        canvas.motionPreference = { false }
        canvas.titleBarVisible = false
        canvas.fixedWindowEnabled = false
        canvas.image = NSImage(size: NSSize(width: 800, height: 600))
        canvas.imageURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/ocr-test.png")
        canvas.fileDragController = ImageFileDragController(
            files: ImageDragFileProvider(temporaryResourceRoots: []),
            startSession: { [weak self] _, items, _, _ in
                guard let self, let item = items.first, let url = item.item as? NSURL else { return }
                self.startedURLs.append(url as URL)
                self.previewFrames.append(item.draggingFrame)
            }
        )
        window = FileDragTestWindow(contentRect: CGRect(x: 200, y: 200, width: 400, height: 300),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        canvas.layoutSubtreeIfNeeded()
        startedURLs = []
        previewFrames = []
    }

    override func tearDown() async throws {
        canvas.fileDragController.finish()
        window.orderOut(nil)
        window.contentView = nil
        window = nil
        canvas = nil
        UserDefaults.standard.set(savedWindowPreference, forKey: WindowFramePreference.defaultsKey)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    func testFittedImageClickAndInternalDragDoNotExport() throws {
        try down(200, 150)
        try drag(202, 151)
        try drag(390, 150)
        XCTAssertEqual(canvas.panOffset, .zero)
        XCTAssertTrue(startedURLs.isEmpty)
        try up(390, 150)
        try drag(430, 150)
        XCTAssertTrue(startedURLs.isEmpty, "Mouse-up must disarm export")
    }

    func testZoomedImagePansUntilOutsideWindowThenStartsOnlyOneFileDrag() throws {
        canvas.zoomScale = 2
        try down(200, 150)
        try drag(230, 170)
        XCTAssertEqual(canvas.panOffset, CGSize(width: 30, height: 20))
        XCTAssertTrue(startedURLs.isEmpty)
        try drag(405, 170)
        XCTAssertTrue(startedURLs.isEmpty, "A five-point overshoot must keep panning")
        let offsetAtTakeover = canvas.panOffset
        try drag(430, 170)
        XCTAssertEqual(startedURLs, [canvas.imageURL!])
        XCTAssertEqual(canvas.panOffset, offsetAtTakeover)
        XCTAssertTrue(canvas.fileDragController.isDragging)
        try drag(450, 170)
        XCTAssertEqual(startedURLs.count, 1)
        XCTAssertLessThanOrEqual(previewFrames[0].width, 160)
        XCTAssertLessThanOrEqual(previewFrames[0].height, 160)
    }

    func testFittedImageCanExportWithoutOptionAndCanceledDragCanRepeat() throws {
        let source = try XCTUnwrap(canvas.imageURL)
        let original = try Data(contentsOf: source)
        for _ in 0..<3 {
            try down(200, 150)
            try drag(430, 150)
            canvas.fileDragController.finish()
            XCTAssertFalse(canvas.fileDragController.isDragging)
        }
        XCTAssertEqual(startedURLs, [source, source, source])
        XCTAssertEqual(try Data(contentsOf: source), original)
        canvas.zoomScale = 2
        try down(200, 150)
        try drag(220, 150)
        XCTAssertEqual(canvas.panOffset.width, 20, accuracy: 0.001)
    }

    func testTitlelessTopDragKeepsMovingWindowEvenOutsideBoundary() throws {
        try down(200, 285)
        try drag(430, 330)
        XCTAssertEqual(window.moveCount, 1)
        XCTAssertTrue(startedURLs.isEmpty)
    }

    func testTitlelessBottomRightDragKeepsResizingEvenOutsideBoundary() throws {
        XCTAssertNil(canvas.debugResizeAnchor(at: CGPoint(x: 360, y: 40)),
                     "The old interior resize area must remain available for image interaction")
        XCTAssertNil(canvas.debugResizeAnchor(at: CGPoint(x: 390, y: 21)))
        XCTAssertEqual(canvas.debugResizeAnchor(at: CGPoint(x: 390, y: 10)), .bottomRight)
        let original = window.frame
        try down(390, 10)
        try drag(450, -40)
        XCTAssertEqual(window.frame.width, original.width + 60, accuracy: 0.001)
        XCTAssertEqual(window.frame.height, original.height + 50, accuracy: 0.001)
        XCTAssertTrue(startedURLs.isEmpty)
    }

    func testTitlelessTopLeftDragKeepsResizingEvenOutsideBoundary() throws {
        let original = window.frame
        try down(10, 290)
        try drag(-40, 340)
        XCTAssertEqual(window.frame.width, original.width + 50, accuracy: 0.001)
        XCTAssertEqual(window.frame.height, original.height + 50, accuracy: 0.001)
        XCTAssertTrue(startedURLs.isEmpty)
    }

    func testDragFromBlankAreaCannotExport() throws {
        canvas.image = NSImage(size: NSSize(width: 800, height: 100))
        canvas.layoutSubtreeIfNeeded()
        try down(200, 70)
        try drag(430, 70)
        XCTAssertTrue(startedURLs.isEmpty)
    }

    func testChangingImageOrURLDisarmsPendingExport() throws {
        try down(200, 150)
        canvas.imageURL = URL(fileURLWithPath: "/missing/next.png")
        try drag(430, 150)
        XCTAssertTrue(startedURLs.isEmpty)
        try down(200, 150)
        canvas.image = NSImage(size: NSSize(width: 800, height: 600))
        try drag(430, 150)
        XCTAssertTrue(startedURLs.isEmpty)
    }

    func testFailedExportDoesNotRetryOnEveryMouseEventAndPanningStillWorks() throws {
        canvas.imageURL = nil
        try down(200, 150)
        try drag(430, 150)
        XCTAssertFalse(canvas.fileDragController.isDragging)
        try drag(450, 150)
        XCTAssertTrue(startedURLs.isEmpty)
        canvas.zoomScale = 2
        try down(200, 150)
        try drag(225, 150)
        XCTAssertEqual(canvas.panOffset.width, 25, accuracy: 0.001)
    }

    func testLongPressTakesOverPanAndExportAndRestoresCursorAfterNativeDrag() throws {
        canvas.zoomScale = 2
        try down(200, 150)
        XCTAssertTrue(canvas.debugHasWindowLongPressCandidate)
        canvas.debugFireWindowLongPress(at: CGPoint(x: 202, y: 151))
        XCTAssertTrue(canvas.debugIsLongPressMovingWindow)
        XCTAssertEqual(NSCursor.current, canvas.debugWindowMoveCursor)
        XCTAssertNotEqual(NSCursor.current, .closedHand)
        let dragEvent = try event(.leftMouseDragged, 430, 170)
        XCTAssertNil(canvas.debugHandleWindowLongPressEvent(dragEvent))
        XCTAssertEqual(window.moveCount, 1)
        XCTAssertEqual(canvas.panOffset, .zero)
        XCTAssertTrue(startedURLs.isEmpty)
        XCTAssertTrue(canvas.debugIsLongPressMovingWindow)
        XCTAssertEqual(NSCursor.current, canvas.debugWindowMoveCursor)
        try up(430, 170)
        XCTAssertFalse(canvas.debugIsLongPressMovingWindow)
        XCTAssertNotEqual(NSCursor.current, canvas.debugWindowMoveCursor)
    }

    func testWindowMoveCursorPersistsAfterNativeDragReturnsUntilRelease() throws {
        canvas.zoomScale = 2
        try down(200, 150)
        canvas.debugFireWindowLongPress(at: CGPoint(x: 200, y: 150))
        try drag(220, 150)
        XCTAssertTrue(canvas.debugIsLongPressMovingWindow)
        XCTAssertEqual(NSCursor.current, canvas.debugWindowMoveCursor)
        canvas.cursorUpdate(with: try event(.leftMouseDragged, 220, 150))
        XCTAssertEqual(NSCursor.current, canvas.debugWindowMoveCursor)
        try drag(240, 150)
        XCTAssertEqual(window.moveCount, 1, "Start the native drag only once per press")
        try up(240, 150)
        XCTAssertFalse(canvas.debugIsLongPressMovingWindow)
        XCTAssertNotEqual(NSCursor.current, canvas.debugWindowMoveCursor)
    }

    func testMissingNativeMouseUpRestoresCursorWhenPhysicalButtonIsReleased() throws {
        try down(200, 150)
        canvas.debugFireWindowLongPress(at: CGPoint(x: 200, y: 150))
        try drag(220, 150)
        NSCursor.closedHand.set() // Simulate a cursor update from AppKit during native dragging.
        canvas.debugUpdateWindowMoveCursor(leftButtonDown: true)
        XCTAssertTrue(canvas.debugIsLongPressMovingWindow)
        XCTAssertEqual(NSCursor.current, canvas.debugWindowMoveCursor)
        canvas.debugUpdateWindowMoveCursor(leftButtonDown: false)
        XCTAssertFalse(canvas.debugIsLongPressMovingWindow)
        XCTAssertNotEqual(NSCursor.current, canvas.debugWindowMoveCursor)
        NSCursor.arrow.set()
        canvas.debugUpdateWindowMoveCursor(leftButtonDown: true)
        XCTAssertEqual(NSCursor.current, .arrow, "A completed gesture must not reclaim the cursor")
    }

    func testMonitorPassesQuickDragThrough() throws {
        canvas.zoomScale = 2
        try down(200, 150)
        let dragEvent = try event(.leftMouseDragged, 230, 170)
        XCTAssertTrue(canvas.debugHandleWindowLongPressEvent(dragEvent) === dragEvent)
        XCTAssertFalse(canvas.debugHasWindowLongPressCandidate)
        canvas.mouseDragged(with: dragEvent)
        XCTAssertEqual(canvas.panOffset, CGSize(width: 30, height: 20))
    }

    func testLiveTextDelegatePreservesCandidateAndRejectsSelectionAfterTakeover() throws {
        try down(200, 150)
        let overlay = canvas.debugLiveTextOverlay
        XCTAssertTrue(canvas.overlayView(overlay, shouldBeginAt: CGPoint(x: 200, y: 150),
                                          forAnalysisType: .textSelection))
        XCTAssertTrue(canvas.debugHasWindowLongPressCandidate)
        canvas.debugFireWindowLongPress(at: CGPoint(x: 200, y: 150))
        XCTAssertFalse(canvas.overlayView(overlay, shouldBeginAt: CGPoint(x: 200, y: 150),
                                           forAnalysisType: .textSelection))
        try up(200, 150)
    }

    func testEarlyMovementPermanentlyCancelsLongPressForThisPress() throws {
        canvas.zoomScale = 2
        try down(200, 150)
        try drag(205, 150)
        XCTAssertFalse(canvas.debugHasWindowLongPressCandidate)
        canvas.debugFireWindowLongPress(at: CGPoint(x: 200, y: 150))
        XCTAssertFalse(canvas.debugIsLongPressMovingWindow)
        try drag(230, 170)
        XCTAssertEqual(canvas.panOffset, CGSize(width: 30, height: 20))
        XCTAssertEqual(window.moveCount, 0)
    }

    func testSmallMovementAllowsLongPressButReleaseDisarmsIt() throws {
        try down(200, 150)
        try drag(202, 151)
        XCTAssertTrue(canvas.debugHasWindowLongPressCandidate)
        try up(202, 151)
        canvas.debugFireWindowLongPress(at: CGPoint(x: 202, y: 151))
        XCTAssertFalse(canvas.debugIsLongPressMovingWindow)
    }

    func testEditingControlsAndResizeEdgesDoNotArmLongPress() throws {
        canvas.windowLongPressEnabled = false
        try down(200, 150)
        XCTAssertFalse(canvas.debugHasWindowLongPressCandidate)
        canvas.windowLongPressEnabled = true
        let button = NSButton(frame: CGRect(x: 180, y: 130, width: 40, height: 40))
        canvas.addSubview(button)
        try down(200, 150)
        XCTAssertFalse(canvas.debugHasWindowLongPressCandidate)
        button.removeFromSuperview()
        for point in [CGPoint(x: 200, y: 285), CGPoint(x: 390, y: 10),
                      CGPoint(x: 10, y: 290), CGPoint(x: 1, y: 150)] {
            try down(point.x, point.y)
            XCTAssertFalse(canvas.debugHasWindowLongPressCandidate)
        }
    }

    func testControlInResizeCornerReceivesClicksAndNeighborStillResizes() throws {
        let button = NSButton(frame: CGRect(x: 360, y: 8, width: 32, height: 32))
        canvas.addSubview(button)
        let buttonPoint = CGPoint(x: 388, y: 16)
        XCTAssertTrue(canvas.hitTest(buttonPoint) === button)
        XCTAssertNil(canvas.debugResizeAnchor(at: buttonPoint))
        canvas.cursorUpdate(with: try event(.leftMouseDragged, buttonPoint.x, buttonPoint.y))
        XCTAssertEqual(NSCursor.current, .arrow)
        XCTAssertEqual(canvas.debugResizeAnchor(at: CGPoint(x: 398, y: 2)), .bottomRight)
        XCTAssertTrue(canvas.hitTest(CGPoint(x: 398, y: 2)) === canvas)
        button.isHidden = true
        XCTAssertEqual(canvas.debugResizeAnchor(at: buttonPoint), .bottomRight)
    }

    func testControlPriorityAndResizeUseLocalCoordinatesInOffsetCanvas() throws {
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 500, height: 400))
        window.contentView = host
        host.addSubview(canvas)
        canvas.frame = CGRect(x: 50, y: 40, width: 400, height: 300)
        let button = NSButton(frame: CGRect(x: 372, y: 4, width: 24, height: 24))
        canvas.addSubview(button)
        let point = CGPoint(x: 388, y: 16)
        XCTAssertTrue(canvas.hitTest(canvas.convert(point, to: host)) === button)
        XCTAssertNil(canvas.debugResizeAnchor(at: point))
        let windowPoint = canvas.convert(point, to: nil)
        canvas.cursorUpdate(with: try event(.leftMouseDragged, windowPoint.x, windowPoint.y))
        XCTAssertEqual(NSCursor.current, .arrow)
        let corner = CGPoint(x: 398, y: 2)
        XCTAssertTrue(canvas.hitTest(canvas.convert(corner, to: host)) === canvas)
        XCTAssertEqual(canvas.debugResizeAnchor(at: corner), .bottomRight)
        button.isHidden = true
        XCTAssertEqual(canvas.debugResizeAnchor(at: point), .bottomRight)
    }

    func testDoubleClickDoesNotArmLongPress() throws {
        canvas.zoomScale = 2
        let doubleClick = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: CGPoint(x: 200, y: 150), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1))
        canvas.mouseDown(with: doubleClick)
        XCTAssertFalse(canvas.debugHasWindowLongPressCandidate)
        XCTAssertEqual(canvas.zoomScale, 1)
    }

    func testFocusLossImageChangeAndSheetCancelLongPress() throws {
        try down(200, 150)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertFalse(canvas.debugHasWindowLongPressCandidate)
        try down(200, 150)
        canvas.image = NSImage(size: CGSize(width: 900, height: 700))
        XCTAssertFalse(canvas.debugHasWindowLongPressCandidate)
        try down(200, 150)
        NotificationCenter.default.post(name: NSWindow.willBeginSheetNotification, object: window)
        XCTAssertFalse(canvas.debugHasWindowLongPressCandidate)
    }

    private func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
    }

    private func down(_ x: CGFloat, _ y: CGFloat) throws { canvas.mouseDown(with: try event(.leftMouseDown, x, y)) }
    private func drag(_ x: CGFloat, _ y: CGFloat) throws { canvas.mouseDragged(with: try event(.leftMouseDragged, x, y)) }
    private func up(_ x: CGFloat, _ y: CGFloat) throws { canvas.mouseUp(with: try event(.leftMouseUp, x, y)) }
}

@MainActor
private final class FileDragTestWindow: NSWindow {
    var moveCount = 0
    override func performDrag(with event: NSEvent) { moveCount += 1 }
}
