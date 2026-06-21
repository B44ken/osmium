import AppKit

@Observable
final class Keyboard {
    private let keyCodes: [UInt16: String] = [ 0:"a", 1:"s", 2:"d", 3:"f", 4:"h", 5:"g", 6:"z", 7:"x", 8:"c", 9:"v", 11:"b", 12:"q", 13:"w", 14:"e", 15:"r", 16:"y", 17:"t", 18:"1", 19:"2", 20:"3", 21:"4", 22:"6", 23:"5", 25:"9", 26:"7", 28:"8", 29:"0", 30:"]", 31:"o", 32:"u", 33:"[", 34:"i", 35:"p", 37:"l", 38:"j", 39:"'", 40:"k", 41:";", 42:"\\", 43:",", 44:"/", 45:"n", 46:"m", 47:".", 36:"return", 48:"tab", 49:"space", 50:"`", 51:"delete"]
    var opt = false
    var doSidebar = false
    var key: String?
    var callbacks: [(String, () -> Void)] = []
    var monitor: Any?

    func on(_ key: String, _ callback: @escaping () -> Void) { callbacks.append((key, callback)) }
    func handle() -> Bool {
        let combo = ((opt ? "opt " : "") + (key ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
        var matched = false
        for cb in callbacks { if cb.0 == combo { cb.1(); matched = true } }
        doSidebar = opt && (key == nil || key == "[" || key == "]")
        return matched
    }

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [self] ev in
            if ev.type == .flagsChanged { self.opt = ev.modifierFlags.contains(.option); return self.handle() ? nil : ev }
            if ev.type == .keyDown && !ev.isARepeat { self.key = keyCodes[ev.keyCode]; return self.handle() ? nil : ev }
            if ev.type == .keyUp { self.key = nil }
            return ev
        }
    }
}

final class Pipe {
    struct Cmd: Decodable { let cmd: String, type, path, id: String? }
    var fh: FileHandle?

    func getOne() -> Cmd? {
        if fh == nil {
            mkfifo("/tmp/osm.fifo", 0o644)
            fh = FileHandle(forReadingAtPath: "/tmp/osm.fifo")
        }

        var buf = Data()
        while true {
            guard let chunk = try? fh!.read(upToCount: 1), !chunk.isEmpty else { fh = nil; return nil }
            buf.append(chunk)
            if chunk.first == 0x0a { break }
        }
        return try? JSONDecoder().decode(Cmd.self, from: buf)
    }
}