import AppKit
import XCTest
@testable import PicSee
final class ScreenshotCaretLayoutTests: XCTestCase {
    @MainActor func testFocusedEditorPaddingAndClickAlignment() throws {
        _ = NSApplication.shared
        let image = NSImage(size: NSSize(width: 600, height: 400), flipped: false) { rect in
            NSColor.gray.setFill(); rect.fill(); return true
        }
        let document = try ScreenshotDocument(image: image, rotationDegrees: 0)
        document.selectAll(); document.tool = .text
        let canvas = ScreenshotCanvasNSView(document: document)
        let rect = CGRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = canvas
        canvas.frame = rect; canvas.displayImageRect = rect
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 300, y: 200), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        canvas.mouseDown(with: event)
        let field = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertEqual(field.frame.minX, 300, accuracy: 0.01)
        XCTAssertEqual(field.frame.midY, 200, accuracy: 0.01)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        for typed in [false, true] {
            if typed { editor.insertText("中文输入测试", replacementRange: NSRange(location: 0, length: 0)) }
            canvas.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let editorRect = field.convert(editor.bounds, from: editor)
            XCTAssertGreaterThanOrEqual(editorRect.minX, 10)
            XCTAssertGreaterThanOrEqual(field.bounds.maxY - editorRect.maxY, 8)

        }
    }
}
