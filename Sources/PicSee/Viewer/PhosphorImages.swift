import AppKit

@MainActor
enum PhosphorImages {
    static let trash: NSImage = {
        guard let url = PicSeeResourceBundle.url(
            forResource: "trash", withExtension: "svg",
            subdirectory: "Phosphor.xcassets/trash.imageset"
        ), let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing Phosphor trash icon")
        }
        return image
    }()

    static let check: NSImage = {
        guard let url = PicSeeResourceBundle.url(
            forResource: "check-bold", withExtension: "svg",
            subdirectory: "Phosphor.xcassets/check-bold.imageset"
        ), let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing Phosphor check-bold icon")
        }
        return image
    }()
}
