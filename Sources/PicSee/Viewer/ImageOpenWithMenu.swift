import AppKit
import UniformTypeIdentifiers

extension CanvasNSView {
    private struct OpenWithSelection {
        let imageURL: URL
        let applicationURL: URL?
    }

    func makeOpenWithMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L10n.text("图片打开方式"), action: nil, keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier("PicSee.OpenWith")
        item.image = PhosphorImages.contextMenuImage(for: "macwindow")
        LanguageSettings.bind(item) { $0.title = L10n.text("图片打开方式") }
        guard image != nil, let imageURL, Self.hasOriginalFile(at: imageURL) else {
            item.isEnabled = false
            return item
        }

        let submenu = NSMenu()
        var seen: Set<URL> = []
        for applicationURL in applicationsForOpeningImage(imageURL) {
            let canonicalURL = applicationURL.resolvingSymlinksInPath()
            guard seen.insert(canonicalURL).inserted,
                  Bundle(url: canonicalURL)?.bundleIdentifier != "local.picsee.viewer" else { continue }
            let filename = FileManager.default.displayName(atPath: applicationURL.path)
            let name = filename.hasSuffix(".app") ? String(filename.dropLast(4)) : filename
            let appItem = openWithItem(title: name, imageURL: imageURL, applicationURL: applicationURL)
            if let icon = NSWorkspace.shared.icon(forFile: applicationURL.path).copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                appItem.image = icon
            }
            submenu.addItem(appItem)
        }
        if !submenu.items.isEmpty { submenu.addItem(.separator()) }
        let other = openWithItem(title: L10n.text("其他…"), imageURL: imageURL, applicationURL: nil)
        LanguageSettings.bind(other) { $0.title = L10n.text("其他…") }
        submenu.addItem(other)
        item.submenu = submenu
        return item
    }

    private func openWithItem(title: String, imageURL: URL, applicationURL: URL?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(openImageWithForMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = OpenWithSelection(imageURL: imageURL, applicationURL: applicationURL)
        return item
    }

    @objc private func openImageWithForMenu(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? OpenWithSelection else { return }
        if let applicationURL = selection.applicationURL {
            openOriginalImage(selection.imageURL, with: applicationURL)
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
        panel.canChooseDirectories = false
        LanguageSettings.bind(panel) {
            $0.title = L10n.text("选择应用程序")
            $0.prompt = L10n.text("打开")
        }
        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let applicationURL = panel.url else { return }
            self?.openOriginalImage(selection.imageURL, with: applicationURL)
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: complete) }
        else { panel.begin(completionHandler: complete) }
    }

    private func openOriginalImage(_ imageURL: URL, with applicationURL: URL) {
        Task { [weak self] in
            guard let self else { return }
            do {
                guard Self.hasOriginalFile(at: imageURL) else { throw CocoaError(.fileReadNoSuchFile) }
                try await self.openImageInApplication(imageURL, applicationURL)
            } catch {
                let alert = NSAlert()
                alert.addButton(withTitle: L10n.text("好"))
                LanguageSettings.bind(alert) {
                    $0.messageText = L10n.text("无法使用所选应用打开图片")
                    $0.informativeText = L10n.errorDescription(error)
                    $0.buttons.first?.title = L10n.text("好")
                }
                if let window = self.window { alert.beginSheetModal(for: window, completionHandler: nil) }
                else { alert.runPicSeeModal() }
            }
        }
    }

    private static func hasOriginalFile(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return url.isFileURL && FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }
}
