import AppKit
import SwiftUI

/// Use the native minimal well to keep custom colors visually close to the presets.
struct ScreenshotColorWell: NSViewRepresentable {
    @Binding var color: NSColor

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.colorWellStyle = .minimal
        well.supportsAlpha = false
        well.color = color
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        well.setAccessibilityLabel("自定义标注颜色")
        well.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.parent = self
        if !well.color.isEqual(color) { well.color = color }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ScreenshotColorWell
        init(parent: ScreenshotColorWell) { self.parent = parent }

        @objc func colorChanged(_ sender: NSColorWell) {
            parent.color = sender.color
        }
    }
}
