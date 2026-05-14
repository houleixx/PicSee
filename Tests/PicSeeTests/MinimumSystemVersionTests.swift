import XCTest

final class MinimumSystemVersionTests: XCTestCase {
    func testSwiftPackageDeclaresMacOS13Minimum() throws {
        let package = try repositoryFile("Package.swift")
        XCTAssertTrue(package.contains(".macOS(.v13)"))
    }

    func testBuildScriptDeclaresMacOS13Minimum() throws {
        let script = try repositoryFile("Scripts/build-app.sh")
        XCTAssertTrue(script.contains("<key>LSMinimumSystemVersion</key>\n    <string>13.0</string>"))
    }

    func testBuildScriptHidesDockIcon() throws {
        let script = try repositoryFile("Scripts/build-app.sh")
        XCTAssertTrue(script.contains("<key>LSUIElement</key>\n    <true/>"))
    }

    func testReadmeDeclaresMacOS13Minimum() throws {
        let readme = try repositoryFile("README.md")
        XCTAssertTrue(readme.contains("macOS 13 及以上"))
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
