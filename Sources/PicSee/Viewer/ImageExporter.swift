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

enum ImageExporterError: Error {
    case missingCGImage
    case invalidDestination
    case failedToRender
    case failedToFinalize
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
        let sizes = image.representations.compactMap { representation -> CGSize? in
            guard representation.pixelsWide > 0, representation.pixelsHigh > 0 else { return nil }
            return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }

        if let largest = sizes.max(by: { lhs, rhs in
            lhs.width * lhs.height < rhs.width * rhs.height
        }) {
            return largest
        }

        guard image.size.width > 0, image.size.height > 0 else { return nil }
        return CGSize(width: image.size.width.rounded(), height: image.size.height.rounded())
    }

    private static func renderedImage(
        from source: CGImage,
        format: ImageExportFormat,
        pixelSize: CGSize?
    ) throws -> CGImage {
        let targetWidth = Int((pixelSize?.width ?? CGFloat(source.width)).rounded())
        let targetHeight = Int((pixelSize?.height ?? CGFloat(source.height)).rounded())
        guard targetWidth > 0, targetHeight > 0 else {
            throw ImageExporterError.failedToRender
        }

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
