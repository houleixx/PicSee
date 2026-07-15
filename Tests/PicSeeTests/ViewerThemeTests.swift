import AppKit
import XCTest
@testable import PicSee

final class ViewerThemeTests: XCTestCase {
    func testDefaultsToSystemAndFallsBackFromInvalidValue() {
        withDefaults { defaults in
            XCTAssertEqual(ViewerTheme.current(in: defaults), .system)
            defaults.set(999, forKey: ViewerTheme.defaultsKey)
            XCTAssertEqual(ViewerTheme.current(in: defaults), .system)
        }
    }

    func testPersistsEveryThemeAndMapsAppearance() {
        withDefaults { defaults in
            for theme in ViewerTheme.allCases {
                ViewerTheme.set(theme, in: defaults)
                XCTAssertEqual(ViewerTheme.current(in: defaults), theme)
            }
            XCTAssertNil(ViewerTheme.system.appearance)
            XCTAssertEqual(ViewerTheme.light.appearance?.name, .aqua)
            XCTAssertEqual(ViewerTheme.dark.appearance?.name, .darkAqua)
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "PicSee.ViewerThemeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}
