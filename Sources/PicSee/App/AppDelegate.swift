import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowManager = WindowManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let info = Bundle.main.infoDictionary ?? [:]
        NSApp.mainMenu = AppMenu.buildMainMenu(appName: AppMenu.applicationName(from: info))
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showAboutPanel(_ sender: Any?) {
        let info = Bundle.main.infoDictionary ?? [:]
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppMenu.applicationName(from: info),
            .applicationVersion: AppMenu.aboutPanelVersion(from: info)
        ])
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let imageURLs = urls.filter(FolderImageNavigator.isSupportedImage)
        let routing = ImageOpenRouting.route(urls: imageURLs, hasOpenViewer: windowManager.hasOpenViewer)

        if let currentProcessURL = routing.currentProcessURL {
            windowManager.openViewer(for: currentProcessURL)
        }

        for spawnedURL in routing.spawnedProcessURLs {
            spawnNewProcess(for: spawnedURL)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
}
