import CoreGraphics

struct MinimapGeometry {
    let size: CGSize
    let visibleRect: CGRect
}

struct ImageZoomAdjustment {
    static let minimumZoomScale: CGFloat = 0.05
    static let maximumZoomScale: CGFloat = 20

    let zoomScale: CGFloat
    let panOffset: CGSize

    static func clampedZoom(currentZoom: CGFloat, multiplier: CGFloat) -> CGFloat {
        min(maximumZoomScale, max(minimumZoomScale, currentZoom * max(0.01, multiplier)))
    }

    static func adjustment(
        from geometry: ImageDisplayGeometry,
        multiplier: CGFloat
    ) -> ImageZoomAdjustment {
        let nextZoom = clampedZoom(currentZoom: geometry.zoomScale, multiplier: multiplier)
        let nextGeometry = ImageDisplayGeometry(
            imageSize: geometry.imageSize,
            viewportSize: geometry.viewportSize,
            zoomScale: nextZoom,
            panOffset: geometry.panOffset
        )
        let allowsPanAfterZoom = abs(nextGeometry.zoomScale - 1) > 0.001 || nextGeometry.canPan

        guard allowsPanAfterZoom else {
            return ImageZoomAdjustment(zoomScale: nextZoom, panOffset: .zero)
        }

        return ImageZoomAdjustment(
            zoomScale: nextZoom,
            panOffset: geometry.constrainedPan(
                preservingViewportCenterWhenZoomingTo: nextZoom,
                allowSlackWhenFitted: true
            )
        )
    }
}

struct ImageDisplayGeometry {
    let imageSize: CGSize
    let viewportSize: CGSize
    let zoomScale: CGFloat
    let panOffset: CGSize
    let rotationDegrees: Int

    init(
        imageSize: CGSize,
        viewportSize: CGSize,
        zoomScale: CGFloat,
        panOffset: CGSize,
        rotationDegrees: Int = 0
    ) {
        self.imageSize = imageSize
        self.viewportSize = viewportSize
        self.zoomScale = zoomScale
        self.panOffset = panOffset
        self.rotationDegrees = ((rotationDegrees % 360) + 360) % 360
    }

    var rotatedImageSize: CGSize {
        rotationDegrees == 90 || rotationDegrees == 270
            ? CGSize(width: imageSize.height, height: imageSize.width)
            : imageSize
    }

    var fitScale: CGFloat {
        guard rotatedImageSize.width > 0, rotatedImageSize.height > 0, viewportSize.width > 0, viewportSize.height > 0 else {
            return 1
        }
        // 不对小图进行放大：当图像在两个维度上都小于视口时，基准缩放保持 1:1。
        // 仅当任一维度超出视口时，才按较小比例缩小以完整显示。
        let scaleToFit = min(viewportSize.width / rotatedImageSize.width, viewportSize.height / rotatedImageSize.height)
        return min(1, scaleToFit)
    }

    var displayScale: CGFloat {
        max(0.01, fitScale * max(0.1, zoomScale))
    }

    var displaySize: CGSize {
        CGSize(width: rotatedImageSize.width * displayScale, height: rotatedImageSize.height * displayScale)
    }

    var unrotatedDisplaySize: CGSize {
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

    var unrotatedImageRect: CGRect {
        CGRect(
            x: imageRect.midX - unrotatedDisplaySize.width / 2,
            y: imageRect.midY - unrotatedDisplaySize.height / 2,
            width: unrotatedDisplaySize.width,
            height: unrotatedDisplaySize.height
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

    var shouldShowMinimap: Bool {
        canPan
    }

    func minimapGeometry(maxSize: CGSize) -> MinimapGeometry {
        guard imageSize.width > 0, imageSize.height > 0, maxSize.width > 0, maxSize.height > 0 else {
            return MinimapGeometry(size: .zero, visibleRect: .zero)
        }

        let scale = min(maxSize.width / imageSize.width, maxSize.height / imageSize.height)
        let minimapSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let visibleImageRect = imageBounds.intersection(
            CGRect(
                x: -imageRect.minX / displayScale,
                y: -imageRect.minY / displayScale,
                width: viewportSize.width / displayScale,
                height: viewportSize.height / displayScale
            )
        )

        return MinimapGeometry(
            size: minimapSize,
            visibleRect: CGRect(
                x: visibleImageRect.minX * scale,
                y: visibleImageRect.minY * scale,
                width: visibleImageRect.width * scale,
                height: visibleImageRect.height * scale
            )
        )
    }

    func constrainedPan(centeredAtMinimapPoint point: CGPoint, minimap: MinimapGeometry) -> CGSize {
        guard minimap.size.width > 0, minimap.size.height > 0 else {
            return constrainedPan(panOffset)
        }

        let imagePoint = CGPoint(
            x: min(max(point.x / minimap.size.width, 0), 1) * imageSize.width,
            y: min(max(point.y / minimap.size.height, 0), 1) * imageSize.height
        )
        let proposed = CGSize(
            width: displaySize.width / 2 - imagePoint.x * displayScale,
            height: displaySize.height / 2 - imagePoint.y * displayScale
        )

        return constrainedPan(proposed)
    }

    func constrainedPan(
        preservingViewportCenterWhenZoomingTo nextZoomScale: CGFloat,
        allowSlackWhenFitted: Bool = false
    ) -> CGSize {
        guard displayScale > 0 else {
            return panOffset
        }

        let viewportCenter = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let centeredImagePoint = CGPoint(
            x: (viewportCenter.x - imageRect.minX) / displayScale,
            y: (viewportCenter.y - imageRect.minY) / displayScale
        )
        let nextGeometry = ImageDisplayGeometry(
            imageSize: imageSize,
            viewportSize: viewportSize,
            zoomScale: nextZoomScale,
            panOffset: panOffset
        )
        let proposed = CGSize(
            width: nextGeometry.displaySize.width / 2 - centeredImagePoint.x * nextGeometry.displayScale,
            height: nextGeometry.displaySize.height / 2 - centeredImagePoint.y * nextGeometry.displayScale
        )

        return nextGeometry.constrainedPan(proposed, allowSlackWhenFitted: allowSlackWhenFitted)
    }
}
