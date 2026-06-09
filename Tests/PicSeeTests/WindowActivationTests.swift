import XCTest

final class WindowActivationTests: XCTestCase {
    func testViewerActivatesApplicationBeforeOrderingWindowFront() throws {
        let source = try repositoryFile("Sources/PicSee/App/WindowManager.swift")

        let regularPolicyIndex = try XCTUnwrap(source.range(of: "NSApp.setActivationPolicy(.regular)")?.lowerBound)
        let activationIndex = try XCTUnwrap(source.range(of: "NSRunningApplication.current.activate")?.lowerBound)
        let orderFrontIndex = try XCTUnwrap(source.range(of: "window.orderFrontRegardless()")?.lowerBound)

        XCTAssertLessThan(regularPolicyIndex, activationIndex)
        XCTAssertLessThan(activationIndex, orderFrontIndex)
    }

    func testViewerRetriesFrontOrderingAfterLaunchServicesActivationSettles() throws {
        let source = try repositoryFile("Sources/PicSee/App/WindowManager.swift")

        XCTAssertTrue(source.contains("window.orderFrontRegardless()"))
        XCTAssertTrue(source.contains("DispatchQueue.main.async"))
        XCTAssertTrue(source.contains("NSApp.activate(ignoringOtherApps: true)"))
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
