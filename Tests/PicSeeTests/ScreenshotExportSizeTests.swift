import AppKit
import XCTest
@testable import PicSee

final class ScreenshotExportSizeTests: XCTestCase {
    func testSelectedSizeIsIndependentOfViewerZoom() {
        let source = CGSize(width: 600, height: 400)
        for scale: CGFloat in [0.25, 0.5, 1, 2] {
            XCTAssertEqual(ScreenshotExportSizeMode.selectedSize.pixelSize(sourceSize: source, displayScale: scale), source)
        }
    }

    func testRestoringOriginalRatioUsesInverseDisplayScale() {
        let source = CGSize(width: 600, height: 400)
        XCTAssertEqual(ScreenshotExportSizeMode.imageScale.pixelSize(sourceSize: source, displayScale: 0.5),
                       CGSize(width: 1200, height: 800))
        XCTAssertEqual(ScreenshotExportSizeMode.imageScale.pixelSize(sourceSize: source, displayScale: 0.25),
                       CGSize(width: 2400, height: 1600))
        XCTAssertEqual(ScreenshotExportSizeMode.imageScale.pixelSize(sourceSize: source, displayScale: 2), CGSize(width: 300, height: 200))
    }

    func testOutputRoundsToWholePixelsAndInvalidScalesDoNotEnlarge() {
        XCTAssertEqual(ScreenshotExportSizeMode.imageScale.pixelSize(
            sourceSize: CGSize(width: 7, height: 3), displayScale: 0.4), CGSize(width: 18, height: 8))
        for scale: CGFloat in [0, -1, .nan, .infinity] {
            XCTAssertEqual(ScreenshotExportSizeMode.imageScale.scaleFactor(displayScale: scale), 1)
        }
    }

    @MainActor
    func testSaveAccessoryDefaultsToSelectedSizeAndRecalculatesOnModeChange() throws {
        let accessory = ScreenshotExportAccessoryView(sourceSize: CGSize(width: 600, height: 400), displayScale: 0.5)
        let grid = try XCTUnwrap(accessory.subviews.compactMap { $0 as? NSGridView }.first)
        let selectedSizeLabel = try XCTUnwrap(grid.cell(atColumnIndex: 1, rowIndex: 1).contentView as? NSTextField)
        let factorLabel = try XCTUnwrap(grid.cell(atColumnIndex: 1, rowIndex: 2).contentView as? NSTextField)
        let outputLabel = try XCTUnwrap(grid.cell(atColumnIndex: 1, rowIndex: 3).contentView as? NSTextField)
        XCTAssertEqual(accessory.selectedMode, .selectedSize)
        XCTAssertEqual(grid.numberOfRows, 4)
        XCTAssertTrue(grid.row(at: 2).isHidden)
        XCTAssertEqual(selectedSizeLabel.stringValue, "宽：600 × 高：400 px")
        XCTAssertEqual(factorLabel.stringValue, "1 ×（100%）")
        XCTAssertEqual(outputLabel.stringValue, "宽：600 × 高：400 px")
        XCTAssertEqual(accessory.exportOptions.pixelSize, CGSize(width: 600, height: 400))
        accessory.selectedMode = .imageScale
        XCTAssertFalse(grid.row(at: 2).isHidden)
        XCTAssertEqual(accessory.exportOptions.pixelSize, CGSize(width: 1200, height: 800))
        XCTAssertEqual(factorLabel.stringValue, "2 ×（200%）")
        XCTAssertEqual(outputLabel.stringValue, "宽：1200 × 高：800 px")
        XCTAssertEqual(selectedSizeLabel.stringValue, "宽：600 × 高：400 px")
        accessory.selectedMode = .selectedSize
        XCTAssertTrue(grid.row(at: 2).isHidden)
        XCTAssertEqual(accessory.exportOptions.pixelSize, CGSize(width: 600, height: 400))
        XCTAssertEqual(factorLabel.stringValue, "1 ×（100%）")
        XCTAssertEqual(outputLabel.stringValue, "宽：600 × 高：400 px")
    }

    @MainActor
    func testSavedPNGUsesChosenDimensionsAndIncludesAnnotations() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 40,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = NSImage(size: CGSize(width: 80, height: 40))
        image.addRepresentation(bitmap)
        let document = try ScreenshotDocument(image: image, rotationDegrees: 0)
        document.selectAll()
        document.state.annotations = [ScreenshotAnnotation(tool: .pen,
            points: [CGPoint(x: 0, y: 20), CGPoint(x: 80, y: 20)], color: .red, width: 20)]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for mode in ScreenshotExportSizeMode.allCases {
            let accessory = ScreenshotExportAccessoryView(sourceSize: document.pixelSize, displayScale: 0.25)
            accessory.selectedMode = mode
            let url = directory.appendingPathComponent("\(mode.rawValue).png")
            try ImageExporter.export(document.renderedImage(), to: url, options: accessory.exportOptions)
            let saved = try XCTUnwrap(NSImage(contentsOf: url))
            XCTAssertEqual(ImageExporter.pixelSize(of: saved), accessory.exportOptions.pixelSize)
            let pixels = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
            let center = try XCTUnwrap(pixels.colorAt(x: pixels.pixelsWide / 2, y: pixels.pixelsHigh / 2))
            XCTAssertGreaterThan(center.redComponent, 0.9)
            XCTAssertGreaterThan(center.alphaComponent, 0.9)
        }
    }
    @MainActor
    func testSaveParametersStayRightAlignedAcrossWidthsAndModes() throws {
        let accessory = ScreenshotExportAccessoryView(sourceSize: CGSize(width: 600, height: 400), displayScale: 0.5)
        let grid = try XCTUnwrap(accessory.subviews.compactMap { $0 as? NSGridView }.first)
        let popup = try XCTUnwrap(grid.cell(atColumnIndex: 1, rowIndex: 0).contentView as? NSPopUpButton)
        for width: CGFloat in [460, 670, 900, 460] {
            accessory.setFrameSize(NSSize(width: width, height: accessory.frame.height))
            for mode in [ScreenshotExportSizeMode.selectedSize, .imageScale, .selectedSize] {
                accessory.selectedMode = mode
                accessory.layoutSubtreeIfNeeded()
                let popupRect = try XCTUnwrap(popup.superview).convert(
                    popup.alignmentRect(forFrame: popup.frame), to: accessory)
                XCTAssertEqual(popupRect.maxX, accessory.bounds.maxX - 20, accuracy: 1,
                               "Parameter controls must follow the right edge at width \(width)")
                XCTAssertEqual(popupRect.width, 240, accuracy: 1)
            }
        }
    }

}
