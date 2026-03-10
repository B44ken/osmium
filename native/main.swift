import AppKit

let app = NSApplication.shared
let delegate = App()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
