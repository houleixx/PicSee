import AppKit
import Foundation

/// Per-viewer cache. Opening a file never starts speculative work; only a
/// completed manual page turn does. Cache misses still use the foreground reader.
@MainActor
final class ImagePrefetchCache {
    static let defaultByteLimit = Int(min(UInt64(128 * 1024 * 1024), ProcessInfo.processInfo.physicalMemory / 16))
    private struct Stamp: Equatable {
        let modified: Date
        let size: UInt64
        let inode: UInt64

        init?(_ url: URL) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let modified = attributes[.modificationDate] as? Date,
                  let size = attributes[.size] as? NSNumber,
                  let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
            self.modified = modified
            self.size = size.uint64Value
            self.inode = inode.uint64Value
        }
    }
    private struct Entry {
        let url: URL
        let stamp: Stamp
        let image: LoadedImage
        let cost: Int
    }
    private var entries: [Entry] = []
    private var displayed: Entry?
    private var speculative: (url: URL, stamp: Stamp, id: UUID, task: Task<LoadedImage?, Never>)?
    private let byteLimit: Int
    private let prefetchReader: @Sendable (URL, Int) async -> LoadedImage?

    init(byteLimit: Int = defaultByteLimit,
         prefetchReader: @escaping @Sendable (URL, Int) async -> LoadedImage? = ImageLoadWorker.prefetch) {
        self.byteLimit = max(0, byteLimit)
        self.prefetchReader = prefetchReader
    }

    deinit { speculative?.task.cancel() }

    func clear() {
        cancelPrefetch()
        entries.removeAll()
        displayed = nil
    }

    private func cancelPrefetch() {
        speculative?.task.cancel()
        speculative = nil
    }

    private func cached(_ url: URL) -> LoadedImage? {
        guard let index = entries.firstIndex(where: { $0.url == url }) else { return nil }
        let entry = entries.remove(at: index)
        guard Stamp(url) == entry.stamp else { return nil }
        entries.append(entry)
        return entry.image
    }

    func load(_ url: URL, reader: @Sendable (URL) async -> LoadedImage?) async -> LoadedImage? {
        let url = url.standardizedFileURL
        if speculative?.url != url { cancelPrefetch() }
        if let image = cached(url) { return image }
        if let pending = speculative, pending.url == url, Stamp(url) == pending.stamp {
            // Awaiting the same task reuses the work already in progress.
            let image = await pending.task.value
            guard !Task.isCancelled else { return nil }
            if let image, Stamp(url) == pending.stamp { return image }
        }
        guard !Task.isCancelled else { return nil }
        return await reader(url)
    }

    func didDisplay(_ url: URL, image: LoadedImage?, retainingPrevious: Bool) {
        if retainingPrevious, let previous = displayed, previous.url != url,
           Stamp(previous.url) == previous.stamp {
            insert(previous)
        }
        entries.removeAll { $0.url == url }
        displayed = image.flatMap { makeEntry(url, image: $0) }
    }

    func prefetch(_ url: URL?) {
        guard let url = url?.standardizedFileURL, url != displayed?.url,
              byteLimit > 0 else { cancelPrefetch(); return }
        if cached(url) != nil { cancelPrefetch(); return }
        if speculative?.url == url { return }
        cancelPrefetch()
        guard let stamp = Stamp(url) else { return }
        let id = UUID()
        let reader = prefetchReader
        let limit = byteLimit
        let task = Task(priority: .utility) { [weak self] in
            let image = await reader(url, limit)
            guard !Task.isCancelled, let self, self.speculative?.id == id else { return nil as LoadedImage? }
            self.speculative = nil
            guard Stamp(url) == stamp else { return nil }
            if let image, let entry = self.makeEntry(url, image: image) { self.insert(entry) }
            return image
        }
        speculative = (url, stamp, id, task)
    }

    private func makeEntry(_ url: URL, image: LoadedImage) -> Entry? {
        guard let stamp = Stamp(url), let size = image.pixelSize,
              size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        // Budget for decoded pixels and retained encoded data, rather than the
        // compressed file size alone. Multi-frame images are never cached.
        let cost = Double(size.width) * Double(size.height) * 8 + Double(max(0, image.byteCount ?? 0))
        guard cost <= Double(byteLimit),
              image.image.representations.allSatisfy({
                  (($0 as? NSBitmapImageRep)?.value(forProperty: .frameCount) as? Int ?? 1) <= 1
              }) else { return nil }
        return Entry(url: url, stamp: stamp, image: image, cost: Int(cost.rounded(.up)))
    }

    private func insert(_ entry: Entry) {
        entries.removeAll { $0.url == entry.url }
        entries.append(entry)
        while entries.count > 2 || entries.reduce(0, { $0 + $1.cost }) > byteLimit {
            entries.removeFirst()
        }
    }
}
