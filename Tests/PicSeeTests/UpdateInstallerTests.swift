import XCTest
@testable import PicSee

final class UpdateInstallerTests: XCTestCase {
    func testRejectsHTTPFailuresAndInsecureRedirects() throws {
        for (url, status) in [("https://example.com/update.dmg", 404), ("http://example.com/update.dmg", 200)] {
            let response = try XCTUnwrap(HTTPURLResponse(url: URL(string: url)!, statusCode: status,
                                                       httpVersion: nil, headerFields: nil))
            XCTAssertThrowsError(try UpdateInstaller.validateResponse(response))
        }
        let response = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://example.com/update.dmg")!,
                                                   statusCode: 200, httpVersion: nil, headerFields: nil))
        XCTAssertNoThrow(try UpdateInstaller.validateResponse(response))
    }

    func testRejectsEmptyAndTruncatedDownloads() {
        XCTAssertThrowsError(try UpdateInstaller.validateLength(downloaded: 0, expected: -1))
        XCTAssertThrowsError(try UpdateInstaller.validateLength(downloaded: 90, expected: 100))
        XCTAssertNoThrow(try UpdateInstaller.validateLength(downloaded: 100, expected: 100))
        XCTAssertNoThrow(try UpdateInstaller.validateLength(downloaded: 100, expected: -1))
    }

    func testInstallerReplacesApplicationAfterValidation() throws {
        let result = try runTransaction(failure: "")
        XCTAssertEqual(result.exit, 0)
        XCTAssertEqual(result.contents, "new")
        XCTAssertEqual(result.status, "success\n")
        XCTAssertFalse(result.hasBackup)
    }

    func testInvalidSignaturePreservesOriginalApplication() throws {
        let result = try runTransaction(failure: "validation")
        XCTAssertNotEqual(result.exit, 0)
        XCTAssertEqual(result.contents, "old")
        XCTAssertEqual(result.status, "failed\n")
    }

    func testFailedFinalRenameRestoresOriginalApplication() throws {
        let result = try runTransaction(failure: "rename")
        XCTAssertNotEqual(result.exit, 0)
        XCTAssertEqual(result.contents, "old")
        XCTAssertEqual(result.status, "failed\n")
        XCTAssertFalse(result.hasBackup)
    }

    func testFailedLaunchRestoresOriginalApplication() throws {
        let result = try runTransaction(failure: "launch")
        XCTAssertNotEqual(result.exit, 0)
        XCTAssertEqual(result.contents, "old")
        XCTAssertEqual(result.status, "failed\n")
        XCTAssertFalse(result.hasBackup)
    }

    private func runTransaction(failure: String) throws -> (exit: Int32, contents: String, status: String, hasBackup: Bool) {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("PicSee-InstallerTests-\(UUID().uuidString)")
        try files.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: directory) }
        let target = directory.appendingPathComponent("PicSee.app")
        let staged = directory.appendingPathComponent("staged.app")
        let tools = directory.appendingPathComponent("tools")
        for url in [target, staged, tools] { try files.createDirectory(at: url, withIntermediateDirectories: false) }
        try "old".write(to: target.appendingPathComponent("marker"), atomically: true, encoding: .utf8)
        try "new".write(to: staged.appendingPathComponent("marker"), atomically: true, encoding: .utf8)
        let commands = [
            "codesign": "if [ \"$PICSEE_TEST_FAILURE\" = validation ]; then exit 1; fi",
            "spctl": "exit 0",
            "open": "if [ \"$PICSEE_TEST_FAILURE\" = launch ] && [ \"$(cat \"$1/marker\")\" = new ]; then exit 1; fi",
            "mv": "if [ \"$PICSEE_TEST_FAILURE\" = rename ] && [ \"$1\" = \"$PICSEE_TEST_STAGING\" ]; then exit 1; fi\n/bin/mv \"$@\""
        ]
        for (name, body) in commands {
            let url = tools.appendingPathComponent(name)
            try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
            try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        let script = directory.appendingPathComponent("install.zsh")
        // Substitute only external OS commands; execute the actual transaction and trap.
        let body = UpdateInstaller.script.replacingOccurrences(of: "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
                                                               with: "PATH=\"\(tools.path):/usr/bin:/bin:/usr/sbin:/sbin\"")
        try body.write(to: script, atomically: true, encoding: .utf8)
        let status = directory.appendingPathComponent("status")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path, staged.path, target.path, status.path, "99999999"]
        var environment = ProcessInfo.processInfo.environment
        environment["PICSEE_TEST_FAILURE"] = failure
        environment["PICSEE_TEST_STAGING"] = staged.path
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let contents = try String(contentsOf: target.appendingPathComponent("marker"), encoding: .utf8)
        let hasBackup = try files.contentsOfDirectory(atPath: directory.path).contains { $0.contains(".previous.") }
        return (process.terminationStatus, contents, try String(contentsOf: status, encoding: .utf8), hasBackup)
    }
}
