import AppKit
import SwiftUI
import XCTest
@testable import PicSee

@MainActor
final class ScreenshotSizeFieldLayoutTests: XCTestCase {
    func testDimensionDigitsStayInPlaceWhenFocusChanges() throws {
        let (document, host, window) = try fixture()
        defer { window.orderOut(nil) }
        let dimensions = textFields(in: host).filter { ["516", "252"].contains($0.stringValue) }
        XCTAssertEqual(dimensions.count, 2)
        for field in dimensions {
            window.makeFirstResponder(nil)
            settle(host)
            let before = try inkBounds(field, in: host)
            field.selectText(nil)
            settle(host)
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            editor.insertionPointColor = .clear
            let focused = try inkBounds(field, in: host)
            XCTAssertEqual(focused.minX, before.minX, accuracy: 0.5, "Digits moved horizontally on focus")
            XCTAssertEqual(focused.minY, before.minY, accuracy: 0.5, "Digits moved vertically on focus")
            XCTAssertEqual(focused.width, before.width, accuracy: 0.5, "Digit advances changed on focus")
            XCTAssertEqual(focused.height, before.height, accuracy: 0.5, "Digit height changed on focus")
            window.makeFirstResponder(nil)
            settle(host)
            XCTAssertEqual(try inkBounds(field, in: host), before)
        }
        XCTAssertEqual(document.state.selection?.size, CGSize(width: 516, height: 252))
    }

    func testTypingCommitsWithoutResettingCaretAndGroupsUndo() throws {
        let (document, host, window) = try fixture()
        defer { window.orderOut(nil) }
        let width = try XCTUnwrap(textFields(in: host).first { $0.stringValue == "516" })
        width.selectText(nil)
        settle(host)
        let editor = try XCTUnwrap(width.currentEditor() as? NSTextView)
        editor.insertText("4", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        settle(host)
        for digit in ["2", "0"] {
            editor.insertText(digit, replacementRange: editor.selectedRange())
            settle(host)
        }
        XCTAssertEqual(width.stringValue, "420")
        XCTAssertEqual(editor.selectedRange().location, 3)
        XCTAssertEqual(document.state.selection?.width, 420)
        XCTAssertEqual(document.undoStates.count, 1)
        editor.insertNewline(nil)
        settle(host)
        XCTAssertEqual(width.stringValue, "420")
        window.makeFirstResponder(nil)
        settle(host)
        document.undo()
        settle(host)
        XCTAssertEqual(document.state.selection?.width, 516)
        XCTAssertEqual(width.stringValue, "516")
    }

    private func fixture() throws -> (ScreenshotDocument, NSView, NSWindow) {
        _ = NSApplication.shared
        let image = NSImage(size: NSSize(width: 1200, height: 800), flipped: false) { rect in
            NSColor.gray.setFill(); rect.fill(); return true
        }
        let document = try ScreenshotDocument(image: image, rotationDegrees: 0)
        document.state.selection = CGRect(x: 40, y: 40, width: 516, height: 252)
        let host = NSHostingView(rootView: ScreenshotEditorView(
            document: document, imageRect: CGRect(origin: .zero, size: document.pixelSize), onClose: {}
        ).environment(\.colorScheme, .dark).environment(\.displayScale, 1))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFront(nil)
        settle(host)
        return (document, host, window)
    }

    private func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { textFields(in: $0) }
    }

    /// Compare the rendered digits, excluding the gray well, blue focus ring and caret.
    private func inkBounds(_ field: NSTextField, in host: NSView) throws -> CGRect {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let rect = field.convert(field.bounds, to: host).insetBy(dx: 2, dy: 0)
        let sx = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let sy = CGFloat(bitmap.pixelsHigh) / host.bounds.height
        var points: [CGPoint] = []
        for y in Int(ceil(rect.minY * sy))..<Int(floor(rect.maxY * sy)) {
            for x in Int(ceil(rect.minX * sx))..<Int(floor(rect.maxX * sx)) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                // Include the anti-aliased edges: a high threshold can mistake
                // AppKit's focus-dependent smoothing for a change in glyph size.
                if color.alphaComponent > 0.5 && min(color.redComponent, color.greenComponent, color.blueComponent) > 0.5 {
                    points.append(CGPoint(x: CGFloat(x) / sx, y: CGFloat(y) / sy))
                }
            }
        }
        let minX = try XCTUnwrap(points.map(\.x).min())
        let minY = try XCTUnwrap(points.map(\.y).min())
        return CGRect(x: minX, y: minY, width: points.map(\.x).max()! - minX,
                      height: points.map(\.y).max()! - minY)
    }
}
