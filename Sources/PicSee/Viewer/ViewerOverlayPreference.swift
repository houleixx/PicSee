import Foundation

enum ViewerOverlayPreference {
    static let minimapEnabledDefaultsKey = "PicSee.MinimapEnabled"
    static let fileInfoVisibleDefaultsKey = "PicSee.FileInfoVisible"
    static let toolbarVisibleDefaultsKey = "PicSee.ToolbarVisible"
    static let imageParametersVisibleDefaultsKey = "PicSee.ImageParametersVisible"
    static let toggleImageParametersNotification = Notification.Name("PicSee.ToggleImageParameters")
    static let beginScreenshotNotification = Notification.Name("PicSee.BeginScreenshot")
    static let didEnterFullScreenNotification = Notification.Name("PicSee.DidEnterFullScreen")
    static let didExitFullScreenNotification = Notification.Name("PicSee.DidExitFullScreen")

    static func isFileInfoVisible(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: fileInfoVisibleDefaultsKey) as? Bool ?? true
    }

    static func setFileInfoVisible(_ visible: Bool, in defaults: UserDefaults = .standard) {
        guard visible != isFileInfoVisible(in: defaults) else { return }
        defaults.set(visible, forKey: fileInfoVisibleDefaultsKey)
        ViewerPreferenceChange.post(in: defaults)
    }

    static func isToolbarVisible(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: toolbarVisibleDefaultsKey) as? Bool ?? true
    }

    static func setToolbarVisible(_ visible: Bool, in defaults: UserDefaults = .standard) {
        guard visible != isToolbarVisible(in: defaults) else { return }
        defaults.set(visible, forKey: toolbarVisibleDefaultsKey)
        ViewerPreferenceChange.post(in: defaults)
    }

    static func isImageParametersVisible(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: imageParametersVisibleDefaultsKey) as? Bool ?? false
    }

    static func setImageParametersVisible(_ visible: Bool, in defaults: UserDefaults = .standard) {
        guard visible != isImageParametersVisible(in: defaults) else { return }
        defaults.set(visible, forKey: imageParametersVisibleDefaultsKey)
        ViewerPreferenceChange.post(in: defaults)
    }

    static func isMinimapEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: minimapEnabledDefaultsKey) as? Bool ?? true
    }

    static func setMinimapEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        guard enabled != isMinimapEnabled(in: defaults) else { return }
        defaults.set(enabled, forKey: minimapEnabledDefaultsKey)
        ViewerPreferenceChange.post(in: defaults)
    }
}
