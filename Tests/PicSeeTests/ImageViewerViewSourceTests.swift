import XCTest

final class ImageViewerViewSourceTests: XCTestCase {
    func testMetadataHudAllowsMouseEventsToReachCanvas() throws {
        let source = try repositoryFile("Sources/PicSee/Viewer/ImageViewerView.swift")

        XCTAssertTrue(source.contains(".allowsHitTesting(false)"))
    }

    func testMetadataHudCanHideFileInfoSeparatelyFromZoom() throws {
        let source = try repositoryFile("Sources/PicSee/Viewer/ImageViewerView.swift")

        XCTAssertTrue(source.contains("@State private var fileInfoVisible"))
        XCTAssertTrue(source.contains("if fileInfoVisible, let imageMetadataText = viewModel.imageMetadataText"))
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
