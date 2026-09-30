import AppKit

enum ImageCloseGesturePreference {
    static let defaultsKey = "PicSee.RightMouseCloseGesture"
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: defaultsKey) }
    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: defaultsKey)
        ViewerPreferenceChange.post(in: defaults)
    }
}

/// Canvas coordinates have Y pointing up. Follow downward and then rightward
/// trends, allowing diagonal strokes and rounded corners without requiring a
/// precise angle. Clicks, horizontal strokes and reversed legs do not close.
struct ImageCloseGesture {
    enum Result: Equatable { case menu, close, cancelled }
    private enum Phase { case down, right, invalid }
    private let start: CGPoint
    private var turn: CGPoint
    private var furthestRight: CGFloat
    private var phase = Phase.down
    private var startedRight = false
    private var rightBaselineY: CGFloat?
    private(set) var hasDragged = false
    private(set) var isReady = false
    private(set) var points: [CGPoint]
    var isInvalid: Bool { phase == .invalid }

    init(start: CGPoint) {
        self.start = start
        turn = start
        furthestRight = start.x
        points = [start]
    }

    mutating func move(to point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite else { cancel(); return }
        let previousPoint = points.last ?? start
        points.append(point)
        if points.count > 512 { points.removeFirst(256) }
        if hypot(point.x - start.x, point.y - start.y) > 8 { hasDragged = true }
        switch phase {
        case .down:
            let down = start.y - point.y
            if down < -12 {
                cancel()
            } else if down >= 10 {
                turn = point
                furthestRight = point.x
                phase = .right
            }
        case .right:
            // The first leg may lean left. Follow it until a rightward trend
            // actually starts, rather than treating its drift as a reversal.
            if !startedRight, point.x < turn.x, point.y <= turn.y + 12 {
                turn.x = point.x
                turn.y = min(turn.y, point.y)
                furthestRight = point.x
                break
            }
            // The first leg can be longer than the minimum recognition distance.
            // Keep its turn point at the bottom until the horizontal leg starts.
            if !startedRight, abs(point.x - turn.x) < 16, point.y <= turn.y {
                // Keep the horizontal origin fixed: otherwise dense mouse
                // events continually reset it and the right leg never starts.
                turn.y = point.y
                furthestRight = max(furthestRight, point.x)
                break
            }
            if point.x - turn.x >= 16 { startedRight = true }
            let horizontalTravel = point.x - turn.x
            // Allow a sloped or rounded rightward stroke. A separate vertical
            // leg with no rightward progress still cancels the gesture.
            let verticalDrift = abs(point.y - (rightBaselineY ?? turn.y))
            let right = point.x - previousPoint.x
            let verticalTolerance: CGFloat = rightBaselineY == nil ? max(48, horizontalTravel * 2) : max(16, right * 2)
            if point.x < furthestRight - 12 || verticalDrift > verticalTolerance {
                cancel()
            } else {
                furthestRight = max(furthestRight, point.x)
                isReady = horizontalTravel >= 16
                if isReady {
                    // Follow rightward progress through a sloped or rounded
                    // stroke; a new vertical/reversed leg keeps the old baseline.
                    if rightBaselineY == nil || right > 0 {
                        rightBaselineY = point.y
                    }
                }
            }
        case .invalid: break
        }
    }

    mutating func cancel() {
        phase = .invalid
        isReady = false
    }

    var result: Result {
        if isInvalid { return .cancelled }
        if isReady { return .close }
        return hasDragged ? .cancelled : .menu
    }
}

/// Decorative only: never intercepts a click, selection or drag.
final class ImageCloseGestureOverlay: NSView {
    var gesture: ImageCloseGesture? { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let gesture, gesture.hasDragged else { return }
        let path = NSBezierPath()
        if let first = gesture.points.first { path.move(to: first) }
        for point in gesture.points.dropFirst() { path.line(to: point) }
        path.lineWidth = 5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.systemBlue.setStroke()
        path.stroke()
    }
}
