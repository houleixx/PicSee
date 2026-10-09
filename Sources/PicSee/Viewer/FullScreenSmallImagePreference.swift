import Foundation

enum FullScreenSmallImageMode: String, CaseIterable, Sendable {
    case original
    case fitScreen
    case smart

    var displayName: String {
        switch self {
        case .original: L10n.text("原始尺寸（100%）")
        case .fitScreen: L10n.text("始终适应屏幕")
        case .smart: L10n.text("智能放大")
        }
    }

    func maximumPixelScale(isFullScreen: Bool, smartLimit: Double) -> CGFloat {
        guard isFullScreen else { return 1 }
        switch self {
        case .original: return 1
        case .fitScreen: return .infinity
        case .smart: return CGFloat(smartLimit)
        }
    }
}

enum FullScreenSmallImagePreference {
    static let modeKey = "PicSee.FullScreenSmallImageMode"
    static let maximumScaleKey = "PicSee.FullScreenSmallImageMaximumScale"
    static let scaleOptions: [Double] = [1.5, 2, 3, 4]

    static func mode(in defaults: UserDefaults = .standard) -> FullScreenSmallImageMode {
        defaults.string(forKey: modeKey).flatMap(FullScreenSmallImageMode.init(rawValue:)) ?? .original
    }

    static func maximumScale(in defaults: UserDefaults = .standard) -> Double {
        let saved = defaults.object(forKey: maximumScaleKey) as? Double
        return saved.flatMap { scaleOptions.contains($0) ? $0 : nil } ?? 2
    }

    static func setMode(_ mode: FullScreenSmallImageMode, in defaults: UserDefaults = .standard) {
        guard mode != self.mode(in: defaults) else { return }
        defaults.set(mode.rawValue, forKey: modeKey)
        ViewerPreferenceChange.post(in: defaults)
    }

    static func setMaximumScale(_ scale: Double, in defaults: UserDefaults = .standard) {
        guard scaleOptions.contains(scale), scale != maximumScale(in: defaults) else { return }
        defaults.set(scale, forKey: maximumScaleKey)
        ViewerPreferenceChange.post(in: defaults)
    }
}
