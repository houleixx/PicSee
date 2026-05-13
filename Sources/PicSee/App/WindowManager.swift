import AppKit
import ObjectiveC
import SwiftUI

@MainActor
final class WindowManager {
    private var windows: [ObjectIdentifier: NSWindow] = [:]

    func openViewer(for url: URL) {
        let viewModel = ImageViewerViewModel(imageURL: url)
        let rootView = ImageViewerView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        let identifier = ObjectIdentifier(window)
        windows[identifier] = window

        window.title = viewModel.currentFilename
        window.contentViewController = hostingController
        window.center()
        window.makeKeyAndOrderFront(nil)

        let delegate = WindowDelegate(onClose: { [weak self] in
            self?.windows.removeValue(forKey: identifier)
        })
        window.delegate = delegate
        objc_setAssociatedObject(window, &Self.delegateAssociationKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        NSApp.activate(ignoringOtherApps: true)
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
