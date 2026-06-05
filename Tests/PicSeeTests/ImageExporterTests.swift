import AppKit
import XCTest
@testable import PicSee

final class ImageExporterTests: XCTestCase {
    @MainActor
    func testAccessoryViewHidesJPEGQualityControlsForPNGWithoutCollapsingRow() {
        let accessoryView = ImageExportAccessoryView(defaultPixelSize: CGSize(width: 100, height: 80))

        XCTAssertTrue(accessoryView.debugQualityControlsVisible)

        accessoryView.debugSelectPNG()

        XCTAssertFalse(accessoryView.debugQualityControlsVisible)
        XCTAssertEqual(accessoryView.exportOptions.format, .png)

        accessoryView.debugSelectJPEG()

        XCTAssertTrue(accessoryView.debugQualityControlsVisible)
    }

    @MainActor
    func testAccessoryViewUsesFixedLabelColumnWidth() {
        XCTAssertEqual(ImageExportAccessoryView.debugLabelColumnWidth, 108)
    }

    @MainActor
    func testAccessoryViewUsesFixedSizeFieldWidthForPixelUnitLabels() {
        XCTAssertEqual(ImageExportAccessoryView.debugSizeFieldWidth, 150)
    }

    @MainActor
    func testAccessoryViewUsesRoomierNativeSpacing() {
        let accessoryView = ImageExportAccessoryView(defaultPixelSize: CGSize(width: 100, height: 80))

        XCTAssertEqual(accessoryView.frame.size, CGSize(width: 460, height: 190))
        XCTAssertEqual(accessoryView.debugGridRowSpacing, 10)
        XCTAssertEqual(accessoryView.debugGridColumnSpacing, 0)
        XCTAssertEqual(accessoryView.debugPixelUnitSpacing, 8)
        XCTAssertEqual(accessoryView.debugPixelUnitTextColor, NSColor.tertiaryLabelColor)
    }

    @MainActor
    func testAccessoryViewMatchesSavePanelLabelAndControlRhythm() {
        let accessoryView = ImageExportAccessoryView(defaultPixelSize: CGSize(width: 100, height: 80))

        XCTAssertEqual(accessoryView.debugLabelTexts, ["格式:", "尺寸模式:", "宽度:", "高度:", "JPEG 质量:"])
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
