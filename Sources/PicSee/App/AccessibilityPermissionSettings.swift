import AppKit
import ApplicationServices
import Foundation

protocol AccessibilityPermissionHandling {
    var isTrusted: Bool { get }
    func requestSystemPermissionPrompt()
    func openSystemSettings()
}

enum AccessibilityPermissionSettings {
    static let explanation = "开启辅助功能权限，按 Finder 显示顺序预览图片。"
    static let enabledStatus = "已经开启"
    static let actionTitle = "去开启"

    static let systemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

}

enum AccessibilityPermissionPromptPreference {
    private static let didRequestPermissionKey = "didRequestAccessibilityPermission"

    static func shouldRequestPermission(
        isTrusted: Bool,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard !defaults.bool(forKey: didRequestPermissionKey) else {
            return false
        }

        defaults.set(true, forKey: didRequestPermissionKey)
        return !isTrusted
    }
}

struct SystemAccessibilityPermissionHandler: AccessibilityPermissionHandling {
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestSystemPermissionPrompt() {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(AccessibilityPermissionSettings.systemSettingsURL)
    }
}
