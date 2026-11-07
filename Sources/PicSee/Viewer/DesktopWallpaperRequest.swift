import AppKit
import Combine

/// Native full screen occupies a separate Space. Apply to the desktop only
/// after the exit has completed and the viewer's desktop is active.
@MainActor
final class DesktopWallpaperRequest {
    private weak var window: NSWindow?
    private var apply: (() -> Void)?
    private var cancel: ((Bool) -> Void)?
    private var didExitFullScreen = false
    private var observations: Set<AnyCancellable> = []

    func perform(in window: NSWindow, apply: @escaping () -> Void, cancel: @escaping (Bool) -> Void) {
        guard self.apply == nil else { return }
        guard window.styleMask.contains(.fullScreen) else {
            apply()
            return
        }
        self.window = window
        self.apply = apply
        self.cancel = cancel
        didExitFullScreen = false
        NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification, object: window)
            .sink { [weak self] _ in
                self?.didExitFullScreen = true
                self?.applyWhenDesktopIsReady()
            }
            .store(in: &observations)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in self?.applyWhenDesktopIsReady() }
            .store(in: &observations)
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: window)
            .sink { [weak self] _ in self?.finishCancellation(exitFailed: false) }
            .store(in: &observations)
        NotificationCenter.default.publisher(for: ViewerWindow.didFailToExitFullScreenNotification, object: window)
            .sink { [weak self] _ in self?.finishCancellation(exitFailed: true) }
            .store(in: &observations)
        window.toggleFullScreen(nil)
    }

    private func applyWhenDesktopIsReady() {
        guard didExitFullScreen, let window, !window.styleMask.contains(.fullScreen),
              window.isOnActiveSpace, let apply else { return }
        reset()
        apply()
    }

    private func finishCancellation(exitFailed: Bool) {
        let cancel = cancel
        reset()
        cancel?(exitFailed)
    }

    private func reset() {
        observations.removeAll()
        window = nil
        apply = nil
        cancel = nil
        didExitFullScreen = false
    }
}
