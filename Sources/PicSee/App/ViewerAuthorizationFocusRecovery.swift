import AppKit
import OSLog

/// Remembers only the window that initiated an interactive authorization request.
@MainActor
final class ViewerAuthorizationFocusRecovery {
    private weak var window: NSWindow?
    private weak var fileAccessWindow: NSWindow?
    private var fileAccessPending = false
    private var fileAccessHadPrompt = false
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

    /// Directory enumeration can trigger a Files and Folders consent dialog
    /// without passing through Finder's Apple Events authorization callback.
    func setFileAccessPending(_ pending: Bool, for window: NSWindow?) {
        if pending {
            guard !fileAccessPending else { return }
            fileAccessPending = true
            fileAccessHadPrompt = false
            fileAccessWindow = window.flatMap { Self.canRestore($0) ? $0 : nil }
            return
        }
        let requestedWindow = fileAccessWindow
        let shouldRestore = fileAccessHadPrompt
        fileAccessPending = false
        fileAccessHadPrompt = false
        fileAccessWindow = nil
        guard shouldRestore, let requestedWindow, requestedWindow === window,
              Self.canRestore(requestedWindow) else { return }
        Self.logger.notice("Restoring viewer after Files and Folders consent")
        bringToFront(requestedWindow)
    }

    func applicationActivated(bundleIdentifier: String?) {
        guard fileAccessPending, fileAccessWindow != nil, let bundleIdentifier else { return }
        if bundleIdentifier == "com.apple.UserNotificationCenter" || bundleIdentifier == "com.apple.SecurityAgent" {
            fileAccessHadPrompt = true
        } else if bundleIdentifier != Bundle.main.bundleIdentifier && bundleIdentifier != "com.apple.finder" {
            // A deliberate switch to another application takes precedence over
            // returning from consent. Finder may be reactivated by the dialog.
            fileAccessWindow = nil
            fileAccessHadPrompt = false
        }
    }

    static func canRestore(_ window: NSWindow) -> Bool {
        window.isVisible && !window.isMiniaturized && window.isOnActiveSpace && !NSApp.isHidden
    }
}
