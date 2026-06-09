import AppKit
import ImageIO
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
        viewModel.rotateRight()

        viewModel.navigate(to: second)

        XCTAssertEqual(viewModel.currentURL, second.standardizedFileURL)
        XCTAssertEqual(viewModel.zoomScale, 1)
        XCTAssertEqual(viewModel.panOffset, .zero)
        XCTAssertEqual(viewModel.rotationDegrees, 0)
        XCTAssertNotNil(viewModel.image)
    }

    @MainActor
    func testShowActualSizeAdjustsZoomToOneHundredPercentDisplayScale() throws {
        let imageURL = try writePNG(named: "001.png", color: .red)
        let viewModel = ImageViewerViewModel(imageURL: imageURL)
        viewModel.zoomScale = 1
        viewModel.displayScale = 0.5
        viewModel.panOffset = CGSize(width: 20, height: 30)

        viewModel.showActualSize()

        XCTAssertEqual(viewModel.zoomScale, 2, accuracy: 0.001)
        XCTAssertEqual(viewModel.panOffset, .zero)
    }

    @MainActor
    func testFitToWindowResetsZoomAndPan() throws {
        let imageURL = try writePNG(named: "001.png", color: .red)
        let viewModel = ImageViewerViewModel(imageURL: imageURL)
        viewModel.zoomScale = 2
        viewModel.panOffset = CGSize(width: 20, height: 30)

        viewModel.fitToWindow()

        XCTAssertEqual(viewModel.zoomScale, 1)
        XCTAssertEqual(viewModel.panOffset, .zero)
    }

    @MainActor
    func testZoomButtonsCreateFixedStepZoomRequests() throws {
        let imageURL = try writePNG(named: "001.png", color: .red)
        let viewModel = ImageViewerViewModel(imageURL: imageURL)

        viewModel.zoomIn()
        let zoomInRequest = try XCTUnwrap(viewModel.zoomRequest)
        XCTAssertEqual(zoomInRequest.multiplier, 1.25, accuracy: 0.001)

        viewModel.zoomOut()
        let zoomOutRequest = try XCTUnwrap(viewModel.zoomRequest)
        XCTAssertEqual(zoomOutRequest.multiplier, 0.8, accuracy: 0.001)
        XCTAssertNotEqual(zoomInRequest.id, zoomOutRequest.id)

        viewModel.clearZoomRequest(id: zoomOutRequest.id)
        XCTAssertNil(viewModel.zoomRequest)
    }

    @MainActor
    func testRotationWrapsInNinetyDegreeStepsAndResetsPan() throws {
        let imageURL = try writePNG(named: "001.png", color: .red)
        let viewModel = ImageViewerViewModel(imageURL: imageURL)
        viewModel.panOffset = CGSize(width: 20, height: 30)

        viewModel.rotateLeft()
        XCTAssertEqual(viewModel.rotationDegrees, 90)
        XCTAssertEqual(viewModel.panOffset, .zero)

        viewModel.rotateRight()
        XCTAssertEqual(viewModel.rotationDegrees, 0)

        viewModel.rotateRight()
        XCTAssertEqual(viewModel.rotationDegrees, 270)
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

    func testImageParametersTextIncludesCameraExposureApertureAndLensMetadata() throws {
        let metadata = try XCTUnwrap(ImageParameterMetadata(properties: [
            kCGImagePropertyPixelWidth: 2448,
            kCGImagePropertyPixelHeight: 3264,
            kCGImagePropertyDPIWidth: 72,
            kCGImagePropertyDPIHeight: 72,
            kCGImagePropertyProfileName: "sRGB IEC61966-2.1",
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Fujifilm",
                kCGImagePropertyTIFFModel: "X100V"
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2016:07:25 15:27:00",
                kCGImagePropertyExifExposureTime: 0.008,
                kCGImagePropertyExifFNumber: 2.8,
                kCGImagePropertyExifISOSpeedRatings: [400],
                kCGImagePropertyExifFocalLength: 23,
                kCGImagePropertyExifLensModel: "23mm F2",
                kCGImagePropertyExifFlash: 0
            ]
        ]))
        let text = metadata.displayText

        XCTAssertTrue(text.contains("创建时间: 2016年07月25日 15:27"))
        XCTAssertTrue(text.contains("尺寸: 2448 × 3264 px"))
        XCTAssertTrue(text.contains("分辨率: 72×72"))
        XCTAssertTrue(text.contains("色彩空间: sRGB IEC61966-2.1"))
        XCTAssertTrue(text.contains("相机: Fujifilm X100V"))
        XCTAssertTrue(text.contains("镜头: 23mm F2"))
        XCTAssertTrue(text.contains("快门: 1/125 s"))
        XCTAssertTrue(text.contains("光圈: f/2.8"))
        XCTAssertTrue(text.contains("ISO: 400"))
        XCTAssertTrue(text.contains("焦距: 23 mm"))
        XCTAssertTrue(text.contains("闪光灯: 否"))
    }

    @MainActor
    func testImageParameterMetadataReturnsNilWithoutAnyProperties() throws {
        XCTAssertNil(ImageParameterMetadata(properties: [:]))
    }

    @MainActor
    func testImageParametersTextFallsBackToFileCreationDateWhenMetadataDateIsMissing() throws {
        let imageURL = try writePNG(named: "fallback.png", color: .red)
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone.current
        components.year = 2016
        components.month = 7
        components.day = 25
        components.hour = 15
        components.minute = 30
        components.second = 0
        let creationDate = try XCTUnwrap(components.date)
        try FileManager.default.setAttributes([.creationDate: creationDate], ofItemAtPath: imageURL.path)

        let viewModel = ImageViewerViewModel(imageURL: imageURL)

        XCTAssertTrue(viewModel.imageParametersText?.contains("创建时间: 2016年07月25日 15:30") ?? false)
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
