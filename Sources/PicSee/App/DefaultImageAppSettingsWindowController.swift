import AppKit

@MainActor
final class DefaultImageAppSettingsWindowController: NSWindowController {
    private let handler: DefaultImageAppHandling
    private var checkboxes: [(format: DefaultImageFormat, button: NSButton)] = []
    private let statusLabel = NSTextField(labelWithString: "")

    init(handler: DefaultImageAppHandling) {
        self.handler = handler

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置默认图片打开方式"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        window.contentView = buildContentView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContentView() -> NSView {
        let contentView = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let title = NSTextField(labelWithString: "设置 PicSee 为默认图片查看器")
        title.font = .boldSystemFont(ofSize: 18)
        stack.addArrangedSubview(title)

        let subtitle = wrappingLabel("选择要交给 PicSee 打开的图片格式。之后双击这些图片时会直接用 PicSee 打开。")
        stack.addArrangedSubview(subtitle)

        let formatStack = NSStackView()
        formatStack.orientation = .vertical
        formatStack.alignment = .leading
        formatStack.spacing = 8

        let hasExistingDefaults = DefaultImageAppSettings.formats.contains { handler.isDefaultViewer(for: $0) }
        for format in DefaultImageAppSettings.formats {
            let button = NSButton(
                checkboxWithTitle: "\(format.label)  .\(format.extensions)",
                target: nil,
                action: nil
            )
            button.state = (hasExistingDefaults ? handler.isDefaultViewer(for: format) : true) ? .on : .off
            button.toolTip = format.contentType
            checkboxes.append((format, button))
            formatStack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(formatStack)

        let fallback = wrappingLabel(DefaultImageAppSettings.fallbackInstructions)
        fallback.textColor = .secondaryLabelColor
        stack.addArrangedSubview(fallback)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(statusLabel)

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 10

        let selectAllButton = NSButton(title: "全选", target: self, action: #selector(selectAllFormats(_:)))
        let applyButton = NSButton(title: "设为默认", target: self, action: #selector(applySelectedFormats(_:)))
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        let closeButton = NSButton(title: "关闭", target: self, action: #selector(closeWindow(_:)))

        buttonStack.addArrangedSubview(selectAllButton)
        buttonStack.addArrangedSubview(NSView())
        buttonStack.addArrangedSubview(closeButton)
        buttonStack.addArrangedSubview(applyButton)
        stack.addArrangedSubview(buttonStack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            fallback.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonStack.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        return contentView
    }

    private func wrappingLabel(_ string: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        return label
    }

    @objc private func selectAllFormats(_ sender: Any?) {
        for checkbox in checkboxes {
            checkbox.button.state = .on
        }
    }

    @objc private func closeWindow(_ sender: Any?) {
        close()
    }

    @objc private func applySelectedFormats(_ sender: Any?) {
        let selectedFormats = checkboxes
            .filter { $0.button.state == .on }
            .map(\.format)

        guard !selectedFormats.isEmpty else {
            NSSound.beep()
            statusLabel.stringValue = "请至少选择一种图片格式。"
            return
        }

        do {
            for format in selectedFormats {
                try handler.setDefaultViewer(for: format)
            }
            statusLabel.stringValue = "已设置 \(selectedFormats.count) 种图片格式默认用 PicSee 打开。"
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "设置默认打开方式失败"
            alert.runModal()
        }
    }
}
