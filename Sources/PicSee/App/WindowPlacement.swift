import AppKit

enum WindowPlacement {
    static let compactMinimumSize = NSSize(width: 360, height: 240)

    /// Divides image dimensions by backingScale to get screen points.
    /// Pass logical image dimensions with the default scale of 1.
    static func frame(
        for imageSize: NSSize?, in screenFrame: NSRect, backingScale: CGFloat = 1,
        minimumSize: NSSize = NSSize(width: 800, height: 600)
    ) -> NSRect {
        let maximumWidth = min(screenFrame.width, max(800, screenFrame.width * 0.8))
        let maximumHeight = min(screenFrame.height, max(600, screenFrame.height * 0.8))
        let screenScale = backingScale.isFinite && backingScale > 0 ? backingScale : 1
        let fittedSize: NSSize
        if let imageSize, imageSize.width.isFinite, imageSize.height.isFinite,
           imageSize.width > 0, imageSize.height > 0 {
            let nativeSize = NSSize(width: imageSize.width / screenScale, height: imageSize.height / screenScale)
            let fit = min(1, maximumWidth / nativeSize.width, maximumHeight / nativeSize.height)
            fittedSize = NSSize(width: nativeSize.width * fit, height: nativeSize.height * fit)
        } else {
            fittedSize = NSSize(width: min(maximumWidth, maximumHeight * 4 / 3), height: maximumHeight)
        }
        let width = min(maximumWidth, max(minimumSize.width, fittedSize.width))
        let height = min(maximumHeight, max(minimumSize.height, fittedSize.height))
        return NSRect(x: screenFrame.midX - width / 2, y: screenFrame.midY - height / 2,
                      width: width, height: height)
    }
}
