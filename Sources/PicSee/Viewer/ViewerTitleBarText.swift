import AppKit

@MainActor
enum ViewerTitleBarText {
    static func fitting(
        filename: String,
        fileSize: String?,
        pixelSize: String?,
        zoom: String,
        frameWidth: CGFloat,
        styleMask: NSWindow.StyleMask
    ) -> String {
        let separator = " | "
        let details = [fileSize, pixelSize, zoom].compactMap { $0 }.joined(separator: separator)
        let fullTitle = filename + separator + details

        func fits(_ title: String) -> Bool {
            NSWindow.minFrameWidth(withTitle: title, styleMask: styleMask) <= frameWidth
        }

        if frameWidth == .infinity || fits(fullTitle) { return fullTitle }
        if !fits(details) {
            let compactDetails = [pixelSize, zoom].compactMap { $0 }.joined(separator: separator)
            return fits(compactDetails) ? compactDetails : pixelSize ?? zoom
        }

        let ellipsis = "…"
        let suffix = separator + details
        guard fits(ellipsis + suffix) else { return details }

        let characters = Array(filename)
        let pathExtension = (filename as NSString).pathExtension
        let extensionLength = pathExtension.isEmpty ? 0 : 1 + pathExtension.count
        let keepsExtension = extensionLength > 0 && extensionLength < characters.count &&
            fits(String(characters.prefix(1)) + ellipsis + String(characters.suffix(extensionLength)) + suffix)
        let minimumEndLength = keepsExtension ? extensionLength : 0

        // Measure each complete candidate so the separator and all metadata fit in AppKit's title area.
        var lower = keepsExtension ? extensionLength + 1 : 0
        var upper = characters.count - 1
        var best = ellipsis + suffix
        while lower <= upper {
            let length = lower + (upper - lower) / 2
            let endLength = max(minimumEndLength, length / 2)
            let candidate = String(characters.prefix(length - endLength)) + ellipsis
                + String(characters.suffix(endLength)) + suffix
            if fits(candidate) {
                best = candidate
                lower = length + 1
            } else {
                upper = length - 1
            }
        }
        return best
    }
}
