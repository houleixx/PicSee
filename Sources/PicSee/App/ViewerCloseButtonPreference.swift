import Foundation

enum ViewerCloseButtonPreference {
    static let defaultsKey = "PicSee.CloseButtonOnLeft"

    static func isOnLeft(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? false
    }

    static func setOnLeft(_ onLeft: Bool, in defaults: UserDefaults = .standard) {
        guard onLeft != isOnLeft(in: defaults) else { return }
        defaults.set(onLeft, forKey: defaultsKey)
        ViewerPreferenceChange.post(in: defaults)
    }
}
