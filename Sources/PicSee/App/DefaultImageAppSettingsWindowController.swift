import AppKit

@MainActor
final class DefaultImageAppSettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let formatRowHeight: CGFloat = 38
    private static let formatColumnCount = 3
    private static let formatColumnWidth: CGFloat = 210
    private static let optionLeadingInset: CGFloat = 15

    private let handler: DefaultImageAppHandling
    private var checkboxes: [(format: DefaultImageFormat, button: NSButton)] = []
    private var primaryLabels: [NSTextField] = []
    private var secondaryLabels: [NSTextField] = []
    private weak var contentBackgroundLayer: CALayer?
    private var cardLayers: [CALayer] = []
    private var escapeKeyMonitor: Any?
    private let statusLabel = NSTextField(labelWithString: "")

    init(handler: DefaultImageAppHandling) {
        self.handler = handler

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 730, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置默认图片打开方式"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 730, height: 410)
        window.center()

        super.init(window: window)

        window.appearance = ViewerTheme.current().appearance
        window.delegate = self
        window.contentView = buildContentView()
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        // Refresh the setting when the user has changed it since this
        // controller was created. A nil appearance follows the system setting.
        applyTheme()
        installEscapeKeyMonitor()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContentView() -> NSView {
        let contentView = NSView()
        contentView.wantsLayer = true
        contentBackgroundLayer = contentView.layer

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let header = buildHeaderView()
        let settingsCard = buildSettingsCard()

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(settingsCard)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            settingsCard.widthAnchor.constraint(equalTo: stack.widthAnchor)
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
        primaryLabels.append(title)

        let subtitle = wrappingLabel("选择双击图片时交给 PicSee 打开的格式，已是 PicSee 默认打开的格式会自动勾选。")
        secondaryLabels.append(subtitle)

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
        cardContent.spacing = 16

        cardContent.addArrangedSubview(buildCardHeaderView(title: "支持的图片格式"))
        cardContent.addArrangedSubview(buildFormatGridView())
        cardContent.addArrangedSubview(buildTipView())
        cardContent.addArrangedSubview(buildSeparatorView())
        cardContent.addArrangedSubview(buildFormatActionsView())

        return insetCard(cardContent, horizontal: 16, vertical: 16)
    }

    private func buildCardHeaderView(title: String = "常用图片格式") -> NSView {
        let row = NSView()

        let sectionTitle = NSTextField(labelWithString: title)
        sectionTitle.font = .boldSystemFont(ofSize: 13)
        secondaryLabels.append(sectionTitle)
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
        let rows = stride(
            from: 0,
            to: DefaultImageAppSettings.formats.count,
            by: Self.formatColumnCount
        ).map { index in
            (0..<Self.formatColumnCount).map {
                formatCell(at: index + $0, hasExistingDefaults: hasExistingDefaults)
            }
        }

        for row in rows {
            grid.addRow(with: row)
        }

        for columnIndex in 0..<grid.numberOfColumns {
            grid.column(at: columnIndex).xPlacement = .fill
            grid.column(at: columnIndex).width = Self.formatColumnWidth
        }

        for rowIndex in 0..<grid.numberOfRows {
            grid.row(at: rowIndex).height = Self.formatRowHeight
        }

        let gridHeight = (Self.formatRowHeight * CGFloat(grid.numberOfRows)) + (grid.rowSpacing * CGFloat(max(grid.numberOfRows - 1, 0)))
        let gridWidth = (Self.formatColumnWidth * CGFloat(grid.numberOfColumns)) + (grid.columnSpacing * CGFloat(max(grid.numberOfColumns - 1, 0)))
        grid.widthAnchor.constraint(equalToConstant: gridWidth).isActive = true
        grid.heightAnchor.constraint(equalToConstant: gridHeight).isActive = true

        let container = NSView()
        container.addSubview(grid)

        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            grid.topAnchor.constraint(equalTo: container.topAnchor),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func formatCell(at index: Int, hasExistingDefaults: Bool) -> NSView {
        guard index < DefaultImageAppSettings.formats.count else {
            return NSView()
        }

        let format = DefaultImageAppSettings.formats[index]
        let button = NSButton(
            checkboxWithTitle: "\(format.label)  \(dottedExtensions(displayExtensions(for: format)))",
            target: nil,
            action: nil
        )
        button.state = (hasExistingDefaults ? handler.isDefaultViewer(for: format) : true) ? .on : .off
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.lineBreakMode = .byTruncatingTail
        button.toolTip = "\(format.label): \(dottedExtensions(format.extensions))"
        checkboxes.append((format, button))

        return button
    }

    private func displayExtensions(for format: DefaultImageFormat) -> String {
        format.label == "RAW" ? "dng, cr2, cr3 等" : format.extensions
    }

    private func buildFormatActionsView() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        let selectAllButton = NSButton(title: "全选", target: self, action: #selector(selectAllFormats(_:)))
        selectAllButton.bezelStyle = .rounded

        let clearButton = NSButton(title: "清除", target: self, action: #selector(clearSelectedFormats(_:)))
        clearButton.bezelStyle = .rounded

        statusLabel.font = .systemFont(ofSize: 12)
        secondaryLabels.append(statusLabel)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let applyButton = NSButton(
            title: "设为默认",
            target: self,
            action: #selector(applySelectedFormats(_:))
        )
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        applyButton.setAccessibilityIdentifier("set-default-image-formats")

        row.addArrangedSubview(selectAllButton)
        row.addArrangedSubview(clearButton)
        row.addArrangedSubview(flexibleSpacer())
        row.addArrangedSubview(statusLabel)
        row.addArrangedSubview(applyButton)
        return row
    }

    private func buildSeparatorView() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    private func dottedExtensions(_ extensions: String) -> String {
        extensions
            .split(separator: ",")
            .map { "." + $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: ", ")
    }

    private func buildTipView() -> NSView {
        let label = wrappingLabel(DefaultImageAppSettings.fallbackInstructions)
        secondaryLabels.append(label)

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
        card.layer?.borderWidth = 1
        if let layer = card.layer {
            cardLayers.append(layer)
        }

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

    private func cardBackgroundColor(for appearance: NSAppearance) -> NSColor {
        var backgroundColor: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            backgroundColor = NSColor.windowBackgroundColor.blended(
                withFraction: 0.35,
                of: .controlBackgroundColor
            ) ?? .windowBackgroundColor
        }
        return backgroundColor ?? .windowBackgroundColor
    }

    private func cgColor(for color: NSColor, appearance: NSAppearance) -> CGColor {
        var resolvedColor: CGColor?
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.cgColor
        }
        return resolvedColor ?? color.cgColor
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

    private func installEscapeKeyMonitor() {
        guard escapeKeyMonitor == nil else { return }

        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard
                event.keyCode == 53,
                event.window === self?.window
            else {
                return event
            }

            self?.window?.performClose(nil)
            return nil
        }
    }

    private func removeEscapeKeyMonitor() {
        guard let escapeKeyMonitor else { return }
        NSEvent.removeMonitor(escapeKeyMonitor)
        self.escapeKeyMonitor = nil
    }

    func windowWillClose(_ notification: Notification) {
        removeEscapeKeyMonitor()
    }

    private func applyTheme() {
        let theme = ViewerTheme.current()
        window?.appearance = theme.appearance
        let appearance = window?.effectiveAppearance ?? NSApp.effectiveAppearance

        contentBackgroundLayer?.backgroundColor = cgColor(for: .windowBackgroundColor, appearance: appearance)
        let cardBackground = cgColor(for: cardBackgroundColor(for: appearance), appearance: appearance)
        let cardBorder = cgColor(for: .separatorColor, appearance: appearance)
        for layer in cardLayers {
            layer.backgroundColor = cardBackground
            layer.borderColor = cardBorder
        }

        let primaryColor: NSColor
        let secondaryColor: NSColor
        switch theme {
        case .dark:
            primaryColor = .white
            secondaryColor = NSColor(calibratedWhite: 0.72, alpha: 1)
        case .light, .system:
            primaryColor = .labelColor
            secondaryColor = .secondaryLabelColor
        }

        primaryLabels.forEach { $0.textColor = primaryColor }
        secondaryLabels.forEach { $0.textColor = secondaryColor }
        for checkbox in checkboxes {
            checkbox.button.attributedTitle = NSAttributedString(
                string: checkbox.button.title,
                attributes: [
                    .font: checkbox.button.font ?? .systemFont(ofSize: 13),
                    .foregroundColor: primaryColor
                ]
            )
        }
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
