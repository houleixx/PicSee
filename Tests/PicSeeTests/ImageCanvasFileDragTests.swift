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
