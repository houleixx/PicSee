import AppKit
import XCTest
@testable import PicSee

final class WindowPlacementTests: XCTestCase {
    func testReadingModesDoNotLetLongImageHeightShrinkTheWindowWidth() throws {
        let screen = NSRect(x: 0, y: 24, width: 1440, height: 856)
        let image = NSSize(width: 1279, height: 6826)
        let actual = try XCTUnwrap(WindowPlacement.automaticFrame(
            for: image, in: screen, backingScale: 2, displayMode: .actualSize))
        XCTAssertEqual(actual.width, 639.5, accuracy: 0.001)
        XCTAssertEqual(actual.height, screen.height * 0.9, accuracy: 0.001)
        let widthFit = try XCTUnwrap(WindowPlacement.automaticFrame(
            for: image, in: screen, backingScale: 2, displayMode: .fitWidth))
        XCTAssertEqual(widthFit.width, 800, accuracy: 0.001)
        XCTAssertEqual(widthFit.height, screen.height * 0.9, accuracy: 0.001)
        for frame in [actual, widthFit] {
            XCTAssertTrue(screen.contains(frame))
            XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.001)
            XCTAssertEqual(frame.midY, screen.midY, accuracy: 0.001)
        }
    }

    func testReadingModesClampToScreenAndKeepSmallWindowsUsable() throws {
        for mode in [ImageDisplayMode.actualSize, .fitWidth] {
            let screen = NSRect(x: 30, y: 40, width: 600, height: 450)
            let large = try XCTUnwrap(WindowPlacement.automaticFrame(
                for: NSSize(width: 10000, height: 20000), in: screen, backingScale: 2, displayMode: mode))
            XCTAssertTrue(screen.contains(large))
            XCTAssertEqual(large.width, 540, accuracy: 0.001)
            XCTAssertEqual(large.height, 405, accuracy: 0.001)
            let tinyScreen = NSRect(x: 10, y: 20, width: 300, height: 200)
            let tiny = try XCTUnwrap(WindowPlacement.automaticFrame(
                for: NSSize(width: 100, height: 600), in: tinyScreen, backingScale: 2, displayMode: mode))
            XCTAssertEqual(tiny, tinyScreen)
        }
        let small = try XCTUnwrap(WindowPlacement.automaticFrame(for: NSSize(width: 400, height: 240),
            in: NSRect(x: 0, y: 0, width: 1440, height: 900), backingScale: 2, displayMode: .actualSize))
        XCTAssertEqual(small.size, NSSize(width: 480, height: 320))
    }

    func testAutomaticWindowUsesImageSizeWithUsableMinimum() throws {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let small = try XCTUnwrap(WindowPlacement.automaticFrame(
            for: NSSize(width: 400, height: 240), in: screen, backingScale: 2))
        XCTAssertEqual(small.size, NSSize(width: 480, height: 320))
        let medium = try XCTUnwrap(WindowPlacement.automaticFrame(
            for: NSSize(width: 1400, height: 1000), in: screen, backingScale: 2))
        XCTAssertEqual(medium.size, NSSize(width: 700, height: 500))
    }

    func testAutomaticWindowFitsLargeImagesToVisibleScreen() throws {
        let screen = NSRect(x: 40, y: 50, width: 1000, height: 800)
        let frame = try XCTUnwrap(WindowPlacement.automaticFrame(
            for: NSSize(width: 4000, height: 2000), in: screen))
        XCTAssertEqual(frame.width, 900, accuracy: 0.001)
        XCTAssertEqual(frame.height, 450, accuracy: 0.001)
        XCTAssertTrue(screen.contains(frame))
    }

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
