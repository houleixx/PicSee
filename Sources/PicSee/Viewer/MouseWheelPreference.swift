import Foundation

enum MouseWheelBehavior: String, CaseIterable, Sendable {
    case zoom
    case scroll

    var displayName: String {
        switch self {
        case .zoom: L10n.text("缩放图片")
        case .scroll: L10n.text("上下滚动")
        }
    }
}

enum MouseWheelPreference {
    static let defaultsKey = "PicSee.MouseWheelBehavior"

    static func behavior(in defaults: UserDefaults = .standard) -> MouseWheelBehavior {
        defaults.string(forKey: defaultsKey).flatMap(MouseWheelBehavior.init(rawValue:)) ?? .zoom
    }

    static func setBehavior(_ behavior: MouseWheelBehavior, in defaults: UserDefaults = .standard) {
        guard behavior != self.behavior(in: defaults) else { return }
        defaults.set(behavior.rawValue, forKey: defaultsKey)
        ViewerPreferenceChange.post(in: defaults)
    }
}
