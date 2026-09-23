import AppKit
import OSLog

/// Remembers only the window that initiated an interactive authorization request.
@MainActor
final class ViewerAuthorizationFocusRecovery {
    private weak var window: NSWindow?
    private let bringToFront: (NSWindow) -> Void
    private static let logger = Logger(subsystem: "local.picsee.viewer", category: "AuthorizationFocus")

    init(bringToFront: @escaping (NSWindow) -> Void) {
        self.bringToFront = bringToFront
    }

    func begin(for window: NSWindow?) {
        self.window = window.flatMap { Self.canRestore($0) ? $0 : nil }
        Self.logger.notice("Interactive authorization started: hasViewer=\(self.window != nil)")
    }

    func finish() {
        let requestedWindow = window
        window = nil
        guard let requestedWindow, Self.canRestore(requestedWindow) else {
            Self.logger.notice("Authorization finished without an eligible viewer to restore")
            return
        }
        Self.logger.notice("Restoring viewer after interactive authorization")
        bringToFront(requestedWindow)
    }

    static func canRestore(_ window: NSWindow) -> Bool {
        window.isVisible && !window.isMiniaturized && window.isOnActiveSpace && !NSApp.isHidden
    }
}
