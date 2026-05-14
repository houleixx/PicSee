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
