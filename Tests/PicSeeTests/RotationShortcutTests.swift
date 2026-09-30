import AppKit
import Testing
@testable import PicSee

struct RotationShortcutTests {
    @Test(arguments: [UInt16(123), UInt16(124)])
    func commandArrowsRotateWithoutAffectingNavigation(keyCode: UInt16) {
        let rotation: KeyboardNavigation.Action = keyCode == 123 ? .rotateLeft : .rotateRight
        let navigation: KeyboardNavigation.Action = keyCode == 123 ? .previous : .next
        #expect(KeyboardNavigation.action(for: keyCode, modifiers: .command) == rotation)
        #expect(KeyboardNavigation.action(for: keyCode, modifiers: [.command, .capsLock]) == rotation)
        #expect(KeyboardNavigation.action(for: keyCode, modifiers: .command, isRepeat: true) == .none)
        #expect(KeyboardNavigation.action(for: keyCode) == navigation)
        #expect(KeyboardNavigation.action(for: keyCode, isRepeat: true) == navigation)
        for extra: NSEvent.ModifierFlags in [.shift, .option, .control] {
            #expect(KeyboardNavigation.action(for: keyCode, modifiers: [.command, extra]) == .none)
        }
    }
}
