import SwiftUI

/// The wave mark, and the mark + `DROMO` lockup — carried over from dromo.fit.
///
/// The artwork is solid black on transparent, so it ships as a template image and takes
/// its colour from `foregroundColor` rather than baking one in. There is no Ø: the
/// earlier DRØMO slash lockup is retired.
struct WaveMark: View {
    /// Height of the mark. The artwork is 1.72:1, so width follows from it.
    var height: CGFloat

    var body: some View {
        Image("WaveMark")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: height * WaveMark.aspect, height: height)
            .accessibilityHidden(true)
    }

    /// The artwork's own proportions (360×209).
    static let aspect: CGFloat = 1.72
}

/// Mark + wordmark, sized off one type size the way the site sizes it: the mark stands
/// `1em` tall against the text, with a `0.5em` gap.
struct DromoWordmark: View {
    /// Size of the `DROMO` text. The mark scales with it.
    var size: CGFloat = 16
    var weight: Font.Weight = .semibold
    var color: Color = .oraTextPrimary

    var body: some View {
        HStack(spacing: size * 0.5) {
            WaveMark(height: size)
            Text("DROMO")
                .font(.system(size: size, weight: weight))
                .tracking(size * 0.04)
        }
        .foregroundColor(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dromo")
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        DromoWordmark()
        DromoWordmark(size: 14, color: .oraTextSecondary)
        DromoWordmark(size: 24, weight: .bold)
    }
    .padding()
    .background(Color.oraBackground)
}
