import AppKit

/// Native file-association form embedded in the unified settings window.
@MainActor
final class DefaultImageAppSettingsViewController: NSViewController {
    private static let formatRowHeight: CGFloat = 33
    private static let formatColumnCount = 3
    private static let formatColumnWidth: CGFloat = 203
    private static let extensionSpacing: CGFloat = 6
    private static let optionLeadingInset: CGFloat = 15

    private let handler: DefaultImageAppHandling
    private var checkboxes: [(format: DefaultImageFormat, button: NSButton)] = []
    private var primaryLabels: [NSTextField] = []
    private var secondaryLabels: [NSTextField] = []
    private weak var contentBackgroundLayer: CALayer?
    private var cardLayers: [CALayer] = []
    private let statusLabel = NSTextField(labelWithString: "")

    init(handler: DefaultImageAppHandling) {
        self.handler = handler
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = buildContentView()
    }

    private func buildContentView() -> NSView {
        let contentView = NSView()
        contentView.wantsLayer = true
        contentBackgroundLayer = contentView.layer

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let header = buildHeaderView()
        let settingsCard = buildSettingsCard()
        let footer = buildFooterView()

        stack.addArrangedSubview(header)
        stack.setCustomSpacing(20, after: header)
        stack.addArrangedSubview(settingsCard)
        stack.addArrangedSubview(footer)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            settingsCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        return contentView
    }

    private func buildHeaderView() -> NSView {
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 16

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 8

        let title = NSTextField(labelWithString: "默认图片打开方式")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
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
        cardContent.spacing = 12

        let header = buildCardHeaderView(title: "支持的图片格式")
        cardContent.addArrangedSubview(header)
        cardContent.addArrangedSubview(buildFormatGridView())

        return insetCard(cardContent, horizontal: 18, vertical: 18)
    }

    private func buildFooterView() -> NSView {
        let footer = NSStackView()
        footer.orientation = .vertical
        footer.alignment = .width
        footer.spacing = 14
        let tip = buildTipView()
        footer.addArrangedSubview(tip)
        tip.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true
        footer.addArrangedSubview(buildSeparatorView())
        footer.addArrangedSubview(buildFormatActionsView())
        return footer
    }

    private func buildCardHeaderView(title: String = "常用图片格式") -> NSView {
        let row = NSView()

        let sectionTitle = NSTextField(labelWithString: title)
        sectionTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        primaryLabels.append(sectionTitle)
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
        grid.columnSpacing = 12

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
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
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
        button.controlSize = .small
        button.font = .systemFont(ofSize: 13, weight: .medium)
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
        label.font = .systemFont(ofSize: 11)
        label.alignment = .left
        secondaryLabels.append(label)

        let tip = insetView(label, horizontal: 0, vertical: 0)

        NSLayoutConstraint.activate([
            tip.widthAnchor.constraint(greaterThanOrEqualToConstant: 1)
        ])

        return tip
    }

    private func insetCard(_ content: NSView, horizontal: CGFloat, vertical: CGFloat) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 0.5
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
                withFraction: 0.035,
                of: .labelColor
            ) ?? .windowBackgroundColor
        }
        return backgroundColor ?? .windowBackgroundColor
    }

    private func cgColor(for color: NSColor, appearance: NSAppearance, alpha: CGFloat? = nil) -> CGColor {
        var resolvedColor: CGColor?
        appearance.performAsCurrentDrawingAppearance {
            // Adding alpha resolves semantic colors immediately, so do it
            // inside the target appearance rather than the system appearance.
            resolvedColor = (alpha.map { color.withAlphaComponent($0) } ?? color).cgColor
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
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        return label
    }

    private func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    func applyTheme(_ theme: ViewerTheme) {
        view.appearance = theme.appearance
        let appearance = view.effectiveAppearance

        contentBackgroundLayer?.backgroundColor = cgColor(for: .windowBackgroundColor, appearance: appearance)
        let cardBackground = cgColor(for: cardBackgroundColor(for: appearance), appearance: appearance)
        let cardBorder = cgColor(for: .labelColor, appearance: appearance, alpha: 0.10)
        for layer in cardLayers {
            layer.backgroundColor = cardBackground
            layer.borderColor = cardBorder
        }

        let primaryColor = NSColor.labelColor
        let secondaryColor = NSColor.secondaryLabelColor

        primaryLabels.forEach { $0.textColor = primaryColor }
        secondaryLabels.forEach { $0.textColor = secondaryColor }
        let extensionFont = NSFont.systemFont(ofSize: 12)
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: extensionFont]).width
        for checkbox in checkboxes {
            let title = NSMutableAttributedString(
                string: checkbox.format.label,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: primaryColor
                ]
            )
            // Use a measured six-point gap while keeping the whole label clickable.
            title.append(NSAttributedString(
                string: " ",
                attributes: [
                    .font: extensionFont,
                    .kern: Self.extensionSpacing - spaceWidth
                ]
            ))
            title.append(NSAttributedString(
                string: dottedExtensions(displayExtensions(for: checkbox.format)),
                attributes: [
                    .font: extensionFont,
                    .foregroundColor: secondaryColor
                ]
            ))
            checkbox.button.attributedTitle = title
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

        let result = DefaultImageAppSettings.apply(selectedFormats, using: handler)
        statusLabel.stringValue = result.statusMessage
        for checkbox in checkboxes {
            checkbox.button.state = handler.isDefaultViewer(for: checkbox.format) ? .on : .off
        }
        if !result.failures.isEmpty {
            Self.makeFailureAlert(for: result).runModal()
        }
    }

    static func makeFailureAlert(for result: DefaultImageAppApplyResult) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = result.completed.isEmpty ? "设置默认打开方式失败" : "部分格式设置失败"
        alert.informativeText = result.statusMessage + "\n\n" + result.failureDetails
            + "\n\n可在 Finder 的“显示简介”→“打开方式”中选择 PicSee，并点“全部更改…”。"
        alert.addButton(withTitle: "好")
        return alert
    }
}
