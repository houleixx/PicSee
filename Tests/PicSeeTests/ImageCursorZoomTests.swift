import CoreGraphics
import Testing
@testable import PicSee

struct ImageCursorZoomTests {
    @Test(arguments: [0, 90, 180, 270], [CGFloat(0.8), CGFloat(1.4)])
    func cursorPixelStaysFixedWhenZooming(rotation: Int, multiplier: CGFloat) {
        let geometry = ImageDisplayGeometry(imageSize: CGSize(width: 1000, height: 800),
            viewportSize: CGSize(width: 400, height: 300), zoomScale: 3,
            panOffset: CGSize(width: 20, height: -15), rotationDegrees: rotation)
        let anchor = CGPoint(x: 280, y: 210)
        let pixel = sourcePixel(at: anchor, geometry: geometry)
        let adjustment = ImageZoomAdjustment.adjustment(from: geometry, multiplier: multiplier, anchorPoint: anchor)
        let next = ImageDisplayGeometry(imageSize: geometry.imageSize, viewportSize: geometry.viewportSize,
            zoomScale: adjustment.zoomScale, panOffset: adjustment.panOffset, rotationDegrees: rotation)
        let nextPixel = sourcePixel(at: anchor, geometry: next)
        #expect(abs(pixel.x - nextPixel.x) < 0.0001)
        #expect(abs(pixel.y - nextPixel.y) < 0.0001)
    }

    @Test(arguments: [0, 90, 180, 270])
    func defaultAnchorStillPreservesCenterOnRotatedImages(rotation: Int) {
        let geometry = ImageDisplayGeometry(imageSize: CGSize(width: 1000, height: 800),
            viewportSize: CGSize(width: 400, height: 300), zoomScale: 3,
            panOffset: CGSize(width: 20, height: -15), rotationDegrees: rotation)
        let adjustment = ImageZoomAdjustment.adjustment(from: geometry, multiplier: 1.4)
        #expect(abs(adjustment.panOffset.width - 28) < 0.0001)
        #expect(abs(adjustment.panOffset.height + 21) < 0.0001)
    }

    @Test func cursorZoomObeysPanBoundsAndFitStillCentersImage() {
        let geometry = ImageDisplayGeometry(imageSize: CGSize(width: 1000, height: 800),
            viewportSize: CGSize(width: 400, height: 300), zoomScale: 2,
            panOffset: CGSize(width: 100, height: 100))
        let adjustment = ImageZoomAdjustment.adjustment(from: geometry, multiplier: 0.6,
            anchorPoint: CGPoint(x: 390, y: 290))
        #expect(abs(adjustment.panOffset.width - 25) < 0.0001)
        #expect(abs(adjustment.panOffset.height - 30) < 0.0001)
        let fitted = ImageZoomAdjustment.adjustment(from: geometry, multiplier: 0.5,
            anchorPoint: CGPoint(x: 390, y: 290))
        #expect(fitted.zoomScale == 1)
        #expect(fitted.panOffset == .zero)
    }

    @Test(arguments: [CGFloat(0.06), CGFloat(19)])
    func cursorZoomUsesClampedScale(zoom: CGFloat) {
        let geometry = ImageDisplayGeometry(imageSize: CGSize(width: 1000, height: 800),
            viewportSize: CGSize(width: 400, height: 300), zoomScale: zoom, panOffset: .zero)
        let anchor = CGPoint(x: 230, y: 180)
        let adjustment = ImageZoomAdjustment.adjustment(from: geometry,
            multiplier: zoom < 1 ? 0.1 : 2, anchorPoint: anchor)
        #expect(adjustment.zoomScale == (zoom < 1 ? 0.05 : 20))
        let next = ImageDisplayGeometry(imageSize: geometry.imageSize, viewportSize: geometry.viewportSize,
            zoomScale: adjustment.zoomScale, panOffset: adjustment.panOffset)
        let before = sourcePixel(at: anchor, geometry: geometry)
        let after = sourcePixel(at: anchor, geometry: next)
        #expect(abs(before.x - after.x) < 0.0001)
        #expect(abs(before.y - after.y) < 0.0001)
    }
}

/// Independently undo the view's translation, scale and rotation to compare
/// actual source pixels, rather than testing only a matching pan formula.
func sourcePixel(at anchor: CGPoint, geometry: ImageDisplayGeometry) -> CGPoint {
    let x = (anchor.x - geometry.viewportSize.width / 2 - geometry.panOffset.width) / geometry.displayScale
    let y = (anchor.y - geometry.viewportSize.height / 2 - geometry.panOffset.height) / geometry.displayScale
    let angle = CGFloat(geometry.rotationDegrees) * .pi / 180
    return CGPoint(x: geometry.imageSize.width / 2 + cos(angle) * x + sin(angle) * y,
                   y: geometry.imageSize.height / 2 - sin(angle) * x + cos(angle) * y)
}
