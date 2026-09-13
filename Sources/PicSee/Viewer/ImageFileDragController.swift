import AppKit
import OSLog

@MainActor
final class ImageFileDragController: NSObject, NSDraggingSource {
    typealias SessionStarter = (NSView, [NSDraggingItem], NSEvent, any NSDraggingSource) -> Void

    private let files: ImageDragFileProvider
    private let startSession: SessionStarter
    private var onEnded: (() -> Void)?
    private(set) var isDragging = false

    init(
        files: ImageDragFileProvider = ImageDragFileProvider(),
        startSession: @escaping SessionStarter = { view, items, event, source in
            view.beginDraggingSession(with: items, event: event, source: source)
        }
    ) {
        self.files = files
        self.startSession = startSession
    }

    @discardableResult
    func begin(from view: NSView, event: NSEvent, image: NSImage, sourceURL: URL?, onEnded: @escaping () -> Void) -> Bool {
        guard !isDragging else { return false }
        do {
            let url = try files.fileURL(sourceURL: sourceURL, image: image)
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let scale = min(1, 160 / max(image.size.width, image.size.height, 1))
            let size = NSSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
            let preview = NSImage(size: size, flipped: false) { rect in
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.85)
                return true
            }
            let point = view.convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                         width: size.width, height: size.height), contents: preview)
            self.onEnded = onEnded
            isDragging = true
            startSession(view, [item], event, self)
            return true
        } catch {
            Logger(subsystem: "local.picsee.viewer", category: "ImageDrag")
                .error("Unable to prepare dragged image: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        finish()
    }

    // The receiver may still be reading temporary files here; expiration happens
    // on a later launch/export, never in the session-end callback.
    func finish() {
        isDragging = false
        let completion = onEnded
        onEnded = nil
        completion?()
    }
}
