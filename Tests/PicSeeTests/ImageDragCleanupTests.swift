import AppKit
import Testing
@testable import PicSee

struct ImageDragCleanupTests {
    @MainActor
    @Test func workerRunsOffMainThreadAndCoalescesConcurrentRequests() async {
        await confirmation(expectedCount: 1) { cleaned in
            let worker = ImageDragCleanupWorker { _ in
                #expect(!Thread.isMainThread)
                cleaned()
            }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<20 { group.addTask { await worker.run(root: root) } }
            }
        }
    }

    @Test func differentDirectoriesAreCleanedIndependently() async {
        await confirmation(expectedCount: 2) { cleaned in
            let worker = ImageDragCleanupWorker { _ in cleaned() }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            await worker.run(root: root.appendingPathComponent("first"))
            await worker.run(root: root.appendingPathComponent("second"))
            await worker.run(root: root.appendingPathComponent("first"))
        }
    }

    @Test func cleanupCanRunAgainAfterCooldown() async {
        await confirmation(expectedCount: 2) { cleaned in
            let worker = ImageDragCleanupWorker(minimumInterval: 0) { _ in cleaned() }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            await worker.run(root: root)
            await worker.run(root: root)
        }
    }

    @Test func backgroundCleanupPreservesActiveRecentAndUnrelatedFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PicSee-Cleanup-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let expired = now.addingTimeInterval(-ImageDragFileProvider.retentionInterval - 1)
        for (name, date) in [("export-111-expired", expired), ("export-222-active", expired),
                              ("export-333-recent", now), ("unrelated", expired)] {
            let url = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        let worker = ImageDragCleanupWorker { directory in
            ImageDragFileProvider(root: directory, temporaryResourceRoots: [])
                .cleanupExpiredFiles(now: now, processIsRunning: { $0 == 222 })
        }
        await worker.run(root: root)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)) ==
                Set(["export-222-active", "export-333-recent", "unrelated"]))
    }

    @MainActor
    @Test func dragSchedulesCleanupAndKeepsNewExportReadable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PicSee-DragCleanup-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let expired = root.appendingPathComponent("export-2147483647-expired")
        try FileManager.default.createDirectory(at: expired, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-90000)], ofItemAtPath: expired.path)
        let source = root.appendingPathComponent("source.gif")
        let bytes = Data("GIF89a-original-data".utf8)
        try bytes.write(to: source)
        let provider = ImageDragFileProvider(root: root, temporaryResourceRoots: [root])
        let exported = try provider.fileURL(sourceURL: source, image: NSImage())
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while FileManager.default.fileExists(atPath: expired.path) {
            guard ContinuousClock.now < deadline else { throw CleanupTimeout() }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(try Data(contentsOf: exported) == bytes)
        #expect(try Data(contentsOf: source) == bytes)
    }
}

private struct CleanupTimeout: Error {}
