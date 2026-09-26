import AppKit
import Combine

/// One persisted preference shared by every viewer process and both UI entry points.
enum WindowPinningPreference {
    static let defaultsKey = "PicSee.WindowAlwaysOnTop"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        guard enabled != isEnabled(in: defaults) else { return }
        defaults.set(enabled, forKey: defaultsKey)
        ViewerPreferenceChange.post(in: defaults)
    }
}

/// Changes stacking only: never activates the app, grabs focus, or changes Spaces.
@MainActor
final class WindowPinningController {
    enum Role { case viewer, settings }

    private weak var window: NSWindow?
    private let role: Role
    private var enabled: Bool
    private var isFullScreenActive = false
    private var observations = Set<AnyCancellable>()
    private weak var trackedSheet: NSWindow?
    private var originalSheetLevel: NSWindow.Level?

    init(window: NSWindow, role: Role = .viewer, preferences: ViewerPreferences = .shared) {
        self.window = window
        self.role = role
        self.enabled = preferences.snapshot.alwaysOnTopEnabled
        preferences.$snapshot.map(\.alwaysOnTopEnabled).removeDuplicates()
            .sink { [weak self] enabled in
                self?.enabled = enabled
                self?.apply()
            }
            .store(in: &observations)
        for name in [NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification] {
            NotificationCenter.default.publisher(for: name, object: window)
                .sink { [weak self] _ in
                    // The sheet is attached/detached after the notification is delivered.
                    DispatchQueue.main.async { [weak self] in self?.apply() }
                }
                .store(in: &observations)
        }
    }

    func setFullScreenActive(_ active: Bool) {
        isFullScreenActive = active
        apply()
    }

    func apply() {
        guard let window else { return }
        let pinned = enabled && !isFullScreenActive && !window.styleMask.contains(.fullScreen)
        let level: NSWindow.Level = pinned
            ? (role == .viewer ? .floating : NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1))
            : .normal
        if window.level != level { window.level = level }

        let sheet = window.attachedSheet
        if sheet !== trackedSheet {
            if let trackedSheet, let originalSheetLevel { trackedSheet.level = originalSheetLevel }
            trackedSheet = sheet
            originalSheetLevel = sheet?.level
        }
        if let sheet, let originalSheetLevel {
            sheet.level = pinned
                ? NSWindow.Level(rawValue: max(originalSheetLevel.rawValue, NSWindow.Level.floating.rawValue + 2))
                : originalSheetLevel
        }
    }
}
