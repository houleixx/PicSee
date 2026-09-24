import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowManager = WindowManager()
    private var didReceiveOpenRequest = false
    private var settingsWindowController: SettingsWindowController?

    init(settingsWindowController: SettingsWindowController? = nil) {
        self.settingsWindowController = settingsWindowController
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ImageDragFileProvider().cleanupExpiredFiles()
        let info = Bundle.main.infoDictionary ?? [:]
        NSApp.mainMenu = AppMenu.buildMainMenu(appName: AppMenu.applicationName(from: info))
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [weak self] in
            self?.showSettingsWindowAfterDirectLaunchIfNeeded()
        }
    }

    @objc func showAboutSettings(_ sender: Any?) {
        showSettings(page: .about)
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
        showSettings(page: .defaultApps)
    }

    @objc func showSettings(_ sender: Any?) {
        showSettings(page: .browsing)
    }

    private func showSettings(page: SettingsPage) {
        do {
            let controller = try settingsWindowController ?? SettingsWindowController(
                updateChecker: windowManager.updateChecker,
                defaultAppHandler: LaunchServicesDefaultImageAppHandler(),
                captureFixedWindowFrame: { [weak self] in self?.windowManager.captureFixedWindowFrame() }
            )
            settingsWindowController = controller
            controller.show(page: page)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "无法打开设置"
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

        showSettings(page: .defaultApps)
    }
}
