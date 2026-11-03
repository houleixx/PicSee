import AppKit
import PDFKit
import XCTest
@testable import PicSee

@MainActor
final class ImagePrintingTests: XCTestCase {
    func testShortcutRequiresCommandPWithoutRepeat() {
        XCTAssertEqual(KeyboardNavigation.action(for: 35, modifiers: .command), .printImage)
        XCTAssertEqual(KeyboardNavigation.action(for: 35, modifiers: [.command, .capsLock]), .printImage)
        XCTAssertEqual(KeyboardNavigation.action(for: 35), .none)
        XCTAssertEqual(KeyboardNavigation.action(for: 35, modifiers: [.command, .shift]), .none)
        XCTAssertEqual(KeyboardNavigation.action(for: 35, modifiers: .command, isRepeat: true), .none)
    }

    func testPrintingUsesOriginalPixelsAndRotatedBounds() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 800,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = NSImage(size: NSSize(width: 120, height: 80))
        image.addRepresentation(bitmap)
        for rotation in [0, 90, 180, 270] {
            let operation = try ImagePrinter.makeOperation(image: image, rotationDegrees: rotation, title: "Photo")
            XCTAssertEqual(operation.view?.bounds.size,
                           rotation % 180 == 0 ? NSSize(width: 1200, height: 800) : NSSize(width: 800, height: 1200))
            XCTAssertEqual(operation.printInfo.horizontalPagination, .clip)
            XCTAssertEqual(operation.printInfo.verticalPagination, .clip)
            XCTAssertTrue(operation.printInfo.isHorizontallyCentered)
            XCTAssertTrue(operation.printInfo.isVerticallyCentered)
            XCTAssertEqual(operation.jobTitle, "Photo")

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
            defer { try? FileManager.default.removeItem(at: url) }
            operation.printInfo.jobDisposition = .save
            operation.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false
            XCTAssertTrue(operation.run())
            let pdf = try XCTUnwrap(PDFDocument(url: url))
            XCTAssertEqual(pdf.pageCount, 1)
        }
    }
    func testFitFillScaleAndAutoRotationGeometry() throws {
        var settings = ImagePrintSettings()
        let size = CGSize(width: 400, height: 200)
        let page = CGSize(width: 200, height: 300)
        var layout = ImagePrintLayout(imageSize: size, pageSize: page, settings: settings)
        XCTAssertTrue(try XCTUnwrap(layout.placements.first).rotates)
        XCTAssertEqual(layout.placements.first?.imageRect, CGRect(x: 25, y: 0, width: 150, height: 300))
        settings.automaticallyRotates = false
        layout = ImagePrintLayout(imageSize: size, pageSize: page, settings: settings)
        XCTAssertEqual(layout.placements.first?.imageRect, CGRect(x: 0, y: 100, width: 200, height: 100))
        settings.sizing = .fill
        layout = ImagePrintLayout(imageSize: size, pageSize: page, settings: settings)
        XCTAssertEqual(layout.placements.first?.imageRect, CGRect(x: -200, y: 0, width: 600, height: 300))
        settings.sizing = .scale
        settings.scalePercent = 50
        layout = ImagePrintLayout(imageSize: size, pageSize: page, settings: settings)
        XCTAssertEqual(layout.placements.first?.imageRect, CGRect(x: 0, y: 100, width: 200, height: 100))
    }

    func testCopiesHaveSeparateNonOverlappingClips() {
        for count in 1...16 {
            var settings = ImagePrintSettings()
            settings.copiesPerPage = count
            settings.sizing = .fill
            let placements = ImagePrintLayout(imageSize: CGSize(width: 600, height: 400),
                pageSize: CGSize(width: 500, height: 700), settings: settings).placements
            XCTAssertEqual(placements.count, count)
            for (index, placement) in placements.enumerated() {
                XCTAssertTrue(placement.imageRect.insetBy(dx: -0.001, dy: -0.001).contains(placement.clip))
                for other in placements.dropFirst(index + 1) {
                    let intersection = placement.clip.intersection(other.clip)
                    XCTAssertTrue(intersection.isNull || intersection.width < 0.001 || intersection.height < 0.001)
                }
            }
        }
    }

    func testAccessoryUpdatesSettingsAndPreviewAndUsesImageDPI() throws {
        let image = NSImage(size: CGSize(width: 288, height: 144))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 600,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        image.addRepresentation(bitmap)
        let operation = try ImagePrinter.makeOperation(image: image, rotationDegrees: 90, title: nil)
        let view = try XCTUnwrap(operation.view as? ImagePrintView)
        XCTAssertEqual(view.physicalSize, CGSize(width: 144, height: 288))
        let accessory = try XCTUnwrap(operation.printPanel.accessoryControllers.first as? ImagePrintAccessoryController)
        _ = accessory.view
        accessory.representedObject = operation.printInfo
        var settings = ImagePrintSettings()
        settings.sizing = .scale
        settings.scalePercent = 75
        settings.copiesPerPage = 4
        settings.automaticallyRotates = false
        accessory.updateSettings(settings)
        XCTAssertEqual(ImagePrintSettings(printInfo: operation.printInfo), settings)
        XCTAssertEqual(accessory.previewRevision, 1)
        XCTAssertTrue(accessory.keyPathsForValuesAffectingPreview().contains("previewRevision"))
        XCTAssertFalse(operation.printPanel.options.contains(.showsScaling))
    }

    func testRadioGroupsRemainIndependentlySelected() throws {
        _ = NSApplication.shared
        let accessory = ImagePrintAccessoryController(printInfo: NSPrintInfo(), imageSize: CGSize(width: 600, height: 300))
        func allButtons(in view: NSView) -> [NSButton] {
            view.subviews.flatMap { subview in
                (subview as? NSButton).map { [$0] } ?? allButtons(in: subview)
            }
        }
        let buttons = allButtons(in: accessory.view)
        let fit = try XCTUnwrap(buttons.first { $0.tag == 2 })
        let entire = try XCTUnwrap(buttons.first { $0.tag == 3 })
        let fill = try XCTUnwrap(buttons.first { $0.tag == 4 })
        XCTAssertEqual(fit.state, .on)
        XCTAssertEqual(entire.state, .on)
        fill.performClick(nil)
        XCTAssertEqual(fit.state, .on)
        XCTAssertEqual(fill.state, .on)
        XCTAssertEqual(entire.state, .off)
        XCTAssertEqual(accessory.settings.sizing, .fill)
    }

    func testPDFContainsExpectedPrintedAreaForEachSizingMode() throws {
        let image = NSImage(size: CGSize(width: 80, height: 40), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        for (sizing, copies, expectedArea) in [(ImagePrintSettings.Sizing.scale, 1, 3200),
                                              (.fit, 1, 145800), (.fill, 1, 388800), (.scale, 4, 12800)] {
            let operation = try ImagePrinter.makeOperation(image: image, rotationDegrees: 0, title: "Geometry")
            let info = operation.printInfo
            info.paperSize = CGSize(width: 612, height: 792)
            info.orientation = .portrait
            info.leftMargin = 36
            info.rightMargin = 36
            info.topMargin = 36
            info.bottomMargin = 36
            var settings = ImagePrintSettings()
            settings.automaticallyRotates = false
            settings.sizing = sizing
            settings.copiesPerPage = copies
            settings.store(in: info)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
            defer { try? FileManager.default.removeItem(at: url) }
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false
            XCTAssertTrue(operation.run())
            let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
            XCTAssertEqual(pdf.numberOfPages, 1)
            let page = try XCTUnwrap(pdf.page(at: 1))
            XCTAssertEqual(page.getBoxRect(.mediaBox).size, CGSize(width: 612, height: 792))
            let context = try XCTUnwrap(CGContext(data: nil, width: 612, height: 792, bitsPerComponent: 8,
                bytesPerRow: 612 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 612, height: 792))
            context.drawPDFPage(page)
            let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            let redPixels = (0..<(612 * 792)).reduce(0) { count, index in
                count + (data[index * 4] > 240 && data[index * 4 + 1] < 20 && data[index * 4 + 2] < 20 ? 1 : 0)
            }
            XCTAssertEqual(Double(redPixels), Double(expectedArea), accuracy: 100,
                           "Unexpected printed area for \(sizing), copies \(copies)")
        }
    }

    func testScaleTypingUpdatesPreviewBeforeEditingEndsAndPreservesInput() throws {
        _ = NSApplication.shared
        let info = NSPrintInfo()
        let accessory = ImagePrintAccessoryController(printInfo: info, imageSize: CGSize(width: 600, height: 300))
        var settings = ImagePrintSettings()
        settings.sizing = .scale
        accessory.updateSettings(settings)
        let field = try XCTUnwrap(accessory.view.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable })
        let revision = accessory.previewRevision
        for text in ["4", "40", "40.5%"] {
            field.stringValue = text
            field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
            XCTAssertEqual(accessory.settings.scalePercent, Double(text.replacingOccurrences(of: "%", with: "")))
            XCTAssertEqual(field.stringValue, text, "Typing must not rewrite text or move the caret")
        }
        XCTAssertGreaterThan(accessory.previewRevision, revision)
        field.stringValue = ""
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertEqual(field.stringValue, "")
        XCTAssertEqual(accessory.settings.scalePercent, 40.5)
    }

    func testFillSelectionSurvivesSwitchToManualScaleAndBack() throws {
        _ = NSApplication.shared
        let accessory = ImagePrintAccessoryController(printInfo: NSPrintInfo(), imageSize: CGSize(width: 600, height: 300))
        func buttons(_ view: NSView) -> [NSButton] {
            view.subviews.flatMap { ($0 as? NSButton).map { [$0] } ?? buttons($0) }
        }
        let controls = buttons(accessory.view)
        let fill = try XCTUnwrap(controls.first { $0.tag == 4 })
        let scale = try XCTUnwrap(controls.first { $0.tag == 1 })
        let fit = try XCTUnwrap(controls.first { $0.tag == 2 })
        fill.performClick(nil)
        scale.performClick(nil)
        XCTAssertEqual(fill.state, .on)
        XCTAssertFalse(fill.isEnabled)
        fit.performClick(nil)
        XCTAssertEqual(accessory.settings.sizing, .fill)
    }

    func testDefaultPrintingCentersImageOnPaperWithSymmetricInset() throws {
        let image = NSImage(size: CGSize(width: 200, height: 600), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let operation = try ImagePrinter.makeOperation(image: image, rotationDegrees: 0, title: nil)
        let info = operation.printInfo
        XCTAssertEqual(info.topMargin, 12, accuracy: 0.01)
        XCTAssertEqual(info.bottomMargin, 12, accuracy: 0.01)
        XCTAssertEqual(info.leftMargin, 12, accuracy: 0.01)
        XCTAssertEqual(info.rightMargin, 12, accuracy: 0.01)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        XCTAssertTrue(operation.run())
        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let page = try XCTUnwrap(pdf.page(at: 1))
        let paper = page.getBoxRect(.mediaBox)
        let width = Int(paper.width.rounded())
        let height = Int(paper.height.rounded())
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(paper)
        context.drawPDFPage(page)
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let paintedRows = (0..<height).filter { row in
            let index = (row * width + width / 2) * 4
            return data[index] > 240 && data[index + 1] < 20 && data[index + 2] < 20
        }
        let bottom = try XCTUnwrap(paintedRows.first)
        let top = height - 1 - (try XCTUnwrap(paintedRows.last))
        XCTAssertEqual(Double(bottom), Double(top), accuracy: 1, "Image must be centered on the paper, not the driver printable area")
        XCTAssertEqual(Double(bottom), 12, accuracy: 1)
    }

}
