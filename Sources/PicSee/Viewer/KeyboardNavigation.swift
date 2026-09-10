import AppKit

enum KeyboardNavigation {
    enum Action: Equatable {
        case previous
        case next
        case quit
        case toggleImageParameters
        case trash
        case undoDeletion
        case none
    }

    static func action(for keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], isRepeat: Bool = false) -> Action {
        let commandModifiers = modifiers.intersection([.command, .control, .option, .shift])
        if commandModifiers == .command {
            if keyCode == 51 { return isRepeat ? .none : .trash }
            if keyCode == 6 { return isRepeat ? .none : .undoDeletion }
        }
        guard commandModifiers.isEmpty else { return .none }
        switch keyCode {
        case 123, 126:
            return .previous
        case 124, 125:
            return .next
        case 49, 53:
            return .quit
        case 34:
            return .toggleImageParameters
        default:
            return .none
        }
    }
}
