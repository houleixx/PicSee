import AppKit
import Testing
@testable import PicSee

@MainActor
struct TransparencyBackgroundTests {
    @Test(arguments: [false, true])
    func transparentAndSemitransparentPixelsRevealCheckerboard(darkAppearance: Bool) throws {
        let view = CanvasNSView(frame: NSRect(x: 0, y: 0, width: 96, height: 32), backend: .vision)
        view.appearance = NSAppearance(named: darkAppearance ? .darkAqua : .aqua)
        view.wantsLayer = true
        view.image = try pngImage()
        let pixels = try render(view)
        let gray = try color(pixels, x: 4)
        let white = try color(pixels, x: 12)
        let contrast = abs(gray.redComponent - white.redComponent)
        #expect(contrast > 0.18)
        #expect(contrast < 0.22)
        #expect(min(gray.redComponent, white.redComponent) > 0.79)
        #expect(gray.alphaComponent == 1)
        #expect(white.alphaComponent == 1)

        let halfRedOnGray = try color(pixels, x: 36)
        let halfRedOnWhite = try color(pixels, x: 44)
        #expect(halfRedOnGray.redComponent > halfRedOnGray.greenComponent + 0.3)
        #expect(abs(halfRedOnGray.greenComponent - halfRedOnWhite.greenComponent) > 0.01)

        let solidA = try color(pixels, x: 68)
        let solidB = try color(pixels, x: 76)
        #expect(solidA.redComponent > 0.98)
        #expect(solidA.redComponent > solidA.greenComponent + 0.7)
        #expect(abs(solidA.redComponent - solidB.redComponent) < 0.01)
        #expect(abs(solidA.greenComponent - solidB.greenComponent) < 0.01)

        let plainView = NSImageView(frame: view.frame)
        plainView.image = view.image
        plainView.imageScaling = .scaleProportionallyUpOrDown
        let disabled = try render(plainView)
        #expect(try color(disabled, x: 4).alphaComponent == 0)
        #expect(try color(disabled, x: 12).alphaComponent == 0)
        let solidWithoutBackground = try color(disabled, x: 68)
        #expect(abs(solidA.redComponent - solidWithoutBackground.redComponent) < 0.01)
        #expect(abs(solidA.greenComponent - solidWithoutBackground.greenComponent) < 0.01)
        // Preview rendering must leave the source PNG's transparency intact.
        let sourceData = try #require(view.image?.tiffRepresentation)
        let source = try #require(NSBitmapImageRep(data: sourceData))
        #expect(try color(source, x: 4).alphaComponent == 0)
    }

    @Test func emptyViewDoesNotDrawCheckerboard() throws {
        let view = CanvasNSView(frame: NSRect(x: 0, y: 0, width: 96, height: 32), backend: .vision)
        let pixels = try render(view)
        let first = try color(pixels, x: 4)
        let second = try color(pixels, x: 12)
        #expect(abs(first.redComponent - second.redComponent) < 0.01)
    }

    @Test func checkerboardStaysViewportSizedWhileImageZooms() throws {
        let view = CanvasNSView(frame: NSRect(x: 0, y: 0, width: 96, height: 32), backend: .vision)
        view.motionPreference = { true }
        view.image = try pngImage()
        for scale: CGFloat in [1, 2, 0.5, 1.25, 12, 1] {
            view.zoomScale = scale
            view.layoutSubtreeIfNeeded()
            let backgrounds = view.subviews.compactMap { $0 as? TransparencyBackgroundView }
            #expect(backgrounds.count == 2)
            #expect(backgrounds.allSatisfy { $0.bounds.size == view.bounds.size })
            #expect(backgrounds.allSatisfy { CATransform3DIsIdentity($0.layer!.transform) })
        }
        let pixels = try render(view)
        #expect(abs(try color(pixels, x: 4).redComponent - color(pixels, x: 12).redComponent) > 0.18)
    }

    @Test(arguments: [0.64, 0.8, 1.0, 1.25, 1.5625, 2.0])
    func checkerboardHasNoDarkSeamsAtFractionalScales(scale: CGFloat) throws {
        let pixels = try bitmap(width: 256, height: 256)
        let context = try #require(NSGraphicsContext(bitmapImageRep: pixels))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor(white: 0.2, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 256, height: 256).fill()
        context.cgContext.scaleBy(x: scale, y: scale)
        TransparencyBackground.draw(in: NSRect(x: 0, y: 0, width: 256 / scale, height: 256 / scale))
        var darkest: CGFloat = 1
        for y in 8..<248 {
            for x in 8..<248 {
                let color = try #require(pixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                darkest = min(darkest, color.redComponent)
            }
        }
        #expect(darkest > 0.79, "No tile seam may expose the dark canvas at scale \(scale)")
    }

    @Test func checkerboardIsAlwaysVisibleWithoutContextMenuToggle() throws {
        let suite = "PicSee.TransparencyBackgroundTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // An old installation's disabled preference must no longer hide the grid.
        defaults.set(false, forKey: "PicSee.TransparencyBackgroundVisible")
        let canvas = CanvasNSView(frame: NSRect(x: 0, y: 0, width: 96, height: 32), backend: .vision, defaults: defaults)
        canvas.image = try pngImage()
        canvas.layoutSubtreeIfNeeded()
        canvas.navigationDirection = 1
        canvas.image = try pngImage()
        canvas.layoutSubtreeIfNeeded()
        let menu = NSMenu()
        canvas.debugAppendPicSeeContextMenuItems(to: menu)
        #expect(!menu.items.contains { $0.title == "显示透明棋盘格" })
        let backgrounds = canvas.subviews.compactMap { $0 as? TransparencyBackgroundView }
        #expect(backgrounds.count == 2)
        for background in backgrounds {
            // Inspect both transition backgrounds independently of fade opacity.
            background.isHidden = false
            background.motionMask.removeAllAnimations()
            background.imageMask.removeAllAnimations()
            background.imageMask.opacity = 1
            let pixels = try render(background)
            let first = try color(pixels, x: 4)
            let second = try color(pixels, x: 12)
            #expect(first.alphaComponent == 1)
            #expect(second.alphaComponent == 1)
            #expect(abs(first.redComponent - second.redComponent) > 0.18)
        }
    }

    private func pngImage() throws -> NSImage {
        let bitmap = try bitmap()
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        context.cgContext.clear(CGRect(x: 0, y: 0, width: 96, height: 32))
        context.cgContext.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        context.cgContext.fill(CGRect(x: 32, y: 0, width: 32, height: 32))
        context.cgContext.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.cgContext.fill(CGRect(x: 64, y: 0, width: 32, height: 32))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        return try #require(NSImage(data: data))
    }

    private func bitmap(width: Int = 96, height: Int = 32) throws -> NSBitmapImageRep {
        try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    }

    private func render(_ view: NSView) throws -> NSBitmapImageRep {
        let pixels = try bitmap()
        view.layoutSubtreeIfNeeded()
        view.cacheDisplay(in: view.bounds, to: pixels)
        return pixels
    }

    private func color(_ pixels: NSBitmapImageRep, x: Int) throws -> NSColor {
        try #require(pixels.colorAt(x: x, y: 4)?.usingColorSpace(.deviceRGB))
    }
}
