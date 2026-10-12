import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PicSee

@MainActor
struct LargeImageLoadingTests {
    @Test(arguments: [UTType.jpeg.identifier, UTType.png.identifier])
    func oversizedImagesKeepSourceSizeWithoutOversizedDisplayBitmaps(type: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let pixels = try #require(CGContext(data: nil, width: 64, height: 32768, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        pixels.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        pixels.fill(CGRect(x: 0, y: 0, width: 64, height: 16384))
        pixels.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        pixels.fill(CGRect(x: 0, y: 16384, width: 64, height: 16384))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(pixels.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        let loaded = try #require(LoadedImage.read(url))
        #expect(loaded.pixelSize == CGSize(width: 64, height: 32768))
        #expect(ImageExporter.pixelSize(of: loaded.image) == loaded.pixelSize)
        #expect(loaded.image.representations.allSatisfy { max($0.pixelsWide, $0.pixelsHigh) <= 2048 })
        let original = try #require(loaded.image.fullResolutionCGImage)
        #expect(original.width == 64)
        #expect(original.height == 32768)
    }
    @Test(arguments: Array(1...8))
    func tilesMatchOrientedPreviewAndCropsKeepNativeDetail(orientation: Int) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let context = try #require(CGContext(data: nil, width: 64, height: 9000, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for (x, y, color) in [(0,0,CGColor(red:1,green:0,blue:0,alpha:1)),
                              (32,0,CGColor(red:0,green:1,blue:0,alpha:1)),
                              (0,4500,CGColor(red:0,green:0,blue:1,alpha:1)),
                              (32,4500,CGColor(red:1,green:1,blue:0,alpha:1))] {
            context.setFillColor(color)
            context.fill(CGRect(x:x,y:y,width:32,height:4500))
        }
        // A native-pixel mark too small to survive the fitted preview.
        context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 4, y: 4, width: 4, height: 4))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()),
                                  [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let loaded = try #require(LoadedImage.read(url))
        let source = try #require(loaded.image.largeImageSource)
        let expectedSize = orientation >= 5 ? CGSize(width:9000,height:64) : CGSize(width:64,height:9000)
        #expect(loaded.pixelSize == expectedSize)
        let actual = try #require(CGContext(data:nil,width:128,height:128,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        actual.scaleBy(x: 128 / expectedSize.width, y: 128 / expectedSize.height)
        source.draw(in: actual)
        let expected = try #require(CGContext(data:nil,width:128,height:128,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        expected.draw(source.preview, in: CGRect(x:0,y:0,width:128,height:128))
        let actualPixels = NSBitmapImageRep(cgImage: try #require(actual.makeImage()))
        let expectedPixels = NSBitmapImageRep(cgImage: try #require(expected.makeImage()))
        for (x,y) in [(32,32),(96,32),(32,96),(96,96)] {
            let a = try #require(actualPixels.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB))
            let e = try #require(expectedPixels.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB))
            for (a,e) in zip([a.redComponent,a.greenComponent,a.blueComponent], [e.redComponent,e.greenComponent,e.blueComponent]) {
                #expect(abs(a-e) < 0.05)
            }
        }
        if orientation == 1 {
            let document = try ScreenshotDocument(image: loaded.image, rotationDegrees: 0)
            document.state.selection = CGRect(x:4,y:4,width:4,height:4)
            let cropped = try document.renderedImage()
            let pixels = NSBitmapImageRep(cgImage: try #require(cropped.fullResolutionCGImage))
            let mark = try #require(pixels.colorAt(x:2,y:2)?.usingColorSpace(.deviceRGB))
            #expect(mark.redComponent > 0.95)
            #expect(mark.blueComponent > 0.95)
            let referencePixels = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
            let reference = try #require(referencePixels.colorAt(x:6,y:8994)?.usingColorSpace(.deviceRGB))
            #expect(abs(mark.greenComponent - reference.greenComponent) < 0.02)
            let exported = url.appendingPathExtension("resized.png")
            defer { try? FileManager.default.removeItem(at:exported) }
            try ImageExporter.export(loaded.image, to:exported,
                options:ImageExportOptions(format:.png,pixelSize:CGSize(width:32,height:4500)))
            let saved = try #require(NSImage(contentsOf: exported))
            #expect(ImageExporter.pixelSize(of:saved) == CGSize(width:32,height:4500))
        }
    }

    @Test
    func missingSourceFailsCropInsteadOfSavingBlankPixels() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let context = try #require(CGContext(data: nil, width: 16, height: 9000, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 9000))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        let loaded = try #require(LoadedImage.read(url))
        let document = try ScreenshotDocument(image: loaded.image, rotationDegrees: 0)
        document.state.selection = CGRect(x: 0, y: 0, width: 16, height: 16)
        try FileManager.default.removeItem(at: url)
        #expect(throws: ImageExporterError.self) { try document.renderedImage() }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LARGE_IMAGE_FIXTURE"] != nil))
    func realGigapixelFixture() throws {
        let path = try #require(ProcessInfo.processInfo.environment["LARGE_IMAGE_FIXTURE"])
        let start = ContinuousClock.now
        let loaded = try #require(LoadedImage.read(URL(fileURLWithPath:path)))
        print("Gigapixel preview load: \(start.duration(to:.now)); pixels=\(String(describing:loaded.pixelSize))")
        let source = try #require(loaded.image.largeImageSource)
        if ProcessInfo.processInfo.environment["LARGE_IMAGE_TILE"] == "1" {
            let context = try #require(CGContext(data:nil,width:512,height:512,bitsPerComponent:8,bytesPerRow:0,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            context.translateBy(x:256-source.pixelSize.width/2,y:256-source.pixelSize.height/2)
            let tileStart = ContinuousClock.now
            source.draw(in:context)
            print("Gigapixel native tile: \(tileStart.duration(to:.now))")
            let pixels = NSBitmapImageRep(cgImage:try #require(context.makeImage()))
            try #require(pixels.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/tmp/picsee-large-diagnosis/native-tile.png"))
            let red = try #require(pixels.colorAt(x:240,y:128)?.usingColorSpace(.sRGB))
            #expect(red.redComponent > 0.95)
            #expect(red.greenComponent < 0.05)
            #expect(red.blueComponent < 0.05)
        }
        #expect(loaded.image.representations.allSatisfy { max($0.pixelsWide,$0.pixelsHigh) <= 2048 })
    }

}
