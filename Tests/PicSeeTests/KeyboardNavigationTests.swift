import AppKit
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

    func testFullScreenShortcutsDoNotRepeatAndWorkDuringSlideshow() {
        for modifiers: NSEvent.ModifierFlags in [[], [.control, .command], .capsLock] {
            for slideshowActive in [false, true] {
                XCTAssertEqual(KeyboardNavigation.action(for: 3, modifiers: modifiers,
                    slideshowActive: slideshowActive), .toggleFullScreen)
                XCTAssertEqual(KeyboardNavigation.action(for: 3, modifiers: modifiers,
                    isRepeat: true, slideshowActive: slideshowActive), .none)
            }
        }
        for modifiers: NSEvent.ModifierFlags in [.command, .control, .option, .shift,
                                                [.control, .command, .shift], [.control, .command, .option]] {
            XCTAssertEqual(KeyboardNavigation.action(for: 3, modifiers: modifiers), .none)
        }
    }

    func testDeleteAndForwardDeleteTrashWithoutRepeating() {
        for keyCode: UInt16 in [51, 117] {
            XCTAssertEqual(KeyboardNavigation.action(for: keyCode), .trash)
            XCTAssertEqual(KeyboardNavigation.action(for: keyCode, isRepeat: true), .none)
            XCTAssertEqual(KeyboardNavigation.action(for: keyCode, modifiers: .function), .trash)
            for modifiers: NSEvent.ModifierFlags in [.shift, .option, .control] {
                XCTAssertEqual(KeyboardNavigation.action(for: keyCode, modifiers: modifiers), .none)
            }
        }
    }

    func testCommandDeleteStillTrashesWithoutRepeating() {
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
