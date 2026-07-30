import SwiftUI

/// Design tokens — Colors.
///
/// Design language v2, aligned to dromo.fit: near-black neutral surfaces and a single
/// steel accent. The old palette was blue-tinted in its greys and neon in its zones.
extension Color {
    // MARK: - Surfaces

    static let oraBackground = Color(hex: "#0E1013")        // the site's --bg
    static let oraSurface = Color(hex: "#16181C")           // cards, list rows, nav bars
    static let oraSurfaceElevated = Color(hex: "#1F2227")   // neutral, where this was blue-tinted

    /// Hairline card/row border. The site outlines its surfaces; the app used bare fills.
    static let oraBorder = Color.white.opacity(0.07)
    /// The 2px leading accent rule on secondary/settings cards.
    static let oraBorderStrong = Color.white.opacity(0.16)

    // MARK: - Coaching colour
    //
    // The one place the app keeps hue: the HUD tints the whole screen to the coaching
    // state, so hue is doing real work at a glance mid-run. Each state is a hue rotation
    // of the site's steel accent at matched lightness and chroma — as restrained as the
    // site, still instantly distinguishable.

    static let zoneWarmUp = Color(hex: "#8FA9C4")    // warm-up · "EASE" / too-fast
    static let zoneSteady = Color(hex: "#6EA8C9")    // steady · "ON PACE" · the site's accent
    static let zonePeak = Color(hex: "#C98A6E")      // peak · "SPEED UP" / too-slow
    static let zoneRecovery = Color(hex: "#A78FC4")  // recovery

    // MARK: - Text

    static let oraTextPrimary = Color(hex: "#E7E9EC")   // softened off-white, not pure white
    static let oraTextSecondary = Color(hex: "#9298A1")
    static let oraTextMuted = Color(hex: "#5B616A")

    // MARK: - Semantic
    //
    // Muted to the zones' chroma — no saturated red/green/orange anywhere.

    static let oraSuccess = Color(hex: "#7FB09A")
    static let oraWarning = Color(hex: "#C9A96E")
    static let oraDestructive = Color(hex: "#C96E6E")

    // MARK: - Light primary button
    //
    // Primary CTAs are light-on-dark as on the site, not accent-filled.

    static let oraButtonFill = Color(hex: "#E7E9EC")
    static let oraButtonText = Color(hex: "#16181C")
}
