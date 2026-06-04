import SwiftUI
import DromoCore

/// Generated cover art for a track. The real providers don't hand us album
/// artwork in `Track`, so we synthesize a stable gradient keyed to the track id
/// (same track ⇒ same colors) with the title's initial — the way music apps
/// fall back when artwork is missing.
struct TrackArtwork: View {
    let track: Track
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 10

    private var hue: Double {
        // Stable hash of the id → 0...1 hue.
        let sum = track.id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(sum % 360) / 360
    }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.55, brightness: 0.55),
                Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1),
                      saturation: 0.65, brightness: 0.32)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var initial: String {
        String(track.title.first.map(String.init)?.uppercased() ?? "♪")
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(gradient)
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}
