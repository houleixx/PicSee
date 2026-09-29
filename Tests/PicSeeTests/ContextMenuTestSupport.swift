import AppKit

@MainActor
extension NSMenu {
    var displayOptionsItems: [NSMenuItem] {
        items.first { $0.identifier == NSUserInterfaceItemIdentifier("PicSee.DisplayOptions") }?.submenu?.items ?? []
    }
}
