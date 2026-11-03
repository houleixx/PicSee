import AppKit

@MainActor
enum ImagePrinter {
    static func present(image: NSImage, rotationDegrees: Int, title: String?, in window: NSWindow) {
        guard window.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        do {
            let operation = try makeOperation(image: image, rotationDegrees: rotationDegrees, title: title)
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.text("无法打印图片")
            alert.informativeText = L10n.errorDescription(error)
            alert.addButton(withTitle: L10n.text("好"))
            alert.beginSheetModal(for: window)
        }
    }

    static func makeOperation(image: NSImage, rotationDegrees: Int, title: String?) throws -> NSPrintOperation {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        useImagePageMargins(in: info)
        info.horizontalPagination = .clip
        info.verticalPagination = .clip
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        info.scalingFactor = 1
        let view = try ImagePrintView(image: image, rotationDegrees: rotationDegrees, printInfo: info)
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = title ?? "PicSee"
        operation.printPanel.options.formUnion([.showsPaperSize, .showsOrientation, .showsPreview])
        operation.printPanel.options.remove(.showsScaling)
        operation.printPanel.addAccessoryController(ImagePrintAccessoryController(printInfo: operation.printInfo, imageSize: view.physicalSize))
        return operation
    }

    static func useImagePageMargins(in info: NSPrintInfo) {
        // Image layout is centered on the sheet. Printer imageable bounds can be
        // asymmetric (for example 18 pt above and 41 pt below), shifting the image.
        // Keep a small symmetric inset, matching the reference image-print layout.
        let horizontalInset = min(12, max(0, (info.paperSize.width - 1) / 2))
        let verticalInset = min(12, max(0, (info.paperSize.height - 1) / 2))
        info.leftMargin = horizontalInset
        info.rightMargin = horizontalInset
        info.topMargin = verticalInset
        info.bottomMargin = verticalInset
    }
}

/// A snapshot of the original pixels, independent of the viewer's zoom and overlays.
@MainActor
final class ImagePrintView: NSView {
    private let pixels: CGImage
    private let rotation: CGFloat
    let physicalSize: CGSize
    private let printInfo: NSPrintInfo

    init(image: NSImage, rotationDegrees: Int, printInfo: NSPrintInfo) throws {
        self.printInfo = printInfo
        if let size = ImageExporter.pixelSize(of: image) {
            _ = try ImageRenderBudget.dimensions(for: size)
        }
        guard let pixels = image.fullResolutionCGImage else { throw ImageExporterError.missingCGImage }
        self.pixels = pixels
        let degrees = ((rotationDegrees % 360) + 360) % 360
        rotation = CGFloat(degrees) * .pi / 180
        let swapsAxes = degrees == 90 || degrees == 270
        let size = image.size
        let validSize = size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
            ? size : CGSize(width: pixels.width, height: pixels.height)
        physicalSize = swapsAxes ? CGSize(width: validSize.height, height: validSize.width) : validSize
        super.init(frame: CGRect(x: 0, y: 0,
                                width: swapsAxes ? pixels.height : pixels.width,
                                height: swapsAxes ? pixels.width : pixels.height))
    }

    required init?(coder: NSCoder) { nil }

    private var currentPrintInfo: NSPrintInfo { NSPrintOperation.current?.printInfo ?? printInfo }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        let info = currentPrintInfo
        info.scalingFactor = 1
        let size = CGSize(width: max(1, info.paperSize.width - info.leftMargin - info.rightMargin),
                          height: max(1, info.paperSize.height - info.topMargin - info.bottomMargin))
        setFrameSize(size)
        range.pointee = NSRange(location: 1, length: 1)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect { bounds }

    override func locationOfPrintRect(_ rect: NSRect) -> NSPoint {
        // NSView's default placement centers within the driver's imageable bounds,
        // even when our page margins are symmetric. Place explicitly on the sheet.
        NSPoint(x: currentPrintInfo.leftMargin, y: currentPrintInfo.bottomMargin)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(bounds)
        let layout = ImagePrintLayout(imageSize: physicalSize, pageSize: bounds.size,
                                     settings: ImagePrintSettings(printInfo: currentPrintInfo))
        for placement in layout.placements {
            context.saveGState()
            context.clip(to: placement.clip)
            let rect = placement.imageRect
            context.translateBy(x: rect.midX, y: rect.midY)
            context.rotate(by: rotation + (placement.rotates ? .pi / 2 : 0))
            context.interpolationQuality = .high
            let swapsAxes = abs(sin(rotation + (placement.rotates ? .pi / 2 : 0))) > 0.5
            let size = swapsAxes ? CGSize(width: rect.height, height: rect.width) : rect.size
            context.draw(pixels, in: CGRect(x: -size.width / 2, y: -size.height / 2,
                                           width: size.width, height: size.height))
            context.restoreGState()
        }
    }
}
