import AppKit

enum KeyboardNavigation {
    enum Action: Equatable {
        case previous
        case next
        case rotateLeft
        case rotateRight
        case zoomIn
        case zoomOut
        case toggleSlideshowPause
        case endSlideshow
        case exitFullScreen
        case quit
        case toggleImageParameters
        case toggleFullScreen
        case toggleAlwaysOnTop
        case printImage
        case screenshot
        case trash
        case undoDeletion
        case none
    }

    static func action(for keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], charactersIgnoringModifiers: String? = nil, isRepeat: Bool = false, slideshowActive: Bool = false, isFullScreen: Bool = false) -> Action {
        let commandModifiers = modifiers.intersection([.command, .control, .option, .shift])
        if commandModifiers == [.control, .command], keyCode == 17 {
            return isRepeat ? .none : .toggleAlwaysOnTop
        }
        // Printable shortcuts follow the active keyboard layout. The physical-key
        // fallback also supports callers that do not provide event characters.
        let zoomInKey: Bool
        let zoomOutKey: Bool
        if let charactersIgnoringModifiers, !charactersIgnoringModifiers.isEmpty {
            zoomInKey = charactersIgnoringModifiers == "+" || charactersIgnoringModifiers == "="
            zoomOutKey = charactersIgnoringModifiers == "-"
        } else {
            zoomInKey = keyCode == 24
            zoomOutKey = keyCode == 27
        }
        if (commandModifiers == .command || commandModifiers == [.command, .shift]), zoomInKey {
            return .zoomIn
        }
        if commandModifiers == .command {
            if keyCode == 126 { return .zoomIn }
            if keyCode == 125 { return .zoomOut }
            if keyCode == 69 || keyCode == 81 { return .zoomIn } // Keypad + and =
            if zoomOutKey || keyCode == 78 { return .zoomOut } // Main and keypad -
        }
        if keyCode == 3, commandModifiers.isEmpty || commandModifiers == [.control, .command] {
            return isRepeat ? .none : .toggleFullScreen
        }
        if commandModifiers == [.command, .shift], keyCode == 0 {
            return isRepeat ? .none : .screenshot
        }
        if commandModifiers == .command {
            if keyCode == 35 { return isRepeat ? .none : .printImage }
            if keyCode == 123 { return isRepeat ? .none : .rotateLeft }
            if keyCode == 124 { return isRepeat ? .none : .rotateRight }
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
            if isRepeat { return .none }
            if slideshowActive { return .endSlideshow }
            return isFullScreen ? .exitFullScreen : .quit
        case 34:
            return .toggleImageParameters
        default:
            return .none
        }
    }
}
