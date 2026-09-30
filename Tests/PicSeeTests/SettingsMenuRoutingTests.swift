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

    func testContextAndApplicationMenusSelectTheirPageAndReuseOneWindow() throws {
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
        XCTAssertEqual(menu.items.last?.title, L10n.text("关于…"))
        XCTAssertEqual(menu.items.last?.action, #selector(AppDelegate.showAboutSettings(_:)))
        let applicationMenu = try XCTUnwrap(AppMenu.buildMainMenu(appName: "PicSee").items.first?.submenu)
        let entries: [(String, SettingsPage)] = [
            (L10n.text("设置…"), .browsing),
            (L10n.text("关于…"), .about),
            (L10n.text("默认打开方式…"), .defaultApps),
            (L10n.text("关于 %1$@", "PicSee"), .about),
            (L10n.text("设置…"), .browsing),
            (L10n.text("关于…"), .about),
            (L10n.text("关于 %1$@", "PicSee"), .about),
            (L10n.text("默认打开方式…"), .defaultApps)
        ]
        controller.navigation.page = .about
        for (index, entry) in entries.enumerated() {
            // Exercise both an already-visible window and a reopened window.
            if index >= 3 { window.orderOut(nil) }
            let source = entry.1 == .browsing || entry.0 == L10n.text("关于…") ? menu : applicationMenu
            let item = try XCTUnwrap(source.items.first { $0.title == entry.0 })
            if source === applicationMenu { item.target = delegate }
            let action = try XCTUnwrap(item.action)
            XCTAssertTrue(item.target === delegate)
            XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item))
            XCTAssertEqual(controller.navigation.page, entry.1)
            XCTAssertTrue(window.isVisible)
            XCTAssertEqual(Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init)), expectedWindows)
        }
    }
}
