let win = Window(width: 800, height: 500, pad: 12)
win.addSidebar(Sidebar(pad: 12, inset: 6))
// win.addPanel(Term(pad: 12, inset: 6))

let bridge = Bridge()
bridge.manage(window: win)

bridge.run()
win.run()
