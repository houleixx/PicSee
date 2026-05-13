import AppKit
import XCTest
@testable import PicSee

final class ImageViewerViewModelTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicSeeViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    @MainActor
    func testLoadsValidImageAndBuildsNavigator() throws {
        let first = try writePNG(named: "001.png", color: .red)
        let second = try writePNG(named: "002.png", color: .blue)

        let viewModel = ImageViewerViewModel(imageURL: first)

        XCTAssertEqual(viewModel.currentURL, first.standardizedFileURL)
        XCTAssertNotNil(viewModel.image)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.currentFilename, "001.png")
        XCTAssertEqual(viewModel.nextURL, second.standardizedFileURL)
    }

    @MainActor
    func testInvalidImageShowsErrorState() throws {
        let invalid = temporaryDirectory.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: invalid)

        let viewModel = ImageViewerViewModel(imageURL: invalid)

        XCTAssertNil(viewModel.image)
        XCTAssertEqual(viewModel.currentURL, invalid.standardizedFileURL)
        XCTAssertEqual(viewModel.currentFilename, "broken.jpg")
        XCTAssertNotNil(viewModel.errorMessage)
    }

    @MainActor
    func testNavigateNextResetsZoomAndPan() throws {
        let first = try writePNG(named: "001.png", color: .red)
        let second = try writePNG(named: "002.png", color: .blue)

        let viewModel = ImageViewerViewModel(imageURL: first)
        viewModel.zoomScale = 3
        viewModel.panOffset = CGSize(width: 40, height: 50)

        viewModel.navigate(to: second)

        XCTAssertEqual(viewModel.currentURL, second.standardizedFileURL)
        XCTAssertEqual(viewModel.zoomScale, 1)
        XCTAssertEqual(viewModel.panOffset, .zero)
        XCTAssertNotNil(viewModel.image)
    }

    private func writePNG(named name: String, color: NSColor) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()

        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            XCTFail("Failed to create PNG fixture")
            return url
        }

        try data.write(to: url)
        return url.standardizedFileURL
    }
}
