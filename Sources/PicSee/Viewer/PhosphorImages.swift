import AppKit

@MainActor
enum PhosphorImages {
    private static let contextMenuNames = [
        "link": "link",
        "square.and.arrow.down": "download-simple",
        "desktopcomputer": "desktop",
        "play.circle": "play-circle",
        "stop": "stop",
        "slider.horizontal.3": "sliders-horizontal",
        "macwindow": "app-window",
        "pin": "push-pin",
        "lock": "lock-simple",
        "circle.lefthalf.filled": "circle-half",
        "trash": "trash",
        "arrow.uturn.backward": "arrow-u-up-left",
        "gearshape": "gear",
        "arrow.triangle.2.circlepath": "arrows-clockwise",
        "info.circle": "info",
        "doc.on.doc": "copy",
        "square.and.arrow.up": "export"
    ]

    private static let contextMenuImages: [String: NSImage] =
        Dictionary(uniqueKeysWithValues: Set(contextMenuNames.values).map { name in
            guard let url = PicSeeResourceBundle.url(
                forResource: name, withExtension: "svg",
                subdirectory: "Phosphor.xcassets/\(name).imageset"
            ), let image = NSImage(contentsOf: url) else {
                preconditionFailure("Missing Phosphor menu icon: \(name)")
            }
            // Keep the library's common vector canvas and native proportions.
            image.size = NSSize(width: 16, height: 16)
            image.isTemplate = true
            return (name, image)
        })

    private static let settingsImages: [String: NSImage] =
        Dictionary(uniqueKeysWithValues: ["images-bold", "monitor-bold", "sun-fill", "info-fill"].map { name in
            guard let url = PicSeeResourceBundle.url(
                forResource: name, withExtension: "svg",
                subdirectory: "Phosphor.xcassets/\(name).imageset"
            ), let image = NSImage(contentsOf: url) else {
                preconditionFailure("Missing Phosphor settings icon: \(name)")
            }
            image.isTemplate = true
            return (name, image)
        })

    static func contextMenuImage(for systemSymbol: String) -> NSImage? {
        contextMenuNames[systemSymbol].flatMap { contextMenuImages[$0] }
    }

    static func image(named name: String) -> NSImage {
        guard let image = settingsImages[name] else {
            preconditionFailure("Missing Phosphor icon: \(name)")
        }
        return image
    }

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
