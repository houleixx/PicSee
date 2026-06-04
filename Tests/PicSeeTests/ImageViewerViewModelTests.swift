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

    @MainActor
    func testImagePixelSizeTextUsesLoadedImageDimensions() throws {
        let imageURL = try writePNG(named: "001.png", color: .red, size: NSSize(width: 12, height: 34))

        let viewModel = ImageViewerViewModel(imageURL: imageURL)

        XCTAssertEqual(viewModel.imagePixelSizeText, "12 × 34 px")
    }

    @MainActor
    func testImageMetadataTextIncludesFilenameFileSizeAndPixelDimensions() throws {
        let imageURL = try writePNG(named: "sample image.png", color: .red, size: NSSize(width: 12, height: 34))
        let expectedFileSize = ByteCountFormatter.string(
            fromByteCount: Int64(try Data(contentsOf: imageURL).count),
            countStyle: .file
        )

        let viewModel = ImageViewerViewModel(imageURL: imageURL)

        XCTAssertEqual(viewModel.imageMetadataText, "sample image.png | \(expectedFileSize) | 12 × 34 px")
    }

    @MainActor
    func testTitleBarTextIncludesFileMetadataAndZoomPercentage() throws {
        let imageURL = try writePNG(named: "sample image.png", color: .red, size: NSSize(width: 12, height: 34))
        let expectedFileSize = ByteCountFormatter.string(
            fromByteCount: Int64(try Data(contentsOf: imageURL).count),
            countStyle: .file
        )
        let viewModel = ImageViewerViewModel(imageURL: imageURL)
        viewModel.displayScale = 1.25

        XCTAssertEqual(viewModel.titleBarText, "sample image.png | \(expectedFileSize) | 12 × 34 px | 125%")
    }

    private func writePNG(named name: String, color: NSColor, size: NSSize = NSSize(width: 8, height: 8)) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            XCTFail("Failed to create bitmap fixture")
            return url
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to create PNG fixture")
            return url
        }

        try data.write(to: url)
        return url.standardizedFileURL
    }
}
