import SwiftUI

extension Color {
    /// Creates a color from a hex string, e.g. "#1A1F2E" or "1A1F2E".
    /// Supports RGB (6) and ARGB (8) hex digits.
    init(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)

        let a, r, g, b: UInt64
        switch raw.count {
        case 8: // ARGB
            (a, r, g, b) = (value >> 24 & 0xFF, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default: // RGB (6) — opaque
            (a, r, g, b) = (255, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
