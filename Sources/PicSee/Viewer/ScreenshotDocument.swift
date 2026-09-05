import AppKit

/// All editing coordinates are in oriented image pixels, with a bottom-left origin.
enum ScreenshotTool: String, CaseIterable, Identifiable {
    case crop, pen, highlighter, line, arrow, rectangle, ellipse, text, mosaic, eraser
    static let toolbarOrder: [ScreenshotTool] = [
        .crop, .arrow, .ellipse, .rectangle, .text, .pen, .highlighter,
        .line, .mosaic, .eraser
    ]
    var id: Self { self }
    var title: String {
        switch self {
        case .crop: "调整选区"
        case .pen: "画笔"
        case .highlighter: "荧光笔"
        case .line: "直线"
        case .arrow: "箭头"
        case .rectangle: "矩形"
        case .ellipse: "椭圆"
        case .text: "文字"
        case .mosaic: "马赛克"
        case .eraser: "删除标注"
        }
    }
    var symbol: String {
        switch self {
        case .crop: "crop"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "oval"
        case .text: "t"
        case .mosaic: "square.grid.3x3.fill"
        case .eraser: "eraser"
        }
    }
}

struct ScreenshotAnnotation {
    var tool: ScreenshotTool
    var points: [CGPoint]
    var color: NSColor
    var width: CGFloat
    var text = ""
    var fontSize: CGFloat = 18
    var sourceUnitsPerPoint: CGFloat = 1
    var rect: CGRect {
        guard let first = points.first else { return .zero }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
            CGRect(x: min(rect.minX, point.x), y: min(rect.minY, point.y),
                   width: max(rect.maxX, point.x) - min(rect.minX, point.x),
                   height: max(rect.maxY, point.y) - min(rect.minY, point.y))
        }
    }
    var textAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: fontSize, weight: .regular), .foregroundColor: color]
    }
    var hitBounds: CGRect {
        if tool == .text, let point = points.first {
            return CGRect(origin: point, size: (text as NSString).size(withAttributes: textAttributes))
        }
        return rect.insetBy(dx: -max(width, 8 * sourceUnitsPerPoint), dy: -max(width, 8 * sourceUnitsPerPoint))
    }
}

struct ScreenshotState {
    var selection: CGRect?
    var annotations: [ScreenshotAnnotation] = []
}

@MainActor
final class ScreenshotDocument: ObservableObject {
    let image: NSImage
    let pixelSize: CGSize
    let mosaicImage: NSImage
    @Published var state = ScreenshotState()
    @Published var tool: ScreenshotTool = .crop
    @Published var color = NSColor.systemRed
    @Published var strokeWidth: CGFloat = 6
    @Published var mosaicDiameter: CGFloat = 40
    @Published var fontSize: CGFloat = 18
    @Published var pendingText: ScreenshotAnnotation?
    @Published private(set) var editingTextIndex: Int?
    @Published private(set) var undoStates: [ScreenshotState] = []
    @Published private(set) var redoStates: [ScreenshotState] = []

    init(image: NSImage, rotationDegrees: Int) throws {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageExporterError.missingCGImage
        }
        let rotation = ((rotationDegrees % 360) + 360) % 360
        let swapsAxes = rotation == 90 || rotation == 270
        pixelSize = CGSize(width: swapsAxes ? source.height : source.width,
                           height: swapsAxes ? source.width : source.height)
        let bitmap = try Self.bitmap(size: pixelSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.translateBy(x: pixelSize.width / 2, y: pixelSize.height / 2)
        context.rotate(by: CGFloat(rotation) * .pi / 180)
        context.draw(source, in: CGRect(x: -CGFloat(source.width) / 2, y: -CGFloat(source.height) / 2,
                                       width: CGFloat(source.width), height: CGFloat(source.height)))
        NSGraphicsContext.restoreGraphicsState()
        self.image = NSImage(size: pixelSize)
        self.image.addRepresentation(bitmap)

        let smallSize = CGSize(width: max(1, ceil(pixelSize.width / 16)), height: max(1, ceil(pixelSize.height / 16)))
        let small = try Self.bitmap(size: smallSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
        NSGraphicsContext.current?.imageInterpolation = .high
        self.image.draw(in: CGRect(origin: .zero, size: smallSize))
        NSGraphicsContext.restoreGraphicsState()
        mosaicImage = NSImage(size: smallSize)
        mosaicImage.addRepresentation(small)
    }

    var bounds: CGRect { CGRect(origin: .zero, size: pixelSize) }
    var canExport: Bool { state.selection.map { $0.width >= 1 && $0.height >= 1 } ?? false }
    func checkpoint() {
        // The first valid crop is the editing baseline, never an undoable empty state.
        guard canExport else { return }
        undoStates.append(state)
        if undoStates.count > 100 { undoStates.removeFirst() }
        redoStates.removeAll()
    }
    /// Toolbar sizes are display points; annotations retain source coordinates for export.
    func makeAnnotation(tool: ScreenshotTool, points: [CGPoint], displayScale: CGFloat) -> ScreenshotAnnotation {
        let factor: CGFloat = displayScale.isFinite && displayScale > 0 ? 1 / displayScale : 1
        return ScreenshotAnnotation(tool: tool, points: points, color: color,
            width: (tool == .mosaic ? mosaicDiameter : strokeWidth) * factor,
            fontSize: fontSize * factor, sourceUnitsPerPoint: factor)
    }
    func beginText(at point: CGPoint, displayScale: CGFloat = 1) {
        commitPendingText()
        editingTextIndex = state.annotations.indices.reversed().first {
            state.annotations[$0].tool == .text && state.annotations[$0].hitBounds.insetBy(dx: -4, dy: -4).contains(point)
        }
        if let index = editingTextIndex {
            pendingText = state.annotations[index]
        } else {
            pendingText = makeAnnotation(tool: .text, points: [point], displayScale: displayScale)
        }
    }
    func cancelPendingText() {
        pendingText = nil
        editingTextIndex = nil
    }
    func commitPendingText() {
        guard let annotation = pendingText else { editingTextIndex = nil; return }
        let index = editingTextIndex
        cancelPendingText()
        guard !annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let index, state.annotations.indices.contains(index) {
            guard state.annotations[index].text != annotation.text || state.annotations[index].points != annotation.points else { return }
            checkpoint()
            state.annotations[index] = annotation
        } else {
            checkpoint()
            state.annotations.append(annotation)
        }
    }
    func undo() {
        commitPendingText()
        guard let previous = undoStates.popLast() else { return }
        redoStates.append(state)
        state = previous
    }
    func redo() {
        commitPendingText()
        guard let next = redoStates.popLast() else { return }
        undoStates.append(state)
        state = next
    }
    func reselect() {
        commitPendingText()
        checkpoint()
        state.selection = nil
        tool = .crop
    }
    func selectAll() {
        commitPendingText()
        guard state.selection != bounds else { tool = .crop; return }
        checkpoint()
        state.selection = bounds
        tool = .crop
    }
    /// Pixel-aligned dimensions match the exported PNG. Keep the top-left corner when
    /// possible, shifting the selection only if its requested size reaches an image edge.
    @discardableResult
    func resizeSelection(width: Int? = nil, height: Int? = nil, recordUndo: Bool = true) -> Bool {
        guard let selection = state.selection,
              width.map({ $0 > 0 }) ?? true, height.map({ $0 > 0 }) ?? true else { return false }
        let crop = selection.integral.intersection(bounds)
        guard !crop.isNull, !crop.isEmpty else { return false }
        let newWidth = min(CGFloat(width ?? Int(crop.width)), pixelSize.width)
        let newHeight = min(CGFloat(height ?? Int(crop.height)), pixelSize.height)
        let resized = CGRect(
            x: min(max(0, crop.minX), pixelSize.width - newWidth),
            y: min(max(0, crop.maxY - newHeight), pixelSize.height - newHeight),
            width: newWidth, height: newHeight
        )
        guard resized != selection else { return false }
        commitPendingText()
        if recordUndo { checkpoint() }
        state.selection = resized
        return true
    }

    func clearAnnotations() {
        commitPendingText()
        checkpoint()
        state.annotations.removeAll()
    }
    func clamp(_ point: CGPoint, to rect: CGRect? = nil) -> CGPoint {
        let limit = rect ?? bounds
        return CGPoint(x: min(max(point.x, limit.minX), limit.maxX),
                       y: min(max(point.y, limit.minY), limit.maxY))
    }
    func erase(at point: CGPoint) {
        if let index = state.annotations.lastIndex(where: { $0.hitBounds.contains(point) }) {
            state.annotations.remove(at: index)
        }
    }

    func drawAnnotations(_ annotations: [ScreenshotAnnotation]) {
        guard let selection = state.selection else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selection).addClip()
        for annotation in annotations {
            guard let start = annotation.points.first, let end = annotation.points.last else { continue }
            annotation.color.setStroke()
            annotation.color.setFill()
            let path = NSBezierPath()
            path.lineWidth = annotation.width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            switch annotation.tool {
            case .pen, .highlighter:
                if annotation.tool == .highlighter {
                    annotation.color.withAlphaComponent(0.3).setStroke()
                    path.lineWidth *= 4
                }
                path.move(to: start)
                for point in annotation.points.dropFirst() { path.line(to: point) }
                if annotation.points.count == 1 { path.line(to: CGPoint(x: start.x + 0.1, y: start.y)) }
                path.stroke()
            case .line, .arrow:
                path.move(to: start)
                path.line(to: end)
                if annotation.tool == .arrow {
                    let angle = atan2(end.y - start.y, end.x - start.x)
                    let length = max(16 * annotation.sourceUnitsPerPoint, annotation.width * 4)
                    for delta in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                        path.move(to: end)
                        path.line(to: CGPoint(x: end.x - length * cos(angle + delta),
                                              y: end.y - length * sin(angle + delta)))
                    }
                }
                path.stroke()
            case .rectangle, .ellipse:
                let shape = annotation.tool == .rectangle ? NSBezierPath(rect: annotation.rect) : NSBezierPath(ovalIn: annotation.rect)
                shape.lineWidth = annotation.width
                shape.stroke()
            case .text:
                (annotation.text as NSString).draw(at: start, withAttributes: annotation.textAttributes)
            case .mosaic:
                NSGraphicsContext.saveGraphicsState()
                let stroke = CGMutablePath()
                stroke.move(to: start)
                for point in annotation.points.dropFirst() { stroke.addLine(to: point) }
                let mask: CGPath
                if annotation.points.allSatisfy({ $0 == start }) {
                    mask = CGPath(ellipseIn: CGRect(x: start.x - annotation.width / 2,
                        y: start.y - annotation.width / 2, width: annotation.width, height: annotation.width), transform: nil)
                } else {
                    mask = stroke.copy(strokingWithWidth: annotation.width, lineCap: .round,
                                       lineJoin: .round, miterLimit: 1)
                }
                NSGraphicsContext.current?.cgContext.addPath(mask)
                NSGraphicsContext.current?.cgContext.clip()
                NSGraphicsContext.current?.imageInterpolation = .none
                mosaicImage.draw(in: bounds)
                NSGraphicsContext.restoreGraphicsState()
            case .crop, .eraser: break
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    func renderedImage() throws -> NSImage {
        commitPendingText()
        guard canExport, let selection = state.selection else { throw ImageExporterError.failedToRender }
        let crop = selection.integral.intersection(bounds)
        let bitmap = try Self.bitmap(size: crop.size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.cgContext.translateBy(x: -crop.minX, y: -crop.minY)
        image.draw(in: bounds)
        drawAnnotations(state.annotations)
        let result = NSImage(size: crop.size)
        result.addRepresentation(bitmap)
        return result
    }

    private static func bitmap(size: CGSize) throws -> NSBitmapImageRep {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw ImageExporterError.failedToRender
        }
        return bitmap
    }
}
