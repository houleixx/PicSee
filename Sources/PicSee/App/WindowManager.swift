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

        let window = NSWindow(
            contentRect: initialWindowFrame(for: viewModel.image),
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
        window.isMovableByWindowBackground = false
        window.backgroundColor = .black
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentViewController = hostingController
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

        let visibleFrame = screen.visibleFrame
        let maxWidth = visibleFrame.width * 0.86
        let maxHeight = visibleFrame.height * 0.86
        let fallbackSize = NSSize(width: min(1000, maxWidth), height: min(760, maxHeight))
        let imageSize = image?.size ?? fallbackSize
        let imageAspect = max(0.1, imageSize.width / max(1, imageSize.height))
        var width = maxWidth
        var height = width / imageAspect

        if height > maxHeight {
            height = maxHeight
            width = height * imageAspect
        }

        width = max(360, min(width, maxWidth))
        height = max(260, min(height, maxHeight))

        return NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
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
