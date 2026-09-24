import AppKit
import XCTest
@testable import PicSee

@MainActor
final class SettingsMenuRoutingTests: XCTestCase {
    private struct ReadOnlyDefaultAppHandler: DefaultImageAppHandling {
        func isDefaultViewer(for format: DefaultImageFormat) -> Bool { false }
        func setDefaultViewer(for format: DefaultImageFormat) throws {
            XCTFail("Menu navigation must not change file associations")
        }
    }

    func testContextMenuEntriesSelectTheirPageAndReuseOneWindow() throws {
        _ = NSApplication.shared
        let suite = "PicSee.SettingsMenuRoutingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = SettingsWindowController(
            preferences: ViewerPreferences(defaults: defaults), updateChecker: nil,
            defaultAppHandler: ReadOnlyDefaultAppHandler(), captureFixedWindowFrame: {}
        )
        let window = try XCTUnwrap(controller.window)
        let delegate = AppDelegate(settingsWindowController: controller)
        let previousDelegate = NSApp.delegate
        NSApp.delegate = delegate
        defer {
            window.orderOut(nil)
            NSApp.delegate = previousDelegate
        }
        let visibleBefore = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        let expectedWindows = visibleBefore.union([ObjectIdentifier(window)])
        let view = CanvasNSView(frame: .zero, backend: .vision)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0
        ))
        let menu = try XCTUnwrap(view.menu(for: event))
        let entries: [(String, SettingsPage)] = [
            ("设置…", .browsing),
            ("默认打开方式…", .defaultApps),
            ("关于 PicSee", .about),
            ("设置…", .browsing),
            ("关于 PicSee", .about),
            ("默认打开方式…", .defaultApps)
        ]
        controller.navigation.page = .about
        for (index, entry) in entries.enumerated() {
            // Exercise both an already-visible window and a reopened window.
            if index >= 3 { window.orderOut(nil) }
            let item = try XCTUnwrap(menu.items.first { $0.title == entry.0 })
            let action = try XCTUnwrap(item.action)
            XCTAssertTrue(item.target === delegate)
            XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item))
            XCTAssertEqual(controller.navigation.page, entry.1)
            XCTAssertTrue(window.isVisible)
            XCTAssertEqual(Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init)), expectedWindows)
        }
    }
}
