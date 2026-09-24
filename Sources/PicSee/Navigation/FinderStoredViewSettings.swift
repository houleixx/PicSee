import Foundation

/// A bounded, read-only reader for the folder's view records. Never writes Finder preferences.
/// Saved records may lag behind Finder; live list-view sorting always takes precedence.
struct FinderStoredViewSettings {
    let records: [String: Data]
    let columnOptions: [String: Any]

    init(folder: URL) {
        let parent = folder.deletingLastPathComponent()
        let parentRecords = Self.read(parent.appendingPathComponent(".DS_Store"), name: folder.lastPathComponent)
        let ownRecords = Self.read(folder.appendingPathComponent(".DS_Store"), name: ".")
        records = parentRecords.merging(ownRecords) { current, _ in current }
        let preferencesURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.finder.plist")
        let preferences = (try? Data(contentsOf: preferencesURL)).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }
        columnOptions = (preferences?["StandardViewOptions"] as? [String: Any])?["ColumnViewOptions"] as? [String: Any] ?? [:]
    }

    init(records: [String: Data], columnOptions: [String: Any]) {
        self.records = records
        self.columnOptions = columnOptions
    }

    var group: String? { records["GRP0"].flatMap { String(data: $0, encoding: .utf16BigEndian) } }

    var hasGrouping: Bool { group.map { !$0.isEmpty && $0 != "None" } ?? false }

    func supportsGrouping(for rule: ImageSortOrder) -> Bool {
        guard hasGrouping, let group else { return true }
        // Chronological grouping preserves a descending date order when the group
        // and item fields agree. Other combinations need explicit bucket rules.
        return rule.field.isDate && !rule.ascending && Self.field(group) == rule.field
    }

    var columnOrder: ImageSortOrder? {
        guard let key = columnOptions["ArrangeBy"] as? String, let field = Self.field(key) else { return nil }
        let rule = ImageSortOrder(field: field, ascending: !field.isDate && field != .size)
        return supportsGrouping(for: rule) ? rule : nil
    }

    func listOrder(ascending: Bool) -> ImageSortOrder? {
        for key in ["lsvC", "lsvP", "lsvp"] {
            guard let data = records[key],
                  let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let name = values["sortColumn"] as? String,
                  let field = Self.field(name) else { continue }
            let rule = ImageSortOrder(field: field, ascending: ascending)
            return supportsGrouping(for: rule) ? rule : nil
        }
        return nil
    }

    static func field(_ value: String) -> ImageSortOrder.Field? {
        switch value {
        case "dnam", "Name", "name": .name
        case "pAdd", "Date Added", "dateAdded": .addedDate
        case "ascd", "Date Created", "dateCreated": .creationDate
        case "modd", "Date Modified", "dateModified": .modificationDate
        case "logs", "Size", "size": .size
        case "kipl", "kind", "Kind": .kind
        default: nil
        }
    }

    private static func read(_ url: URL, name: String) -> [String: Data] {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 16 * 1024 * 1024, let data = try? Data(contentsOf: url)
        else { return [:] }
        return (try? FinderViewRecordReader.records(in: data, filename: name)) ?? [:]
    }
}

/// Only decodes records from allocated B-tree nodes; stale/free blocks are ignored.
struct FinderViewRecordReader {
    enum InvalidStore: Error { case malformed }
    private struct Cursor {
        let data: Data
        var index = 0
        mutating func bytes(_ count: Int) throws -> Data {
            guard count >= 0, index <= data.count, count <= data.count - index else { throw InvalidStore.malformed }
            defer { index += count }
            return data.subdata(in: index..<(index + count))
        }
        mutating func uint32() throws -> Int {
            try bytes(4).reduce(0) { ($0 << 8) | Int($1) }
        }
        mutating func text(_ count: Int, encoding: String.Encoding = .ascii) throws -> String {
            guard let string = String(data: try bytes(count), encoding: encoding) else { throw InvalidStore.malformed }
            return string
        }
    }

    static func records(in data: Data, filename: String) throws -> [String: Data] {
        var header = Cursor(data: data)
        guard try header.uint32() == 1, try header.text(4) == "Bud1" else { throw InvalidStore.malformed }
        let rootOffset = try header.uint32()
        let rootSize = try header.uint32()
        guard try header.uint32() == rootOffset else { throw InvalidStore.malformed }
        func slice(_ offset: Int, _ size: Int) throws -> Data {
            guard offset >= 0, offset <= data.count, size >= 0, size <= data.count - offset else { throw InvalidStore.malformed }
            return data.subdata(in: offset..<(offset + size))
        }
        var allocator = Cursor(data: try slice(rootOffset + 4, rootSize))
        let count = try allocator.uint32()
        guard count > 0, count <= 65536 else { throw InvalidStore.malformed }
        _ = try allocator.uint32()
        var addresses: [Int] = []
        for _ in 0..<count { addresses.append(try allocator.uint32()) }
        _ = try allocator.bytes(((count + 255) / 256 * 256 - count) * 4)
        let tableCount = try allocator.uint32()
        guard tableCount <= 256 else { throw InvalidStore.malformed }
        var database: Int?
        for _ in 0..<tableCount {
            let length = Int(try allocator.bytes(1).first!)
            let name = try allocator.text(length)
            let block = try allocator.uint32()
            if name == "DSDB" { database = block }
        }
        func block(_ id: Int) throws -> Cursor {
            guard addresses.indices.contains(id) else { throw InvalidStore.malformed }
            let address = addresses[id]
            return Cursor(data: try slice((address & ~31) + 4, 1 << (address & 31)))
        }
        guard let database else { throw InvalidStore.malformed }
        var superblock = try block(database)
        let rootNode = try superblock.uint32()
        var visited: Set<Int> = []
        var result: [String: Data] = [:]
        func visit(_ id: Int, depth: Int) throws {
            guard depth < 32, visited.count < 8192, visited.insert(id).inserted else { throw InvalidStore.malformed }
            var node = try block(id)
            let lastChild = try node.uint32()
            let entryCount = try node.uint32()
            guard entryCount <= 65536 else { throw InvalidStore.malformed }
            for _ in 0..<entryCount {
                if lastChild != 0 { try visit(node.uint32(), depth: depth + 1) }
                let nameLength = try node.uint32()
                let name = try node.text(nameLength * 2, encoding: .utf16BigEndian)
                let code = try node.text(4)
                let type = try node.text(4)
                let value: Data
                switch type {
                case "ustr": value = try node.bytes(node.uint32() * 2)
                case "blob": value = try node.bytes(node.uint32())
                case "bool": value = try node.bytes(1)
                case "long", "shor", "type": value = try node.bytes(4)
                case "comp", "dutc": value = try node.bytes(8)
                default: throw InvalidStore.malformed
                }
                if name == filename { result[code] = value }
            }
            if lastChild != 0 { try visit(lastChild, depth: depth + 1) }
        }
        try visit(rootNode, depth: 0)
        return result
    }
}
