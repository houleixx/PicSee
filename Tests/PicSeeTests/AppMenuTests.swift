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

    func testImageContextMenuContainsAboutItem() {
        let view = CanvasNSView(frame: .zero, backend: .vision)
        let menu = view.menu(for: rightClickEvent())

        XCTAssertNotNil(menu?.items.first { $0.title == "复制图片路径" })
        XCTAssertNotNil(menu?.items.first { $0.title == "关于 PicSee" })
        XCTAssertEqual(
            menu?.items.first { $0.title == "关于 PicSee" }?.action,
            #selector(AppDelegate.showAboutPanel(_:))
        )
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
