import AppKit

enum ScreenshotExportSizeMode: Int, CaseIterable {
    case selectedSize, imageScale

    var title: String {
        switch self {
        case .selectedSize: L10n.text("按选择尺寸保存")
        case .imageScale: L10n.text("按原图尺寸保存")
        }
    }

    static func validDisplayScale(_ scale: CGFloat) -> CGFloat {
        scale.isFinite && scale > 0 ? scale : 1
    }

    /// Original image pixels to physical screen pixels, including Retina backing scale.
    static func displayPixelScale(imageDisplayScale: CGFloat, screenScale: CGFloat) -> CGFloat {
        validDisplayScale(imageDisplayScale) * validDisplayScale(screenScale)
    }

    func pixelSize(sourceSize: CGSize, displayScale: CGFloat) -> CGSize {
        let factor: CGFloat = self == .selectedSize ? Self.validDisplayScale(displayScale) : 1
        return CGSize(width: max(1, (sourceSize.width * factor).rounded()),
                      height: max(1, (sourceSize.height * factor).rounded()))
    }
}

@MainActor
final class ScreenshotExportAccessoryView: NSView {
    private let sourceSize: CGSize
    private let displayScale: CGFloat
    private var modeButtons: [NSButton] = []

    var selectedMode: ScreenshotExportSizeMode = .selectedSize {
        didSet { updateControls() }
    }

    init(sourceSize: CGSize, displayScale: CGFloat, screenScale: CGFloat = 1) {
        self.sourceSize = sourceSize
        self.displayScale = displayScale
        super.init(frame: CGRect(x: 0, y: 0, width: 460, height: 80))
        autoresizingMask = [.width]
        let imageDisplayScale = ScreenshotExportSizeMode.validDisplayScale(displayScale)
            / ScreenshotExportSizeMode.validDisplayScale(screenScale)
        let scaleText = L10n.text("（当前显示比例 %1$@%）", String(describing: Int((imageDisplayScale * 100).rounded())))
        modeButtons = ScreenshotExportSizeMode.allCases.map { mode in
            let size = mode.pixelSize(sourceSize: sourceSize, displayScale: displayScale)
            let title = "\(mode.title) · \(Int(size.width)) × \(Int(size.height)) px"
                + (mode == .imageScale ? scaleText : "")
            let button = NSButton(radioButtonWithTitle: title, target: self, action: #selector(optionsChanged(_:)))
            button.tag = mode.rawValue
            button.setAccessibilityLabel(title)
            return button
        }
        let optionsWidth = max(328, ceil(modeButtons.map { $0.intrinsicContentSize.width }.max() ?? 328))
        let gridWidth = 90 + 12 + optionsWidth
        setFrameSize(NSSize(width: max(460, gridWidth + 36), height: 80))
        let sizeLabel = NSTextField(labelWithString: L10n.text("保存尺寸："))
        let grid = NSGridView(views: [
            [sizeLabel, modeButtons[0]],
            [NSGridCell.emptyContentView, modeButtons[1]]
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).width = 90
        grid.column(at: 1).width = optionsWidth
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.yPlacement = .center
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            grid.widthAnchor.constraint(greaterThanOrEqualToConstant: gridWidth),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10)
        ])
        updateControls()
        LanguageSettings.bind(self) { accessory in
            sizeLabel.stringValue = L10n.text("保存尺寸：")
            for (button, mode) in zip(accessory.modeButtons, ScreenshotExportSizeMode.allCases) {
                let size = mode.pixelSize(sourceSize: sourceSize, displayScale: displayScale)
                button.title = "\(mode.title) · \(Int(size.width)) × \(Int(size.height)) px"
                    + (mode == .imageScale ? L10n.text("（当前显示比例 %1$@%）", String(Int((imageDisplayScale * 100).rounded()))) : "")
                button.setAccessibilityLabel(button.title)
            }
            grid.column(at: 1).width = max(328, ceil(accessory.modeButtons.map { $0.intrinsicContentSize.width }.max() ?? 328))
            accessory.setFrameSize(NSSize(width: max(460, 90 + 12 + grid.column(at: 1).width + 36), height: 80))
        }
    }

    required init?(coder: NSCoder) { nil }

    var exportOptions: ImageExportOptions {
        ImageExportOptions(format: .png, pixelSize: selectedMode.pixelSize(
            sourceSize: sourceSize, displayScale: displayScale))
    }

    @objc private func optionsChanged(_ sender: NSButton) {
        guard let mode = ScreenshotExportSizeMode(rawValue: sender.tag) else { return }
        selectedMode = mode
    }

    private func updateControls() {
        for button in modeButtons {
            button.state = button.tag == selectedMode.rawValue ? .on : .off
        }
    }
}
