import AppKit

@MainActor
final class DefaultImageAppSettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let formatRowHeight: CGFloat = 38
    private static let leftFormatColumnWidth: CGFloat = 150
    private static let rightFormatColumnWidth: CGFloat = 330
    private static let optionLeadingInset: CGFloat = 15

    private let handler: DefaultImageAppHandling
    private let accessibilityPermissionHandler: AccessibilityPermissionHandling
    private var checkboxes: [(format: DefaultImageFormat, button: NSButton)] = []
    private let statusLabel = NSTextField(labelWithString: "")
    private let accessibilityEnabledLabel = NSTextField(labelWithString: AccessibilityPermissionSettings.enabledStatus)
    private var accessibilitySettingsButton: NSButton!

    init(
        handler: DefaultImageAppHandling,
        accessibilityPermissionHandler: AccessibilityPermissionHandling = SystemAccessibilityPermissionHandler()
    ) {
        self.handler = handler
        self.accessibilityPermissionHandler = accessibilityPermissionHandler

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 590, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置默认图片打开方式"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 570, height: 480)
        window.center()

        super.init(window: window)

        window.delegate = self
        window.contentView = buildContentView()
        refreshAccessibilityPermissionStatus()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        refreshAccessibilityPermissionStatus()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContentView() -> NSView {
        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let header = buildHeaderView()
        let settingsCard = buildSettingsCard()
        let accessibilityCard = buildAccessibilityCard()

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(settingsCard)
        stack.addArrangedSubview(accessibilityCard)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            settingsCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            accessibilityCard.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        return contentView
    }

    private func buildHeaderView() -> NSView {
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .top
        header.spacing = 14

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 5

        let title = NSTextField(labelWithString: "默认图片打开方式")
        title.font = .boldSystemFont(ofSize: 22)

        let subtitle = wrappingLabel("选择双击图片时交给 PicSee 打开的格式，已是 PicSee 默认打开的格式会自动勾选。")
        subtitle.textColor = .secondaryLabelColor

        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(subtitle)
        header.addArrangedSubview(icon)
        header.addArrangedSubview(textStack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 48),
            subtitle.widthAnchor.constraint(equalTo: textStack.widthAnchor)
        ])

        return header
    }

    private func buildSettingsCard() -> NSView {
        let cardContent = NSStackView()
        cardContent.orientation = .vertical
        cardContent.alignment = .width
        cardContent.spacing = 14

        cardContent.addArrangedSubview(buildCardHeaderView())
        cardContent.addArrangedSubview(buildFormatGridView())
        cardContent.addArrangedSubview(indentedView(buildFormatSelectionControlsView()))
        cardContent.addArrangedSubview(indentedView(buildTipView()))

        return insetCard(cardContent, horizontal: 14, vertical: 14)
    }

    private func buildAccessibilityCard() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let explanation = wrappingLabel(AccessibilityPermissionSettings.explanation)
        explanation.font = .systemFont(ofSize: 13)
        explanation.alignment = .left

        accessibilityEnabledLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        accessibilityEnabledLabel.textColor = .systemGreen
        accessibilityEnabledLabel.setAccessibilityIdentifier("accessibility-permission-enabled")

        accessibilitySettingsButton = NSButton(
            title: AccessibilityPermissionSettings.actionTitle,
            target: self,
            action: #selector(openAccessibilitySettings(_:))
        )
        accessibilitySettingsButton.bezelStyle = .rounded
        accessibilitySettingsButton.setAccessibilityIdentifier("open-accessibility-settings")

        row.addArrangedSubview(explanation)
        row.addArrangedSubview(flexibleSpacer())
        row.addArrangedSubview(accessibilityEnabledLabel)
        row.addArrangedSubview(accessibilitySettingsButton)

        return insetCard(row, horizontal: 14, vertical: 12)
    }

    private func buildCardHeaderView(title: String = "常用图片格式") -> NSView {
        let row = NSView()

        let sectionTitle = NSTextField(labelWithString: title)
        sectionTitle.font = .boldSystemFont(ofSize: 13)
        sectionTitle.textColor = .secondaryLabelColor
        sectionTitle.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(sectionTitle)

        NSLayoutConstraint.activate([
            sectionTitle.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            sectionTitle.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
            sectionTitle.topAnchor.constraint(equalTo: row.topAnchor),
            sectionTitle.bottomAnchor.constraint(equalTo: row.bottomAnchor)
        ])

        return row
    }

    private func buildFormatGridView() -> NSView {
        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.xPlacement = .fill
        grid.yPlacement = .fill
        grid.rowSpacing = 2
        grid.columnSpacing = 6

        let hasExistingDefaults = DefaultImageAppSettings.formats.contains { handler.isDefaultViewer(for: $0) }
        let rows = stride(from: 0, to: DefaultImageAppSettings.formats.count, by: 2).map { index in
            [formatCell(at: index, hasExistingDefaults: hasExistingDefaults),
             formatCell(at: index + 1, hasExistingDefaults: hasExistingDefaults)]
        }

        for row in rows {
            grid.addRow(with: row)
        }

        if grid.numberOfColumns > 0 {
            grid.column(at: 0).xPlacement = .fill
            grid.column(at: 0).width = Self.leftFormatColumnWidth
        }

        if grid.numberOfColumns > 1 {
            grid.column(at: 1).xPlacement = .fill
            grid.column(at: 1).width = Self.rightFormatColumnWidth
        }

        for rowIndex in 0..<grid.numberOfRows {
            grid.row(at: rowIndex).height = Self.formatRowHeight
        }

        let gridHeight = (Self.formatRowHeight * CGFloat(grid.numberOfRows)) + (grid.rowSpacing * CGFloat(max(grid.numberOfRows - 1, 0)))
        grid.heightAnchor.constraint(equalToConstant: gridHeight).isActive = true

        return grid
    }

    private func formatCell(at index: Int, hasExistingDefaults: Bool) -> NSView {
        guard index < DefaultImageAppSettings.formats.count else {
            return NSView()
        }

        let format = DefaultImageAppSettings.formats[index]
        let button = NSButton(
            checkboxWithTitle: "\(format.label)  \(dottedExtensions(format.extensions))",
            target: nil,
            action: nil
        )
        button.state = (hasExistingDefaults ? handler.isDefaultViewer(for: format) : true) ? .on : .off
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.lineBreakMode = .byTruncatingTail
        button.toolTip = format.contentType
        checkboxes.append((format, button))

        return button
    }

    private func buildFormatSelectionControlsView() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        let selectAllButton = NSButton(title: "全选", target: self, action: #selector(selectAllFormats(_:)))
        selectAllButton.bezelStyle = .rounded

        let clearButton = NSButton(title: "清除", target: self, action: #selector(clearSelectedFormats(_:)))
        clearButton.bezelStyle = .rounded

        let applyButton = NSButton(title: "设为默认", target: self, action: #selector(applySelectedFormats(_:)))
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(selectAllButton)
        row.addArrangedSubview(clearButton)
        row.addArrangedSubview(flexibleSpacer())
        row.addArrangedSubview(statusLabel)
        row.addArrangedSubview(applyButton)

        return row
    }

    private func dottedExtensions(_ extensions: String) -> String {
        extensions
            .split(separator: ",")
            .map { "." + $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: ", ")
    }

    private func buildTipView() -> NSView {
        let label = wrappingLabel(DefaultImageAppSettings.fallbackInstructions)
        label.textColor = .secondaryLabelColor

        let tip = insetView(label, horizontal: 0, vertical: 4)

        NSLayoutConstraint.activate([
            tip.widthAnchor.constraint(greaterThanOrEqualToConstant: 1)
        ])

        return tip
    }

    private func insetCard(_ content: NSView, horizontal: CGFloat, vertical: CGFloat) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = cardBackgroundColor.cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor

        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: horizontal),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -horizontal),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: vertical),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -vertical)
        ])

        return card
    }

    private func insetView(_ content: NSView, horizontal: CGFloat, vertical: CGFloat) -> NSView {
        let wrapper = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: horizontal),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -horizontal),
            content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: vertical),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -vertical)
        ])

        return wrapper
    }

    private var cardBackgroundColor: NSColor {
        NSColor.windowBackgroundColor.blended(
            withFraction: 0.35,
            of: .controlBackgroundColor
        ) ?? .windowBackgroundColor
    }

    private func indentedView(_ content: NSView) -> NSView {
        let wrapper = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: Self.optionLeadingInset),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            content.topAnchor.constraint(equalTo: wrapper.topAnchor),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])

        return wrapper
    }

    private func wrappingLabel(_ string: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        return label
    }

    private func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshAccessibilityPermissionStatus()
    }

    private func refreshAccessibilityPermissionStatus() {
        let isTrusted = accessibilityPermissionHandler.isTrusted
        accessibilityEnabledLabel.isHidden = !isTrusted
        accessibilitySettingsButton?.isHidden = isTrusted
    }

    @objc private func openAccessibilitySettings(_ sender: Any?) {
        accessibilityPermissionHandler.openSystemSettings()
    }

    @objc private func selectAllFormats(_ sender: Any?) {
        for checkbox in checkboxes {
            checkbox.button.state = .on
        }
    }

    @objc private func clearSelectedFormats(_ sender: Any?) {
        for checkbox in checkboxes {
            checkbox.button.state = .off
        }
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
            statusLabel.stringValue = "已设置 \(selectedFormats.count) 种格式。"
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "设置默认打开方式失败"
            alert.runModal()
        }
    }
}
