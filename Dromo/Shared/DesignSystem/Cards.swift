import SwiftUI

/// Card surfaces, from dromo.fit: an `oraSurface` fill with a hairline border, and a
/// variant carrying a 2px leading accent rule (the site's mobile step pattern).
///
/// The plain card is the default; the ruled one is for secondary and settings cards, so
/// the rule stays meaningful instead of decorating everything.
extension View {
    /// `oraSurface` + hairline border.
    func oraCard(radius: CGFloat = 16, padding: CGFloat? = Spacing.md) -> some View {
        modifier(OraCard(radius: radius, padding: padding, ruled: false))
    }

    /// `oraSurface` + hairline border + a 2px `oraBorderStrong` leading edge.
    func oraRuledCard(radius: CGFloat = 16, padding: CGFloat? = Spacing.md) -> some View {
        modifier(OraCard(radius: radius, padding: padding, ruled: true))
    }
}

private struct OraCard: ViewModifier {
    let radius: CGFloat
    let padding: CGFloat?
    let ruled: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.oraSurface)
            .overlay(alignment: .leading) {
                if ruled {
                    // Inside the clip, so the rule takes the card's own corner radius
                    // rather than sitting proud of it.
                    Rectangle().fill(Color.oraBorderStrong).frame(width: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.oraBorder, lineWidth: 1)
            }
    }
}

/// An uppercase eyebrow label — 10pt semibold, +0.16em, muted.
struct OraLabel: View {
    let text: String
    var color: Color = .oraTextMuted

    init(_ text: String, color: Color = .oraTextMuted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(Tracking.label)
            .foregroundColor(color)
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            OraLabel("Target pace")
            Text("5:20 /km").font(.system(size: 22, weight: .bold)).monospacedDigit()
                .foregroundColor(.zoneSteady)
        }
        .oraCard()

        VStack(alignment: .leading, spacing: Spacing.xs) {
            OraLabel("Distance goal")
            Text("10.0 km").font(.system(size: 20, weight: .bold)).monospacedDigit()
                .foregroundColor(.zoneSteady)
        }
        .oraRuledCard()
    }
    .padding()
    .background(Color.oraBackground)
}
