import AppKit
import OSLog

/// Remembers only the window that initiated an interactive authorization request.
@MainActor
final class ViewerAuthorizationFocusRecovery {
    private(set) var restorationRevision = 0
    private weak var window: NSWindow?
    private weak var fileAccessWindow: NSWindow?
    private var fileAccessPending = false
    private var fileAccessHadPrompt = false
    private weak var recentlyRestoredWindow: NSWindow?
    private var handoffDeadline: TimeInterval = 0
    private let uptime: () -> TimeInterval
    private let bringToFront: (NSWindow) -> Void
    private static let logger = Logger(subsystem: "local.picsee.viewer", category: "AuthorizationFocus")

    init(uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         bringToFront: @escaping (NSWindow) -> Void) {
        self.uptime = uptime
        self.bringToFront = bringToFront
    }

    func begin(for window: NSWindow?) {
        recentlyRestoredWindow = nil
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
        restoreAfterConsent(requestedWindow)
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
        restoreAfterConsent(requestedWindow)
    }

    private func restoreAfterConsent(_ window: NSWindow) {
        // The authorization API may finish before the system activates Finder
        // while dismissing its prompt. Permit one late handoff, for a short time.
        recentlyRestoredWindow = window
        handoffDeadline = uptime() + 1
        bringToFront(window)
    }

    func applicationActivated(bundleIdentifier: String?) {
        guard let bundleIdentifier else { return }
        if bundleIdentifier == "com.apple.UserNotificationCenter" || bundleIdentifier == "com.apple.SecurityAgent" {
            if fileAccessPending, fileAccessWindow != nil { fileAccessHadPrompt = true }
        } else if bundleIdentifier == "com.apple.finder" {
            let restoredWindow = recentlyRestoredWindow
            recentlyRestoredWindow = nil
            guard uptime() <= handoffDeadline, let restoredWindow,
                  Self.canRestore(restoredWindow) else { return }
            bringToFront(restoredWindow)
        } else if bundleIdentifier != Bundle.main.bundleIdentifier {
            // A deliberate switch to another application takes precedence over
            // both in-flight consent and its deferred system handoff.
            restorationRevision += 1
            window = nil
            fileAccessWindow = nil
            fileAccessHadPrompt = false
            recentlyRestoredWindow = nil
        }
    }

    static func canRestore(_ window: NSWindow) -> Bool {
        window.isVisible && !window.isMiniaturized && window.isOnActiveSpace && !NSApp.isHidden
    }
}
