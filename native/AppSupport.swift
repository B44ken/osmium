import AppKit
import CodeEditSourceEditor
import Foundation

extension NSView {
    func pin(to p: NSView, insets i: NSEdgeInsets = .init()) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: p.leadingAnchor, constant: i.left),
            trailingAnchor.constraint(equalTo: p.trailingAnchor, constant: -i.right),
            topAnchor.constraint(equalTo: p.topAnchor, constant: i.top),
            bottomAnchor.constraint(equalTo: p.bottomAnchor, constant: -i.bottom),
        ])
    }
}

extension NSVisualEffectView {
    func glass(_ mat: Material = .hudWindow, blend: BlendingMode = .withinWindow,
               radius: CGFloat = 14, border: NSColor? = nil, bg: NSColor? = nil) {
        material = mat
        blendingMode = blend
        state = .active
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.masksToBounds = true
        if let border {
            layer?.borderWidth = 1
            layer?.borderColor = border.cgColor
        }
        if let bg {
            layer?.backgroundColor = bg.cgColor
        }
        if #available(macOS 13.0, *) {
            layer?.cornerCurve = .continuous
        }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

func appColor(_ hex: String, alpha: CGFloat = 1.0) -> NSColor {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var v: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&v)
    if cleaned.count > 6 {
        return NSColor(
            calibratedRed: CGFloat((v >> 24) & 0xFF) / 255,
            green: CGFloat((v >> 16) & 0xFF) / 255,
            blue: CGFloat((v >> 8) & 0xFF) / 255,
            alpha: CGFloat(v & 0xFF) / 255
        )
    }
    return NSColor(
        calibratedRed: CGFloat((v >> 16) & 0xFF) / 255,
        green: CGFloat((v >> 8) & 0xFF) / 255,
        blue: CGFloat(v & 0xFF) / 255,
        alpha: alpha
    )
}

func animate(_ dur: Double = 0.15, body: @escaping @MainActor () -> Void) {
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = dur
        ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ctx.allowsImplicitAnimation = true
        body()
    }
}

func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

struct AppCommand: Decodable, Sendable {
    let type: String
    let cwd: String?
    let path: String?
    let url: String?
}

final class Cfg: Sendable {
    static let shared = Cfg()
    private let data: [String: String]

    init() {
        var d: [String: String] = [:]
        let path = NSHomeDirectory() + "/.osm/config"
        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            for line in content.split(separator: "\n") {
                guard let eq = line.firstIndex(of: "=") else { continue }
                d[String(line[line.startIndex..<eq])] = String(line[line.index(after: eq)...])
            }
        }
        data = d
    }

    func string(_ key: String) -> String { data[key]! }
    func optionalString(_ key: String) -> String? { data[key] }
    func float(_ key: String) -> CGFloat { CGFloat(Double(data[key]!)!) }
    func color(_ key: String) -> NSColor { appColor(data[key]!) }
}

let cfg = Cfg.shared

extension Cfg {
    var fontSize: CGFloat {
        float("options.font_size")
    }

    var monoFontName: String {
        string("options.font_mono")
    }

    var sansFontName: String {
        string("options.font_sans")
    }

    var tabsSlideDuration: Double {
        Double(float("options.tabs_slide_ms")) / 1000
    }

    var tabsSlideDelay: Double {
        Double(float("options.tabs_slide_delay")) / 1000
    }

    var windowMinWidth: CGFloat {
        float("window.min_width")
    }

    var windowMinHeight: CGFloat {
        float("window.min_height")
    }

    var windowMaxWidth: CGFloat {
        float("window.max_width")
    }

    var windowMaxHeight: CGFloat {
        float("window.max_height")
    }

    var tabsSidebarWidth: CGFloat {
        float("window.tabs_width")
    }

    var pickerSidebarWidth: CGFloat {
        tabsSidebarWidth
    }

    var startDirectory: String {
        optionalString("start_dir")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .ifEmpty(NSHomeDirectory())
            ?? NSHomeDirectory()
    }

    var font: NSFont {
        let s = fontSize
        let n = monoFontName
        return NSFont(name: n, size: s) ?? .monospacedSystemFont(ofSize: s, weight: .regular)
    }

    func font(_ w: NSFont.Weight) -> NSFont {
        let s = fontSize
        let n = monoFontName
        return NSFont(name: n, size: s) ?? .monospacedSystemFont(ofSize: s, weight: w)
    }

    func font(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let n = monoFontName
        return NSFont(name: n, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    var agentFont: NSFont {
        let s = fontSize
        let n = sansFontName
        return NSFont(name: n, size: s) ?? .systemFont(ofSize: s, weight: .regular)
    }

    func agentFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let n = sansFontName
        return NSFont(name: n, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    var editorTheme: EditorTheme {
        func a(_ key: String, bold: Bool = false) -> EditorTheme.Attribute {
            EditorTheme.Attribute(color: color(key), bold: bold)
        }

        return EditorTheme(
            text: a("theme.editor_text"),
            insertionPoint: color("theme.editor_cursor"),
            invisibles: a("theme.editor_invisibles"),
            background: color("theme.editor_bg"),
            lineHighlight: color("theme.editor_line_highlight"),
            selection: color("theme.editor_selection"),
            keywords: a("theme.editor_keywords", bold: true),
            commands: a("theme.editor_commands"),
            types: a("theme.editor_types"),
            attributes: a("theme.editor_attributes"),
            variables: a("theme.editor_variables"),
            values: a("theme.editor_values"),
            numbers: a("theme.editor_numbers"),
            strings: a("theme.editor_strings"),
            characters: a("theme.editor_characters"),
            comments: a("theme.editor_comments")
        )
    }
}
