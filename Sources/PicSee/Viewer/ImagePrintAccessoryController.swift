import AppKit

/// Uses the system print panel's accessory section, so the surrounding panel follows macOS.
@MainActor
final class ImagePrintAccessoryController: NSViewController, NSPrintPanelAccessorizing, NSTextFieldDelegate {
    private let initialPrintInfo: NSPrintInfo
    private let imageSize: CGSize
    private var paperObservations: [NSKeyValueObservation] = []
    @objc dynamic private(set) var previewRevision = 0
    private var automaticRotation: NSButton!
    private var scaleButton: NSButton!
    private var fitButton: NSButton!
    private var entireImage: NSButton!
    private var fillPaper: NSButton!
    private var scaleField: NSTextField!
    private var copies: NSPopUpButton!

    private var printInfo: NSPrintInfo { representedObject as? NSPrintInfo ?? initialPrintInfo }
    var settings: ImagePrintSettings { ImagePrintSettings(printInfo: printInfo) }

    init(printInfo: NSPrintInfo, imageSize: CGSize) {
        initialPrintInfo = printInfo
        self.imageSize = imageSize
        super.init(nibName: nil, bundle: nil)
        title = L10n.text("预览")
    }

    required init?(coder: NSCoder) { nil }

    override var representedObject: Any? {
        didSet {
            func observe<Value>(_ keyPath: KeyPath<NSPrintInfo, Value>) -> NSKeyValueObservation {
                printInfo.observe(keyPath) { [weak self] _, _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        ImagePrinter.useImagePageMargins(in: self.printInfo)
                        if self.isViewLoaded { self.refreshControls() }
                    }
                }
            }
            paperObservations = [observe(\.paperSize), observe(\.orientation), observe(\.printer)]
            if isViewLoaded { refreshControls() }
        }
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 190))
        func button(_ title: String, _ type: NSButton.ButtonType, _ rect: NSRect, tag: Int) -> NSButton {
            let button = NSButton(title: title, target: self, action: #selector(changeOption(_:)))
            button.setButtonType(type)
            button.tag = tag
            button.frame = rect
            view.addSubview(button)
            return button
        }
        automaticRotation = button(L10n.text("自动旋转"), .switch, NSRect(x: 16, y: 153, width: 200, height: 24), tag: 0)
        scaleButton = button(L10n.text("缩放："), .radio, NSRect(x: 16, y: 119, width: 200, height: 24), tag: 1)
        fitButton = button(L10n.text("缩放以适合："), .radio, NSRect(x: 16, y: 93, width: 200, height: 24), tag: 2)
        entireImage = button(L10n.text("打印整个图像"), .radio, NSRect(x: 230, y: 93, width: 214, height: 24), tag: 3)
        fillPaper = button(L10n.text("填满纸张"), .radio, NSRect(x: 230, y: 67, width: 214, height: 24), tag: 4)
        // AppKit groups sibling radio buttons automatically. These are two independent groups.
        for (buttons, frame) in [([scaleButton!, fitButton!], NSRect(x: 16, y: 93, width: 210, height: 50)),
                                 ([entireImage!, fillPaper!], NSRect(x: 230, y: 67, width: 214, height: 50))] {
            let group = NSView(frame: frame)
            view.addSubview(group)
            for button in buttons {
                let origin = button.frame.origin
                button.removeFromSuperview()
                button.setFrameOrigin(NSPoint(x: origin.x - frame.minX, y: origin.y - frame.minY))
                group.addSubview(button)
            }
        }
        scaleField = NSTextField(frame: NSRect(x: 230, y: 120, width: 90, height: 22))
        scaleField.delegate = self
        scaleField.target = self
        scaleField.action = #selector(changeScale(_:))
        scaleField.setAccessibilityLabel(L10n.text("缩放百分比"))
        view.addSubview(scaleField)
        let copiesLabel = NSTextField(labelWithString: L10n.text("每页份数："))
        copiesLabel.frame = NSRect(x: 16, y: 22, width: 200, height: 22)
        view.addSubview(copiesLabel)
        copies = NSPopUpButton(frame: NSRect(x: 227, y: 19, width: 140, height: 26), pullsDown: false)
        copies.addItems(withTitles: (1...16).map(String.init))
        copies.target = self
        copies.action = #selector(changeCopies(_:))
        copies.setAccessibilityLabel(L10n.text("每页份数："))
        view.addSubview(copies)
        refreshControls()
    }

    func updateSettings(_ settings: ImagePrintSettings, preservingScaleInput: Bool = false) {
        var settings = settings
        if settings.sizing != .scale { settings.fillsPaperWhenFitting = settings.sizing == .fill }
        willChangeValue(forKey: "localizedSummaryItems")
        settings.store(in: printInfo)
        if isViewLoaded { refreshControls(updateScaleText: !preservingScaleInput) }
        previewRevision += 1
        didChangeValue(forKey: "localizedSummaryItems")
    }

    private func refreshControls(updateScaleText: Bool = true) {
        let settings = settings
        automaticRotation.state = settings.automaticallyRotates ? .on : .off
        scaleButton.state = settings.sizing == .scale ? .on : .off
        fitButton.state = settings.sizing == .scale ? .off : .on
        let fillsPaper = settings.sizing == .fill || (settings.sizing == .scale && settings.fillsPaperWhenFitting)
        entireImage.state = fillsPaper ? .off : .on
        fillPaper.state = fillsPaper ? .on : .off
        scaleField.isEnabled = settings.sizing == .scale
        let percent: Double
        if settings.sizing == .scale {
            percent = settings.scalePercent
        } else {
            let page = CGSize(width: max(1, printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin),
                              height: max(1, printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin))
            let placement = ImagePrintLayout(imageSize: imageSize, pageSize: page, settings: settings).placements.first
            percent = placement.map { Double($0.imageRect.width / ($0.rotates ? imageSize.height : imageSize.width)) * 100 } ?? 100
        }
        if updateScaleText {
            scaleField.stringValue = percent.formatted(.number.precision(.fractionLength(0...2))) + "%"
        }
        entireImage.isEnabled = settings.sizing != .scale
        fillPaper.isEnabled = settings.sizing != .scale
        copies.selectItem(at: settings.copiesPerPage - 1)
    }

    @objc private func changeOption(_ sender: NSButton) {
        var settings = settings
        switch sender.tag {
        case 0: settings.automaticallyRotates = sender.state == .on
        case 1:
            if settings.sizing != .scale {
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                let text = scaleField.stringValue.replacingOccurrences(of: "%", with: "")
                let percent = formatter.number(from: text)?.doubleValue ?? 100
                settings.scalePercent = min(10000, max(1, percent))
            }
            settings.sizing = .scale
        case 2: settings.sizing = settings.fillsPaperWhenFitting ? .fill : .fit
        case 3: settings.sizing = .fit
        case 4: settings.sizing = .fill
        default: return
        }
        updateSettings(settings)
    }

    @objc private func changeScale(_ sender: NSTextField) { commitScale() }
    func controlTextDidEndEditing(_ obj: Notification) { commitScale() }

    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as? NSTextField === scaleField,
              settings.sizing == .scale,
              (scaleField.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        commitScale(isFinal: false)
    }

    private func commitScale(isFinal: Bool = true) {
        let text = scaleField.stringValue.replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        guard let value = formatter.number(from: text)?.doubleValue, value.isFinite, value >= 1, value <= 10000 else {
            // Empty and incomplete input is expected while typing. Keep the last valid preview.
            if isFinal {
                NSSound.beep()
                refreshControls()
            }
            return
        }
        var settings = settings
        settings.scalePercent = value
        if settings != self.settings {
            updateSettings(settings, preservingScaleInput: !isFinal)
        } else if isFinal {
            refreshControls()
        }
    }

    @objc private func changeCopies(_ sender: NSPopUpButton) {
        var settings = settings
        settings.copiesPerPage = sender.indexOfSelectedItem + 1
        updateSettings(settings)
    }

    func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        let settings = settings
        let sizing: String
        switch settings.sizing {
        case .scale: sizing = settings.scalePercent.formatted() + "%"
        case .fit: sizing = L10n.text("打印整个图像")
        case .fill: sizing = L10n.text("填满纸张")
        }
        return [
            [.itemName: L10n.text("自动旋转"), .itemDescription: settings.automaticallyRotates ? L10n.text("开") : L10n.text("关")],
            [.itemName: L10n.text("缩放："), .itemDescription: sizing],
            [.itemName: L10n.text("每页份数："), .itemDescription: String(settings.copiesPerPage)]
        ]
    }

    func keyPathsForValuesAffectingPreview() -> Set<String> {
        ["previewRevision", "representedObject", "representedObject.paperSize", "representedObject.orientation",
         "representedObject.leftMargin", "representedObject.rightMargin",
         "representedObject.topMargin", "representedObject.bottomMargin"]
    }
}
