import SwiftUI

/// Design tokens — Typography.
///
/// Design language v2. The site sets `"Helvetica Neue", Helvetica, Arial, sans-serif`;
/// on iOS the honest equivalent is the system font (SF Pro) at `.default` design.
///
/// This replaces declarations for Syne and DM Mono. Those font files were never
/// embedded, so they already resolved to the system font — naming them recorded an
/// intent the app never actually had. `.rounded` is deliberately absent: that softness
/// is what made the app read as a different product from the site.
extension Font {
    /// Large numeric display — pace, cadence, BPM. Pair with `.monospacedDigit()`.
    static let oraDisplay = Font.system(size: 30, weight: .bold)
    /// Screen titles.
    static let oraTitle = Font.system(size: 22, weight: .semibold)
    /// Card headings.
    static let oraHeadline = Font.system(size: 16, weight: .semibold)
    /// Body copy — use with `oraTextSecondary`.
    static let oraBody = Font.system(size: 15, weight: .regular)
    static let oraCaption = Font.system(size: 13, weight: .regular)
    /// Eyebrow label. Pair with `.textCase(.uppercase)` and `.tracking(Tracking.label)`.
    static let oraLabel = Font.system(size: 10, weight: .semibold)
}

/// Letter-spacing from the site, resolved to points.
///
/// SwiftUI's `.tracking` takes points rather than em, so each value below is the spec's
/// em figure multiplied by the size it is used at: labels +0.16em at 10pt, the wordmark
/// +0.04em at 16pt, numeric display −0.03em at 29pt, the nudge badge +0.02em at 30pt.
enum Tracking {
    /// Uppercase eyebrow labels (+0.16em at 10pt).
    static let label: CGFloat = 1.6
    /// Smaller inline caps such as the `BPM` sublabel (+0.14em at 9pt).
    static let labelTight: CGFloat = 1.26
    /// The `DROMO` wordmark (+0.04em at 16pt).
    static let wordmark: CGFloat = 0.64
    /// Numeric display (−0.03em at 29pt).
    static let numeric: CGFloat = -0.87
    /// The nudge badge (+0.02em at 30pt).
    static let badge: CGFloat = 0.6
}
