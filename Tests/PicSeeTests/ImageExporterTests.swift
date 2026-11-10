import AppKit
import XCTest
@testable import PicSee

final class ImageExporterTests: XCTestCase {
    @MainActor
    func testCGBackedImageReportsSourcePixelsRatherThanRetinaSnapshotDimensions() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 40,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = NSImage(cgImage: try XCTUnwrap(bitmap.cgImage), size: CGSize(width: 80, height: 40))
        XCTAssertEqual(ImageExporter.pixelSize(of: image), CGSize(width: 80, height: 40))
    }

    @MainActor
    func testAccessoryViewHidesJPEGQualityWithoutChangingLayoutForPNG() {
        let accessoryView = ImageExportAccessoryView(defaultPixelSize: CGSize(width: 100, height: 80))

        XCTAssertTrue(accessoryView.debugQualityControlsVisible)
        XCTAssertFalse(accessoryView.debugQualityRowHidden)

        accessoryView.debugSelectPNG()

        XCTAssertFalse(accessoryView.debugQualityControlsVisible)
        XCTAssertFalse(accessoryView.debugQualityRowHidden)
        XCTAssertEqual(accessoryView.exportOptions.format, .png)

        accessoryView.debugSelectJPEG()

        XCTAssertTrue(accessoryView.debugQualityControlsVisible)
        XCTAssertFalse(accessoryView.debugQualityRowHidden)
    }

    @MainActor
    func testAccessoryViewUsesFixedLabelColumnWidth() {
        XCTAssertEqual(ImageExportAccessoryView.debugLabelColumnWidth, 94)
    }

    @MainActor
    func testAccessoryViewUsesFixedSizeFieldWidthForPixelUnitLabels() {
        XCTAssertEqual(ImageExportAccessoryView.debugSizeFieldWidth, 150)
    }

    @MainActor
    func testAccessoryViewUsesRoomierNativeSpacing() {
        let accessoryView = ImageExportAccessoryView(defaultPixelSize: CGSize(width: 100, height: 80))

        XCTAssertEqual(accessoryView.frame.size, CGSize(width: 460, height: 222))
        XCTAssertEqual(accessoryView.debugGridRowSpacing, 10)
        XCTAssertEqual(accessoryView.debugGridColumnSpacing, 12)
        XCTAssertEqual(accessoryView.debugGridLeadingInset, 38)
        XCTAssertEqual(accessoryView.debugPixelUnitSpacing, 8)
        XCTAssertEqual(accessoryView.debugPixelUnitTextColor, NSColor.tertiaryLabelColor)
    }

    @MainActor
    func testAccessoryViewMatchesSavePanelLabelAndControlRhythm() {
        let accessoryView = ImageExportAccessoryView(defaultPixelSize: CGSize(width: 100, height: 80))

        XCTAssertEqual(accessoryView.debugLabelTexts, [L10n.text("格式:"), L10n.text("尺寸模式:"), L10n.text("宽度:"), L10n.text("高度:"), L10n.text("JPEG 质量:"), L10n.text("预计大小:")])
        XCTAssertEqual(accessoryView.debugFormatPopupWidth, 150)
        XCTAssertEqual(accessoryView.debugResizeModePopupWidth, 150)
    }

    @MainActor
    func testAccessoryViewKeepsFixedSizeFieldsEditable() {
        let accessoryView = ImageExportAccessoryView(defaultPixelSize: CGSize(width: 100, height: 80))

        accessoryView.debugSelectFixedSizeMode()
        accessoryView.debugSetWidth(320)
        accessoryView.debugSetHeight(240)

        XCTAssertTrue(accessoryView.debugWidthFieldEnabled)
        XCTAssertTrue(accessoryView.debugHeightFieldEnabled)
        XCTAssertEqual(accessoryView.exportOptions.pixelSize, CGSize(width: 320, height: 240))
    }

    @MainActor
    func testAccessoryViewCalculatesHeightFromProportionalWidth() {
        let accessoryView = ImageExportAccessoryView(defaultPixelSize: CGSize(width: 400, height: 200))

        accessoryView.debugSelectProportionalWidthMode()
        accessoryView.debugSetWidth(100)

        XCTAssertTrue(accessoryView.debugWidthFieldEnabled)
        XCTAssertFalse(accessoryView.debugHeightFieldEnabled)
        XCTAssertEqual(accessoryView.exportOptions.pixelSize, CGSize(width: 100, height: 50))
    }

    @MainActor
    func testAccessoryViewCalculatesWidthFromProportionalHeight() {
        let accessoryView = ImageExportAccessoryView(defaultPixelSize: CGSize(width: 400, height: 200))

        accessoryView.debugSelectProportionalHeightMode()
        accessoryView.debugSetHeight(25)

        XCTAssertFalse(accessoryView.debugWidthFieldEnabled)
        XCTAssertTrue(accessoryView.debugHeightFieldEnabled)
        XCTAssertEqual(accessoryView.exportOptions.pixelSize, CGSize(width: 50, height: 25))
    }

    func testExportsResizedJPEG() throws {
        let image = try makeImage(size: NSSize(width: 20, height: 10), color: .red)
        let url = temporaryURL(named: "export.jpg")

        try ImageExporter.export(
            image,
            to: url,
            options: ImageExportOptions(format: .jpeg(quality: 0.82), pixelSize: CGSize(width: 10, height: 5))
        )

        let exported = try XCTUnwrap(NSImage(contentsOf: url))
        XCTAssertEqual(ImageExporter.pixelSize(of: exported), CGSize(width: 10, height: 5))
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 0)
    }

    func testExportsPNGAtOriginalSizeWhenNoResizeIsProvided() throws {
        let image = try makeImage(size: NSSize(width: 12, height: 8), color: .blue)
        let url = temporaryURL(named: "export.png")

        try ImageExporter.export(
            image,
            to: url,
            options: ImageExportOptions(format: .png, pixelSize: nil)
        )

        let exported = try XCTUnwrap(NSImage(contentsOf: url))
        XCTAssertEqual(ImageExporter.pixelSize(of: exported), CGSize(width: 12, height: 8))
    }

    func testCalculatedSizeMatchesSavedFileForEachFormatAndSize() throws {
        let image = try makeImage(size: NSSize(width: 80, height: 40), color: .red)
        for format in [ImageExportFormat.jpeg(quality: 0.4), .jpeg(quality: 0.9), .png] {
            for size in [CGSize?.none, CGSize(width: 20, height: 10)] {
                let options = ImageExportOptions(format: format, pixelSize: size)
                let url = temporaryURL(named: "size.\(format.pathExtension)")
                defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                try ImageExporter.export(image, to: url, options: options)
                XCTAssertEqual(try ImageExporter.encodedSize(of: image, options: options), try Data(contentsOf: url).count)
            }
        }
    }

    @MainActor
    func testSizePreviewUpdatesToLatestQualityDimensionsAndFormat() async throws {
        let image = try makeImage(size: NSSize(width: 80, height: 40), color: .red)
        let view = ImageExportAccessoryView(defaultPixelSize: CGSize(width: 80, height: 40), image: image)
        defer { view.cancelSizeCalculation() }

        for quality in [0.4, 1.0] {
            view.debugSetQuality(quality)
            XCTAssertEqual(view.exportOptions.format, .jpeg(quality: quality))
            try await waitForSizePreview(view, image: image)
        }
        view.debugSetWidth(40)
        view.debugSetHeight(20)
        view.debugSelectPNG()
        try await waitForSizePreview(view, image: image)
    }

    @MainActor
    private func waitForSizePreview(_ view: ImageExportAccessoryView, image: NSImage) async throws {
        let count = try ImageExporter.encodedSize(of: image, options: view.exportOptions)
        let expected = ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
        for _ in 0..<100 {
            if view.debugEstimatedSizeText == expected { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(view.debugEstimatedSizeText, expected)
    }

    private func makeImage(size: NSSize, color: NSColor) throws -> NSImage {
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
            throw XCTSkip("Could not create bitmap")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    private func temporaryURL(named filename: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(filename)
    }
}
