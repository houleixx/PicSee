import AppKit
import SwiftUI

/// Use the same native text renderer and font before and during editing.
struct ScreenshotDimensionInput: NSViewRepresentable {
    let title: String
    @Binding var text: String
    let onFocusChange: (Bool) -> Void
    let onCommit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = ScreenshotDimensionField(string: text)
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        field.textColor = .labelColor
        field.alignment = .center
        field.cell?.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.delegate = context.coordinator
        let coordinator = context.coordinator
        field.onFocusChange = { [weak coordinator] in coordinator?.parent.onFocusChange($0) }
        field.setAccessibilityLabel(title)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        // Avoid resetting the field editor's selection on every keystroke.
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ScreenshotDimensionInput
        init(parent: ScreenshotDimensionInput) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onCommit()
            return true
        }
    }
}

/// Editing notifications alone start only after the first keystroke. Report
/// actual focus too, so a click or Tab immediately updates the focus outline.
final class ScreenshotDimensionField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override func selectText(_ sender: Any?) {
        super.selectText(sender)
        if currentEditor() != nil { onFocusChange?(true) }
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange?(false)
    }
}
