import AppKit

enum ScreenshotExportSizeMode: Int, CaseIterable {
    case selectedSize, imageScale

    var title: String {
        switch self {
        case .selectedSize: "按选中大小保存"
        case .imageScale: "原图比较保存"
        }
    }

    func scaleFactor(displayScale: CGFloat) -> CGFloat {
        guard self == .imageScale, displayScale.isFinite, displayScale > 0 else { return 1 }
        return 1 / displayScale
    }

    func pixelSize(sourceSize: CGSize, displayScale: CGFloat) -> CGSize {
        let factor = scaleFactor(displayScale: displayScale)
        return CGSize(width: max(1, (sourceSize.width * factor).rounded()),
                      height: max(1, (sourceSize.height * factor).rounded()))
    }
}

@MainActor
final class ScreenshotExportAccessoryView: NSView {
    private let sourceSize: CGSize
    private let displayScale: CGFloat
    private let modePopup = NSPopUpButton()
    private let selectionLabel = NSTextField(labelWithString: "")
    private let factorLabel = NSTextField(labelWithString: "")
    private let outputLabel = NSTextField(labelWithString: "")
    private var gridView: NSGridView?

    init(sourceSize: CGSize, displayScale: CGFloat) {
        self.sourceSize = sourceSize
        self.displayScale = displayScale
        super.init(frame: CGRect(x: 0, y: 0, width: 460, height: 136))
        autoresizingMask = [.width]
        modePopup.addItems(withTitles: ScreenshotExportSizeMode.allCases.map(\.title))
        modePopup.target = self
        modePopup.action = #selector(optionsChanged(_:))
        modePopup.setAccessibilityLabel("截图保存尺寸模式")
        factorLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        selectionLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        outputLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "保存尺寸："), modePopup],
            [NSTextField(labelWithString: "选中大小："), selectionLabel],
            [NSTextField(labelWithString: "缩放系数："), factorLabel],
            [NSTextField(labelWithString: "输出像素："), outputLabel]
        ])
        gridView = grid
        grid.rowSpacing = 9
        grid.columnSpacing = 12
        grid.column(at: 0).width = 76
        grid.column(at: 1).width = 240
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            grid.widthAnchor.constraint(equalToConstant: 328),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),
            modePopup.widthAnchor.constraint(equalToConstant: 240)
        ])
        updateControls()
    }

    required init?(coder: NSCoder) { nil }

    var selectedMode: ScreenshotExportSizeMode {
        get { ScreenshotExportSizeMode(rawValue: modePopup.indexOfSelectedItem) ?? .selectedSize }
        set {
            modePopup.selectItem(at: newValue.rawValue)
            updateControls()
        }
    }

    var exportOptions: ImageExportOptions {
        ImageExportOptions(format: .png, pixelSize: selectedMode.pixelSize(
            sourceSize: sourceSize, displayScale: displayScale))
    }

    @objc private func optionsChanged(_ sender: Any?) { updateControls() }

    private func updateControls() {
        let factor = selectedMode.scaleFactor(displayScale: displayScale)
        selectionLabel.stringValue = "宽：\(Int(sourceSize.width)) × 高：\(Int(sourceSize.height)) px"
        factorLabel.stringValue = String(format: "%.3g ×（%.3g%%）", Double(factor), Double(factor * 100))
        let size = exportOptions.pixelSize ?? sourceSize
        outputLabel.stringValue = "宽：\(Int(size.width)) × 高：\(Int(size.height)) px"
        gridView?.row(at: 2).isHidden = selectedMode == .selectedSize
        setFrameSize(NSSize(width: frame.width, height: selectedMode == .selectedSize ? 108 : 136))
    }
}
