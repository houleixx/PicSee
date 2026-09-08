import AppKit
import XCTest
@testable import PicSee

final class WindowPlacementTests: XCTestCase {
    func testLargeImageFitsAvailableAreaAndCentersWindow() {
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

        XCTAssertEqual(frame.height, 600, accuracy: 0.001)
        XCTAssertEqual(frame.width, 800, accuracy: 0.001)
    }

    func testProvidesCenteredFallbackForMissingImageSize() {
        let screen = NSRect(x: 100, y: 50, width: 1600, height: 1000)

        let frame = WindowPlacement.frame(for: nil, in: screen)

        XCTAssertEqual(frame.height, 800, accuracy: 0.001)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, screen.midY, accuracy: 0.001)
    }

    func testSmallRetinaScreenshotUsesMinimumWindowSize() {
        let screen = NSRect(x: 0, y: 40, width: 1440, height: 820)
        let frame = WindowPlacement.frame(for: NSSize(width: 1042, height: 664), in: screen, backingScale: 2)
        XCTAssertEqual(frame.size, NSSize(width: 800, height: 600))
        XCTAssertEqual(frame.midX, screen.midX)
        XCTAssertEqual(frame.midY, screen.midY)
    }

    func testStandardScreenUsesMinimumWindowSizeForSmallImage() {
        let frame = WindowPlacement.frame(for: NSSize(width: 500, height: 300),
            in: NSRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(frame.size, NSSize(width: 800, height: 600))
    }

    func testTinyImageRetainsUsableMinimumWindowAndFitsSmallScreen() {
        let frame = WindowPlacement.frame(for: NSSize(width: 16, height: 16),
            in: NSRect(x: 0, y: 0, width: 1440, height: 900), backingScale: 2)
        XCTAssertEqual(frame.size, NSSize(width: 800, height: 600))
        let screen = NSRect(x: 20, y: 30, width: 300, height: 200)
        XCTAssertEqual(WindowPlacement.frame(for: NSSize(width: 4000, height: 3000), in: screen), screen)
    }

    func testLargePortraitFitsHeightWithoutFillingScreenWidth() {
        let screen = NSRect(x: 1440, y: 40, width: 1440, height: 820)
        let frame = WindowPlacement.frame(for: NSSize(width: 2000, height: 6000), in: screen, backingScale: 2)
        XCTAssertEqual(frame.height, 656, accuracy: 0.001)
        XCTAssertEqual(frame.width, 800, accuracy: 0.001)
        XCTAssertTrue(screen.contains(frame))
    }
}
