import Foundation

struct ImageOpenRouting {
    let currentProcessURL: URL?
    let spawnedProcessURLs: [URL]

    static func route(urls: [URL], hasOpenViewer: Bool) -> ImageOpenRouting {
        guard !urls.isEmpty else {
            return ImageOpenRouting(currentProcessURL: nil, spawnedProcessURLs: [])
        }

        if hasOpenViewer {
            return ImageOpenRouting(currentProcessURL: nil, spawnedProcessURLs: urls)
        }

        return ImageOpenRouting(
            currentProcessURL: urls.first,
            spawnedProcessURLs: Array(urls.dropFirst())
        )
    }
}
