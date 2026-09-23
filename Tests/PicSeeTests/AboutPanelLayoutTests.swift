import AppKit
import XCTest
@testable import PicSee

@MainActor
final class AboutPanelLayoutTests: XCTestCase {
    func testCreditsAndBothLinesAreCenteredInTheActualAboutWindow() throws {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        delegate.showAboutPanel(nil)
        let credits = AppMenu.aboutPanelCredits(from: Bundle.main.infoDictionary ?? [:])
        let textView = try XCTUnwrap(NSApp.windows.compactMap { window in
            window.contentView.flatMap { findCredits(in: $0, text: credits.string) }
        }.first)
        let window = try XCTUnwrap(textView.window)
        defer { window.orderOut(nil) }
        window.contentView?.layoutSubtreeIfNeeded()

        let container = try XCTUnwrap(textView.textContainer)
        let layout = try XCTUnwrap(textView.layoutManager)
        layout.ensureLayout(for: container)
        let center = window.frame.width / 2
        let textFrame = textView.convert(textView.bounds, to: nil)
        XCTAssertEqual(textFrame.midX, center, accuracy: 0.5,
                       "Centered paragraphs must also sit in a window-centered text view")
        print("ABOUT_LAYOUT windowWidth=\(window.frame.width) windowCenter=\(center) textFrame=\(textFrame)")

        let storage = try XCTUnwrap(textView.textStorage)
        let text = storage.string as NSString
        for line in credits.string.components(separatedBy: "\n") {
            let range = text.range(of: line)
            XCTAssertNotEqual(range.location, NSNotFound)
            guard range.location != NSNotFound else { continue }
            let paragraph = try XCTUnwrap(storage.attribute(.paragraphStyle, at: range.location,
                                                           effectiveRange: nil) as? NSParagraphStyle)
            XCTAssertEqual(paragraph.alignment, .center)
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            let windowRect = textView.convert(rect, to: nil)
            print("ABOUT_LAYOUT line=\(line) frame=\(windowRect) center=\(windowRect.midX)")
            XCTAssertEqual(windowRect.midX, center, accuracy: 1,
                           "Each line's laid-out glyph bounds must be centered in the whole window")
        }
    }

    private func findCredits(in view: NSView, text: String) -> NSTextView? {
        if let textView = view as? NSTextView, textView.string == text { return textView }
        return view.subviews.lazy.compactMap { self.findCredits(in: $0, text: text) }.first
    }
}
