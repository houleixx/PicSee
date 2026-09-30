import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowManager = WindowManager()
    private var languageObservation: AnyCancellable?
    private var didReceiveOpenRequest = false
    private var settingsWindowController: SettingsWindowController?

    init(settingsWindowController: SettingsWindowController? = nil) {
        self.settingsWindowController = settingsWindowController
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ImageDragFileProvider().cleanupExpiredFiles()
        do {
            let target = Bundle.main.bundleURL
            let status = target.deletingLastPathComponent().appendingPathComponent(".PicSee-update-status")
            if (try? String(contentsOf: status, encoding: .utf8)) == "failed\n" {
                try? FileManager.default.removeItem(at: status)
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = L10n.text("更新安装失败，原版本已保留。")
                    alert.informativeText = L10n.text("可重试更新，或从发布页面手动安装。安装日志：%1$@", target.deletingLastPathComponent().appendingPathComponent(".PicSee-update.log").path)
                    alert.addButton(withTitle: L10n.text("好"))
                    alert.runModal()
                }
            }
        }
        let info = Bundle.main.infoDictionary ?? [:]
        NSApp.mainMenu = AppMenu.buildMainMenu(appName: AppMenu.applicationName(from: info))
        languageObservation = LanguageSettings.shared.$revision.sink { _ in
            NSApp.mainMenu = AppMenu.buildMainMenu(appName: AppMenu.applicationName(from: Bundle.main.infoDictionary ?? [:]))
        }
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
        UserDefaults.standard.synchronize()
        let singleWindow = SingleWindowPreference.isEnabled()
        if singleWindow, let url = imageURLs.first {
            let receiver = SingleWindowRouter.receiverPID()
            if receiver != ProcessInfo.processInfo.processIdentifier {
                do {
                    try SingleWindowRouter.forward(url, to: receiver)
                    // A newly launched forwarding instance has no reason to stay alive.
                    if !windowManager.hasOpenViewer, settingsWindowController == nil {
                        NSApp.terminate(nil)
                    }
                    return
                } catch {
                    // If the receiver exited between discovery and delivery, take over.
                    if let app = NSRunningApplication(processIdentifier: receiver), !app.isTerminated {
                        let alert = NSAlert()
                        alert.addButton(withTitle: L10n.text("好"))
                        LanguageSettings.bind(alert) {
                            $0.messageText = L10n.text("无法在已有窗口中打开图片")
                            $0.informativeText = L10n.errorDescription(error)
                            $0.buttons.first?.title = L10n.text("好")
                        }
                        alert.runModal()
                        return
                    }
                }
            }
        }
        let routing = ImageOpenRouting.route(
            urls: imageURLs, hasOpenViewer: windowManager.hasOpenViewer,
            singleWindowEnabled: singleWindow
        )

        if let currentProcessURL = routing.currentProcessURL {
            if singleWindow {
                windowManager.openInExistingViewer(for: currentProcessURL)
            } else {
                windowManager.openViewer(for: currentProcessURL)
            }
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
            let alert = NSAlert()
            alert.addButton(withTitle: L10n.text("好"))
            LanguageSettings.bind(alert) {
                $0.messageText = L10n.text("无法打开设置")
                $0.informativeText = L10n.errorDescription(error)
                $0.buttons.first?.title = L10n.text("好")
            }
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
