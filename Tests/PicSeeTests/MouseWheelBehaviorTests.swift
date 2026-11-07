import AppKit
import Combine
import XCTest
@testable import PicSee

@MainActor
final class MouseWheelBehaviorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        _ = NSApplication.shared
        suiteName = "PicSee.MouseWheelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testDefaultAndUnknownPreferenceKeepWheelZoom() {
        XCTAssertEqual(MouseWheelPreference.behavior(in: defaults), .zoom)
        defaults.set("unknown", forKey: MouseWheelPreference.defaultsKey)
        let canvas = makeCanvas()
        XCTAssertEqual(ViewerPreferences(defaults: defaults).snapshot.mouseWheelBehavior, .zoom)
        canvas.scrollWheel(with: WheelEvent(y: 1))
        XCTAssertGreaterThan(canvas.zoomScale, 3)
    }

    func testVerticalScrollKeepsScaleAndHorizontalPositionAndStopsAtEdges() {
        MouseWheelPreference.setBehavior(.scroll, in: defaults)
        let canvas = makeCanvas()
        canvas.panOffset.width = 20
        for rotation in [0, 90, 180, 270] {
            canvas.rotationDegrees = rotation
            canvas.panOffset.height = 0
            let geometry = canvas.debugGeometry
            let limit = (geometry.displaySize.height - geometry.viewportSize.height) / 2
            canvas.scrollWheel(with: WheelEvent(y: 3, x: 8))
            XCTAssertEqual(canvas.zoomScale, 3)
            XCTAssertEqual(canvas.panOffset, CGSize(width: 20, height: -48))
            canvas.scrollWheel(with: WheelEvent(y: 10_000))
            XCTAssertEqual(canvas.panOffset.height, -limit, accuracy: 0.001)
            canvas.scrollWheel(with: WheelEvent(y: -10_000))
            XCTAssertEqual(canvas.panOffset.height, limit, accuracy: 0.001)
        }
    }

    func testFittedOrOnlyHorizontallyOverflowingImagesDoNotScrollOrZoom() {
        MouseWheelPreference.setBehavior(.scroll, in: defaults)
        let canvas = makeCanvas()
        for zoom: CGFloat in [1, 0.5] {
            canvas.zoomScale = zoom
            canvas.scrollWheel(with: WheelEvent(y: 3))
            XCTAssertEqual(canvas.panOffset, .zero)
            XCTAssertEqual(canvas.zoomScale, zoom)
        }
        canvas.image = NSImage(size: CGSize(width: 1000, height: 100))
        canvas.zoomScale = 2
        XCTAssertGreaterThan(canvas.debugGeometry.displaySize.width, canvas.bounds.width)
        canvas.scrollWheel(with: WheelEvent(y: 3))
        XCTAssertEqual(canvas.panOffset, .zero)
        XCTAssertEqual(canvas.zoomScale, 2)
    }

    func testPreciseMouseAndTrackpadRemainDistinct() {
        MouseWheelPreference.setBehavior(.scroll, in: defaults)
        let canvas = makeCanvas()
        canvas.scrollWheel(with: WheelEvent(y: 3, precise: true))
        XCTAssertEqual(canvas.panOffset.height, -3)
        canvas.scrollWheel(with: WheelEvent(y: 3, x: 2, precise: true, phase: .changed))
        XCTAssertEqual(canvas.panOffset, CGSize(width: 2, height: -6))
        canvas.scrollWheel(with: WheelEvent(y: 3, x: 2, precise: true, momentum: .changed))
        XCTAssertEqual(canvas.panOffset, CGSize(width: 4, height: -9))
        XCTAssertEqual(canvas.zoomScale, 3)
        canvas.magnify(with: WheelEvent(y: 0))
        XCTAssertGreaterThan(canvas.zoomScale, 3)

        canvas.zoomScale = 1
        canvas.panOffset = .zero
        canvas.scrollWheel(with: WheelEvent(y: 3, precise: true, phase: .changed))
        XCTAssertGreaterThan(canvas.zoomScale, 1, "Keep the existing fitted-trackpad behavior")
    }

    func testSettingsUpdateExistingCanvasAndPersist() async {
        let canvas = makeCanvas()
        let preferences = ViewerPreferences(defaults: defaults)
        let mirror = ViewerPreferences(defaults: defaults)
        let received = expectation(description: "Existing preferences receive wheel behavior")
        let observation = mirror.$snapshot.dropFirst().filter { $0.mouseWheelBehavior == .scroll }.first()
            .sink { _ in received.fulfill() }
        defer { observation.cancel() }
        preferences.setMouseWheelBehavior(.scroll)
        await fulfillment(of: [received], timeout: 2)
        canvas.scrollWheel(with: WheelEvent(y: 3))
        XCTAssertEqual(canvas.zoomScale, 3)
        XCTAssertEqual(canvas.panOffset.height, -48)
        XCTAssertEqual(ViewerPreferences(defaults: defaults).snapshot.mouseWheelBehavior, .scroll)

        preferences.setMouseWheelBehavior(.zoom)
        let reset = expectation(description: "Existing preferences return to zoom")
        let resetObservation = mirror.$snapshot.dropFirst().filter { $0.mouseWheelBehavior == .zoom }.first()
            .sink { _ in reset.fulfill() }
        defer { resetObservation.cancel() }
        await fulfillment(of: [reset], timeout: 2)
        canvas.scrollWheel(with: WheelEvent(y: 1))
        XCTAssertGreaterThan(canvas.zoomScale, 3)
    }

    private func makeCanvas() -> CanvasNSView {
        let canvas = CanvasNSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                                  backend: .vision, defaults: defaults)
        canvas.motionPreference = { true }
        canvas.image = NSImage(size: CGSize(width: 1000, height: 800))
        canvas.zoomScale = 3
        return canvas
    }
}

private final class WheelEvent: NSEvent {
    private let y: CGFloat
    private let x: CGFloat
    private let precise: Bool
    private let scrollPhase: NSEvent.Phase
    private let momentum: NSEvent.Phase
    init(y: CGFloat, x: CGFloat = 0, precise: Bool = false,
         phase: NSEvent.Phase = [], momentum: NSEvent.Phase = []) {
        self.y = y
        self.x = x
        self.precise = precise
        self.scrollPhase = phase
        self.momentum = momentum
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override var scrollingDeltaY: CGFloat { y }
    override var scrollingDeltaX: CGFloat { x }
    override var hasPreciseScrollingDeltas: Bool { precise }
    override var phase: NSEvent.Phase { scrollPhase }
    override var momentumPhase: NSEvent.Phase { momentum }
    override var magnification: CGFloat { 0.2 }
}
