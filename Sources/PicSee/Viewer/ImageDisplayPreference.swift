import Foundation

enum ImageDisplayMode: String, CaseIterable, Sendable {
    case fitWindow
    case fitWidth
    case actualSize

    var displayName: String {
        switch self {
        case .fitWindow: L10n.text("适合窗口")
        case .fitWidth: L10n.text("适合宽度")
        case .actualSize: L10n.text("原始尺寸（100%）")
        }
    }
}

enum ImageDisplayPreference {
    static let defaultsKey = "PicSee.DefaultImageDisplayMode"

    static func mode(in defaults: UserDefaults = .standard) -> ImageDisplayMode {
        defaults.string(forKey: defaultsKey).flatMap(ImageDisplayMode.init(rawValue:)) ?? .fitWindow
    }

    static func setMode(_ mode: ImageDisplayMode, in defaults: UserDefaults = .standard) {
        guard mode != self.mode(in: defaults) else { return }
        defaults.set(mode.rawValue, forKey: defaultsKey)
        ViewerPreferenceChange.post(in: defaults)
    }
}
