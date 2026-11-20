import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()

application.delegate = delegate
delegate.configureDockIcon(for: application)
application.run()
