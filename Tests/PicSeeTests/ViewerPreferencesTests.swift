import AppKit
import Combine
import XCTest
@testable import PicSee

@MainActor
final class ViewerPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "PicSee.ViewerPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testSettingsChangesReachExistingCanvasAndPersistForNextLaunch() async throws {
        let preferences = ViewerPreferences(defaults: defaults)
        let canvas = CanvasNSView(frame: .zero, backend: .vision, defaults: defaults)
        let received = expectation(description: "Existing canvas receives settings")
        let mirror = ViewerPreferences(defaults: defaults)
        let observation = mirror.$snapshot.dropFirst().filter { $0.fixedWindowEnabled }.first()
            .sink { _ in received.fulfill() }
        defer { observation.cancel() }

        preferences.set(\.titleBarVisible, to: true)
        preferences.set(\.minimapEnabled, to: false)
        preferences.set(\.fileInfoVisible, to: false)
        preferences.set(\.toolbarVisible, to: false)
        preferences.set(\.imageParametersVisible, to: true)
        preferences.setTheme(.dark)
        preferences.set(\.fixedWindowEnabled, to: true)

        await fulfillment(of: [received], timeout: 2)
        // Check the actual view, before opening its menu (which also refreshes).
        XCTAssertTrue(canvas.titleBarVisible)
        XCTAssertFalse(canvas.debugMinimapEnabled)
        XCTAssertFalse(canvas.fileInfoVisible)
        XCTAssertFalse(canvas.toolbarVisible)
        XCTAssertTrue(canvas.imageParametersVisible)
        XCTAssertTrue(canvas.fixedWindowEnabled)

        let reopened = ViewerPreferences(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        XCTAssertEqual(reopened.snapshot, preferences.snapshot)
        XCTAssertEqual(reopened.snapshot.theme, .dark)
        let menu = NSMenu()
        canvas.debugAppendPicSeeContextMenuItems(to: menu)
        XCTAssertEqual(menu.items.first { $0.title == "显示缩略图" }?.state, .off)
        XCTAssertEqual(menu.items.first { $0.title == "显示标题栏" }?.state, .on)
        XCTAssertEqual(menu.items.first { $0.title == "显示图片参数" }?.state, .on)
    }

    func testContextMenuChangesUpdateOpenSettingsWithoutManualReload() async {
        let preferences = ViewerPreferences(defaults: defaults)
        let canvas = CanvasNSView(frame: .zero, backend: .vision, defaults: defaults)
        let received = expectation(description: "Settings receives context menu changes")
        let observation = preferences.$snapshot.dropFirst().filter { $0.theme == .dark }.first()
            .sink { _ in received.fulfill() }
        defer { observation.cancel() }

        canvas.toggleTitleBarForMenu(nil)
        canvas.toggleMinimapForMenu(nil)
        canvas.toggleFileInfoForMenu(nil)
        canvas.toggleToolbarForMenu(nil)
        canvas.toggleImageParametersForMenu(nil)
        canvas.toggleFixedWindowForMenu(nil)
        let dark = NSMenuItem()
        dark.representedObject = ViewerTheme.dark.rawValue
        canvas.selectTheme(dark)

        await fulfillment(of: [received], timeout: 2)
        XCTAssertTrue(preferences.snapshot.titleBarVisible)
        XCTAssertFalse(preferences.snapshot.minimapEnabled)
        XCTAssertFalse(preferences.snapshot.fileInfoVisible)
        XCTAssertFalse(preferences.snapshot.toolbarVisible)
        XCTAssertTrue(preferences.snapshot.imageParametersVisible)
        XCTAssertTrue(preferences.snapshot.fixedWindowEnabled)
    }

    func testExistingPreferencesAreReadWithoutMigration() {
        defaults.set(true, forKey: "PicSee.TitleBarVisible")
        defaults.set(false, forKey: "PicSee.MinimapEnabled")
        defaults.set(false, forKey: "PicSee.FileInfoVisible")
        defaults.set(false, forKey: "PicSee.ToolbarVisible")
        defaults.set(true, forKey: "PicSee.ImageParametersVisible")
        defaults.set(true, forKey: "PicSee.FixedWindowFrameEnabled")
        defaults.set(ViewerTheme.light.rawValue, forKey: "PicSee.Theme")

        let preferences = ViewerPreferences(defaults: defaults)
        XCTAssertTrue(preferences.snapshot.titleBarVisible)
        XCTAssertFalse(preferences.snapshot.minimapEnabled)
        XCTAssertFalse(preferences.snapshot.fileInfoVisible)
        XCTAssertFalse(preferences.snapshot.toolbarVisible)
        XCTAssertTrue(preferences.snapshot.imageParametersVisible)
        XCTAssertTrue(preferences.snapshot.fixedWindowEnabled)
        XCTAssertEqual(preferences.snapshot.theme, .light)
    }

    func testReusedLiveTextMenuRefreshesCheckmarksAfterSettingsChange() {
        let canvas = CanvasNSView(frame: .zero, backend: .liveText, defaults: defaults)
        let menu = NSMenu()
        canvas.debugAppendPicSeeContextMenuItems(to: menu)
        let preferences = ViewerPreferences(defaults: defaults)
        preferences.set(\.toolbarVisible, to: false)
        preferences.setTheme(.dark)

        let toolbar = menu.items.first { $0.title == "显示底部工具栏" }!
        XCTAssertTrue(canvas.validateMenuItem(toolbar))
        XCTAssertEqual(toolbar.state, .off)
        let themes = menu.items.first { $0.title == "主题" }!.submenu!.items
        for item in themes { _ = canvas.validateMenuItem(item) }
        XCTAssertEqual(themes.filter { $0.state == .on }.count, 1)
        XCTAssertEqual(themes.first { $0.state == .on }?.representedObject as? Int, ViewerTheme.dark.rawValue)
    }

    func testNewSettingsEntryPreservesExistingMenuAndCommandShortcut() {
        let canvas = CanvasNSView(frame: .zero, backend: .vision, defaults: defaults)
        let menu = NSMenu()
        canvas.debugAppendPicSeeContextMenuItems(to: menu)
        canvas.debugAppendPicSeeContextMenuItems(to: menu)
        XCTAssertEqual(menu.items.filter { $0.action == #selector(AppDelegate.showSettings(_:)) }.count, 1)
        for title in ["默认打开方式…", "检查更新", "关于 PicSee", "主题", "显示缩略图"] {
            XCTAssertNotNil(menu.items.first { $0.title == title })
        }
        let main = AppMenu.buildMainMenu(appName: "PicSee")
        let settings = main.items.first?.submenu?.items.first { $0.action == #selector(AppDelegate.showSettings(_:)) }
        XCTAssertEqual(settings?.keyEquivalent, ",")
        XCTAssertEqual(settings?.keyEquivalentModifierMask, .command)
    }

    func testPreferenceWrittenByAnotherProcessRefreshesOpenSettings() async throws {
        let preferences = ViewerPreferences(defaults: defaults)
        let received = expectation(description: "Distributed preference change")
        let observation = preferences.$snapshot.dropFirst().filter { $0.titleBarVisible }.first()
            .sink { _ in received.fulfill() }
        defer { observation.cancel() }

        let script = """
        import Foundation
        let defaults = UserDefaults(suiteName: CommandLine.arguments[1])!
        defaults.set(true, forKey: "PicSee.TitleBarVisible")
        defaults.synchronize()
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("local.picsee.viewer.preferencesChanged"),
            object: nil, userInfo: nil, deliverImmediately: true
        )
        """
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scriptURL = directory.appendingPathComponent("change-preference.swift")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["-module-cache-path", directory.appendingPathComponent("cache").path, scriptURL.path, suiteName]
        let exited = expectation(description: "Preference writer exited")
        process.terminationHandler = { _ in exited.fulfill() }
        try process.run()
        await fulfillment(of: [received, exited], timeout: 30)
        if process.isRunning { process.terminate() }
        XCTAssertTrue(preferences.snapshot.titleBarVisible)
    }
}
