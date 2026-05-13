import CoreGraphics
import XCTest
@testable import PicSee

final class ImageDisplayGeometryTests: XCTestCase {
    func testFitScaleShowsEntireImageWithoutCropping() {
        let geometry = ImageDisplayGeometry(
            imageSize: CGSize(width: 400, height: 300),
            viewportSize: CGSize(width: 1200, height: 600),
            zoomScale: 1,
            panOffset: .zero
        )

        XCTAssertEqual(geometry.displaySize.width, 800, accuracy: 0.001)
        XCTAssertEqual(geometry.displaySize.height, 600, accuracy: 0.001)
        XCTAssertEqual(geometry.imageRect.minX, 200, accuracy: 0.001)
        XCTAssertEqual(geometry.imageRect.minY, 0, accuracy: 0.001)
    }

    func testFitScaleCentersEntireImageInTallViewport() {
        let geometry = ImageDisplayGeometry(
            imageSize: CGSize(width: 400, height: 300),
            viewportSize: CGSize(width: 500, height: 900),
            zoomScale: 1,
            panOffset: .zero
        )

        XCTAssertEqual(geometry.displaySize.width, 500, accuracy: 0.001)
        XCTAssertEqual(geometry.displaySize.height, 375, accuracy: 0.001)
        XCTAssertEqual(geometry.imageRect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(geometry.imageRect.minY, 262.5, accuracy: 0.001)
    }

    func testPanIsDisabledAtBaseZoomWhenImageAlreadyFits() {
        let geometry = ImageDisplayGeometry(
            imageSize: CGSize(width: 400, height: 300),
            viewportSize: CGSize(width: 1200, height: 600),
            zoomScale: 1,
            panOffset: .zero
        )

        let constrained = geometry.constrainedPan(CGSize(width: 0, height: 200))

        XCTAssertEqual(constrained.width, 0, accuracy: 0.001)
        XCTAssertEqual(constrained.height, 0, accuracy: 0.001)
    }

    func testPanIsAllowedWhenImageIsZoomedIn() {
        let geometry = ImageDisplayGeometry(
            imageSize: CGSize(width: 400, height: 300),
            viewportSize: CGSize(width: 1200, height: 600),
            zoomScale: 2,
            panOffset: .zero
        )

        let constrained = geometry.constrainedPan(CGSize(width: 250, height: 250))

        XCTAssertEqual(constrained.width, 200, accuracy: 0.001)
        XCTAssertEqual(constrained.height, 250, accuracy: 0.001)
    }
}
