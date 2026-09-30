import Foundation

/// Bound each full-resolution render buffer, including overflow, before AppKit
/// or Core Graphics allocates it. Viewing and source-pixel coordinates stay intact.
enum ImageRenderBudget {
    static let maximumBitmapBytes = min(UInt64(512 * 1024 * 1024), ProcessInfo.processInfo.physicalMemory / 8)

    static func dimensions(for size: CGSize, maximumBytes: UInt64 = maximumBitmapBytes) throws -> (width: Int, height: Int) {
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1,
              size.width < CGFloat(Int.max), size.height < CGFloat(Int.max) else {
            throw ImageExporterError.failedToRender
        }
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        let (pixels, overflow) = UInt64(width).multipliedReportingOverflow(by: UInt64(height))
        guard !overflow, pixels <= maximumBytes / 4 else { throw ImageExporterError.renderTooLarge }
        return (width, height)
    }
}
