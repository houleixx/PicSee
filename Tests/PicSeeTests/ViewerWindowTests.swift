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

    func testNormalWindowUsesCurrentFrameForPersistence() {
        let window = ViewerWindow(
            contentRect: NSRect(x: 100, y: 80, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        XCTAssertEqual(window.persistableFrame, window.frame)
    }

    func testNativeFullScreenTransitionUsesCapturedFrameForPersistence() {
        let window = ViewerWindow(
            contentRect: NSRect(x: 100, y: 80, width: 800, height: 600),
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let originalFrame = window.frame

        window.prepareStyleMaskForNativeFullScreen()
        window.setFrame(NSRect(x: 0, y: 0, width: 1440, height: 900), display: false)

        XCTAssertEqual(window.persistableFrame, originalFrame)
    }

    func testFullScreenWithoutSnapshotHasNoPersistableFrame() {
        XCTAssertNil(ViewerWindow.persistableFrame(
            currentFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            capturedFrame: nil,
            isFullScreen: true
        ))
    }

    func testHiddenTitleBarExitRestoresOriginalFrame() {
        assertNativeFullScreenExit(
            entryMask: [.borderless, .resizable, .fullSizeContentView],
            exitMask: [.borderless, .resizable, .fullSizeContentView]
        )
    }

    func testChangingFromHiddenToVisibleTitleBarInFullScreenRestoresOriginalFrame() {
        assertNativeFullScreenExit(
            entryMask: [.borderless, .resizable, .fullSizeContentView],
            exitMask: [.titled, .closable, .miniaturizable, .resizable]
        )
    }

    func testChangingFromVisibleToHiddenTitleBarInFullScreenRestoresOriginalFrame() {
        assertNativeFullScreenExit(
            entryMask: [.titled, .closable, .miniaturizable, .resizable],
            exitMask: [.borderless, .resizable, .fullSizeContentView]
        )
    }

    func testFailedNativeFullScreenEntryRestoresOriginalStyleMaskOnce() {
        let originalMask: NSWindow.StyleMask = [.borderless, .resizable, .fullSizeContentView]
        let window = ViewerWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: originalMask,
            backing: .buffered,
            defer: false
        )
        let originalFrame = window.frame

        window.prepareStyleMaskForNativeFullScreen()
        XCTAssertTrue(window.styleMask.contains(.titled))
        window.setFrame(NSRect(x: 0, y: 0, width: 1440, height: 900), display: false)

        window.restoreStyleMaskAfterFailedFullScreenEntry()
        XCTAssertEqual(window.styleMask, originalMask)
        XCTAssertEqual(window.frame, originalFrame)

        let normalFrameAfterCleanup = NSRect(x: 180, y: 140, width: 720, height: 480)
        window.setFrame(normalFrameAfterCleanup, display: false)
        XCTAssertEqual(window.persistableFrame, normalFrameAfterCleanup)

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
        XCTAssertTrue(window.completeNativeFullScreenExit(restoring: originalMask))

        let normalFrameAfterCleanup = NSRect(x: 180, y: 140, width: 720, height: 480)
        window.setFrame(normalFrameAfterCleanup, display: false)
        XCTAssertEqual(window.persistableFrame, normalFrameAfterCleanup)

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
        let originalFrame = window.frame

        window.prepareStyleMaskForNativeFullScreen()
        window.setFrame(NSRect(x: 0, y: 0, width: 1440, height: 900), display: false)
        window.prepareStyleMaskForNativeFullScreen()
        window.restoreStyleMaskAfterFailedFullScreenEntry()

        XCTAssertEqual(window.styleMask, originalMask)
        XCTAssertEqual(window.frame, originalFrame)
    }

    private func assertNativeFullScreenExit(
        entryMask: NSWindow.StyleMask,
        exitMask: NSWindow.StyleMask,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let window = ViewerWindow(
            contentRect: NSRect(x: 100, y: 80, width: 800, height: 600),
            styleMask: entryMask,
            backing: .buffered,
            defer: false
        )
        let originalFrame = window.frame

        window.prepareStyleMaskForNativeFullScreen()
        window.setFrame(NSRect(x: 0, y: 0, width: 1440, height: 900), display: false)

        XCTAssertTrue(
            window.completeNativeFullScreenExit(restoring: exitMask),
            file: file,
            line: line
        )
        XCTAssertEqual(window.frame, originalFrame, file: file, line: line)
        XCTAssertEqual(window.styleMask, exitMask, file: file, line: line)

        let frameAfterExit = window.frame
        XCTAssertFalse(
            window.completeNativeFullScreenExit(restoring: entryMask),
            file: file,
            line: line
        )
        XCTAssertEqual(window.frame, frameAfterExit, file: file, line: line)
    }
}
