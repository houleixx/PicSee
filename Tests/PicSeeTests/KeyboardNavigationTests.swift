import XCTest
@testable import PicSee

final class KeyboardNavigationTests: XCTestCase {
    func testLeftAndUpMapToPreviousImage() {
        XCTAssertEqual(KeyboardNavigation.action(for: 123), .previous)
        XCTAssertEqual(KeyboardNavigation.action(for: 126), .previous)
    }

    func testRightAndDownMapToNextImage() {
        XCTAssertEqual(KeyboardNavigation.action(for: 124), .next)
        XCTAssertEqual(KeyboardNavigation.action(for: 125), .next)
    }

    func testEscapeMapsToQuit() {
        XCTAssertEqual(KeyboardNavigation.action(for: 53), .quit)
    }
}
