import XCTest
@testable import PicSee

final class DefaultImageAppSettingsTests: XCTestCase {
    func testDefaultFormatListCoversCommonImageTypes() {
        let contentTypes = Set(DefaultImageAppSettings.formats.map(\.contentType))

        XCTAssertTrue(contentTypes.contains("public.jpeg"))
        XCTAssertTrue(contentTypes.contains("public.png"))
        XCTAssertTrue(contentTypes.contains("com.compuserve.gif"))
        XCTAssertTrue(contentTypes.contains("public.heic"))
        XCTAssertTrue(contentTypes.contains("public.tiff"))
        XCTAssertTrue(contentTypes.contains("com.microsoft.bmp"))
        XCTAssertTrue(contentTypes.contains("org.webmproject.webp"))
        XCTAssertTrue(contentTypes.contains("public.camera-raw-image"))
    }

    func testFallbackInstructionsExplainFinderGetInfoForUnlistedFormats() {
        XCTAssertTrue(DefaultImageAppSettings.fallbackInstructions.contains("显示简介"))
        XCTAssertTrue(DefaultImageAppSettings.fallbackInstructions.contains("打开方式"))
        XCTAssertTrue(DefaultImageAppSettings.fallbackInstructions.contains("全部更改"))
    }

    func testLaunchSettingsWindowOnlyForDirectLaunchWithoutOpenedImages() {
        XCTAssertTrue(
            DefaultImageAppSettings.shouldShowSettingsWindowAfterLaunch(
                didReceiveOpenRequest: false,
                hasOpenViewer: false
            )
        )

        XCTAssertFalse(
            DefaultImageAppSettings.shouldShowSettingsWindowAfterLaunch(
                didReceiveOpenRequest: true,
                hasOpenViewer: false
            )
        )

        XCTAssertFalse(
            DefaultImageAppSettings.shouldShowSettingsWindowAfterLaunch(
                didReceiveOpenRequest: false,
                hasOpenViewer: true
            )
        )
    }
}
