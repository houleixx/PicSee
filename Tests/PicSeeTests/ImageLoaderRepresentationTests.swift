import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PicSee

@MainActor
struct ImageLoaderRepresentationTests {
    @Test(arguments: [false, true])
    func largePNGPreservesSourcePixelsLogicalSizeAndTransparency(transparent: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("long.png")
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: 64, pixelsHigh: 4096, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let bytes = try #require(bitmap.bitmapData)
        for row in 0..<bitmap.pixelsHigh {
            for column in 0..<bitmap.pixelsWide {
                let offset = row * bitmap.bytesPerRow + column * 4
                bytes[offset] = UInt8(row % 256)
                bytes[offset + 1] = UInt8(column * 3)
                bytes[offset + 2] = 97
                bytes[offset + 3] = transparent && row == 4095 && column == 63 ? 128 : 255
            }
        }
        bitmap.size = NSSize(width: 32, height: 2048) // Preserve non-72dpi source sizing.
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        let original = try #require(NSImage(contentsOf: url))
        let loaded = try #require(LoadedImage.read(url))
        #expect(loaded.image.size == original.size)
        #expect(loaded.pixelSize == CGSize(width: 64, height: 4096))
        #expect(ImageExporter.pixelSize(of: loaded.image) == loaded.pixelSize)
        let exportedURL = directory.appendingPathComponent("exported.png")
        try ImageExporter.export(loaded.image, to: exportedURL,
            options: ImageExportOptions(format: .png, pixelSize: ImageExporter.pixelSize(of: loaded.image)))
        let exported = try #require(NSImage(contentsOf: exportedURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(exported.width == 64)
        #expect(exported.height == 4096)
        #expect(loaded.containsTransparency == transparent)
        #expect(loaded.byteCount == Int64(try Data(contentsOf: url).count))
        #expect(loaded.metadata != nil)
        let sourceCG = try #require(original.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let displayCG = try #require(loaded.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(displayCG.width == sourceCG.width)
        #expect(displayCG.height == sourceCG.height)
        #expect(displayCG.bitsPerComponent == sourceCG.bitsPerComponent)
        let sourcePixels = NSBitmapImageRep(cgImage: sourceCG)
        let displayPixels = NSBitmapImageRep(cgImage: displayCG)
        for (x, y) in [(0, 0), (31, 1000), (63, 4095)] {
            let expected = try #require(sourcePixels.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            let actual = try #require(displayPixels.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            #expect(abs(expected.redComponent - actual.redComponent) < 0.001)
            #expect(abs(expected.greenComponent - actual.greenComponent) < 0.001)
            #expect(abs(expected.blueComponent - actual.blueComponent) < 0.001)
            #expect(abs(expected.alphaComponent - actual.alphaComponent) < 0.001)
        }
        // Enlarged viewing and exports must still select the full-resolution representation.
        var enlarged = NSRect(origin: .zero, size: original.size)
        let enlargedCG = try #require(loaded.image.cgImage(forProposedRect: &enlarged, context: nil, hints: nil))
        #expect(enlargedCG.height == 4096)
    }

    @Test(arguments: [UTType.gif.identifier, UTType.png.identifier])
    func multiFrameImagesKeepNativeFrameRepresentations(type: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).image")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 2, nil))
        let properties = [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: 0.1],
                          kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary
        for channel in [0, 2] {
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: 2, pixelsHigh: 4096, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let bytes = try #require(bitmap.bitmapData)
            for row in 0..<4096 {
                for column in 0..<2 {
                    let offset = row * bitmap.bytesPerRow + column * 4
                    for component in 0..<4 { bytes[offset + component] = component == channel || component == 3 ? 255 : 0 }
                }
            }
            CGImageDestinationAddImage(destination, try #require(bitmap.cgImage), properties)
        }
        #expect(CGImageDestinationFinalize(destination))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 2)
        let original = try #require(NSImage(contentsOf: url))
        let loaded = try #require(LoadedImage.read(url))
        let originalBitmap = try #require(original.representations.first as? NSBitmapImageRep)
        let loadedBitmap = try #require(loaded.image.representations.first as? NSBitmapImageRep)
        #expect(loaded.image.representations.count == original.representations.count)
        #expect((loadedBitmap.value(forProperty: .frameCount) as? NSNumber)
                == (originalBitmap.value(forProperty: .frameCount) as? NSNumber))
    }

    @Test
    func highBitDepthPNGKeepsNativePrecision() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: 2, pixelsHigh: 4096, bitsPerSample: 16, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let bytes = try #require(bitmap.bitmapData)
        for offset in 0..<bitmap.bytesPerRow * bitmap.pixelsHigh { bytes[offset] = 255 }
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        let original = try #require(NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let loaded = try #require(LoadedImage.read(url))
        let result = try #require(loaded.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(original.bitsPerComponent == 16)
        #expect(result.bitsPerComponent == 16)
        #expect(result.width == original.width)
        #expect(result.height == original.height)
    }
}
