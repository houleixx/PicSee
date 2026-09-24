import AppKit
import CoreServices
import Foundation
import OSLog

protocol FinderFolderOrderProviding: Sendable {
    var isOrderingAvailableImmediately: Bool { get }
    func orderedURLs(for folderURL: URL) async -> [URL]?
    func ordering(for folderURL: URL) async -> FolderOrderingResult
}

extension FinderFolderOrderProviding {
    var isOrderingAvailableImmediately: Bool { false }
    func ordering(for folderURL: URL) async -> FolderOrderingResult {
        let urls = await orderedURLs(for: folderURL)
        return FolderOrderingResult(urls: urls, status: urls == nil ? FolderOrderingResult.unavailable.status : "跟随 Finder")
    }
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
    case rule(ImageSortOrder)
    case column
    case savedList(ascending: Bool)
}

struct FinderFolderOrderProvider: FinderFolderOrderProviding {
    typealias ScriptRunner = @Sendable (String) -> String?
    typealias DirectoryReader = @Sendable (URL) -> [URL]?
    typealias PermissionRequester = @Sendable () async -> Bool

    private let scriptRunner: ScriptRunner
    private let directoryReader: DirectoryReader
    private let permissionRequester: PermissionRequester
    private let settingsReader: @Sendable (URL) -> FinderStoredViewSettings
    private static let logger = Logger(subsystem: "local.picsee.viewer", category: "FinderOrder")

    var isOrderingAvailableImmediately: Bool { false }

    init(
        _ scriptRunner: ScriptRunner? = nil,
        directoryReader: DirectoryReader? = nil,
        permissionRequester: PermissionRequester? = nil,
        settingsReader: @escaping @Sendable (URL) -> FinderStoredViewSettings = { FinderStoredViewSettings(folder: $0) },
        onAuthorizationPromptWillBegin: @escaping @MainActor @Sendable () -> Void = {},
        onAuthorizationPromptFinished: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.scriptRunner = scriptRunner ?? Self.execute
        self.directoryReader = directoryReader ?? Self.directoryImageURLs
        self.settingsReader = settingsReader
        self.permissionRequester = permissionRequester ?? {
            await Self.requestPermission(
                onPromptWillBegin: onAuthorizationPromptWillBegin,
                onPromptFinished: onAuthorizationPromptFinished
            )
        }
    }

    func orderedURLs(for folderURL: URL) async -> [URL]? {
        await ordering(for: folderURL).urls
    }

    func ordering(for folderURL: URL) async -> FolderOrderingResult {
        guard !Task.isCancelled, await permissionRequester(), !Task.isCancelled else {
            return .unavailable
        }
        // AppleScript/file metadata are blocking. A dedicated serial queue also
        // prevents simultaneous viewer windows from issuing competing scripts.
        return await withCheckedContinuation { continuation in
            Self.readQueue.async {
                continuation.resume(returning: self.readOrdering(for: folderURL))
            }
        }
    }

    private static let readQueue = DispatchQueue(label: "PicSee.FinderOrder", qos: .userInitiated)

    private func readOrdering(for folderURL: URL) -> FolderOrderingResult {
        guard let output = scriptRunner(Self.scriptSource(folderURL: folderURL)),
              let instruction = Self.parseInstruction(output) else {
            Self.logger.notice("Finder sorting rule unavailable")
            return .unavailable
        }
        guard let directoryURLs = directoryReader(folderURL), !directoryURLs.isEmpty else { return .unavailable }
        let urls: [URL]?
        let status: String
        switch instruction {
        case .rule(let rule):
            guard settingsReader(folderURL).supportsGrouping(for: rule) else {
                return FolderOrderingResult(urls: nil, status: "暂不支持此分组组合，当前按名称升序")
            }
            urls = rule.sorted(directoryURLs)
            status = "跟随 Finder：" + rule.title
        case .savedList(let ascending):
            guard let rule = settingsReader(folderURL).listOrder(ascending: ascending) else { return .unavailable }
            urls = rule.sorted(directoryURLs)
            status = "按 Finder 保存的排列：" + rule.title
        case .column:
            guard let rule = settingsReader(folderURL).columnOrder else { return .unavailable }
            urls = rule.sorted(directoryURLs)
            status = "按 Finder 保存的排列：" + rule.title
        case .exact(let ordered):
            guard !settingsReader(folderURL).hasGrouping else { return .unavailable }
            urls = Self.validatedImageOrder(ordered, directoryURLs: directoryURLs)
            status = "跟随 Finder"
        case .positions(let positioned):
            guard !settingsReader(folderURL).hasGrouping else { return .unavailable }
            let ordered = positioned.sorted {
                if $0.y != $1.y { return $0.y < $1.y }
                if $0.x != $1.x { return $0.x < $1.x }
                return Self.nameComesBefore($0.url, $1.url)
            }.map(\.url)
            urls = Self.validatedImageOrder(ordered, directoryURLs: directoryURLs)
            status = "按 Finder 图标位置"
        }
        return urls.map { FolderOrderingResult(urls: $0, status: status) } ?? .unavailable
    }

    static func parseOutput(_ output: String) -> [URL]? {
        guard let instruction = parseInstruction(output) else { return nil }
        switch instruction {
        case .rule, .column, .savedList: return nil
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
        with timeout of 3 seconds
            tell application "Finder"
                set finderWindowCount to count of Finder windows
                repeat with finderWindowIndex from 1 to finderWindowCount
                    try
                        set finderWindow to Finder window finderWindowIndex
                        if (URL of target of finderWindow) is requestedFolderURL then
                            set viewMode to current view of finderWindow
                            if viewMode is list view then
                                set activeColumn to sort column of list view options of finderWindow
                                set activeColumnName to name of activeColumn
                                set directionName to "ASC"
                                if (sort direction of activeColumn) is reversed then set directionName to "DESC"
                                if activeColumnName is name column then
                                    return "RULE" & tab & "name" & tab & directionName
                                else if activeColumnName is modification date column then
                                    return "RULE" & tab & "modificationDate" & tab & directionName
                                else if activeColumnName is creation date column then
                                    return "RULE" & tab & "creationDate" & tab & directionName
                                else if activeColumnName is size column then
                                    return "RULE" & tab & "size" & tab & directionName
                                else if activeColumnName is kind column then
                                    return "RULE" & tab & "kind" & tab & directionName
                                else if activeColumnName is label column then
                                    set orderedItems to sort (every item of target of finderWindow) by label index
                                else if activeColumnName is version column then
                                    set orderedItems to sort (every item of target of finderWindow) by version
                                else if activeColumnName is comment column then
                                    set orderedItems to sort (every item of target of finderWindow) by comment
                                else
                                    return "LIST_SAVED" & tab & directionName
                                end if
                                if (sort direction of activeColumn) is reversed then
                                    set orderedItems to my reversedItems(orderedItems)
                                end if
                                return my encodeOrdered(orderedItems)
                            else if viewMode is icon view then
                                set iconArrangement to arrangement of icon view options of finderWindow
                                if iconArrangement is not arranged or iconArrangement is snap to grid then
                                    return my encodePositions(every item of target of finderWindow)
                                else
                                    -- Finder does not expose the sort direction for
                                    -- arranged icon views. Do not guess an ascending
                                    -- order when the visible order may be descending.
                                    return ""
                                end if
                            else if viewMode is column view then
                                return "COLUMN"
                            else if viewMode is group view then
                                return "UNSUPPORTED_VIEW"
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
        case "RULE":
            guard header.count == 3, let field = ImageSortOrder.Field(rawValue: header[1]),
                  ["ASC", "DESC"].contains(header[2]) else { return nil }
            return .rule(ImageSortOrder(field: field, ascending: header[2] == "ASC"))
        case "LIST_SAVED":
            guard header.count == 2, ["ASC", "DESC"].contains(header[1]) else { return nil }
            return .savedList(ascending: header[1] == "ASC")
        case "COLUMN": return .column
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

    typealias AuthorizationCheck = @Sendable (_ askUser: Bool) async -> OSStatus

    static func requestPermission(
        check: AuthorizationCheck = checkPermission,
        onPromptWillBegin: @MainActor @Sendable () -> Void = {},
        onPromptFinished: @MainActor @Sendable () -> Void = {}
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        let status = await check(false)
        guard !Task.isCancelled else { return false }
        guard status == errAEEventWouldRequireUserConsent else { return status == noErr }

        await onPromptWillBegin()
        guard !Task.isCancelled else { return false }
        let response = await check(true)
        guard !Task.isCancelled else { return false }
        // A preflight with no decision was followed by an interactive response.
        // Return focus for both Allow and Don't Allow, never for ordinary checks.
        if response == noErr || response == errAEEventNotPermitted {
            await onPromptFinished()
        }
        return response == noErr
    }

    private static func checkPermission(askUser: Bool) async -> OSStatus {
        // This synchronous system API can wait indefinitely for user consent.
        // Keep it off both the main thread and Swift's cooperative executor.
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                logger.notice("Checking Finder automation authorization: askUser=\(askUser)")
                let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
                let status = AEDeterminePermissionToAutomateTarget(
                    target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), askUser
                )
                logger.notice("Finder automation authorization completed: status=\(status)")
                continuation.resume(returning: status)
            }
        }
    }

    private static func execute(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            logger.error("Finder order script failed: code=\(code)")
            return nil
        }
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
