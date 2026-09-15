import AppKit
import SwiftTerm

// one dark, the same palette the codemirror editor renders with (@codemirror/theme-one-dark);
// ansi 0-15 are the canonical one dark terminal colors
enum OneDark {
    static let bg = ns(0x282c34), fg = ns(0xabb2bf), cursor = ns(0x528bff), selection = ns(0x3e4451)
    // computed: SwiftTerm.Color is a mutable class, so it can't be a shared global
    static var ansi: [SwiftTerm.Color] {
        [0x1e2127, 0xe06c75, 0x98c379, 0xd19a66, 0x61afef, 0xc678dd, 0x56b6c2, 0xabb2bf,
         0x5c6370, 0xe06c75, 0x98c379, 0xd19a66, 0x61afef, 0xc678dd, 0x56b6c2, 0xffffff]
            .map { SwiftTerm.Color(red: chan($0, 16), green: chan($0, 8), blue: chan($0, 0)) }
    }

    // swiftterm holds 16 bits per channel; 0xff * 257 == 0xffff
    private static func chan(_ hex: Int, _ shift: Int) -> UInt16 { UInt16((hex >> shift) & 0xff) * 257 }
    private static func ns(_ hex: Int) -> NSColor {
        NSColor(deviceRed: CGFloat(chan(hex, 16)) / 65535, green: CGFloat(chan(hex, 8)) / 65535,
                blue: CGFloat(chan(hex, 0)) / 65535, alpha: 1)   // deviceRGB: what swiftterm reads back
    }
}
