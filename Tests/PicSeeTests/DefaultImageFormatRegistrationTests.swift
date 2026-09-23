import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PicSee

struct DefaultImageFormatRegistrationTests {
    @Test func ddsUsesTheSystemsRegisteredContentType() throws {
        let format = try #require(DefaultImageAppSettings.formats.first { $0.label == "DDS" })
        let systemType = try #require(UTType(filenameExtension: "dds"))

        #expect(format.contentType == systemType.identifier)
        #expect(UTType(format.contentType) != nil)
    }

    @Test func appDeclaresEverySelectableContentType() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("Scripts/build-app.sh"), encoding: .utf8)
        let types = try #require(script.components(separatedBy: "<key>LSItemContentTypes</key>").last?
            .components(separatedBy: "</array>").first)

        for format in DefaultImageAppSettings.formats {
            #expect(types.contains("<string>\(format.contentType)</string>"), "Missing registration for \(format.label)")
        }
    }
}
