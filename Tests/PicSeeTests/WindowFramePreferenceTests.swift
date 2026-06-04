import AppKit
import XCTest
@testable import PicSee

final class WindowFramePreferenceTests: XCTestCase {
    func testPersistsWindowFrame() {
        let suiteName = "PicSee.WindowFramePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let frame = NSRect(x: 120, y: 80, width: 640, height: 420)

        WindowFramePreference.save(frame, in: defaults)

        XCTAssertEqual(
            WindowFramePreference.savedFrame(
                in: defaults,
                fitting: NSRect(x: 0, y: 0, width: 1200, height: 900),
                minimumSize: NSSize(width: 320, height: 220)
            ),
            frame
        )
    }

    func testClampsSavedWindowFrameIntoVisibleScreen() throws {
        let suiteName = "PicSee.WindowFramePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        WindowFramePreference.save(NSRect(x: 900, y: 700, width: 500, height: 400), in: defaults)

        let frame = try XCTUnwrap(WindowFramePreference.savedFrame(
            in: defaults,
            fitting: NSRect(x: 0, y: 0, width: 1000, height: 800),
            minimumSize: NSSize(width: 320, height: 220)
        ))

        XCTAssertEqual(frame.maxX, 1000, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, 800, accuracy: 0.001)
        XCTAssertEqual(frame.width, 500, accuracy: 0.001)
        XCTAssertEqual(frame.height, 400, accuracy: 0.001)
    }

    func testFixedWindowFrameIsOnlyReturnedWhenEnabled() throws {
        let suiteName = "PicSee.WindowFramePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let frame = NSRect(x: 120, y: 80, width: 640, height: 420)

        WindowFramePreference.saveFixedFrame(frame, in: defaults)

        XCTAssertNil(WindowFramePreference.fixedFrame(
            in: defaults,
            fitting: NSRect(x: 0, y: 0, width: 1200, height: 900),
            minimumSize: NSSize(width: 320, height: 220)
        ))

        WindowFramePreference.setFixedEnabled(true, in: defaults)

        XCTAssertEqual(
            WindowFramePreference.fixedFrame(
                in: defaults,
                fitting: NSRect(x: 0, y: 0, width: 1200, height: 900),
                minimumSize: NSSize(width: 320, height: 220)
            ),
            frame
        )
    }

    func testResizeAnchorsRespectMinimumSize() {
        let start = NSRect(x: 100, y: 100, width: 500, height: 360)
        let minimum = NSSize(width: 320, height: 220)

        let bottomRight = WindowResizeGeometry.frame(
            from: start,
            anchor: .bottomRight,
            delta: CGSize(width: -300, height: 260),
            minimumSize: minimum
        )
        XCTAssertEqual(bottomRight.width, 320, accuracy: 0.001)
        XCTAssertEqual(bottomRight.height, 220, accuracy: 0.001)
        XCTAssertEqual(bottomRight.minX, start.minX, accuracy: 0.001)
        XCTAssertEqual(bottomRight.maxY, start.maxY, accuracy: 0.001)

        let topLeft = WindowResizeGeometry.frame(
            from: start,
            anchor: .topLeft,
            delta: CGSize(width: 260, height: -220),
            minimumSize: minimum
        )
        XCTAssertEqual(topLeft.width, 320, accuracy: 0.001)
        XCTAssertEqual(topLeft.height, 220, accuracy: 0.001)
        XCTAssertEqual(topLeft.maxX, start.maxX, accuracy: 0.001)
        XCTAssertEqual(topLeft.minY, start.minY, accuracy: 0.001)
    }
}
