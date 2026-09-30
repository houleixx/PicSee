import AppKit
import Testing
@testable import PicSee

@MainActor
@Suite(.serialized)
struct ImageCloseGestureInteractionTests {
    @Test(arguments: [1, 4, 16, 100])
    func roundedGestureClosesOnReleaseAtDifferentEventDensities(stepSize: Int) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let points: [CGPoint] = [
            CGPoint(x: 100, y: 220), CGPoint(x: 100, y: 200),
            CGPoint(x: 105, y: 184), CGPoint(x: 111, y: 169),
            CGPoint(x: 121, y: 157), CGPoint(x: 135, y: 149),
            CGPoint(x: 153, y: 144), CGPoint(x: 175, y: 141),
            CGPoint(x: 215, y: 141), CGPoint(x: 277, y: 140)
        ]
        _ = fixture.canvas.debugHandleCloseGestureEvent(try fixture.event(.rightMouseDown, points[0]))
        for (previous, point) in zip(points, points.dropFirst()) {
            let steps = max(1, Int(ceil(max(abs(point.x - previous.x), abs(point.y - previous.y)) / CGFloat(stepSize))))
            for step in 1...steps {
                let fraction = CGFloat(step) / CGFloat(steps)
                let location = CGPoint(x: previous.x + (point.x - previous.x) * fraction,
                    y: previous.y + (point.y - previous.y) * fraction)
                _ = fixture.canvas.debugHandleCloseGestureEvent(try fixture.event(.rightMouseDragged, location))
            }
        }
        #expect(fixture.window.closeCount == 0)
        _ = fixture.canvas.debugHandleCloseGestureEvent(try fixture.event(.rightMouseUp, points[points.count - 1]))
        #expect(fixture.window.closeCount == 1)
        #expect(fixture.menuCapture.menus.isEmpty)
    }

    @Test func rightClickOpensMenuOnlyOnRelease() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let down = try fixture.event(.rightMouseDown, CGPoint(x: 100, y: 200))
        #expect(fixture.canvas.debugHandleCloseGestureEvent(down) == nil)
        #expect(fixture.menuCapture.menus.isEmpty)
        #expect(fixture.canvas.debugHandleCloseGestureEvent(try fixture.event(.rightMouseUp, CGPoint(x: 102, y: 198))) == nil)
        #expect(fixture.menuCapture.menus.count == 1)
        #expect(fixture.menuCapture.menuEventType == .rightMouseUp)
        #expect(fixture.window.closeCount == 0)
    }

    @Test func validGestureClosesOnlyItsWindowOnRelease() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        _ = fixture.canvas.debugHandleCloseGestureEvent(try fixture.event(.rightMouseDown, CGPoint(x: 100, y: 200)))
        _ = fixture.canvas.debugHandleCloseGestureEvent(try fixture.event(.rightMouseDragged, CGPoint(x: 100, y: 160)))
        _ = fixture.canvas.debugHandleCloseGestureEvent(try fixture.event(.rightMouseDragged, CGPoint(x: 140, y: 160)))
        #expect(fixture.window.closeCount == 0)
        _ = fixture.canvas.debugHandleCloseGestureEvent(try fixture.event(.rightMouseUp, CGPoint(x: 140, y: 160)))
        #expect(fixture.window.closeCount == 1)
        #expect(fixture.menuCapture.menus.isEmpty)
    }

    @Test func unrecognizedDragNeitherClosesNorOpensMenu() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        _ = fixture.canvas.debugHandleCloseGestureEvent(try fixture.event(.rightMouseDown, CGPoint(x: 100, y: 200)))
        _ = fixture.canvas.debugHandleCloseGestureEvent(try fixture.event(.rightMouseDragged, CGPoint(x: 170, y: 200)))
        _ = fixture.canvas.debugHandleCloseGestureEvent(try fixture.event(.rightMouseUp, CGPoint(x: 170, y: 200)))
        #expect(fixture.window.closeCount == 0)
        #expect(fixture.menuCapture.menus.isEmpty)
    }

    @Test(arguments: ["escape", "focus", "image", "outside", "disable"])
    func interruptionsCancelRecognizedGesture(interruption: String) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        _ = fixture.canvas.debugHandleCloseGestureEvent(try fixture.event(.rightMouseDown, CGPoint(x: 100, y: 200)))
        _ = fixture.canvas.debugHandleCloseGestureEvent(try fixture.event(.rightMouseDragged, CGPoint(x: 100, y: 160)))
        _ = fixture.canvas.debugHandleCloseGestureEvent(try fixture.event(.rightMouseDragged, CGPoint(x: 140, y: 160)))
        switch interruption {
        case "escape":
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: fixture.window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false, keyCode: 53))
            #expect(fixture.canvas.debugHandleCloseGestureEvent(event) == nil)
        case "focus": NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        case "image": fixture.canvas.image = NSImage(size: CGSize(width: 900, height: 700))
        case "outside": _ = fixture.canvas.debugHandleCloseGestureEvent(try fixture.event(.rightMouseDragged, CGPoint(x: 500, y: 160)))
        case "disable":
            fixture.defaults.set(false, forKey: ImageCloseGesturePreference.defaultsKey)
            fixture.canvas.debugReloadGesturePreferences()
        default: break
        }
        _ = fixture.canvas.debugHandleCloseGestureEvent(try fixture.event(.rightMouseUp, CGPoint(x: 140, y: 160)))
        #expect(fixture.window.closeCount == 0)
        #expect(fixture.menuCapture.menus.isEmpty)
    }

    @Test func disabledGestureAndOtherWindowsPassEventsThrough() throws {
        let fixture = try Fixture(enabled: false)
        defer { fixture.close() }
        let event = try fixture.event(.rightMouseDown, CGPoint(x: 100, y: 200))
        #expect(fixture.canvas.debugHandleCloseGestureEvent(event) === event)
        let other = try Fixture()
        defer { other.close() }
        #expect(other.canvas.debugHandleCloseGestureEvent(event) === event)
    }

    @Test func controlsAndModifiedRightClicksKeepNativeBehavior() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let button = NSButton(frame: CGRect(x: 85, y: 185, width: 50, height: 40))
        fixture.window.contentView?.addSubview(button)
        let buttonEvent = try fixture.event(.rightMouseDown, CGPoint(x: 100, y: 200))
        #expect(fixture.canvas.debugHandleCloseGestureEvent(buttonEvent) === buttonEvent)
        let modified = try fixture.event(.rightMouseDown, CGPoint(x: 160, y: 200), modifiers: .option)
        #expect(fixture.canvas.debugHandleCloseGestureEvent(modified) === modified)
    }
}

@MainActor
private struct Fixture {
    let suite = "PicSee-GestureInteraction-\(UUID())"
    let defaults: UserDefaults
    let window: GestureTestWindow
    let canvas: CanvasNSView
    let menuCapture = GestureMenuCapture()
    init(enabled: Bool = true) throws {
        _ = NSApplication.shared
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(enabled, forKey: ImageCloseGesturePreference.defaultsKey)
        window = GestureTestWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        canvas = CanvasNSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), backend: .vision, defaults: defaults)
        canvas.image = NSImage(size: CGSize(width: 800, height: 600))
        let capture = menuCapture
        canvas.debugCloseGestureMenuPresenter = { menu, event, _ in
            capture.menus.append(menu)
            capture.menuEventType = event.type
        }
        window.contentView = canvas
        canvas.layoutSubtreeIfNeeded()
    }
    func event(_ type: NSEvent.EventType, _ point: CGPoint, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }
    func close() {
        window.close()
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor
private final class GestureTestWindow: NSWindow {
    var closeCount = 0
    override func close() { closeCount += 1; super.close() }
}

@MainActor
private final class GestureMenuCapture {
    var menus: [NSMenu] = []
    var menuEventType: NSEvent.EventType?
}
