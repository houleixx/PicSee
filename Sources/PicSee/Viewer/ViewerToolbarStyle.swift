import SwiftUI

/// Logical points shared by the viewing and screenshot toolbars.
enum ViewerToolbarMetrics {
    static let iconSize: CGFloat = 17
    static let strokeWidth: CGFloat = 2
    static let buttonSize: CGFloat = 34
    static let buttonHeight: CGFloat = buttonSize
    static let viewerButtonHeight: CGFloat = 30
    static let spacing: CGFloat = 6
    static let editorSpacing: CGFloat = 2
    static let editorGroupSpacing: CGFloat = 6
    static let horizontalPadding: CGFloat = 8
    static let viewerHorizontalPadding: CGFloat = 7
    static let viewerDividerPadding: CGFloat = 3
    static let viewerWidth = buttonSize * 8 + spacing * 8 + 1
        + viewerDividerPadding * 2 + viewerHorizontalPadding * 2
    static let editorWidth = buttonSize * 15 + editorSpacing * 12
        + editorGroupSpacing * 4 + 2 + horizontalPadding * 2
    static let secondaryForeground = Color.primary.opacity(0.72)
}

/// A single outline source keeps repeated actions identical across modes.
struct ViewerToolbarIcon: View {
    enum Symbol {
        case fit, actualSize, zoomOut, zoomIn, rotateLeft, rotateRight
        case copy, crop, undo, redo, cancel, confirm
    }

    let symbol: Symbol

    private var opticalScale: CGFloat {
        switch symbol {
        case .copy, .zoomOut, .zoomIn: return 0.94
        case .actualSize: return 0.96
        case .fit, .cancel: return 1.05
        default: return 1
        }
    }

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 24, y: size.height / 24)
            var path = Path()
            func line(_ points: [(CGFloat, CGFloat)]) {
                guard let first = points.first else { return }
                path.move(to: CGPoint(x: first.0, y: first.1))
                for point in points.dropFirst() {
                    path.addLine(to: CGPoint(x: point.0, y: point.1))
                }
            }
            switch symbol {
            case .fit:
                line([(4, 9), (4, 4), (9, 4)])
                line([(15, 4), (20, 4), (20, 9)])
                line([(20, 15), (20, 20), (15, 20)])
                line([(9, 20), (4, 20), (4, 15)])
            case .actualSize:
                path.addRoundedRect(in: CGRect(x: 4, y: 3, width: 16, height: 18),
                                    cornerSize: CGSize(width: 1, height: 1))
                line([(10, 9), (13, 7), (13, 17)])
            case .zoomOut, .zoomIn:
                path.addEllipse(in: CGRect(x: 3, y: 3, width: 14, height: 14))
                line([(15, 15), (21, 21)])
                line([(7, 10), (13, 10)])
                if symbol == .zoomIn { line([(10, 7), (10, 13)]) }
            case .rotateLeft, .rotateRight:
                if symbol == .rotateRight {
                    context.translateBy(x: 24, y: 0)
                    context.scaleBy(x: -1, y: 1)
                }
                path.move(to: CGPoint(x: 5, y: 8))
                path.addCurve(to: CGPoint(x: 20, y: 12),
                              control1: CGPoint(x: 9, y: 0), control2: CGPoint(x: 20, y: 3))
                path.addCurve(to: CGPoint(x: 6, y: 18),
                              control1: CGPoint(x: 20, y: 20), control2: CGPoint(x: 11, y: 23))
                line([(5, 3), (5, 8), (10, 8)])
            case .copy:
                path.addRoundedRect(in: CGRect(x: 3, y: 8, width: 13, height: 13),
                                    cornerSize: CGSize(width: 1, height: 1))
                line([(8, 8), (8, 3), (21, 3), (21, 16), (16, 16)])
            case .crop:
                line([(7.5, 3), (7.5, 16.5), (21, 16.5)])
                line([(3, 7.5), (16.5, 7.5), (16.5, 21)])
            case .undo, .redo:
                if symbol == .redo {
                    context.translateBy(x: 24, y: 0)
                    context.scaleBy(x: -1, y: 1)
                }
                line([(9, 4), (3, 10), (9, 16)])
                path.move(to: CGPoint(x: 3, y: 10))
                path.addLine(to: CGPoint(x: 14, y: 10))
                path.addCurve(to: CGPoint(x: 14, y: 21),
                              control1: CGPoint(x: 23, y: 10), control2: CGPoint(x: 23, y: 21))
                path.addLine(to: CGPoint(x: 11, y: 21))
            case .cancel:
                line([(5, 5), (19, 19)])
                line([(19, 5), (5, 19)])
            case .confirm:
                line([(3, 12), (9, 18), (21, 6)])
            }
            // Adjust the outline around its center while preserving stroke weight
            // and the shared icon frame / button hit area.
            let balanced = path.applying(CGAffineTransform(
                a: opticalScale, b: 0, c: 0, d: opticalScale,
                tx: 12 * (1 - opticalScale), ty: 12 * (1 - opticalScale)
            ))
            context.stroke(balanced, with: .foreground,
                           style: StrokeStyle(lineWidth: ViewerToolbarMetrics.strokeWidth,
                                              lineCap: .round, lineJoin: .round))
        }
        .frame(width: ViewerToolbarMetrics.iconSize, height: ViewerToolbarMetrics.iconSize)
        .accessibilityHidden(true)
    }
}

struct ViewerToolbarDivider: View {
    var color: Color = .primary

    var body: some View {
        Rectangle().fill(color.opacity(0.22)).frame(width: 1, height: 18)
            .accessibilityHidden(true)
    }
}

struct ViewerToolbarButtonStyle: ButtonStyle {
    var selected = false
    var tint: Color?
    var foreground: Color = .primary
    var cornerRadius: CGFloat = 8
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.accentColor : (tint ?? foreground))
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.3)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovered)
            .animation(.easeOut(duration: 0.12), value: selected)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        let pressed = isEnabled && isPressed
        let hovering = isEnabled && hovered
        if selected {
            return Color.accentColor.opacity(pressed ? 0.22 : (hovering ? 0.17 : 0.12))
        }
        return foreground.opacity(pressed ? 0.14 : (hovering ? 0.07 : 0))
    }
}
