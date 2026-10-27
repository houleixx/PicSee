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
        let view = try ImagePrintView(image: image, rotationDegrees: rotationDegrees)
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = title ?? "PicSee"
        operation.printPanel.options.formUnion([.showsPaperSize, .showsOrientation, .showsPreview])
        return operation
    }

}

/// A snapshot of the original pixels, independent of the viewer's zoom and overlays.
@MainActor
final class ImagePrintView: NSView {
    private let pixels: CGImage
    private let rotation: CGFloat

    init(image: NSImage, rotationDegrees: Int) throws {
        if let size = ImageExporter.pixelSize(of: image) {
            _ = try ImageRenderBudget.dimensions(for: size)
        }
        guard let pixels = image.fullResolutionCGImage else { throw ImageExporterError.missingCGImage }
        self.pixels = pixels
        let degrees = ((rotationDegrees % 360) + 360) % 360
        rotation = CGFloat(degrees) * .pi / 180
        let swapsAxes = degrees == 90 || degrees == 270
        super.init(frame: CGRect(x: 0, y: 0,
                                width: swapsAxes ? pixels.height : pixels.width,
                                height: swapsAxes ? pixels.width : pixels.height))
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(bounds)
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: rotation)
        context.interpolationQuality = .high
        context.draw(pixels, in: CGRect(x: -CGFloat(pixels.width) / 2, y: -CGFloat(pixels.height) / 2,
                                       width: CGFloat(pixels.width), height: CGFloat(pixels.height)))
    }
}
