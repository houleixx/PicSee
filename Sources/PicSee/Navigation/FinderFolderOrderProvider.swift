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

struct FinderFolderOrderProvider: FinderFolderOrderProviding {
    typealias ScriptRunner = @Sendable (String) -> String?

    private let scriptRunner: ScriptRunner

    init(scriptRunner: ScriptRunner? = nil) {
        self.scriptRunner = scriptRunner ?? Self.execute
    }

    func orderedURLs(for folderURL: URL) async -> [URL]? {
        guard let output = scriptRunner(Self.scriptSource(folderURL: folderURL)) else {
            return nil
        }
        if output.trimmingCharacters(in: .whitespacesAndNewlines) == "DATE_ADDED_DESCENDING" {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.addedToDirectoryDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                return nil
            }
            return Self.sortedByDateAdded(urls.map(\.standardizedFileURL), dateAdded: Self.dateAddedDate)
        }
        return Self.parseOutput(output)
    }

    static func parseOutput(_ output: String) -> [URL]? {
        parseOutput(output, dateAdded: dateAddedDate)
    }

    static func parseOutput(
        _ output: String,
        dateAdded: (URL) -> Date?
    ) -> [URL]? {
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let mode = lines.first else { return nil }

        switch mode {
        case "ORDERED":
            let urls = lines.dropFirst().compactMap(Self.fileURL)
            return urls.isEmpty ? nil : urls
        case "DATE_ADDED_DESCENDING":
            let urls = lines.dropFirst().compactMap(Self.fileURL)
            guard !urls.isEmpty else { return nil }
            return sortedByDateAdded(urls, dateAdded: dateAdded)
        case "POSITION":
            let positionedURLs = lines.dropFirst().compactMap { line -> PositionedURL? in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard
                    fields.count == 3,
                    let url = Self.fileURL(String(fields[0])),
                    let x = Double(fields[1]),
                    let y = Double(fields[2])
                else {
                    return nil
                }
                return PositionedURL(url: url, x: x, y: y)
            }
            guard positionedURLs.count == lines.count - 1, !positionedURLs.isEmpty else { return nil }
            return positionedURLs.sorted {
                if $0.y != $1.y { return $0.y < $1.y }
                if $0.x != $1.x { return $0.x < $1.x }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }.map(\.url)
        default:
            return nil
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
        tell application "Finder"
            set finderWindowCount to count of Finder windows
            repeat with finderWindowIndex from 1 to finderWindowCount
                try
                    set finderWindow to Finder window finderWindowIndex
                    if (URL of target of finderWindow) is requestedFolderURL then
                        set viewMode to current view of finderWindow
                        set finderArrangement to ""
                        if viewMode is column view then
                            try
                                set finderArrangement to do shell script "/usr/bin/defaults read com.apple.finder FK_ArrangeBy"
                            end try
                            if finderArrangement is "Date Added" then
                                return "DATE_ADDED_DESCENDING"
                            end if
                        end if
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
                            else if iconArrangement is arranged by name then
                                set orderedItems to sort folderItems by name
                            else if iconArrangement is arranged by modification date then
                                set orderedItems to sort folderItems by modification date
                            else if iconArrangement is arranged by creation date then
                                set orderedItems to sort folderItems by creation date
                            else if iconArrangement is arranged by size then
                                set orderedItems to sort folderItems by size
                            else if iconArrangement is arranged by kind then
                                set orderedItems to sort folderItems by kind
                            else if iconArrangement is arranged by label then
                                set orderedItems to sort folderItems by label index
                            else
                                return ""
                            end if
                            return my encodeOrdered(orderedItems)
                        else if current view of finderWindow is column view then
                            if finderArrangement is "Date Modified" then
                                set orderedItems to sort folderItems by modification date
                                return my encodeOrdered(my reversedItems(orderedItems))
                            else if finderArrangement is "Date Created" then
                                set orderedItems to sort folderItems by creation date
                                return my encodeOrdered(my reversedItems(orderedItems))
                            else if finderArrangement is "Size" then
                                set orderedItems to sort folderItems by size
                                return my encodeOrdered(my reversedItems(orderedItems))
                            else if finderArrangement is "Kind" then
                                set orderedItems to sort folderItems by kind
                                return my encodeOrdered(orderedItems)
                            else
                                set orderedItems to sort folderItems by name
                                return my encodeOrdered(orderedItems)
                            end if
                        else
                            return ""
                        end if
                    end if
                on error errorMessage number errorNumber
                    return "SCRIPT_ERROR" & tab & errorNumber & tab & errorMessage
                end try
            end repeat
        end tell
        return "NO_MATCHING_WINDOW"
        """
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

    private static func dateAddedDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate
    }

    private static func sortedByDateAdded(
        _ urls: [URL],
        dateAdded: (URL) -> Date?
    ) -> [URL] {
        urls.sorted {
            let lhsDate = dateAdded($0) ?? .distantPast
            let rhsDate = dateAdded($1) ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private static func appleScriptLiteral(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private struct PositionedURL {
    let url: URL
    let x: Double
    let y: Double
}
