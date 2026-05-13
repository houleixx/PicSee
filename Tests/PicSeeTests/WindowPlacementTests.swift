import AppKit
import XCTest
@testable import PicSee

final class WindowPlacementTests: XCTestCase {
    func testUsesEightyPercentOfScreenHeightAndCentersWindow() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let imageSize = NSSize(width: 1200, height: 800)

        let frame = WindowPlacement.frame(for: imageSize, in: screen)

        XCTAssertEqual(frame.height, 720, accuracy: 0.001)
        XCTAssertEqual(frame.width, 1080, accuracy: 0.001)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, screen.midY, accuracy: 0.001)
    }

    func testClampsWidthToScreenFrameWhenImageIsVeryWide() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let imageSize = NSSize(width: 4000, height: 500)

        let frame = WindowPlacement.frame(for: imageSize, in: screen)

        XCTAssertEqual(frame.height, 640, accuracy: 0.001)
        XCTAssertEqual(frame.width, 1000, accuracy: 0.001)
    }

    func testProvidesCenteredFallbackForMissingImageSize() {
        let screen = NSRect(x: 100, y: 50, width: 1600, height: 1000)

        let frame = WindowPlacement.frame(for: nil, in: screen)

        XCTAssertEqual(frame.height, 800, accuracy: 0.001)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, screen.midY, accuracy: 0.001)
    }
}
