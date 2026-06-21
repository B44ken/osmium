import Foundation

// All logs (app + inherited by the agent bridge) → log.txt at repo root.
let logPath = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "log.txt").path
freopen(logPath, "a", stdout)
freopen(logPath, "a", stderr)
setvbuf(stdout, nil, _IOLBF, 0)   // line-buffer so tail -f shows lines promptly
setvbuf(stderr, nil, _IONBF, 0)   // unbuffered: crash messages must flush before the trap

let osm = Osmium()
