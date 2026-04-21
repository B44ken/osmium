import AppKit
import Foundation

private struct Command: Decodable {
    let cmd: String
    let msg: String?
}

final class Bridge: @unchecked Sendable {
    weak var win: Window?

    func manage(window: Window) { self.win = window }

    func run() {
        Thread {
            while let line = readLine(),
                  let cmd = try? JSONDecoder().decode(Command.self, from: Data(line.utf8)) {
                DispatchQueue.main.async {
                    switch cmd.cmd {
                    case "set_text": self.win?.sidebar?.setText(cmd.msg ?? "")
                    case "new_term": self.win?.addPanel(Term())
                    default: break
                    }
                }
            }
        }.start()
    }
}
