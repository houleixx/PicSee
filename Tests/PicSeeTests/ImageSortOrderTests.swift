import AppKit
import XCTest
@testable import PicSee

final class ImageSortOrderTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    private func file(_ name: String, date: Double = 100, size: Int = 1) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(repeating: 0, count: size).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: date)], ofItemAtPath: url.path)
        return url
    }

    func testLocalDateSortAndDeterministicNaturalNameTies() throws {
        let ten = try file("10.png", date: 200)
        let two = try file("2.png", date: 200)
        let old = try file("1.png", date: 100)
        let order = ImageSortOrder(field: .modificationDate, ascending: false)
        XCTAssertEqual(order.sorted([old, ten, two]), [two, ten, old])
        XCTAssertEqual(ImageSortOrder.filename.sorted([ten, two, old]), [old, two, ten])
        XCTAssertEqual(ImageSortOrder(field: .modificationDate, ascending: true).sorted([ten, old, two]), [old, two, ten])
    }

    func testMissingMetadataDoesNotInventAnOrder() {
        let missing = folder.appendingPathComponent("missing.png")
        XCTAssertNil(ImageSortOrder(field: .modificationDate, ascending: false).sorted([missing]))
    }

    func testProviderAppliesLiveRuleInsteadOfFilenameFallback() async throws {
        let old = try file("1.png", date: 100)
        let new = try file("2.png", date: 200)
        let provider = FinderFolderOrderProvider(
            { _ in "RULE\tmodificationDate\tDESC" }, directoryReader: { _ in [old, new] },
            permissionRequester: { true },
            settingsReader: { _ in FinderStoredViewSettings(records: [:], columnOptions: [:]) }
        )
        let result = await provider.ordering(for: folder)
        XCTAssertEqual(result.urls, [new, old])
        XCTAssertEqual(result.status, "跟随 Finder：修改日期降序")
        XCTAssertFalse(provider.isOrderingAvailableImmediately)
    }

    func testColumnOrderingUsesItsOwnRuleRatherThanOldListColumn() async throws {
        let small = try file("1.png", size: 1)
        let large = try file("2.png", size: 20)
        let provider = FinderFolderOrderProvider(
            { _ in "COLUMN" }, directoryReader: { _ in [small, large] }, permissionRequester: { true },
            settingsReader: { _ in FinderStoredViewSettings(records: [:], columnOptions: ["ArrangeBy": "logs"]) }
        )
        let result = await provider.ordering(for: folder)
        XCTAssertEqual(result.urls, [large, small])
    }

    func testUnsupportedGroupingAndMalformedRuleProduceExplicitFallback() async throws {
        let image = try file("1.png")
        for output in ["RULE\tmodificationDate\tDESC", "RULE\tunknown\tDESC", "RULE\tname\tINVALID"] {
            let provider = FinderFolderOrderProvider(
                { _ in output }, directoryReader: { _ in [image] }, permissionRequester: { true },
                settingsReader: { _ in FinderStoredViewSettings(records: ["GRP0": Data("Kind".utf16BigEndianBytes)], columnOptions: [:]) }
            )
            let result = await provider.ordering(for: folder)
            XCTAssertNil(result.urls)
            XCTAssertTrue(result.status.contains("当前按名称"))
        }
    }

    func testDateGroupsRequireMatchingDescendingItemRule() {
        let settings = FinderStoredViewSettings(records: ["GRP0": Data("Date Added".utf16BigEndianBytes)], columnOptions: ["ArrangeBy": "pAdd"])
        XCTAssertEqual(settings.columnOrder, ImageSortOrder(field: .addedDate, ascending: false))
        XCTAssertFalse(settings.supportsGrouping(for: .init(field: .addedDate, ascending: true)))
        XCTAssertFalse(settings.supportsGrouping(for: .init(field: .modificationDate, ascending: false)))
    }

    func testSavedListRuleUsesLiveDirectionAndRecognizesAddedDate() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["sortColumn": "dateAdded"], format: .binary, options: 0)
        let settings = FinderStoredViewSettings(records: ["lsvC": data], columnOptions: [:])
        XCTAssertEqual(settings.listOrder(ascending: false), ImageSortOrder(field: .addedDate, ascending: false))
        XCTAssertEqual(settings.listOrder(ascending: true), ImageSortOrder(field: .addedDate, ascending: true))
        let unknown = FinderStoredViewSettings(records: [:], columnOptions: ["ArrangeBy": "unrecognized"])
        XCTAssertNil(unknown.columnOrder)
    }

    func testViewRecordReaderAndCorruptionHandling() throws {
        var data = Data(repeating: 0, count: 4100)
        func integer(_ value: UInt32, _ offset: Int) {
            data.replaceSubrange(offset..<(offset + 4), with: [UInt8(value >> 24), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)])
        }
        integer(1, 0)
        data.replaceSubrange(4..<8, with: Data("Bud1".utf8))
        integer(2048, 8); integer(2048, 12); integer(2048, 16)
        integer(2, 2052) // allocator: two block addresses, padded to 256
        integer(32 | 5, 2060); integer(256 | 10, 2064)
        integer(1, 3084)
        data[3088] = 4
        data.replaceSubrange(3089..<3093, with: Data("DSDB".utf8))
        integer(0, 3093)
        integer(1, 36) // superblock -> node 1
        integer(0, 260); integer(1, 264)
        let filename = Data("photos".utf16BigEndianBytes)
        integer(6, 268)
        data.replaceSubrange(272..<284, with: filename)
        data.replaceSubrange(284..<292, with: Data("GRP0ustr".utf8))
        integer(10, 292)
        data.replaceSubrange(296..<316, with: Data("Date Added".utf16BigEndianBytes))
        let records = try FinderViewRecordReader.records(in: data, filename: "photos")
        XCTAssertEqual(String(data: try XCTUnwrap(records["GRP0"]), encoding: .utf16BigEndian), "Date Added")
        XCTAssertTrue(try FinderViewRecordReader.records(in: data, filename: "other").isEmpty)
        for length in [0, 8, 100, 300, 2100, 3100] {
            XCTAssertThrowsError(try FinderViewRecordReader.records(in: Data(data.prefix(length)), filename: "photos"))
        }
        integer(UInt32.max, 264)
        XCTAssertThrowsError(try FinderViewRecordReader.records(in: data, filename: "photos"))
    }
}

private extension String {
    var utf16BigEndianBytes: [UInt8] { utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] } }
}
