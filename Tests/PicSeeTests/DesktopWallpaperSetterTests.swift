import AppKit
import ImageIO
import Testing
@testable import PicSee

@MainActor
struct DesktopWallpaperSetterTests {
    private func image() throws -> NSImage {
        let context = try #require(CGContext(data: nil, width: 12, height: 8,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        return NSImage(cgImage: try #require(context.makeImage()), size: CGSize(width: 6, height: 4))
    }

    @Test func savesFullResolutionPNGAndRetainsPreviousWallpapers() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let setter = DesktopWallpaperSetter(store: DesktopWallpaperStore(directory: directory))
        var urls: [URL] = []
        for _ in 0..<2 {
            try await setter.set(image()) { url in
                #expect(Thread.isMainThread)
                let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
                let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
                #expect(decoded.width == 12 && decoded.height == 8)
                #expect(url.pathExtension == "png")
                urls.append(url)
            }
        }
        #expect(urls[0] != urls[1])
        #expect(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func rejectedWallpaperIsRemovedAndErrorPropagates() async throws {
        enum Failure: Error { case rejected }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let setter = DesktopWallpaperSetter(store: DesktopWallpaperStore(directory: directory))
        var rejectedURL: URL?
        do {
            try await setter.set(image()) { url in
                rejectedURL = url
                throw Failure.rejected
            }
            Issue.record("Expected wallpaper setting to fail")
        } catch Failure.rejected {
            let url = try #require(rejectedURL)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }
}
