import Foundation

enum ImageNavigationAnimationPreference {
    static let defaultsKey = "PicSee.ImageNavigationAnimationEnabled"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? true
    }

    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        guard enabled != isEnabled(in: defaults) else { return }
        defaults.set(enabled, forKey: defaultsKey)
        ViewerPreferenceChange.post(in: defaults)
    }
}
