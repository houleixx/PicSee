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

    var hasOpenViewer: Bool {
        currentWindow != nil
    }

    func openViewer(for url: URL) {
        guard currentWindow == nil else { return }

        let viewModel = ImageViewerViewModel(imageURL: url)
        let rootView = ImageViewerView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)

        let initialFrame = initialWindowFrame(for: viewModel.image)
        let window = ViewerWindow(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        currentWindow = window
        titleObserver = viewModel.$currentURL
            .sink { [weak window] url in
                window?.title = url.lastPathComponent
            }

        window.title = viewModel.currentFilename
        window.isMovableByWindowBackground = false
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.contentViewController = hostingController
        window.setFrame(initialFrame, display: false)
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        applyRoundedCorners(to: window)
        installKeyboardMonitor(for: viewModel)

        let delegate = WindowDelegate(onClose: { [weak self] in
            self?.titleObserver = nil
            if let monitor = self?.keyEventMonitor {
                NSEvent.removeMonitor(monitor)
                self?.keyEventMonitor = nil
            }
            self?.currentWindow = nil
        })
        window.delegate = delegate
        objc_setAssociatedObject(window, &Self.delegateAssociationKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        NSApp.activate(ignoringOtherApps: true)
    }

    private func initialWindowFrame(for image: NSImage?) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 1000, height: 760)
        }

        return WindowPlacement.frame(for: image?.size, in: screen.frame)
    }

    private static var delegateAssociationKey: UInt8 = 0

    private func applyRoundedCorners(to window: NSWindow) {
        guard let frameView = window.contentView?.superview else { return }
        frameView.wantsLayer = true
        frameView.layer?.cornerRadius = 14
        frameView.layer?.masksToBounds = true
    }

    private func installKeyboardMonitor(for viewModel: ImageViewerViewModel) {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.currentWindow, NSApp.keyWindow === window else {
                return event
            }
            switch KeyboardNavigation.action(for: event.keyCode) {
            case .previous:
                viewModel.navigateToPrevious()
                return nil
            case .next:
                viewModel.navigateToNext()
                return nil
            case .quit:
                NSApp.terminate(nil)
                return nil
            case .none:
                return event
            }
        }
    }
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
