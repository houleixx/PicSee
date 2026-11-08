import AppKit
import Combine
import XCTest
@testable import PicSee

@MainActor
final class ImageDefaultDisplayTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var folder: URL!

    override func setUp() async throws {
        suite = "PicSee.DefaultDisplayTests.\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: folder)
    }

    func testDefaultsAndInvalidValuesPreserveFitWindow() {
        XCTAssertEqual(ImageDisplayPreference.mode(in: defaults), .fitWindow)
        defaults.set("unknown", forKey: ImageDisplayPreference.defaultsKey)
        XCTAssertEqual(ViewerPreferences(defaults: defaults).snapshot.imageDisplayMode, .fitWindow)
    }

    func testWidthAndActualSizeRespectRotationAndBackingPixels() {
        for backing: CGFloat in [1, 2] {
            for rotation in [0, 90, 180, 270] {
                let width = geometry(.fitWidth, backing: backing, rotation: rotation)
                XCTAssertEqual(width.displaySize.width, 400, accuracy: 0.001)
                let actual = geometry(.actualSize, backing: backing, rotation: rotation)
                XCTAssertEqual(actual.pixelDisplayScale, 1, accuracy: 0.001)
                XCTAssertEqual(actual.displaySize.width * backing, actual.rotatedImageSize.width, accuracy: 0.001)
                let fit = geometry(.fitWindow, backing: backing, rotation: rotation)
                XCTAssertLessThanOrEqual(fit.displaySize.width, 400)
                XCTAssertLessThanOrEqual(fit.displaySize.height, 300)
            }
        }
    }

    func testCursorZoomPreservesPixelInAllDisplayModes() {
        let anchor = CGPoint(x: 240, y: 170)
        for mode in ImageDisplayMode.allCases {
            let before = geometry(mode, zoom: 2)
            let adjustment = ImageZoomAdjustment.adjustment(from: before, multiplier: 1.25, anchorPoint: anchor)
            let after = geometry(mode, zoom: adjustment.zoomScale, pan: adjustment.panOffset)
            XCTAssertEqual((anchor.x - before.imageRect.minX) / before.displayScale,
                           (anchor.x - after.imageRect.minX) / after.displayScale, accuracy: 0.001)
            XCTAssertEqual((anchor.y - before.imageRect.minY) / before.displayScale,
                           (anchor.y - after.imageRect.minY) / after.displayScale, accuracy: 0.001)
        }
    }

    func testEachImageUsesDefaultAfterTemporaryFitOrZoom() throws {
        let first = try writePNG("01.png")
        let second = try writePNG("02.png")
        for mode in ImageDisplayMode.allCases {
            ImageDisplayPreference.setMode(mode, in: defaults)
            let model = ImageViewerViewModel(loadingMode: .immediate, imageURL: first, defaults: defaults)
            XCTAssertEqual(model.displayMode, mode)
            model.fitToWindow()
            XCTAssertEqual(model.displayMode, .fitWindow)
            XCTAssertEqual(ImageDisplayPreference.mode(in: defaults), mode)
            model.zoomScale = 4
            model.panOffset = CGSize(width: 30, height: 40)
            model.navigate(to: second)
            XCTAssertEqual(model.displayMode, mode)
            XCTAssertEqual(model.zoomScale, 1)
            XCTAssertEqual(model.panOffset, .zero)
        }
    }

    func testSettingsSyncToExistingModelAndPersistIndependentlyOfWindowOptions() async throws {
        let model = ImageViewerViewModel(loadingMode: .immediate, imageURL: try writePNG("01.png"), defaults: defaults)
        let preferences = ViewerPreferences(defaults: defaults)
        preferences.set(\.fixedWindowEnabled, to: true)
        preferences.set(\.automaticWindowSizeEnabled, to: true)
        model.zoomScale = 4
        model.panOffset = CGSize(width: 20, height: 30)
        let received = expectation(description: "Existing model receives display mode")
        let observation = model.$displayMode.dropFirst().filter { $0 == .actualSize }.first()
            .sink { _ in received.fulfill() }
        defer { observation.cancel() }
        preferences.setImageDisplayMode(.actualSize)
        await fulfillment(of: [received], timeout: 2)
        XCTAssertEqual(model.zoomScale, 1)
        XCTAssertEqual(model.panOffset, .zero)
        let reopened = ViewerPreferences(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(reopened.snapshot.imageDisplayMode, .actualSize)
        XCTAssertTrue(reopened.snapshot.fixedWindowEnabled)
        XCTAssertTrue(reopened.snapshot.automaticWindowSizeEnabled)
    }

    private func geometry(_ mode: ImageDisplayMode, backing: CGFloat = 2, rotation: Int = 0,
                          zoom: CGFloat = 1, pan: CGSize = .zero) -> ImageDisplayGeometry {
        ImageDisplayGeometry(imageSize: CGSize(width: 1000, height: 6000),
            viewportSize: CGSize(width: 400, height: 300), zoomScale: zoom, panOffset: pan,
            rotationDegrees: rotation, backingScaleFactor: backing,
            maximumAutomaticPixelScale: .infinity, displayMode: mode)
    }

    private func writePNG(_ name: String) throws -> URL {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 600,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let url = folder.appendingPathComponent(name)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        return url
    }
}
