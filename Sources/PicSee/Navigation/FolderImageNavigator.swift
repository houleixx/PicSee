import Foundation

struct FolderImageNavigator {
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "tif", "tiff", "bmp", "webp"
    ]

    let images: [URL]
    let currentIndex: Int

    init(currentImageURL: URL, fileManager: FileManager = .default) throws {
        let standardizedCurrent = currentImageURL.standardizedFileURL
        let folderURL = standardizedCurrent.deletingLastPathComponent()
        let folderContents: [URL]

        do {
            folderContents = try fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            self.images = [standardizedCurrent]
            self.currentIndex = 0
            return
        }

        let sortedImages = folderContents
            .map { $0.standardizedFileURL }
            .filter(Self.isSupportedImage)
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }

        if let index = sortedImages.firstIndex(of: standardizedCurrent) {
            self.images = sortedImages
            self.currentIndex = index
        } else {
            self.images = [standardizedCurrent]
            self.currentIndex = 0
        }
    }

    static func isSupportedImage(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return !pathExtension.isEmpty && supportedExtensions.contains(pathExtension)
    }

    func previousURL() -> URL? {
        guard currentIndex > 0 else { return nil }
        return images[currentIndex - 1]
    }

    func nextURL() -> URL? {
        guard currentIndex + 1 < images.count else { return nil }
        return images[currentIndex + 1]
    }
}
