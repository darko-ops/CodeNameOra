import SwiftUI
import DromoCore

/// Step 2 — set a target pace directly, or enter a goal finish time for a
/// distance and let Dromo derive the pace. Sensitivity controls how hard the music
/// reacts when you drift off pace.
struct SessionSetupView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var vm = SessionSetupViewModel()
    @State private var showLiveHUD = false
    /// The playlist a run was started from, when it came in from the Sound tab. Its
    /// tracks become the session's pool, so "run at Threshold" runs on Threshold's music.
    @State private var runSource: AppCoordinator.RunRequest?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    if let note = coordinator.bpmNote {
                        bpmWarning(note)
                    }
                    if let runSource { sourceBanner(runSource) }
                    modePicker
                    targetCard
                    if vm.mode == .pace { distanceGoalCard }
                    sensitivityCard
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.vertical, Spacing.lg)
            }

            startBar
        }
        // Consume the request and clear it, so it applies once instead of re-arming
        // every time the tab is revisited. Handled on both appear and change: the tab
        // may already be on screen when the request arrives, or not yet built.
        .onAppear { consumeRunRequest() }
        .onChange(of: coordinator.runRequest) { _ in consumeRunRequest() }
        .fullScreenCover(isPresented: $showLiveHUD) {
            LiveHUDView(vm: LiveSessionViewModel(
                tracks: runSource?.tracks ?? coordinator.library,
                targetPaceSecPerKm: vm.targetPaceSecondsPerKm,
                targetDistanceMeters: vm.targetDistanceMeters,
                provider: coordinator.musicProvider,
                aliases: coordinator.recordingAliases))
        }
    }

    private func consumeRunRequest() {
        guard let request = coordinator.runRequest else { return }
        vm.apply(targetPaceSecondsPerKm: request.targetPaceSecPerKm)
        runSource = request
        coordinator.runRequest = nil
    }

    /// Says where the prefilled pace and music came from, and offers a way out — a
    /// silently narrowed track pool would be indistinguishable from a bug.
    private func sourceBanner(_ request: AppCoordinator.RunRequest) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "waveform")
                .foregroundColor(.zoneSteady)
            VStack(alignment: .leading, spacing: 2) {
                Text("Running \(request.sourceName)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.oraTextPrimary)
                Text("\(request.tracks.count) tracks · pace set to match")
                    .font(.system(size: 12))
                    .foregroundColor(.oraTextSecondary)
            }
            Spacer(minLength: 0)
            Button("Use all music") { runSource = nil }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.zoneSteady)
        }
        .oraRuledCard(radius: 12)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Set your target")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.oraTextPrimary)
            Spacer()
            Picker("Unit", selection: $vm.useMetric) {
                Text("km").tag(true)
                Text("mi").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 96)
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }

    private func bpmWarning(_ note: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.oraWarning)
            Text(note)
                .font(.system(size: 12))
                .foregroundColor(.oraWarning)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.oraWarning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var modePicker: some View {
        Picker("Mode", selection: $vm.mode) {
            ForEach(SessionSetupViewModel.Mode.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Target card

    private var targetCard: some View {
        VStack(spacing: Spacing.md) {
            if vm.mode == .pace {
                paceWheels
            } else {
                goalTimeInputs
            }

            Divider().overlay(Color.oraBorder)

            HStack {
                Text("Target pace")
                    .font(.system(size: 13))
                    .foregroundColor(.oraTextSecondary)
                Spacer()
                Text(vm.targetPaceDisplay)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.zoneSteady)
                    .monospacedDigit()
            }
        }
        .oraCard()
    }

    private var paceWheels: some View {
        HStack(spacing: 0) {
            wheel(value: $vm.paceMinutes, range: 2...15, suffix: "min")
            Text(":").font(.system(size: 28, weight: .bold)).foregroundColor(.oraTextMuted)
            wheel(value: $vm.paceSeconds, range: 0...59, suffix: "sec", zeroPadded: true)
            Text(vm.useMetric ? "/km" : "/mi")
                .font(.system(size: 14))
                .foregroundColor(.oraTextMuted)
                .padding(.leading, Spacing.sm)
        }
        .frame(height: 120)
    }

    private var goalTimeInputs: some View {
        VStack(spacing: Spacing.md) {
            Picker("Distance", selection: $vm.distance) {
                ForEach(RaceDistance.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 0) {
                wheel(value: $vm.goalHours, range: 0...6, suffix: "hr")
                Text(":").font(.system(size: 24, weight: .bold)).foregroundColor(.oraTextMuted)
                wheel(value: $vm.goalMinutes, range: 0...59, suffix: "min", zeroPadded: true)
                Text(":").font(.system(size: 24, weight: .bold)).foregroundColor(.oraTextMuted)
                wheel(value: $vm.goalSeconds, range: 0...59, suffix: "sec", zeroPadded: true)
            }
            .frame(height: 120)
        }
    }

    private func wheel(value: Binding<Int>, range: ClosedRange<Int>,
                       suffix: String, zeroPadded: Bool = false) -> some View {
        VStack(spacing: 2) {
            Picker(suffix, selection: value) {
                ForEach(Array(range), id: \.self) { n in
                    Text(zeroPadded ? String(format: "%02d", n) : "\(n)")
                        .font(.system(size: 22, weight: .semibold))
                        .tag(n)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 64)
            OraLabel(suffix)
        }
    }

    // MARK: - Distance goal (pace mode)

    private var distanceGoalCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            OraLabel("Distance goal (optional)")
            HStack {
                Text(vm.distanceGoalKm > 0
                     ? String(format: "%.1f km", vm.distanceGoalKm)
                     : "Off")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(vm.distanceGoalKm > 0 ? .zoneSteady : .oraTextMuted)
                    .monospacedDigit()
                Spacer()
                Stepper("", value: $vm.distanceGoalKm, in: 0...50, step: 0.5)
                    .labelsHidden()
            }
            Text(vm.distanceGoalKm > 0
                 ? "The final 10% gets a finishing-line push, even if you're tiring."
                 : "Set a goal to get a finishing-line kick in the last stretch.")
                .font(.system(size: 12))
                .foregroundColor(.oraTextSecondary)
        }
        .oraRuledCard()
    }

    // MARK: - Sensitivity

    private var sensitivityCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            OraLabel("BPM sensitivity")
            Picker("Sensitivity", selection: $vm.sensitivity) {
                Text("Easy").tag(UserSettings.BPMSensitivity.conservative)
                Text("Standard").tag(UserSettings.BPMSensitivity.standard)
                Text("Aggressive").tag(UserSettings.BPMSensitivity.aggressive)
            }
            .pickerStyle(.segmented)
            Text(vm.sensitivityDescription)
                .font(.system(size: 12))
                .foregroundColor(.oraTextSecondary)
        }
        .oraRuledCard()
    }

    // MARK: - Start

    private var startBar: some View {
        Button {
            showLiveHUD = true   // launch the live adaptive engine (LiveLoop)
        } label: {
            Text("Start run")
        }
        .buttonStyle(.lightPrimary)
        .disabled(!vm.isValid)
        .padding(.horizontal, Spacing.screen)
        .padding(.bottom, Spacing.lg)
    }
}
