import CoreGraphics

struct ImageNavigationVisibility: Equatable {
    let previous: Bool
    let next: Bool
}

enum ImageNavigationVisibilityPolicy {
    static let edgeFraction: CGFloat = 0.20

    static func visibility(
        pointerX: CGFloat?,
        viewerWidth: CGFloat,
        hasPrevious: Bool,
        hasNext: Bool,
        revealsAvailableDirections: Bool
    ) -> ImageNavigationVisibility {
        if revealsAvailableDirections {
            return ImageNavigationVisibility(previous: hasPrevious, next: hasNext)
        }

        guard
            viewerWidth > 0,
            let pointerX,
            (0...viewerWidth).contains(pointerX)
        else {
            return ImageNavigationVisibility(previous: false, next: false)
        }

        let edgeWidth = viewerWidth * edgeFraction
        if pointerX <= edgeWidth {
            return ImageNavigationVisibility(previous: hasPrevious, next: false)
        }
        if pointerX >= viewerWidth - edgeWidth {
            return ImageNavigationVisibility(previous: false, next: hasNext)
        }
        return ImageNavigationVisibility(previous: false, next: false)
    }
}
