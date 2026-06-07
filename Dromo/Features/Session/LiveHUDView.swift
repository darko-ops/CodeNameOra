import SwiftUI
import DromoCore

/// The minimal hands-free HUD (Phase 5): current vs target pace, the nudge state,
/// and now-playing + its BPM. Updates live from `LoopState`; requires zero taps
/// during a run. The same `LoopState` feeds the lock-screen Live Activity + Watch.
struct LiveHUDView: View {
    @ObservedObject var vm: LiveSessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.oraBackground.ignoresSafeArea()
            VStack(spacing: Spacing.xl) {
                nudgeBadge
                paceBlock
                Spacer()
                nowPlaying
                feedbackControls
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, Spacing.xl)
        }
        .overlay { paceAlertOverlay }
        .animation(.easeInOut(duration: 0.4), value: vm.paceAlert)
        .overlay(alignment: .topTrailing) {
            Button("End") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.oraTextSecondary)
                .padding(Spacing.md)
        }
        .preferredColorScheme(.dark)
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    // MARK: Pace-deviation overlay

    /// A central radial glow + message that fades in while the runner is outside the
    /// ±20 s/km band — the visual companion to the beep. Distinct color per direction.
    @ViewBuilder
    private var paceAlertOverlay: some View {
        if let alert = vm.paceAlert {
            let tint: Color = alert == .tooSlow ? .zonePeak : .zoneWarmUp
            let title = alert == .tooSlow ? "TOO SLOW" : "TOO FAST"
            let subtitle = alert == .tooSlow ? "Pick up the pace" : "Ease off"

            ZStack {
                RadialGradient(
                    colors: [tint.opacity(0.45), tint.opacity(0.12), .clear],
                    center: .center, startRadius: 0, endRadius: 360)
                    .ignoresSafeArea()

                VStack(spacing: Spacing.sm) {
                    Image(systemName: alert == .tooSlow ? "hare.fill" : "tortoise.fill")
                        .font(.system(size: 40, weight: .bold))
                    Text(title)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.oraTextSecondary)
                }
                .foregroundColor(tint)
                .shadow(color: tint.opacity(0.5), radius: 16)
            }
            .allowsHitTesting(false)   // never blocks the End button / feedback controls
            .transition(.opacity)
        }
    }

    // MARK: Nudge

    private var nudgeColor: Color {
        switch vm.state.nudge {
        case .speedUp: return .zonePeak
        case .hold: return .zoneSteady
        case .slowDown: return .zoneWarmUp
        }
    }

    private var nudgeText: String {
        switch vm.state.nudge {
        case .speedUp: return "SPEED UP"
        case .hold: return "ON PACE"
        case .slowDown: return "EASE"
        }
    }

    private var nudgeBadge: some View {
        Text(nudgeText)
            .font(.system(size: 34, weight: .bold))
            .foregroundColor(nudgeColor)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity)
            .background(nudgeColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .animation(.easeInOut(duration: 0.3), value: vm.state.nudge)
    }

    // MARK: Pace

    private var paceBlock: some View {
        HStack(spacing: Spacing.xl) {
            paceStat("CURRENT", vm.state.currentPaceSecPerKm)
            paceStat("TARGET", vm.state.targetPaceSecPerKm)
        }
    }

    private func paceStat(_ label: String, _ secPerKm: Double) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.oraTextMuted)
            Text(PaceMath.paceString(secondsPerKm: secPerKm, metric: true))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.oraTextPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Now playing

    private var nowPlaying: some View {
        VStack(spacing: 6) {
            if let id = vm.state.nowPlayingTrackID {
                Text(vm.labelsByID[id] ?? id)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.oraTextPrimary)
                    .lineLimit(1)
                if let bpm = vm.state.nowPlayingBPM {
                    Text("\(Int(bpm)) BPM")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(nudgeColor)
                        .monospacedDigit()
                }
            } else {
                Text("Finding your tempo…")
                    .font(.system(size: 14))
                    .foregroundColor(.oraTextMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.md)
        .background(Color.oraSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Feedback controls

    /// Optional, secondary controls (the run is hands-free by default). Like/skip feed
    /// the private taste layer and re-weight selection live; "off-beat" flags the
    /// tempo to the Global Track Table.
    private var feedbackControls: some View {
        HStack(spacing: Spacing.xl) {
            controlButton("hand.thumbsup.fill", "Like", .zoneSteady) { vm.like() }
            controlButton("metronome", "Off-beat", .oraWarning) { vm.flagOffTempo() }
            controlButton("forward.end.fill", "Skip", .oraTextSecondary) { vm.skip() }
        }
        .disabled(vm.state.nowPlayingTrackID == nil)
        .opacity(vm.state.nowPlayingTrackID == nil ? 0.4 : 1)
    }

    private func controlButton(_ icon: String, _ label: String, _ tint: Color,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(label)
    }
}
