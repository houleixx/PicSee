import Foundation

struct ImageSortOrder: Equatable, Sendable {
    enum Field: String, Sendable {
        case name, creationDate, modificationDate, addedDate, size, kind

        var title: String {
            switch self {
            case .name: L10n.text("名称")
            case .creationDate: L10n.text("创建日期")
            case .modificationDate: L10n.text("修改日期")
            case .addedDate: L10n.text("添加日期")
            case .size: L10n.text("文件大小")
            case .kind: L10n.text("种类")
            }
        }

        var isDate: Bool { [.creationDate, .modificationDate, .addedDate].contains(self) }
    }

    var field: Field
    var ascending: Bool
    var title: String { L10n.text("%1$@%2$@", String(describing: field.title), String(describing: ascending ? L10n.text("升序") : L10n.text("降序"))) }
    static let filename = Self(field: .name, ascending: true)

    // Materialize metadata once, rather than performing file I/O inside the comparator.
    func sorted(_ urls: [URL]) -> [URL]? {
        let keys: Set<URLResourceKey>
        switch field {
        case .name: keys = []
        case .creationDate: keys = [.creationDateKey]
        case .modificationDate: keys = [.contentModificationDateKey]
        case .addedDate: keys = [.addedToDirectoryDateKey]
        case .size: keys = [.fileSizeKey]
        case .kind: keys = [.localizedTypeDescriptionKey]
        }
        var entries: [(url: URL, number: Double, text: String)] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            let number: Double?
            var text = url.lastPathComponent
            switch field {
            case .name: number = 0
            case .creationDate: number = values.creationDate?.timeIntervalSince1970
            case .modificationDate: number = values.contentModificationDate?.timeIntervalSince1970
            case .addedDate: number = values.addedToDirectoryDate?.timeIntervalSince1970
            case .size: number = values.fileSize.map(Double.init)
            case .kind:
                guard let kind = values.localizedTypeDescription else { return nil }
                text = kind
                number = 0
            }
            // Missing metadata must not masquerade as a correct Finder ordering.
            guard let number else { return nil }
            entries.append((url, number, text))
        }
        return entries.sorted { lhs, rhs in
            let comparison: ComparisonResult
            if field == .name || field == .kind {
                comparison = lhs.text.localizedStandardCompare(rhs.text)
            } else {
                comparison = lhs.number == rhs.number ? .orderedSame : (lhs.number < rhs.number ? .orderedAscending : .orderedDescending)
            }
            if comparison != .orderedSame {
                return comparison == (ascending ? .orderedAscending : .orderedDescending)
            }
            let tie = lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent)
            if tie != .orderedSame { return tie == .orderedAscending }
            return lhs.url.path < rhs.url.path
        }.map(\.url)
    }
}

struct FolderOrderingResult: Sendable {
    let urls: [URL]?
    let status: String
    static var unavailable: Self { Self(urls: nil, status: L10n.text("未能读取 Finder 顺序，当前按名称升序")) }
}
