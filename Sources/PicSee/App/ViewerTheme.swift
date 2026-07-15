import AppKit
import Foundation

enum ViewerTheme: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    static let defaultsKey = "PicSee.Theme"

    static func current(in defaults: UserDefaults = .standard) -> ViewerTheme {
        ViewerTheme(rawValue: defaults.integer(forKey: defaultsKey)) ?? .system
    }

    static func set(_ theme: ViewerTheme, in defaults: UserDefaults = .standard) {
        defaults.set(theme.rawValue, forKey: defaultsKey)
    }
}
