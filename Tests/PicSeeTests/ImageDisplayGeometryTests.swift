import CoreGraphics
import XCTest
@testable import PicSee

final class ImageDisplayGeometryTests: XCTestCase {
    func testDoesNotUpscaleSmallImagesAtBaseZoom() {
        let geometry = ImageDisplayGeometry(
            imageSize: CGSize(width: 400, height: 300),
            viewportSize: CGSize(width: 1200, height: 600),
            zoomScale: 1,
            panOffset: .zero
        )

        // 小图保持 1:1 显示并居中
        XCTAssertEqual(geometry.displaySize.width, 400, accuracy: 0.001)
        XCTAssertEqual(geometry.displaySize.height, 300, accuracy: 0.001)
        XCTAssertEqual(geometry.imageRect.minX, 400, accuracy: 0.001)
        XCTAssertEqual(geometry.imageRect.minY, 150, accuracy: 0.001)
    }

    func testCentersSmallImageWithoutUpscalingInTallViewport() {
        let geometry = ImageDisplayGeometry(
            imageSize: CGSize(width: 400, height: 300),
            viewportSize: CGSize(width: 500, height: 900),
            zoomScale: 1,
            panOffset: .zero
        )

        // 不放大：保持 400x300，并在 500x900 的视口中居中
        XCTAssertEqual(geometry.displaySize.width, 400, accuracy: 0.001)
        XCTAssertEqual(geometry.displaySize.height, 300, accuracy: 0.001)
        XCTAssertEqual(geometry.imageRect.minX, 50, accuracy: 0.001)
        XCTAssertEqual(geometry.imageRect.minY, 300, accuracy: 0.001)
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

    func testPanIsAllowedWhenImageExceedsViewportAfterZoom() {
        let geometry = ImageDisplayGeometry(
            imageSize: CGSize(width: 400, height: 300),
            viewportSize: CGSize(width: 1200, height: 600),
            // 在“基准不放大小图”的前提下，将缩放提高到 4x，使图像两轴都超过视口
            zoomScale: 4,
            panOffset: .zero
        )

        let constrained = geometry.constrainedPan(CGSize(width: 250, height: 250))

        XCTAssertEqual(constrained.width, 200, accuracy: 0.001)
        XCTAssertEqual(constrained.height, 250, accuracy: 0.001)
    }

    func testConstrainedPanSlackWhenFittedAllowsHorizontalNudge() {
        let geometry = ImageDisplayGeometry(
            imageSize: CGSize(width: 400, height: 300),
            viewportSize: CGSize(width: 1200, height: 600),
            zoomScale: 1,
            panOffset: .zero
        )

        let withoutSlack = geometry.constrainedPan(CGSize(width: 80, height: 40), allowSlackWhenFitted: false)
        XCTAssertEqual(withoutSlack.width, 0, accuracy: 0.001)
        XCTAssertEqual(withoutSlack.height, 0, accuracy: 0.001)

        let withSlack = geometry.constrainedPan(CGSize(width: 80, height: 40), allowSlackWhenFitted: true)
        XCTAssertEqual(withSlack.width, 80, accuracy: 0.001)
        // 小图不放大时，允许在两个维度上各自一半空隙范围内的轻微位移
        XCTAssertEqual(withSlack.height, 40, accuracy: 0.001)
    }
}
