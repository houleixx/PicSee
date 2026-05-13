import XCTest
@testable import PicSee

final class ImageOpenRoutingTests: XCTestCase {
    func testEmptyViewerUsesCurrentProcessForFirstImageAndSpawnsRest() {
        let urls = [
            URL(fileURLWithPath: "/tmp/1.png"),
            URL(fileURLWithPath: "/tmp/2.png"),
            URL(fileURLWithPath: "/tmp/3.png")
        ]

        let routing = ImageOpenRouting.route(urls: urls, hasOpenViewer: false)

        XCTAssertEqual(routing.currentProcessURL, urls[0])
        XCTAssertEqual(routing.spawnedProcessURLs, [urls[1], urls[2]])
    }

    func testExistingViewerSpawnsEveryNewImage() {
        let urls = [
            URL(fileURLWithPath: "/tmp/1.png"),
            URL(fileURLWithPath: "/tmp/2.png")
        ]

        let routing = ImageOpenRouting.route(urls: urls, hasOpenViewer: true)

        XCTAssertNil(routing.currentProcessURL)
        XCTAssertEqual(routing.spawnedProcessURLs, urls)
    }
}
