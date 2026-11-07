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

    // Stay above common floating panels, with room for our settings and sheets.
    private static let pinnedLevel = NSWindow.Level(rawValue: 50)

    static func prepareModalWindow(_ window: NSWindow, preferences: ViewerPreferences = .shared) {
        guard preferences.snapshot.alwaysOnTopEnabled else { return }
        window.level = NSWindow.Level(rawValue: max(window.level.rawValue, pinnedLevel.rawValue + 2))
    }

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
            ? (role == .viewer ? Self.pinnedLevel : NSWindow.Level(rawValue: Self.pinnedLevel.rawValue + 1))
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
                ? NSWindow.Level(rawValue: max(originalSheetLevel.rawValue, Self.pinnedLevel.rawValue + 2))
                : originalSheetLevel
        }
    }
}

extension NSAlert {
    @MainActor
    @discardableResult
    func runPicSeeModal(preferences: ViewerPreferences = .shared) -> NSApplication.ModalResponse {
        let modalWindow = window
        let originalLevel = modalWindow.level
        WindowPinningController.prepareModalWindow(modalWindow, preferences: preferences)
        // AppKit resets the level when entering its modal session. Apply it again
        // once the alert becomes key, after that reset has happened.
        let observation = NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification, object: modalWindow
        ).sink { _ in
            if modalWindow.level.rawValue < originalLevel.rawValue {
                modalWindow.level = originalLevel
            }
            WindowPinningController.prepareModalWindow(modalWindow, preferences: preferences)
        }
        // Becoming key can precede AppKit's modal-level reset, or be omitted
        // when another accessory app owns focus. Reapply inside the modal loop.
        RunLoop.main.perform(inModes: [.modalPanel]) {
            MainActor.assumeIsolated {
                guard NSApp.modalWindow === modalWindow else { return }
                modalWindow.level = NSWindow.Level(rawValue: max(modalWindow.level.rawValue, originalLevel.rawValue))
                WindowPinningController.prepareModalWindow(modalWindow, preferences: preferences)
            }
        }
        defer {
            observation.cancel()
            modalWindow.level = originalLevel
        }
        return runModal()
    }
}
