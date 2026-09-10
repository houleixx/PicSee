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

    func testSpaceMapsToQuit() {
        XCTAssertEqual(KeyboardNavigation.action(for: 49), .quit)
    }

    func testIMapsToToggleImageParameters() {
        XCTAssertEqual(KeyboardNavigation.action(for: 34), .toggleImageParameters)
    }

    func testTrashRequiresCommandAndDoesNotRepeat() {
        XCTAssertEqual(KeyboardNavigation.action(for: 51), .none)
        XCTAssertEqual(KeyboardNavigation.action(for: 51, modifiers: .command), .trash)
        XCTAssertEqual(KeyboardNavigation.action(for: 51, modifiers: [.command, .shift]), .none)
        XCTAssertEqual(KeyboardNavigation.action(for: 51, modifiers: .command, isRepeat: true), .none)
        XCTAssertEqual(KeyboardNavigation.action(for: 117, modifiers: .command), .none)
    }

    func testUndoRequiresCommandAndDoesNotRepeat() {
        XCTAssertEqual(KeyboardNavigation.action(for: 6), .none)
        XCTAssertEqual(KeyboardNavigation.action(for: 6, modifiers: .command), .undoDeletion)
        XCTAssertEqual(KeyboardNavigation.action(for: 6, modifiers: [.command, .shift]), .none)
        XCTAssertEqual(KeyboardNavigation.action(for: 6, modifiers: .command, isRepeat: true), .none)
    }
}
