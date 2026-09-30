import Foundation

/// File cleanup has no UI dependencies. A single worker keeps scans off the
/// main actor and coalesces launch/drag requests for the same export directory.
actor ImageDragCleanupWorker {
    private static let shared = ImageDragCleanupWorker()
    private var completedAt: [URL: Date] = [:]
    private let minimumInterval: TimeInterval
    private let cleanup: @Sendable (URL) -> Void

    init(minimumInterval: TimeInterval = 60,
         cleanup: @escaping @Sendable (URL) -> Void = { root in
             ImageDragFileProvider(root: root, temporaryResourceRoots: []).cleanupExpiredFiles()
         }) {
        self.minimumInterval = minimumInterval
        self.cleanup = cleanup
    }

    nonisolated static func schedule(root: URL = ImageDragFileProvider.defaultRoot) {
        Task(priority: .utility) { await shared.run(root: root) }
    }

    func run(root: URL) {
        let root = root.standardizedFileURL
        let now = Date()
        if let completed = completedAt[root], now.timeIntervalSince(completed) < minimumInterval { return }
        // Bound bookkeeping when viewers use different temporary roots.
        completedAt = completedAt.filter { now.timeIntervalSince($0.value) < minimumInterval }
        cleanup(root)
        // Queued requests see the completion time, even if a scan was slow.
        completedAt[root] = Date()
    }
}
