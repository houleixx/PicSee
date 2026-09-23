import AppKit
import Testing
@testable import PicSee

struct DefaultImageAppApplyTests {
    @Test func failureDoesNotPreventLaterFormatsFromBeingSet() throws {
        let png = try format("PNG")
        let dds = try format("DDS")
        let exr = try format("OpenEXR")
        let hdr = try format("Radiance HDR")
        let jxl = try format("JPEG XL")
        let handler = RecordingDefaultHandler(defaults: [png.id], failures: [dds.id: -50])

        let result = DefaultImageAppSettings.apply([png, dds, exr, hdr, jxl], using: handler)

        #expect(handler.attempted == [dds.id, exr.id, hdr.id, jxl.id])
        #expect(result.completed == [png, exr, hdr, jxl])
        #expect(result.failures.map(\.format) == [dds])
        #expect(result.failureDetails.contains("DDS"))
        #expect(result.failureDetails.contains("-50"))
        #expect(result.statusMessage == "已完成 4 种，1 种失败。")
    }

    @Test func successfulBatchReportsAllSelectedFormats() throws {
        let formats = [try format("DDS"), try format("OpenEXR")]
        let handler = RecordingDefaultHandler()

        let result = DefaultImageAppSettings.apply(formats, using: handler)

        #expect(result.completed == formats)
        #expect(result.failures.isEmpty)
        #expect(result.statusMessage == "已设置 2 种格式。")
        #expect(formats.allSatisfy { handler.isDefaultViewer(for: $0) })
    }

    @Test @MainActor func errorAlertPreservesFormatAndErrorCode() throws {
        let dds = try format("DDS")
        let handler = RecordingDefaultHandler(failures: [dds.id: -50])
        let result = DefaultImageAppSettings.apply([dds], using: handler)

        let alert = DefaultImageAppSettingsWindowController.makeFailureAlert(for: result)

        #expect(alert.messageText == "设置默认打开方式失败")
        #expect(alert.informativeText.contains("DDS"))
        #expect(alert.informativeText.contains("-50"))
        #expect(alert.informativeText.contains("全部更改"))
    }

    private func format(_ label: String) throws -> DefaultImageFormat {
        try #require(DefaultImageAppSettings.formats.first { $0.label == label })
    }
}

private final class RecordingDefaultHandler: DefaultImageAppHandling {
    private var defaults: Set<String>
    private let failures: [String: OSStatus]
    private(set) var attempted: [String] = []

    init(defaults: Set<String> = [], failures: [String: OSStatus] = [:]) {
        self.defaults = defaults
        self.failures = failures
    }

    func isDefaultViewer(for format: DefaultImageFormat) -> Bool {
        defaults.contains(format.id)
    }

    func setDefaultViewer(for format: DefaultImageFormat) throws {
        attempted.append(format.id)
        if let status = failures[format.id] {
            throw DefaultImageAppError.launchServicesFailed(status, format.contentType)
        }
        defaults.insert(format.id)
    }
}
