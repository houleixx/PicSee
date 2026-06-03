import AppKit
import Foundation

struct ViewerTitleBarPreference {
    static let defaultsKey = "PicSee.TitleBarVisible"

    static func isVisible(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? false
    }

    static func setVisible(_ visible: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(visible, forKey: defaultsKey)
    }

    static func styleMask(titleBarVisible: Bool) -> NSWindow.StyleMask {
        if titleBarVisible {
            return [.titled, .closable, .miniaturizable, .resizable]
        }
        return [.borderless, .resizable, .fullSizeContentView]
    }

    @MainActor
    static func windowFrame(forContentFrame contentFrame: NSRect, titleBarVisible: Bool) -> NSRect {
        guard titleBarVisible else { return contentFrame }
        return NSWindow.frameRect(forContentRect: contentFrame, styleMask: styleMask(titleBarVisible: true))
    }
}
