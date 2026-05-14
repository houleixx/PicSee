import AppKit
import ImageIO
import SwiftUI
import Vision
@preconcurrency import VisionKit

struct ImageCanvasView: NSViewRepresentable {
    let image: NSImage
    let imageURL: URL
    @Binding var zoomScale: CGFloat
    @Binding var panOffset: CGSize
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onReset: () -> Void
    let onClose: () -> Void
    let onDisplayScaleChanged: (CGFloat) -> Void

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        view.imageURL = imageURL
        view.image = image
        view.onPrevious = onPrevious
        view.onNext = onNext
        view.onReset = onReset
        view.onClose = onClose
        view.onDisplayScaleChanged = onDisplayScaleChanged
        view.onZoomChanged = { zoomScale = $0 }
        view.onPanChanged = { panOffset = $0 }
        return view
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.imageURL = imageURL
        nsView.image = image
        nsView.zoomScale = zoomScale
        nsView.panOffset = panOffset
        nsView.onPrevious = onPrevious
        nsView.onNext = onNext
        nsView.onReset = onReset
        nsView.onClose = onClose
        nsView.onDisplayScaleChanged = onDisplayScaleChanged
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

enum TextRecognitionBackend {
    case liveText
    case vision

    static var preferred: TextRecognitionBackend {
        preferredBackend(
            liveTextSupported: ImageAnalyzer.isSupported,
            supportsLiveTextSelection: supportsLiveTextSelection
        )
    }

    static func preferredBackend(
        liveTextSupported: Bool,
        supportsLiveTextSelection: Bool
    ) -> TextRecognitionBackend {
        liveTextSupported && supportsLiveTextSelection ? .liveText : .vision
    }

    private static var supportsLiveTextSelection: Bool {
        if #available(macOS 14.0, *) {
            true
        } else {
            false
        }
    }
}

final class CanvasNSView: NSView {
    private let imageView = NSImageView(frame: .zero)
    private let backend: TextRecognitionBackend

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

    var onZoomChanged: ((CGFloat) -> Void)?
    var onPanChanged: ((CGSize) -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onReset: (() -> Void)?
    var onClose: (() -> Void)?
    var onDisplayScaleChanged: ((CGFloat) -> Void)?

    private enum DragType {
        case none
        case window
        case pan
        case textSelection
    }

    private var dragType: DragType = .none
    private var dragStartPoint: NSPoint?
    private var dragStartOffset: CGSize = .zero
    private var lastReportedDisplayScale: CGFloat = -1
    private var trackingArea: NSTrackingArea?
    private var analysisTask: Task<Void, Never>?
    private var analysisToken = 0

    private let topDragRegionHeight: CGFloat = 36

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(frame frameRect: NSRect, backend: TextRecognitionBackend) {
        self.backend = backend
        super.init(frame: frameRect)
        configureSubviews()
    }

    override convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, backend: .preferred)
    }

    required init?(coder: NSCoder) {
        self.backend = .preferred
        super.init(coder: coder)
        configureSubviews()
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
        imageView.frame = geometry.imageRect
        switch backend {
        case .liveText:
            liveTextOverlay.frame = imageView.bounds
        case .vision:
            selectionOverlayView.frame = bounds
            updateSelectionOverlay()
        }
        reportDisplayScaleIfNeeded(geometry.displayScale)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: cursorForCurrentMouseLocation())
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
        let applied = delta > 0 ? multiplier : 1 / multiplier
        let nextZoom = min(20, max(0.05, zoomScale * applied))
        zoomScale = nextZoom
        onZoomChanged?(nextZoom)

        let geometry = currentGeometry()
        if !panImageMode(geometry) {
            panOffset = .zero
            onPanChanged?(.zero)
        }
        if backend == .vision {
            updateSelectionOverlay()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let geometry = currentGeometry()
        let point = convert(event.locationInWindow, from: nil)

        dragType = .none
        dragStartPoint = nil
        dragStartOffset = .zero
        selectionAnchorLocation = nil
        selectionFocusLocation = nil

        let hitText = backend == .vision ? hitTextLocation(at: point, geometry: geometry) : nil

        if event.clickCount == 2, hitText == nil {
            zoomScale = 1
            panOffset = .zero
            onZoomChanged?(1)
            onPanChanged?(.zero)
            onReset?()
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
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragType == .pan {
            cursorForPoint(convert(event.locationInWindow, from: nil)).set()
        }
        dragType = .none
        dragStartPoint = nil
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

    @objc private func copySelectedText() {
        _ = copySelectedTextToPasteboard()
    }

    private func appendPicSeeContextMenuItems(to menu: NSMenu) {
        if menu.items.first(where: { $0.action == #selector(copyImagePathForMenu(_:)) }) == nil {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            let pathItem = NSMenuItem(title: "复制图片路径", action: #selector(copyImagePathForMenu(_:)), keyEquivalent: "")
            pathItem.target = self
            pathItem.isEnabled = imageURL != nil
            menu.addItem(pathItem)
        }

        AppMenu.appendAboutItem(to: menu)
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
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, token == self.analysisToken else { return }
                    self.liveTextOverlay.analysis = nil
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
            panOffset: panOffset
        )
    }

    private func panImageMode(_ geometry: ImageDisplayGeometry) -> Bool {
        if abs(geometry.zoomScale - 1) > 0.001 { return true }
        return geometry.canPan
    }

    private func constrainPan(_ proposed: CGSize, geometry: ImageDisplayGeometry) -> CGSize {
        geometry.constrainedPan(proposed, allowSlackWhenFitted: panImageMode(geometry))
    }

    private func isInTopDragRegion(_ point: CGPoint) -> Bool {
        point.y >= bounds.height - topDragRegionHeight
    }

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
            if #available(macOS 14.0, *) {
                return liveTextOverlay.selectedText
            }
            return ""
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

    private func cursorForCurrentMouseLocation() -> NSCursor {
        guard let window else { return .arrow }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return cursorForPoint(point)
    }

    private func cursorForPoint(_ point: CGPoint) -> NSCursor {
        let geometry = currentGeometry()
        if backend == .vision, hitTextLocation(at: point, geometry: geometry) != nil {
            return .iBeam
        }
        if dragType == .pan || (panImageMode(geometry) && geometry.imageRect.contains(point)) {
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
    @available(macOS 14.0, *)
    func overlayView(_ overlayView: ImageAnalysisOverlayView, updatedMenuFor menu: NSMenu, for event: NSEvent, at point: CGPoint) -> NSMenu {
        appendPicSeeContextMenuItems(to: menu)
        return menu
    }
}

#if DEBUG
extension CanvasNSView {
    var debugBackend: TextRecognitionBackend { backend }

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
}
#endif
