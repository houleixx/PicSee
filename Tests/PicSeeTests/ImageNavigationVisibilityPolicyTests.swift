import XCTest
@testable import PicSee

final class ImageNavigationVisibilityPolicyTests: XCTestCase {
    func testInitialRevealShowsEveryAvailableDirection() {
        XCTAssertEqual(
            visibility(pointerX: nil, revealsAvailableDirections: true),
            ImageNavigationVisibility(previous: true, next: true)
        )
    }

    func testLeftEdgeShowsOnlyPreviousDirection() {
        XCTAssertEqual(
            visibility(pointerX: 100),
            ImageNavigationVisibility(previous: true, next: false)
        )
    }

    func testMiddleHidesBothDirections() {
        XCTAssertEqual(
            visibility(pointerX: 500),
            ImageNavigationVisibility(previous: false, next: false)
        )
    }

    func testRightEdgeShowsOnlyNextDirection() {
        XCTAssertEqual(
            visibility(pointerX: 900),
            ImageNavigationVisibility(previous: false, next: true)
        )
    }

    func testTwentyPercentBoundariesBelongToEdgeZones() {
        XCTAssertEqual(
            visibility(pointerX: 200),
            ImageNavigationVisibility(previous: true, next: false)
        )
        XCTAssertEqual(
            visibility(pointerX: 800),
            ImageNavigationVisibility(previous: false, next: true)
        )
    }

    func testUnavailableDirectionsRemainHidden() {
        XCTAssertEqual(
            visibility(pointerX: 100, hasPrevious: false),
            ImageNavigationVisibility(previous: false, next: false)
        )
        XCTAssertEqual(
            visibility(pointerX: 900, hasNext: false),
            ImageNavigationVisibility(previous: false, next: false)
        )
        XCTAssertEqual(
            visibility(
                pointerX: nil,
                hasPrevious: false,
                hasNext: true,
                revealsAvailableDirections: true
            ),
            ImageNavigationVisibility(previous: false, next: true)
        )
    }

    func testPointerOutsideViewerHidesBothDirections() {
        XCTAssertEqual(
            visibility(pointerX: -1),
            ImageNavigationVisibility(previous: false, next: false)
        )
        XCTAssertEqual(
            visibility(pointerX: 1_001),
            ImageNavigationVisibility(previous: false, next: false)
        )
        XCTAssertEqual(
            visibility(pointerX: nil),
            ImageNavigationVisibility(previous: false, next: false)
        )
    }

    func testInvalidViewerWidthHidesBothDirections() {
        XCTAssertEqual(
            ImageNavigationVisibilityPolicy.visibility(
                pointerX: 0,
                viewerWidth: 0,
                hasPrevious: true,
                hasNext: true,
                revealsAvailableDirections: false
            ),
            ImageNavigationVisibility(previous: false, next: false)
        )
    }

    private func visibility(
        pointerX: CGFloat?,
        hasPrevious: Bool = true,
        hasNext: Bool = true,
        revealsAvailableDirections: Bool = false
    ) -> ImageNavigationVisibility {
        ImageNavigationVisibilityPolicy.visibility(
            pointerX: pointerX,
            viewerWidth: 1_000,
            hasPrevious: hasPrevious,
            hasNext: hasNext,
            revealsAvailableDirections: revealsAvailableDirections
        )
    }
}
