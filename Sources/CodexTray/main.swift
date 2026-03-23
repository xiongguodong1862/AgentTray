import AppKit
import CodexTrayFeature

let app = NSApplication.shared
let delegate = CodexTrayAppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
