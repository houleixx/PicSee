import AppKit
import Foundation

enum WindowFramePreference {
    static let defaultsKey = "PicSee.WindowFrame"
    private static let fixedDefaultsKey = "PicSee.FixedWindowFrame"
    private static let fixedEnabledDefaultsKey = "PicSee.FixedWindowFrameEnabled"
    private static let temporaryDesktopFullScreenRestoreDefaultsKey = "PicSee.TemporaryDesktopFullScreenRestoreFrame"

    static func save(_ frame: NSRect, in defaults: UserDefaults = .standard) {
        defaults.set(NSStringFromRect(frame), forKey: defaultsKey)
    }

    static func savedFrame(
        in defaults: UserDefaults = .standard,
        fitting screenFrame: NSRect,
        minimumSize: NSSize
    ) -> NSRect? {
        guard
            let rawValue = defaults.string(forKey: defaultsKey),
            !rawValue.isEmpty
        else {
            return nil
        }

        let frame = NSRectFromString(rawValue)
        guard frame.width > 0, frame.height > 0 else { return nil }
        return WindowResizeGeometry.clamped(frame, to: screenFrame, minimumSize: minimumSize)
    }

    static func setFixedEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: fixedEnabledDefaultsKey)
    }

    static func isFixedEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: fixedEnabledDefaultsKey) as? Bool ?? false
    }

    static func saveFixedFrame(_ frame: NSRect, in defaults: UserDefaults = .standard) {
        defaults.set(NSStringFromRect(frame), forKey: fixedDefaultsKey)
    }

    static func fixedFrame(
        in defaults: UserDefaults = .standard,
        fitting screenFrame: NSRect,
        minimumSize: NSSize
    ) -> NSRect? {
        guard
            isFixedEnabled(in: defaults),
            let rawValue = defaults.string(forKey: fixedDefaultsKey),
            !rawValue.isEmpty
        else {
            return nil
        }

        let frame = NSRectFromString(rawValue)
        guard frame.width > 0, frame.height > 0 else { return nil }
        return WindowResizeGeometry.clamped(frame, to: screenFrame, minimumSize: minimumSize)
    }

    static func saveTemporaryDesktopFullScreenRestoreFrame(_ frame: NSRect, in defaults: UserDefaults = .standard) {
        defaults.set(NSStringFromRect(frame), forKey: temporaryDesktopFullScreenRestoreDefaultsKey)
    }

    static func temporaryDesktopFullScreenRestoreFrame(
        in defaults: UserDefaults = .standard,
        fitting screenFrame: NSRect,
        minimumSize: NSSize
    ) -> NSRect? {
        guard
            let rawValue = defaults.string(forKey: temporaryDesktopFullScreenRestoreDefaultsKey),
            !rawValue.isEmpty
        else {
            return nil
        }

        let frame = NSRectFromString(rawValue)
        guard frame.width > 0, frame.height > 0 else { return nil }
        return WindowResizeGeometry.clamped(frame, to: screenFrame, minimumSize: minimumSize)
    }
}

enum WindowResizeAnchor: Equatable {
    case bottomRight
    case topLeft
}

enum WindowResizeGeometry {
    static func frame(
        from startFrame: NSRect,
        anchor: WindowResizeAnchor,
        delta: CGSize,
        minimumSize: NSSize
    ) -> NSRect {
        switch anchor {
        case .bottomRight:
            var width = startFrame.width + delta.width
            var height = startFrame.height - delta.height
            width = max(width, minimumSize.width)
            height = max(height, minimumSize.height)
            return NSRect(
                x: startFrame.minX,
                y: startFrame.maxY - height,
                width: width,
                height: height
            )
        case .topLeft:
            var width = startFrame.width - delta.width
            var height = startFrame.height + delta.height
            width = max(width, minimumSize.width)
            height = max(height, minimumSize.height)
            return NSRect(
                x: startFrame.maxX - width,
                y: startFrame.minY,
                width: width,
                height: height
            )
        }
    }

    static func clamped(_ frame: NSRect, to screenFrame: NSRect, minimumSize: NSSize) -> NSRect {
        var width = min(max(frame.width, minimumSize.width), screenFrame.width)
        var height = min(max(frame.height, minimumSize.height), screenFrame.height)
        if !width.isFinite { width = minimumSize.width }
        if !height.isFinite { height = minimumSize.height }

        var x = frame.minX
        var y = frame.minY
        if x + width > screenFrame.maxX {
            x = screenFrame.maxX - width
        }
        if y + height > screenFrame.maxY {
            y = screenFrame.maxY - height
        }
        x = max(screenFrame.minX, x)
        y = max(screenFrame.minY, y)

        return NSRect(x: x, y: y, width: width, height: height)
    }
}
