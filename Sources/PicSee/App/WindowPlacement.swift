import AppKit

enum WindowPlacement {
    static func frame(for imageSize: NSSize?, in visibleFrame: NSRect) -> NSRect {
        let targetHeight = max(260, visibleFrame.height * 0.8)
        let aspectRatio: CGFloat

        if let imageSize, imageSize.width > 0, imageSize.height > 0 {
            aspectRatio = imageSize.width / imageSize.height
        } else {
            aspectRatio = 4.0 / 3.0
        }

        let width = min(max(360, targetHeight * aspectRatio), visibleFrame.width)
        let height = min(targetHeight, visibleFrame.height)

        return NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }
}
