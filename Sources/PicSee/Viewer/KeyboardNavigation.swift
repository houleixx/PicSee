enum KeyboardNavigation {
    enum Action: Equatable {
        case previous
        case next
        case quit
        case none
    }

    static func action(for keyCode: UInt16) -> Action {
        switch keyCode {
        case 123, 126:
            return .previous
        case 124, 125:
            return .next
        case 53:
            return .quit
        default:
            return .none
        }
    }
}
