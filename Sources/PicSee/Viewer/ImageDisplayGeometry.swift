import CoreGraphics

struct ImageDisplayGeometry {
    let imageSize: CGSize
    let viewportSize: CGSize
    let zoomScale: CGFloat
    let panOffset: CGSize

    var fitScale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0, viewportSize.width > 0, viewportSize.height > 0 else {
            return 1
        }

        return min(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
    }

    var displayScale: CGFloat {
        max(0.01, fitScale * max(0.1, zoomScale))
    }

    var displaySize: CGSize {
        CGSize(width: imageSize.width * displayScale, height: imageSize.height * displayScale)
    }

    var imageRect: CGRect {
        CGRect(
            x: viewportSize.width / 2 - displaySize.width / 2 + panOffset.width,
            y: viewportSize.height / 2 - displaySize.height / 2 + panOffset.height,
            width: displaySize.width,
            height: displaySize.height
        )
    }

    /// - Parameter allowSlackWhenFitted: When true and the scaled image is smaller than the viewport in an axis,
    ///   still allow panning up to half the slack so the image can be repositioned (e.g. after zooming out).
    func constrainedPan(_ proposed: CGSize, allowSlackWhenFitted: Bool = false) -> CGSize {
        let maxX: CGFloat
        let maxY: CGFloat
        if allowSlackWhenFitted {
            maxX = abs(displaySize.width - viewportSize.width) / 2
            maxY = abs(displaySize.height - viewportSize.height) / 2
        } else {
            maxX = max(0, (displaySize.width - viewportSize.width) / 2)
            maxY = max(0, (displaySize.height - viewportSize.height) / 2)
        }

        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    var canPan: Bool {
        displaySize.width > viewportSize.width || displaySize.height > viewportSize.height
    }
}
