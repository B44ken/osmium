import Foundation

let logPath = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "log.txt").path
freopen(logPath, "a", stdout)
freopen(logPath, "a", stderr)
setvbuf(stdout, nil, _IOLBF, 0)
setvbuf(stderr, nil, _IONBF, 0)

let osm = Osmium()