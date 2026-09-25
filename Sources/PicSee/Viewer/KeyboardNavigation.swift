import AppKit

enum KeyboardNavigation {
    enum Action: Equatable {
        case previous
        case next
        case toggleSlideshowPause
        case endSlideshow
        case quit
        case toggleImageParameters
        case toggleFullScreen
        case screenshot
        case trash
        case undoDeletion
        case none
    }

    static func action(for keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], isRepeat: Bool = false, slideshowActive: Bool = false) -> Action {
        let commandModifiers = modifiers.intersection([.command, .control, .option, .shift])
        if keyCode == 3, commandModifiers.isEmpty || commandModifiers == [.control, .command] {
            return isRepeat ? .none : .toggleFullScreen
        }
        if commandModifiers == [.command, .shift], keyCode == 0 {
            return isRepeat ? .none : .screenshot
        }
        if commandModifiers == .command {
            if keyCode == 51 { return isRepeat ? .none : .trash }
            if keyCode == 6 { return isRepeat ? .none : .undoDeletion }
        }
        guard commandModifiers.isEmpty else { return .none }
        switch keyCode {
        case 51, 117:
            return isRepeat ? .none : .trash
        case 123, 126:
            return .previous
        case 124, 125:
            return .next
        case 49:
            return isRepeat ? .none : (slideshowActive ? .toggleSlideshowPause : .quit)
        case 53:
            return isRepeat ? .none : (slideshowActive ? .endSlideshow : .quit)
        case 34:
            return .toggleImageParameters
        default:
            return .none
        }
    }
}
