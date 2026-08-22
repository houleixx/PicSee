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

    func testAccessibilityPermissionExplanationDescribesBehaviorAndFallback() {
        XCTAssertEqual(
            AccessibilityPermissionSettings.explanation,
            "开启辅助功能权限，按 Finder 显示顺序预览图片。"
        )
    }

    func testAccessibilityPermissionPresentationReflectsCurrentState() {
        XCTAssertEqual(AccessibilityPermissionSettings.enabledStatus, "已经开启")
        XCTAssertEqual(AccessibilityPermissionSettings.actionTitle, "去开启")
    }

    func testAccessibilityPermissionSettingsURLTargetsAccessibilityPrivacyPane() {
        XCTAssertTrue(
            AccessibilityPermissionSettings.systemSettingsURL.absoluteString.contains("Privacy_Accessibility")
        )
    }

    func testAccessibilityPermissionPromptIsRequestedOnlyOnceWhenNotTrusted() {
        let suiteName = "AccessibilityPermissionPromptTests.notTrusted"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(
            AccessibilityPermissionPromptPreference.shouldRequestPermission(
                isTrusted: false,
                defaults: defaults
            )
        )
        XCTAssertFalse(
            AccessibilityPermissionPromptPreference.shouldRequestPermission(
                isTrusted: false,
                defaults: defaults
            )
        )
    }

    func testAccessibilityPermissionPromptIsConsumedWhenAlreadyTrusted() {
        let suiteName = "AccessibilityPermissionPromptTests.trusted"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(
            AccessibilityPermissionPromptPreference.shouldRequestPermission(
                isTrusted: true,
                defaults: defaults
            )
        )
        XCTAssertFalse(
            AccessibilityPermissionPromptPreference.shouldRequestPermission(
                isTrusted: false,
                defaults: defaults
            )
        )
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
