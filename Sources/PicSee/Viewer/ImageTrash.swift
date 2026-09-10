import Foundation

protocol ImageTrashing {
    func trash(_ url: URL) throws -> URL?
    func restore(_ trashedURL: URL, to originalURL: URL) throws
}

struct ImageTrash: ImageTrashing {
    func trash(_ url: URL) throws -> URL? {
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        return destination as URL?
    }

    func restore(_ trashedURL: URL, to originalURL: URL) throws {
        // moveItem refuses to overwrite an existing file, including a new image
        // created at the original path after deletion.
        try FileManager.default.moveItem(at: trashedURL, to: originalURL)
    }
}
