import AppKit
import Combine
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import Vision
@preconcurrency import VisionKit

struct ImageCanvasView: NSViewRepresentable {
    let image: NSImage
    let imageURL: URL
    let displayMode: ImageDisplayMode
    let defaultDisplayRequestID: Int
    @Binding var zoomScale: CGFloat
    @Binding var panOffset: CGSize
    @Binding var rotationDegrees: Int
    @Binding var zoomRequest: ImageZoomRequest?
    let transformAnimationID: Int
    let navigationDirection: Int?
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onRotateLeft: () -> Void
    let onRotateRight: () -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onReset: () -> Void
    let onDefaultDisplayModeRequested: (ImageDisplayMode) -> Void
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
    var windowLongPressEnabled = true
    var canTrashImage = false
    var canUndoDeletion = false
    var onTrashImage: (() -> Void)?
    var onUndoDeletion: (() -> Void)?
    var slideshow: SlideshowController?
    var onStartSlideshow: (() -> Void)?

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        view.windowLongPressEnabled = windowLongPressEnabled
        view.displayMode = displayMode
        view.defaultDisplayRequestID = defaultDisplayRequestID
        view.setImage(image, url: imageURL)
        view.titleBarVisible = titleBarVisible
        view.fileInfoVisible = fileInfoVisible
        view.toolbarVisible = toolbarVisible
        view.imageParametersVisible = imageParametersVisible
        view.fixedWindowEnabled = fixedWindowEnabled
        view.rotationDegrees = rotationDegrees
        view.onPrevious = onPrevious
        view.onNext = onNext
        view.onRotateLeft = onRotateLeft
        view.onRotateRight = onRotateRight
        view.onZoomIn = onZoomIn
        view.onZoomOut = onZoomOut
        view.onReset = onReset
        view.onDefaultDisplayModeRequested = onDefaultDisplayModeRequested
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
        view.canTrashImage = canTrashImage
        view.canUndoDeletion = canUndoDeletion
        view.onTrashImage = onTrashImage
        view.onUndoDeletion = onUndoDeletion
        view.slideshow = slideshow
        view.onStartSlideshow = onStartSlideshow
        return view
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.windowLongPressEnabled = windowLongPressEnabled
        nsView.navigationDirection = navigationDirection
        let imageChanged = nsView.image !== image
        nsView.setImage(image, url: imageURL)
        nsView.updateTransform(zoom: zoomScale, pan: panOffset, rotation: rotationDegrees,
                               animationID: transformAnimationID, imageChanged: imageChanged, displayMode: displayMode,
                               defaultDisplayRequestID: defaultDisplayRequestID)
        nsView.onPrevious = onPrevious
        nsView.onNext = onNext
        nsView.onRotateLeft = onRotateLeft
        nsView.onRotateRight = onRotateRight
        nsView.onZoomIn = onZoomIn
        nsView.onZoomOut = onZoomOut
        nsView.onReset = onReset
        nsView.onDefaultDisplayModeRequested = onDefaultDisplayModeRequested
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
        nsView.canTrashImage = canTrashImage
        nsView.canUndoDeletion = canUndoDeletion
        nsView.onTrashImage = onTrashImage
        nsView.onUndoDeletion = onUndoDeletion
        nsView.slideshow = slideshow
        nsView.onStartSlideshow = onStartSlideshow
        if let zoomRequest {
            // The command writes SwiftUI bindings. Apply it after this representable update.
            DispatchQueue.main.async { [weak nsView] in
                guard let nsView, nsView.image === image else { return }
                nsView.applyToolbarZoom(request: zoomRequest)
            }
        }
        nsView.needsDisplay = true
    }
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
        didSet {
            if oldValue !== image {
                showsTransparencyBackground = image.map { TransparencyBackground.needsCheckerboard(for: $0) } ?? false
            }
            needsDisplay = true
        }
    }
    private var showsTransparencyBackground = false

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
        if showsTransparencyBackground {
            TransparencyBackground.draw(in: contentRect)
        }
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
    private static let labelColumnWidth: CGFloat = 94
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
    private let exportImage: NSImage?
    private let fileSizeField = NSTextField(labelWithString: "—")
    private let sizeCalculator = ImageExportSizeCalculator()
    private var sizeTask: Task<Void, Never>?
    private var sizeRevision = 0
    private var labels: [NSTextField] = []
    private var qualityLabel: NSTextField?
    private var gridView: NSGridView?
    private var gridLeadingConstraint: NSLayoutConstraint?
    private var pixelUnitLabels: [NSTextField] = []
    private var pixelInputStacks: [NSStackView] = []
    var onFormatChanged: ((ImageExportFormat) -> Void)?

    init(defaultPixelSize: CGSize?, image: NSImage? = nil) {
        self.exportImage = image
        self.defaultPixelSize = defaultPixelSize
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 222))
        qualitySlider.target = self
        qualitySlider.action = #selector(qualityChanged(_:))
        qualitySlider.isContinuous = true
        fileSizeField.textColor = .secondaryLabelColor
        formatPopup.addItems(withTitles: ["JPEG", "PNG"])
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged(_:))
        resizeModePopup.addItems(withTitles: [L10n.text("固定尺寸"), L10n.text("按宽等比"), L10n.text("按高等比")])
        resizeModePopup.target = self
        resizeModePopup.action = #selector(resizeModeChanged(_:))

        widthField.placeholderString = L10n.text("宽")
        heightField.placeholderString = L10n.text("高")
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

        let labels = [L10n.text("格式:"), L10n.text("尺寸模式:"), L10n.text("宽度:"), L10n.text("高度:"), L10n.text("JPEG 质量:"), L10n.text("预计大小:")].map(Self.label)
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
            [labels[5], fileSizeField],
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
        scheduleSizeCalculation()
        LanguageSettings.bind(self) { accessory in
            for (item, title) in zip(accessory.resizeModePopup.itemArray,
                                    [L10n.text("固定尺寸"), L10n.text("按宽等比"), L10n.text("按高等比")]) {
                item.title = title
            }
            accessory.widthField.placeholderString = L10n.text("宽")
            accessory.heightField.placeholderString = L10n.text("高")
            for (label, text) in zip(accessory.labels, [L10n.text("格式:"), L10n.text("尺寸模式:"), L10n.text("宽度:"), L10n.text("高度:"), L10n.text("JPEG 质量:"), L10n.text("预计大小:")]) {
                label.stringValue = text
            }
        }
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
        scheduleSizeCalculation()
    }

    @objc private func resizeModeChanged(_ sender: Any?) {
        updateResizeControls()
        updateProportionalSize(changedField: nil)
        scheduleSizeCalculation()
    }

    @objc private func sizeFieldChanged(_ sender: Any?) {
        updateProportionalSize(changedField: sender as? NSTextField)
        scheduleSizeCalculation()
    }

    @objc private func qualityChanged(_ sender: Any?) {
        scheduleSizeCalculation()
    }

    private func scheduleSizeCalculation() {
        sizeRevision += 1
        guard let exportImage else { return }
        fileSizeField.stringValue = L10n.text("计算中…")
        // Coalesce changes while an encode is running, but keep updating during a drag.
        guard sizeTask == nil else { return }
        let calculator = sizeCalculator
        sizeTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
                guard let revision = self?.sizeRevision, let options = self?.exportOptions else { return }
                let count = try? await calculator.byteCount(for: exportImage, options: options)
                guard !Task.isCancelled, let self else { return }
                guard self.sizeRevision == revision else { continue }
                if let count {
                    self.fileSizeField.stringValue = ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
                } else {
                    self.fileSizeField.stringValue = L10n.text("无法计算")
                }
                self.sizeTask = nil
                return
            }
        }
    }

    func cancelSizeCalculation() {
        sizeTask?.cancel()
        sizeTask = nil
        sizeRevision += 1
    }

    private func updateFormatControls() {
        let showQualityControls: Bool
        if case .png = selectedFormat {
            showQualityControls = false
        } else {
            showQualityControls = true
        }

        // Preserve the grid geometry: hiding an NSGridRow makes NSSavePanel
        // relayout and can shift the accessory horizontally when switching formats.
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
    var debugQualityRowHidden: Bool { gridView?.row(at: 5).isHidden ?? false }

    var debugEstimatedSizeText: String { fileSizeField.stringValue }

    func debugSetQuality(_ quality: Double) {
        qualitySlider.doubleValue = quality
        qualityChanged(nil)
    }

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

final class CanvasNSView: NSView, NSMenuItemValidation {
    private static let rotationAnimationKey = "PicSee.RotationAnimation"
    private static let themeMenuIdentifier = NSUserInterfaceItemIdentifier("PicSee.ThemeMenu")

    private let imageView = NSImageView(frame: .zero)
    private var imageDetailLayer: LargeImageTileLayer?
    private var isSettingWallpaper = false
    private let desktopWallpaperRequest = DesktopWallpaperRequest()
    var applyDesktopWallpaper: (NSImage, NSScreen) async throws -> Void = { image, screen in
        try await DesktopWallpaperSetter().set(image) { url in
            let workspace = NSWorkspace.shared
            try workspace.setDesktopImageURL(
                url, for: screen, options: workspace.desktopImageOptions(for: screen) ?? [:]
            )
        }
    }
    private let transparencyBackground = TransparencyBackgroundView(frame: .zero)
    private let outgoingTransparencyBackground = TransparencyBackgroundView(frame: .zero)
    // Animate a container, leaving the image's rotation and AppKit layout independent.
    private let imageMotionView = NSView(frame: .zero)
    private let outgoingImageView = NSImageView(frame: .zero)
    private static let transformAnimationKey = "PicSee.ZoomAnimation"
    private var transformMotion: TransformMotion?
    private static let navigationAnimationKey = "PicSee.NavigationAnimation"
    private var handledTransformAnimationID = 0
    private var navigationToken = 0
    private var pendingNavigationAnimation = false
    private var lastNavigationTime: CFTimeInterval?
    private var navigationAnimationEnabled = true
    private var mouseWheelBehavior: MouseWheelBehavior = .zoom
    private var smallImageMode: FullScreenSmallImageMode = .original
    private var maximumSmallImageScale: Double = 2
    var navigationTime: () -> CFTimeInterval = { CACurrentMediaTime() }
    var navigationDirection: Int?
    var motionPreference: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var reduceMotion: Bool { motionPreference() }

    private let minimapView = ImageMinimapView(frame: .zero)
    private let backend: TextRecognitionBackend
    private let defaults: UserDefaults
    private let preferences: ViewerPreferences
    private var preferenceObservation: AnyCancellable?
    private var slideshowWindowObservations: Set<AnyCancellable> = []

    // Live Text path
    private let liveTextOverlay = ImageAnalysisOverlayView()
    private let textRecognizer = ImageTextRecognizer()
    private var isUpdatingImage = false

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

    private var imagePixelSize: CGSize = .zero
    private var alignsImageToTop = false
    // A fresh request restores top alignment even if the mode itself is unchanged.
    var defaultDisplayRequestID = 0 {
        didSet {
            guard oldValue != defaultDisplayRequestID else { return }
            alignsImageToTop = displayMode.startsOverflowAtTop
            needsLayout = true
        }
    }
    var displayMode: ImageDisplayMode = .fitWindow {
        didSet {
            guard oldValue != displayMode else { return }
            alignsImageToTop = displayMode.startsOverflowAtTop
            needsLayout = true
        }
    }

    var image: NSImage? {
        didSet {
            let imageChanged = oldValue !== image
            if imageChanged {
                cancelImageDragCandidate()
                cancelCloseGesture()
                prepareImageTransition()
                imagePixelSize = image.flatMap { ImageExporter.pixelSize(of: $0) } ?? image?.size ?? .zero
                imageView.layer?.removeAnimation(forKey: Self.rotationAnimationKey)
                transparencyBackground.imageMask.removeAnimation(forKey: Self.rotationAnimationKey)
                pendingRotationAnimation = nil
                rotationDegrees = 0
                pendingRotationAnimation = nil
                zoomScale = 1
                panOffset = .zero
                alignsImageToTop = displayMode.startsOverflowAtTop
                resetTextSelectionState()
            }
            imageView.image = image
            if imageChanged {
                imageDetailLayer?.setActive(false)
                imageDetailLayer?.removeFromSuperlayer()
                imageDetailLayer?.source?.discardDetailCache()
                imageDetailLayer = nil
                if let large = image?.largeImageSource {
                    let tiles = LargeImageTileLayer(source: large)
                    imageView.layer?.addSublayer(tiles)
                    imageDetailLayer = tiles
                }
                transparencyBackground.isHidden = image.map { !TransparencyBackground.needsCheckerboard(for: $0) } ?? true
                if !isUpdatingImage { analyzeImageIfPossible() }
            }
            needsLayout = true
            needsDisplay = true
        }
    }

    var imageURL: URL? {
        didSet {
            guard oldValue != imageURL else { return }
            cancelImageDragCandidate()
            if image != nil {
                if !isUpdatingImage { analyzeImageIfPossible() }
            }
        }
    }

    func setImage(_ newImage: NSImage, url: URL) {
        let changed = image !== newImage || imageURL != url
        isUpdatingImage = true
        imageURL = url
        image = newImage
        isUpdatingImage = false
        if changed {
            alignsImageToTop = displayMode.startsOverflowAtTop
            analyzeImageIfPossible()
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
                alignsImageToTop = false
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
    var onRotateLeft: (() -> Void)?
    var onRotateRight: (() -> Void)?
    var onZoomIn: (() -> Void)?
    var onZoomOut: (() -> Void)?
    var onReset: (() -> Void)?
    var onDefaultDisplayModeRequested: ((ImageDisplayMode) -> Void)?
    var onClose: (() -> Void)?
    var canTrashImage = false
    var canUndoDeletion = false
    var onTrashImage: (() -> Void)?
    var onUndoDeletion: (() -> Void)?
    var slideshow: SlideshowController?
    var onStartSlideshow: (() -> Void)?
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
        case fileExport
    }

    // Keep the trial interaction's tuning in one place (screen points).
    private enum WindowLongPress {
        static let duration: TimeInterval = 0.6
        static let movementTolerance: CGFloat = 4
    }
    // A centered four-way arrow distinguishes window movement from image panning.
    private static let windowMoveCursor: NSCursor = {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size, flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform()
            transform.scale(by: size.width / 28)
            transform.concat()
            let points: [CGPoint] = [
                CGPoint(x: 14, y: 26), CGPoint(x: 19, y: 21), CGPoint(x: 16, y: 21),
                CGPoint(x: 16, y: 16), CGPoint(x: 21, y: 16), CGPoint(x: 21, y: 19),
                CGPoint(x: 26, y: 14), CGPoint(x: 21, y: 9), CGPoint(x: 21, y: 12),
                CGPoint(x: 16, y: 12), CGPoint(x: 16, y: 7), CGPoint(x: 19, y: 7),
                CGPoint(x: 14, y: 2), CGPoint(x: 9, y: 7), CGPoint(x: 12, y: 7),
                CGPoint(x: 12, y: 12), CGPoint(x: 7, y: 12), CGPoint(x: 7, y: 9),
                CGPoint(x: 2, y: 14), CGPoint(x: 7, y: 19), CGPoint(x: 7, y: 16),
                CGPoint(x: 12, y: 16), CGPoint(x: 12, y: 21), CGPoint(x: 9, y: 21)
            ]
            let path = NSBezierPath()
            path.move(to: points[0])
            for point in points.dropFirst() { path.line(to: point) }
            path.close()
            path.lineWidth = 2.5
            path.lineJoinStyle = .round
            // A white border keeps the black arrow visible over dark images.
            NSColor.white.setStroke()
            path.stroke()
            NSColor.black.setFill()
            path.fill()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }()

    var windowLongPressEnabled = true {
        didSet { if !windowLongPressEnabled { resetMouseDrag() } }
    }
    private var windowLongPressTimer: Timer?
    private var windowLongPressStart: CGPoint?
    private var isLongPressMovingWindow = false
    private var hasStartedLongPressWindowDrag = false
    private var windowMoveCursorTimer: Timer?
    private var windowLongPressMonitor: Any?

    var fileDragController = ImageFileDragController()
    private var fileDragStartScreenPoint: CGPoint?
    private var dragType: DragType = .none
    private var dragStartPoint: NSPoint?
    private var dragStartWindowFrame: NSRect?
    private var dragStartOffset: CGSize = .zero
    private var lastReportedDisplayScale: CGFloat = -1
    private var trackingArea: NSTrackingArea?
    private var closeGestureMonitor: Any?
    private var closeGesture: ImageCloseGesture?
    private var closeGestureDownEvent: NSEvent?
    private weak var closeGestureMenuView: NSView?
    private let closeGestureOverlay = ImageCloseGestureOverlay(frame: .zero)
    private var closeGestureEnabled = false
    #if DEBUG
    var debugCloseGestureMenuPresenter: ((NSMenu, NSEvent, NSView) -> Void)?
    #endif
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
    var fixedWindowEnabled: Bool {
        didSet {
            guard oldValue != fixedWindowEnabled else { return }
            needsLayout = true
            window?.invalidateCursorRects(for: self)
        }
    }

    private let topDragRegionHeight: CGFloat = 36
    private let topLeftResizeRegionSize: CGFloat = 44
    private let bottomRightResizeRegionSize: CGFloat = 20
    private let resizeAvoidancePadding: CGFloat = 4
    private var minimumWindowSize: NSSize {
        AutomaticWindowSizePreference.isEnabled(in: defaults) && !fixedWindowEnabled
            ? WindowPlacement.minimumAutomaticContentSize
            : NSSize(width: 320, height: 220)
    }
    private let minimapMaxSize = CGSize(width: 140, height: 100)
    private let minimapPadding: CGFloat = 12

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(frame frameRect: NSRect, backend: TextRecognitionBackend, defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
        self.preferences = defaults === UserDefaults.standard ? .shared : ViewerPreferences(defaults: defaults)
        self.minimapEnabled = Self.defaultMinimapEnabled(in: defaults)
        self.titleBarVisible = ViewerTitleBarPreference.isVisible(in: defaults)
        self.fileInfoVisible = ViewerOverlayPreference.isFileInfoVisible(in: defaults)
        self.toolbarVisible = ViewerOverlayPreference.isToolbarVisible(in: defaults)
        self.imageParametersVisible = ViewerOverlayPreference.isImageParametersVisible(in: defaults)
        self.fixedWindowEnabled = WindowFramePreference.isFixedEnabled(in: defaults)
        super.init(frame: frameRect)
        configureSubviews()
        observePreferences()
    }

    override convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, backend: .preferred)
    }

    required init?(coder: NSCoder) {
        self.backend = .preferred
        self.defaults = .standard
        self.preferences = .shared
        self.minimapEnabled = Self.defaultMinimapEnabled(in: .standard)
        self.titleBarVisible = ViewerTitleBarPreference.isVisible(in: .standard)
        self.fileInfoVisible = ViewerOverlayPreference.isFileInfoVisible(in: .standard)
        self.toolbarVisible = ViewerOverlayPreference.isToolbarVisible(in: .standard)
        self.imageParametersVisible = ViewerOverlayPreference.isImageParametersVisible(in: .standard)
        self.fixedWindowEnabled = WindowFramePreference.isFixedEnabled(in: .standard)
        super.init(coder: coder)
        configureSubviews()
        observePreferences()
    }

    private static func defaultMinimapEnabled(in defaults: UserDefaults) -> Bool {
        ViewerOverlayPreference.isMinimapEnabled(in: defaults)
    }

    private func observePreferences() {
        applyPreferences(preferences.snapshot)
        preferenceObservation = preferences.$snapshot.dropFirst().sink { [weak self] snapshot in
            self?.applyPreferences(snapshot)
        }
    }

    private func applyPreferences(_ snapshot: ViewerPreferencesSnapshot) {
        mouseWheelBehavior = snapshot.mouseWheelBehavior
        if smallImageMode != snapshot.fullScreenSmallImageMode || maximumSmallImageScale != snapshot.maximumSmallImageScale {
            interruptMotion()
            smallImageMode = snapshot.fullScreenSmallImageMode
            maximumSmallImageScale = snapshot.maximumSmallImageScale
        }
        if navigationAnimationEnabled != snapshot.imageNavigationAnimationEnabled {
            navigationAnimationEnabled = snapshot.imageNavigationAnimationEnabled
            lastNavigationTime = nil
            if !navigationAnimationEnabled { cancelNavigationAnimation() }
        }
        titleBarVisible = snapshot.titleBarVisible
        minimapEnabled = snapshot.minimapEnabled
        fileInfoVisible = snapshot.fileInfoVisible
        toolbarVisible = snapshot.toolbarVisible
        imageParametersVisible = snapshot.imageParametersVisible
        fixedWindowEnabled = snapshot.fixedWindowEnabled
        closeGestureEnabled = snapshot.rightMouseCloseGestureEnabled
        if !closeGestureEnabled { cancelCloseGesture() }
        window?.appearance = snapshot.theme.appearance
        needsLayout = true
        window?.invalidateCursorRects(for: self)
    }

    private static func normalizedRotationDegrees(_ degrees: Int) -> Int {
        ((degrees % 360) + 360) % 360
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
        if let closeGestureMonitor { NSEvent.removeMonitor(closeGestureMonitor) }
        closeGestureMonitor = nil
        resetCloseGesture()
        resetMouseDrag()
        if let windowLongPressMonitor { NSEvent.removeMonitor(windowLongPressMonitor) }
        windowLongPressMonitor = nil
        window?.acceptsMouseMovedEvents = true
        slideshowWindowObservations.removeAll()
        guard let window else { return }
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            NotificationCenter.default.publisher(for: name, object: window)
                .sink { [weak self] _ in
                    self?.interruptMotion()
                    self?.resetMouseDrag()
                    self?.needsLayout = true
                }
                .store(in: &slideshowWindowObservations)
        }
        windowLongPressMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            return self.handleWindowLongPressEvent(event)
        }
        closeGestureEnabled = preferences.snapshot.rightMouseCloseGestureEnabled
        closeGestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseDragged, .rightMouseUp, .keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleCloseGestureEvent(event)
        }
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: window)
            .sink { [weak self] _ in
                guard let self else { return }
                if let monitor = self.closeGestureMonitor { NSEvent.removeMonitor(monitor) }
                self.closeGestureMonitor = nil
                self.resetCloseGesture()
                self.resetMouseDrag()
                if let monitor = self.windowLongPressMonitor { NSEvent.removeMonitor(monitor) }
                self.windowLongPressMonitor = nil
            }
            .store(in: &slideshowWindowObservations)
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: window)
            .sink { [weak self] _ in
                self?.slideshow?.pauseForWindowDeactivation()
                self?.cancelCloseGesture()
                self?.resetMouseDrag()
            }
            .store(in: &slideshowWindowObservations)
        NotificationCenter.default.publisher(for: NSWindow.willBeginSheetNotification, object: window)
            .sink { [weak self] _ in
                self?.slideshow?.pause()
                self?.cancelCloseGesture()
                self?.resetMouseDrag()
            }
            .store(in: &slideshowWindowObservations)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        interruptMotion()
        needsLayout = true
    }

    /// Observe Live Text presses without withholding events from its selection handlers.
    private func handleWindowLongPressEvent(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else { return event }
        if event.type == .leftMouseDown {
            if let content = window.contentView,
               let hit = content.hitTest(content.convert(event.locationInWindow, from: nil)),
               hit === liveTextOverlay || hit.isDescendant(of: liveTextOverlay) {
                armWindowLongPress(with: event)
            }
        } else if event.type == .leftMouseDragged {
            if isLongPressMovingWindow {
                mouseDragged(with: event)
                return nil
            }
            updateWindowLongPressMovement(with: event)
        } else if event.type == .leftMouseUp {
            // Let Live Text receive its release too, even after a takeover.
            if isLongPressMovingWindow { resetMouseDrag() }
            cancelWindowLongPressCandidate()
        }
        return event
    }

    private func armWindowLongPress(with event: NSEvent) {
        cancelWindowLongPressCandidate()
        let point = convert(event.locationInWindow, from: nil)
        guard event.type == .leftMouseDown, event.clickCount == 1,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              windowLongPressEnabled, image != nil, let window,
              window.attachedSheet == nil, !window.styleMask.contains(.fullScreen),
              bounds.insetBy(dx: 4, dy: 4).contains(point), resizeAnchor(at: point) == nil, !isInTopDragRegion(point),
              let content = window.contentView,
              let hit = content.hitTest(content.convert(event.locationInWindow, from: nil)),
              isCloseGestureImageHit(hit),
              hit !== minimapView, !hit.isDescendant(of: minimapView),
              !liveTextOverlay.hasSupplementaryInterface(at: liveTextOverlay.convert(event.locationInWindow, from: nil))
        else { return }
        windowLongPressStart = window.convertPoint(toScreen: event.locationInWindow)
        let timer = Timer(timeInterval: WindowLongPress.duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                self.activateWindowLongPress(at: NSEvent.mouseLocation, leftButtonDown: NSEvent.pressedMouseButtons & 1 != 0,
                                             window: window)
            }
        }
        windowLongPressTimer = timer
        // Live Text can run an AppKit event tracking loop while selecting.
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateWindowLongPressMovement(with event: NSEvent) {
        guard let start = windowLongPressStart, let window else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        if hypot(point.x - start.x, point.y - start.y) > WindowLongPress.movementTolerance {
            cancelWindowLongPressCandidate()
        }
    }

    private func activateWindowLongPress(at point: CGPoint, leftButtonDown: Bool, window: NSWindow) {
        guard let start = windowLongPressStart else { return }
        let shouldActivate = leftButtonDown && windowLongPressEnabled && window.attachedSheet == nil
            && !window.styleMask.contains(.fullScreen)
            && hypot(point.x - start.x, point.y - start.y) <= WindowLongPress.movementTolerance
        cancelWindowLongPressCandidate()
        guard shouldActivate else { return }
        fileDragStartScreenPoint = nil
        selectionAnchorLocation = nil
        selectionFocusLocation = nil
        liveTextOverlay.resetSelection()
        clearTextSelection()
        dragType = .window
        isLongPressMovingWindow = true
        Self.windowMoveCursor.set()
        // performDrag returns immediately and may consume mouse-up. Poll the actual
        // button state so the cursor stays active until release in either case.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateWindowMoveCursor(leftButtonDown: NSEvent.pressedMouseButtons & 1 != 0)
            }
        }
        windowMoveCursorTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateWindowMoveCursor(leftButtonDown: Bool) {
        guard isLongPressMovingWindow else { return }
        if leftButtonDown {
            Self.windowMoveCursor.set()
        } else {
            resetMouseDrag()
        }
    }

    private func cancelWindowLongPressCandidate() {
        windowLongPressTimer?.invalidate()
        windowLongPressTimer = nil
        windowLongPressStart = nil
    }

    /// Intercept before Live Text or a child image view opens its context menu.
    /// Controls and other windows remain outside the gesture's scope.
    private func handleCloseGestureEvent(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else { return event }
        if event.type == .keyDown {
            guard closeGesture != nil, event.keyCode == 53 else { return event }
            cancelCloseGesture()
            return nil
        }
        let point = convert(event.locationInWindow, from: nil)
        if event.type == .rightMouseDown {
            guard closeGestureEnabled, window.attachedSheet == nil, bounds.contains(point),
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                  let content = window.contentView,
                  let hit = content.hitTest(content.convert(event.locationInWindow, from: nil)),
                  isCloseGestureImageHit(hit) else { return event }
            slideshow?.pause()
            interruptMotion()
            closeGesture = ImageCloseGesture(start: point)
            closeGestureDownEvent = event
            closeGestureMenuView = hit
            closeGestureOverlay.frame = bounds
            closeGestureOverlay.autoresizingMask = [.width, .height]
            addSubview(closeGestureOverlay, positioned: .above, relativeTo: nil)
            return nil
        }
        guard closeGesture != nil else { return event }
        if event.type == .rightMouseDragged || event.type == .rightMouseUp {
            closeGesture?.move(to: point)
            if !bounds.contains(point) || window.attachedSheet != nil { closeGesture?.cancel() }
            closeGestureOverlay.gesture = closeGesture
        }
        guard event.type == .rightMouseUp else { return nil }
        let result = closeGesture?.result
        let down = closeGestureDownEvent ?? event
        let menuView = closeGestureMenuView ?? self
        resetCloseGesture()
        switch result {
        case .close: window.close()
        case .menu:
            if let menu = menuView.menu(for: down) ?? menu(for: down) {
                presentCloseGestureMenu(menu, event: event, view: menuView)
            }
        default: break
        }
        return nil
    }

    private func isCloseGestureImageHit(_ hit: NSView) -> Bool {
        var current: NSView? = hit
        while let view = current {
            if view is NSControl, !(view is NSImageView) { return false }
            if view === self { return true }
            current = view.superview
        }
        return false
    }

    private func presentCloseGestureMenu(_ menu: NSMenu, event: NSEvent, view: NSView) {
        #if DEBUG
        if let presenter = debugCloseGestureMenuPresenter {
            presenter(menu, event, view)
            return
        }
        #endif
        _ = menu.popUp(positioning: nil, at: view.convert(event.locationInWindow, from: nil), in: view)
    }

    private func cancelCloseGesture() {
        closeGesture?.cancel()
        closeGestureOverlay.removeFromSuperview()
    }

    private func resetCloseGesture() {
        closeGesture = nil
        closeGestureDownEvent = nil
        closeGestureMenuView = nil
        closeGestureOverlay.gesture = nil
        closeGestureOverlay.removeFromSuperview()
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
        prepareDefaultDisplayLayout()
        let geometry = currentGeometry()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageMotionView.frame = bounds
        transparencyBackground.frame = bounds
        outgoingTransparencyBackground.frame = bounds
        imageMotionView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        imageMotionView.layer?.position = CGPoint(x: bounds.midX, y: bounds.midY)
        imageView.frame = geometry.unrotatedImageRect
        imageView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        imageView.layer?.position = CGPoint(x: geometry.imageRect.midX, y: geometry.imageRect.midY)
        if let tiles = imageDetailLayer, let source = tiles.source {
            tiles.bounds = CGRect(origin: .zero, size: source.pixelSize)
            tiles.anchorPoint = .zero
            tiles.position = .zero
            tiles.setAffineTransform(CGAffineTransform(scaleX: imageView.bounds.width / source.pixelSize.width,
                                                       y: imageView.bounds.height / source.pixelSize.height))
            let scale = window?.backingScaleFactor ?? 1
            let fitsPreview = imageView.bounds.width * scale <= CGFloat(source.preview.width)
                && imageView.bounds.height * scale <= CGFloat(source.preview.height)
            let hidden = (displayMode == .fitWindow && geometry.zoomScale <= 1.001) || fitsPreview
            if hidden && !tiles.isHidden { source.discardDetailCache() }
            let becomingVisible = tiles.isHidden && !hidden
            tiles.setActive(!hidden)
            tiles.isHidden = hidden
            // Semitransparent native tiles must not composite over the same
            // semitransparent preview. Opaque photos keep the loading fallback.
            let preview = source.hasAlpha && !hidden ? nil : image
            if imageView.image !== preview { imageView.image = preview }
            if becomingVisible { tiles.setNeedsDisplay() }
        }
        applyImageRotation()
        if let imageLayer = imageView.layer {
            transparencyBackground.synchronize(imageLayer: imageLayer, motionLayer: imageMotionView.layer)
        }
        CATransaction.commit()
        if pendingNavigationAnimation {
            pendingNavigationAnimation = false
            animateImageTransition()
        }
        switch backend {
        case .liveText:
            liveTextOverlay.frame = imageView.bounds
            liveTextOverlay.layer?.zPosition = 2
            repositionLiveTextControlsIfNeeded()
        case .vision:
            selectionOverlayView.frame = bounds
            updateSelectionOverlay()
        }
        updateMinimap(geometry: geometry)
        reportDisplayScaleIfNeeded(geometry.pixelDisplayScale)
    }

    private func prepareDefaultDisplayLayout() {
        guard displayMode != .fitWindow, image != nil, bounds.width > 0, bounds.height > 0 else { return }
        let geometry = currentGeometry()
        let nextPan = alignsImageToTop
            ? CGSize(width: 0, height: -max(0, (geometry.displaySize.height - bounds.height) / 2))
            : geometry.constrainedPan(panOffset, allowSlackWhenFitted: panImageMode(geometry))
        guard nextPan != panOffset else { return }
        panOffset = nextPan
        let requestedImage = image
        let requestedURL = imageURL
        // Layout can run during a SwiftUI update; publish after that update.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.image === requestedImage, self.imageURL == requestedURL,
                  self.panOffset == nextPan else { return }
            self.onPanChanged?(nextPan)
        }
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
        // SwiftUI probes the canvas while routing toolbar clicks too. Hit testing
        // must not change image state; interrupt only when an interaction begins.
        let localPoint = convert(point, from: superview)
        if let control = interactiveControlHit(at: localPoint) { return control }
        if resizeAnchor(at: localPoint) != nil {
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
        slideshow?.pause()
        interruptMotion()
        let isTrackpad = event.hasPreciseScrollingDeltas && (event.phase != [] || event.momentumPhase != [])
        if !isTrackpad, mouseWheelBehavior == .scroll {
            let geometry = currentGeometry()
            guard geometry.displaySize.height > geometry.viewportSize.height else { return }
            // Discrete wheel deltas are in lines; precise devices already supply points.
            let distance = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 16)
            guard distance != 0 else { return }
            alignsImageToTop = false
            panOffset.height = geometry.constrainedPan(
                CGSize(width: panOffset.width, height: panOffset.height - distance)
            ).height
            onPanChanged?(panOffset)
            needsLayout = true
            return
        }
        if isTrackpad, panImageMode(currentGeometry()) {
            alignsImageToTop = false
            panOffset = constrainPan(
                CGSize(width: panOffset.width + event.scrollingDeltaX, height: panOffset.height - event.scrollingDeltaY),
                geometry: currentGeometry()
            )
            onPanChanged?(panOffset)
            needsLayout = true
            return
        }
        let delta = event.scrollingDeltaY == 0 ? -event.scrollingDeltaX : event.scrollingDeltaY
        guard delta != 0 else { return }
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 0.0018 : 0.018
        let multiplier = exp(abs(delta) * step)
        applyZoom(multiplier: delta > 0 ? multiplier : 1 / multiplier, anchorPoint: zoomAnchor(for: event))
    }

    override func magnify(with event: NSEvent) {
        slideshow?.pause()
        interruptMotion()
        guard event.magnification != 0 else { return }
        applyZoom(multiplier: 1 + event.magnification, anchorPoint: zoomAnchor(for: event))
    }

    func applyToolbarZoom(request: ImageZoomRequest) {
        guard handledZoomRequestID != request.id else { return }
        handledZoomRequestID = request.id
        let visual = visualTransform()
        let velocity = imageMotionView.layer?.animation(forKey: Self.transformAnimationKey) != nil
            ? transformMotion?.zoomVelocity(at: visual.zoomScale) ?? 0 : 0
        cancelNavigationAnimation()
        applyZoom(multiplier: request.multiplier)
        animateTransform(from: visual, duration: 0.18, timing: .easeInEaseOut, initialZoomVelocity: velocity)
        onZoomRequestHandled?(request.id)
    }

    private func zoomAnchor(for event: NSEvent) -> CGPoint? {
        let point = convert(event.locationInWindow, from: nil)
        guard point.x.isFinite, point.y.isFinite, bounds.contains(point) else { return nil }
        return CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
    }

    private func applyZoom(multiplier: CGFloat, anchorPoint: CGPoint? = nil) {
        alignsImageToTop = false
        let geometry = currentGeometry()
        let adjustment = ImageZoomAdjustment.adjustment(
            from: geometry,
            multiplier: multiplier,
            anchorPoint: anchorPoint
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
        guard !fileDragController.isDragging else { return }
        slideshow?.pause()
        interruptMotion()
        let geometry = currentGeometry()
        let point = convert(event.locationInWindow, from: nil)

        resetMouseDrag()

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
            let isFitted = displayMode == .fitWindow && abs(zoomScale - 1) < 0.001 && abs(panOffset.width) < 0.5 && abs(panOffset.height) < 0.5
            if isFitted {
                window?.toggleFullScreen(nil)
            } else {
                let visual = visualTransform()
                let previousBaseScale = currentGeometry().fitScale
                displayMode = .fitWindow
                zoomScale = 1
                panOffset = .zero
                onZoomChanged?(1)
                onPanChanged?(.zero)
                onReset?()
                let adjustedVisual = ImageZoomAdjustment(
                    zoomScale: visual.zoomScale * previousBaseScale / currentGeometry().fitScale,
                    panOffset: visual.panOffset
                )
                animateTransform(from: adjustedVisual, duration: 0.20)
            }
            return
        }

        armWindowLongPress(with: event)

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

        // Only an ordinary image press can become a file drag. Window movement,
        // corner resizing and text selection above own their entire gesture.
        if image != nil, geometry.imageRect.contains(point), let window {
            fileDragStartScreenPoint = window.convertPoint(toScreen: event.locationInWindow)
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
        updateWindowLongPressMovement(with: event)
        let point = convert(event.locationInWindow, from: nil)

        if let start = fileDragStartScreenPoint, let window,
           ImageDragPolicy.shouldExport(start: start,
                                        current: window.convertPoint(toScreen: event.locationInWindow),
                                        windowFrame: window.frame), let image {
            // One attempt per press, including failures. Stop panning before the
            // native session takes over; its completion replaces mouseUp.
            fileDragStartScreenPoint = nil
            dragType = .fileExport
            if !fileDragController.begin(from: self, event: event, image: image, sourceURL: imageURL,
                                         onEnded: { [weak self] in self?.resetMouseDrag() }) {
                resetMouseDrag()
            }
            return
        }

        switch dragType {
        case .none, .fileExport:
            break
        case .window:
            if isLongPressMovingWindow {
                guard !hasStartedLongPressWindowDrag else { return }
                hasStartedLongPressWindowDrag = true
                window?.performDrag(with: event)
                Self.windowMoveCursor.set()
            } else {
                window?.performDrag(with: event)
            }
        case .pan:
            guard let dragStartPoint else { return }
            alignsImageToTop = false
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
        guard !fileDragController.isDragging else { return }
        resetMouseDrag()
    }

    private func cancelImageDragCandidate() {
        guard fileDragStartScreenPoint != nil || windowLongPressStart != nil || isLongPressMovingWindow else { return }
        resetMouseDrag()
    }

    private func resetMouseDrag() {
        cancelWindowLongPressCandidate()
        windowMoveCursorTimer?.invalidate()
        windowMoveCursorTimer = nil
        isLongPressMovingWindow = false
        hasStartedLongPressWindowDrag = false
        fileDragStartScreenPoint = nil
        dragType = .none
        dragStartPoint = nil
        dragStartWindowFrame = nil
        dragStartOffset = .zero
        selectionAnchorLocation = nil
        selectionFocusLocation = nil
        if let window {
            cursorForPoint(convert(window.mouseLocationOutsideOfEventStream, from: nil)).set()
            window.invalidateCursorRects(for: self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, slideshow?.isFullScreenTransitioning == true { return }
        switch KeyboardNavigation.action(
            for: event.keyCode,
            modifiers: event.modifierFlags,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            isRepeat: event.isARepeat,
            slideshowActive: slideshow?.isActive == true,
            isFullScreen: window?.styleMask.contains(.fullScreen) == true
                || (window as? ViewerWindow)?.isTemporaryDesktopFullScreenActive == true
        ) {
        case .trash:
            trashImageForMenu(nil)
        case .undoDeletion:
            undoDeletionForMenu(nil)
        case .toggleAlwaysOnTop:
            toggleAlwaysOnTopForMenu(nil)
        case .previous:
            onPrevious?()
        case .next:
            onNext?()
        case .rotateLeft:
            if image != nil { onRotateLeft?() }
        case .rotateRight:
            if image != nil { onRotateRight?() }
        case .zoomIn:
            if image != nil { onZoomIn?() }
        case .zoomOut:
            if image != nil { onZoomOut?() }
        case .toggleSlideshowPause:
            slideshow?.togglePause()
        case .endSlideshow:
            slideshow?.stop()
        case .exitFullScreen:
            guard let window, slideshow?.isFullScreenTransitioning != true else { return }
            if let viewerWindow = window as? ViewerWindow, viewerWindow.isTemporaryDesktopFullScreenActive {
                viewerWindow.toggleTemporaryDesktopFullScreen()
            } else {
                slideshow?.beginFullScreenTransition()
                window.toggleFullScreen(nil)
            }
        case .quit:
            onClose?()
        case .toggleFullScreen:
            guard let window, slideshow?.isFullScreenTransitioning != true else { return }
            slideshow?.beginFullScreenTransition()
            window.toggleFullScreen(nil)
        case .toggleImageParameters:
            toggleImageParametersVisibility()
        case .printImage:
            printImageForMenu(nil)
        case .screenshot:
            NotificationCenter.default.post(name: ViewerOverlayPreference.beginScreenshotNotification, object: window)
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
            let copyItem = NSMenuItem(title: L10n.text("复制"), action: #selector(copySelectedText), keyEquivalent: "c")
            LanguageSettings.bind(copyItem) { $0.title = L10n.text("复制") }
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

    @objc func trashImageForMenu(_ sender: Any?) {
        guard canTrashImage else { return }
        onTrashImage?()
    }

    @objc func undoDeletionForMenu(_ sender: Any?) {
        guard canUndoDeletion else { return }
        onUndoDeletion?()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let snapshot = ViewerPreferencesSnapshot(defaults: defaults)
        let toggles: [Selector: Bool] = [
            #selector(toggleTitleBarForMenu(_:)): snapshot.titleBarVisible,
            #selector(toggleMinimapForMenu(_:)): snapshot.minimapEnabled,
            #selector(toggleFileInfoForMenu(_:)): snapshot.fileInfoVisible,
            #selector(toggleToolbarForMenu(_:)): snapshot.toolbarVisible,
            #selector(toggleImageParametersForMenu(_:)): snapshot.imageParametersVisible,
            #selector(toggleSingleWindowForMenu(_:)): snapshot.singleWindowEnabled,
            #selector(toggleAlwaysOnTopForMenu(_:)): snapshot.alwaysOnTopEnabled,
            #selector(toggleFixedWindowForMenu(_:)): snapshot.fixedWindowEnabled
        ]
        if let action = menuItem.action, let enabled = toggles[action] {
            menuItem.state = enabled ? .on : .off
        }
        if menuItem.action == #selector(selectTheme(_:)) {
            menuItem.state = menuItem.representedObject as? Int == snapshot.theme.rawValue ? .on : .off
        }
        if menuItem.action == #selector(selectImageDisplayModeForMenu(_:)) {
            menuItem.state = menuItem.representedObject as? String == snapshot.imageDisplayMode.rawValue ? .on : .off
        }
        if menuItem.action == #selector(trashImageForMenu(_:)) { return canTrashImage }
        if menuItem.action == #selector(undoDeletionForMenu(_:)) { return canUndoDeletion }
        if menuItem.action == #selector(checkForUpdatesForMenu(_:)) { return onCheckForUpdates != nil }
        if menuItem.action == #selector(setDesktopWallpaperForMenu(_:)) { return image != nil && !isSettingWallpaper }
        if menuItem.action == #selector(printImageForMenu(_:)) { return image != nil && window?.attachedSheet == nil }
        return true
    }

    @objc func printImageForMenu(_ sender: Any?) {
        guard let image, let window, window.attachedSheet == nil else { return }
        slideshow?.pause()
        ImagePrinter.present(image: image, rotationDegrees: rotationDegrees,
                             title: imageURL?.lastPathComponent, in: window)
    }

    @objc func setDesktopWallpaperForMenu(_ sender: Any?) {
        guard !isSettingWallpaper, let image, let window, let screen = window.screen ?? NSScreen.main else { return }
        slideshow?.pause()
        isSettingWallpaper = true
        desktopWallpaperRequest.perform(in: window, apply: { [weak self] in
            self?.setDesktopWallpaper(image, screen: screen)
        }, cancel: { [weak self] exitFailed in
            guard let self else { return }
            self.isSettingWallpaper = false
            if exitFailed {
                self.presentWallpaperError(message: L10n.text("无法退出全屏，请退出全屏后重试。"))
            }
        })
    }

    private func setDesktopWallpaper(_ image: NSImage, screen: NSScreen) {
        Task { [weak self] in
            defer { self?.isSettingWallpaper = false }
            do {
                try await self?.applyDesktopWallpaper(image, screen)
            } catch {
                guard let self else { return }
                self.presentWallpaperError(message: L10n.errorDescription(error))
            }
        }
    }

    private func presentWallpaperError(message: String) {
        let alert = NSAlert()
        LanguageSettings.bind(alert) {
            $0.messageText = L10n.text("设置桌面壁纸失败")
            $0.informativeText = message
            $0.buttons.first?.title = L10n.text("好")
        }
        alert.addButton(withTitle: L10n.text("好"))
        if let window { alert.beginSheetModal(for: window) }
        else { alert.runPicSeeModal() }
    }

    @objc func exportImageForMenu(_ sender: Any?) {
        slideshow?.pause()
        guard let image else { return }

        let panel = NSSavePanel()
        let accessoryView = ImageExportAccessoryView(defaultPixelSize: ImageExporter.pixelSize(of: image), image: image)
        LanguageSettings.bind(panel) {
            $0.title = L10n.text("图片另存为")
            $0.prompt = L10n.text("保存")
            $0.nameFieldLabel = L10n.text("文件名：")
        }
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
            accessoryView?.cancelSizeCalculation()
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
        minimapEnabled = !ViewerOverlayPreference.isMinimapEnabled(in: defaults)
        ViewerOverlayPreference.setMinimapEnabled(minimapEnabled, in: defaults)
        needsLayout = true
    }

    @objc func toggleTitleBarForMenu(_ sender: Any?) {
        titleBarVisible = !ViewerTitleBarPreference.isVisible(in: defaults)
        ViewerTitleBarPreference.setVisible(titleBarVisible, in: defaults)
        onTitleBarVisibilityChanged?(titleBarVisible)
    }

    @objc func toggleFileInfoForMenu(_ sender: Any?) {
        fileInfoVisible = !ViewerOverlayPreference.isFileInfoVisible(in: defaults)
        ViewerOverlayPreference.setFileInfoVisible(fileInfoVisible, in: defaults)
        onFileInfoVisibilityChanged?(fileInfoVisible)
    }

    @objc func toggleToolbarForMenu(_ sender: Any?) {
        toolbarVisible = !ViewerOverlayPreference.isToolbarVisible(in: defaults)
        ViewerOverlayPreference.setToolbarVisible(toolbarVisible, in: defaults)
        onToolbarVisibilityChanged?(toolbarVisible)
    }

    @objc func toggleImageParametersForMenu(_ sender: Any?) {
        toggleImageParametersVisibility()
    }

    @objc func toggleFixedWindowForMenu(_ sender: Any?) {
        fixedWindowEnabled = !WindowFramePreference.isFixedEnabled(in: defaults)
        WindowFramePreference.setFixedEnabled(fixedWindowEnabled, in: defaults)
        if fixedWindowEnabled, let window {
            WindowFramePreference.saveFixedFrame(window.frame, in: defaults)
        }
        onFixedWindowChanged?(fixedWindowEnabled)
        window?.invalidateCursorRects(for: self)
    }

    @objc func toggleAlwaysOnTopForMenu(_ sender: Any?) {
        WindowPinningPreference.setEnabled(!WindowPinningPreference.isEnabled(in: defaults), in: defaults)
    }

    @objc func toggleSingleWindowForMenu(_ sender: Any?) {
        SingleWindowPreference.setEnabled(!SingleWindowPreference.isEnabled(in: defaults), in: defaults)
    }

    @objc func checkForUpdatesForMenu(_ sender: Any?) {
        onCheckForUpdates?()
    }

    @objc func selectImageDisplayModeForMenu(_ sender: Any?) {
        guard let rawValue = (sender as? NSMenuItem)?.representedObject as? String,
              let mode = ImageDisplayMode(rawValue: rawValue) else { return }
        slideshow?.pause()
        let alreadySelected = ImageDisplayPreference.mode(in: defaults) == mode
        preferences.setImageDisplayMode(mode)
        if alreadySelected { onDefaultDisplayModeRequested?(mode) }
    }

    @objc func selectTheme(_ sender: Any?) {
        guard
            let item = sender as? NSMenuItem,
            let rawValue = item.representedObject as? Int,
            let theme = ViewerTheme(rawValue: rawValue)
        else { return }
        ViewerTheme.set(theme, in: defaults)
        item.menu?.items.forEach { menuItem in
            menuItem.state = menuItem.representedObject as? Int == theme.rawValue ? .on : .off
        }
        if let appearance = theme.appearance {
            window?.appearance = appearance
        } else {
            window?.appearance = nil
        }
    }

    private func toggleImageParametersVisibility() {
        imageParametersVisible = !ViewerOverlayPreference.isImageParametersVisible(in: defaults)
        ViewerOverlayPreference.setImageParametersVisible(imageParametersVisible, in: defaults)
        onImageParametersVisibilityChanged?(imageParametersVisible)
    }

    @objc private func copySelectedText() {
        _ = copySelectedTextToPasteboard()
    }

    @objc func toggleSlideshowForMenu(_ sender: Any?) {
        if slideshow?.isActive == true {
            slideshow?.togglePause()
        } else {
            onStartSlideshow?()
        }
    }

    @objc func endSlideshowForMenu(_ sender: Any?) { slideshow?.stop() }

    private func appendPicSeeContextMenuItems(to menu: NSMenu) {
        slideshow?.pause()
        applyPreferences(ViewerPreferencesSnapshot(defaults: defaults))
        let displayIdentifier = NSUserInterfaceItemIdentifier("PicSee.DisplayOptions")
        guard !menu.items.contains(where: { $0.identifier == displayIdentifier }) else { return }
        alignSystemContextMenuItems(in: menu)
        if menu.items.first(where: { $0.action == #selector(copyImagePathForMenu(_:)) }) == nil {
            let pathItem = NSMenuItem(title: L10n.text("复制图片路径"), action: #selector(copyImagePathForMenu(_:)), keyEquivalent: "")
            pathItem.image = contextMenuImage("link")
            LanguageSettings.bind(pathItem) { $0.title = L10n.text("复制图片路径") }
            pathItem.target = self
            pathItem.isEnabled = imageURL != nil
            menu.addItem(pathItem)
        }

        if menu.items.first(where: { $0.action == #selector(exportImageForMenu(_:)) }) == nil {
            let exportItem = NSMenuItem(title: L10n.text("图片另存为..."), action: #selector(exportImageForMenu(_:)), keyEquivalent: "")
            exportItem.image = contextMenuImage("square.and.arrow.down")
            LanguageSettings.bind(exportItem) { $0.title = L10n.text("图片另存为...") }
            exportItem.target = self
            exportItem.isEnabled = image != nil
            menu.addItem(exportItem)
        }

        let wallpaperItem = NSMenuItem(title: L10n.text("设为桌面壁纸"), action: #selector(setDesktopWallpaperForMenu(_:)), keyEquivalent: "")
        wallpaperItem.image = contextMenuImage("desktopcomputer")
        LanguageSettings.bind(wallpaperItem) { $0.title = L10n.text("设为桌面壁纸") }
        wallpaperItem.target = self
        wallpaperItem.isEnabled = image != nil && !isSettingWallpaper
        menu.addItem(wallpaperItem)

        let printItem = NSMenuItem(title: L10n.text("打印…"), action: #selector(printImageForMenu(_:)), keyEquivalent: "p")
        printItem.keyEquivalentModifierMask = .command
        printItem.image = contextMenuImage("printer")
        LanguageSettings.bind(printItem) { $0.title = L10n.text("打印…") }
        printItem.target = self
        printItem.isEnabled = image != nil
        menu.addItem(printItem)

        if onStartSlideshow != nil,
           !menu.items.contains(where: { $0.action == #selector(toggleSlideshowForMenu(_:)) }) {
            menu.addItem(.separator())
            let title = slideshow?.isActive == true ? L10n.text("继续幻灯片") : L10n.text("播放幻灯片")
            let playItem = NSMenuItem(title: title, action: #selector(toggleSlideshowForMenu(_:)), keyEquivalent: "")
            playItem.image = contextMenuImage("play.circle")
            LanguageSettings.bind(playItem) { [weak slideshow] item in
                item.title = slideshow?.isActive == true ? L10n.text("继续幻灯片") : L10n.text("播放幻灯片")
            }
            playItem.target = self
            menu.addItem(playItem)
            if slideshow?.isActive == true {
                let stopItem = NSMenuItem(title: L10n.text("结束幻灯片"), action: #selector(endSlideshowForMenu(_:)), keyEquivalent: "")
                stopItem.image = contextMenuImage("stop")
                LanguageSettings.bind(stopItem) { $0.title = L10n.text("结束幻灯片") }
                stopItem.target = self
                menu.addItem(stopItem)
            }
        }
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

        let imageDisplayItem = NSMenuItem(title: L10n.text("图片默认显示方式"), action: nil, keyEquivalent: "")
        LanguageSettings.bind(imageDisplayItem) { $0.title = L10n.text("图片默认显示方式") }
        imageDisplayItem.identifier = NSUserInterfaceItemIdentifier("PicSee.ImageDisplayMode")
        imageDisplayItem.image = contextMenuImage("photo")
        let imageDisplayMenu = NSMenu(title: L10n.text("图片默认显示方式"))
        imageDisplayItem.submenu = imageDisplayMenu
        let selectedDisplayMode = ImageDisplayPreference.mode(in: defaults)
        for mode in ImageDisplayMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(selectImageDisplayModeForMenu(_:)), keyEquivalent: "")
            LanguageSettings.bind(item) { $0.title = mode.displayName }
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == selectedDisplayMode ? .on : .off
            imageDisplayMenu.addItem(item)
        }
        menu.addItem(imageDisplayItem)

        let displayItem = NSMenuItem(title: L10n.text("显示选项"), action: nil, keyEquivalent: "")
        LanguageSettings.bind(displayItem) { $0.title = L10n.text("显示选项") }
        displayItem.identifier = displayIdentifier
        displayItem.image = contextMenuImage("slider.horizontal.3")
        let displayMenu = NSMenu(title: L10n.text("显示选项"))
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)

        if shouldAddTitleBarItem {
            let titleBarItem = NSMenuItem(title: L10n.text("显示标题栏"), action: #selector(toggleTitleBarForMenu(_:)), keyEquivalent: "")
            LanguageSettings.bind(titleBarItem) { $0.title = L10n.text("显示标题栏") }
            titleBarItem.target = self
            titleBarItem.state = titleBarVisible ? .on : .off
            displayMenu.addItem(titleBarItem)
        }

        if shouldAddMinimapItem {
            let minimapItem = NSMenuItem(title: L10n.text("显示缩略图"), action: #selector(toggleMinimapForMenu(_:)), keyEquivalent: "")
            LanguageSettings.bind(minimapItem) { $0.title = L10n.text("显示缩略图") }
            minimapItem.target = self
            minimapItem.state = minimapEnabled ? .on : .off
            displayMenu.addItem(minimapItem)
        }

        if shouldAddFileInfoItem {
            let fileInfoItem = NSMenuItem(title: L10n.text("显示文件信息"), action: #selector(toggleFileInfoForMenu(_:)), keyEquivalent: "")
            LanguageSettings.bind(fileInfoItem) { $0.title = L10n.text("显示文件信息") }
            fileInfoItem.target = self
            fileInfoItem.state = fileInfoVisible ? .on : .off
            displayMenu.addItem(fileInfoItem)
        }

        if shouldAddToolbarItem {
            let toolbarItem = NSMenuItem(title: L10n.text("显示底部工具栏"), action: #selector(toggleToolbarForMenu(_:)), keyEquivalent: "")
            LanguageSettings.bind(toolbarItem) { $0.title = L10n.text("显示底部工具栏") }
            toolbarItem.target = self
            toolbarItem.state = toolbarVisible ? .on : .off
            displayMenu.addItem(toolbarItem)
        }

        if shouldAddImageParametersItem {
            let imageParametersItem = NSMenuItem(title: L10n.text("显示图片参数"), action: #selector(toggleImageParametersForMenu(_:)), keyEquivalent: "i")
            LanguageSettings.bind(imageParametersItem) { $0.title = L10n.text("显示图片参数") }
            imageParametersItem.target = self
            imageParametersItem.state = imageParametersVisible ? .on : .off
            displayMenu.addItem(imageParametersItem)
        }

        if !menu.items.contains(where: { $0.action == #selector(toggleSingleWindowForMenu(_:)) }) {
            let item = NSMenuItem(title: L10n.text("单窗口看图"), action: #selector(toggleSingleWindowForMenu(_:)), keyEquivalent: "")
            item.image = contextMenuImage("macwindow")
            LanguageSettings.bind(item) { $0.title = L10n.text("单窗口看图") }
            item.target = self
            item.state = SingleWindowPreference.isEnabled(in: defaults) ? .on : .off
            menu.addItem(item)
        }

        if !menu.items.contains(where: { $0.action == #selector(toggleAlwaysOnTopForMenu(_:)) }) {
            let item = NSMenuItem(title: L10n.text("窗口置顶"), action: #selector(toggleAlwaysOnTopForMenu(_:)), keyEquivalent: "t")
            item.keyEquivalentModifierMask = [.control, .command]
            item.image = contextMenuImage("pin")
            LanguageSettings.bind(item) { $0.title = L10n.text("窗口置顶") }
            item.target = self
            item.state = WindowPinningPreference.isEnabled(in: defaults) ? .on : .off
            menu.addItem(item)
        }

        if shouldAddFixedWindowItem {
            let fixedWindowItem = NSMenuItem(title: L10n.text("固定窗口大小和位置"), action: #selector(toggleFixedWindowForMenu(_:)), keyEquivalent: "")
            fixedWindowItem.image = contextMenuImage("lock")
            LanguageSettings.bind(fixedWindowItem) { $0.title = L10n.text("固定窗口大小和位置") }
            fixedWindowItem.target = self
            fixedWindowItem.state = fixedWindowEnabled ? .on : .off
            menu.addItem(fixedWindowItem)
        }

        if menu.items.first(where: { $0.identifier == Self.themeMenuIdentifier }) == nil {
            let themeItem = NSMenuItem(title: L10n.text("主题"), action: nil, keyEquivalent: "")
            themeItem.image = contextMenuImage("circle.lefthalf.filled")
            LanguageSettings.bind(themeItem) { $0.title = L10n.text("主题") }
            themeItem.identifier = Self.themeMenuIdentifier
            let themeMenu = NSMenu(title: L10n.text("主题"))
            for theme in ViewerTheme.allCases {
                let item = NSMenuItem(title: theme.displayName, action: #selector(selectTheme(_:)), keyEquivalent: "")
                LanguageSettings.bind(item) { $0.title = theme.displayName }
                item.target = self
                item.state = ViewerTheme.current(in: defaults) == theme ? .on : .off
                item.representedObject = theme.rawValue
                themeMenu.addItem(item)
            }
            themeItem.submenu = themeMenu
            menu.addItem(themeItem)
        }

        if !menu.items.contains(where: { $0.action == #selector(trashImageForMenu(_:)) }) {
            menu.addItem(.separator())
            let trashItem = NSMenuItem(title: L10n.text("移到废纸篓"), action: #selector(trashImageForMenu(_:)), keyEquivalent: "\u{8}")
            trashItem.image = contextMenuImage("trash")
            LanguageSettings.bind(trashItem) { $0.title = L10n.text("移到废纸篓") }
            trashItem.keyEquivalentModifierMask = .command
            trashItem.target = self
            trashItem.isEnabled = canTrashImage
            menu.addItem(trashItem)
            let undoItem = NSMenuItem(title: L10n.text("撤销移到废纸篓"), action: #selector(undoDeletionForMenu(_:)), keyEquivalent: "z")
            undoItem.image = contextMenuImage("arrow.uturn.backward")
            LanguageSettings.bind(undoItem) { $0.title = L10n.text("撤销移到废纸篓") }
            undoItem.keyEquivalentModifierMask = .command
            undoItem.target = self
            undoItem.isEnabled = canUndoDeletion
            menu.addItem(undoItem)
        }

        if !menu.items.contains(where: { $0.action == #selector(AppDelegate.showSettings(_:)) }) {
            menu.addItem(.separator())
            let settingsItem = NSMenuItem(title: L10n.text("设置…"), action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
            settingsItem.image = contextMenuImage("gearshape")
            LanguageSettings.bind(settingsItem) { $0.title = L10n.text("设置…") }
            settingsItem.target = NSApplication.shared.delegate
            menu.addItem(settingsItem)
        }

        if !menu.items.contains(where: { $0.action == #selector(checkForUpdatesForMenu(_:)) }) {
            let updateItem = NSMenuItem(title: L10n.text("检查更新"), action: #selector(checkForUpdatesForMenu(_:)), keyEquivalent: "")
            updateItem.image = contextMenuImage("arrow.triangle.2.circlepath")
            LanguageSettings.bind(updateItem) { $0.title = L10n.text("检查更新") }
            updateItem.target = self
            updateItem.isEnabled = onCheckForUpdates != nil
            menu.addItem(updateItem)
        }

        if !menu.items.contains(where: { $0.action == #selector(AppDelegate.showAboutSettings(_:)) }) {
            let aboutItem = NSMenuItem(title: L10n.text("关于…"), action: #selector(AppDelegate.showAboutSettings(_:)), keyEquivalent: "")
            aboutItem.image = contextMenuImage("info.circle")
            LanguageSettings.bind(aboutItem) { $0.title = L10n.text("关于…") }
            aboutItem.target = NSApplication.shared.delegate
            menu.addItem(aboutItem)
        }
    }

    private func contextMenuImage(_ symbolName: String) -> NSImage? {
        PhosphorImages.contextMenuImage(for: symbolName)
    }

    private func alignSystemContextMenuItems(in menu: NSMenu) {
        // VisionKit owns these actions. Only decorate their presentation; preserve
        // targets, validation, ordering, and any icons supplied by the system.
        for item in menu.items where !item.isSeparatorItem && item.image == nil {
            let title = item.title.lowercased()
            if ["copy", "拷贝", "复制"].contains(where: { title.hasPrefix($0) }) {
                item.image = contextMenuImage("doc.on.doc")
            } else if ["share", "共享", "分享"].contains(where: { title.hasPrefix($0) }) {
                item.image = contextMenuImage("square.and.arrow.up")
            } else {
                // Reserve the same icon column for other system languages/actions.
                let spacer = NSImage(size: NSSize(width: 16, height: 16))
                spacer.isTemplate = true
                item.image = spacer
            }
        }
    }

    private func defaultExportFilename() -> String {
        Self.defaultExportFilename(for: imageURL)
    }

    private static func defaultExportFilename(for url: URL?) -> String {
        let baseName = url?.deletingPathExtension().lastPathComponent ?? L10n.text("导出图片")
        return L10n.text("%1$@_副本.jpg", String(describing: baseName))
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
        let alert = NSAlert()
        alert.addButton(withTitle: L10n.text("好"))
        LanguageSettings.bind(alert) {
            $0.messageText = L10n.text("保存图片失败")
            $0.informativeText = L10n.errorDescription(error)
            $0.buttons.first?.title = L10n.text("好")
        }
        alert.runPicSeeModal()
    }

    private func configureSubviews() {
        transparencyBackground.isHidden = true
        outgoingTransparencyBackground.isHidden = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.contentsGravity = .resizeAspect
        outgoingImageView.imageScaling = .scaleProportionallyUpOrDown
        outgoingImageView.wantsLayer = true
        outgoingImageView.layer?.opacity = 0
        addSubview(outgoingTransparencyBackground)
        addSubview(outgoingImageView)
        addSubview(transparencyBackground)
        imageMotionView.wantsLayer = true
        addSubview(imageMotionView)
        imageMotionView.addSubview(imageView)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)

        switch backend {
        case .liveText:
            liveTextOverlay.autoresizingMask = [.width, .height]
            liveTextOverlay.trackingImageView = imageView
            liveTextOverlay.delegate = self
            liveTextOverlay.preferredInteractionTypes = .automatic
            imageView.addSubview(liveTextOverlay)
        case .vision:
            selectionOverlayView.autoresizingMask = [.width, .height]
            imageMotionView.addSubview(selectionOverlayView)
        }

        minimapView.isHidden = true
        minimapView.onNavigate = { [weak self] point in
            self?.slideshow?.pause()
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
        resetTextSelectionState()
        scheduleLiveTextControlReposition()
        textRecognizer.schedule(image: image, url: imageURL, backend: backend,
            liveText: { [weak self] analysis in
                self?.liveTextOverlay.analysis = analysis
                self?.scheduleLiveTextControlReposition()
            }, vision: { [weak self] lines in self?.recognizedLines = lines })
    }

    private func currentGeometry() -> ImageDisplayGeometry {
        ImageDisplayGeometry(
            imageSize: imagePixelSize,
            viewportSize: bounds.size,
            zoomScale: zoomScale,
            panOffset: panOffset,
            rotationDegrees: rotationDegrees,
            backingScaleFactor: window?.backingScaleFactor ?? 1,
            maximumAutomaticPixelScale: automaticPixelScaleLimit,
            displayMode: displayMode
        )
    }

    private var automaticPixelScaleLimit: CGFloat {
        smallImageMode.maximumPixelScale(isFullScreen: window?.styleMask.contains(.fullScreen) == true,
                                        smartLimit: maximumSmallImageScale)
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
            let previousRadians = targetRadians - Self.shortestRotationDeltaRadians(
                from: pendingRotationAnimation.from,
                to: pendingRotationAnimation.to
            )
            let visualRadians = (layer.presentation()?.value(forKeyPath: "transform.rotation.z") as? CGFloat)
                ?? previousRadians
            // Equivalent angles nearest the new target avoid 270° wraparound and resume mid-flight.
            let fromRadians = targetRadians + atan2(sin(visualRadians - targetRadians),
                                                     cos(visualRadians - targetRadians))
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = fromRadians
            animation.toValue = targetRadians
            animation.duration = 0.22
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.removeAnimation(forKey: Self.rotationAnimationKey)
            transparencyBackground.imageMask.removeAnimation(forKey: Self.rotationAnimationKey)
            if !reduceMotion {
                layer.add(animation, forKey: Self.rotationAnimationKey)
                transparencyBackground.imageMask.add(animation, forKey: Self.rotationAnimationKey)
            }
            self.pendingRotationAnimation = nil
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setAffineTransform(CGAffineTransform(rotationAngle: targetRadians))
        CATransaction.commit()
    }

    func updateTransform(zoom: CGFloat, pan: CGSize, rotation: Int, animationID: Int, imageChanged: Bool,
                         displayMode nextDisplayMode: ImageDisplayMode? = nil, defaultDisplayRequestID: Int? = nil) {
        let shouldAnimate = animationID != handledTransformAnimationID && !imageChanged
        let hasNewDisplayRequest = (nextDisplayMode.map { $0 != displayMode } ?? false)
            || (defaultDisplayRequestID.map { $0 != self.defaultDisplayRequestID } ?? false)
        var visual = visualTransform()
        if let nextDisplayMode, nextDisplayMode != displayMode {
            let previousBaseScale = currentGeometry().fitScale
            displayMode = nextDisplayMode
            visual = ImageZoomAdjustment(
                zoomScale: visual.zoomScale * previousBaseScale / currentGeometry().fitScale,
                panOffset: visual.panOffset
            )
        }
        if let defaultDisplayRequestID { self.defaultDisplayRequestID = defaultDisplayRequestID }
        if hasNewDisplayRequest && !shouldAnimate && !imageChanged {
            imageMotionView.layer?.removeAnimation(forKey: Self.transformAnimationKey)
            transparencyBackground.motionMask.removeAnimation(forKey: Self.transformAnimationKey)
            transformMotion = nil
            cancelNavigationAnimation()
        }
        if shouldAnimate && !hasNewDisplayRequest { alignsImageToTop = false }
        handledTransformAnimationID = animationID
        zoomScale = zoom
        panOffset = pan
        rotationDegrees = rotation
        if shouldAnimate {
            cancelNavigationAnimation()
            animateTransform(from: visual, duration: 0.20)
        }
    }

    private func visualTransform() -> ImageZoomAdjustment {
        guard let layer = imageMotionView.layer,
              layer.animation(forKey: Self.transformAnimationKey) != nil else {
            return ImageZoomAdjustment(zoomScale: zoomScale, panOffset: panOffset)
        }
        if let presentedContainer = layer.presentation(),
           let presentedImage = imageView.layer?.presentation(),
           imagePixelSize.width > 0 {
            // Read geometry and transform from the same presented frame. The model's
            // zoom/pan may already describe a replacement not yet rendered by CA.
            let transform = presentedContainer.transform
            let renderedScale = presentedImage.bounds.width / imagePixelSize.width
            return ImageZoomAdjustment(
                zoomScale: renderedScale * transform.m11 / currentGeometry().fitScale,
                panOffset: CGSize(
                    width: (presentedImage.position.x - presentedContainer.bounds.midX) * transform.m11 + transform.m41,
                    height: (presentedImage.position.y - presentedContainer.bounds.midY) * transform.m11 + transform.m42))
        }
        // An offscreen view has no presented frame; use the pending animation's start.
        let transform = ((layer.animation(forKey: Self.transformAnimationKey) as? CABasicAnimation)?.fromValue as? CATransform3D)
            ?? CATransform3DIdentity
        return ImageZoomAdjustment(
            zoomScale: max(CGFloat.leastNormalMagnitude, zoomScale) * transform.m11,
            panOffset: CGSize(width: panOffset.width * transform.m11 + transform.m41,
                              height: panOffset.height * transform.m11 + transform.m42))
    }

    private struct TransformMotion {
        let startZoom: CGFloat
        let targetZoom: CGFloat
        let duration: CFTimeInterval
        let timing: CAMediaTimingFunction

        func zoomVelocity(at zoom: CGFloat) -> CGFloat {
            let distance = targetZoom - startZoom
            guard abs(distance) > 0.000001 else { return 0 }
            let progress = min(1, max(0, (zoom - startZoom) / distance))
            var first: [Float] = [0, 0]
            var second: [Float] = [0, 0]
            timing.getControlPoint(at: 1, values: &first)
            timing.getControlPoint(at: 2, values: &second)
            let x1 = CGFloat(first[0]), y1 = CGFloat(first[1])
            let x2 = CGFloat(second[0]), y2 = CGFloat(second[1])
            // Invert the curve at the displayed position, not wall-clock time:
            // the presentation layer can lag a pending replacement by one frame.
            var low: CGFloat = 0
            var high: CGFloat = 1
            for _ in 0..<24 {
                let t = (low + high) / 2
                let u = 1 - t
                let y = 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t
                if y < progress { low = t } else { high = t }
            }
            let t = (low + high) / 2
            let u = 1 - t
            let dx = 3 * (u * u * x1 + 2 * u * t * (x2 - x1) + t * t * (1 - x2))
            let dy = 3 * (u * u * y1 + 2 * u * t * (y2 - y1) + t * t * (1 - y2))
            return dx > 0.000001 ? distance / duration * dy / dx : 0
        }
    }

    private func animateTransform(
        from visual: ImageZoomAdjustment,
        duration: CFTimeInterval,
        timing: CAMediaTimingFunctionName = .easeOut,
        initialZoomVelocity: CGFloat = 0
    ) {
        layoutSubtreeIfNeeded()
        guard let layer = imageMotionView.layer else { return }
        layer.removeAnimation(forKey: Self.transformAnimationKey)
        transparencyBackground.motionMask.removeAnimation(forKey: Self.transformAnimationKey)
        guard !reduceMotion else { return }
        let ratio = max(CGFloat.leastNormalMagnitude, visual.zoomScale) / max(CGFloat.leastNormalMagnitude, zoomScale)
        let transform = CGAffineTransform(a: ratio, b: 0, c: 0, d: ratio,
                                         tx: visual.panOffset.width - panOffset.width * ratio,
                                         ty: visual.panOffset.height - panOffset.height * ratio)
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = CATransform3DMakeAffineTransform(transform)
        animation.toValue = CATransform3DIdentity
        animation.duration = duration
        var curve = CAMediaTimingFunction(name: timing)
        let distance = zoomScale - visual.zoomScale
        if abs(distance) > 0.000001 {
            let slope = initialZoomVelocity * duration / distance
            if slope.isFinite, slope > 0 {
                // Match incoming speed for same-direction retargets, then ease to rest.
                // Ordered control points keep the curve monotonic and prevent overshoot.
                let x1 = min(0.42, 1 / slope)
                curve = CAMediaTimingFunction(controlPoints: Float(x1), Float(min(1, slope * x1)), 0.58, 1)
            }
        }
        animation.timingFunction = curve
        transformMotion = TransformMotion(startZoom: visual.zoomScale, targetZoom: zoomScale,
                                          duration: duration, timing: curve)
        layer.add(animation, forKey: Self.transformAnimationKey)
        transparencyBackground.motionMask.add(animation, forKey: Self.transformAnimationKey)
    }

    private func interruptMotion() {
        let visual = visualTransform()
        let wasZooming = imageMotionView.layer?.animation(forKey: Self.transformAnimationKey) != nil
        imageMotionView.layer?.removeAnimation(forKey: Self.transformAnimationKey)
        transparencyBackground.motionMask.removeAnimation(forKey: Self.transformAnimationKey)
        cancelNavigationAnimation()
        if wasZooming {
            zoomScale = visual.zoomScale
            panOffset = visual.panOffset
            onZoomChanged?(zoomScale)
            onPanChanged?(panOffset)
            layoutSubtreeIfNeeded()
        }
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        guard reduceMotion else { return }
        // Keep committed targets when the system preference changes mid-animation.
        imageMotionView.layer?.removeAnimation(forKey: Self.transformAnimationKey)
        imageView.layer?.removeAnimation(forKey: Self.rotationAnimationKey)
        transparencyBackground.motionMask.removeAnimation(forKey: Self.transformAnimationKey)
        transparencyBackground.imageMask.removeAnimation(forKey: Self.rotationAnimationKey)
        cancelNavigationAnimation()
    }

    private func cancelNavigationAnimation() {
        navigationToken += 1
        pendingNavigationAnimation = false
        imageMotionView.layer?.removeAnimation(forKey: Self.navigationAnimationKey)
        transparencyBackground.motionMask.removeAnimation(forKey: Self.navigationAnimationKey)
        outgoingImageView.layer?.removeAllAnimations()
        outgoingTransparencyBackground.imageMask.removeAllAnimations()
        outgoingImageView.image = nil
        outgoingTransparencyBackground.isHidden = true
    }

    private func prepareImageTransition() {
        let previousImage = imageView.image
        let previousSource = imageDetailLayer?.source
        let wasNavigating = pendingNavigationAnimation
            || imageMotionView.layer?.animation(forKey: Self.navigationAnimationKey) != nil
        let visual = visualTransform()
        cancelNavigationAnimation()
        imageMotionView.layer?.removeAnimation(forKey: Self.transformAnimationKey)
        transparencyBackground.motionMask.removeAnimation(forKey: Self.transformAnimationKey)
        guard navigationAnimationEnabled, previousImage != nil || previousSource != nil,
              image != nil, navigationDirection != nil else {
            lastNavigationTime = nil
            return
        }
        let now = navigationTime()
        let isRapidRepeat = lastNavigationTime.map { now - $0 < 0.22 } ?? false
        lastNavigationTime = now
        // Keep the entire burst immediate, including reversals. Testing only whether
        // an animation exists would restart it on every other repeat after cancellation.
        guard !wasNavigating, !isRapidRepeat else { return }
        let geometry = ImageDisplayGeometry(imageSize: imagePixelSize, viewportSize: bounds.size,
                                           zoomScale: visual.zoomScale, panOffset: visual.panOffset,
                                           rotationDegrees: rotationDegrees,
                                           backingScaleFactor: window?.backingScaleFactor ?? 1,
                                           maximumAutomaticPixelScale: automaticPixelScaleLimit,
                                           displayMode: displayMode)
        // Transparent tiled images hide their underlay to avoid double alpha.
        // Use the retained preview for the short outgoing fade without decoding
        // or allocating a full-resolution snapshot.
        outgoingImageView.image = previousImage ?? previousSource.map {
            NSImage(cgImage: $0.preview, size: $0.pixelSize)
        }
        outgoingImageView.frame = geometry.unrotatedImageRect
        outgoingImageView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        outgoingImageView.layer?.position = CGPoint(x: geometry.imageRect.midX, y: geometry.imageRect.midY)
        outgoingImageView.layer?.transform = imageView.layer?.presentation()?.transform
            ?? imageView.layer?.transform ?? CATransform3DIdentity
        outgoingTransparencyBackground.frame = bounds
        if let imageLayer = outgoingImageView.layer {
            outgoingTransparencyBackground.synchronize(imageLayer: imageLayer)
        }
        outgoingTransparencyBackground.isHidden = transparencyBackground.isHidden
        pendingNavigationAnimation = true
    }

    private func animateImageTransition() {
        guard navigationAnimationEnabled else { cancelNavigationAnimation(); return }
        guard let incoming = imageMotionView.layer, let outgoing = outgoingImageView.layer else { return }
        let offset: CGFloat = reduceMotion ? 0 : CGFloat(navigationDirection ?? 0) * 24
        let duration = reduceMotion ? 0.12 : 0.16
        let moveIn = CABasicAnimation(keyPath: "transform.translation.x")
        moveIn.fromValue = offset
        moveIn.toValue = 0
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.94
        fadeIn.toValue = 1
        let moveOut = CABasicAnimation(keyPath: "position.x")
        moveOut.fromValue = outgoing.position.x
        moveOut.toValue = outgoing.position.x - offset
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        let token = navigationToken
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Keep the old image invisible after its explicit fade is removed, even
        // before the asynchronous cleanup runs (especially across different sizes).
        outgoing.opacity = 0
        outgoingTransparencyBackground.imageMask.opacity = 0
        CATransaction.setCompletionBlock { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.navigationToken == token else { return }
                self.outgoingImageView.image = nil
                self.outgoingTransparencyBackground.isHidden = true
            }
        }
        for (layer, animations, transitionDuration) in [
            (incoming, [moveIn, fadeIn], duration),
            (outgoing, [moveOut, fadeOut], 0.10)
        ] {
            let group = CAAnimationGroup()
            group.animations = animations
            group.duration = transitionDuration
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(group, forKey: Self.navigationAnimationKey)
            let mask = layer === incoming
                ? transparencyBackground.motionMask : outgoingTransparencyBackground.imageMask
            mask.add(group, forKey: Self.navigationAnimationKey)
        }
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
        guard backend == .liveText else { return }
        let inset = !titleBarVisible && !fixedWindowEnabled
            ? bottomRightResizeRegionSize + resizeAvoidancePadding : 0
        let current = liveTextOverlay.supplementaryInterfaceContentInsets
        guard current.bottom != inset || current.right != inset || current.top != 0 || current.left != 0 else { return }
        // Let VisionKit own the button layout so subsequent system layouts retain
        // the avoidance margin instead of restoring a manually moved subview.
        liveTextOverlay.supplementaryInterfaceContentInsets = NSEdgeInsets(top: 0, left: 0, bottom: inset, right: inset)
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
        interruptMotion()
        alignsImageToTop = false
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

    /// Controls keep their native click behavior even if a system layout briefly
    /// places the Live Text interface inside a corner resize region.
    private func interactiveControlHit(at point: CGPoint) -> NSView? {
        guard let hit = super.hitTest(convert(point, to: superview)), hit !== self else { return nil }
        var current: NSView? = hit
        while let view = current, view !== self {
            if view is NSControl, !(view is NSImageView) { return hit }
            current = view.superview
        }
        if backend == .liveText,
           (hit === liveTextOverlay || hit.isDescendant(of: liveTextOverlay)),
           liveTextOverlay.hasSupplementaryInterface(at: liveTextOverlay.convert(point, from: self)) {
            return hit
        }
        return nil
    }

    private func resizeAnchor(at point: CGPoint) -> WindowResizeAnchor? {
        guard !titleBarVisible, !fixedWindowEnabled, interactiveControlHit(at: point) == nil else { return nil }
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
        // Layout may run inside updateNSView; publishing here would re-enter SwiftUI.
        DispatchQueue.main.async { [weak self] in
            guard let self, abs(self.lastReportedDisplayScale - displayScale) < 0.0001 else { return }
            self.onDisplayScaleChanged?(displayScale)
        }
    }

    private func cursorForPoint(_ point: CGPoint) -> NSCursor {
        if isLongPressMovingWindow { return Self.windowMoveCursor }
        if interactiveControlHit(at: point) != nil { return .arrow }
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


}

extension CanvasNSView: ImageAnalysisOverlayViewDelegate {
    func overlayView(
        _ overlayView: ImageAnalysisOverlayView,
        shouldBeginAt point: CGPoint,
        forAnalysisType analysisType: ImageAnalysisOverlayView.InteractionTypes
    ) -> Bool {
        slideshow?.pause()
        guard !isLongPressMovingWindow else { return false }
        if fileDragStartScreenPoint != nil {
            // Live Text owns selection; keep only the independent long-press candidate.
            fileDragStartScreenPoint = nil
            dragType = .none
            dragStartPoint = nil
            dragStartOffset = .zero
        }
        interruptMotion()
        return true
    }

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
    func debugUpdateWindowMoveCursor(leftButtonDown: Bool) { updateWindowMoveCursor(leftButtonDown: leftButtonDown) }
    var debugWindowMoveCursor: NSCursor { Self.windowMoveCursor }
    var debugIsLongPressMovingWindow: Bool { isLongPressMovingWindow }
    var debugHasWindowLongPressCandidate: Bool { windowLongPressStart != nil }
    func debugFireWindowLongPress(at point: CGPoint) {
        guard let window else { return }
        activateWindowLongPress(at: window.convertPoint(toScreen: point), leftButtonDown: true, window: window)
    }
    func debugHandleWindowLongPressEvent(_ event: NSEvent) -> NSEvent? { handleWindowLongPressEvent(event) }
    var debugGeometry: ImageDisplayGeometry { currentGeometry() }
    func debugHandleCloseGestureEvent(_ event: NSEvent) -> NSEvent? { handleCloseGestureEvent(event) }
    func debugReloadGesturePreferences() { preferences.reload(); applyPreferences(preferences.snapshot) }
    var debugBackend: TextRecognitionBackend { backend }
    var debugMotionLayer: CALayer? { imageMotionView.layer }
    var debugLiveTextOverlay: ImageAnalysisOverlayView { liveTextOverlay }
    var debugRotationLayer: CALayer? { imageView.layer }
    var debugOutgoingImage: NSImage? { outgoingImageView.image }
    var debugOutgoingLayer: CALayer? { outgoingImageView.layer }
    var debugNavigationAnimationEnabled: Bool { navigationAnimationEnabled }
    func debugCancelTextRecognition() { textRecognizer.cancel() }
    func debugInterruptMotion() { interruptMotion() }
    func debugMotionPreferenceChanged() { accessibilityDisplayOptionsChanged() }
    var debugVisualTransform: ImageZoomAdjustment { visualTransform() }

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
