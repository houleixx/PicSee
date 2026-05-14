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

    private func load(imageURL: URL) {
        let standardizedURL = imageURL.standardizedFileURL
        currentURL = standardizedURL
        resetViewTransform()

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
