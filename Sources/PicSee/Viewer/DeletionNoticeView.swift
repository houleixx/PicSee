import SwiftUI

struct DeletionNoticeView: View {
    @Environment(\.colorScheme) private var colorScheme
    let canUndo: Bool
    let onUndo: () -> Void

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: PhosphorImages.trash)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("已移到废纸篓")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            if canUndo {
                DeletionUndoButton(onUndo: onUndo)
                    .frame(width: 40, height: 22)
                    .help("撤销移到废纸篓（⌘Z）")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDark ? Color(white: 0.16) : .white)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isDark ? Color.white.opacity(0.20) : Color.black.opacity(0.12), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(isDark ? 0.30 : 0.16), radius: 8, y: 3)
    }
}



private struct DeletionUndoButton: NSViewRepresentable {
    let onUndo: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "撤销", target: context.coordinator, action: #selector(Coordinator.undo))
        let cell = DefaultAppearanceButtonCell(textCell: "撤销")
        cell.bezelStyle = .rounded
        cell.setButtonType(.momentaryPushIn)
        button.cell = cell
        button.target = context.coordinator
        button.action = #selector(Coordinator.undo)
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.toolTip = "撤销移到废纸篓（⌘Z）"
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.onUndo = onUndo
    }

    func makeCoordinator() -> Coordinator { Coordinator(onUndo: onUndo) }

    final class Coordinator: NSObject {
        var onUndo: () -> Void
        init(onUndo: @escaping () -> Void) { self.onUndo = onUndo }
        @objc func undo() { onUndo() }
    }

    private final class DefaultAppearanceButtonCell: NSButtonCell {
        override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
            // Use the system default-button colors only while drawing, without binding Return to undo.
            let previousKeyEquivalent = keyEquivalent
            keyEquivalent = "\r"
            defer { keyEquivalent = previousKeyEquivalent }
            super.draw(withFrame: cellFrame, in: controlView)
        }
    }
}
