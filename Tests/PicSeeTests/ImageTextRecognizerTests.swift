import AppKit
import XCTest
@testable import PicSee

@MainActor
final class ImageTextRecognizerTests: XCTestCase {
    func testCancelDuringDebounceDoesNotStartRecognition() async throws {
        let recognizer = ImageTextRecognizer()
        recognizer.schedule(image: try image(), url: nil, backend: .vision,
            liveText: { _ in XCTFail("Cancelled request delivered Live Text") },
            vision: { _ in XCTFail("Cancelled request delivered Vision text") })
        recognizer.cancel()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(recognizer.startedCount, 0)
    }

    func testRapidImageReplacementsStartOnlyTheSettledRequest() async throws {
        let recognizer = ImageTextRecognizer()
        let ready = expectation(description: "Latest recognition finished")
        for _ in 0..<5 {
            recognizer.schedule(image: try image(), url: nil, backend: .vision,
                liveText: { _ in XCTFail("Wrong backend") }, vision: { _ in ready.fulfill() })
        }
        await fulfillment(of: [ready], timeout: 10)
        XCTAssertEqual(recognizer.startedCount, 1)
    }

    private func image() throws -> NSImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = NSImage(size: CGSize(width: 32, height: 32))
        image.addRepresentation(bitmap)
        return image
    }
}
