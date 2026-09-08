import AppKit
import XCTest
@testable import PicSee

final class ScreenshotExportSizeTests: XCTestCase {
    func testSelectedSizeTracksViewerZoom() {
        let source = CGSize(width: 600, height: 400)
        for scale: CGFloat in [0.25, 0.5, 1, 2] {
            XCTAssertEqual(ScreenshotExportSizeMode.selectedSize.pixelSize(sourceSize: source, displayScale: scale),
                           CGSize(width: 600 * scale, height: 400 * scale))
        }
    }

    func testOriginalSizeIsIndependentOfViewerZoom() {
        let source = CGSize(width: 600, height: 400)
        for scale: CGFloat in [0.25, 0.5, 1, 2] {
            XCTAssertEqual(ScreenshotExportSizeMode.imageScale.pixelSize(sourceSize: source, displayScale: scale), source)
        }
        XCTAssertEqual(ScreenshotExportSizeMode.imageScale.title, "按原图尺寸保存")
    }

    func testOutputRoundsToWholePixelsAndInvalidScalesUseOriginalSize() {
        XCTAssertEqual(ScreenshotExportSizeMode.selectedSize.pixelSize(
            sourceSize: CGSize(width: 7, height: 3), displayScale: 0.4), CGSize(width: 3, height: 1))
        for mode in ScreenshotExportSizeMode.allCases {
            for scale: CGFloat in [0, -1, .nan, .infinity] {
                XCTAssertEqual(mode.pixelSize(sourceSize: CGSize(width: 7, height: 3), displayScale: scale),
                               CGSize(width: 7, height: 3))
            }
        }
    }

    func testScreenPixelsTrackWindowZoomAndBackingScale() {
        let source = CGSize(width: 1200, height: 800)
        for screenScale: CGFloat in [1, 2] {
            for zoom: CGFloat in [0.25, 0.5, 1, 2] {
                let scale = ScreenshotExportSizeMode.displayPixelScale(imageDisplayScale: zoom, screenScale: screenScale)
                XCTAssertEqual(ScreenshotExportSizeMode.selectedSize.pixelSize(sourceSize: source, displayScale: scale),
                    CGSize(width: 1200 * zoom * screenScale, height: 800 * zoom * screenScale))
                XCTAssertEqual(ScreenshotExportSizeMode.imageScale.pixelSize(sourceSize: source, displayScale: scale), source)
            }
        }
    }

    @MainActor
    func testSaveRadioButtonsShowBothSizesAndSelectExactlyOneMode() throws {
        _ = NSApplication.shared
        let accessory = ScreenshotExportAccessoryView(sourceSize: CGSize(width: 600, height: 400), displayScale: 0.5, screenScale: 2)
        let grid = try XCTUnwrap(accessory.subviews.compactMap { $0 as? NSGridView }.first)
        let selected = try XCTUnwrap(grid.cell(atColumnIndex: 1, rowIndex: 0).contentView as? NSButton)
        let original = try XCTUnwrap(grid.cell(atColumnIndex: 1, rowIndex: 1).contentView as? NSButton)
        XCTAssertEqual(selected.title, "按选择尺寸保存 · 300 × 200 px")
        XCTAssertEqual(original.title, "按原图尺寸保存 · 600 × 400 px（当前显示比例 25%）")
        XCTAssertEqual(selected.state, .on)
        XCTAssertEqual(original.state, .off)
        XCTAssertEqual(accessory.exportOptions.pixelSize, CGSize(width: 300, height: 200))
        original.performClick(nil)
        XCTAssertEqual(accessory.selectedMode, .imageScale)
        XCTAssertEqual(selected.state, .off)
        XCTAssertEqual(original.state, .on)
        XCTAssertEqual(accessory.exportOptions.pixelSize, CGSize(width: 600, height: 400))
        original.performClick(nil)
        XCTAssertEqual(original.state, .on)
        selected.performClick(nil)
        XCTAssertEqual(accessory.selectedMode, .selectedSize)
        XCTAssertEqual(selected.state, .on)
        XCTAssertEqual(original.state, .off)
        XCTAssertEqual(accessory.exportOptions.pixelSize, CGSize(width: 300, height: 200))
        XCTAssertEqual(accessory.frame.height, 80)
        XCTAssertEqual(grid.numberOfRows, 2)
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
        for screenScale: CGFloat in [1, 2] {
            for mode in ScreenshotExportSizeMode.allCases {
                let scale = ScreenshotExportSizeMode.displayPixelScale(imageDisplayScale: 0.25, screenScale: screenScale)
                let accessory = ScreenshotExportAccessoryView(sourceSize: document.pixelSize, displayScale: scale)
                accessory.selectedMode = mode
                let url = directory.appendingPathComponent("\(mode.rawValue).png")
                let rendered = try document.exportImage(mode: mode, displayPixelScale: scale)
                XCTAssertEqual(ImageExporter.pixelSize(of: rendered), mode == .selectedSize
                    ? CGSize(width: 20 * screenScale, height: 10 * screenScale) : document.pixelSize)
                try ImageExporter.export(rendered, to: url, options: accessory.exportOptions)
                let saved = try XCTUnwrap(NSImage(contentsOf: url))
                XCTAssertEqual(ImageExporter.pixelSize(of: saved),
                               mode == .selectedSize ? CGSize(width: 20 * screenScale, height: 10 * screenScale) : CGSize(width: 80, height: 40))
                if mode == .selectedSize {
                    let pasteboard = NSPasteboard.withUniqueName()
                    defer { pasteboard.releaseGlobally() }
                    let copied = try document.exportImage(mode: .selectedSize, displayPixelScale: scale)
                    XCTAssertTrue(pasteboard.writeObjects([copied]))
                    let pasted = try XCTUnwrap(NSImage(pasteboard: pasteboard))
                    XCTAssertEqual(ImageExporter.pixelSize(of: pasted), ImageExporter.pixelSize(of: saved))
                    let pastedPixels = NSBitmapImageRep(cgImage: try XCTUnwrap(
                        pasted.cgImage(forProposedRect: nil, context: nil, hints: nil)))
                    let pastedCenter = try XCTUnwrap(pastedPixels.colorAt(
                        x: pastedPixels.pixelsWide / 2, y: pastedPixels.pixelsHigh / 2))
                    XCTAssertGreaterThan(pastedCenter.redComponent, 0.9)
                    XCTAssertGreaterThan(pastedCenter.alphaComponent, 0.9)
                }
                let pixels = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
                let center = try XCTUnwrap(pixels.colorAt(x: pixels.pixelsWide / 2, y: pixels.pixelsHigh / 2))
                XCTAssertGreaterThan(center.redComponent, 0.9)
                XCTAssertGreaterThan(center.alphaComponent, 0.9)
            }
        }
    }
    @MainActor
    func testSaveRadioButtonsStayAlignedAcrossPanelWidths() throws {
        let accessory = ScreenshotExportAccessoryView(sourceSize: CGSize(width: 600, height: 400), displayScale: 0.5)
        let grid = try XCTUnwrap(accessory.subviews.compactMap { $0 as? NSGridView }.first)
        let first = try XCTUnwrap(grid.cell(atColumnIndex: 1, rowIndex: 0).contentView as? NSButton)
        let second = try XCTUnwrap(grid.cell(atColumnIndex: 1, rowIndex: 1).contentView as? NSButton)
        for width: CGFloat in [accessory.frame.width, 670, 900, accessory.frame.width] {
            accessory.setFrameSize(NSSize(width: width, height: 80))
            accessory.layoutSubtreeIfNeeded()
            XCTAssertEqual(grid.frame.maxX, accessory.bounds.maxX - 20, accuracy: 1)
            XCTAssertEqual(first.frame.minX, second.frame.minX, accuracy: 1)
            XCTAssertGreaterThanOrEqual(grid.frame.minX, 16)
            for button in [first, second] {
                XCTAssertGreaterThanOrEqual(button.frame.width, button.intrinsicContentSize.width - 1)
            }
        }
    }
}
