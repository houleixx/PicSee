import Foundation

final class FolderImageNavigator {
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "tif", "tiff", "bmp", "webp",
        "raw", "dng", "cr2", "cr3", "nef", "nrw", "arw", "srf", "sr2",
        "raf", "orf", "rw2", "rwl", "pef", "3fr", "fff", "iiq", "mos",
        "mrw", "x3f", "erf", "kdc", "dcr"
    ]

    private(set) var images: [URL]
    private(set) var currentIndex: Int
    private let fileManager: FileManager

    init(
        currentImageURL: URL,
        fileManager: FileManager = .default,
        preferredOrder: [URL]? = nil
    ) throws {
        self.fileManager = fileManager
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
            .filter { Self.isSupportedImage($0) && Self.isRegularFile($0) }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }

        let preferredImages = Self.normalizedPreferredOrder(preferredOrder, in: folderURL)
        if preferredImages.contains(standardizedCurrent) {
            self.images = preferredImages
            self.currentIndex = preferredImages.firstIndex(of: standardizedCurrent) ?? 0
            return
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
        while currentIndex > 0 {
            let candidateIndex = currentIndex - 1
            let candidate = images[candidateIndex]
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            images.remove(at: candidateIndex)
            currentIndex -= 1
        }
        return nil
    }

    func nextURL() -> URL? {
        while currentIndex + 1 < images.count {
            let candidateIndex = currentIndex + 1
            let candidate = images[candidateIndex]
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            images.remove(at: candidateIndex)
        }
        return nil
    }

    func move(to url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard images.contains(standardizedURL) else { return }

        let oldCurrentURL = images[currentIndex]
        if oldCurrentURL != standardizedURL,
           !fileManager.fileExists(atPath: oldCurrentURL.path) {
            removeFromSnapshot(oldCurrentURL)
        }
        if let index = images.firstIndex(of: standardizedURL) {
            currentIndex = index
        }
    }

    func removeFromSnapshot(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard let index = images.firstIndex(of: standardizedURL) else { return }

        images.remove(at: index)
        if images.isEmpty {
            currentIndex = 0
        } else if index < currentIndex {
            currentIndex -= 1
        } else if currentIndex >= images.count {
            currentIndex = images.count - 1
        }
    }

    private static func normalizedPreferredOrder(_ order: [URL]?, in folderURL: URL) -> [URL] {
        guard let order else { return [] }

        let standardizedFolder = folderURL.standardizedFileURL
        var seen: Set<URL> = []
        return order.compactMap { url in
            let standardizedURL = url.standardizedFileURL
            guard
                standardizedURL.deletingLastPathComponent() == standardizedFolder,
                isSupportedImage(standardizedURL),
                isRegularFile(standardizedURL),
                seen.insert(standardizedURL).inserted
            else {
                return nil
            }
            return standardizedURL
        }
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}
