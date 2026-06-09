import Foundation

enum ViewerOverlayPreference {
    static let fileInfoVisibleDefaultsKey = "PicSee.FileInfoVisible"
    static let toolbarVisibleDefaultsKey = "PicSee.ToolbarVisible"
    static let imageParametersVisibleDefaultsKey = "PicSee.ImageParametersVisible"
    static let toggleImageParametersNotification = Notification.Name("PicSee.ToggleImageParameters")

    static func isFileInfoVisible(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: fileInfoVisibleDefaultsKey) as? Bool ?? true
    }

    static func setFileInfoVisible(_ visible: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(visible, forKey: fileInfoVisibleDefaultsKey)
    }

    static func isToolbarVisible(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: toolbarVisibleDefaultsKey) as? Bool ?? true
    }

    static func setToolbarVisible(_ visible: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(visible, forKey: toolbarVisibleDefaultsKey)
    }

    static func isImageParametersVisible(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: imageParametersVisibleDefaultsKey) as? Bool ?? false
    }

    static func setImageParametersVisible(_ visible: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(visible, forKey: imageParametersVisibleDefaultsKey)
    }
}
