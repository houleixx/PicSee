import AppKit
import Foundation
import SwiftUI

@MainActor
final class ImageViewerViewModel: ObservableObject {
    @Published private(set) var currentURL: URL
    @Published private(set) var image: NSImage?
    @Published private(set) var errorMessage: String?
    @Published var zoomScale: CGFloat = 1
    @Published var panOffset: CGSize = .zero
    @Published var displayScale: CGFloat = 1
    @Published var rotationDegrees: Int = 0

    private var navigator: FolderImageNavigator?

    init(imageURL: URL) {
        self.currentURL = imageURL.standardizedFileURL
        load(imageURL: imageURL)
    }

    var currentFilename: String {
        currentURL.lastPathComponent
    }

    var zoomPercentageText: String {
        "\(Int((displayScale * 100).rounded()))%"
    }

    var imagePixelSizeText: String? {
        guard let image, let pixelSize = image.pixelSize else { return nil }
        return "\(pixelSize.width) × \(pixelSize.height) px"
    }

    var fileSizeText: String? {
        guard let byteCount = currentURL.fileByteCount else { return nil }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    var imageMetadataText: String? {
        [currentFilename, fileSizeText, imagePixelSizeText]
            .compactMap { $0 }
            .joined(separator: " | ")
    }

    var titleBarText: String {
        [imageMetadataText, zoomPercentageText]
            .compactMap { $0 }
            .joined(separator: " | ")
    }

    var previousURL: URL? {
        navigator?.previousURL()
    }

    var nextURL: URL? {
        navigator?.nextURL()
    }

    func navigateToPrevious() {
        guard let previousURL else { return }
        navigate(to: previousURL)
    }

    func navigateToNext() {
        guard let nextURL else { return }
        navigate(to: nextURL)
    }

    func navigate(to url: URL) {
        load(imageURL: url)
    }

    func resetViewTransform() {
        zoomScale = 1
        panOffset = .zero
    }

    func fitToWindow() {
        resetViewTransform()
    }

    func showActualSize() {
        guard displayScale > 0 else {
            resetViewTransform()
            return
        }
        zoomScale = ImageZoomAdjustment.clampedZoom(currentZoom: zoomScale, multiplier: 1 / displayScale)
        panOffset = .zero
    }

    func zoomIn() {
        zoomScale = ImageZoomAdjustment.clampedZoom(currentZoom: zoomScale, multiplier: 1.25)
        panOffset = .zero
    }

    func zoomOut() {
        zoomScale = ImageZoomAdjustment.clampedZoom(currentZoom: zoomScale, multiplier: 0.8)
        panOffset = .zero
    }

    func rotateLeft() {
        rotationDegrees = (rotationDegrees + 90) % 360
        panOffset = .zero
    }

    func rotateRight() {
        rotationDegrees = (rotationDegrees + 270) % 360
        panOffset = .zero
    }

    private func load(imageURL: URL) {
        let standardizedURL = imageURL.standardizedFileURL
        currentURL = standardizedURL
        resetViewTransform()
        rotationDegrees = 0

        do {
            navigator = try FolderImageNavigator(currentImageURL: standardizedURL)
        } catch {
            navigator = nil
        }

        guard let loadedImage = NSImage(contentsOf: standardizedURL), loadedImage.isValid else {
            image = nil
            errorMessage = "PicSee could not open this image."
            return
        }

        image = loadedImage
        errorMessage = nil
    }
}

private extension URL {
    var fileByteCount: Int64? {
        guard let value = try? resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return Int64(value)
    }
}

private extension NSImage {
    var pixelSize: (width: Int, height: Int)? {
        let bitmapRepresentations = representations.compactMap { representation -> (width: Int, height: Int)? in
            guard representation.pixelsWide > 0, representation.pixelsHigh > 0 else { return nil }
            return (representation.pixelsWide, representation.pixelsHigh)
        }

        if let largestRepresentation = bitmapRepresentations.max(by: { lhs, rhs in
            lhs.width * lhs.height < rhs.width * rhs.height
        }) {
            return largestRepresentation
        }

        guard size.width > 0, size.height > 0 else { return nil }
        return (Int(size.width.rounded()), Int(size.height.rounded()))
    }
}
