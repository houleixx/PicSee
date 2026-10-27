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
            XCTAssertEqual(operation.printInfo.horizontalPagination, .fit)
            XCTAssertEqual(operation.printInfo.verticalPagination, .fit)
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
}
