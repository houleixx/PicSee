import AppKit

@MainActor
enum AppMenu {
    static func buildMainMenu(appName: String) -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        appMenuItem.title = appName
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: appName)
        appMenuItem.submenu = appMenu

        appMenu.addItem(buildAboutMenuItem(appName: appName))
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(
                title: "退出 \(appName)",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        return mainMenu
    }

    static func buildAboutMenuItem(appName: String) -> NSMenuItem {
        NSMenuItem(
            title: "关于 \(appName)",
            action: #selector(AppDelegate.showAboutPanel(_:)),
            keyEquivalent: ""
        )
    }

    static func appendAboutItem(to menu: NSMenu, appName: String = "PicSee") {
        guard menu.items.first(where: { $0.action == #selector(AppDelegate.showAboutPanel(_:)) }) == nil else {
            return
        }

        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        let aboutItem = buildAboutMenuItem(appName: appName)
        aboutItem.target = NSApplication.shared.delegate
        menu.addItem(aboutItem)
    }

    static func applicationName(from info: [String: Any]) -> String {
        stringValue(for: "CFBundleDisplayName", in: info)
            ?? stringValue(for: "CFBundleName", in: info)
            ?? "PicSee"
    }

    static func versionSummary(from info: [String: Any]) -> String {
        let shortVersion = stringValue(for: "CFBundleShortVersionString", in: info) ?? "未知"
        guard let build = stringValue(for: "CFBundleVersion", in: info), !build.isEmpty else {
            return "版本 \(shortVersion)"
        }

        return "版本 \(shortVersion) (\(build))"
    }

    static func aboutPanelVersion(from info: [String: Any]) -> String {
        stringValue(for: "CFBundleShortVersionString", in: info) ?? "未知"
    }

    private static func stringValue(for key: String, in info: [String: Any]) -> String? {
        guard let value = info[key] as? String, !value.isEmpty else { return nil }
        return value
    }
}
