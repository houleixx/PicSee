import AppKit
import XCTest
@testable import PicSee

@MainActor
final class ImageCanvasOCRTests: XCTestCase {
    func testOCRRecognizesFixtureAndMapsLinesTopToBottom() {
        let view = CanvasNSView(frame: CGRect(x: 0, y: 0, width: 1152, height: 768))
        view.image = loadFixtureImage()
        view.imageURL = fixtureURL
        view.layoutSubtreeIfNeeded()

        waitForOCR(on: view)

        let texts = view.debugRecognizedTexts()
        XCTAssertGreaterThanOrEqual(texts.count, 3, "Expected OCR to find the three fixture lines, got: \(texts)")
        guard texts.count >= 3 else { return }
        XCTAssertEqual(texts.prefix(3).map { $0 }, ["第一行测试文字", "第二行复制验证", "第三行放大后选择"])

        let rects = view.debugLineRects()
        guard rects.count >= 3 else {
            XCTFail("Expected three OCR rects, got: \(rects)")
            return
        }
        XCTAssertGreaterThan(rects[0].midY, rects[1].midY, "Top line should map above the second line: \(rects)")
        XCTAssertGreaterThan(rects[1].midY, rects[2].midY, "Second line should map above the third line: \(rects)")

        for (index, rect) in rects.prefix(3).enumerated() {
            XCTAssertEqual(view.debugHitTextIndex(at: CGPoint(x: rect.midX, y: rect.midY)), index)
        }

        let firstLineFragments = view.debugFragmentRects(forLine: 0)
        XCTAssertFalse(firstLineFragments.isEmpty)
        XCTAssertTrue(
            view.debugSelectText(
                from: CGPoint(x: firstLineFragments[1].midX, y: firstLineFragments[1].midY),
                to: CGPoint(x: firstLineFragments[4].midX, y: firstLineFragments[4].midY)
            )
        )
        XCTAssertEqual(view.debugSelectedText(), "一行测试")

        view.zoomScale = 2
        view.panOffset = CGSize(width: 60, height: -30)
        view.layoutSubtreeIfNeeded()

        let zoomedRects = view.debugLineRects()
        guard zoomedRects.count >= 3 else {
            XCTFail("Expected three OCR rects after zoom, got: \(zoomedRects)")
            return
        }
        for (index, rect) in zoomedRects.prefix(3).enumerated() {
            XCTAssertEqual(view.debugHitTextIndex(at: CGPoint(x: rect.midX, y: rect.midY)), index)
        }

        let zoomedThirdLineFragments = view.debugFragmentRects(forLine: 2)
        XCTAssertGreaterThanOrEqual(zoomedThirdLineFragments.count, 7)
        NSPasteboard.general.clearContents()
        XCTAssertTrue(
            view.debugSelectText(
                from: CGPoint(x: zoomedThirdLineFragments[3].midX, y: zoomedThirdLineFragments[3].midY),
                to: CGPoint(x: zoomedThirdLineFragments[7].midX, y: zoomedThirdLineFragments[7].midY)
            )
        )
        XCTAssertTrue(view.debugCopySelectedText())
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "放大后选择")
    }

    private func waitForOCR(on view: CanvasNSView, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while view.debugRecognizedLineCount == 0 && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertGreaterThan(view.debugRecognizedLineCount, 0, "OCR did not produce any text lines within \(timeout)s")
    }

    private func loadFixtureImage() -> NSImage {
        guard let image = NSImage(contentsOf: fixtureURL) else {
            XCTFail("Missing OCR fixture at \(fixtureURL.path)")
            return NSImage()
        }
        return image
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("build/ocr-test.png")
    }
}
