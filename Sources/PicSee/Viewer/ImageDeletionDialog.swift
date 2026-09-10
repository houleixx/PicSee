import AppKit

@MainActor
final class ImageDeletionDialog: NSPanel {
    let messageText = "将图片移到废纸篓？"
    let filename: String
    let suppressionButton = NSButton(checkboxWithTitle: "以后不再询问", target: nil, action: nil)
    private(set) var buttons: [NSButton] = []

    init(filename: String) {
        self.filename = filename
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 220),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        isReleasedWhenClosed = false
        title = "移到废纸篓"

        let content = NSView()
        contentView = content
        let titleLabel = NSTextField(labelWithString: messageText)
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        let filenameLabel = NSTextField(labelWithString: filename)
        filenameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        filenameLabel.usesSingleLineMode = true
        filenameLabel.lineBreakMode = .byTruncatingMiddle
        filenameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        filenameLabel.toolTip = filename
        filenameLabel.setAccessibilityValue(filename)
        let explanation = NSTextField(wrappingLabelWithString:
            "原文件将移到废纸篓，删除后可撤销。"
        )
        explanation.font = .systemFont(ofSize: 12)
        explanation.textColor = .secondaryLabelColor
        explanation.preferredMaxLayoutWidth = 352
        suppressionButton.state = .off
        suppressionButton.controlSize = .small
        suppressionButton.font = .systemFont(ofSize: 12)

        let cancel = ConfirmationActionButton()
        cancel.cell = ConfirmationActionButtonCell(textCell: "取消")
        cancel.title = "取消"
        cancel.setButtonType(.momentaryPushIn)
        cancel.target = self
        cancel.action = #selector(cancelDeletion(_:))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\r"
        cancel.font = .systemFont(ofSize: 13)
        let trash = ConfirmationActionButton()
        trash.cell = ConfirmationActionButtonCell(textCell: "移到废纸篓")
        trash.title = "移到废纸篓"
        trash.setButtonType(.momentaryPushIn)
        trash.target = self
        trash.action = #selector(confirmDeletion(_:))
        trash.bezelStyle = .rounded
        trash.font = .systemFont(ofSize: 13)
        trash.hasDestructiveAction = true
        buttons = [cancel, trash]

        let buttonRow = NSStackView(views: buttons)
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.distribution = .fillEqually
        let textStack = NSStackView(views: [titleLabel, filenameLabel, explanation, suppressionButton])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 8
        textStack.setCustomSpacing(16, after: explanation)
        for view in [textStack, buttonRow] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            textStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            textStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            titleLabel.widthAnchor.constraint(equalTo: textStack.widthAnchor),
            filenameLabel.widthAnchor.constraint(equalTo: textStack.widthAnchor),
            explanation.widthAnchor.constraint(equalTo: textStack.widthAnchor),
            buttonRow.topAnchor.constraint(equalTo: textStack.bottomAnchor, constant: 16),
            buttonRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            buttonRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            cancel.widthAnchor.constraint(equalToConstant: 104),
            trash.widthAnchor.constraint(equalToConstant: 104),
            cancel.heightAnchor.constraint(equalToConstant: 32),
            trash.heightAnchor.constraint(equalToConstant: 32)
        ])
        // Explicit sizing keeps both actions on the same row, including long filenames.
        let explanationHeight = explanation.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 352, height: 80)).height ?? 32
        let height = 24 + titleLabel.intrinsicContentSize.height + 8
            + filenameLabel.intrinsicContentSize.height + 8 + explanationHeight + 16
            + suppressionButton.intrinsicContentSize.height + 16 + 32 + 20
        setContentSize(NSSize(width: 400, height: ceil(height)))
        defaultButtonCell = cancel.cell as? NSButtonCell
        initialFirstResponder = cancel
    }

    @objc private func cancelDeletion(_ sender: Any?) {
        sheetParent?.endSheet(self, returnCode: .alertFirstButtonReturn)
    }

    @objc private func confirmDeletion(_ sender: Any?) {
        sheetParent?.endSheet(self, returnCode: .alertSecondButtonReturn)
    }
}

private final class ConfirmationActionButton: NSButton {
    // The custom bezel fills the control itself; native rounded-button alignment
    // insets would enlarge its frame beyond the width and height constraints.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
}

private final class ConfirmationActionButtonCell: NSButtonCell {
    private func bezelPath(in frame: NSRect) -> NSBezierPath {
        NSBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 2), xRadius: 6, yRadius: 6)
    }

    override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
        let isDefault = controlView.window?.defaultButtonCell === self
        let baseColor = isDefault ? NSColor.controlAccentColor : NSColor.controlColor
        let fillColor = isEnabled ? baseColor : baseColor.withAlphaComponent(0.5)
        fillColor.setFill()
        // AppKit may pass an expanded native bezel frame. Use the control's
        // actual bounds so the visible shape cannot consume the inter-button gap.
        let path = bezelPath(in: controlView.bounds)
        path.fill()
        if isHighlighted {
            NSColor.black.withAlphaComponent(0.12).setFill()
            path.fill()
        }
        NSColor.labelColor.withAlphaComponent(0.1).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    override func drawFocusRingMask(withFrame frame: NSRect, in controlView: NSView) {
        bezelPath(in: controlView.bounds).fill()
    }

    override func focusRingMaskBounds(forFrame frame: NSRect, in controlView: NSView) -> NSRect {
        controlView.bounds.insetBy(dx: 1, dy: 2)
    }

    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        let isDefault = controlView.window?.defaultButtonCell === self
        let textColor = isDefault ? NSColor.white : NSColor.systemRed
        let coloredTitle = NSMutableAttributedString(attributedString: title)
        coloredTitle.addAttribute(
            .foregroundColor, value: isEnabled ? textColor : NSColor.disabledControlTextColor,
            range: NSRange(location: 0, length: coloredTitle.length)
        )
        // Center the measured text in our visible bezel instead of using the
        // title frame computed for AppKit's thinner native rounded button.
        let bezelBounds = controlView.bounds.insetBy(dx: 1, dy: 2)
        let titleSize = coloredTitle.size()
        let titleFrame = NSRect(
            x: bezelBounds.midX - titleSize.width / 2,
            y: bezelBounds.midY - titleSize.height / 2,
            width: titleSize.width,
            height: titleSize.height
        )
        coloredTitle.draw(in: titleFrame)
        return titleFrame
    }
}
