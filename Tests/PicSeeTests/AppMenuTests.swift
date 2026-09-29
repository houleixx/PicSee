import AppKit
import XCTest
@testable import PicSee

@MainActor
final class AppMenuTests: XCTestCase {
    func testBuildsApplicationMenuWithAboutItem() {
        let menu = AppMenu.buildMainMenu(appName: "PicSee")

        guard let appMenuItem = menu.items.first else {
            return XCTFail("Expected an application menu item")
        }

        XCTAssertEqual(appMenuItem.title, "PicSee")

        guard let submenu = appMenuItem.submenu else {
            return XCTFail("Expected application submenu")
        }

        XCTAssertEqual(submenu.items.first?.title, L10n.text("关于 %1$@", "PicSee"))
        XCTAssertEqual(submenu.items.first?.action, #selector(AppDelegate.showAboutSettings(_:)))
        XCTAssertNotNil(submenu.items.first { $0.title == L10n.text("默认打开方式…") })
        XCTAssertEqual(
            submenu.items.first { $0.title == L10n.text("默认打开方式…") }?.action,
            #selector(AppDelegate.showDefaultImageAppSettings(_:))
        )
        XCTAssertEqual(submenu.items.last?.title, L10n.text("退出 PicSee"))
        XCTAssertEqual(submenu.items.last?.action, #selector(NSApplication.terminate(_:)))
    }

    func testReadsDisplayNameAndVersionFromBundleInfo() {
        let info: [String: Any] = [
            "CFBundleName": "PicSee",
            "CFBundleShortVersionString": "0.2.5",
            "CFBundleVersion": "7"
        ]

        XCTAssertEqual(AppMenu.applicationName(from: info), "PicSee")
        XCTAssertEqual(AppMenu.versionSummary(from: info), L10n.text("版本 %1$@", "0.2.5"))
    }

    func testReleasePageURLUsesWebsite() {
        XCTAssertEqual(AppMenu.releasePageURL(from: [:]), URL(string: "https://picsee.pages.dev/"))
    }

    func testContextMenuKeepsApplicationSettingsInSettingsWindow() {
        let view = CanvasNSView(frame: .zero, backend: .vision)
        let menu = view.menu(for: rightClickEvent())!
        XCTAssertEqual(menu.items.last?.action, #selector(CanvasNSView.checkForUpdatesForMenu(_:)))
        XCTAssertEqual(menu.items[menu.items.count - 2].action, #selector(AppDelegate.showSettings(_:)))
        XCTAssertFalse(view.validateMenuItem(menu.items.last!))
        for action in [#selector(AppDelegate.showAboutSettings(_:)),
                       #selector(AppDelegate.showDefaultImageAppSettings(_:))] {
            XCTAssertFalse(menu.items.contains { $0.action == action })
        }
        XCTAssertEqual(menu.items.first?.action, #selector(CanvasNSView.copyImagePathForMenu(_:)))
        XCTAssertEqual(menu.items[1].action, #selector(CanvasNSView.exportImageForMenu(_:)))
    }

    func testDisplayOptionsAreGroupedInAnIconFreeSubmenu() {
        let view = CanvasNSView(frame: .zero, backend: .vision)
        let menu = view.menu(for: rightClickEvent())!
        let items = menu.displayOptionsItems
        XCTAssertEqual(items.map(\.title), ["显示标题栏", "显示缩略图", "显示文件信息", "显示底部工具栏", "显示图片参数"].map { L10n.text($0) })
        XCTAssertTrue(items.allSatisfy { $0.image == nil && $0.target === view })
        XCTAssertFalse(menu.items.contains { $0.action == #selector(CanvasNSView.toggleMinimapForMenu(_:)) })
        XCTAssertEqual(items.last?.keyEquivalent, "i")
        XCTAssertEqual(items.last?.keyEquivalentModifierMask, .command)
    }

    func testMainMenuIconsLoadAndWindowControlsRemainTogether() {
        let view = CanvasNSView(frame: .zero, backend: .vision)
        view.onStartSlideshow = {}
        let menu = view.menu(for: rightClickEvent())!
        XCTAssertTrue(menu.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.image != nil })
        let index = menu.items.firstIndex { $0.title == L10n.text("显示选项") }!
        XCTAssertEqual(Array(menu.items[(index + 1)...(index + 4)]).map(\.title),
                       ["单窗口看图", "窗口置顶", "固定窗口大小和位置", "主题"].map { L10n.text($0) })
    }

    func testLiveTextActionsKeepTheirTargetsAndGainAlignedIcons() {
        let view = CanvasNSView(frame: .zero, backend: .liveText)
        let menu = NSMenu()
        let copy = NSMenuItem(title: "拷贝图像", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        copy.target = view
        let share = NSMenuItem(title: "Share Image…", action: nil, keyEquivalent: "")
        menu.addItem(copy)
        menu.addItem(share)
        view.debugAppendPicSeeContextMenuItems(to: menu)
        let count = menu.items.count
        view.debugAppendPicSeeContextMenuItems(to: menu)
        XCTAssertEqual(menu.items.count, count)
        XCTAssertTrue(menu.items[0] === copy)
        XCTAssertTrue(copy.target === view)
        XCTAssertEqual(copy.action, #selector(NSText.copy(_:)))
        XCTAssertNotNil(copy.image)
        XCTAssertNotNil(share.image)
        XCTAssertEqual(menu.displayOptionsItems.count, 5)
    }

    func testAppendingPicSeeItemsTwiceAddsOnlyOneThemeMenu() {
        let view = CanvasNSView(frame: .zero, backend: .liveText)
        let menu = NSMenu(title: "Live Text")

        view.debugAppendPicSeeContextMenuItems(to: menu)
        view.debugAppendPicSeeContextMenuItems(to: menu)

        XCTAssertEqual(menu.items.filter { $0.title == L10n.text("主题") }.count, 1)
    }

    func testSelectingThemeRefreshesReusedMenuCheckmarks() {
        let suiteName = "PicSee.AppMenuTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let view = CanvasNSView(frame: .zero, backend: .liveText, defaults: defaults)
        let menu = NSMenu(title: "Live Text")

        view.debugAppendPicSeeContextMenuItems(to: menu)
        guard
            let themeItems = menu.items.first(where: { $0.title == L10n.text("主题") })?.submenu?.items,
            let darkItem = themeItems.first(where: { $0.representedObject as? Int == ViewerTheme.dark.rawValue })
        else {
            return XCTFail("Expected theme submenu")
        }

        view.selectTheme(darkItem)

        XCTAssertEqual(ViewerTheme.current(in: defaults), .dark)
        XCTAssertEqual(darkItem.state, .on)
        XCTAssertTrue(themeItems.filter { $0.state == .on }.count == 1)
    }

    func testImageContextMenuCheckForUpdatesTriggersCallback() {
        let view = CanvasNSView(frame: .zero, backend: .vision)
        var didCheck = false
        view.onCheckForUpdates = { didCheck = true }

        let menu = view.menu(for: rightClickEvent())
        let updateItem = menu?.items.first { $0.title == L10n.text("检查更新") }

        XCTAssertNotNil(updateItem)
        XCTAssertNotNil(updateItem?.image)
        XCTAssertTrue(updateItem?.target === view)
        XCTAssertEqual(updateItem?.action, #selector(CanvasNSView.checkForUpdatesForMenu(_:)))
        XCTAssertTrue(view.validateMenuItem(updateItem!))
        view.checkForUpdatesForMenu(updateItem)

        XCTAssertTrue(didCheck)
    }

    func testTopDragRegionIsDisabledWhenTitleBarIsVisible() {
        let view = CanvasNSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), backend: .vision)

        XCTAssertTrue(view.debugCanDragWindow(at: CGPoint(x: 200, y: 292)))

        view.titleBarVisible = true

        XCTAssertFalse(view.debugCanDragWindow(at: CGPoint(x: 200, y: 292)))
    }

    func testBottomRightResizeAnchorUsesInsetHitAreaForRoundedWindowCorner() {
        let view = CanvasNSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), backend: .vision)

        XCTAssertEqual(view.debugResizeAnchor(at: CGPoint(x: 340, y: 20)), .bottomRight)
        XCTAssertNil(view.debugResizeAnchor(at: CGPoint(x: 332, y: 72)))

        view.titleBarVisible = true

        XCTAssertNil(view.debugResizeAnchor(at: CGPoint(x: 340, y: 20)))
    }

    func testResizeAnchorIsDisabledWhenWindowSizeIsFixed() {
        let view = CanvasNSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), backend: .vision)

        XCTAssertEqual(view.debugResizeAnchor(at: CGPoint(x: 340, y: 20)), .bottomRight)

        view.fixedWindowEnabled = true

        XCTAssertNil(view.debugResizeAnchor(at: CGPoint(x: 340, y: 20)))
    }

    func testDefaultExportFilenameUsesCopySuffix() {
        let url = URL(fileURLWithPath: "/tmp/sample.image.png")

        XCTAssertEqual(CanvasNSView.debugDefaultExportFilename(for: url), L10n.text("%1$@_副本.jpg", "sample.image"))
        XCTAssertEqual(CanvasNSView.debugDefaultExportFilename(for: nil), L10n.text("%1$@_副本.jpg", L10n.text("导出图片")))
    }

    func testImageContextMenuTogglesMinimapVisibilityPreference() {
        let view = CanvasNSView(frame: .zero, backend: .vision)

        var menu = view.menu(for: rightClickEvent())
        let firstItem = menu?.displayOptionsItems.first { $0.title == L10n.text("显示缩略图") }
        XCTAssertEqual(firstItem?.state, .on)
        XCTAssertTrue(view.debugMinimapEnabled)

        view.toggleMinimapForMenu(firstItem)

        menu = view.menu(for: rightClickEvent())
        let secondItem = menu?.displayOptionsItems.first { $0.title == L10n.text("显示缩略图") }
        XCTAssertEqual(secondItem?.state, .off)
        XCTAssertFalse(view.debugMinimapEnabled)

        view.toggleMinimapForMenu(secondItem)

        XCTAssertTrue(view.debugMinimapEnabled)
    }

    func testImageContextMenuPersistsMinimapVisibilityPreference() {
        let suiteName = "PicSee.AppMenuTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstView = CanvasNSView(frame: .zero, backend: .vision, defaults: defaults)
        XCTAssertTrue(firstView.debugMinimapEnabled)

        firstView.toggleMinimapForMenu(nil as Any?)
        XCTAssertFalse(firstView.debugMinimapEnabled)

        let secondView = CanvasNSView(frame: .zero, backend: .vision, defaults: defaults)
        XCTAssertFalse(secondView.debugMinimapEnabled)
        XCTAssertEqual(secondView.menu(for: rightClickEvent())?.displayOptionsItems.first { $0.title == L10n.text("显示缩略图") }?.state, .off)
    }

    func testImageContextMenuTogglesFileInfoVisibilityPreference() {
        let suiteName = "PicSee.AppMenuFileInfoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstView = CanvasNSView(frame: .zero, backend: .vision, defaults: defaults)
        var observedValues: [Bool] = []
        firstView.onFileInfoVisibilityChanged = { observedValues.append($0) }

        var menu = firstView.menu(for: rightClickEvent())
        let firstItem = menu?.displayOptionsItems.first { $0.title == L10n.text("显示文件信息") }
        XCTAssertEqual(firstItem?.state, .on)
        XCTAssertTrue(firstView.debugFileInfoVisible)

        firstView.toggleFileInfoForMenu(firstItem)

        menu = firstView.menu(for: rightClickEvent())
        let secondItem = menu?.displayOptionsItems.first { $0.title == L10n.text("显示文件信息") }
        XCTAssertEqual(secondItem?.state, .off)
        XCTAssertFalse(firstView.debugFileInfoVisible)
        XCTAssertEqual(observedValues, [false])

        let secondView = CanvasNSView(frame: .zero, backend: .vision, defaults: defaults)
        XCTAssertFalse(secondView.debugFileInfoVisible)
    }

    func testImageContextMenuTogglesToolbarVisibilityPreference() {
        let suiteName = "PicSee.AppMenuToolbarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstView = CanvasNSView(frame: .zero, backend: .vision, defaults: defaults)
        var observedValues: [Bool] = []
        firstView.onToolbarVisibilityChanged = { observedValues.append($0) }

        var menu = firstView.menu(for: rightClickEvent())
        let firstItem = menu?.displayOptionsItems.first { $0.title == L10n.text("显示底部工具栏") }
        XCTAssertEqual(firstItem?.state, .on)
        XCTAssertTrue(firstView.debugToolbarVisible)

        firstView.toggleToolbarForMenu(firstItem)

        menu = firstView.menu(for: rightClickEvent())
        let secondItem = menu?.displayOptionsItems.first { $0.title == L10n.text("显示底部工具栏") }
        XCTAssertEqual(secondItem?.state, .off)
        XCTAssertFalse(firstView.debugToolbarVisible)
        XCTAssertEqual(observedValues, [false])

        let secondView = CanvasNSView(frame: .zero, backend: .vision, defaults: defaults)
        XCTAssertFalse(secondView.debugToolbarVisible)
    }

    func testImageContextMenuTogglesImageParametersVisibilityPreference() {
        let suiteName = "PicSee.AppMenuImageParametersTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstView = CanvasNSView(frame: .zero, backend: .vision, defaults: defaults)
        var observedValues: [Bool] = []
        firstView.onImageParametersVisibilityChanged = { observedValues.append($0) }

        var menu = firstView.menu(for: rightClickEvent())
        let firstItem = menu?.displayOptionsItems.first { $0.title == L10n.text("显示图片参数") }
        XCTAssertEqual(firstItem?.state, .off)
        XCTAssertFalse(firstView.debugImageParametersVisible)

        firstView.toggleImageParametersForMenu(firstItem)

        menu = firstView.menu(for: rightClickEvent())
        let secondItem = menu?.displayOptionsItems.first { $0.title == L10n.text("显示图片参数") }
        XCTAssertEqual(secondItem?.state, .on)
        XCTAssertTrue(firstView.debugImageParametersVisible)
        XCTAssertEqual(observedValues, [true])

        let secondView = CanvasNSView(frame: .zero, backend: .vision, defaults: defaults)
        XCTAssertTrue(secondView.debugImageParametersVisible)
    }

    func testImageContextMenuTogglesTitleBarVisibilityPreference() {
        let suiteName = "PicSee.AppMenuTitleBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let view = CanvasNSView(frame: .zero, backend: .vision, defaults: defaults)
        var observedValues: [Bool] = []
        view.onTitleBarVisibilityChanged = { observedValues.append($0) }

        var menu = view.menu(for: rightClickEvent())
        let firstItem = menu?.displayOptionsItems.first { $0.title == L10n.text("显示标题栏") }
        XCTAssertEqual(firstItem?.state, .off)
        XCTAssertFalse(view.debugTitleBarVisible)

        view.toggleTitleBarForMenu(firstItem)

        menu = view.menu(for: rightClickEvent())
        let secondItem = menu?.displayOptionsItems.first { $0.title == L10n.text("显示标题栏") }
        XCTAssertEqual(secondItem?.state, .on)
        XCTAssertTrue(view.debugTitleBarVisible)
        XCTAssertEqual(observedValues, [true])

        let secondView = CanvasNSView(frame: .zero, backend: .vision, defaults: defaults)
        XCTAssertTrue(secondView.debugTitleBarVisible)
    }

    func testImageContextMenuTogglesFixedWindowPreference() {
        let suiteName = "PicSee.AppMenuFixedWindowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let view = CanvasNSView(frame: .zero, backend: .vision, defaults: defaults)
        var observedValues: [Bool] = []
        view.onFixedWindowChanged = { observedValues.append($0) }

        var menu = view.menu(for: rightClickEvent())
        let firstItem = menu?.items.first { $0.title == L10n.text("固定窗口大小和位置") }
        XCTAssertEqual(firstItem?.state, .off)
        XCTAssertFalse(view.debugFixedWindowEnabled)

        view.toggleFixedWindowForMenu(firstItem)

        menu = view.menu(for: rightClickEvent())
        let secondItem = menu?.items.first { $0.title == L10n.text("固定窗口大小和位置") }
        XCTAssertEqual(secondItem?.state, .on)
        XCTAssertTrue(view.debugFixedWindowEnabled)
        XCTAssertTrue(WindowFramePreference.isFixedEnabled(in: defaults))
        XCTAssertEqual(observedValues, [true])

        view.toggleFixedWindowForMenu(secondItem)

        XCTAssertFalse(view.debugFixedWindowEnabled)
        XCTAssertFalse(WindowFramePreference.isFixedEnabled(in: defaults))
        XCTAssertEqual(observedValues, [true, false])
    }

    func testAppendsPicSeeItemsToExistingLiveTextMenu() {
        let view = CanvasNSView(frame: .zero, backend: .liveText)
        view.imageURL = URL(fileURLWithPath: "/tmp/example.png")
        let menu = NSMenu(title: "Live Text")
        menu.addItem(NSMenuItem(title: L10n.text("复制"), action: nil, keyEquivalent: ""))

        view.debugAppendPicSeeContextMenuItems(to: menu)

        let pathItem = menu.items.first { $0.title == L10n.text("复制图片路径") }
        XCTAssertNotNil(pathItem)
        XCTAssertTrue(pathItem?.isEnabled ?? false)
        XCTAssertEqual(pathItem?.action, #selector(CanvasNSView.copyImagePathForMenu(_:)))
        XCTAssertNotNil(menu.items.first { $0.title == L10n.text("图片另存为...") })
        XCTAssertNotNil(menu.displayOptionsItems.first { $0.title == L10n.text("显示缩略图") })
        XCTAssertNotNil(menu.displayOptionsItems.first { $0.title == L10n.text("显示标题栏") })
        XCTAssertNotNil(menu.displayOptionsItems.first { $0.title == L10n.text("显示文件信息") })
        XCTAssertNotNil(menu.displayOptionsItems.first { $0.title == L10n.text("显示底部工具栏") })
        XCTAssertNotNil(menu.displayOptionsItems.first { $0.title == L10n.text("显示图片参数") })
        XCTAssertNotNil(menu.items.first { $0.title == L10n.text("固定窗口大小和位置") })
        XCTAssertNil(menu.items.first { $0.title == L10n.text("默认打开方式…") })
        XCTAssertNotNil(menu.items.first { $0.title == L10n.text("检查更新") })
        XCTAssertNil(menu.items.first { $0.title == L10n.text("关于 %1$@", "PicSee") })
    }

    func testAppendsAboutItemToExistingMenuOnce() {
        let menu = NSMenu(title: "Live Text")
        menu.addItem(NSMenuItem(title: L10n.text("复制"), action: nil, keyEquivalent: ""))

        AppMenu.appendAboutItem(to: menu)
        AppMenu.appendAboutItem(to: menu)

        let aboutItems = menu.items.filter { $0.title == L10n.text("关于 %1$@", "PicSee") }
        XCTAssertEqual(aboutItems.count, 1)
        XCTAssertEqual(aboutItems.first?.action, #selector(AppDelegate.showAboutSettings(_:)))
    }

    private func rightClickEvent() -> NSEvent {
        NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )!
    }
}
