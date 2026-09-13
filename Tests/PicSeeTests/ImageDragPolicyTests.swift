import XCTest
@testable import PicSee

final class ImageDragPolicyTests: XCTestCase {
    private let frame = CGRect(x: -600, y: 100, width: 400, height: 300)
    private let start = CGPoint(x: -400, y: 250)

    func testInsideWindowNeverExportsEvenAfterLongDrag() {
        XCTAssertFalse(ImageDragPolicy.shouldExport(start: start, current: CGPoint(x: -201, y: 399), windowFrame: frame))
    }

    func testJustOutsideWindowRemainsInDeadZone() {
        XCTAssertFalse(ImageDragPolicy.shouldExport(start: start, current: CGPoint(x: -195, y: 250), windowFrame: frame))
    }

    func testEachWindowEdgeCanStartExportOnNegativeCoordinateDisplay() {
        for point in [CGPoint(x: -613, y: 250), CGPoint(x: -187, y: 250),
                      CGPoint(x: -400, y: 87), CGPoint(x: -400, y: 413)] {
            XCTAssertTrue(ImageDragPolicy.shouldExport(start: start, current: point, windowFrame: frame))
        }
    }

    func testSmallMotionCannotExportAndEmptyFrameCannotExport() {
        XCTAssertFalse(ImageDragPolicy.shouldExport(start: CGPoint(x: -188, y: 250),
                                                   current: CGPoint(x: -187, y: 250), windowFrame: frame))
        XCTAssertFalse(ImageDragPolicy.shouldExport(start: start, current: .zero, windowFrame: .zero))
    }
}
