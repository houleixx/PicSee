import AppKit
import Testing
@testable import PicSee

@Suite(.serialized)
@MainActor
struct WindowPinningTests {
    private let suite: String
    private let defaults: UserDefaults

    init() throws {
        suite = "PicSee.PinningTests.\(UUID())"
        defaults = try #require(UserDefaults(suiteName: suite))
        _ = NSApplication.shared
    }

    @Test func defaultsOffAndBothEntrypointsPersistAndValidate() async throws {
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ViewerPreferences(defaults: defaults)
        #expect(!preferences.snapshot.alwaysOnTopEnabled)
        let canvas = CanvasNSView(frame: .zero, backend: .vision, defaults: defaults)
        let menu = NSMenu()
        canvas.debugAppendPicSeeContextMenuItems(to: menu)
        canvas.debugAppendPicSeeContextMenuItems(to: menu)
        let item = try #require(menu.items.first { $0.title == "窗口置顶" })
        #expect(menu.items.filter { $0.title == "窗口置顶" }.count == 1)
        #expect(item.state == .off)
        preferences.set(\.alwaysOnTopEnabled, to: true)
        #expect(canvas.validateMenuItem(item))
        #expect(item.state == .on)
        let reopened = try #require(UserDefaults(suiteName: suite))
        #expect(ViewerPreferences(defaults: reopened).snapshot.alwaysOnTopEnabled)
        canvas.toggleAlwaysOnTopForMenu(nil)
        try await settle()
        #expect(!preferences.snapshot.alwaysOnTopEnabled)
        #expect(canvas.validateMenuItem(item))
        #expect(item.state == .off)
    }

    @Test func existingAndNewWindowsSyncWithoutChangingFocusFrameOrSpaces() async throws {
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ViewerPreferences(defaults: defaults)
        let mirror = ViewerPreferences(defaults: defaults)
        let first = window()
        let second = window()
        first.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
        let frame = first.frame
        let behavior = first.collectionBehavior
        let keyWindow = NSApp.keyWindow
        let firstController = WindowPinningController(window: first, preferences: preferences)
        let secondController = WindowPinningController(window: second, preferences: mirror)
        defer { withExtendedLifetime((firstController, secondController)) {} }
        #expect(first.level == .normal)
        preferences.set(\.alwaysOnTopEnabled, to: true)
        try await settle()
        #expect(first.level == .floating)
        #expect(second.level == .floating)
        let third = window()
        let thirdController = WindowPinningController(window: third, preferences: mirror)
        defer { withExtendedLifetime(thirdController) {} }
        #expect(third.level == .floating)
        #expect(first.frame == frame)
        #expect(first.collectionBehavior == behavior)
        #expect(NSApp.keyWindow === keyWindow)
        preferences.set(\.alwaysOnTopEnabled, to: false)
        try await settle()
        #expect(first.level == .normal)
        #expect(second.level == .normal)
        #expect(third.level == .normal)
    }

    @Test func nativeFullScreenSuspendsPinningAndRestoresLatestPreference() {
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ViewerPreferences(defaults: defaults)
        preferences.set(\.alwaysOnTopEnabled, to: true)
        let viewer = window()
        viewer.pinningController = WindowPinningController(window: viewer, preferences: preferences)
        #expect(viewer.level == .floating)
        let frame = viewer.frame
        let mask = viewer.styleMask
        viewer.prepareStyleMaskForNativeFullScreen()
        #expect(viewer.level == .normal)
        preferences.set(\.alwaysOnTopEnabled, to: false)
        preferences.set(\.alwaysOnTopEnabled, to: true)
        #expect(viewer.level == .normal)
        #expect(viewer.completeNativeFullScreenExit(restoring: mask))
        #expect(viewer.level == .floating)
        #expect(viewer.frame == frame)
        viewer.prepareStyleMaskForNativeFullScreen()
        preferences.set(\.alwaysOnTopEnabled, to: false)
        #expect(viewer.completeNativeFullScreenExit(restoring: mask))
        #expect(viewer.level == .normal)
    }

    @Test func failedFullScreenEntryRestoresPinningAndWindowStyle() {
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ViewerPreferences(defaults: defaults)
        preferences.set(\.alwaysOnTopEnabled, to: true)
        let viewer = window()
        viewer.pinningController = WindowPinningController(window: viewer, preferences: preferences)
        let mask = viewer.styleMask
        viewer.prepareStyleMaskForNativeFullScreen()
        #expect(viewer.level == .normal)
        viewer.restoreStyleMaskAfterFailedFullScreenEntry()
        #expect(viewer.level == .floating)
        #expect(viewer.styleMask == mask)
    }

    @Test func settingsAndSheetsStayAbovePinnedViewersAndRestore() async throws {
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ViewerPreferences(defaults: defaults)
        preferences.set(\.alwaysOnTopEnabled, to: true)
        let viewer = window()
        let settings = SettingsWindowController(preferences: preferences, updateChecker: nil,
            defaultAppHandler: ReadOnlyDefaultAppHandler(), captureFixedWindowFrame: {})
        let settingsWindow = try #require(settings.window)
        viewer.pinningController = WindowPinningController(window: viewer, preferences: preferences)
        #expect(settingsWindow.level.rawValue > viewer.level.rawValue)
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 150),
            styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        viewer.orderFront(nil)
        defer { viewer.orderOut(nil) }
        viewer.beginSheet(sheet, completionHandler: nil)
        try await settle()
        #expect(sheet.level.rawValue > settingsWindow.level.rawValue)
        viewer.endSheet(sheet)
        sheet.orderOut(nil)
        try await settle()
        preferences.set(\.alwaysOnTopEnabled, to: false)
        #expect(settingsWindow.level == .normal)
        #expect(viewer.level == .normal)
    }

    private func window() -> ViewerWindow {
        let window = ViewerWindow(contentRect: NSRect(x: 10, y: 20, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(100)) }

    private struct ReadOnlyDefaultAppHandler: DefaultImageAppHandling {
        func isDefaultViewer(for format: DefaultImageFormat) -> Bool { false }
        func setDefaultViewer(for format: DefaultImageFormat) throws {
            Issue.record("Opening settings must not change file associations")
        }
    }
}
