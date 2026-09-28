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
        appMenu.addItem(NSMenuItem(
            title: L10n.text("设置…"), action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ","
        ))
        appMenu.addItem(
            NSMenuItem(
                title: L10n.text("默认打开方式…"),
                action: #selector(AppDelegate.showDefaultImageAppSettings(_:)),
                keyEquivalent: ""
            )
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(
                title: L10n.text("退出 %1$@", String(describing: appName)),
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        return mainMenu
    }

    static func buildAboutMenuItem(appName: String) -> NSMenuItem {
        let item = NSMenuItem(
            title: L10n.text("关于 %1$@", appName),
            action: #selector(AppDelegate.showAboutSettings(_:)),
            keyEquivalent: ""
        )
        LanguageSettings.bind(item) { $0.title = L10n.text("关于 %1$@", appName) }
        return item
    }

    static func appendAboutItem(to menu: NSMenu, appName: String = "PicSee", includeSeparator: Bool = true) {
        guard menu.items.first(where: { $0.action == #selector(AppDelegate.showAboutSettings(_:)) }) == nil else {
            return
        }

        if includeSeparator, !menu.items.isEmpty {
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
        let shortVersion = stringValue(for: "CFBundleShortVersionString", in: info) ?? L10n.text("未知")
        return L10n.text("版本 %1$@", String(describing: shortVersion))
    }

    static func releasePageURL(from info: [String: Any]) -> URL {
        URL(string: "https://picsee.pages.dev/")!
    }

    private static func stringValue(for key: String, in info: [String: Any]) -> String? {
        guard let value = info[key] as? String, !value.isEmpty else { return nil }
        return value
    }
}
