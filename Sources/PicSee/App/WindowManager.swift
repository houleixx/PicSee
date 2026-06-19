import AppKit
import Combine
import ObjectiveC
import SwiftUI

private final class ViewerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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

        let viewModel = ImageViewerViewModel(imageURL: url)
        let updateChecker = UpdateChecker(bundleInfo: Bundle.main.infoDictionary ?? [:])
        let titleBarVisible = ViewerTitleBarPreference.isVisible()
        let initialContentFrame = initialWindowContentFrame(for: viewModel.image)
        let styleMask = ViewerTitleBarPreference.styleMask(titleBarVisible: titleBarVisible)
        let initialWindowFrame = self.initialWindowFrame(
            contentFrame: initialContentFrame,
            styleMask: styleMask
        )
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
        let frame = window.frame
        window.styleMask = ViewerTitleBarPreference.styleMask(titleBarVisible: visible)
        window.setFrame(frame, display: true)
        applyWindowShape(to: window, titleBarVisible: visible)
        applyFixedWindowState(WindowFramePreference.isFixedEnabled(), to: window)
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
            applyRoundedCorners(to: window)
        }
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

    init(onFrameChanged: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onFrameChanged = onFrameChanged
        self.onClose = onClose
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

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
