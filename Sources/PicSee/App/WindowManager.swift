import AppKit
import Combine
import ObjectiveC
import SwiftUI

final class ViewerWindow: NSWindow {
    var pinningController: WindowPinningController?
    var automaticImageResizeTarget: NSRect?
    private struct NativeFullScreenSnapshot {
        let styleMask: NSWindow.StyleMask
        let frame: NSRect
    }

    private var restoreFrameAfterTemporaryDesktopFullScreen: NSRect?
    var isTemporaryDesktopFullScreenActive: Bool { restoreFrameAfterTemporaryDesktopFullScreen != nil }
    var fallbackFrameForTemporaryDesktopFullScreen: NSRect?
    var onWillEnterTemporaryDesktopFullScreen: ((NSRect) -> Void)?
    private var nativeFullScreenSnapshot: NativeFullScreenSnapshot?
    var isNativeFullScreenTransitionActive: Bool { nativeFullScreenSnapshot != nil }

    var persistableFrame: NSRect? {
        Self.persistableFrame(
            currentFrame: frame,
            capturedFrame: nativeFullScreenSnapshot?.frame,
            isFullScreen: styleMask.contains(.fullScreen)
        )
    }

    static func persistableFrame(
        currentFrame: NSRect,
        capturedFrame: NSRect?,
        isFullScreen: Bool
    ) -> NSRect? {
        if let capturedFrame {
            return capturedFrame
        }
        return isFullScreen ? nil : currentFrame
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval {
        if let automaticImageResizeTarget,
           newFrame.isApproximatelyEqual(to: automaticImageResizeTarget) {
            return 0.24
        }
        return super.animationResizeTime(newFrame)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, isTitleBarEvent(event) {
            toggleTemporaryDesktopFullScreen()
            return
        }
        super.mouseDown(with: event)
    }

    override func toggleFullScreen(_ sender: Any?) {
        guard !styleMask.contains(.fullScreen) else {
            super.toggleFullScreen(sender)
            return
        }
        guard nativeFullScreenSnapshot == nil else { return }
        prepareStyleMaskForNativeFullScreen()
        super.toggleFullScreen(sender)
    }

    func prepareStyleMaskForNativeFullScreen() {
        guard nativeFullScreenSnapshot == nil else { return }
        pinningController?.setFullScreenActive(true)
        nativeFullScreenSnapshot = NativeFullScreenSnapshot(styleMask: styleMask, frame: frame)
        styleMask = [.titled, .closable, .miniaturizable, .resizable]
    }

    func restoreStyleMaskAfterFailedFullScreenEntry() {
        guard let snapshot = nativeFullScreenSnapshot else { return }
        styleMask = snapshot.styleMask
        setFrame(snapshot.frame, display: true)
        nativeFullScreenSnapshot = nil
        pinningController?.setFullScreenActive(false)
    }

    @discardableResult
    func completeNativeFullScreenExit(restoring styleMask: NSWindow.StyleMask) -> Bool {
        guard let snapshot = nativeFullScreenSnapshot else { return false }
        self.styleMask = styleMask
        setFrame(snapshot.frame, display: true)
        nativeFullScreenSnapshot = nil
        pinningController?.setFullScreenActive(false)
        return true
    }

    func toggleTemporaryDesktopFullScreen() {
        guard let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let transition = Self.temporaryDesktopFullScreenTransition(
            currentFrame: frame,
            visibleFrame: visibleFrame,
            restoreFrame: restoreFrameAfterTemporaryDesktopFullScreen,
            fallbackFrame: fallbackFrameForTemporaryDesktopFullScreen
        )
        if transition.nextRestoreFrame != nil {
            onWillEnterTemporaryDesktopFullScreen?(frame)
        }
        restoreFrameAfterTemporaryDesktopFullScreen = transition.nextRestoreFrame
        setFrame(transition.nextFrame, display: true, animate: true)
    }

    static func temporaryDesktopFullScreenTransition(
        currentFrame: NSRect,
        visibleFrame: NSRect,
        restoreFrame: NSRect?,
        fallbackFrame: NSRect?
    ) -> (nextFrame: NSRect, nextRestoreFrame: NSRect?) {
        if let restoreFrame {
            return (restoreFrame, nil)
        }
        if currentFrame.isApproximatelyEqual(to: visibleFrame), let fallbackFrame {
            return (fallbackFrame, nil)
        }
        return (visibleFrame, currentFrame)
    }

    static func temporaryDesktopFullScreenFallbackFrame(
        suitableFrame: NSRect,
        fixedRestoreFrame: NSRect?
    ) -> NSRect {
        fixedRestoreFrame ?? suitableFrame
    }

    func isTitleBarPoint(_ point: NSPoint) -> Bool {
        Self.isTitleBarPoint(
            point,
            contentLayoutRect: contentLayoutRect,
            styleMask: styleMask
        )
    }

    static func isTitleBarPoint(
        _ point: NSPoint,
        contentLayoutRect: NSRect,
        styleMask: NSWindow.StyleMask
    ) -> Bool {
        styleMask.contains(.titled) && !contentLayoutRect.contains(point)
    }

    private func isTitleBarEvent(_ event: NSEvent) -> Bool {
        isTitleBarPoint(event.locationInWindow)
    }
}

@MainActor
final class WindowManager {
    typealias AuthorizationRestorationScheduler = @MainActor (@escaping @MainActor @Sendable () -> Void) -> Void
    typealias ScreenGeometry = (visibleFrame: NSRect, backingScale: CGFloat)

    let updateChecker: UpdateChecker?
    private var updateRestoreObserver: AnyCancellable?
    private(set) var currentWindow: NSWindow?
    private(set) var currentViewModel: ImageViewerViewModel?
    private var pendingOpenURL: URL?
    private var isConfirmingReplacement = false
    private var sheetObserver: AnyCancellable?
    private var initialImageObserver: AnyCancellable?
    private var initialImageFailureObserver: AnyCancellable?
    private var automaticImageObserver: AnyCancellable?
    private var automaticSizePreferenceObserver: AnyCancellable?
    private var fileAccessObserver: AnyCancellable?
    private var applicationActivationObserver: AnyCancellable?
    private let loadingMode: ImageLoadingMode
    private let screenGeometryOverride: ScreenGeometry?
    private var titleObserver: AnyCancellable?
    private var appearanceObserver: AnyCancellable?
    private var keyEventMonitor: Any?
    private let finderOrderProvider: (any FinderFolderOrderProviding)?
    private let deletionConfirmation = ImageDeletionConfirmation()
    private let minimumWindowSize = NSSize(width: 320, height: 220)
    private var automaticSizingPausedByUser = false
    private var hasPresentedInitialImage = false
    private var automaticResizeRevision = 0
    private var isApplyingAutomaticFrame = false
    private var authorizationRestoreRevision = 0
    private let authorizationRestorationScheduler: AuthorizationRestorationScheduler
    private lazy var authorizationFocusRecovery = ViewerAuthorizationFocusRecovery { [weak self] window in
        self?.restoreViewerAfterAuthorization(window)
    }

    #if DEBUG
    func debugRestoreViewerAfterFolderConsent(_ window: NSWindow) {
        authorizationFocusRecovery.setFileAccessPending(true, for: window)
        authorizationFocusRecovery.applicationActivated(bundleIdentifier: "com.apple.UserNotificationCenter")
        authorizationFocusRecovery.setFileAccessPending(false, for: window)
    }
    #endif

    init(
        updateChecker: UpdateChecker? = UpdateChecker(bundleInfo: Bundle.main.infoDictionary ?? [:]),
        finderOrderProvider: (any FinderFolderOrderProviding)? = nil,
        loadingMode: ImageLoadingMode = .background,
        screenGeometryOverride: ScreenGeometry? = nil,
        authorizationRestorationScheduler: @escaping AuthorizationRestorationScheduler = { restore in
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { restore() }
        }
    ) {
        self.updateChecker = updateChecker
        self.loadingMode = loadingMode
        self.screenGeometryOverride = screenGeometryOverride
        self.finderOrderProvider = finderOrderProvider
        self.authorizationRestorationScheduler = authorizationRestorationScheduler
        applicationActivationObserver = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.authorizationFocusRecovery.applicationActivated(bundleIdentifier: application.bundleIdentifier)
            }
    }

    var hasOpenViewer: Bool {
        currentWindow != nil
    }

    func captureUpdateViewer() -> UpdateSession.Viewer? {
        guard let window = currentWindow, let model = currentViewModel else { return nil }
        return UpdateSession.Viewer(url: model.currentURL, frame: window.frame,
            zoom: model.zoomScale, pan: model.panOffset, rotation: model.rotationDegrees,
            fullScreen: window.styleMask.contains(.fullScreen),
            desktopFullScreen: (window as? ViewerWindow)?.isTemporaryDesktopFullScreenActive == true,
            minimized: window.isMiniaturized)
    }

    func restoreUpdateViewer(_ state: UpdateSession.Viewer, completion: @escaping @MainActor () -> Void = {}) {
        openViewer(for: state.url, presentsWindow: false)
        guard let window = currentWindow, let model = currentViewModel else { return }
        automaticSizingPausedByUser = true
        initialImageObserver = nil
        window.setFrame(state.frame, display: true)
        let restore: @MainActor @Sendable () -> Void = { [weak self, weak window, weak model] in
            guard let self, let window, let model, self.currentWindow === window,
                  model.currentURL == state.url else { return }
            window.setFrame(state.frame, display: true)
            model.zoomScale = state.zoom
            model.panOffset = state.pan
            model.rotationDegrees = state.rotation
            if state.fullScreen { window.toggleFullScreen(nil) }
            else if state.desktopFullScreen { (window as? ViewerWindow)?.toggleTemporaryDesktopFullScreen() }
            window.makeKeyAndOrderFront(nil)
            if state.minimized { window.miniaturize(nil) }
            self.updateRestoreObserver = nil
            completion()
        }
        if model.image != nil {
            DispatchQueue.main.async(execute: restore)
        } else {
            updateRestoreObserver = model.$isImageLoading.filter { !$0 }.first().sink { _ in
                DispatchQueue.main.async(execute: restore)
            }
        }
    }

    func openInExistingViewer(for url: URL) {
        guard let window = currentWindow, let viewModel = currentViewModel else {
            openViewer(for: url)
            return
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        bringViewerToFront(window)
        // Keep only the latest request while an export/deletion/confirmation sheet is open.
        pendingOpenURL = url
        guard window.attachedSheet == nil, !isConfirmingReplacement else { return }
        pendingOpenURL = nil
        if url.standardizedFileURL == viewModel.currentURL, viewModel.image != nil, !viewModel.isFolderEmpty {
            viewModel.openImage(url)
            return
        }
        guard viewModel.isScreenshotEditing else {
            viewModel.openImage(url)
            return
        }
        isConfirmingReplacement = true
        let alert = NSAlert()
        alert.messageText = L10n.text("放弃当前编辑并打开新图片？")
        alert.informativeText = L10n.text("当前截图和标注中尚未保存的内容将丢失。")
        alert.addButton(withTitle: L10n.text("放弃并打开"))
        alert.addButton(withTitle: L10n.text("取消"))
        LanguageSettings.bind(alert) {
            $0.messageText = L10n.text("放弃当前编辑并打开新图片？")
            $0.informativeText = L10n.text("当前截图和标注中尚未保存的内容将丢失。")
            $0.buttons[0].title = L10n.text("放弃并打开")
            $0.buttons[1].title = L10n.text("取消")
        }
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [weak self, weak viewModel] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn { viewModel?.openImage(url) }
            self.isConfirmingReplacement = false
            self.resumePendingOpen()
        }
    }

    private func resumePendingOpen() {
        // Sheets finish detaching after their completion callback.
        DispatchQueue.main.async { [weak self] in
            guard let self, let url = self.pendingOpenURL else { return }
            self.openInExistingViewer(for: url)
        }
    }

    func openViewer(for url: URL, presentsWindow: Bool = true) {
        guard currentWindow == nil else { return }

        let viewModel = ImageViewerViewModel(
            loadingMode: loadingMode,
            imageURL: url,
            finderOrderProvider: finderOrderProvider ?? FinderFolderOrderProvider(
                onAuthorizationPromptWillBegin: { [weak self] in
                    guard let self else { return }
                    self.authorizationFocusRecovery.begin(for: self.currentWindow)
                },
                onAuthorizationPromptFinished: { [weak self] in
                    self?.authorizationFocusRecovery.finish()
                }
            )
        )
        let deferInitialPresentation = viewModel.image == nil &&
            AutomaticWindowSizePreference.isEnabled() && !WindowFramePreference.isFixedEnabled()
        let titleBarVisible = ViewerTitleBarPreference.isVisible()
        let styleMask = ViewerTitleBarPreference.styleMask(titleBarVisible: titleBarVisible)
        let initialContentFrame = initialWindowContentFrame(for: viewModel.image, styleMask: styleMask)
        let suitableWindowFrame = NSWindow.frameRect(forContentRect: initialContentFrame, styleMask: styleMask)
        let initialWindowFrame = self.initialWindowFrame(
            contentFrame: initialContentFrame,
            styleMask: styleMask
        )
        let fixedRestoreFrame = temporaryDesktopFullScreenRestoreFrame(fitting: initialWindowFrame)
        let initialContentRect = NSWindow.contentRect(forFrameRect: initialWindowFrame, styleMask: styleMask)
        let window = ViewerWindow(
            contentRect: initialContentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        let rootView = ImageViewerView(
            viewModel: viewModel,
            updateChecker: updateChecker,
            onTitleBarVisibilityChanged: { [weak self, weak window, weak viewModel] visible in
                guard let self, let window else { return }
                self.applyTitleBarVisibility(visible, to: window)
                if let viewModel {
                    window.title = visible ? viewModel.titleBarText : viewModel.currentFilename
                }
            },
            onFixedWindowChanged: { [weak self, weak window] fixed in
                guard let self, let window else { return }
                self.applyFixedWindowState(fixed, to: window)
                if !fixed, let image = self.currentViewModel?.image {
                    self.automaticSizingPausedByUser = false
                    self.resizeWindowToImage(image, in: window)
                }
            },
            onRequestDeletion: { [weak self, weak window, weak viewModel] in
                guard let self, let window, let viewModel else { return }
                self.deletionConfirmation.requestDeletion(for: viewModel, in: window)
            },
            onToggleFullScreen: { [weak window, weak viewModel] in
                guard let window, let viewModel,
                      !viewModel.slideshow.isFullScreenTransitioning else { return }
                viewModel.slideshow.beginFullScreenTransition()
                window.toggleFullScreen(nil)
            },
            onCloseViewer: { [weak window] in window?.close() }
        )
        let hostingController = NSHostingController(rootView: rootView)

        window.pinningController = WindowPinningController(window: window)
        currentWindow = window
        currentViewModel = viewModel
        automaticSizingPausedByUser = false
        hasPresentedInitialImage = false
        sheetObserver = NotificationCenter.default.publisher(for: NSWindow.didEndSheetNotification, object: window)
            .sink { [weak self] _ in self?.resumePendingOpen() }
        appearanceObserver = ViewerPreferences.shared.$snapshot.map(\.theme).removeDuplicates()
            .sink { [weak window] theme in window?.appearance = theme.appearance }
        window.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
        titleObserver = viewModel.$currentURL
            .combineLatest(viewModel.$displayScale, viewModel.$image)
            .receive(on: RunLoop.main)
            .sink { [weak window, weak viewModel] _, _, _ in
                guard let window, let viewModel else { return }
                window.title = ViewerTitleBarPreference.isVisible() ? viewModel.titleBarText : viewModel.currentFilename
            }

        LanguageSettings.bind(window) { [weak viewModel] window in
            guard let viewModel else { return }
            window.title = ViewerTitleBarPreference.isVisible() ? viewModel.titleBarText : viewModel.currentFilename
        }
        window.title = titleBarVisible ? viewModel.titleBarText : viewModel.currentFilename
        window.isMovableByWindowBackground = false
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        if let appearance = ViewerTheme.current().appearance {
            window.appearance = appearance
        }
        window.fallbackFrameForTemporaryDesktopFullScreen = ViewerWindow.temporaryDesktopFullScreenFallbackFrame(
            suitableFrame: suitableWindowFrame,
            fixedRestoreFrame: fixedRestoreFrame
        )
        window.onWillEnterTemporaryDesktopFullScreen = { frame in
            if WindowFramePreference.isFixedEnabled() {
                WindowFramePreference.saveTemporaryDesktopFullScreenRestoreFrame(frame)
            }
        }
        window.hasShadow = titleBarVisible
        window.minSize = minimumWindowSize
        window.contentViewController = hostingController
        window.setFrame(initialWindowFrame, display: false)
        applyFixedWindowState(WindowFramePreference.isFixedEnabled(), to: window)
        automaticSizePreferenceObserver = ViewerPreferences.shared.$snapshot
            .map(\.automaticWindowSizeEnabled).removeDuplicates().dropFirst()
            .sink { [weak self, weak window, weak viewModel] enabled in
                guard let self, let window, let viewModel else { return }
                self.applyFixedWindowState(WindowFramePreference.isFixedEnabled(), to: window)
                if enabled, let image = viewModel.image {
                    self.automaticSizingPausedByUser = false
                    self.resizeWindowToImage(image, in: window)
                }
            }
        automaticImageObserver = viewModel.$image.compactMap { $0 }
            .sink { [weak self, weak window] image in
                let shouldAnimate = self?.hasPresentedInitialImage == true
                self?.hasPresentedInitialImage = true
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, let window, self.currentWindow === window else { return }
                    self.resizeWindowToImage(image, in: window, animate: shouldAnimate)
                    if deferInitialPresentation && !window.isVisible {
                        if presentsWindow { self.bringViewerToFront(window) }
                    }
                }
            }
        if deferInitialPresentation {
            initialImageFailureObserver = viewModel.$image.dropFirst()
                .filter { $0 == nil }.first()
                .sink { [weak self, weak window] _ in
                    DispatchQueue.main.async { [weak self, weak window] in
                        guard let self, let window, self.currentWindow === window,
                              !window.isVisible else { return }
                        if presentsWindow { self.bringViewerToFront(window) }
                    }
                }
        } else {
            if presentsWindow { bringViewerToFront(window) }
        }
        fileAccessObserver = viewModel.$isImageLoading.combineLatest(viewModel.$isNavigationOrderReady)
            .map { loading, ready in loading || !ready }
            .removeDuplicates()
            .sink { [weak self, weak window] pending in
                self?.authorizationFocusRecovery.setFileAccessPending(pending, for: window)
            }
        applyWindowShape(to: window, titleBarVisible: titleBarVisible)
        installKeyboardMonitor(for: viewModel)

        if viewModel.image == nil {
            initialImageObserver = viewModel.$image.compactMap { $0 }.first()
                .sink { [weak self, weak window] image in
                    DispatchQueue.main.async { [weak self, weak window] in
                        guard let self, let window, self.currentWindow === window,
                              window.frame == initialWindowFrame,
                              !AutomaticWindowSizePreference.isEnabled(),
                              !WindowFramePreference.isFixedEnabled(),
                              !window.styleMask.contains(.fullScreen) else { return }
                        let frame = self.initialWindowContentFrame(for: image, styleMask: window.styleMask)
                        let sized = self.initialWindowFrame(contentFrame: frame, styleMask: window.styleMask)
                        window.setFrame(sized, display: true)
                        window.fallbackFrameForTemporaryDesktopFullScreen = sized
                    }
                }
        }

        let delegate = WindowDelegate(
            onFrameChanged: { [weak self, weak window] in
                guard let self, let window else { return }
                self.saveWindowFrame(window)
            },
            onUserFrameChanged: { [weak self, weak window] in
                guard let self, let window, !self.isApplyingAutomaticFrame,
                      !window.isNativeFullScreenTransitionActive,
                      self.currentViewModel?.slideshow.isFullScreenTransitioning != true,
                      !window.styleMask.contains(.fullScreen),
                      !WindowFramePreference.isFixedEnabled(),
                      AutomaticWindowSizePreference.isEnabled() else { return }
                self.automaticSizingPausedByUser = true
            },
            onWindowResized: { [weak self, weak window] in
                guard let self, let window, !self.isApplyingAutomaticFrame,
                      !window.isNativeFullScreenTransitionActive,
                      self.currentViewModel?.slideshow.isFullScreenTransitioning != true,
                      NSApp.currentEvent?.type == .leftMouseDragged,
                      !window.styleMask.contains(.fullScreen),
                      !WindowFramePreference.isFixedEnabled(),
                      AutomaticWindowSizePreference.isEnabled() else { return }
                self.automaticSizingPausedByUser = true
            },
            onWindowMoved: { [weak self, weak window] in
                guard let self, let window, !self.isApplyingAutomaticFrame,
                      !window.isNativeFullScreenTransitionActive,
                      self.currentViewModel?.slideshow.isFullScreenTransitioning != true,
                      !window.styleMask.contains(.fullScreen),
                      !WindowFramePreference.isFixedEnabled(),
                      AutomaticWindowSizePreference.isEnabled() else { return }
                self.automaticSizingPausedByUser = true
            },
            onClose: { [weak self, weak window, weak viewModel] in
                viewModel?.slideshow.stop()
                if let self, let window {
                    self.saveWindowFrame(window)
                }
                self?.updateRestoreObserver = nil
                self?.initialImageObserver = nil
                self?.initialImageFailureObserver = nil
                self?.automaticImageObserver = nil
                self?.automaticSizePreferenceObserver = nil
                self?.fileAccessObserver = nil
                self?.authorizationFocusRecovery.setFileAccessPending(false, for: nil)
                self?.titleObserver = nil
                self?.appearanceObserver = nil
                if let monitor = self?.keyEventMonitor {
                    NSEvent.removeMonitor(monitor)
                    self?.keyEventMonitor = nil
                }
                self?.currentWindow = nil
                self?.currentViewModel = nil
                self?.sheetObserver = nil
                self?.pendingOpenURL = nil
                self?.isConfirmingReplacement = false
                self?.automaticSizingPausedByUser = false
                self?.hasPresentedInitialImage = false
                self?.automaticResizeRevision += 1
                self?.isApplyingAutomaticFrame = false
            },
            onExitFullScreen: { [weak self, weak window] in
                guard let self, let window else { return }
                self.restoreStyleMaskAfterFullScreen(to: window)
                // Navigation in full screen defers sizing until the normal frame is restored.
                if let image = self.currentViewModel?.image {
                    self.resizeWindowToImage(image, in: window)
                }
            },
            onFailToEnterFullScreen: { [weak window] in
                window?.restoreStyleMaskAfterFailedFullScreenEntry()
            },
            slideshow: viewModel.slideshow
        )
        window.delegate = delegate
        objc_setAssociatedObject(window, &Self.delegateAssociationKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private func initialWindowContentFrame(for image: NSImage?, styleMask: NSWindow.StyleMask) -> NSRect {
        guard let screen = screenGeometry(for: nil) else {
            return NSRect(x: 0, y: 0, width: 1000, height: 760)
        }

        let availableContentFrame = NSWindow.contentRect(forFrameRect: screen.visibleFrame, styleMask: styleMask)
        if AutomaticWindowSizePreference.isEnabled(), !WindowFramePreference.isFixedEnabled(),
           let image, let imageSize = ImageExporter.pixelSize(of: image),
           let frame = WindowPlacement.automaticFrame(for: imageSize, in: availableContentFrame,
                                                     backingScale: screen.backingScale) {
            return frame
        }
        return WindowPlacement.frame(for: image.flatMap { ImageExporter.pixelSize(of: $0) },
                                     in: availableContentFrame, backingScale: screen.backingScale)
    }

    private func screenGeometry(for window: NSWindow?) -> ScreenGeometry? {
        if let screenGeometryOverride { return screenGeometryOverride }
        guard let screen = window?.screen ?? NSScreen.main else { return nil }
        return (screen.visibleFrame, screen.backingScaleFactor)
    }

    private func resizeWindowToImage(_ image: NSImage, in window: NSWindow, animate: Bool = true) {
        guard AutomaticWindowSizePreference.isEnabled(),
              !WindowFramePreference.isFixedEnabled(), !automaticSizingPausedByUser,
              (window as? ViewerWindow)?.isNativeFullScreenTransitionActive != true,
              !window.styleMask.contains(.fullScreen), window.attachedSheet == nil,
              (window as? ViewerWindow)?.isTemporaryDesktopFullScreenActive != true,
              currentViewModel?.isScreenshotEditing != true,
              let screen = screenGeometry(for: window),
              let imageSize = currentViewModel?.imagePixelSize ?? ImageExporter.pixelSize(of: image) else { return }
        let availableContentFrame = NSWindow.contentRect(forFrameRect: screen.visibleFrame, styleMask: window.styleMask)
        guard let contentFrame = WindowPlacement.automaticFrame(for: imageSize, in: availableContentFrame,
                                                               backingScale: screen.backingScale) else { return }
        let targetSize = NSWindow.frameRect(forContentRect: contentFrame, styleMask: window.styleMask).size
        let centered = NSRect(x: window.frame.midX - targetSize.width / 2,
                              y: window.frame.midY - targetSize.height / 2,
                              width: targetSize.width, height: targetSize.height)
        let target = WindowResizeGeometry.clamped(centered, to: screen.visibleFrame,
                                                  minimumSize: automaticMinimumWindowSize(for: window.styleMask))
        guard !window.frame.isApproximatelyEqual(to: target) else { return }
        automaticResizeRevision += 1
        let revision = automaticResizeRevision
        isApplyingAutomaticFrame = true
        let shouldAnimate = animate && AutomaticWindowResizeAnimationPreference.isEnabled() &&
            window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let viewerWindow = window as? ViewerWindow
        viewerWindow?.automaticImageResizeTarget = shouldAnimate ? target : nil
        window.setFrame(target, display: true, animate: shouldAnimate)
        viewerWindow?.fallbackFrameForTemporaryDesktopFullScreen = target
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) { [weak self, weak viewerWindow] in
            guard let self, self.automaticResizeRevision == revision else { return }
            self.isApplyingAutomaticFrame = false
            viewerWindow?.automaticImageResizeTarget = nil
        }
    }

    private func automaticMinimumWindowSize(for styleMask: NSWindow.StyleMask) -> NSSize {
        NSWindow.frameRect(forContentRect: NSRect(origin: .zero,
            size: WindowPlacement.minimumAutomaticContentSize), styleMask: styleMask).size
    }

    func captureFixedWindowFrame() {
        guard let window = currentWindow as? ViewerWindow,
              let frame = window.persistableFrame else { return }
        WindowFramePreference.saveFixedFrame(frame)
    }

    private func initialWindowFrame(contentFrame: NSRect, styleMask: NSWindow.StyleMask) -> NSRect {
        let defaultFrame = NSWindow.frameRect(forContentRect: contentFrame, styleMask: styleMask)
        guard let screen = NSScreen.main else { return defaultFrame }
        if let fixedFrame = WindowFramePreference.fixedFrame(
            fitting: screen.visibleFrame,
            minimumSize: minimumWindowSize
        ) {
            return fixedFrame
        }
        return defaultFrame
    }

    private func temporaryDesktopFullScreenRestoreFrame(fitting fallbackScreenFrame: NSRect) -> NSRect? {
        let screenFrame = NSScreen.main?.visibleFrame ?? fallbackScreenFrame
        return WindowFramePreference.temporaryDesktopFullScreenRestoreFrame(
            fitting: screenFrame,
            minimumSize: minimumWindowSize
        )
    }

    private func saveWindowFrame(_ window: ViewerWindow) {
        guard let frame = window.persistableFrame else { return }
        WindowFramePreference.save(frame)
        if WindowFramePreference.isFixedEnabled() {
            WindowFramePreference.saveFixedFrame(frame)
        }
    }

    private static var delegateAssociationKey: UInt8 = 0

    private func restoreViewerAfterAuthorization(_ window: NSWindow) {
        authorizationRestoreRevision += 1
        let revision = authorizationRestoreRevision
        // A file read resumes before the permission dismissal animation and
        // initial image/window sizing finish. Give both time to settle, then
        // restore only if the system has not already returned focus itself.
        authorizationRestorationScheduler { [weak self, weak window] in
            guard let self, self.authorizationRestoreRevision == revision,
                  let window, ViewerAuthorizationFocusRecovery.canRestore(window) else { return }
            guard !NSApp.isActive || !window.isKeyWindow else { return }
            if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func bringViewerToFront(_ window: NSWindow) {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.orderFrontRegardless()
        window.makeKey()

        DispatchQueue.main.async { [weak window] in
            guard let window, ViewerAuthorizationFocusRecovery.canRestore(window) else { return }
            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            window.orderFrontRegardless()
            window.makeKey()
        }
    }

    private func applyRoundedCorners(to window: NSWindow) {
        guard let frameView = window.contentView?.superview else { return }
        frameView.wantsLayer = true
        frameView.layer?.cornerRadius = 10
        frameView.layer?.masksToBounds = true
    }

    private func applyTitleBarVisibility(_ visible: Bool, to window: NSWindow) {
        let isFull = window.styleMask.contains(.fullScreen)
        if !isFull {
            let frame = window.frame
            window.styleMask = ViewerTitleBarPreference.styleMask(titleBarVisible: visible)
            window.setFrame(frame, display: true)
        }
        (window as? ViewerWindow)?.pinningController?.apply()
        applyWindowShape(to: window, titleBarVisible: visible)
        if !isFull {
            applyFixedWindowState(WindowFramePreference.isFixedEnabled(), to: window)
        }
    }

    private func applyFixedWindowState(_ fixed: Bool, to window: NSWindow) {
        if fixed {
            window.minSize = window.frame.size
            window.maxSize = window.frame.size
        } else {
            window.minSize = AutomaticWindowSizePreference.isEnabled()
                ? automaticMinimumWindowSize(for: window.styleMask) : minimumWindowSize
            window.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }

    private func applyWindowShape(to window: NSWindow, titleBarVisible: Bool) {
        window.hasShadow = titleBarVisible
        if titleBarVisible {
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            if let frameView = window.contentView?.superview {
                frameView.layer?.cornerRadius = 0
                frameView.layer?.masksToBounds = false
            }
        } else {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            if !window.styleMask.contains(.fullScreen) {
                applyRoundedCorners(to: window)
            }
        }
    }

    private func restoreStyleMaskAfterFullScreen(to window: NSWindow) {
        let titleBarVisible = ViewerTitleBarPreference.isVisible()
        let preferredStyleMask = ViewerTitleBarPreference.styleMask(titleBarVisible: titleBarVisible)
        let fallbackFrame = window.frame
        let restoredCapturedFrame = (window as? ViewerWindow)?
            .completeNativeFullScreenExit(restoring: preferredStyleMask) ?? false

        if !restoredCapturedFrame {
            window.styleMask = preferredStyleMask
            window.setFrame(fallbackFrame, display: true)
        }

        applyWindowShape(to: window, titleBarVisible: titleBarVisible)
        applyFixedWindowState(WindowFramePreference.isFixedEnabled(), to: window)
    }

    private func installKeyboardMonitor(for viewModel: ImageViewerViewModel) {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak viewModel] event in
            guard let self, let window = self.currentWindow, NSApp.keyWindow === window, window.attachedSheet == nil, viewModel?.isScreenshotEditing != true else {
                return event
            }
            if window.firstResponder is NSTextView { return event }
            if event.keyCode == 53, viewModel?.slideshow.isFullScreenTransitioning == true { return nil }
            switch KeyboardNavigation.action(
                for: event.keyCode,
                modifiers: event.modifierFlags,
                isRepeat: event.isARepeat,
                slideshowActive: viewModel?.slideshow.isActive == true,
                isFullScreen: window.styleMask.contains(.fullScreen)
                    || (window as? ViewerWindow)?.isTemporaryDesktopFullScreenActive == true
            ) {
            case .trash:
                if let viewModel {
                    self.deletionConfirmation.requestDeletion(for: viewModel, in: window)
                }
                return nil
            case .undoDeletion:
                guard viewModel?.canUndoDeletion == true else { return event }
                viewModel?.undoDeletion()
                return nil
            case .previous:
                viewModel?.navigateToPrevious()
                return nil
            case .next:
                viewModel?.navigateToNext()
                return nil
            case .rotateLeft:
                guard viewModel?.image != nil else { return event }
                viewModel?.rotateLeft()
                return nil
            case .rotateRight:
                guard viewModel?.image != nil else { return event }
                viewModel?.rotateRight()
                return nil
            case .toggleSlideshowPause:
                viewModel?.slideshow.togglePause()
                return nil
            case .endSlideshow:
                viewModel?.slideshow.stop()
                return nil
            case .exitFullScreen:
                guard viewModel?.slideshow.isFullScreenTransitioning != true else { return nil }
                if let viewerWindow = window as? ViewerWindow, viewerWindow.isTemporaryDesktopFullScreenActive {
                    viewerWindow.toggleTemporaryDesktopFullScreen()
                } else {
                    viewModel?.slideshow.beginFullScreenTransition()
                    window.toggleFullScreen(nil)
                }
                return nil
            case .quit:
                window.close()
                return nil
            case .toggleFullScreen:
                guard let viewModel, !viewModel.slideshow.isFullScreenTransitioning else { return nil }
                viewModel.slideshow.beginFullScreenTransition()
                window.toggleFullScreen(nil)
                return nil
            case .toggleImageParameters:
                NotificationCenter.default.post(name: ViewerOverlayPreference.toggleImageParametersNotification, object: window)
                return nil
            case .printImage:
                guard let viewModel, let image = viewModel.image else { return event }
                viewModel.slideshow.pause()
                ImagePrinter.present(image: image, rotationDegrees: viewModel.rotationDegrees,
                                     title: viewModel.currentURL.lastPathComponent, in: window)
                return nil
            case .screenshot:
                NotificationCenter.default.post(name: ViewerOverlayPreference.beginScreenshotNotification, object: window)
                return nil
            case .none:
                return event
            }
        }
    }
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
    private let onFrameChanged: () -> Void
    private let onUserFrameChanged: () -> Void
    private let onWindowResized: () -> Void
    private let onWindowMoved: () -> Void
    private let onClose: () -> Void
    private let onExitFullScreen: () -> Void
    private let onFailToEnterFullScreen: () -> Void
    private weak var slideshow: SlideshowController?

    init(
        onFrameChanged: @escaping () -> Void,
        onUserFrameChanged: @escaping () -> Void,
        onWindowResized: @escaping () -> Void,
        onWindowMoved: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onExitFullScreen: @escaping () -> Void,
        onFailToEnterFullScreen: @escaping () -> Void,
        slideshow: SlideshowController
    ) {
        self.onFrameChanged = onFrameChanged
        self.onUserFrameChanged = onUserFrameChanged
        self.onWindowResized = onWindowResized
        self.onWindowMoved = onWindowMoved
        self.onClose = onClose
        self.onExitFullScreen = onExitFullScreen
        self.onFailToEnterFullScreen = onFailToEnterFullScreen
        self.slideshow = slideshow
    }

    func windowDidMove(_ notification: Notification) {
        onFrameChanged()
    }

    func windowWillMove(_ notification: Notification) {
        onWindowMoved()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        onFrameChanged()
        onUserFrameChanged()
    }

    func windowDidResize(_ notification: Notification) {
        onFrameChanged()
        onWindowResized()
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        (notification.object as? ViewerWindow)?.pinningController?.setFullScreenActive(true)
        slideshow?.beginFullScreenTransition()
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        slideshow?.beginFullScreenTransition()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        NotificationCenter.default.post(name: ViewerOverlayPreference.didEnterFullScreenNotification, object: nil)
        slideshow?.endFullScreenTransition()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        NotificationCenter.default.post(name: ViewerOverlayPreference.didExitFullScreenNotification, object: nil)
        onExitFullScreen()
        (notification.object as? ViewerWindow)?.pinningController?.setFullScreenActive(false)
        slideshow?.endFullScreenTransition()
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        onFailToEnterFullScreen()
        (window as? ViewerWindow)?.pinningController?.setFullScreenActive(false)
        slideshow?.endFullScreenTransition()
    }

    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        slideshow?.endFullScreenTransition()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private extension NSRect {
    func isApproximatelyEqual(to other: NSRect, tolerance: CGFloat = 1) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
