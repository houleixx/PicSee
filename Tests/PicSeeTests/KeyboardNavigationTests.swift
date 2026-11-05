import AppKit
import XCTest
@testable import PicSee

final class KeyboardNavigationTests: XCTestCase {
    func testPrintableZoomShortcutsFollowKeyboardLayout() {
        XCTAssertEqual(KeyboardNavigation.action(for: 30, modifiers: .command, charactersIgnoringModifiers: "+"), .zoomIn)
        XCTAssertEqual(KeyboardNavigation.action(for: 30, modifiers: [.command, .shift], charactersIgnoringModifiers: "+"), .zoomIn)
        XCTAssertEqual(KeyboardNavigation.action(for: 44, modifiers: .command, charactersIgnoringModifiers: "-"), .zoomOut)
        XCTAssertEqual(KeyboardNavigation.action(for: 24, modifiers: .command, charactersIgnoringModifiers: "´"), .none)
        XCTAssertEqual(KeyboardNavigation.action(for: 27, modifiers: .command, charactersIgnoringModifiers: "ß"), .none)
        XCTAssertEqual(KeyboardNavigation.action(for: 24, modifiers: .command, charactersIgnoringModifiers: "="), .zoomIn)
        XCTAssertEqual(KeyboardNavigation.action(for: 30, charactersIgnoringModifiers: "+"), .none)
        XCTAssertEqual(KeyboardNavigation.action(for: 44, modifiers: [.command, .shift], charactersIgnoringModifiers: "-"), .none)
    }

    func testAlwaysOnTopRequiresControlCommandTAndDoesNotRepeat() {
        XCTAssertEqual(KeyboardNavigation.action(for: 17, modifiers: [.control, .command]), .toggleAlwaysOnTop)
        XCTAssertEqual(KeyboardNavigation.action(for: 17, modifiers: [.control, .command, .capsLock]), .toggleAlwaysOnTop)
        XCTAssertEqual(KeyboardNavigation.action(for: 17, modifiers: [.control, .command], isRepeat: true), .none)
        for modifiers: NSEvent.ModifierFlags in [[], .control, .command, [.control, .command, .shift], [.control, .command, .option]] {
            XCTAssertEqual(KeyboardNavigation.action(for: 17, modifiers: modifiers), .none)
        }
    }

    func testZoomShortcutsSupportMainAndNumericKeyboardsAndRepeating() {
        for keyCode: UInt16 in [24, 69, 81, 27, 78] {
            let expected: KeyboardNavigation.Action = [24, 69, 81].contains(keyCode) ? .zoomIn : .zoomOut
            XCTAssertEqual(KeyboardNavigation.action(for: keyCode, modifiers: .command), expected)
            XCTAssertEqual(KeyboardNavigation.action(for: keyCode, modifiers: [.command, .capsLock]), expected)
            XCTAssertEqual(KeyboardNavigation.action(for: keyCode, modifiers: .command, isRepeat: true), expected)
            XCTAssertEqual(KeyboardNavigation.action(for: keyCode), .none)
            for extra: NSEvent.ModifierFlags in [.option, .control] {
                XCTAssertEqual(KeyboardNavigation.action(for: keyCode, modifiers: [.command, extra]), .none)
            }
        }
        XCTAssertEqual(KeyboardNavigation.action(for: 24, modifiers: [.command, .shift]), .zoomIn)
        XCTAssertEqual(KeyboardNavigation.action(for: 24, modifiers: [.command, .shift], isRepeat: true), .zoomIn)
        XCTAssertEqual(KeyboardNavigation.action(for: 27, modifiers: [.command, .shift]), .none)
    }

    func testLeftAndUpMapToPreviousImage() {
        XCTAssertEqual(KeyboardNavigation.action(for: 123), .previous)
        XCTAssertEqual(KeyboardNavigation.action(for: 126), .previous)
    }

    func testCommandUpAndDownZoomWithoutChangingPlainArrowNavigation() {
        for keyCode: UInt16 in [126, 125] {
            let expected: KeyboardNavigation.Action = keyCode == 126 ? .zoomIn : .zoomOut
            XCTAssertEqual(KeyboardNavigation.action(for: keyCode, modifiers: .command), expected)
            XCTAssertEqual(KeyboardNavigation.action(for: keyCode, modifiers: [.command, .capsLock]), expected)
            XCTAssertEqual(KeyboardNavigation.action(for: keyCode, modifiers: .command, isRepeat: true), expected)
            XCTAssertEqual(KeyboardNavigation.action(for: keyCode), keyCode == 126 ? .previous : .next)
            for extra: NSEvent.ModifierFlags in [.shift, .option, .control] {
                XCTAssertEqual(KeyboardNavigation.action(for: keyCode, modifiers: [.command, extra]), .none)
            }
        }
    }

    func testRightAndDownMapToNextImage() {
        XCTAssertEqual(KeyboardNavigation.action(for: 124), .next)
        XCTAssertEqual(KeyboardNavigation.action(for: 125), .next)
    }

    func testEscapeExitsFullScreenBeforeQuitting() {
        XCTAssertEqual(KeyboardNavigation.action(for: 53, isFullScreen: true), .exitFullScreen)
        XCTAssertEqual(KeyboardNavigation.action(for: 53), .quit)
        XCTAssertEqual(KeyboardNavigation.action(for: 53, isRepeat: true, isFullScreen: true), .none)
        XCTAssertEqual(KeyboardNavigation.action(for: 53, modifiers: .command, isFullScreen: true), .none)
        XCTAssertEqual(KeyboardNavigation.action(for: 53, slideshowActive: true, isFullScreen: true), .endSlideshow)
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
