import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScreenshotEditorView: View {
    @ObservedObject var document: ScreenshotDocument
    @Environment(\.colorScheme) private var colorScheme
    let filename: String
    let imageRect: CGRect
    let onClose: () -> Void
    var onCopy: () -> Void = {}
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            ScreenshotCanvas(document: document, imageRect: imageRect, onCancel: onClose)
            VStack(spacing: 8) {
                Text(hint)
                    .font(.caption)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .allowsHitTesting(false)
                Spacer(minLength: 0)
                if document.canExport {
                    controls
                }
            }
            .padding(12)
        }
        .onExitCommand(perform: onClose)
        .alert("截图操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if document.canExport {
                HStack(spacing: 4) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(ScreenshotTool.toolbarOrder) { tool in
                                Button { document.commitPendingText(); document.tool = tool } label: {
                                    ScreenshotToolbarGlyph(tool: tool)
                                        .frame(width: 30, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(ScreenshotToolButtonStyle(selected: document.tool == tool)).help(tool.title).accessibilityLabel(tool.title)
                                .accessibilityAddTraits(document.tool == tool ? .isSelected : [])
                            }
                            Rectangle().fill(.primary.opacity(0.16)).frame(width: 1, height: 18)
                            Button { document.undo() } label: { historyIcon("arrow.uturn.backward") }
                            .buttonStyle(ScreenshotToolButtonStyle())
                                .disabled(document.undoStates.isEmpty).help("撤销（⌘Z）")
                                .keyboardShortcut("z", modifiers: .command)
                            Button { document.redo() } label: { historyIcon("arrow.uturn.forward") }
                            .buttonStyle(ScreenshotToolButtonStyle())
                                .disabled(document.redoStates.isEmpty).help("重做（⇧⌘Z）")
                                .keyboardShortcut("z", modifiers: [.command, .shift])
                        }
                    }
                    Rectangle().fill(.primary.opacity(0.16)).frame(width: 1, height: 18)
                    HStack(spacing: 4) {
                        Button(action: copy) { actionIcon("doc.on.doc") }
                            .buttonStyle(ScreenshotToolButtonStyle())
                            .help("复制截图").accessibilityLabel("复制截图")
                        Button(action: onClose) { actionIcon("xmark") }
                            .buttonStyle(ScreenshotToolButtonStyle(tint: colorScheme == .dark ? .red : Color(red: 0.78, green: 0.12, blue: 0.12)))
                            .keyboardShortcut(.cancelAction)
                            .help("取消截图（Esc）").accessibilityLabel("取消截图")
                        Button(action: save) { actionIcon("checkmark") }
                            .buttonStyle(ScreenshotToolButtonStyle(tint: colorScheme == .dark ? .green : Color(red: 0.05, green: 0.45, blue: 0.2)))
                            .help("保存截图…").accessibilityLabel("保存截图")
                    }
                    .fixedSize()
                }
                HStack(spacing: 4) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        toolSettings
                    }
                    Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 16)
                        .padding(.horizontal, 4)
                    ScreenshotSizeFields(document: document)
                }
                .frame(height: 28)

            }
        }
        .font(.system(size: 12))
        .controlSize(.small)
        .padding(10)
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 14, y: 5)
    }

    @ViewBuilder
    private var toolSettings: some View {
        switch document.tool {
        case .crop:
            Text("拖动边角调整选区")
                .font(.caption).foregroundStyle(.secondary).fixedSize()
        case .eraser:
            Text("点击或拖动删除标注")
                .font(.caption).foregroundStyle(.secondary).fixedSize()
        case .mosaic:
            HStack(spacing: 3) {
                Text("直径：").font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach([16, 40, 96], id: \.self) { size in
                    sizePreset(size, value: $document.mosaicDiameter, width: 22, title: "马赛克直径")
                }
                ScreenshotParameterSlider(value: $document.mosaicDiameter, title: "马赛克直径", range: 8...160)
            }.fixedSize()
        case .text:
            HStack(spacing: 4) {
                annotationColorPicker
                Text("字号：").font(.system(size: 11)).foregroundStyle(.secondary)
                ScreenshotParameterSlider(value: $document.fontSize, title: "字号", range: 12...96)

            }.fixedSize()
        default:
            HStack(spacing: 4) {
                annotationColorPicker
                Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 16)
                HStack(spacing: 2) {
                    Text("粗细：").font(.system(size: 11)).foregroundStyle(.secondary)
                    ForEach([2, 6, 12], id: \.self) { size in
                        sizePreset(size, value: $document.strokeWidth, width: 16, title: "画笔粗细")
                    }
                    ScreenshotParameterSlider(value: $document.strokeWidth, title: "画笔粗细", range: 2...32)

                }
            }.fixedSize()
        }
    }

    private func sizePreset(_ size: Int, value: Binding<CGFloat>, width: CGFloat, title: String) -> some View {
        Button { value.wrappedValue = CGFloat(size) } label: {
            Text("\(size)")
                .font(.system(size: 10).monospacedDigit())
                .frame(width: width, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(ScreenshotToolButtonStyle(selected: value.wrappedValue == CGFloat(size)))
        .help("\(title)：\(size) px")
        .accessibilityLabel("\(title) \(size) 像素")
        .accessibilityAddTraits(value.wrappedValue == CGFloat(size) ? .isSelected : [])
    }

    private var commonColors: [(name: String, color: NSColor)] {
        [("红色", .systemRed), ("黄色", .systemYellow), ("蓝色", .systemBlue), ("黑色", .black), ("绿色", .systemGreen)]
    }

    private var annotationColorPicker: some View {
        HStack(spacing: 2) {
            Text("颜色：").font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.trailing, 4)
            ForEach(commonColors.indices, id: \.self) { index in
                let preset = commonColors[index]
                let selected = document.color.isEqual(preset.color)
                Button { document.color = preset.color } label: {
                    Circle().fill(Color(nsColor: preset.color))
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 0.5))
                        .padding(2)
                        .overlay(Circle().stroke(selected ? Color.accentColor : .clear, lineWidth: 1))
                        .frame(width: 16, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(preset.name).accessibilityLabel("标注颜色：\(preset.name)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            ColorPicker("自定义颜色", selection: Binding(get: { Color(nsColor: document.color) },
                set: { document.color = NSColor($0) }), supportsOpacity: false)
                .labelsHidden().frame(width: 28)
                .help("自定义标注颜色")
                .padding(.leading, 4)
        }.fixedSize()
    }

    private func actionIcon(_ name: String) -> some View {
        ScreenshotToolbarGlyph(symbol: name)
            .frame(width: 30, height: 28)
            .contentShape(Rectangle())
    }

    private func historyIcon(_ name: String) -> some View {
        actionIcon(name)
    }

    private var hint: String {
        if !document.canExport { return "拖动图片选择截图区域，按 Esc 退出" }
        switch document.tool {
        case .crop: return "拖动选区内部移动；拖动边角调整大小；在外部拖动重新选择"
        case .text: return "点击框外确认；拖动文字移动，双击编辑，回车换行"
        case .eraser: return "点击或拖动删除标注；不会擦除原图像素"
        case .mosaic: return "按住鼠标用圆形画刷涂抹马赛克；在下方调整画刷直径"
        default: return "在选区内拖动添加标注；可随时切换“调整选区”修改裁剪范围"
        }
    }
    private func copy() {
        do {
            let image = try document.renderedImage()
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.writeObjects([image]) else { throw ImageExporterError.failedToRender }
            onCopy()
            onClose()
        } catch { errorMessage = error.localizedDescription }
    }
    private func save() {
        document.commitPendingText()
        guard let selection = document.state.selection else { return }
        let accessory = ScreenshotExportAccessoryView(
            sourceSize: selection.integral.intersection(document.bounds).size,
            displayScale: imageRect.width / document.pixelSize.width
        )
        let panel = NSSavePanel()
        panel.title = "保存截图"
        panel.appearance = ViewerTheme.current().appearance
        panel.accessoryView = accessory
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent + "-截图.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try ImageExporter.export(document.renderedImage(), to: url,
                                         options: accessory.exportOptions)
                onClose()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct ScreenshotSizeFields: View {
    @ObservedObject var document: ScreenshotDocument
    @State private var widthText = ""
    @State private var heightText = ""
    @State private var recordedResize = false
    @State private var lastAppliedSelection: CGRect?
    @FocusState private var focusedDimension: Dimension?
    private enum Dimension: Hashable { case width, height }

    var body: some View {
        HStack(spacing: 4) {
            Text("宽：").foregroundStyle(.secondary).fixedSize()
            dimensionField("选区宽度（像素）", text: $widthText, dimension: .width)
            Image(systemName: "multiply")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 14, height: 16)
                .accessibilityLabel("乘")
            Text("高：").foregroundStyle(.secondary).fixedSize()
            dimensionField("选区高度（像素）", text: $heightText, dimension: .height)
            Text("px").foregroundStyle(.secondary).fixedSize()
        }
        .font(.system(size: 11).monospacedDigit())
        .onAppear { synchronize() }
        .onChange(of: document.state.selection) { _, selection in
            let isTypingChange = selection == lastAppliedSelection
            if !isTypingChange { recordedResize = false }
            synchronize(preservingInput: isTypingChange)
        }
        .onChange(of: widthText) { _, _ in
            if focusedDimension == .width { apply(.width) }
        }
        .onChange(of: heightText) { _, _ in
            if focusedDimension == .height { apply(.height) }
        }
        .onChange(of: focusedDimension) { previous, _ in
            if let previous { commit(previous) }
            recordedResize = false
        }
    }

    private func dimensionField(_ title: String, text: Binding<String>, dimension: Dimension) -> some View {
        TextField(title, text: text)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 48)
            .focused($focusedDimension, equals: dimension)
            .onSubmit { commit(dimension) }
            .accessibilityLabel(title)
            .help("输入像素数即时调整选区；最大为图片尺寸")
    }

    private func commit(_ dimension: Dimension) {
        apply(dimension)
        synchronize()
    }

    private func apply(_ dimension: Dimension) {
        let text = dimension == .width ? widthText : heightText
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else { return }
        let changed: Bool
        if dimension == .width {
            changed = document.resizeSelection(width: value, recordUndo: !recordedResize)
        } else {
            changed = document.resizeSelection(height: value, recordUndo: !recordedResize)
        }
        recordedResize = recordedResize || changed
        lastAppliedSelection = document.state.selection
    }

    private func synchronize(preservingInput: Bool = false) {
        guard let selection = document.state.selection else { return }
        if !preservingInput || focusedDimension != .width {
            widthText = String(Int(selection.integral.width))
        }
        if !preservingInput || focusedDimension != .height {
            heightText = String(Int(selection.integral.height))
        }
    }

}

/// Keep every glyph optically centered inside the same compact button footprint.
private struct ScreenshotToolbarGlyph: View {
    var tool: ScreenshotTool?
    var symbol: String?

    var body: some View {
        Group {
            if let tool {
                if tool == .mosaic {
                    ScreenshotMosaicIcon().frame(width: 14, height: 14)
                } else {
                    ScreenshotToolOutline(tool: tool).frame(width: 20, height: 20)
                }
            } else if symbol == "checkmark" {
                Path { path in
                    path.move(to: CGPoint(x: 2, y: 8))
                    path.addLine(to: CGPoint(x: 7, y: 13))
                    path.addLine(to: CGPoint(x: 17, y: 3))
                }
                .stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                .frame(width: 19, height: 16)
            } else {
                Image(systemName: symbol ?? "circle")
                    .resizable().scaledToFit()
                    .symbolRenderingMode(.monochrome)
                    .frame(width: symbol == "xmark" ? 12 : 16, height: symbol == "xmark" ? 12 : 16)
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

/// A shared 24-unit grid and rounded stroke keep the annotation tools visually related.
private struct ScreenshotToolOutline: View {
    let tool: ScreenshotTool

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 24, y: size.height / 24)
            var path = Path()
            func line(_ points: [(CGFloat, CGFloat)]) {
                guard let first = points.first else { return }
                path.move(to: CGPoint(x: first.0, y: first.1))
                for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
            }
            switch tool {
            case .crop:
                line([(7.5, 4), (7.5, 16.5), (20, 16.5)])
                line([(4, 7.5), (16.5, 7.5), (16.5, 20)])
            case .arrow:
                line([(5, 19), (19, 5)])
                line([(8.5, 5), (19, 5), (19, 15.5)])
            case .ellipse:
                path.addEllipse(in: CGRect(x: 3.5, y: 5, width: 17, height: 14))
            case .rectangle:
                path.addRoundedRect(in: CGRect(x: 4, y: 5, width: 16, height: 14), cornerSize: CGSize(width: 2, height: 2))
            case .text:
                line([(5.5, 7), (5.5, 5.5), (18.5, 5.5), (18.5, 7)])
                line([(12, 5.5), (12, 18.5)])
                line([(8.75, 18.5), (15.25, 18.5)])
            case .pen:
                line([(5, 19), (7, 13), (16, 4), (20, 8), (11, 17), (5, 19)])
                line([(13, 7), (17, 11)])
                line([(7, 13), (11, 17)])
            case .highlighter:
                line([(8.5, 15.5), (6, 13), (14, 4), (20, 10), (12, 18), (8.5, 15.5)])
                line([(6, 13), (12, 18)])
                line([(8.5, 15.5), (5, 19), (8.5, 19), (10, 17.5)])
                line([(5, 21), (19, 21)])
            case .line:
                line([(5, 19), (19, 5)])
            case .eraser:
                line([(3, 14), (13, 4), (21, 12), (13, 20), (9, 20), (3, 14)])
                line([(8, 9), (16, 17)])
            case .mosaic:
                break
            }
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
        }
    }
}

/// The hit shape fills the original 30 × 28 pt button, including transparent padding.
private struct ScreenshotToolButtonStyle: ButtonStyle {
    var selected = false
    var tint: Color?
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.accentColor : (tint ?? Color.primary))
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.accentColor.opacity(0.18) :
                        Color.primary.opacity(configuration.isPressed ? 0.12 : (hovered && isEnabled ? 0.07 : 0)))
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.3)
            .onHover { hovered = $0 }
    }
}

/// Uneven shades and adjoining square pixels read as pixelation, rather than an app grid.
private struct ScreenshotMosaicIcon: View {
    private let shades: [Double] = [0.95, 0.4, 0.75, 0.3, 0.5, 0.85, 0.25, 0.7,
                                     0.8, 0.3, 1, 0.45, 0.35, 0.7, 0.5, 0.9]
    var body: some View {
        Canvas { context, size in
            let cell = size.width / 4
            for index in shades.indices {
                let rect = CGRect(x: CGFloat(index % 4) * cell, y: CGFloat(index / 4) * cell,
                                  width: cell, height: cell)
                context.opacity = shades[index]
                context.fill(Path(rect), with: .foreground)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ScreenshotCanvas: NSViewRepresentable {
    @ObservedObject var document: ScreenshotDocument
    let imageRect: CGRect
    let onCancel: () -> Void
    func makeNSView(context: Context) -> ScreenshotCanvasNSView {
        let view = ScreenshotCanvasNSView(document: document)
        view.displayImageRect = imageRect
        view.onCancel = onCancel
        return view
    }
    func updateNSView(_ nsView: ScreenshotCanvasNSView, context: Context) {
        nsView.displayImageRect = imageRect
        nsView.onCancel = onCancel
        nsView.synchronizeTextEditor()
        nsView.needsDisplay = true
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

/// Use the same padding for the text and AppKit's field editor at every font size.
private final class ScreenshotTextInputCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: rect).insetBy(dx: 10, dy: 8)
    }
    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                         delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: rect.insetBy(dx: 10, dy: 8), in: controlView, editor: textObj,
                     delegate: delegate, start: selStart, length: selLength)
    }
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                       delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: rect.insetBy(dx: 10, dy: 8), in: controlView, editor: textObj,
                   delegate: delegate, event: event)
    }
}

@MainActor
final class ScreenshotCanvasNSView: NSView, NSTextFieldDelegate {
    let document: ScreenshotDocument
    var displayImageRect: CGRect?
    var onCancel: (() -> Void)?
    private var textEditor: NSTextField?
    private var brushPointer: CGPoint?
    private var brushTrackingArea: NSTrackingArea?
    private var anchor: CGPoint?
    private var originalSelection: CGRect?
    private var handle: Int?
    private var moving = false
    private var movingTextIndex: Int?
    private var movingTextOrigin: CGPoint?
    private var textMoveRecorded = false
    private var cropGestureRecorded = false
    private var draft: ScreenshotAnnotation?
    private var activeTool: ScreenshotTool = .crop

    init(document: ScreenshotDocument) {
        self.document = document
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { window.acceptsMouseMovedEvents = true; window.makeFirstResponder(self) }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            textEditor?.layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
        needsDisplay = true
    }
    override func cancelOperation(_ sender: Any?) {
        if textEditor != nil { finishTextEditing(commit: false) } else { onCancel?() }
    }

    func synchronizeTextEditor() {
        guard document.pendingText != nil else {
            textEditor?.removeFromSuperview()
            textEditor = nil
            return
        }
    }

    private func beginTextEditing(at point: CGPoint) {
        document.beginText(at: point, displayScale: scale)
        guard let annotation = document.pendingText, let origin = annotation.points.first else { return }
        let field = NSTextField(string: "")
        field.cell = ScreenshotTextInputCell(textCell: "")
        field.isEditable = true
        field.isSelectable = true
        field.stringValue = annotation.text
        field.delegate = self
        field.placeholderString = "输入文字"
        field.font = .systemFont(ofSize: max(1, annotation.fontSize * scale), weight: .regular)
        field.textColor = annotation.color
        field.backgroundColor = .clear
        // Rounded native bezels have a fixed control-height drawing rect that clips
        // large annotation fonts. Use a padded, borderless cell with one custom outline.
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.usesSingleLineMode = false
        field.cell?.wraps = false
        field.cell?.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.wantsLayer = true
        field.layer?.cornerRadius = 6
        field.layer?.borderWidth = 1
        field.layer?.masksToBounds = true
        effectiveAppearance.performAsCurrentDrawingAppearance {
            field.layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
        field.setAccessibilityLabel("截图文字输入")
        let x = imageRect.minX + origin.x * scale - 10
        let y = imageRect.minY + origin.y * scale - 8
        let height = max(28, ceil((field.font?.ascender ?? 0) - (field.font?.descender ?? 0)
            + (field.font?.leading ?? 0)) + 16)
        field.frame = CGRect(x: x, y: min(y, bounds.maxY - height),
            width: max(30, min(80, bounds.maxX - x)), height: height)
        addSubview(field)
        textEditor = field
        resizeTextEditor(preservingTop: false)
        if document.editingTextIndex == nil {
            let center = CGPoint(x: imageRect.minX + point.x * scale, y: imageRect.minY + point.y * scale)
            field.setFrameOrigin(CGPoint(
                x: min(max(bounds.minX, center.x), max(bounds.minX, bounds.maxX - field.frame.width)),
                y: min(max(bounds.minY, center.y - field.frame.height / 2), max(bounds.minY, bounds.maxY - field.frame.height))))
        }
        synchronizeTextPosition()
        window?.makeFirstResponder(field)
        if let editor = field.currentEditor() as? NSTextView {
            editor.drawsBackground = false
            editor.textColor = annotation.color
            editor.setSelectedRange(NSRange(location: (annotation.text as NSString).length, length: 0))
        }
        needsDisplay = true
    }

    private func finishTextEditing(commit: Bool) {
        guard let field = textEditor else { return }
        // Detach the delegate before changing focus to avoid committing twice.
        field.delegate = nil
        document.pendingText?.text = field.stringValue
        if commit { document.commitPendingText() } else { document.cancelPendingText() }
        field.removeFromSuperview()
        textEditor = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = textEditor else { return }
        document.pendingText?.text = field.stringValue
        resizeTextEditor()
    }

    private func resizeTextEditor(preservingTop: Bool = true) {
        guard let field = textEditor, let font = field.font else { return }
        let measuredText = field.stringValue.isEmpty ? "输入文字" : field.stringValue + "\u{200B}"
        let measured = (measuredText as NSString).size(withAttributes: [.font: font])
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let height = min(bounds.height, max(28, max(lineHeight, ceil(measured.height)) + 16))
        let width = max(30, min(max(80, ceil(measured.width) + 24), bounds.maxX - field.frame.minX))
        let y = preservingTop ? max(bounds.minY, field.frame.maxY - height) : min(field.frame.minY, bounds.maxY - height)
        field.frame = CGRect(x: field.frame.minX, y: y, width: width, height: height)
        synchronizeTextPosition()
        needsDisplay = true
    }

    private func synchronizeTextPosition() {
        guard let field = textEditor, var annotation = document.pendingText else { return }
        annotation.points = [CGPoint(x: (field.frame.minX + 10 - imageRect.minX) / scale,
                                     y: (field.frame.minY + 8 - imageRect.minY) / scale)]
        document.pendingText = annotation
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        finishTextEditing(commit: true)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            textView.insertNewlineIgnoringFieldEditor(nil)
            if let field = textEditor {
                field.stringValue = textView.string
                document.pendingText?.text = textView.string
                resizeTextEditor()
            }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishTextEditing(commit: false)
            return true
        }
        return false
    }

    override func scrollWheel(with event: NSEvent) {}
    override func magnify(with event: NSEvent) {}
    override func rotate(with event: NSEvent) {}

    private func movableText(at point: CGPoint) -> Int? {
        guard textEditor == nil, document.tool == .text || document.tool == .crop,
              document.state.selection?.contains(point) == true else { return nil }
        return document.state.annotations.indices.reversed().first {
            document.state.annotations[$0].tool == .text &&
            document.state.annotations[$0].hitBounds.insetBy(dx: -3 / scale, dy: -3 / scale).contains(point)
        }
    }
    override func resetCursorRects() {
        addCursorRect(imageRect, cursor: .crosshair)
        guard document.tool == .text || document.tool == .crop, let selection = document.state.selection else { return }
        for annotation in document.state.annotations where annotation.tool == .text {
            let rect = annotation.hitBounds.insetBy(dx: -3 / scale, dy: -3 / scale).intersection(selection)
            guard !rect.isNull else { continue }
            addCursorRect(CGRect(x: imageRect.minX + rect.minX * scale, y: imageRect.minY + rect.minY * scale,
                width: rect.width * scale, height: rect.height * scale), cursor: .openHand)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let brushTrackingArea { removeTrackingArea(brushTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        brushTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        brushPointer = convert(event.locationInWindow, from: nil)
        if textEditor == nil {
            (movableText(at: imagePoint(event)) != nil ? NSCursor.openHand : NSCursor.crosshair).set()
        }
        if document.tool == .mosaic { needsDisplay = true }
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseExited(with event: NSEvent) {
        brushPointer = nil
        needsDisplay = true
    }


    private var scale: CGFloat {
        if let displayImageRect { return max(0.0001, displayImageRect.width / document.pixelSize.width) }
        return max(0.0001, min((bounds.width - 40) / document.pixelSize.width,
                        (bounds.height - 40) / document.pixelSize.height))
    }
    private var imageRect: CGRect {
        if let displayImageRect { return displayImageRect }
        let size = CGSize(width: document.pixelSize.width * scale, height: document.pixelSize.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: (point.x - imageRect.minX) / scale, y: (point.y - imageRect.minY) / scale)
    }
    private func handles(_ rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY),
         CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)]
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.translateBy(x: imageRect.minX, y: imageRect.minY)
        context.scaleBy(x: scale, y: scale)
        // Inline mode leaves the viewer image in place, including its transparency.
        if displayImageRect == nil { document.image.draw(in: document.bounds) }
        let visibleAnnotations = document.state.annotations.enumerated().compactMap { index, annotation in
            document.pendingText != nil && index == document.editingTextIndex ? nil : annotation
        }
        document.drawAnnotations(visibleAnnotations + (draft.map { [$0] } ?? []))
        let shade = NSBezierPath(rect: document.bounds)
        if let selection = document.state.selection { shade.appendRect(selection) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        shade.fill()
        if let selection = document.state.selection {
            let border = NSBezierPath(rect: selection)
            NSColor.black.withAlphaComponent(0.65).setStroke()
            border.lineWidth = 3 / scale
            border.stroke()
            NSColor.white.setStroke()
            border.lineWidth = 1 / scale
            border.stroke()
            if document.tool == .crop {
                for point in handles(selection) {
                    let handleRect = CGRect(x: point.x - 4 / scale, y: point.y - 4 / scale,
                                            width: 8 / scale, height: 8 / scale)
                    NSColor.controlAccentColor.setFill()
                    NSBezierPath(rect: handleRect).fill()
                    NSColor.white.setStroke()
                    let outline = NSBezierPath(rect: handleRect)
                    outline.lineWidth = 1 / scale
                    outline.stroke()
                }
            }
        }
        if document.tool == .mosaic, let brushPointer, let selection = document.state.selection {
            let center = CGPoint(x: (brushPointer.x - imageRect.minX) / scale,
                                 y: (brushPointer.y - imageRect.minY) / scale)
            if selection.contains(center) {
                let diameter = draft?.width ?? (document.mosaicDiameter / scale)
                let circle = NSBezierPath(ovalIn: CGRect(x: center.x - diameter / 2,
                    y: center.y - diameter / 2, width: diameter, height: diameter))
                NSColor.black.withAlphaComponent(0.8).setStroke()
                circle.lineWidth = 3 / scale
                circle.stroke()
                NSColor.white.setStroke()
                circle.lineWidth = 1 / scale
                circle.stroke()
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        if textEditor != nil {
            finishTextEditing(commit: true)
            window?.invalidateCursorRects(for: self)
            return
        }
        movingTextIndex = nil
        movingTextOrigin = nil
        textMoveRecorded = false
        brushPointer = convert(event.locationInWindow, from: nil)
        let point = imagePoint(event)
        let hitHandle = document.state.selection.flatMap { selection in
            handles(selection).firstIndex { hypot($0.x - point.x, $0.y - point.y) <= 9 / scale }
        }
        guard document.bounds.contains(point) || (document.tool == .crop && hitHandle != nil) else { return }
        window?.makeFirstResponder(self)
        if let index = movableText(at: point) {
            if event.clickCount >= 2 {
                beginTextEditing(at: point)
            } else {
                anchor = point
                movingTextIndex = index
                movingTextOrigin = document.state.annotations[index].points.first
                NSCursor.closedHand.set()
            }
            return
        }
        let startsNewSelection = !document.canExport ||
            (document.state.selection?.contains(point) == false && hitHandle == nil)
        activeTool = startsNewSelection ? .crop : document.tool
        anchor = document.clamp(point)
        originalSelection = document.state.selection
        handle = nil
        moving = false
        cropGestureRecorded = false
        if activeTool == .crop {
            handle = hitHandle
            moving = handle == nil && (originalSelection?.contains(point) ?? false)
            // Preserve the selection and tool until a real drag begins. Clearing here
            // briefly removes the annotation toolbar even for an ordinary outside click.
        } else {
            guard let selection = document.state.selection, selection.contains(point) else { anchor = nil; return }
            if activeTool == .text {
                anchor = nil
                beginTextEditing(at: point)
                return
            }
            // Arrows need a direction; a click alone must not create a head or history entry.
            if activeTool == .arrow { return }
            document.checkpoint()
            if activeTool == .eraser { document.erase(at: point) }
            else {
                draft = document.makeAnnotation(tool: activeTool, points: [point], displayScale: scale)
            }
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        brushPointer = convert(event.locationInWindow, from: nil)
        guard let anchor else { return }
        let point = document.clamp(imagePoint(event))
        if let index = movingTextIndex, let origin = movingTextOrigin, let selection = document.state.selection {
            guard document.state.annotations.indices.contains(index) else { return }
            let dx = point.x - anchor.x, dy = point.y - anchor.y
            guard textMoveRecorded || hypot(dx, dy) * scale >= 3 else { return }
            let size = document.state.annotations[index].hitBounds.size
            let moved = CGPoint(x: min(max(origin.x + dx, selection.minX), max(selection.minX, selection.maxX - size.width)),
                y: min(max(origin.y + dy, selection.minY), max(selection.minY, selection.maxY - size.height)))
            guard document.state.annotations[index].points.first != moved else { return }
            if !textMoveRecorded { document.checkpoint(); textMoveRecorded = true }
            document.state.annotations[index].points = [moved]
            NSCursor.closedHand.set()
            needsDisplay = true
            return
        }
        if activeTool == .crop {
            if !moving && handle == nil {
                // A new rectangle must be visible and contain at least one image pixel
                // in each dimension before it can replace the current selection.
                guard abs(point.x - anchor.x) >= max(1, 3 / scale),
                      abs(point.y - anchor.y) >= max(1, 3 / scale) else { return }
            }
            if !cropGestureRecorded {
                guard hypot(point.x - anchor.x, point.y - anchor.y) * scale >= 3 else { return }
                document.checkpoint()
                cropGestureRecorded = true
                document.tool = .crop
            }
            if let original = originalSelection, moving {
                // Preserve the displayed/exported pixel size while moving. Fractional
                // origins make CGRect.integral expand an integer-sized crop by one pixel.
                let crop = original.integral.intersection(document.bounds)
                let x = min(max((crop.minX + point.x - anchor.x).rounded(), 0), document.pixelSize.width - crop.width)
                let y = min(max((crop.minY + point.y - anchor.y).rounded(), 0), document.pixelSize.height - crop.height)
                document.state.selection = CGRect(origin: CGPoint(x: x, y: y), size: crop.size)
            } else if let original = originalSelection, let handle {
                var minX = original.minX, maxX = original.maxX, minY = original.minY, maxY = original.maxY
                if [0, 6, 7].contains(handle) { minX = min(point.x, maxX - 1) }
                if [2, 3, 4].contains(handle) { maxX = max(point.x, minX + 1) }
                if [0, 1, 2].contains(handle) { minY = min(point.y, maxY - 1) }
                if [4, 5, 6].contains(handle) { maxY = max(point.y, minY + 1) }
                document.state.selection = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            } else {
                document.state.selection = CGRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                    width: abs(point.x - anchor.x), height: abs(point.y - anchor.y))
            }
        } else if let selection = document.state.selection {
            let clipped = document.clamp(point, to: selection)
            if activeTool == .arrow {
                if draft == nil {
                    guard hypot(clipped.x - anchor.x, clipped.y - anchor.y) * scale >= 3 else { return }
                    document.checkpoint()
                    draft = document.makeAnnotation(tool: .arrow, points: [anchor, clipped], displayScale: scale)
                } else {
                    draft?.points = [anchor, clipped]
                }
            } else if activeTool == .eraser { document.erase(at: clipped) }
            else if activeTool == .pen || activeTool == .highlighter || activeTool == .mosaic { draft?.points.append(clipped) }
            else if activeTool != .text { draft?.points = [anchor, clipped] }
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if movingTextIndex != nil {
            movingTextIndex = nil
            movingTextOrigin = nil
            anchor = nil
            window?.invalidateCursorRects(for: self)
            NSCursor.openHand.set()
            return
        }
        guard anchor != nil else { return }
        if let draft { document.state.annotations.append(draft) }
        if !document.canExport {
            document.state.selection = originalSelection
        }
        anchor = nil
        draft = nil
        needsDisplay = true
    }
}

private struct ScreenshotParameterSlider: View {
    @Binding var value: CGFloat
    let title: String
    let range: ClosedRange<CGFloat>
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 3) {
                Text("\(Int(value)) px").monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 10))
            .frame(width: 40, height: 24)
            .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(ScreenshotToolButtonStyle())
        .help("调整\(title)")
        .accessibilityLabel("\(title)，当前 \(Int(value)) 像素")
        .popover(isPresented: $isPresented) {
            HStack(spacing: 10) {
                Text("\(title)：")
                Slider(value: Binding(get: { value }, set: { value = $0.rounded() }), in: range)
                    .frame(width: 140)
                    .accessibilityLabel(title)
                Text("\(Int(value)) px").monospacedDigit().frame(width: 48)
            }.padding(14)
        }
    }
}
