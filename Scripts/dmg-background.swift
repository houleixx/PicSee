import AppKit

// Keep the 560 × 340 point canvas and icon row aligned with dmg-settings.py.
// dmgbuild combines the two PNGs into a Retina-aware TIFF inside the image.
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let canvas = NSSize(width: 560, height: 340)

for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas.width) * scale,
        pixelsHigh: Int(canvas.height) * scale, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    bitmap.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    NSColor(srgbRed: 0.95, green: 0.96, blue: 0.97, alpha: 1).setFill()
    NSRect(origin: .zero, size: canvas).fill()

    func centeredText(_ text: String, top: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color
        ])
        let textSize = attributed.size()
        attributed.draw(at: NSPoint(x: (canvas.width - textSize.width) / 2,
                                    y: canvas.height - top - textSize.height))
    }

    centeredText("安装 PicSee", top: 40, size: 23, weight: .semibold,
                 color: NSColor(srgbRed: 0.16, green: 0.18, blue: 0.21, alpha: 1))
    centeredText("拖入应用程序以安装", top: 276, size: 15, weight: .medium,
                 color: NSColor(srgbRed: 0.36, green: 0.39, blue: 0.44, alpha: 1))

    let rowY = canvas.height - 164
    // Three quiet, rounded chevrons indicate the drag direction.
    NSColor(srgbRed: 0.72, green: 0.74, blue: 0.77, alpha: 1).setStroke()
    for centerX: CGFloat in [261, 280, 299] {
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: centerX - 3.5, y: rowY + 7))
        chevron.line(to: NSPoint(x: centerX + 3.5, y: rowY))
        chevron.line(to: NSPoint(x: centerX - 3.5, y: rowY - 7))
        chevron.lineWidth = 4.5
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        chevron.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()

    let filename = scale == 1 ? "background.png" : "background@2x.png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: outputDirectory.appendingPathComponent(filename))
}
