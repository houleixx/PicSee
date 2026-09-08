import AppKit

enum ScreenshotExportSizeMode: Int, CaseIterable {
    case selectedSize, imageScale

    var title: String {
        switch self {
        case .selectedSize: "按选择尺寸保存"
        case .imageScale: "按原图尺寸保存"
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
        let scaleText = "（当前显示比例 \(Int((imageDisplayScale * 100).rounded()))%）"
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
        let gridWidth = 76 + 12 + optionsWidth
        setFrameSize(NSSize(width: max(460, gridWidth + 36), height: 80))
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "保存尺寸："), modeButtons[0]],
            [NSGridCell.emptyContentView, modeButtons[1]]
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).width = 76
        grid.column(at: 1).width = optionsWidth
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.yPlacement = .center
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            grid.widthAnchor.constraint(equalToConstant: gridWidth),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10)
        ])
        updateControls()
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
