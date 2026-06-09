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

    static func appendAboutItem(to menu: NSMenu, appName: String = "PicSee", includeSeparator: Bool = true) {
        guard menu.items.first(where: { $0.action == #selector(AppDelegate.showAboutPanel(_:)) }) == nil else {
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
        let shortVersion = stringValue(for: "CFBundleShortVersionString", in: info) ?? "未知"
        guard let build = stringValue(for: "CFBundleVersion", in: info), !build.isEmpty else {
            return "版本 \(shortVersion)"
        }

        return "版本 \(shortVersion) (\(build))"
    }

    static func aboutPanelVersion(from info: [String: Any]) -> String {
        stringValue(for: "CFBundleShortVersionString", in: info) ?? "未知"
    }

    static func aboutPanelCredits(from info: [String: Any]) -> NSAttributedString {
        let releaseURL = releasePageURL(from: info)
        let releaseLine = "下载地址：https://github.com/houleixx/PicSee"
        let thanksLine = "感谢“大脑袋范同学”提出的优化建议"
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 6

        let credits = NSMutableAttributedString(
            string: "\(releaseLine)\n\(thanksLine)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
        )

        let range = (credits.string as NSString).range(of: "https://github.com/houleixx/PicSee")
        if range.location != NSNotFound {
            credits.addAttribute(.link, value: releaseURL, range: range)
        }

        return credits
    }

    static func releasePageURL(from info: [String: Any]) -> URL {
        URL(string: "https://github.com/houleixx/PicSee/releases")!
    }

    private static func stringValue(for key: String, in info: [String: Any]) -> String? {
        guard let value = info[key] as? String, !value.isEmpty else { return nil }
        return value
    }
}
