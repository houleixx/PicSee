import AppKit
import XCTest
@testable import PicSee

final class ViewerTitleBarPreferenceTests: XCTestCase {
    func testDefaultsToHiddenTitleBar() {
        let suiteName = "PicSee.TitleBarPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(ViewerTitleBarPreference.isVisible(in: defaults))
    }

    func testPersistsTitleBarVisibility() {
        let suiteName = "PicSee.TitleBarPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        ViewerTitleBarPreference.setVisible(true, in: defaults)

        XCTAssertTrue(ViewerTitleBarPreference.isVisible(in: defaults))
    }

    func testStyleMaskMatchesTitleBarPreference() {
        let hidden = ViewerTitleBarPreference.styleMask(titleBarVisible: false)
        XCTAssertEqual(hidden, [.borderless, .resizable, .fullSizeContentView])
        XCTAssertFalse(hidden.contains(.titled))

        let visible = ViewerTitleBarPreference.styleMask(titleBarVisible: true)
        XCTAssertEqual(visible, [.titled, .closable, .miniaturizable, .resizable])
        XCTAssertTrue(visible.contains(.titled))
        XCTAssertTrue(visible.contains(.closable))
    }

    @MainActor
    func testWindowFramePreservesContentFrameWhenTitleBarIsVisible() {
        let contentFrame = NSRect(x: 120, y: 80, width: 800, height: 600)

        let hiddenFrame = ViewerTitleBarPreference.windowFrame(
            forContentFrame: contentFrame,
            titleBarVisible: false
        )
        let visibleFrame = ViewerTitleBarPreference.windowFrame(
            forContentFrame: contentFrame,
            titleBarVisible: true
        )

        XCTAssertEqual(hiddenFrame, contentFrame)
        XCTAssertGreaterThan(visibleFrame.height, contentFrame.height)
        XCTAssertEqual(visibleFrame.width, contentFrame.width, accuracy: 0.001)
        XCTAssertEqual(visibleFrame.minX, contentFrame.minX, accuracy: 0.001)
        XCTAssertEqual(
            NSWindow.contentRect(
                forFrameRect: visibleFrame,
                styleMask: ViewerTitleBarPreference.styleMask(titleBarVisible: true)
            ),
            contentFrame
        )
    }
}
