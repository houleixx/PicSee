import AppKit
import Combine
import ObjectiveC
import SwiftUI

@MainActor
final class WindowManager {
    private var currentWindow: NSWindow?
    private var titleObserver: AnyCancellable?

    var hasOpenViewer: Bool {
        currentWindow != nil
    }

    func openViewer(for url: URL) {
        guard currentWindow == nil else { return }

        let viewModel = ImageViewerViewModel(imageURL: url)
        let rootView = ImageViewerView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)

        let initialFrame = initialWindowFrame(for: viewModel.image)
        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        currentWindow = window
        titleObserver = viewModel.$currentURL
            .sink { [weak window] url in
                window?.title = url.lastPathComponent
            }

        window.title = viewModel.currentFilename
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentViewController = hostingController
        window.setFrame(initialFrame, display: false)
        window.makeKeyAndOrderFront(nil)

        let delegate = WindowDelegate(onClose: { [weak self] in
            self?.titleObserver = nil
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
