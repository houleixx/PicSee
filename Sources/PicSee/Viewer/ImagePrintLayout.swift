import AppKit

struct ImagePrintSettings: Equatable {
    enum Sizing: Int { case scale, fit, fill }
    var automaticallyRotates = true
    var sizing: Sizing = .fit
    var fillsPaperWhenFitting = false
    var scalePercent = 100.0
    var copiesPerPage = 1

    private static let key = NSPrintInfo.AttributeKey("PicSeeImageSettings")

    init() {}

    init(printInfo: NSPrintInfo) {
        guard let values = printInfo.dictionary()[Self.key] as? [String: NSNumber] else { return }
        automaticallyRotates = values["rotate"]?.boolValue ?? true
        sizing = Sizing(rawValue: values["sizing"]?.intValue ?? 1) ?? .fit
        fillsPaperWhenFitting = values["fill"]?.boolValue ?? (sizing == .fill)
        let percent = values["scale"]?.doubleValue ?? 100
        scalePercent = percent.isFinite ? min(10000, max(1, percent)) : 100
        copiesPerPage = min(16, max(1, values["copies"]?.intValue ?? 1))
    }

    func store(in printInfo: NSPrintInfo) {
        printInfo.dictionary()[Self.key] = ["rotate": NSNumber(value: automaticallyRotates),
            "sizing": NSNumber(value: sizing.rawValue), "scale": NSNumber(value: scalePercent),
            "fill": NSNumber(value: sizing == .fill || (sizing == .scale && fillsPaperWhenFitting)),
            "copies": NSNumber(value: copiesPerPage)]
    }
}

/// Geometry is in paper points. Scaling 100% uses the image's physical size (including DPI).
struct ImagePrintLayout {
    struct Placement {
        let clip: CGRect
        let imageRect: CGRect
        let rotates: Bool
    }
    let placements: [Placement]

    init(imageSize: CGSize, pageSize: CGSize, settings: ImagePrintSettings) {
        guard imageSize.width > 0, imageSize.height > 0,
              pageSize.width > 0, pageSize.height > 0 else {
            placements = []
            return
        }
        let count = min(16, max(1, settings.copiesPerPage))
        // Pick the grid with the largest image area, allowing auto rotation in each cell.
        func fitScale(_ cell: CGSize) -> CGFloat {
            let normal = min(cell.width / imageSize.width, cell.height / imageSize.height)
            let rotated = min(cell.width / imageSize.height, cell.height / imageSize.width)
            return settings.automaticallyRotates ? max(normal, rotated) : normal
        }
        let columns = (1...count).max { lhs, rhs in
            func score(_ columns: Int) -> CGFloat {
                let rows = (count + columns - 1) / columns
                return fitScale(CGSize(width: pageSize.width / CGFloat(columns),
                                       height: pageSize.height / CGFloat(rows)))
            }
            return score(lhs) < score(rhs)
        } ?? 1
        let rows = (count + columns - 1) / columns
        let cell = CGSize(width: pageSize.width / CGFloat(columns), height: pageSize.height / CGFloat(rows))
        let normal = min(cell.width / imageSize.width, cell.height / imageSize.height)
        let rotated = min(cell.width / imageSize.height, cell.height / imageSize.width)
        let rotates = settings.automaticallyRotates && rotated > normal
        let size = rotates ? CGSize(width: imageSize.height, height: imageSize.width) : imageSize
        let scale: CGFloat
        switch settings.sizing {
        case .fit: scale = min(cell.width / size.width, cell.height / size.height)
        case .fill: scale = max(cell.width / size.width, cell.height / size.height)
        case .scale: scale = CGFloat(settings.scalePercent / 100)
        }
        placements = (0..<count).map { index in
            let clip = CGRect(x: CGFloat(index % columns) * cell.width,
                              y: pageSize.height - CGFloat(index / columns + 1) * cell.height,
                              width: cell.width, height: cell.height)
            let printedSize = CGSize(width: size.width * scale, height: size.height * scale)
            return Placement(clip: clip,
                imageRect: CGRect(x: clip.midX - printedSize.width / 2, y: clip.midY - printedSize.height / 2,
                                  width: printedSize.width, height: printedSize.height), rotates: rotates)
        }
    }
}
