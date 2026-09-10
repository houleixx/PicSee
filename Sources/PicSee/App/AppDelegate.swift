import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowManager = WindowManager()
    private var didReceiveOpenRequest = false
    private var defaultImageAppSettingsWindowController: DefaultImageAppSettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let info = Bundle.main.infoDictionary ?? [:]
        NSApp.mainMenu = AppMenu.buildMainMenu(appName: AppMenu.applicationName(from: info))
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [weak self] in
            self?.showSettingsWindowAfterDirectLaunchIfNeeded()
        }
    }

    @objc func showAboutPanel(_ sender: Any?) {
        let info = Bundle.main.infoDictionary ?? [:]
        let credits = AppMenu.aboutPanelCredits(from: info)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppMenu.applicationName(from: info),
            .applicationVersion: AppMenu.aboutPanelVersion(from: info),
            .credits: credits
        ])
        for window in NSApp.windows {
            if let contentView = window.contentView {
                removeAboutLinkUnderlines(in: contentView, credits: credits.string)
            }
        }
    }

    private func removeAboutLinkUnderlines(in view: NSView, credits: String) {
        if let textView = view as? NSTextView, textView.string.contains(credits) {
            // NSTextView applies linkTextAttributes over the attributed string.
            // Keep its link color and cursor, but override the default underline.
            var attributes = textView.linkTextAttributes ?? [:]
            attributes[.underlineStyle] = 0
            textView.linkTextAttributes = attributes
            textView.needsDisplay = true
        }
        for subview in view.subviews {
            removeAboutLinkUnderlines(in: subview, credits: credits)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        didReceiveOpenRequest = true
        open(urls: urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        didReceiveOpenRequest = true
        open(urls: [URL(fileURLWithPath: filename)])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        didReceiveOpenRequest = true
        open(urls: filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func open(urls: [URL]) {
        let imageURLs = urls.filter(FolderImageNavigator.isSupportedImage)
        let routing = ImageOpenRouting.route(urls: imageURLs, hasOpenViewer: windowManager.hasOpenViewer)

        if let currentProcessURL = routing.currentProcessURL {
            windowManager.openViewer(for: currentProcessURL)
        }

        for spawnedURL in routing.spawnedProcessURLs {
            spawnNewProcess(for: spawnedURL)
        }
    }

    private func spawnNewProcess(for url: URL) {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", "-b", bundleIdentifier, url.path]

        do {
            try process.run()
        } catch {
            NSSound.beep()
        }
    }

    @objc func showDefaultImageAppSettings(_ sender: Any?) {
        do {
            let controller = try defaultImageAppSettingsWindowController ?? DefaultImageAppSettingsWindowController(
                handler: LaunchServicesDefaultImageAppHandler()
            )
            defaultImageAppSettingsWindowController = controller
            controller.show()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "无法打开默认图片设置"
            alert.runModal()
        }
    }

    private func showSettingsWindowAfterDirectLaunchIfNeeded() {
        guard DefaultImageAppSettings.shouldShowSettingsWindowAfterLaunch(
            didReceiveOpenRequest: didReceiveOpenRequest,
            hasOpenViewer: windowManager.hasOpenViewer
        ) else {
            return
        }

        showDefaultImageAppSettings(nil)
    }
}
