import AppKit
import XCTest
@testable import PicSee

@MainActor
final class ViewerWindowTests: XCTestCase {
    func testTitledWindowNonContentTopAreaIsTitleBar() {
        let contentLayoutRect = NSRect(x: 0, y: 0, width: 640, height: 420)

        XCTAssertTrue(ViewerWindow.isTitleBarPoint(
            NSPoint(x: 320, y: 432),
            contentLayoutRect: contentLayoutRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable]
        ))
    }

    func testTitledWindowContentAreaIsNotTitleBar() {
        let contentLayoutRect = NSRect(x: 0, y: 0, width: 640, height: 420)

        XCTAssertFalse(ViewerWindow.isTitleBarPoint(
            NSPoint(x: 320, y: 210),
            contentLayoutRect: contentLayoutRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable]
        ))
    }

    func testBorderlessWindowHasNoSystemTitleBarHitArea() {
        let contentLayoutRect = NSRect(x: 0, y: 0, width: 640, height: 420)

        XCTAssertFalse(ViewerWindow.isTitleBarPoint(
            NSPoint(x: 320, y: 432),
            contentLayoutRect: contentLayoutRect,
            styleMask: [.borderless, .resizable, .fullSizeContentView]
        ))
    }

    func testTemporaryDesktopFullScreenUsesVisibleFrameAndStoresCurrentFrame() {
        let currentFrame = NSRect(x: 100, y: 90, width: 640, height: 420)
        let visibleFrame = NSRect(x: 0, y: 25, width: 1440, height: 875)

        let transition = ViewerWindow.temporaryDesktopFullScreenTransition(
            currentFrame: currentFrame,
            visibleFrame: visibleFrame,
            restoreFrame: nil,
            fallbackFrame: nil
        )

        XCTAssertEqual(transition.nextFrame, visibleFrame)
        XCTAssertEqual(transition.nextRestoreFrame, currentFrame)
    }

    func testTemporaryDesktopFullScreenRestoresSavedFrame() {
        let currentFrame = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let restoreFrame = NSRect(x: 100, y: 90, width: 640, height: 420)
        let visibleFrame = NSRect(x: 0, y: 25, width: 1440, height: 875)

        let transition = ViewerWindow.temporaryDesktopFullScreenTransition(
            currentFrame: currentFrame,
            visibleFrame: visibleFrame,
            restoreFrame: restoreFrame,
            fallbackFrame: nil
        )

        XCTAssertEqual(transition.nextFrame, restoreFrame)
        XCTAssertNil(transition.nextRestoreFrame)
    }

    func testAlreadyDesktopFullScreenUsesFallbackFrameWhenNoSavedRestoreFrame() {
        let visibleFrame = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let fallbackFrame = NSRect(x: 320, y: 190, width: 800, height: 520)

        let transition = ViewerWindow.temporaryDesktopFullScreenTransition(
            currentFrame: visibleFrame,
            visibleFrame: visibleFrame,
            restoreFrame: nil,
            fallbackFrame: fallbackFrame
        )

        XCTAssertEqual(transition.nextFrame, fallbackFrame)
        XCTAssertNil(transition.nextRestoreFrame)
    }

    func testTemporaryDesktopFullScreenFallbackPrefersFixedRestoreFrame() {
        let suitableFrame = NSRect(x: 320, y: 190, width: 800, height: 520)
        let fixedRestoreFrame = NSRect(x: 120, y: 80, width: 640, height: 420)

        XCTAssertEqual(
            ViewerWindow.temporaryDesktopFullScreenFallbackFrame(
                suitableFrame: suitableFrame,
                fixedRestoreFrame: fixedRestoreFrame
            ),
            fixedRestoreFrame
        )
    }

    func testTemporaryDesktopFullScreenFallbackUsesSuitableFrameWithoutFixedRestoreFrame() {
        let suitableFrame = NSRect(x: 320, y: 190, width: 800, height: 520)

        XCTAssertEqual(
            ViewerWindow.temporaryDesktopFullScreenFallbackFrame(
                suitableFrame: suitableFrame,
                fixedRestoreFrame: nil
            ),
            suitableFrame
        )
    }

    func testHiddenTitleBarTopDragRegionDoubleClickRequestsDesktopFillToggle() {
        let view = CanvasNSView(frame: NSRect(x: 0, y: 0, width: 640, height: 420), backend: .vision)

        XCTAssertTrue(view.debugShouldToggleDesktopFillOnMouseDown(clickCount: 2, at: CGPoint(x: 320, y: 410)))
    }

    func testHiddenTitleBarTopDragRegionSingleClickDoesNotRequestDesktopFillToggle() {
        let view = CanvasNSView(frame: NSRect(x: 0, y: 0, width: 640, height: 420), backend: .vision)

        XCTAssertFalse(view.debugShouldToggleDesktopFillOnMouseDown(clickCount: 1, at: CGPoint(x: 320, y: 410)))
    }

    func testFailedNativeFullScreenEntryRestoresOriginalStyleMaskOnce() {
        let originalMask: NSWindow.StyleMask = [.borderless, .resizable, .fullSizeContentView]
        let window = ViewerWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: originalMask,
            backing: .buffered,
            defer: false
        )

        window.prepareStyleMaskForNativeFullScreen()
        XCTAssertTrue(window.styleMask.contains(.titled))

        window.restoreStyleMaskAfterFailedFullScreenEntry()
        XCTAssertEqual(window.styleMask, originalMask)

        window.styleMask = [.titled, .resizable]
        window.restoreStyleMaskAfterFailedFullScreenEntry()
        XCTAssertEqual(window.styleMask, [.titled, .resizable])
    }

    func testSuccessfulNativeFullScreenExitClearsSavedStyleMask() {
        let originalMask: NSWindow.StyleMask = [.borderless, .resizable, .fullSizeContentView]
        let window = ViewerWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: originalMask,
            backing: .buffered,
            defer: false
        )

        window.prepareStyleMaskForNativeFullScreen()
        window.completeNativeFullScreenExit()
        window.styleMask = [.titled, .resizable]
        window.restoreStyleMaskAfterFailedFullScreenEntry()

        XCTAssertEqual(window.styleMask, [.titled, .resizable])
    }

    func testRepeatedNativeFullScreenPreparationPreservesOriginalStyleMask() {
        let originalMask: NSWindow.StyleMask = [.borderless, .resizable, .fullSizeContentView]
        let window = ViewerWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: originalMask,
            backing: .buffered,
            defer: false
        )

        window.prepareStyleMaskForNativeFullScreen()
        window.prepareStyleMaskForNativeFullScreen()
        window.restoreStyleMaskAfterFailedFullScreenEntry()

        XCTAssertEqual(window.styleMask, originalMask)
    }
}
