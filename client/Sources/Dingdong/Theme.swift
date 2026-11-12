import AppKit
import SwiftUI

enum Theme {
    static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }

    // 奶油底 + 糖果色
    static let bg = dynamic(hex(0xFFF7F0), hex(0x231C2B))
    static let card = dynamic(hex(0xFFFFFF), hex(0x2F2639))
    static let ink = dynamic(hex(0x3B2F45), hex(0xF6EEFA))
    static let soft = dynamic(hex(0x8C7F96), hex(0xB4A8BE))
    static let hairline = dynamic(hex(0xF0E4EC), hex(0x3E3349))

    static let pink = Color(nsColor: hex(0xFF7EB6))
    static let peach = Color(nsColor: hex(0xFFB066))
    static let mint = Color(nsColor: hex(0x4FD1A1))
    static let lavender = Color(nsColor: hex(0x9B8CFF))
    static let sky = Color(nsColor: hex(0x6EC3FF))
    static let rose = Color(nsColor: hex(0xFF6B8B))
    static let lemon = Color(nsColor: hex(0xFFD45C))

    static func level(_ l: String) -> Color {
        switch l {
        case "success": mint
        case "warning": peach
        case "error": rose
        default: lavender
        }
    }

    /// 同一个来源永远同一个颜色
    static func source(_ s: String) -> Color {
        let palette = [0xFF5FA2, 0x3BA9F5, 0x2FBF8A, 0x8A78FF, 0xFF9A3D, 0xE0A100]
            .map { Color(nsColor: hex(UInt32($0))) }
        var h: UInt32 = 2166136261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return palette[Int(h % UInt32(palette.count))]
    }

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
