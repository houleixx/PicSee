import AppKit
import Foundation

protocol FinderFolderOrderProviding: Sendable {
    var isOrderingAvailableImmediately: Bool { get }
    func orderedURLs(for folderURL: URL) async -> [URL]?
}

extension FinderFolderOrderProviding {
    var isOrderingAvailableImmediately: Bool { false }
}

struct FilenameFolderOrderProvider: FinderFolderOrderProviding {
    var isOrderingAvailableImmediately: Bool { true }

    func orderedURLs(for folderURL: URL) async -> [URL]? {
        nil
    }
}

private enum FinderOrderInstruction: Equatable {
    case exact([URL])
    case positions([PositionedURL])
}

struct FinderFolderOrderProvider: FinderFolderOrderProviding {
    typealias ScriptRunner = @Sendable (String) -> String?
    typealias DirectoryReader = @Sendable (URL) -> [URL]?

    private let scriptRunner: ScriptRunner
    private let directoryReader: DirectoryReader

    var isOrderingAvailableImmediately: Bool { true }

    init(
        _ scriptRunner: ScriptRunner? = nil,
        directoryReader: DirectoryReader? = nil
    ) {
        self.scriptRunner = scriptRunner ?? Self.execute
        self.directoryReader = directoryReader ?? Self.directoryImageURLs
    }

    func orderedURLs(for folderURL: URL) async -> [URL]? {
        guard
            let output = scriptRunner(Self.scriptSource(folderURL: folderURL)),
            let instruction = Self.parseInstruction(output)
        else {
            return nil
        }

        guard let directoryURLs = directoryReader(folderURL), !directoryURLs.isEmpty else {
            return nil
        }

        switch instruction {
        case let .exact(urls):
            return Self.validatedImageOrder(urls, directoryURLs: directoryURLs)
        case let .positions(positionedURLs):
            let urls = positionedURLs.sorted {
                if $0.y != $1.y { return $0.y < $1.y }
                if $0.x != $1.x { return $0.x < $1.x }
                return Self.nameComesBefore($0.url, $1.url)
            }.map(\.url)
            return Self.validatedImageOrder(urls, directoryURLs: directoryURLs)
        }
    }

    static func parseOutput(_ output: String) -> [URL]? {
        guard let instruction = parseInstruction(output) else { return nil }
        switch instruction {
        case let .exact(urls):
            return urls
        case let .positions(positionedURLs):
            return positionedURLs.sorted {
                if $0.y != $1.y { return $0.y < $1.y }
                if $0.x != $1.x { return $0.x < $1.x }
                return Self.nameComesBefore($0.url, $1.url)
            }.map(\.url)
        }
    }

    static func scriptSource(folderURL: URL) -> String {
        let folderLiteral = appleScriptLiteral(folderURL.standardizedFileURL.absoluteString)
        return """
        on reversedItems(itemsToReverse)
            set reversedResult to {}
            repeat with itemIndex from (count itemsToReverse) to 1 by -1
                set end of reversedResult to item itemIndex of itemsToReverse
            end repeat
            return reversedResult
        end reversedItems

        on encodeOrdered(folderItems)
            set outputText to "ORDERED"
            tell application "Finder"
                repeat with folderItem in folderItems
                    set outputText to outputText & linefeed & (URL of folderItem)
                end repeat
            end tell
            return outputText
        end encodeOrdered

        on encodePositions(folderItems)
            set outputText to "POSITION"
            tell application "Finder"
                repeat with folderItem in folderItems
                    set itemPosition to position of folderItem
                    set outputText to outputText & linefeed & (URL of folderItem) & tab & (item 1 of itemPosition as text) & tab & (item 2 of itemPosition as text)
                end repeat
            end tell
            return outputText
        end encodePositions

        set requestedFolderURL to "\(folderLiteral)"
        with timeout of 1 second
            tell application "Finder"
                set finderWindowCount to count of Finder windows
                repeat with finderWindowIndex from 1 to finderWindowCount
                    try
                        set finderWindow to Finder window finderWindowIndex
                        if (URL of target of finderWindow) is requestedFolderURL then
                            set viewMode to current view of finderWindow
                            set folderItems to every item of target of finderWindow
                            set orderedItems to folderItems

                            if viewMode is list view then
                                set activeColumn to sort column of list view options of finderWindow
                                set activeColumnName to name of activeColumn
                                if activeColumnName is name column then
                                    set orderedItems to sort folderItems by name
                                else if activeColumnName is modification date column then
                                    set orderedItems to sort folderItems by modification date
                                else if activeColumnName is creation date column then
                                    set orderedItems to sort folderItems by creation date
                                else if activeColumnName is size column then
                                    set orderedItems to sort folderItems by size
                                else if activeColumnName is kind column then
                                    set orderedItems to sort folderItems by kind
                                else if activeColumnName is label column then
                                    set orderedItems to sort folderItems by label index
                                else if activeColumnName is version column then
                                    set orderedItems to sort folderItems by version
                                else if activeColumnName is comment column then
                                    set orderedItems to sort folderItems by comment
                                else
                                    return ""
                                end if
                                if (sort direction of activeColumn) is reversed then
                                    set orderedItems to my reversedItems(orderedItems)
                                end if
                                return my encodeOrdered(orderedItems)
                            else if viewMode is icon view then
                                set iconArrangement to arrangement of icon view options of finderWindow
                                if iconArrangement is not arranged or iconArrangement is snap to grid then
                                    return my encodePositions(folderItems)
                                else
                                    -- Finder does not expose the sort direction for
                                    -- arranged icon views. Do not guess an ascending
                                    -- order when the visible order may be descending.
                                    return ""
                                end if
                            else if viewMode is column view or viewMode is group view then
                                -- Finder exposes neither column-view order nor grouped
                                -- visual order through its standard scripting interface.
                                -- Returning no system result keeps PicSee's immediate
                                -- filename fallback instead of accepting a guessed order.
                                return ""
                            else
                                return ""
                            end if
                        end if
                    on error errorMessage number errorNumber
                        return "SCRIPT_ERROR" & tab & errorNumber & tab & errorMessage
                    end try
                end repeat
            end tell
        end timeout
        return "NO_MATCHING_WINDOW"
        """
    }

    private static func parseInstruction(_ output: String) -> FinderOrderInstruction? {
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let firstLine = lines.first else { return nil }
        let header = firstLine.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard let mode = header.first else { return nil }

        switch mode {
        case "ORDERED":
            let urls = lines.dropFirst().compactMap(fileURL)
            guard urls.count == lines.count - 1, !urls.isEmpty else { return nil }
            return .exact(urls)
        case "POSITION":
            let positionedURLs = lines.dropFirst().compactMap { line -> PositionedURL? in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard
                    fields.count == 3,
                    let url = fileURL(String(fields[0])),
                    let x = Double(fields[1]),
                    let y = Double(fields[2])
                else {
                    return nil
                }
                return PositionedURL(url: url, x: x, y: y)
            }
            guard positionedURLs.count == lines.count - 1, !positionedURLs.isEmpty else { return nil }
            return .positions(positionedURLs)
        default:
            return nil
        }
    }

    private static func validatedImageOrder(
        _ urls: [URL],
        directoryURLs: [URL]
    ) -> [URL]? {
        let expected = Set(directoryURLs.map { $0.standardizedFileURL })
        var seen: Set<URL> = []
        var images: [URL] = []
        for url in urls {
            let standardizedURL = url.standardizedFileURL
            guard expected.contains(standardizedURL) else { continue }
            guard seen.insert(standardizedURL).inserted else {
                return nil
            }
            images.append(standardizedURL)
        }
        guard images.count == expected.count, Set(images) == expected else { return nil }
        return images
    }

    private static func directoryImageURLs(in folderURL: URL) -> [URL]? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return urls.compactMap { url in
            let standardizedURL = url.standardizedFileURL
            guard
                FolderImageNavigator.isSupportedImage(standardizedURL),
                (try? standardizedURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else {
                return nil
            }
            return standardizedURL
        }
    }

    private static func nameComesBefore(_ lhs: URL, _ rhs: URL) -> Bool {
        let comparison = lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.absoluteString < rhs.absoluteString
    }

    private static func execute(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result.stringValue
    }

    private static func fileURL(_ string: String) -> URL? {
        guard let url = URL(string: string), url.isFileURL else { return nil }
        return url.standardizedFileURL
    }

    private static func appleScriptLiteral(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private struct PositionedURL: Equatable {
    let url: URL
    let x: Double
    let y: Double
}
