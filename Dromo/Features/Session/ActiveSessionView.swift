import SwiftUI
import DromoCore

/// Step 3 — the live run. The whole screen tints to the coaching status (push /
/// on-pace / ease) so you read it at a glance, and the now-playing card shows the
/// track Dromo picked for the current BPM target.
struct ActiveSessionView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject var session: SessionController

    var body: some View {
        ZStack {
            Color.oraBackground.ignoresSafeArea()

            switch session.phase {
            case .countdown(let n):
                CountdownView(value: n)
            default:
                hud
            }
        }
    }

    // MARK: - HUD

    private var hud: some View {
        let status = session.status
        return VStack(spacing: Spacing.lg) {
            statusBanner(status)

            paceBlock(status)

            nowPlaying

            Spacer()

            if session.usesSimulatedPace {
                simulatorControl
            }

            controls
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.vertical, Spacing.lg)
    }

    private func statusBanner(_ status: RunFeedback.Status) -> some View {
        VStack(spacing: 4) {
            Text(status.label)
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundColor(status.color)
            Text(RunFeedback.gapDescription(session.gap))
                .font(.system(size: 13))
                .foregroundColor(.oraTextSecondary)
        }
        .padding(.top, Spacing.md)
        .animation(.easeInOut(duration: 0.3), value: status)
    }

    private func paceBlock(_ status: RunFeedback.Status) -> some View {
        HStack {
            metric(title: "PACE",
                   value: PaceMath.paceString(secondsPerKm: session.currentPaceSecondsPerKm,
                                              metric: session.settings.useMetric),
                   color: status.color)
            Spacer()
            metric(title: "TARGET",
                   value: PaceMath.paceString(secondsPerKm: session.targetPaceSecondsPerKm,
                                              metric: session.settings.useMetric),
                   color: .oraTextPrimary)
            Spacer()
            metric(title: "TIME", value: PaceMath.clock(session.elapsedSeconds),
                   color: .oraTextPrimary)
        }
    }

    private func metric(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.oraTextMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var nowPlaying: some View {
        VStack(spacing: Spacing.sm) {
            BPMBarView(targetBPM: session.targetBPM,
                       range: session.settings.minBPM...session.settings.maxBPM,
                       color: session.status.color)

            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.oraSurfaceElevated)
                    Image(systemName: "music.note")
                        .foregroundColor(.oraTextSecondary)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.currentTrack?.title ?? "Finding your track…")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.oraTextPrimary)
                        .lineLimit(1)
                    Text(session.currentTrack?.artist ?? "—")
                        .font(.system(size: 13))
                        .foregroundColor(.oraTextSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if let bpm = session.currentTrack?.bpm {
                    VStack(spacing: 0) {
                        Text("\(Int(bpm))")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(session.status.color)
                        Text("BPM").font(.system(size: 9)).foregroundColor(.oraTextMuted)
                    }
                }
            }
            .padding(Spacing.md)
            .background(Color.oraSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .animation(.easeInOut(duration: 0.4), value: session.currentTrack?.id)
        }
    }

    // MARK: - Simulator control (replaced by CoreLocation on device)

    private var simulatorControl: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Label("SIMULATED PACE", systemImage: "hammer.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.oraTextMuted)
                Spacer()
                Text(PaceMath.paceString(secondsPerKm: session.simulatedPaceSecondsPerKm,
                                         metric: session.settings.useMetric))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.oraTextSecondary)
                    .monospacedDigit()
            }
            HStack(spacing: Spacing.md) {
                nudge("Run faster", system: "hare.fill") {
                    session.simulatedPaceSecondsPerKm = max(150, session.simulatedPaceSecondsPerKm - 8)
                }
                nudge("Run slower", system: "tortoise.fill") {
                    session.simulatedPaceSecondsPerKm = min(720, session.simulatedPaceSecondsPerKm + 8)
                }
            }
            // Lower sec/km = faster, so invert the slider for an intuitive drag.
            Slider(value: Binding(
                get: { -session.simulatedPaceSecondsPerKm },
                set: { session.simulatedPaceSecondsPerKm = -$0 }
            ), in: -720 ... -150)
            .tint(session.status.color)
        }
        .padding(Spacing.md)
        .background(Color.oraSurface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func nudge(_ title: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: system)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.oraSurfaceElevated)
                .foregroundColor(.oraTextPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Pause / End

    private var controls: some View {
        HStack(spacing: Spacing.md) {
            Button { session.togglePause() } label: {
                Label(session.phase == .paused ? "Resume" : "Pause",
                      systemImage: session.phase == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.oraSurfaceElevated)
                    .foregroundColor(.oraTextPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Button { coordinator.finishSession() } label: {
                Text("End")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.oraDestructive.opacity(0.2))
                    .foregroundColor(.oraDestructive)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Countdown

private struct CountdownView: View {
    let value: Int
    var body: some View {
        VStack(spacing: Spacing.md) {
            Text("Get ready")
                .font(.system(size: 16))
                .foregroundColor(.oraTextSecondary)
            Text("\(value)")
                .font(.system(size: 120, weight: .black, design: .rounded))
                .foregroundColor(.oraTextPrimary)
                .id(value)
                .transition(.scale.combined(with: .opacity))
                .animation(.easeOut(duration: 0.3), value: value)
        }
    }
}
