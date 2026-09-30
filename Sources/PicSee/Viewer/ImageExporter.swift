import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageExportFormat: Equatable {
    case jpeg(quality: CGFloat)
    case png

    var contentType: UTType {
        switch self {
        case .jpeg:
            return .jpeg
        case .png:
            return .png
        }
    }

    var pathExtension: String {
        switch self {
        case .jpeg:
            return "jpg"
        case .png:
            return "png"
        }
    }

    var destinationProperties: [CFString: Any] {
        switch self {
        case .jpeg(let quality):
            return [kCGImageDestinationLossyCompressionQuality: min(max(quality, 0), 1)]
        case .png:
            return [:]
        }
    }
}

struct ImageExportOptions: Equatable {
    let format: ImageExportFormat
    let pixelSize: CGSize?
}

enum ImageExporterError: LocalizedError {
    case missingCGImage
    case invalidDestination
    case failedToRender
    case renderTooLarge
    case failedToFinalize

    var errorDescription: String? {
        switch self {
        case .missingCGImage: L10n.text("无法读取图片像素。")
        case .invalidDestination: L10n.text("无法创建导出文件，请检查保存位置。")
        case .failedToRender: L10n.text("无法生成图片，请检查选区和尺寸。")
        case .renderTooLarge: L10n.text("输出尺寸超过当前内存预算，请减小选区或输出尺寸。")
        case .failedToFinalize: L10n.text("无法完成图片保存。")
        }
    }
}

enum ImageExporter {
    static func export(_ image: NSImage, to url: URL, options: ImageExportOptions) throws {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageExporterError.missingCGImage
        }

        let outputImage = try renderedImage(from: source, format: options.format, pixelSize: options.pixelSize)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            options.format.contentType.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageExporterError.invalidDestination
        }

        CGImageDestinationAddImage(destination, outputImage, options.format.destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageExporterError.failedToFinalize
        }
    }

    static func pixelSize(of image: NSImage) -> CGSize? {
        // CG-backed snapshot representations can report screen-scaled dimensions
        // (for example 160×80 for an 80×40 CGImage on Retina). Only bitmap
        // representations carry authoritative stored-pixel dimensions.
        let sizes = image.representations.compactMap { representation -> CGSize? in
            guard let bitmap = representation as? NSBitmapImageRep,
                  bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { return nil }
            return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }

        if let largest = sizes.max(by: { lhs, rhs in
            lhs.width * lhs.height < rhs.width * rhs.height
        }) {
            return largest
        }

        if let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: source.width, height: source.height)
        }
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        return CGSize(width: image.size.width.rounded(), height: image.size.height.rounded())
    }

    private static func renderedImage(
        from source: CGImage,
        format: ImageExportFormat,
        pixelSize: CGSize?
    ) throws -> CGImage {
        let (targetWidth, targetHeight) = try ImageRenderBudget.dimensions(for: CGSize(
            width: pixelSize?.width ?? CGFloat(source.width), height: pixelSize?.height ?? CGFloat(source.height)))

        if targetWidth == source.width, targetHeight == source.height, case .png = format {
            return source
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw ImageExporterError.failedToRender
        }

        if case .jpeg = format {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        guard let output = context.makeImage() else {
            throw ImageExporterError.failedToRender
        }
        return output
    }
}
