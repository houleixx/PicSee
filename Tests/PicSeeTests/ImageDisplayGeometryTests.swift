import CoreGraphics
import XCTest
@testable import PicSee

final class ImageDisplayGeometryTests: XCTestCase {
    func testCoverScaleFillsTheViewportWithoutSideGaps() {
        let geometry = ImageDisplayGeometry(
            imageSize: CGSize(width: 400, height: 300),
            viewportSize: CGSize(width: 1200, height: 600),
            zoomScale: 1,
            panOffset: .zero
        )

        XCTAssertEqual(geometry.displaySize.width, 1200, accuracy: 0.001)
        XCTAssertGreaterThan(geometry.displaySize.height, 600)
        XCTAssertEqual(geometry.imageRect.minX, 0, accuracy: 0.001)
        XCTAssertLessThan(geometry.imageRect.minY, 0)
    }

    func testCoverScaleFillsTallViewportWithoutTopBottomGaps() {
        let geometry = ImageDisplayGeometry(
            imageSize: CGSize(width: 400, height: 300),
            viewportSize: CGSize(width: 500, height: 900),
            zoomScale: 1,
            panOffset: .zero
        )

        XCTAssertGreaterThan(geometry.displaySize.width, 500)
        XCTAssertEqual(geometry.displaySize.height, 900, accuracy: 0.001)
        XCTAssertLessThan(geometry.imageRect.minX, 0)
        XCTAssertEqual(geometry.imageRect.minY, 0, accuracy: 0.001)
    }

    func testPanIsConstrainedButAllowedWhenCoverCropExistsAtBaseZoom() {
        let geometry = ImageDisplayGeometry(
            imageSize: CGSize(width: 400, height: 300),
            viewportSize: CGSize(width: 1200, height: 600),
            zoomScale: 1,
            panOffset: .zero
        )

        let constrained = geometry.constrainedPan(CGSize(width: 0, height: 200))

        XCTAssertEqual(constrained.width, 0, accuracy: 0.001)
        XCTAssertGreaterThan(constrained.height, 0)
        XCTAssertLessThanOrEqual(constrained.height, 230)
    }
}
