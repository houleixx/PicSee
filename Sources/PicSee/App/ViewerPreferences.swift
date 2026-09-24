import AppKit
import Combine

/// The existing preference keys remain the source of truth for every entry point.
enum ViewerPreferenceChange {
    static let notification = Notification.Name("PicSee.ViewerPreferencesChanged")
    static let distributedNotification = Notification.Name("local.picsee.viewer.preferencesChanged")

    static func post(in defaults: UserDefaults) {
        NotificationCenter.default.post(name: notification, object: defaults)
        if defaults === UserDefaults.standard {
            // Each image can live in a separate PicSee process.
            defaults.synchronize()
            DistributedNotificationCenter.default().postNotificationName(
                distributedNotification, object: nil, userInfo: nil, deliverImmediately: true
            )
        }
    }
}

struct ViewerPreferencesSnapshot: Equatable {
    var theme: ViewerTheme
    var titleBarVisible: Bool
    var minimapEnabled: Bool
    var fileInfoVisible: Bool
    var toolbarVisible: Bool
    var imageParametersVisible: Bool
    var fixedWindowEnabled: Bool

    init(defaults: UserDefaults) {
        theme = ViewerTheme.current(in: defaults)
        titleBarVisible = ViewerTitleBarPreference.isVisible(in: defaults)
        minimapEnabled = ViewerOverlayPreference.isMinimapEnabled(in: defaults)
        fileInfoVisible = ViewerOverlayPreference.isFileInfoVisible(in: defaults)
        toolbarVisible = ViewerOverlayPreference.isToolbarVisible(in: defaults)
        imageParametersVisible = ViewerOverlayPreference.isImageParametersVisible(in: defaults)
        fixedWindowEnabled = WindowFramePreference.isFixedEnabled(in: defaults)
    }
}

@MainActor
final class ViewerPreferences: ObservableObject {
    static let shared = ViewerPreferences()

    @Published private(set) var snapshot: ViewerPreferencesSnapshot
    private let defaults: UserDefaults
    private var observations = Set<AnyCancellable>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snapshot = ViewerPreferencesSnapshot(defaults: defaults)
        NotificationCenter.default.publisher(for: ViewerPreferenceChange.notification, object: defaults)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.reload() }
            }
            .store(in: &observations)
        DistributedNotificationCenter.default().publisher(for: ViewerPreferenceChange.distributedNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.defaults.synchronize()
                    self?.reload()
                }
            }
            .store(in: &observations)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.reload() }
            }
            .store(in: &observations)
    }

    func reload() {
        let latest = ViewerPreferencesSnapshot(defaults: defaults)
        if latest != snapshot { snapshot = latest }
    }

    func setTheme(_ theme: ViewerTheme) {
        ViewerTheme.set(theme, in: defaults)
        reload()
    }

    func set(_ keyPath: WritableKeyPath<ViewerPreferencesSnapshot, Bool>, to value: Bool) {
        switch keyPath {
        case \.titleBarVisible: ViewerTitleBarPreference.setVisible(value, in: defaults)
        case \.minimapEnabled: ViewerOverlayPreference.setMinimapEnabled(value, in: defaults)
        case \.fileInfoVisible: ViewerOverlayPreference.setFileInfoVisible(value, in: defaults)
        case \.toolbarVisible: ViewerOverlayPreference.setToolbarVisible(value, in: defaults)
        case \.imageParametersVisible: ViewerOverlayPreference.setImageParametersVisible(value, in: defaults)
        case \.fixedWindowEnabled: WindowFramePreference.setFixedEnabled(value, in: defaults)
        default: preconditionFailure("Unknown viewer preference")
        }
        reload()
    }
}
