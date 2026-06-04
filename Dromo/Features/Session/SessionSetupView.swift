import SwiftUI
import DromoCore

/// Step 2 — set a target pace directly, or enter a goal finish time for a
/// distance and let Dromo derive the pace. Sensitivity controls how hard the music
/// reacts when you drift off pace.
struct SessionSetupView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var vm = SessionSetupViewModel()
    @State private var showLiveHUD = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    if let note = coordinator.bpmNote {
                        bpmWarning(note)
                    }
                    modePicker
                    targetCard
                    sensitivityCard
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.vertical, Spacing.lg)
            }

            startBar
        }
        .fullScreenCover(isPresented: $showLiveHUD) {
            LiveHUDView(vm: LiveSessionViewModel(
                tracks: coordinator.library,
                targetPaceSecPerKm: vm.targetPaceSecondsPerKm,
                provider: coordinator.musicProvider))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Set your target")
                .font(.system(size: 22, weight: .bold))
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
                .foregroundColor(.oraTextSecondary)
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

            Divider().overlay(Color.oraTextMuted)

            HStack {
                Text("Target pace")
                    .font(.system(size: 13))
                    .foregroundColor(.oraTextSecondary)
                Spacer()
                Text(vm.targetPaceDisplay)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.zoneSteady)
                    .monospacedDigit()
            }
        }
        .padding(Spacing.md)
        .background(Color.oraSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .tag(n)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 64)
            Text(suffix)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.oraTextMuted)
        }
    }

    // MARK: - Sensitivity

    private var sensitivityCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("BPM SENSITIVITY")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.oraTextMuted)
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
        .padding(Spacing.md)
        .background(Color.oraSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Start

    private var startBar: some View {
        Button {
            showLiveHUD = true   // launch the live adaptive engine (LiveLoop)
        } label: {
            Text("Start run")
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(vm.isValid ? Color.zoneSteady : Color.oraSurfaceElevated)
                .foregroundColor(vm.isValid ? .black : .oraTextMuted)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!vm.isValid)
        .padding(.horizontal, Spacing.screen)
        .padding(.bottom, Spacing.lg)
    }
}
