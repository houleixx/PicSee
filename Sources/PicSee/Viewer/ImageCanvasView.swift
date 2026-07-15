import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import Vision
@preconcurrency import VisionKit

struct ImageCanvasView: NSViewRepresentable {
    let image: NSImage
    let imageURL: URL
    @Binding var zoomScale: CGFloat
    @Binding var panOffset: CGSize
    @Binding var rotationDegrees: Int
    @Binding var zoomRequest: ImageZoomRequest?
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onReset: () -> Void
    let onClose: () -> Void
    let onZoomRequestHandled: (Int) -> Void
    let onDisplayScaleChanged: (CGFloat) -> Void
    let titleBarVisible: Bool
    let fileInfoVisible: Bool
    let toolbarVisible: Bool
    let imageParametersVisible: Bool
    let onTitleBarVisibilityChanged: (Bool) -> Void
    let onFileInfoVisibilityChanged: (Bool) -> Void
    let onToolbarVisibilityChanged: (Bool) -> Void
    let onImageParametersVisibilityChanged: (Bool) -> Void
    let fixedWindowEnabled: Bool
    let onFixedWindowChanged: (Bool) -> Void
    let onCheckForUpdates: (() -> Void)?

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        view.imageURL = imageURL
        view.image = image
        view.titleBarVisible = titleBarVisible
        view.fileInfoVisible = fileInfoVisible
        view.toolbarVisible = toolbarVisible
        view.imageParametersVisible = imageParametersVisible
        view.fixedWindowEnabled = fixedWindowEnabled
        view.rotationDegrees = rotationDegrees
        view.onPrevious = onPrevious
        view.onNext = onNext
        view.onReset = onReset
        view.onClose = onClose
        view.onZoomRequestHandled = onZoomRequestHandled
        view.onDisplayScaleChanged = onDisplayScaleChanged
        view.onZoomChanged = { zoomScale = $0 }
        view.onPanChanged = { panOffset = $0 }
        view.onTitleBarVisibilityChanged = onTitleBarVisibilityChanged
        view.onFileInfoVisibilityChanged = onFileInfoVisibilityChanged
        view.onToolbarVisibilityChanged = onToolbarVisibilityChanged
        view.onImageParametersVisibilityChanged = onImageParametersVisibilityChanged
        view.onFixedWindowChanged = onFixedWindowChanged
        view.onCheckForUpdates = onCheckForUpdates
        return view
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.imageURL = imageURL
        nsView.image = image
        nsView.zoomScale = zoomScale
        nsView.panOffset = panOffset
        nsView.rotationDegrees = rotationDegrees
        nsView.onPrevious = onPrevious
        nsView.onNext = onNext
        nsView.onReset = onReset
        nsView.onClose = onClose
        nsView.onZoomRequestHandled = onZoomRequestHandled
        nsView.onDisplayScaleChanged = onDisplayScaleChanged
        nsView.titleBarVisible = titleBarVisible
        nsView.fileInfoVisible = fileInfoVisible
        nsView.toolbarVisible = toolbarVisible
        nsView.imageParametersVisible = imageParametersVisible
        nsView.fixedWindowEnabled = fixedWindowEnabled
        nsView.onTitleBarVisibilityChanged = onTitleBarVisibilityChanged
        nsView.onFileInfoVisibilityChanged = onFileInfoVisibilityChanged
        nsView.onToolbarVisibilityChanged = onToolbarVisibilityChanged
        nsView.onImageParametersVisibilityChanged = onImageParametersVisibilityChanged
        nsView.onFixedWindowChanged = onFixedWindowChanged
        nsView.onCheckForUpdates = onCheckForUpdates
        if let zoomRequest {
            nsView.applyToolbarZoom(request: zoomRequest)
        }
        nsView.needsDisplay = true
    }
}

private struct RecognizedTextFragment {
    let text: String
    let boundingBox: CGRect
    let lineIndex: Int
    let fragmentIndex: Int
}

private struct RecognizedTextLine {
    let text: String
    let boundingBox: CGRect
    let fragments: [RecognizedTextFragment]
}

private struct RecognizedObservationLine {
    let text: String
    let boundingBox: CGRect
    let candidate: VNRecognizedText
}

private struct FragmentLocation: Comparable, Hashable {
    let lineIndex: Int
    let fragmentIndex: Int

    static func < (lhs: FragmentLocation, rhs: FragmentLocation) -> Bool {
        if lhs.lineIndex != rhs.lineIndex {
            return lhs.lineIndex < rhs.lineIndex
        }
        return lhs.fragmentIndex < rhs.fragmentIndex
    }
}

private final class SelectionOverlayView: NSView {
    var selectionRects: [CGRect] = [] {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !selectionRects.isEmpty else { return }

        for rect in selectionRects {
            let rounded = NSBezierPath(roundedRect: rect.insetBy(dx: -1.5, dy: -1), xRadius: 3, yRadius: 3)
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.28).setFill()
            rounded.fill()
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.55).setStroke()
            rounded.lineWidth = 1
            rounded.stroke()
        }
    }
}

private final class ImageMinimapView: NSView {
    static let contentInset: CGFloat = 5

    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    var minimapGeometry: MinimapGeometry? {
        didSet { needsDisplay = true }
    }

    var onNavigate: ((CGPoint) -> Void)?

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, let minimapGeometry else { return }

        let contentRect = bounds.insetBy(dx: Self.contentInset, dy: Self.contentInset)
        let imagePath = NSBezierPath(roundedRect: contentRect, xRadius: 5, yRadius: 5)

        NSGraphicsContext.current?.saveGraphicsState()
        imagePath.addClip()
        NSColor.white.withAlphaComponent(0.08).setFill()
        contentRect.fill()
        image.draw(in: contentRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.current?.restoreGraphicsState()

        NSColor(calibratedWhite: 0.38, alpha: 0.95).setStroke()
        imagePath.lineWidth = 1
        imagePath.stroke()

        let visibleRect = minimapGeometry.visibleRect.offsetBy(dx: Self.contentInset, dy: Self.contentInset)
        let visiblePath = NSBezierPath(roundedRect: visibleRect, xRadius: 3, yRadius: 3)
        NSColor.black.withAlphaComponent(0.12).setFill()
        visiblePath.fill()
        NSColor.white.withAlphaComponent(0.95).setStroke()
        visiblePath.lineWidth = 1
        visiblePath.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        navigate(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        navigate(with: event)
    }

    private func navigate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let contentRect = bounds.insetBy(dx: Self.contentInset, dy: Self.contentInset)
        onNavigate?(
            CGPoint(
                x: min(max(point.x - contentRect.minX, 0), contentRect.width),
                y: min(max(point.y - contentRect.minY, 0), contentRect.height)
            )
        )
    }
}

final class ImageExportAccessoryView: NSView {
    private static let labelColumnWidth: CGFloat = 76
    private static let controlColumnWidth: CGFloat = 150
    private static let sizeFieldWidth: CGFloat = controlColumnWidth

    private enum ResizeMode: Int {
        case fixed
        case proportionalWidth
        case proportionalHeight
    }

    private let formatPopup = NSPopUpButton()
    private let resizeModePopup = NSPopUpButton()
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let qualitySlider = NSSlider(value: 0.9, minValue: 0.4, maxValue: 1.0, target: nil, action: nil)
    private let defaultPixelSize: CGSize?
    private var labels: [NSTextField] = []
    private var qualityLabel: NSTextField?
    private var gridView: NSGridView?
    private var gridLeadingConstraint: NSLayoutConstraint?
    private var pixelUnitLabels: [NSTextField] = []
    private var pixelInputStacks: [NSStackView] = []
    var onFormatChanged: ((ImageExportFormat) -> Void)?

    init(defaultPixelSize: CGSize?) {
        self.defaultPixelSize = defaultPixelSize
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 190))
        formatPopup.addItems(withTitles: ["JPEG", "PNG"])
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged(_:))
        resizeModePopup.addItems(withTitles: ["固定尺寸", "按宽等比", "按高等比"])
        resizeModePopup.target = self
        resizeModePopup.action = #selector(resizeModeChanged(_:))

        widthField.placeholderString = "宽"
        heightField.placeholderString = "高"
        widthField.target = self
        widthField.action = #selector(sizeFieldChanged(_:))
        heightField.target = self
        heightField.action = #selector(sizeFieldChanged(_:))
        widthField.delegate = self
        heightField.delegate = self
        if let defaultPixelSize {
            widthField.stringValue = "\(Int(defaultPixelSize.width.rounded()))"
            heightField.stringValue = "\(Int(defaultPixelSize.height.rounded()))"
        }

        let labels = ["格式:", "尺寸模式:", "宽度:", "高度:", "JPEG 质量:"].map(Self.label)
        self.labels = labels
        let widthInput = Self.pixelInput(field: widthField)
        let heightInput = Self.pixelInput(field: heightField)
        pixelInputStacks = [widthInput, heightInput]
        pixelUnitLabels = [widthInput, heightInput].compactMap { $0.views.last as? NSTextField }
        let grid = NSGridView(views: [
            [labels[0], formatPopup],
            [labels[1], resizeModePopup],
            [labels[2], widthInput],
            [labels[3], heightInput],
            [labels[4], qualitySlider]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        gridView = grid
        qualityLabel = labels[4]
        addSubview(grid)

        let gridLeadingConstraint = grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 38)
        self.gridLeadingConstraint = gridLeadingConstraint
        NSLayoutConstraint.activate([
            gridLeadingConstraint,
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
            formatPopup.widthAnchor.constraint(equalToConstant: Self.controlColumnWidth),
            resizeModePopup.widthAnchor.constraint(equalToConstant: Self.controlColumnWidth),
            widthField.widthAnchor.constraint(equalToConstant: Self.sizeFieldWidth),
            heightField.widthAnchor.constraint(equalTo: widthField.widthAnchor)
        ] + labels.map { $0.widthAnchor.constraint(equalToConstant: Self.labelColumnWidth) })
        updateFormatControls()
        updateResizeControls()
    }

    required init?(coder: NSCoder) {
        nil
    }

    var exportOptions: ImageExportOptions {
        ImageExportOptions(format: selectedFormat, pixelSize: selectedPixelSize)
    }

    var selectedFormat: ImageExportFormat {
        formatPopup.indexOfSelectedItem == 1 ? .png : .jpeg(quality: CGFloat(qualitySlider.doubleValue))
    }

    @objc private func formatChanged(_ sender: Any?) {
        updateFormatControls()
        onFormatChanged?(selectedFormat)
    }

    @objc private func resizeModeChanged(_ sender: Any?) {
        updateResizeControls()
        updateProportionalSize(changedField: nil)
    }

    @objc private func sizeFieldChanged(_ sender: Any?) {
        updateProportionalSize(changedField: sender as? NSTextField)
    }

    private func updateFormatControls() {
        let showQualityControls: Bool
        if case .png = selectedFormat {
            showQualityControls = false
        } else {
            showQualityControls = true
        }

        qualityLabel?.alphaValue = showQualityControls ? 1 : 0
        qualitySlider.alphaValue = showQualityControls ? 1 : 0
        qualitySlider.isEnabled = showQualityControls
    }

    private func updateResizeControls() {
        switch selectedResizeMode {
        case .fixed:
            widthField.isEnabled = true
            heightField.isEnabled = true
        case .proportionalWidth:
            widthField.isEnabled = true
            heightField.isEnabled = false
        case .proportionalHeight:
            widthField.isEnabled = false
            heightField.isEnabled = true
        }
    }

    private func updateProportionalSize(changedField: NSTextField?) {
        guard let defaultPixelSize, defaultPixelSize.width > 0, defaultPixelSize.height > 0 else { return }

        switch selectedResizeMode {
        case .fixed:
            return
        case .proportionalWidth:
            guard changedField == nil || changedField === widthField else { return }
            guard let width = positiveInteger(from: widthField.stringValue) else { return }
            let height = max(1, Int((CGFloat(width) * defaultPixelSize.height / defaultPixelSize.width).rounded()))
            heightField.stringValue = "\(height)"
        case .proportionalHeight:
            guard changedField == nil || changedField === heightField else { return }
            guard let height = positiveInteger(from: heightField.stringValue) else { return }
            let width = max(1, Int((CGFloat(height) * defaultPixelSize.width / defaultPixelSize.height).rounded()))
            widthField.stringValue = "\(width)"
        }
    }

    private var selectedResizeMode: ResizeMode {
        ResizeMode(rawValue: resizeModePopup.indexOfSelectedItem) ?? .fixed
    }

    private var selectedPixelSize: CGSize? {
        updateProportionalSize(changedField: nil)
        let width = positiveInteger(from: widthField.stringValue)
        let height = positiveInteger(from: heightField.stringValue)
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    private func positiveInteger(from string: String) -> Int? {
        let value = Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        field.textColor = .secondaryLabelColor
        return field
    }

    private static func pixelInput(field: NSTextField) -> NSStackView {
        let unitLabel = NSTextField(labelWithString: "px")
        unitLabel.textColor = .tertiaryLabelColor
        unitLabel.alignment = .left

        let stackView = NSStackView(views: [field, unitLabel])
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 8
        return stackView
    }

    #if DEBUG
    var debugQualityControlsVisible: Bool {
        qualityLabel?.alphaValue == 1 && qualitySlider.alphaValue == 1 && qualitySlider.isEnabled
    }

    static var debugLabelColumnWidth: CGFloat {
        labelColumnWidth
    }

    static var debugSizeFieldWidth: CGFloat {
        sizeFieldWidth
    }

    func debugSelectPNG() {
        formatPopup.selectItem(at: 1)
        formatChanged(nil)
    }

    func debugSelectJPEG() {
        formatPopup.selectItem(at: 0)
        formatChanged(nil)
    }

    func debugSelectFixedSizeMode() {
        resizeModePopup.selectItem(at: ResizeMode.fixed.rawValue)
        resizeModeChanged(nil)
    }

    func debugSelectProportionalWidthMode() {
        resizeModePopup.selectItem(at: ResizeMode.proportionalWidth.rawValue)
        resizeModeChanged(nil)
    }

    func debugSelectProportionalHeightMode() {
        resizeModePopup.selectItem(at: ResizeMode.proportionalHeight.rawValue)
        resizeModeChanged(nil)
    }

    func debugSetWidth(_ value: Int) {
        widthField.stringValue = "\(value)"
        sizeFieldChanged(widthField)
    }

    func debugSetHeight(_ value: Int) {
        heightField.stringValue = "\(value)"
        sizeFieldChanged(heightField)
    }

    var debugWidthFieldEnabled: Bool {
        widthField.isEnabled
    }

    var debugHeightFieldEnabled: Bool {
        heightField.isEnabled
    }

    var debugGridRowSpacing: CGFloat {
        gridView?.rowSpacing ?? -1
    }

    var debugGridColumnSpacing: CGFloat {
        gridView?.columnSpacing ?? -1
    }

    var debugGridLeadingInset: CGFloat {
        gridLeadingConstraint?.constant ?? .nan
    }

    var debugPixelUnitSpacing: CGFloat {
        pixelInputStacks.first?.spacing ?? -1
    }

    var debugPixelUnitTextColor: NSColor? {
        pixelUnitLabels.first?.textColor
    }

    var debugLabelTexts: [String] {
        labels.map(\.stringValue)
    }

    var debugFormatPopupWidth: CGFloat {
        formatPopup.constraints.first { $0.firstAttribute == .width }?.constant ?? -1
    }

    var debugResizeModePopupWidth: CGFloat {
        resizeModePopup.constraints.first { $0.firstAttribute == .width }?.constant ?? -1
    }
    #endif
}

extension ImageExportAccessoryView: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        sizeFieldChanged(notification.object)
    }
}

enum TextRecognitionBackend {
    case liveText
    case vision

    static var preferred: TextRecognitionBackend {
        ImageAnalyzer.isSupported ? .liveText : .vision
    }

    static func preferredBackend(
        liveTextSupported: Bool,
        supportsLiveTextSelection: Bool
    ) -> TextRecognitionBackend {
        liveTextSupported && supportsLiveTextSelection ? .liveText : .vision
    }
}

final class CanvasNSView: NSView {
    private static let minimapEnabledDefaultsKey = "PicSee.MinimapEnabled"
    private static let rotationAnimationKey = "PicSee.RotationAnimation"

    private let imageView = NSImageView(frame: .zero)
    private let minimapView = ImageMinimapView(frame: .zero)
    private let backend: TextRecognitionBackend
    private let defaults: UserDefaults

    // Live Text path
    private let liveTextOverlay = ImageAnalysisOverlayView()
    private let analyzer = ImageAnalyzer()

    // Vision path
    private let selectionOverlayView = SelectionOverlayView(frame: .zero)
    private var recognizedLines: [RecognizedTextLine] = [] {
        didSet {
            updateSelectionOverlay()
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    private var selectionAnchorLocation: FragmentLocation?
    private var selectionFocusLocation: FragmentLocation?
    private var selectedFragmentLocations: Set<FragmentLocation> = [] {
        didSet { updateSelectionOverlay() }
    }

    var image: NSImage? {
        didSet {
            let imageChanged = oldValue !== image
            if imageChanged {
                zoomScale = 1
                panOffset = .zero
                resetTextSelectionState()
            }
            imageView.image = image
            if imageChanged {
                analyzeImageIfPossible()
            }
            needsLayout = true
            needsDisplay = true
        }
    }

    var imageURL: URL? {
        didSet {
            guard oldValue != imageURL else { return }
            if image != nil {
                analyzeImageIfPossible()
            }
        }
    }

    var zoomScale: CGFloat = 1 {
        didSet {
            needsLayout = true
            needsDisplay = true
        }
    }

    var panOffset: CGSize = .zero {
        didSet {
            needsLayout = true
            needsDisplay = true
        }
    }

    var rotationDegrees: Int = 0 {
        didSet {
            let oldRotation = Self.normalizedRotationDegrees(oldValue)
            rotationDegrees = Self.normalizedRotationDegrees(rotationDegrees)
            if oldRotation != rotationDegrees {
                pendingRotationAnimation = (from: oldRotation, to: rotationDegrees)
            }
            needsLayout = true
            needsDisplay = true
        }
    }

    var onZoomChanged: ((CGFloat) -> Void)?
    var onPanChanged: ((CGSize) -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onReset: (() -> Void)?
    var onClose: (() -> Void)?
    var onZoomRequestHandled: ((Int) -> Void)?
    var onDisplayScaleChanged: ((CGFloat) -> Void)?
    var onTitleBarVisibilityChanged: ((Bool) -> Void)?
    var onFileInfoVisibilityChanged: ((Bool) -> Void)?
    var onToolbarVisibilityChanged: ((Bool) -> Void)?
    var onImageParametersVisibilityChanged: ((Bool) -> Void)?
    var onFixedWindowChanged: ((Bool) -> Void)?
    var onCheckForUpdates: (() -> Void)?

    private enum DragType {
        case none
        case window
        case pan
        case textSelection
        case resize(WindowResizeAnchor)
    }

    private var dragType: DragType = .none
    private var dragStartPoint: NSPoint?
    private var dragStartWindowFrame: NSRect?
    private var dragStartOffset: CGSize = .zero
    private var lastReportedDisplayScale: CGFloat = -1
    private var trackingArea: NSTrackingArea?
    private var analysisTask: Task<Void, Never>?
    private var analysisToken = 0
    private var pendingRotationAnimation: (from: Int, to: Int)?
    private var handledZoomRequestID: Int?
    private var minimapEnabled: Bool
    var titleBarVisible: Bool {
        didSet {
            guard oldValue != titleBarVisible else { return }
            needsLayout = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var fileInfoVisible: Bool
    var toolbarVisible: Bool
    var imageParametersVisible: Bool
    var fixedWindowEnabled: Bool

    private let topDragRegionHeight: CGFloat = 36
    private let topLeftResizeRegionSize: CGFloat = 44
    private let bottomRightResizeRegionSize: CGFloat = 64
    private let resizeAvoidancePadding: CGFloat = 8
    private let minimumWindowSize = NSSize(width: 320, height: 220)
    private let minimapMaxSize = CGSize(width: 140, height: 100)
    private let minimapPadding: CGFloat = 12

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(frame frameRect: NSRect, backend: TextRecognitionBackend, defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
        self.minimapEnabled = Self.defaultMinimapEnabled(in: defaults)
        self.titleBarVisible = ViewerTitleBarPreference.isVisible(in: defaults)
        self.fileInfoVisible = ViewerOverlayPreference.isFileInfoVisible(in: defaults)
        self.toolbarVisible = ViewerOverlayPreference.isToolbarVisible(in: defaults)
        self.imageParametersVisible = ViewerOverlayPreference.isImageParametersVisible(in: defaults)
        self.fixedWindowEnabled = WindowFramePreference.isFixedEnabled(in: defaults)
        super.init(frame: frameRect)
        configureSubviews()
    }

    override convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, backend: .preferred)
    }

    required init?(coder: NSCoder) {
        self.backend = .preferred
        self.defaults = .standard
        self.minimapEnabled = Self.defaultMinimapEnabled(in: .standard)
        self.titleBarVisible = ViewerTitleBarPreference.isVisible(in: .standard)
        self.fileInfoVisible = ViewerOverlayPreference.isFileInfoVisible(in: .standard)
        self.toolbarVisible = ViewerOverlayPreference.isToolbarVisible(in: .standard)
        self.imageParametersVisible = ViewerOverlayPreference.isImageParametersVisible(in: .standard)
        self.fixedWindowEnabled = WindowFramePreference.isFixedEnabled(in: .standard)
        super.init(coder: coder)
        configureSubviews()
    }

    private static func defaultMinimapEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: minimapEnabledDefaultsKey) as? Bool ?? true
    }

    private static func normalizedRotationDegrees(_ degrees: Int) -> Int {
        ((degrees % 360) + 360) % 360
    }

    deinit {
        analysisTask?.cancel()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseMoved, .cursorUpdate, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func layout() {
        super.layout()
        let geometry = currentGeometry()
        imageView.frame = geometry.unrotatedImageRect
        imageView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        imageView.layer?.position = CGPoint(x: geometry.imageRect.midX, y: geometry.imageRect.midY)
        applyImageRotation()
        switch backend {
        case .liveText:
            liveTextOverlay.frame = imageView.bounds
            repositionLiveTextControlsIfNeeded()
        case .vision:
            selectionOverlayView.frame = bounds
            updateSelectionOverlay()
        }
        updateMinimap(geometry: geometry)
        reportDisplayScaleIfNeeded(geometry.displayScale)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }

    override func resetCursorRects() {
        discardCursorRects()
        guard !titleBarVisible, !fixedWindowEnabled else { return }

        addCursorRect(
            NSRect(
                x: max(bounds.width - bottomRightResizeRegionSize, 0),
                y: 0,
                width: min(bottomRightResizeRegionSize, bounds.width),
                height: min(bottomRightResizeRegionSize, bounds.height)
            ),
            cursor: .resizeLeftRight
        )
        addCursorRect(
            NSRect(
                x: 0,
                y: max(bounds.height - topLeftResizeRegionSize, 0),
                width: min(topLeftResizeRegionSize, bounds.width),
                height: min(topLeftResizeRegionSize, bounds.height)
            ),
            cursor: .resizeLeftRight
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if resizeAnchor(at: point) != nil {
            return self
        }
        return super.hitTest(point)
    }

    override func mouseMoved(with event: NSEvent) {
        cursorForPoint(convert(event.locationInWindow, from: nil)).set()
    }

    override func cursorUpdate(with event: NSEvent) {
        cursorForPoint(convert(event.locationInWindow, from: nil)).set()
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY == 0 ? -event.scrollingDeltaX : event.scrollingDeltaY
        guard delta != 0 else { return }

        let step: CGFloat = event.hasPreciseScrollingDeltas ? 0.0018 : 0.018
        let multiplier = exp(abs(delta) * step)
        applyZoom(multiplier: delta > 0 ? multiplier : 1 / multiplier)
    }

    override func magnify(with event: NSEvent) {
        guard event.magnification != 0 else { return }
        applyZoom(multiplier: 1 + event.magnification)
    }

    func applyToolbarZoom(request: ImageZoomRequest) {
        guard handledZoomRequestID != request.id else { return }
        handledZoomRequestID = request.id
        applyZoom(multiplier: request.multiplier)
        onZoomRequestHandled?(request.id)
    }

    private func applyZoom(multiplier: CGFloat) {
        let geometry = currentGeometry()
        let adjustment = ImageZoomAdjustment.adjustment(
            from: geometry,
            multiplier: multiplier
        )
        zoomScale = adjustment.zoomScale
        panOffset = adjustment.panOffset
        onZoomChanged?(adjustment.zoomScale)
        onPanChanged?(adjustment.panOffset)
        if backend == .vision {
            updateSelectionOverlay()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let geometry = currentGeometry()
        let point = convert(event.locationInWindow, from: nil)

        dragType = .none
        dragStartPoint = nil
        dragStartWindowFrame = nil
        dragStartOffset = .zero
        selectionAnchorLocation = nil
        selectionFocusLocation = nil

        if let resizeAnchor = resizeAnchor(at: point), let window {
            dragType = .resize(resizeAnchor)
            dragStartPoint = window.convertPoint(toScreen: event.locationInWindow)
            dragStartWindowFrame = window.frame
            return
        }

        let hitText = backend == .vision ? hitTextLocation(at: point, geometry: geometry) : nil

        if shouldToggleDesktopFillOnMouseDown(clickCount: event.clickCount, at: point) {
            (window as? ViewerWindow)?.toggleTemporaryDesktopFullScreen()
            return
        }

        if event.clickCount == 2, hitText == nil {
            let isFitted = abs(zoomScale - 1) < 0.001 && abs(panOffset.width) < 0.5 && abs(panOffset.height) < 0.5
            if isFitted {
                window?.toggleFullScreen(nil)
            } else {
                zoomScale = 1
                panOffset = .zero
                onZoomChanged?(1)
                onPanChanged?(.zero)
                onReset?()
            }
            return
        }

        if let textLocation = hitText {
            dragType = .textSelection
            selectionAnchorLocation = textLocation
            selectionFocusLocation = textLocation
            updateSelectedTextRange()
            return
        }

        if isInTopDragRegion(point) {
            dragType = .window
            return
        }

        if panImageMode(geometry), geometry.imageRect.contains(point) {
            dragType = .pan
            dragStartPoint = point
            dragStartOffset = panOffset
            NSCursor.closedHand.set()
        } else if backend == .vision {
            clearTextSelection()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch dragType {
        case .none:
            break
        case .window:
            window?.performDrag(with: event)
        case .pan:
            guard let dragStartPoint else { return }
            let geometry = currentGeometry()
            let nextOffset = CGSize(
                width: dragStartOffset.width + point.x - dragStartPoint.x,
                height: dragStartOffset.height + point.y - dragStartPoint.y
            )
            panOffset = constrainPan(nextOffset, geometry: geometry)
            onPanChanged?(panOffset)
        case .textSelection:
            guard backend == .vision, let anchor = selectionAnchorLocation else { return }
            let geometry = currentGeometry()
            let target = nearestTextLocation(to: point, geometry: geometry) ?? anchor
            selectionFocusLocation = target
            updateSelectedTextRange()
        case .resize(let anchor):
            guard
                let window,
                let dragStartPoint,
                let dragStartWindowFrame
            else { return }
            let currentPoint = window.convertPoint(toScreen: event.locationInWindow)
            let delta = CGSize(
                width: currentPoint.x - dragStartPoint.x,
                height: currentPoint.y - dragStartPoint.y
            )
            let nextFrame = WindowResizeGeometry.frame(
                from: dragStartWindowFrame,
                anchor: anchor,
                delta: delta,
                minimumSize: minimumWindowSize
            )
            window.setFrame(nextFrame, display: true)
            WindowFramePreference.save(nextFrame)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if case .pan = dragType {
            cursorForPoint(convert(event.locationInWindow, from: nil)).set()
        }
        dragType = .none
        dragStartPoint = nil
        dragStartWindowFrame = nil
        dragStartOffset = .zero
        selectionAnchorLocation = nil
        selectionFocusLocation = nil
    }

    override func keyDown(with event: NSEvent) {
        switch KeyboardNavigation.action(for: event.keyCode) {
        case .previous:
            onPrevious?()
        case .next:
            onNext?()
        case .quit:
            onClose?()
        case .toggleImageParameters:
            toggleImageParametersVisibility()
        case .none:
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command],
           event.charactersIgnoringModifiers?.lowercased() == "c",
           copySelectedTextToPasteboard() {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func copy(_ sender: Any?) {
        _ = copySelectedTextToPasteboard()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "Image")

        if backend == .vision, !selectedFragmentLocations.isEmpty {
            let copyItem = NSMenuItem(title: "复制", action: #selector(copySelectedText), keyEquivalent: "c")
            copyItem.target = self
            menu.addItem(copyItem)
            menu.addItem(.separator())
        }

        appendPicSeeContextMenuItems(to: menu)
        return menu
    }

    @objc func copyImagePathForMenu(_ sender: Any?) {
        guard let path = imageURL?.path else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    @objc func exportImageForMenu(_ sender: Any?) {
        guard let image else { return }

        let panel = NSSavePanel()
        let accessoryView = ImageExportAccessoryView(defaultPixelSize: ImageExporter.pixelSize(of: image))
        panel.title = "图片另存为"
        panel.nameFieldStringValue = defaultExportFilename()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.canCreateDirectories = true
        panel.accessoryView = accessoryView
        accessoryView.onFormatChanged = { [weak panel] format in
            guard let panel else { return }
            panel.allowedContentTypes = [format.contentType]
            panel.nameFieldStringValue = Self.filename(panel.nameFieldStringValue, withExtension: format.pathExtension)
        }

        panel.begin { [weak self, weak accessoryView] response in
            guard response == .OK, let url = panel.url, let accessoryView else { return }
            let options = accessoryView.exportOptions
            let destinationURL = Self.destinationURL(url, for: options.format)
            do {
                try ImageExporter.export(image, to: destinationURL, options: options)
            } catch {
                self?.presentExportError(error)
            }
        }
    }

    @objc func toggleMinimapForMenu(_ sender: Any?) {
        minimapEnabled.toggle()
        defaults.set(minimapEnabled, forKey: Self.minimapEnabledDefaultsKey)
        needsLayout = true
    }

    @objc func toggleTitleBarForMenu(_ sender: Any?) {
        titleBarVisible.toggle()
        ViewerTitleBarPreference.setVisible(titleBarVisible, in: defaults)
        onTitleBarVisibilityChanged?(titleBarVisible)
    }

    @objc func toggleFileInfoForMenu(_ sender: Any?) {
        fileInfoVisible.toggle()
        ViewerOverlayPreference.setFileInfoVisible(fileInfoVisible, in: defaults)
        onFileInfoVisibilityChanged?(fileInfoVisible)
    }

    @objc func toggleToolbarForMenu(_ sender: Any?) {
        toolbarVisible.toggle()
        ViewerOverlayPreference.setToolbarVisible(toolbarVisible, in: defaults)
        onToolbarVisibilityChanged?(toolbarVisible)
    }

    @objc func toggleImageParametersForMenu(_ sender: Any?) {
        toggleImageParametersVisibility()
    }

    @objc func toggleFixedWindowForMenu(_ sender: Any?) {
        fixedWindowEnabled.toggle()
        WindowFramePreference.setFixedEnabled(fixedWindowEnabled, in: defaults)
        if fixedWindowEnabled, let window {
            WindowFramePreference.saveFixedFrame(window.frame, in: defaults)
        }
        onFixedWindowChanged?(fixedWindowEnabled)
        window?.invalidateCursorRects(for: self)
    }

    @objc func checkForUpdatesForMenu(_ sender: Any?) {
        onCheckForUpdates?()
    }

    @objc func selectTheme(_ sender: Any?) {
        guard
            let item = sender as? NSMenuItem,
            let rawValue = item.representedObject as? Int,
            let theme = ViewerTheme(rawValue: rawValue)
        else { return }
        ViewerTheme.set(theme, in: defaults)
        if let appearance = theme.appearance {
            window?.appearance = appearance
        } else {
            window?.appearance = nil
        }
    }

    private func toggleImageParametersVisibility() {
        imageParametersVisible.toggle()
        ViewerOverlayPreference.setImageParametersVisible(imageParametersVisible, in: defaults)
        onImageParametersVisibilityChanged?(imageParametersVisible)
    }

    @objc private func copySelectedText() {
        _ = copySelectedTextToPasteboard()
    }

    private func appendPicSeeContextMenuItems(to menu: NSMenu) {
        let shouldAddTitleBarItem = menu.items.first(where: { $0.action == #selector(toggleTitleBarForMenu(_:)) }) == nil
        let shouldAddMinimapItem = menu.items.first(where: { $0.action == #selector(toggleMinimapForMenu(_:)) }) == nil
        let shouldAddFileInfoItem = menu.items.first(where: { $0.action == #selector(toggleFileInfoForMenu(_:)) }) == nil
        let shouldAddToolbarItem = menu.items.first(where: { $0.action == #selector(toggleToolbarForMenu(_:)) }) == nil
        let shouldAddImageParametersItem = menu.items.first(where: { $0.action == #selector(toggleImageParametersForMenu(_:)) }) == nil
        let shouldAddFixedWindowItem = menu.items.first(where: { $0.action == #selector(toggleFixedWindowForMenu(_:)) }) == nil

        if shouldAddTitleBarItem || shouldAddMinimapItem || shouldAddFileInfoItem || shouldAddToolbarItem || shouldAddImageParametersItem || shouldAddFixedWindowItem {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
        }

        if shouldAddTitleBarItem {
            let titleBarItem = NSMenuItem(title: "显示标题栏", action: #selector(toggleTitleBarForMenu(_:)), keyEquivalent: "")
            titleBarItem.target = self
            titleBarItem.state = titleBarVisible ? .on : .off
            menu.addItem(titleBarItem)
        }

        if shouldAddMinimapItem {
            let minimapItem = NSMenuItem(title: "显示缩略图", action: #selector(toggleMinimapForMenu(_:)), keyEquivalent: "")
            minimapItem.target = self
            minimapItem.state = minimapEnabled ? .on : .off
            menu.addItem(minimapItem)
        }

        if shouldAddFileInfoItem {
            let fileInfoItem = NSMenuItem(title: "显示文件信息", action: #selector(toggleFileInfoForMenu(_:)), keyEquivalent: "")
            fileInfoItem.target = self
            fileInfoItem.state = fileInfoVisible ? .on : .off
            menu.addItem(fileInfoItem)
        }

        if shouldAddToolbarItem {
            let toolbarItem = NSMenuItem(title: "显示底部工具栏", action: #selector(toggleToolbarForMenu(_:)), keyEquivalent: "")
            toolbarItem.target = self
            toolbarItem.state = toolbarVisible ? .on : .off
            menu.addItem(toolbarItem)
        }

        if shouldAddImageParametersItem {
            let imageParametersItem = NSMenuItem(title: "显示图片参数", action: #selector(toggleImageParametersForMenu(_:)), keyEquivalent: "i")
            imageParametersItem.target = self
            imageParametersItem.state = imageParametersVisible ? .on : .off
            menu.addItem(imageParametersItem)
        }

        if shouldAddFixedWindowItem {
            let fixedWindowItem = NSMenuItem(title: "固定窗口大小和位置", action: #selector(toggleFixedWindowForMenu(_:)), keyEquivalent: "")
            fixedWindowItem.target = self
            fixedWindowItem.state = fixedWindowEnabled ? .on : .off
            menu.addItem(fixedWindowItem)
        }

        if menu.items.first(where: { $0.action == #selector(selectTheme(_:)) }) == nil {
            let themeItem = NSMenuItem(title: "主题", action: nil, keyEquivalent: "")
            let themeMenu = NSMenu(title: "主题")
            for theme in ViewerTheme.allCases {
                let item = NSMenuItem(title: theme.displayName, action: #selector(selectTheme(_:)), keyEquivalent: "")
                item.target = self
                item.state = ViewerTheme.current(in: defaults) == theme ? .on : .off
                item.representedObject = theme.rawValue
                themeMenu.addItem(item)
            }
            themeItem.submenu = themeMenu
            menu.addItem(themeItem)
        }

        if menu.items.first(where: { $0.action == #selector(copyImagePathForMenu(_:)) }) == nil {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            let pathItem = NSMenuItem(title: "复制图片路径", action: #selector(copyImagePathForMenu(_:)), keyEquivalent: "")
            pathItem.target = self
            pathItem.isEnabled = imageURL != nil
            menu.addItem(pathItem)
        }

        if menu.items.first(where: { $0.action == #selector(exportImageForMenu(_:)) }) == nil {
            let exportItem = NSMenuItem(title: "图片另存为...", action: #selector(exportImageForMenu(_:)), keyEquivalent: "")
            exportItem.target = self
            exportItem.isEnabled = image != nil
            menu.addItem(exportItem)
        }

        if menu.items.first(where: { $0.action == #selector(AppDelegate.showDefaultImageAppSettings(_:)) }) == nil {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            let defaultSettingsItem = NSMenuItem(
                title: "设置图片默认打开方式",
                action: #selector(AppDelegate.showDefaultImageAppSettings(_:)),
                keyEquivalent: ""
            )
            defaultSettingsItem.target = NSApplication.shared.delegate
            menu.addItem(defaultSettingsItem)
        }

        if menu.items.first(where: { $0.action == #selector(checkForUpdatesForMenu(_:)) }) == nil {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }

            let updateItem = NSMenuItem(title: "检查更新", action: #selector(checkForUpdatesForMenu(_:)), keyEquivalent: "")
            updateItem.target = self
            updateItem.isEnabled = onCheckForUpdates != nil
            menu.addItem(updateItem)
        }

        AppMenu.appendAboutItem(to: menu, includeSeparator: false)
    }

    private func defaultExportFilename() -> String {
        Self.defaultExportFilename(for: imageURL)
    }

    private static func defaultExportFilename(for url: URL?) -> String {
        let baseName = url?.deletingPathExtension().lastPathComponent ?? "PicSee Export"
        return "\(baseName)_副本.jpg"
    }

    private static func destinationURL(_ url: URL, for format: ImageExportFormat) -> URL {
        let expectedExtension = format.pathExtension.lowercased()
        guard url.pathExtension.lowercased() != expectedExtension else { return url }
        return url.deletingPathExtension().appendingPathExtension(expectedExtension)
    }

    private static func filename(_ filename: String, withExtension pathExtension: String) -> String {
        let url = URL(fileURLWithPath: filename)
        return url.deletingPathExtension().appendingPathExtension(pathExtension).lastPathComponent
    }

    private func presentExportError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "保存图片失败"
        alert.runModal()
    }

    private func configureSubviews() {
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.contentsGravity = .resizeAspect
        addSubview(imageView)

        switch backend {
        case .liveText:
            liveTextOverlay.autoresizingMask = [.width, .height]
            liveTextOverlay.trackingImageView = imageView
            liveTextOverlay.delegate = self
            liveTextOverlay.preferredInteractionTypes = .automatic
            imageView.addSubview(liveTextOverlay)
        case .vision:
            selectionOverlayView.autoresizingMask = [.width, .height]
            addSubview(selectionOverlayView)
        }

        minimapView.isHidden = true
        minimapView.onNavigate = { [weak self] point in
            self?.navigateWithMinimap(to: point)
        }
        addSubview(minimapView)
    }

    private func resetTextSelectionState() {
        switch backend {
        case .liveText:
            liveTextOverlay.analysis = nil
        case .vision:
            clearTextSelection()
            recognizedLines = []
        }
    }

    private func analyzeImageIfPossible() {
        analysisTask?.cancel()
        analysisToken &+= 1
        let token = analysisToken

        switch backend {
        case .liveText:
            liveTextOverlay.analysis = nil
            scheduleLiveTextControlReposition()
            analyzeWithLiveText(token: token)
        case .vision:
            recognizedLines = []
            analyzeWithVision(token: token)
        }
    }

    private func analyzeWithLiveText(token: Int) {
        guard
            ImageAnalyzer.isSupported,
            let image,
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        let orientation = exifOrientation(for: imageURL)
        let configuration = ImageAnalyzer.Configuration([.text, .machineReadableCode, .visualLookUp])

        analysisTask = Task { [weak self, analyzer] in
            do {
                let analysis = try await analyzer.analyze(cgImage, orientation: orientation, configuration: configuration)
                await MainActor.run { [weak self] in
                    guard let self, !Task.isCancelled, token == self.analysisToken else { return }
                    self.liveTextOverlay.analysis = analysis
                    self.scheduleLiveTextControlReposition()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, token == self.analysisToken else { return }
                    self.liveTextOverlay.analysis = nil
                    self.scheduleLiveTextControlReposition()
                }
            }
        }
    }

    private func analyzeWithVision(token: Int) {
        guard
            let image,
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        let orientation = exifOrientation(for: imageURL)
        analysisTask = Task.detached(priority: .userInitiated) { [weak self] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

            do {
                try handler.perform([request])
                let observations = request.results ?? []
                let sortedObservations = observations.compactMap { observation -> RecognizedObservationLine? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }
                    return RecognizedObservationLine(text: text, boundingBox: observation.boundingBox, candidate: candidate)
                }
                .sorted(by: Self.sortObservationLines)

                let lines = sortedObservations.enumerated().map { lineOffset, line in
                    RecognizedTextLine(
                        text: line.text,
                        boundingBox: line.boundingBox,
                        fragments: Self.makeFragments(from: line.candidate, text: line.text, lineIndex: lineOffset)
                    )
                }

                await MainActor.run { [weak self] in
                    guard let self, !Task.isCancelled, token == self.analysisToken else { return }
                    self.recognizedLines = lines
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, token == self.analysisToken else { return }
                    self.recognizedLines = []
                }
            }
        }
    }

    nonisolated private static func sortObservationLines(_ lhs: RecognizedObservationLine, _ rhs: RecognizedObservationLine) -> Bool {
        let leftY = lhs.boundingBox.midY
        let rightY = rhs.boundingBox.midY
        if abs(leftY - rightY) > 0.01 {
            return leftY > rightY
        }
        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }

    nonisolated private static func makeFragments(
        from candidate: VNRecognizedText,
        text: String,
        lineIndex: Int
    ) -> [RecognizedTextFragment] {
        var fragments: [RecognizedTextFragment] = []
        var fragmentIndex = 0
        var index = text.startIndex

        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            let range = index ..< nextIndex

            if let observation = try? candidate.boundingBox(for: range) {
                let rect = observation.boundingBox
                guard !rect.isEmpty else {
                    fragmentIndex += 1
                    index = nextIndex
                    continue
                }
                fragments.append(
                    RecognizedTextFragment(
                        text: String(text[range]),
                        boundingBox: rect,
                        lineIndex: lineIndex,
                        fragmentIndex: fragmentIndex
                    )
                )
            }

            fragmentIndex += 1
            index = nextIndex
        }

        return fragments
    }

    private func currentGeometry() -> ImageDisplayGeometry {
        ImageDisplayGeometry(
            imageSize: image?.size ?? .zero,
            viewportSize: bounds.size,
            zoomScale: zoomScale,
            panOffset: panOffset,
            rotationDegrees: rotationDegrees
        )
    }

    private func panImageMode(_ geometry: ImageDisplayGeometry) -> Bool {
        if abs(geometry.zoomScale - 1) > 0.001 { return true }
        return geometry.canPan
    }

    private func constrainPan(_ proposed: CGSize, geometry: ImageDisplayGeometry) -> CGSize {
        geometry.constrainedPan(proposed, allowSlackWhenFitted: panImageMode(geometry))
    }

    private func applyImageRotation() {
        guard let layer = imageView.layer else { return }

        let targetRadians = CGFloat(rotationDegrees) * .pi / 180
        if let pendingRotationAnimation {
            let fromRadians = targetRadians - Self.shortestRotationDeltaRadians(
                from: pendingRotationAnimation.from,
                to: pendingRotationAnimation.to
            )
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = fromRadians
            animation.toValue = targetRadians
            animation.duration = 0.22
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.removeAnimation(forKey: Self.rotationAnimationKey)
            layer.add(animation, forKey: Self.rotationAnimationKey)
            self.pendingRotationAnimation = nil
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setAffineTransform(CGAffineTransform(rotationAngle: targetRadians))
        CATransaction.commit()
    }

    private static func shortestRotationDeltaRadians(from oldDegrees: Int, to newDegrees: Int) -> CGFloat {
        let rawDelta = normalizedRotationDegrees(newDegrees) - normalizedRotationDegrees(oldDegrees)
        let shortestDelta: Int
        if rawDelta > 180 {
            shortestDelta = rawDelta - 360
        } else if rawDelta < -180 {
            shortestDelta = rawDelta + 360
        } else {
            shortestDelta = rawDelta
        }
        return CGFloat(shortestDelta) * .pi / 180
    }

    private func scheduleLiveTextControlReposition() {
        DispatchQueue.main.async { [weak self] in
            self?.repositionLiveTextControlsIfNeeded()
        }
    }

    private func repositionLiveTextControlsIfNeeded() {
        guard backend == .liveText, !titleBarVisible else { return }

        let reservedSize = bottomRightResizeRegionSize + resizeAvoidancePadding
        let protectedRect = CGRect(
            x: liveTextOverlay.bounds.maxX - reservedSize,
            y: liveTextOverlay.bounds.minY,
            width: reservedSize,
            height: reservedSize
        )

        for subview in liveTextOverlay.subviews {
            let frame = subview.frame
            guard
                frame.width <= 96,
                frame.height <= 96,
                frame.intersects(protectedRect)
            else {
                continue
            }

            let adjustedFrame = Self.adjustedLiveTextControlFrame(
                for: frame,
                in: liveTextOverlay.bounds,
                reservedSize: reservedSize
            )

            guard adjustedFrame.minX.isFinite, adjustedFrame.minY.isFinite else { continue }
            subview.setFrameOrigin(adjustedFrame.origin)
        }
    }

    private static func adjustedLiveTextControlFrame(
        for frame: CGRect,
        in bounds: CGRect,
        reservedSize: CGFloat
    ) -> CGRect {
        let safeCornerInset = reservedSize + 10
        let maxX = bounds.maxX - safeCornerInset - frame.width
        let minY = bounds.minY + safeCornerInset

        var adjustedFrame = frame
        adjustedFrame.origin.x = min(frame.origin.x, maxX)
        adjustedFrame.origin.y = max(frame.origin.y, minY)

        let clampedX = max(bounds.minX + 8, min(adjustedFrame.origin.x, bounds.maxX - adjustedFrame.width - 8))
        let clampedY = max(bounds.minY + 8, min(adjustedFrame.origin.y, bounds.maxY - adjustedFrame.height - 8))
        adjustedFrame.origin = CGPoint(x: clampedX, y: clampedY)
        return adjustedFrame
    }

    private func updateMinimap(geometry: ImageDisplayGeometry) {
        guard minimapEnabled, geometry.shouldShowMinimap, let image else {
            minimapView.isHidden = true
            minimapView.image = nil
            minimapView.minimapGeometry = nil
            return
        }

        let minimapGeometry = geometry.minimapGeometry(maxSize: minimapMaxSize)
        guard minimapGeometry.size.width > 0, minimapGeometry.size.height > 0 else {
            minimapView.isHidden = true
            return
        }

        minimapView.isHidden = false
        minimapView.image = image
        minimapView.minimapGeometry = minimapGeometry
        let bottomPadding = titleBarVisible ? minimapPadding : bottomRightResizeRegionSize + minimapPadding
        let chromeInset = ImageMinimapView.contentInset * 2
        let minimapFrameSize = CGSize(
            width: minimapGeometry.size.width + chromeInset,
            height: minimapGeometry.size.height + chromeInset
        )
        minimapView.frame = CGRect(
            x: bounds.width - minimapFrameSize.width - minimapPadding,
            y: bottomPadding,
            width: minimapFrameSize.width,
            height: minimapFrameSize.height
        )
    }

    private func navigateWithMinimap(to point: CGPoint) {
        let geometry = currentGeometry()
        guard geometry.shouldShowMinimap else { return }

        let minimapGeometry = geometry.minimapGeometry(maxSize: minimapMaxSize)
        panOffset = geometry.constrainedPan(centeredAtMinimapPoint: point, minimap: minimapGeometry)
        onPanChanged?(panOffset)
        needsLayout = true
    }

    private func isInTopDragRegion(_ point: CGPoint) -> Bool {
        !titleBarVisible && point.y >= bounds.height - topDragRegionHeight
    }

    private func shouldToggleDesktopFillOnMouseDown(clickCount: Int, at point: CGPoint) -> Bool {
        clickCount == 2 && isInTopDragRegion(point)
    }

    private func resizeAnchor(at point: CGPoint) -> WindowResizeAnchor? {
        guard !titleBarVisible, !fixedWindowEnabled else { return nil }
        if point.x <= topLeftResizeRegionSize, point.y >= bounds.height - topLeftResizeRegionSize {
            return .topLeft
        }
        if point.x >= bounds.width - bottomRightResizeRegionSize, point.y <= bottomRightResizeRegionSize {
            return .bottomRight
        }
        return nil
    }

    #if DEBUG
    func debugResizeAnchor(at point: CGPoint) -> WindowResizeAnchor? {
        resizeAnchor(at: point)
    }
    #endif

    private func lineRectInView(_ line: RecognizedTextLine, geometry: ImageDisplayGeometry) -> CGRect {
        CGRect(
            x: geometry.imageRect.minX + line.boundingBox.minX * geometry.imageRect.width,
            y: geometry.imageRect.minY + line.boundingBox.minY * geometry.imageRect.height,
            width: line.boundingBox.width * geometry.imageRect.width,
            height: line.boundingBox.height * geometry.imageRect.height
        )
    }

    private func fragmentRectInView(_ fragment: RecognizedTextFragment, geometry: ImageDisplayGeometry) -> CGRect {
        CGRect(
            x: geometry.imageRect.minX + fragment.boundingBox.minX * geometry.imageRect.width,
            y: geometry.imageRect.minY + fragment.boundingBox.minY * geometry.imageRect.height,
            width: fragment.boundingBox.width * geometry.imageRect.width,
            height: fragment.boundingBox.height * geometry.imageRect.height
        )
    }

    private func hitTextLocation(at point: CGPoint, geometry: ImageDisplayGeometry) -> FragmentLocation? {
        guard backend == .vision else { return nil }
        if let location = hitTextLocationWithoutFallback(at: point, geometry: geometry) {
            return location
        }
        return nearestTextLocation(to: point, geometry: geometry, maxDistanceSquared: 144)
    }

    private func hitTextLocationWithoutFallback(at point: CGPoint, geometry: ImageDisplayGeometry) -> FragmentLocation? {
        guard geometry.imageRect.contains(point) else { return nil }

        for line in recognizedLines {
            for fragment in line.fragments {
                let rect = fragmentRectInView(fragment, geometry: geometry).insetBy(dx: -3, dy: -4)
                if rect.contains(point) {
                    return FragmentLocation(lineIndex: fragment.lineIndex, fragmentIndex: fragment.fragmentIndex)
                }
            }
        }

        return nil
    }

    private func nearestTextLocation(
        to point: CGPoint,
        geometry: ImageDisplayGeometry,
        maxDistanceSquared: CGFloat = 900
    ) -> FragmentLocation? {
        guard geometry.imageRect.contains(point), !recognizedLines.isEmpty else { return nil }

        var bestLocation: FragmentLocation?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for line in recognizedLines {
            let expandedLineRect = lineRectInView(line, geometry: geometry).insetBy(dx: -8, dy: -6)
            guard expandedLineRect.contains(point) else { continue }

            for fragment in line.fragments {
                let rect = fragmentRectInView(fragment, geometry: geometry)
                let dx: CGFloat
                if point.x < rect.minX {
                    dx = rect.minX - point.x
                } else if point.x > rect.maxX {
                    dx = point.x - rect.maxX
                } else {
                    dx = 0
                }

                let dy: CGFloat
                if point.y < rect.minY {
                    dy = rect.minY - point.y
                } else if point.y > rect.maxY {
                    dy = point.y - rect.maxY
                } else {
                    dy = 0
                }

                let distance = dx * dx + dy * dy
                if distance < bestDistance {
                    bestDistance = distance
                    bestLocation = FragmentLocation(lineIndex: fragment.lineIndex, fragmentIndex: fragment.fragmentIndex)
                }
            }
        }

        return bestDistance < maxDistanceSquared ? bestLocation : nil
    }

    private func updateSelectionOverlay() {
        guard backend == .vision else { return }
        let geometry = currentGeometry()
        selectionOverlayView.selectionRects = selectedFragments().map {
            fragmentRectInView($0, geometry: geometry)
        }
    }

    private func updateSelectedTextRange() {
        guard let anchor = selectionAnchorLocation, let focus = selectionFocusLocation else {
            clearTextSelection()
            return
        }

        let lower = min(anchor, focus)
        let upper = max(anchor, focus)
        var selected: Set<FragmentLocation> = []

        for line in recognizedLines {
            for fragment in line.fragments {
                let location = FragmentLocation(lineIndex: fragment.lineIndex, fragmentIndex: fragment.fragmentIndex)
                if location >= lower && location <= upper {
                    selected.insert(location)
                }
            }
        }

        selectedFragmentLocations = selected
    }

    private func clearTextSelection() {
        selectedFragmentLocations = []
        selectionAnchorLocation = nil
        selectionFocusLocation = nil
    }

    private func selectedFragments() -> [RecognizedTextFragment] {
        recognizedLines
            .flatMap(\.fragments)
            .filter { fragment in
                selectedFragmentLocations.contains(
                    FragmentLocation(lineIndex: fragment.lineIndex, fragmentIndex: fragment.fragmentIndex)
                )
            }
            .sorted {
                if $0.lineIndex != $1.lineIndex {
                    return $0.lineIndex < $1.lineIndex
                }
                return $0.fragmentIndex < $1.fragmentIndex
            }
    }

    private func selectedVisionText() -> String {
        let grouped = Dictionary(grouping: selectedFragments(), by: \.lineIndex)
        return grouped.keys.sorted().compactMap { lineIndex in
            grouped[lineIndex]?
                .sorted { $0.fragmentIndex < $1.fragmentIndex }
                .map(\.text)
                .joined()
        }
        .joined(separator: "\n")
    }

    private func currentlySelectedText() -> String {
        switch backend {
        case .liveText:
            return liveTextOverlay.selectedText
        case .vision:
            return selectedVisionText()
        }
    }

    @discardableResult
    private func copySelectedTextToPasteboard() -> Bool {
        let text = currentlySelectedText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return true
    }

    private func reportDisplayScaleIfNeeded(_ displayScale: CGFloat) {
        guard abs(displayScale - lastReportedDisplayScale) > 0.0001 else { return }
        lastReportedDisplayScale = displayScale
        onDisplayScaleChanged?(displayScale)
    }

    private func cursorForPoint(_ point: CGPoint) -> NSCursor {
        let geometry = currentGeometry()
        if resizeAnchor(at: point) != nil {
            return .resizeLeftRight
        }
        if backend == .vision, hitTextLocation(at: point, geometry: geometry) != nil {
            return .iBeam
        }
        if case .pan = dragType {
            return .openHand
        }
        if panImageMode(geometry), geometry.imageRect.contains(point) {
            return .openHand
        }
        return .arrow
    }

    private func exifOrientation(for url: URL?) -> CGImagePropertyOrientation {
        guard
            let url,
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let rawValue = properties[kCGImagePropertyOrientation] as? UInt32,
            let orientation = CGImagePropertyOrientation(rawValue: rawValue)
        else {
            return .up
        }
        return orientation
    }
}

extension CanvasNSView: ImageAnalysisOverlayViewDelegate {
    func overlayView(_ overlayView: ImageAnalysisOverlayView, liveTextButtonDidChangeToVisible visible: Bool) {
        if visible {
            scheduleLiveTextControlReposition()
        }
    }

    func overlayView(_ overlayView: ImageAnalysisOverlayView, updatedMenuFor menu: NSMenu, for event: NSEvent, at point: CGPoint) -> NSMenu {
        appendPicSeeContextMenuItems(to: menu)
        return menu
    }
}

#if DEBUG
extension CanvasNSView {
    var debugBackend: TextRecognitionBackend { backend }

    var debugMinimapEnabled: Bool { minimapEnabled }

    var debugTitleBarVisible: Bool { titleBarVisible }

    var debugFileInfoVisible: Bool { fileInfoVisible }

    var debugToolbarVisible: Bool { toolbarVisible }

    var debugImageParametersVisible: Bool { imageParametersVisible }

    var debugFixedWindowEnabled: Bool { fixedWindowEnabled }

    var debugHasRotationAnimation: Bool {
        imageView.layer?.animation(forKey: Self.rotationAnimationKey) != nil
    }

    func debugApplyToolbarZoom(multiplier: CGFloat) {
        applyToolbarZoom(request: ImageZoomRequest(id: -1, multiplier: multiplier))
    }

    func debugAdjustedLiveTextControlFrame(for frame: CGRect) -> CGRect? {
        guard backend == .liveText else { return nil }
        return Self.adjustedLiveTextControlFrame(for: frame, in: bounds, reservedSize: bottomRightResizeRegionSize + resizeAvoidancePadding)
    }

    func debugCanDragWindow(at point: CGPoint) -> Bool {
        isInTopDragRegion(point)
    }

    func debugShouldToggleDesktopFillOnMouseDown(clickCount: Int, at point: CGPoint) -> Bool {
        shouldToggleDesktopFillOnMouseDown(clickCount: clickCount, at: point)
    }

    var debugLiveTextAnalysis: ImageAnalysis? {
        liveTextOverlay.analysis
    }

    func debugWaitForAnalysis(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while liveTextOverlay.analysis == nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return liveTextOverlay.analysis != nil
    }

    var debugRecognizedLineCount: Int {
        recognizedLines.count
    }

    func debugWaitForVisionRecognition(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while recognizedLines.isEmpty && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return !recognizedLines.isEmpty
    }

    func debugRecognizedTexts() -> [String] {
        recognizedLines.map(\.text)
    }

    func debugLineRects() -> [CGRect] {
        let geometry = currentGeometry()
        return recognizedLines.map { lineRectInView($0, geometry: geometry) }
    }

    func debugFragmentRects(forLine lineIndex: Int) -> [CGRect] {
        let geometry = currentGeometry()
        guard recognizedLines.indices.contains(lineIndex) else { return [] }
        return recognizedLines[lineIndex].fragments.map { fragmentRectInView($0, geometry: geometry) }
    }

    func debugHitTextIndex(at point: CGPoint) -> Int? {
        hitTextLocation(at: point, geometry: currentGeometry())?.lineIndex
    }

    @discardableResult
    func debugSelectText(from start: CGPoint, to end: CGPoint) -> Bool {
        let geometry = currentGeometry()
        guard let anchor = hitTextLocation(at: start, geometry: geometry) else {
            return false
        }
        selectionAnchorLocation = anchor
        selectionFocusLocation = nearestTextLocation(to: end, geometry: geometry) ?? anchor
        updateSelectedTextRange()
        return true
    }

    func debugSelectedText() -> String {
        currentlySelectedText()
    }

    @discardableResult
    func debugCopySelectedText() -> Bool {
        copySelectedTextToPasteboard()
    }

    func debugAppendPicSeeContextMenuItems(to menu: NSMenu) {
        appendPicSeeContextMenuItems(to: menu)
    }

    static func debugDefaultExportFilename(for url: URL?) -> String {
        defaultExportFilename(for: url)
    }
}
#endif
