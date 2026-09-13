import Foundation

/// File dragging takes over only after leaving the entire window, not the image
/// or canvas bounds. Distances are screen points, independent of Retina scale.
enum ImageDragPolicy {
    static let minimumDistance: CGFloat = 12
    static let outsideMargin: CGFloat = 12

    static func shouldExport(start: CGPoint, current: CGPoint, windowFrame: CGRect) -> Bool {
        guard !windowFrame.isEmpty else { return false }
        let distance = hypot(current.x - start.x, current.y - start.y)
        return distance >= minimumDistance
            && !windowFrame.insetBy(dx: -outsideMargin, dy: -outsideMargin).contains(current)
    }
}
