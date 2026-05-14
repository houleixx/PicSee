import AppKit
import VisionKit
import XCTest
@testable import PicSee

@MainActor
final class ImageCanvasOCRTests: XCTestCase {
    func testLiveTextAnalysisRecognizesFixtureLines() throws {
        try XCTSkipUnless(ImageAnalyzer.isSupported, "ImageAnalyzer not supported on this host")

        let view = CanvasNSView(frame: CGRect(x: 0, y: 0, width: 1152, height: 768), backend: .liveText)
        view.image = loadFixtureImage()
        view.imageURL = fixtureURL
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.debugWaitForAnalysis(timeout: 8), "Live Text analysis did not complete")
        let transcript = view.debugLiveTextAnalysis?.transcript ?? ""
        XCTAssertTrue(transcript.contains("第一行测试文字"), "Missing line 1 in transcript: \(transcript)")
        XCTAssertTrue(transcript.contains("第二行复制验证"), "Missing line 2 in transcript: \(transcript)")
        XCTAssertTrue(transcript.contains("第三行放大后选择"), "Missing line 3 in transcript: \(transcript)")

        view.zoomScale = 2
        view.panOffset = CGSize(width: 60, height: -30)
        view.layoutSubtreeIfNeeded()

        XCTAssertNotNil(view.debugLiveTextAnalysis, "Analysis must persist across zoom and pan changes")
    }

    func testVisionFallbackRecognizesAndCopies() {
        let view = CanvasNSView(frame: CGRect(x: 0, y: 0, width: 1152, height: 768), backend: .vision)
        view.image = loadFixtureImage()
        view.imageURL = fixtureURL
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.debugWaitForVisionRecognition(timeout: 8), "Vision OCR did not produce results")

        let texts = view.debugRecognizedTexts()
        XCTAssertGreaterThanOrEqual(texts.count, 3, "Expected at least 3 lines, got: \(texts)")
        guard texts.count >= 3 else { return }
        XCTAssertEqual(texts.prefix(3).map { $0 }, ["第一行测试文字", "第二行复制验证", "第三行放大后选择"])

        let rects = view.debugLineRects()
        guard rects.count >= 3 else {
            XCTFail("Expected three OCR rects, got: \(rects)")
            return
        }
        XCTAssertGreaterThan(rects[0].midY, rects[1].midY)
        XCTAssertGreaterThan(rects[1].midY, rects[2].midY)

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

    func testPreferredBackendIsLiveTextOnSupportedHardware() {
        let expected: TextRecognitionBackend = ImageAnalyzer.isSupported ? .liveText : .vision
        let view = CanvasNSView(frame: .zero)
        XCTAssertEqual(view.debugBackend, expected)
    }

    func testPreferredBackendFallsBackToVisionWhenLiveTextSelectionIsUnavailable() {
        XCTAssertEqual(
            TextRecognitionBackend.preferredBackend(
                liveTextSupported: true,
                supportsLiveTextSelection: false
            ),
            .vision
        )
    }

    func testPreferredBackendUsesLiveTextWhenLiveTextSelectionIsAvailable() {
        XCTAssertEqual(
            TextRecognitionBackend.preferredBackend(
                liveTextSupported: true,
                supportsLiveTextSelection: true
            ),
            .liveText
        )
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
