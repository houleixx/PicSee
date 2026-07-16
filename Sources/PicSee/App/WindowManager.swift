import AppKit
import Combine
import ObjectiveC
import SwiftUI

final class ViewerWindow: NSWindow {
    private var restoreFrameAfterTemporaryDesktopFullScreen: NSRect?
    var fallbackFrameForTemporaryDesktopFullScreen: NSRect?
    var onWillEnterTemporaryDesktopFullScreen: ((NSRect) -> Void)?
    var fullScreenPreMask: NSWindow.StyleMask?
    var preFullScreenFrame: NSRect?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

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
        guard fullScreenPreMask == nil else { return }
        prepareStyleMaskForNativeFullScreen()
        super.toggleFullScreen(sender)
    }

    func prepareStyleMaskForNativeFullScreen() {
        guard fullScreenPreMask == nil else { return }
        fullScreenPreMask = styleMask
        preFullScreenFrame = frame
        styleMask = [.titled, .closable, .miniaturizable, .resizable]
    }

    func restoreStyleMaskAfterFailedFullScreenEntry() {
        guard let fullScreenPreMask else { return }
        styleMask = fullScreenPreMask
        self.fullScreenPreMask = nil
        preFullScreenFrame = nil
    }

    func completeNativeFullScreenExit() {
        fullScreenPreMask = nil
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
    private var currentWindow: NSWindow?
    private var titleObserver: AnyCancellable?
    private var keyEventMonitor: Any?
    private let minimumWindowSize = NSSize(width: 320, height: 220)

    var hasOpenViewer: Bool {
        currentWindow != nil
    }

    func openViewer(for url: URL) {
        guard currentWindow == nil else { return }

        let viewModel = ImageViewerViewModel(
            imageURL: url,
            finderOrderProvider: FinderFolderOrderProvider()
        )
        let updateChecker = UpdateChecker(bundleInfo: Bundle.main.infoDictionary ?? [:])
        let titleBarVisible = ViewerTitleBarPreference.isVisible()
        let initialContentFrame = initialWindowContentFrame(for: viewModel.image)
        let styleMask = ViewerTitleBarPreference.styleMask(titleBarVisible: titleBarVisible)
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
                if fixed {
                    WindowFramePreference.saveFixedFrame(window.frame)
                }
                self.applyFixedWindowState(fixed, to: window)
            }
        )
        let hostingController = NSHostingController(rootView: rootView)

        currentWindow = window
        window.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
        titleObserver = viewModel.$currentURL
            .combineLatest(viewModel.$displayScale, viewModel.$image)
            .sink { [weak window, weak viewModel] _, _, _ in
                guard let window, let viewModel else { return }
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
        window.hasShadow = true
        window.minSize = minimumWindowSize
        window.contentViewController = hostingController
        window.setFrame(initialWindowFrame, display: false)
        applyFixedWindowState(WindowFramePreference.isFixedEnabled(), to: window)
        bringViewerToFront(window)
        applyWindowShape(to: window, titleBarVisible: titleBarVisible)
        installKeyboardMonitor(for: viewModel)

        let delegate = WindowDelegate(
            onFrameChanged: { [weak window] in
                guard let window else { return }
                WindowFramePreference.save(window.frame)
                if WindowFramePreference.isFixedEnabled() {
                    WindowFramePreference.saveFixedFrame(window.frame)
                }
            },
            onClose: { [weak self] in
                self?.titleObserver = nil
                if let monitor = self?.keyEventMonitor {
                    NSEvent.removeMonitor(monitor)
                    self?.keyEventMonitor = nil
                }
                self?.currentWindow = nil
            },
            onExitFullScreen: { [weak self, weak window] in
                guard let window else { return }
                self?.restoreStyleMaskAfterFullScreen(to: window)
            },
            onFailToEnterFullScreen: { [weak window] in
                window?.restoreStyleMaskAfterFailedFullScreenEntry()
            }
        )
        window.delegate = delegate
        objc_setAssociatedObject(window, &Self.delegateAssociationKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private func initialWindowContentFrame(for image: NSImage?) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 1000, height: 760)
        }

        return WindowPlacement.frame(for: image?.size, in: screen.frame)
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

    private static var delegateAssociationKey: UInt8 = 0

    private func bringViewerToFront(_ window: NSWindow) {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.orderFrontRegardless()
        window.makeKey()

        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
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
            window.minSize = minimumWindowSize
            window.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }

    private func applyWindowShape(to window: NSWindow, titleBarVisible: Bool) {
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
        guard let viewerWindow = window as? ViewerWindow,
              let originalFrame = viewerWindow.preFullScreenFrame,
              viewerWindow.fullScreenPreMask != nil
        else {
            let frame = window.frame
            window.styleMask = ViewerTitleBarPreference.styleMask(titleBarVisible: titleBarVisible)
            window.setFrame(frame, display: true)
            applyWindowShape(to: window, titleBarVisible: titleBarVisible)
            applyFixedWindowState(WindowFramePreference.isFixedEnabled(), to: window)
            (window as? ViewerWindow)?.completeNativeFullScreenExit()
            return
        }

        window.styleMask = ViewerTitleBarPreference.styleMask(titleBarVisible: titleBarVisible)
        window.setFrame(originalFrame, display: true)
        applyWindowShape(to: window, titleBarVisible: titleBarVisible)
        applyFixedWindowState(WindowFramePreference.isFixedEnabled(), to: window)
        viewerWindow.completeNativeFullScreenExit()
        viewerWindow.preFullScreenFrame = nil
    }

    private func installKeyboardMonitor(for viewModel: ImageViewerViewModel) {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak viewModel] event in
            guard let self, let window = self.currentWindow, NSApp.keyWindow === window else {
                return event
            }
            switch KeyboardNavigation.action(for: event.keyCode) {
            case .previous:
                viewModel?.navigateToPrevious()
                return nil
            case .next:
                viewModel?.navigateToNext()
                return nil
            case .quit:
                NSApp.terminate(nil)
                return nil
            case .toggleImageParameters:
                NotificationCenter.default.post(name: ViewerOverlayPreference.toggleImageParametersNotification, object: window)
                return nil
            case .none:
                return event
            }
        }
    }
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
    private let onFrameChanged: () -> Void
    private let onClose: () -> Void
    private let onExitFullScreen: () -> Void
    private let onFailToEnterFullScreen: () -> Void

    init(
        onFrameChanged: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onExitFullScreen: @escaping () -> Void,
        onFailToEnterFullScreen: @escaping () -> Void
    ) {
        self.onFrameChanged = onFrameChanged
        self.onClose = onClose
        self.onExitFullScreen = onExitFullScreen
        self.onFailToEnterFullScreen = onFailToEnterFullScreen
    }

    func windowDidMove(_ notification: Notification) {
        onFrameChanged()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        onFrameChanged()
    }

    func windowDidResize(_ notification: Notification) {
        onFrameChanged()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        NotificationCenter.default.post(name: ViewerOverlayPreference.didEnterFullScreenNotification, object: nil)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        NotificationCenter.default.post(name: ViewerOverlayPreference.didExitFullScreenNotification, object: nil)
        onExitFullScreen()
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        onFailToEnterFullScreen()
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
