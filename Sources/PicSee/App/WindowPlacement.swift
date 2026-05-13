import AppKit

enum WindowPlacement {
    static func frame(for imageSize: NSSize?, in screenFrame: NSRect) -> NSRect {
        let targetHeight = max(260, screenFrame.height * 0.8)
        let aspectRatio: CGFloat

        if let imageSize, imageSize.width > 0, imageSize.height > 0 {
            aspectRatio = imageSize.width / imageSize.height
        } else {
            aspectRatio = 4.0 / 3.0
        }

        let width = min(max(360, targetHeight * aspectRatio), screenFrame.width)
        let height = min(targetHeight, screenFrame.height)

        return NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2,
            width: width,
            height: height
        )
    }
}
