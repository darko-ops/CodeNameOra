import SwiftUI

/// Design tokens — Typography (Section 9.2).
///
/// Primary display font: Syne (bold numerics, wide tracking).
/// Secondary / mono: DM Mono (data readouts, labels).
///
/// NOTE (Phase 0): the custom font files are not yet embedded. These custom
/// fonts fall back to the system font until the .ttf files are added to
/// Resources/Fonts and registered via UIAppFonts in Info.plist.
extension Font {
    static let oraDisplay = Font.custom("Syne-ExtraBold", size: 52)
    static let oraTitle = Font.custom("Syne-Bold", size: 28)
    static let oraHeadline = Font.custom("Syne-SemiBold", size: 20)
    static let oraBody = Font.custom("DMSans-Regular", size: 16)
    static let oraCaption = Font.custom("DMMono-Regular", size: 11)
    static let oraLabel = Font.custom("DMMono-Medium", size: 10)
}
