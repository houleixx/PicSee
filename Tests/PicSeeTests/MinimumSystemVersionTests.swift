import XCTest

final class MinimumSystemVersionTests: XCTestCase {
    func testSwiftPackageDeclaresMacOS14Minimum() throws {
        let package = try repositoryFile("Package.swift")
        XCTAssertTrue(package.contains(".macOS(.v14)"))
    }

    func testBuildScriptDeclaresMacOS14Minimum() throws {
        let script = try repositoryFile("Scripts/build-app.sh")
        XCTAssertTrue(script.contains("<key>LSMinimumSystemVersion</key>\n    <string>14.0</string>"))
    }

    func testBuildScriptHidesDockIcon() throws {
        let script = try repositoryFile("Scripts/build-app.sh")
        XCTAssertTrue(script.contains("<key>LSUIElement</key>\n    <true/>"))
    }

    func testBuildScriptDeclaresChineseLocalizationForSystemPanels() throws {
        let script = try repositoryFile("Scripts/build-app.sh")
        let localizedInfoPlist = try repositoryFile("Resources/zh-Hans.lproj/InfoPlist.strings")

        XCTAssertTrue(script.contains("<key>CFBundleDevelopmentRegion</key>\n    <string>zh-Hans</string>"))
        XCTAssertTrue(script.contains("<key>CFBundleLocalizations</key>"))
        XCTAssertTrue(script.contains("<string>zh-Hans</string>"))
        XCTAssertTrue(script.contains("Resources/*.lproj"))
        XCTAssertTrue(localizedInfoPlist.contains("\"CFBundleDisplayName\" = \"PicSee\";"))
    }

    func testBuildScriptRegistersCameraRawDocumentTypes() throws {
        let script = try repositoryFile("Scripts/build-app.sh")

        XCTAssertTrue(script.contains("<string>public.camera-raw-image</string>"))
        XCTAssertTrue(script.contains("<string>dng</string>"))
        XCTAssertTrue(script.contains("<string>cr3</string>"))
        XCTAssertTrue(script.contains("<string>nef</string>"))
        XCTAssertTrue(script.contains("<string>arw</string>"))
        XCTAssertTrue(script.contains("<string>raf</string>"))
        XCTAssertTrue(script.contains("<string>rw2</string>"))
    }

    func testResourceBundleLookupUsesPackagedAppBundleBeforeSwiftPMBundleModule() throws {
        let source = try repositoryFile("Sources/PicSee/Viewer/ImageViewerView.swift")

        let packagedBundleIndex = try XCTUnwrap(
            source.range(of: "Bundle.main.resourceURL?")?.lowerBound
        )
        let earlyReturnIndex = try XCTUnwrap(
            source.range(of: "if !bundles.isEmpty { return bundles }")?.lowerBound
        )
        let bundleModuleIndex = try XCTUnwrap(
            source.range(of: "bundles.append(.module)")?.lowerBound
        )

        XCTAssertLessThan(packagedBundleIndex, earlyReturnIndex)
        XCTAssertLessThan(earlyReturnIndex, bundleModuleIndex)
    }

    func testReadmeDeclaresMacOS14Minimum() throws {
        let readme = try repositoryFile("README.md")
        XCTAssertTrue(readme.contains("macOS 14 及以上"))
    }

    private func repositoryFile(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
