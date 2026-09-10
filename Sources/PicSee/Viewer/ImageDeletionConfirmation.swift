import AppKit

@MainActor
final class ImageDeletionConfirmation {
    static let asksBeforeDeletingKey = "PicSee.AskBeforeDeletingImage"
    typealias Presenter = (ImageDeletionDialog, NSWindow, @escaping (NSApplication.ModalResponse) -> Void) -> Void

    private let defaults: UserDefaults
    private let present: Presenter
    private var isPresenting = false

    init(
        defaults: UserDefaults = .standard,
        present: @escaping Presenter = { dialog, window, completion in
            let escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.window === dialog, event.keyCode == 53 else { return event }
                window.endSheet(dialog, returnCode: .alertFirstButtonReturn)
                return nil
            }
            window.beginSheet(dialog) { response in
                if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
                dialog.orderOut(nil)
                completion(response)
            }
        }
    ) {
        self.defaults = defaults
        self.present = present
    }

    func requestDeletion(for viewModel: ImageViewerViewModel, in window: NSWindow) {
        guard viewModel.canTrashCurrentImage, !isPresenting, window.attachedSheet == nil else { return }
        guard defaults.object(forKey: Self.asksBeforeDeletingKey) as? Bool ?? true else {
            viewModel.trashCurrentImage()
            return
        }

        let imageURL = viewModel.currentURL
        let dialog = ImageDeletionDialog(filename: imageURL.lastPathComponent)
        isPresenting = true
        present(dialog, window) { [weak self, weak viewModel] response in
            guard let self else { return }
            self.isPresenting = false
            guard response == .alertSecondButtonReturn,
                  let viewModel, viewModel.currentURL == imageURL,
                  viewModel.canTrashCurrentImage else { return }
            // Cancelling never changes the preference, even if the box was checked.
            if dialog.suppressionButton.state == .on {
                self.defaults.set(false, forKey: Self.asksBeforeDeletingKey)
            }
            viewModel.trashCurrentImage()
        }
    }
}
