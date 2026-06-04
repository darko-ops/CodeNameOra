import SwiftUI

/// Design tokens — Colors (Section 9.1).
extension Color {
    // Backgrounds
    static let oraBackground = Color(hex: "#080A0E")
    static let oraSurface = Color(hex: "#111318")
    static let oraSurfaceElevated = Color(hex: "#1A1F2E")

    // Zones (pace zones — change entire UI tint)
    static let zoneWarmUp = Color(hex: "#4FC3F7")    // blue
    static let zoneSteady = Color(hex: "#22D3EE")    // aqua blue (primary accent)
    static let zonePeak = Color(hex: "#FF7043")      // orange-red
    static let zoneRecovery = Color(hex: "#CE93D8")  // purple

    // Text
    static let oraTextPrimary = Color.white
    static let oraTextSecondary = Color(hex: "#999999")
    static let oraTextMuted = Color(hex: "#555555")

    // Semantic
    static let oraSuccess = Color(hex: "#4CAF50")
    static let oraWarning = Color(hex: "#FF9800")
    static let oraDestructive = Color(hex: "#F44336")
}
