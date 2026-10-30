import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowManager: WindowManager
    private let successTip = SuccessTipPresenter()
    private var updateObservation: AnyCancellable?
    private var languageObservation: AnyCancellable?
    private var didReceiveOpenRequest = false
    private var settingsWindowController: SettingsWindowController?

    init(settingsWindowController: SettingsWindowController? = nil, windowManager: WindowManager? = nil) {
        self.windowManager = windowManager ?? WindowManager()
        self.settingsWindowController = settingsWindowController
        super.init()
        updateObservation = self.windowManager.updateChecker?.$status.sink { [weak self] status in
            guard status == .failed else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.hasOpenWindows else { return }
                self.showSettings(page: .about)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ImageDragCleanupWorker.schedule()
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
            guard let self else { return }
            if let session = UpdateSession.consume(arguments: ProcessInfo.processInfo.arguments) {
                self.restoreUpdateSession(session) { [weak self] in
                    guard let self else { return }
                    guard ProcessInfo.processInfo.arguments.contains("--picsee-update-success") else {
                        if !self.hasOpenWindows { NSApp.terminate(nil) }
                        return
                    }
                    let preferredWindow = session.settingsInFront ? self.settingsWindowController?.window
                        : self.windowManager.currentWindow ?? self.settingsWindowController?.window
                    guard let anchor = preferredWindow,
                          SuccessTipPresenter.canPresent(in: anchor) else {
                        if !self.hasOpenWindows { NSApp.terminate(nil) }
                        return
                    }
                    self.successTip.show(message: L10n.text("更新安装成功"), in: anchor) { [weak self] in
                        guard let self else { return }
                        if !self.hasOpenWindows { NSApp.terminate(nil) }
                    }
                }
            } else {
                self.showSettingsWindowAfterDirectLaunchIfNeeded()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await windowManager.updateChecker?.checkForUpdatesIfNeeded() }
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
        windowManager.updateChecker?.status != .downloading
    }

    private var hasOpenWindows: Bool {
        windowManager.hasOpenViewer || settingsWindowController?.window.map { $0.isVisible || $0.isMiniaturized } == true
    }

    func captureUpdateSession() -> UpdateSession {
        let settings = settingsWindowController?.window
        let settingsOpen = settings.map { $0.isVisible || $0.isMiniaturized } == true
        return UpdateSession(
            viewer: windowManager.captureUpdateViewer(),
            settingsPage: settingsOpen ? settingsWindowController?.navigation.page.rawValue : nil,
            settingsFrame: settingsOpen ? settings?.frame : nil,
            settingsMinimized: settingsOpen && settings?.isMiniaturized == true,
            settingsInFront: settingsOpen && settings?.isKeyWindow == true
        )
    }

    func restoreUpdateSession(_ session: UpdateSession, completion: @escaping @MainActor () -> Void = {}) {
        var waitsForViewer = false
        if !didReceiveOpenRequest, let viewer = session.viewer,
           FileManager.default.isReadableFile(atPath: viewer.url.path) {
            waitsForViewer = true
            windowManager.restoreUpdateViewer(viewer) { [weak self] in
                self?.focusRestoredWindows(session)
                // Let SwiftUI lay out the loaded image before showing the nonmodal tip.
                DispatchQueue.main.async(execute: completion)
            }
        }
        if let rawPage = session.settingsPage, let page = SettingsPage(rawValue: rawPage) {
            showSettings(page: page)
            if let frame = session.settingsFrame { settingsWindowController?.window?.setFrame(frame, display: true) }
            if session.settingsMinimized { settingsWindowController?.window?.miniaturize(nil) }
        }
        focusRestoredWindows(session)
        // A removed image falls back to settings; an intentionally empty session stays empty.
        if session.viewer != nil, !hasOpenWindows { showSettings(page: .about) }
        if !waitsForViewer { DispatchQueue.main.async(execute: completion) }
    }

    private func focusRestoredWindows(_ session: UpdateSession) {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        if session.settingsInFront, !session.settingsMinimized {
            if let window = settingsWindowController?.window {
                window.orderFrontRegardless()
                window.makeKey()
            }
        } else if session.viewer?.minimized == false {
            if let window = windowManager.currentWindow {
                window.orderFrontRegardless()
                window.makeKey()
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            if session.settingsInFront, !session.settingsMinimized {
                self.settingsWindowController?.window?.makeKey()
            } else if session.viewer?.minimized == false {
                self.windowManager.currentWindow?.makeKey()
            }
        }
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
