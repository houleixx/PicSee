import AppKit

@MainActor
enum PhosphorImages {
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
