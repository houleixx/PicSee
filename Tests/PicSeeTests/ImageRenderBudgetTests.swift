import XCTest
@testable import PicSee

final class ImageRenderBudgetTests: XCTestCase {
    func testRejectsNonFiniteAndNonPositiveSizesBeforeIntegerConversion() {
        for size in [CGSize(width: CGFloat.infinity, height: 1), CGSize(width: CGFloat.nan, height: 1),
                     CGSize(width: -1, height: 1), CGSize(width: 1, height: 0)] {
            XCTAssertThrowsError(try ImageRenderBudget.dimensions(for: size))
        }
    }

    func testBoundsFourChannelBitmapAllocation() throws {
        XCTAssertNoThrow(try ImageRenderBudget.dimensions(for: CGSize(width: 10, height: 10), maximumBytes: 400))
        XCTAssertThrowsError(try ImageRenderBudget.dimensions(for: CGSize(width: 10, height: 11), maximumBytes: 400))
        XCTAssertThrowsError(try ImageRenderBudget.dimensions(for: CGSize(width: 1e12, height: 1e12)))
    }
}
