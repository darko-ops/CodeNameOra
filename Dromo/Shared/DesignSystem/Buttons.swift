import SwiftUI

/// The light primary button, carried over from dromo.fit: `#E7E9EC` fill with `#16181C`
/// text, replacing the app's accent-filled CTAs.
///
/// Disabled state is the spec's own — `oraSurfaceElevated` fill with `oraTextMuted` text
/// — rather than a dimmed fill, so a blocked CTA reads as inert instead of merely faded.
/// Drive it with `.disabled(_:)`; the style reads the environment, so callers don't pass
/// the flag twice.
struct LightPrimaryButtonStyle: ButtonStyle {
    var radius: CGFloat = 14
    var verticalPadding: CGFloat = 16
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            .background(isEnabled ? Color.oraButtonFill : Color.oraSurfaceElevated)
            .foregroundColor(isEnabled ? Color.oraButtonText : Color.oraTextMuted)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// A destructive button — `oraDestructive` text over a neutral or self-tinted fill.
///
/// Two fills, because the spec asks for two: the HUD's End sits on
/// `oraSurfaceElevated` (§2.8) so it reads as the quieter half of a button pair, while
/// standalone destructive actions like Reset learned data (§3.5) take the 20%-alpha
/// destructive wash.
struct DestructiveButtonStyle: ButtonStyle {
    enum Fill { case neutral, tinted }

    var radius: CGFloat = 12
    var fill: Fill = .tinted
    var verticalPadding: CGFloat = 14

    private var background: Color {
        switch fill {
        case .neutral: return .oraSurfaceElevated
        case .tinted: return Color.oraDestructive.opacity(0.2)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            .background(background)
            .foregroundColor(.oraDestructive)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// A neutral secondary button on `oraSurfaceElevated`.
struct SecondaryButtonStyle: ButtonStyle {
    var radius: CGFloat = 12
    var verticalPadding: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            .background(Color.oraSurfaceElevated)
            .foregroundColor(.oraTextPrimary)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension ButtonStyle where Self == LightPrimaryButtonStyle {
    static var lightPrimary: LightPrimaryButtonStyle { .init() }
    static func lightPrimary(radius: CGFloat, verticalPadding: CGFloat = 16)
        -> LightPrimaryButtonStyle {
        .init(radius: radius, verticalPadding: verticalPadding)
    }
}

extension ButtonStyle where Self == DestructiveButtonStyle {
    /// The 20%-alpha destructive wash — standalone destructive actions.
    static var oraDestructive: DestructiveButtonStyle { .init(fill: .tinted) }
    /// Destructive text on a neutral fill — the quieter half of a button pair.
    static var oraDestructiveNeutral: DestructiveButtonStyle { .init(fill: .neutral) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var oraSecondary: SecondaryButtonStyle { .init() }
}

#Preview {
    VStack(spacing: Spacing.md) {
        Button("Start run") {}.buttonStyle(.lightPrimary)
        Button("Start run") {}.buttonStyle(.lightPrimary).disabled(true)
        Button("Pause") {}.buttonStyle(.oraSecondary)
        Button("End run") {}.buttonStyle(.oraDestructive)
    }
    .padding()
    .background(Color.oraBackground)
}
