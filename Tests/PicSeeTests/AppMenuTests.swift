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

        XCTAssertEqual(submenu.items.first?.title, "关于 PicSee")
        XCTAssertEqual(submenu.items.first?.action, #selector(AppDelegate.showAboutPanel(_:)))
        XCTAssertEqual(submenu.items.last?.title, "退出 PicSee")
        XCTAssertEqual(submenu.items.last?.action, #selector(NSApplication.terminate(_:)))
    }

    func testReadsDisplayNameAndVersionFromBundleInfo() {
        let info: [String: Any] = [
            "CFBundleName": "PicSee",
            "CFBundleShortVersionString": "0.2.5",
            "CFBundleVersion": "7"
        ]

        XCTAssertEqual(AppMenu.applicationName(from: info), "PicSee")
        XCTAssertEqual(AppMenu.versionSummary(from: info), "版本 0.2.5 (7)")
        XCTAssertEqual(AppMenu.aboutPanelVersion(from: info), "0.2.5")
    }

    func testAboutPanelCreditsIncludeReleaseLinkAndThanks() {
        let info: [String: Any] = [:]

        let credits = AppMenu.aboutPanelCredits(from: info)
        let text = credits.string
        let releaseURL = URL(string: "https://github.com/houleixx/PicSee/releases")!

        XCTAssertTrue(text.contains("下载地址：https://github.com/houleixx/PicSee"))
        XCTAssertTrue(text.contains("感谢“大脑袋范同学”提出的优化建议"))
        XCTAssertFalse(text.contains("https://github.com/houleixx/PicSee/releases/releases"))

        let urlRange = (text as NSString).range(of: "https://github.com/houleixx/PicSee")
        XCTAssertNotEqual(urlRange.location, NSNotFound)
        XCTAssertEqual(credits.attribute(.link, at: urlRange.location, effectiveRange: nil) as? URL, releaseURL)
    }

    func testReleasePageURLUsesGitHubReleasesIndex() {
        XCTAssertEqual(AppMenu.releasePageURL(from: [:]), URL(string: "https://github.com/houleixx/PicSee/releases"))
    }

    func testImageContextMenuContainsAboutItem() {
        let view = CanvasNSView(frame: .zero, backend: .vision)
        let menu = view.menu(for: rightClickEvent())

        XCTAssertNotNil(menu?.items.first { $0.title == "复制图片路径" })
        XCTAssertNotNil(menu?.items.first { $0.title == "显示缩略图" })
        XCTAssertNotNil(menu?.items.first { $0.title == "显示标题栏" })
        XCTAssertNotNil(menu?.items.first { $0.title == "显示文件信息" })
        XCTAssertNotNil(menu?.items.first { $0.title == "显示底部工具栏" })
        XCTAssertNotNil(menu?.items.first { $0.title == "显示图片参数" })
        XCTAssertNotNil(menu?.items.first { $0.title == "固定窗口大小和位置" })
        XCTAssertNotNil(menu?.items.first { $0.title == "图片另存为..." })
        XCTAssertNotNil(menu?.items.first { $0.title == "检查更新" })
        XCTAssertNotNil(menu?.items.first { $0.title == "关于 PicSee" })
        XCTAssertEqual(
            menu?.items.first { $0.title == "关于 PicSee" }?.action,
            #selector(AppDelegate.showAboutPanel(_:))
        )
    }

    func testImageContextMenuShowsTitleBarItemAboveMinimapItem() {
        let view = CanvasNSView(frame: .zero, backend: .vision)
        let menu = view.menu(for: rightClickEvent())

        guard
            let titleBarIndex = menu?.items.firstIndex(where: { $0.title == "显示标题栏" }),
            let minimapIndex = menu?.items.firstIndex(where: { $0.title == "显示缩略图" })
        else {
            return XCTFail("Expected title bar and minimap menu items")
        }

        XCTAssertLessThan(titleBarIndex, minimapIndex)
    }

    func testImageContextMenuGroupsTitleBarMinimapAndFileInfoItemsTogether() {
        let view = CanvasNSView(frame: .zero, backend: .vision)
        let menu = view.menu(for: rightClickEvent())

        guard
            let items = menu?.items,
            let titleBarIndex = items.firstIndex(where: { $0.title == "显示标题栏" }),
            titleBarIndex + 1 < items.count
        else {
            return XCTFail("Expected title bar menu item")
        }

        XCTAssertEqual(items[titleBarIndex + 1].title, "显示缩略图")
        XCTAssertEqual(items[titleBarIndex + 2].title, "显示文件信息")
        XCTAssertEqual(items[titleBarIndex + 3].title, "显示底部工具栏")
        XCTAssertEqual(items[titleBarIndex + 4].title, "显示图片参数")
        XCTAssertEqual(items[titleBarIndex + 5].title, "固定窗口大小和位置")
        XCTAssertFalse(items[titleBarIndex + 1].isSeparatorItem)
        XCTAssertFalse(items[titleBarIndex + 2].isSeparatorItem)
        XCTAssertFalse(items[titleBarIndex + 3].isSeparatorItem)
        XCTAssertFalse(items[titleBarIndex + 4].isSeparatorItem)
        XCTAssertFalse(items[titleBarIndex + 5].isSeparatorItem)
    }

    func testAppendsPicSeeItemsWithoutSeparatingTitleBarMinimapAndFileInfoItems() {
        let view = CanvasNSView(frame: .zero, backend: .liveText)
        let menu = NSMenu(title: "Live Text")
        menu.addItem(NSMenuItem(title: "复制", action: nil, keyEquivalent: ""))

        view.debugAppendPicSeeContextMenuItems(to: menu)

        guard
            let titleBarIndex = menu.items.firstIndex(where: { $0.title == "显示标题栏" }),
            titleBarIndex + 1 < menu.items.count
        else {
            return XCTFail("Expected title bar menu item")
        }

        XCTAssertEqual(menu.items[titleBarIndex + 1].title, "显示缩略图")
        XCTAssertEqual(menu.items[titleBarIndex + 2].title, "显示文件信息")
        XCTAssertEqual(menu.items[titleBarIndex + 3].title, "显示底部工具栏")
        XCTAssertEqual(menu.items[titleBarIndex + 4].title, "显示图片参数")
        XCTAssertEqual(menu.items[titleBarIndex + 5].title, "固定窗口大小和位置")
        XCTAssertFalse(menu.items[titleBarIndex + 1].isSeparatorItem)
        XCTAssertFalse(menu.items[titleBarIndex + 2].isSeparatorItem)
        XCTAssertFalse(menu.items[titleBarIndex + 3].isSeparatorItem)
        XCTAssertFalse(menu.items[titleBarIndex + 4].isSeparatorItem)
        XCTAssertFalse(menu.items[titleBarIndex + 5].isSeparatorItem)
    }

    func testImageContextMenuShowsCheckForUpdatesAboveAboutItem() {
        let view = CanvasNSView(frame: .zero, backend: .vision)
        view.onCheckForUpdates = {}

        let menu = view.menu(for: rightClickEvent())

        guard
            let items = menu?.items,
            let updateIndex = items.firstIndex(where: { $0.title == "检查更新" }),
            let aboutIndex = items.firstIndex(where: { $0.title == "关于 PicSee" })
        else {
            return XCTFail("Expected update and about menu items")
        }

        XCTAssertEqual(updateIndex + 1, aboutIndex)
        XCTAssertFalse(items[aboutIndex].isSeparatorItem)
        XCTAssertTrue(items[updateIndex].isEnabled)
    }

    func testImageContextMenuCheckForUpdatesTriggersCallback() {
        let view = CanvasNSView(frame: .zero, backend: .vision)
        var didCheck = false
        view.onCheckForUpdates = { didCheck = true }

        let menu = view.menu(for: rightClickEvent())
        let updateItem = menu?.items.first { $0.title == "检查更新" }

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

        XCTAssertEqual(CanvasNSView.debugDefaultExportFilename(for: url), "sample.image_副本.jpg")
        XCTAssertEqual(CanvasNSView.debugDefaultExportFilename(for: nil), "PicSee Export_副本.jpg")
    }

    func testImageContextMenuTogglesMinimapVisibilityPreference() {
        let view = CanvasNSView(frame: .zero, backend: .vision)

        var menu = view.menu(for: rightClickEvent())
        let firstItem = menu?.items.first { $0.title == "显示缩略图" }
        XCTAssertEqual(firstItem?.state, .on)
        XCTAssertTrue(view.debugMinimapEnabled)

        view.toggleMinimapForMenu(firstItem)

        menu = view.menu(for: rightClickEvent())
        let secondItem = menu?.items.first { $0.title == "显示缩略图" }
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
        XCTAssertEqual(secondView.menu(for: rightClickEvent())?.items.first { $0.title == "显示缩略图" }?.state, .off)
    }

    func testImageContextMenuTogglesFileInfoVisibilityPreference() {
        let suiteName = "PicSee.AppMenuFileInfoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstView = CanvasNSView(frame: .zero, backend: .vision, defaults: defaults)
        var observedValues: [Bool] = []
        firstView.onFileInfoVisibilityChanged = { observedValues.append($0) }

        var menu = firstView.menu(for: rightClickEvent())
        let firstItem = menu?.items.first { $0.title == "显示文件信息" }
        XCTAssertEqual(firstItem?.state, .on)
        XCTAssertTrue(firstView.debugFileInfoVisible)

        firstView.toggleFileInfoForMenu(firstItem)

        menu = firstView.menu(for: rightClickEvent())
        let secondItem = menu?.items.first { $0.title == "显示文件信息" }
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
        let firstItem = menu?.items.first { $0.title == "显示底部工具栏" }
        XCTAssertEqual(firstItem?.state, .on)
        XCTAssertTrue(firstView.debugToolbarVisible)

        firstView.toggleToolbarForMenu(firstItem)

        menu = firstView.menu(for: rightClickEvent())
        let secondItem = menu?.items.first { $0.title == "显示底部工具栏" }
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
        let firstItem = menu?.items.first { $0.title == "显示图片参数" }
        XCTAssertEqual(firstItem?.state, .off)
        XCTAssertFalse(firstView.debugImageParametersVisible)

        firstView.toggleImageParametersForMenu(firstItem)

        menu = firstView.menu(for: rightClickEvent())
        let secondItem = menu?.items.first { $0.title == "显示图片参数" }
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
        let firstItem = menu?.items.first { $0.title == "显示标题栏" }
        XCTAssertEqual(firstItem?.state, .off)
        XCTAssertFalse(view.debugTitleBarVisible)

        view.toggleTitleBarForMenu(firstItem)

        menu = view.menu(for: rightClickEvent())
        let secondItem = menu?.items.first { $0.title == "显示标题栏" }
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
        let firstItem = menu?.items.first { $0.title == "固定窗口大小和位置" }
        XCTAssertEqual(firstItem?.state, .off)
        XCTAssertFalse(view.debugFixedWindowEnabled)

        view.toggleFixedWindowForMenu(firstItem)

        menu = view.menu(for: rightClickEvent())
        let secondItem = menu?.items.first { $0.title == "固定窗口大小和位置" }
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
        menu.addItem(NSMenuItem(title: "复制", action: nil, keyEquivalent: ""))

        view.debugAppendPicSeeContextMenuItems(to: menu)

        let pathItem = menu.items.first { $0.title == "复制图片路径" }
        XCTAssertNotNil(pathItem)
        XCTAssertTrue(pathItem?.isEnabled ?? false)
        XCTAssertEqual(pathItem?.action, #selector(CanvasNSView.copyImagePathForMenu(_:)))
        XCTAssertNotNil(menu.items.first { $0.title == "图片另存为..." })
        XCTAssertNotNil(menu.items.first { $0.title == "显示缩略图" })
        XCTAssertNotNil(menu.items.first { $0.title == "显示标题栏" })
        XCTAssertNotNil(menu.items.first { $0.title == "显示文件信息" })
        XCTAssertNotNil(menu.items.first { $0.title == "显示底部工具栏" })
        XCTAssertNotNil(menu.items.first { $0.title == "显示图片参数" })
        XCTAssertNotNil(menu.items.first { $0.title == "固定窗口大小和位置" })
        XCTAssertNotNil(menu.items.first { $0.title == "检查更新" })
        XCTAssertNotNil(menu.items.first { $0.title == "关于 PicSee" })
    }

    func testAppendsAboutItemToExistingMenuOnce() {
        let menu = NSMenu(title: "Live Text")
        menu.addItem(NSMenuItem(title: "复制", action: nil, keyEquivalent: ""))

        AppMenu.appendAboutItem(to: menu)
        AppMenu.appendAboutItem(to: menu)

        let aboutItems = menu.items.filter { $0.title == "关于 PicSee" }
        XCTAssertEqual(aboutItems.count, 1)
        XCTAssertEqual(aboutItems.first?.action, #selector(AppDelegate.showAboutPanel(_:)))
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
