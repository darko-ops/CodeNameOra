import SwiftUI
import DromoCore

/// The hands-free live HUD (design ref 6a on-pace / 6b too-slow). The whole screen
/// tints to the coaching status so you read it at a glance: nudge badge, current vs
/// target pace + time, cadence, the ramped target-BPM bar, now-playing + its BPM, and
/// optional feedback. Updates live from `LoopState`; requires zero taps during a run.
/// The same `LoopState` feeds the lock-screen Live Activity + Watch.
struct LiveHUDView: View {
    @ObservedObject var vm: LiveSessionViewModel
    @Environment(\.dismiss) private var dismiss
    /// "Why this track?" — off by default. A run is hands-free; the explanation is
    /// there for the moment someone wonders, not a permanent readout.
    @State private var showingReason = false
    /// Post-run "What moved you", presented when the runner ends the session.
    @State private var showingSummary = false

    var body: some View {
        ZStack {
            Color.oraBackground.ignoresSafeArea()
            statusGlow

            VStack(spacing: Spacing.lg) {
                topBar
                nudgeBadge
                nudgeSubtitle
                paceBlock
                cadence
                bpmBar
                nowPlaying
                Spacer(minLength: Spacing.md)
                feedbackControls
                controls
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, Spacing.lg)
        }
        .overlay { paceAlertOverlay }
        .animation(.easeInOut(duration: 0.4), value: vm.paceAlert)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSummary) {
            if let session = vm.finishedSession {
                PostRunSummaryView(summary: RunSummary(session: session),
                                   responses: vm.runResponses,
                                   trackLabels: vm.labelsByID,
                                   useMetric: true) {
                    showingSummary = false
                    dismiss()
                }
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    // MARK: Whole-screen status tint (6a)

    /// A soft radial glow near the top, tinted to the coaching status — the ambient
    /// counterpart to the badge. The centered pace-alert overlay (6b) intensifies it.
    private var statusGlow: some View {
        RadialGradient(colors: [nudgeColor.opacity(0.14), .clear],
                       center: UnitPoint(x: 0.5, y: 0.12),
                       startRadius: 0, endRadius: 440)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: vm.state.nudge)
    }

    // MARK: Top bar — wordmark + End

    /// The lockup replaces a bare elapsed label: time already reads in the pace block,
    /// so this row carries identity instead of repeating a number.
    private var topBar: some View {
        HStack {
            DromoWordmark(size: 14, color: .oraTextSecondary)
            Spacer()
            Button("End") {
                // Stop first so the final track's response is finalized and counted in
                // the summary; without this the last (often longest) play is missing.
                vm.stop()
                // Shown whenever there is a run to describe, rather than only when a
                // track earned a mention: distance, pace and the chart are worth seeing
                // even on a run that taught Dromo nothing.
                if vm.hasSummary { showingSummary = true } else { dismiss() }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.oraTextSecondary)
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
            .font(.system(size: 30, weight: .bold))
            .tracking(Tracking.badge)
            .foregroundColor(nudgeColor)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity)
            .background(nudgeColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .animation(.easeInOut(duration: 0.3), value: vm.state.nudge)
    }

    /// Gap description under the badge ("You're right on target" / "15 s/km behind…").
    private var nudgeSubtitle: some View {
        let gap = Int(abs(vm.state.currentPaceSecPerKm - vm.state.targetPaceSecPerKm).rounded())
        let text: String
        switch vm.state.nudge {
        case .hold:     text = "You're right on target — hold it here"
        case .speedUp:  text = "\(gap) s/km behind — pick up the pace"
        case .slowDown: text = "\(gap) s/km ahead — ease off"
        }
        return Text(text)
            .font(.system(size: 13))
            .foregroundColor(.oraTextSecondary)
            .multilineTextAlignment(.center)
    }

    // MARK: Pace block — PACE / TARGET / TIME

    private var paceBlock: some View {
        HStack(spacing: 0) {
            metric("PACE /KM",
                   PaceMath.paceString(secondsPerKm: vm.state.currentPaceSecPerKm, metric: true),
                   nudgeColor)
            divider
            metric("TARGET",
                   PaceMath.paceString(secondsPerKm: vm.state.targetPaceSecPerKm, metric: true),
                   .oraTextPrimary)
            divider
            metric("TIME", PaceMath.clock(vm.elapsedSeconds), .oraTextPrimary)
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.oraBorder).frame(width: 1, height: 34)
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 29, weight: .bold))
                .tracking(Tracking.numeric)
                .foregroundColor(color)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            OraLabel(title)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Cadence

    private var cadence: some View {
        VStack(spacing: 2) {
            OraLabel("Cadence")
            (Text("\(Int(vm.state.currentCadence)) ")
                .font(.system(size: 17, weight: .semibold))
             + Text("spm")
                .font(.system(size: 12)))
                .foregroundColor(.oraTextPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Target-BPM bar

    /// The ramped target BPM within the runner's working range. Rises as Dromo pushes
    /// (behind pace → a faster track) and eases down when ahead.
    private var bpmBar: some View {
        let center = max(vm.state.targetCadence, 1)
        let target = vm.state.nowPlayingBPM ?? center
        // Nil until there's a real reading: a tick pinned to the low end of the range
        // would read as "your cadence is 148", not "we don't know it yet".
        let liveCadence = vm.state.currentCadence > 0 ? vm.state.currentCadence : nil
        return BPMBarView(targetBPM: target,
                          range: (center - 20)...(center + 20),
                          color: nudgeColor,
                          cadence: liveCadence,
                          isPushing: vm.state.nudge == .speedUp)
    }

    // MARK: Now playing

    private var nowPlaying: some View {
        let track = vm.state.nowPlayingTrackID.flatMap { vm.tracksByID[$0] }
        return HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.oraSurfaceElevated)
                Image(systemName: "music.note").foregroundColor(.oraTextSecondary)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(track?.title ?? "Finding your tempo…")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.oraTextPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(track?.artist ?? "—")
                        .font(.system(size: 13))
                        .foregroundColor(.oraTextSecondary)
                        .lineLimit(1)
                    provenanceBadge
                }
            }
            Spacer(minLength: 0)
            if let bpm = vm.state.nowPlayingBPM {
                VStack(spacing: 0) {
                    Text("\(Int(bpm))")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(nudgeColor)
                        .monospacedDigit()
                    Text("BPM")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(Tracking.labelTight)
                        .foregroundColor(.oraTextMuted)
                }
            }
        }
        .oraCard()
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { showingReason.toggle() } }
        .overlay(alignment: .bottom) { reasonPopover }
        .animation(.easeInOut(duration: 0.4), value: vm.state.nowPlayingTrackID)
    }

    /// The engine's ACTUAL reason for this pick, not a plausible story assembled after
    /// the fact — `LiveLoop` reports what the decision was made on.
    @ViewBuilder
    private var reasonPopover: some View {
        if showingReason, let reason = vm.nowPlayingReason {
            VStack(alignment: .leading, spacing: 4) {
                Text(reason.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(nudgeColor)
                Text(reason.detail)
                    .font(.system(size: 11))
                    .foregroundColor(.oraTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.oraSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .offset(y: 64)
            .transition(.opacity)
        }
    }

    /// Where this track came from. Deliberately quiet — it's reassurance ("that was
    /// yours") and a visible measure of the library taking over as coverage grows,
    /// not a label the runner has to read mid-stride. Hidden until something plays.
    @ViewBuilder
    private var provenanceBadge: some View {
        if vm.state.nowPlayingTrackID != nil {
            let fromLibrary = vm.nowPlayingOrigin == .library
            Text(fromLibrary ? "YOUR LIBRARY" : "DROMO MIX")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(fromLibrary ? .zoneSteady : .oraTextMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((fromLibrary ? Color.zoneSteady : Color.oraTextMuted).opacity(0.12))
                .clipShape(Capsule())
        }
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

    // MARK: Pause / End

    private var controls: some View {
        HStack(spacing: Spacing.md) {
            // Pause is the primary mid-run control, so it takes the light button; End
            // stays quieter, since it's the one that costs the run.
            Button { vm.togglePause() } label: {
                Label(vm.isPaused ? "Resume" : "Pause",
                      systemImage: vm.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.lightPrimary(radius: 12, verticalPadding: 14))

            Button { dismiss() } label: {
                Text("End")
            }
            .buttonStyle(.oraDestructiveNeutral)
        }
    }

    // MARK: Pace-deviation overlay (6b)

    /// A central radial glow + message that fades in while the runner is outside the
    /// ±15 s/km band — the visual companion to the chime. Distinct color per direction.
    /// Like the chime, it stays away until the runner has first reached the band.
    @ViewBuilder
    private var paceAlertOverlay: some View {
        if let alert = vm.paceAlert {
            let tint: Color = alert == .tooSlow ? .zonePeak : .zoneWarmUp
            let title = alert == .tooSlow ? "TOO SLOW" : "TOO FAST"
            let subtitle = alert == .tooSlow ? "Pick up the pace" : "Ease off"

            ZStack {
                RadialGradient(
                    colors: [tint.opacity(0.32), tint.opacity(0.1), .clear],
                    center: .center, startRadius: 0, endRadius: 360)
                    .ignoresSafeArea()

                VStack(spacing: Spacing.sm) {
                    Image(systemName: alert == .tooSlow ? "hare.fill" : "tortoise.fill")
                        .font(.system(size: 40, weight: .bold))
                    Text(title)
                        .font(.system(size: 37, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 17, weight: .semibold))
                        // A light tint of the zone colour, not neutral secondary: the
                        // subtitle belongs to the alert, and reads as part of it.
                        .foregroundColor(tint.opacity(0.75))
                }
                .foregroundColor(tint)
                .shadow(color: tint.opacity(0.5), radius: 16)
            }
            .allowsHitTesting(false)   // never blocks the End button / feedback controls
            .transition(.opacity)
        }
    }
}
