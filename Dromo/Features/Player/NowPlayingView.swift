import SwiftUI
import DromoCore

/// Full-screen player: artwork, title/artist/BPM, a scrubber with elapsed/remaining
/// time, skip controls, and the song's details (energy, duration, provider, and the
/// run zone its tempo best suits) folded in below.
struct NowPlayingView: View {
    @EnvironmentObject private var np: NowPlayingController

    var body: some View {
        ZStack {
            Color.oraBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    if let track = np.current {
                        artworkView(track, size: 260, corner: 28)
                            .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                            .padding(.top, Spacing.sm)
                        titleBlock(track)
                        scrubber
                        controls
                        details(track)
                        upNextSection
                    } else {
                        Text("Nothing playing").foregroundColor(.oraTextMuted)
                    }
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.top, 52)   // clear the dismiss button
                .padding(.bottom, Spacing.xl)
            }
        }
        .overlay(alignment: .topLeading) {
            Button { np.isExpanded = false } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.oraTextSecondary)
                    .padding(8)                       // bigger tap target
                    .contentShape(Rectangle())
            }
            .padding(Spacing.md)
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
    }

    // MARK: - Header

    @ViewBuilder
    private func artworkView(_ track: Track, size: CGFloat, corner: CGFloat) -> some View {
        if let image = np.artwork {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        } else {
            TrackArtwork(track: track, size: size, cornerRadius: corner)
        }
    }

    private func titleBlock(_ track: Track) -> some View {
        VStack(spacing: 4) {
            Text(track.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.oraTextPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(track.artist)
                .font(.system(size: 16))
                .foregroundColor(.oraTextSecondary)
        }
        .padding(.top, Spacing.md)
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(value: Binding(get: { np.elapsed }, set: { np.seek(to: $0) }),
                   in: 0...max(1, np.duration))
                .tint(.zoneSteady)
            HStack {
                Text(PaceMath.clock(np.elapsed))
                Spacer()
                Text("-" + PaceMath.clock(max(0, np.duration - np.elapsed)))
            }
            .font(.system(size: 12, design: .rounded))
            .foregroundColor(.oraTextMuted)
            .monospacedDigit()
        }
        .padding(.top, Spacing.md)
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button { np.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(np.isShuffle ? .zoneSteady : .oraTextMuted)
            }
            Button { np.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 26))
            }
            Button { np.togglePlayPause() } label: {
                Image(systemName: np.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 62))
            }
            Button { np.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 26))
            }
            Button { np.cycleRepeat() } label: {
                Image(systemName: np.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(np.repeatMode == .off ? .oraTextMuted : .zoneSteady)
            }
        }
        .foregroundColor(.oraTextPrimary)
        .padding(.top, Spacing.sm)
    }

    // MARK: - Up Next (the rest of the queue)

    @ViewBuilder
    private var upNextSection: some View {
        let upcoming = Array(np.queue.enumerated()).filter { $0.offset > np.index }
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("UP NEXT")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.oraTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 0) {
                    ForEach(upcoming, id: \.element.id) { offset, track in
                        Button { np.jump(to: offset) } label: { upNextRow(track) }
                            .buttonStyle(.plain)
                        if offset != upcoming.last?.offset {
                            Divider().overlay(Color.oraSurfaceElevated)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(Color.oraSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.top, Spacing.lg)
        }
    }

    private func upNextRow(_ track: Track) -> some View {
        HStack(spacing: Spacing.md) {
            TrackArtwork(track: track, size: 40, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.oraTextPrimary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundColor(.oraTextSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if track.bpm > 0 {
                Text("\(Int(track.bpm))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.oraTextMuted)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Details (folded in from the old SongDetailView)

    private func details(_ track: Track) -> some View {
        let zone = PlaylistCatalog.zone(forBPM: track.bpm)
        let accent = zone.map { Color(hex: $0.accentHex) } ?? .zoneSteady
        return VStack(spacing: Spacing.md) {
            statsCard(track, accent: accent)
            if track.bpm > 0, let zone {
                zoneCard(track, zone: zone, accent: accent)
            }
        }
        .padding(.top, Spacing.lg)
    }

    private func statsCard(_ track: Track, accent: Color) -> some View {
        VStack(spacing: Spacing.md) {
            statRow("BPM", track.bpm > 0 ? "\(Int(track.bpm))" : "—", accent)
            Divider().overlay(Color.oraSurfaceElevated)
            energyRow(track, accent: accent)
            Divider().overlay(Color.oraSurfaceElevated)
            statRow("Duration", PaceMath.clock(Double(track.durationSeconds)), .oraTextPrimary)
            Divider().overlay(Color.oraSurfaceElevated)
            statRow("Source", track.provider == .spotify ? "Spotify" : "Apple Music", .oraTextSecondary)
        }
        .padding(Spacing.md)
        .background(Color.oraSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundColor(.oraTextSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(color)
                .monospacedDigit()
        }
    }

    private func energyRow(_ track: Track, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Energy").font(.system(size: 14)).foregroundColor(.oraTextSecondary)
                Spacer()
                Text("\(Int(track.energyLevel * 100))%")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(accent)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.oraSurfaceElevated)
                    Capsule().fill(accent)
                        .frame(width: max(6, geo.size.width * track.energyLevel))
                }
            }
            .frame(height: 8)
        }
    }

    private func zoneCard(_ track: Track,
                          zone: (name: String, subtitle: String, accentHex: String),
                          accent: Color) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 22))
                .foregroundColor(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Best for · \(zone.name)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.oraTextPrimary)
                Text("\(zone.subtitle) — Dromo plays this when your cadence is near \(Int(track.bpm)) BPM.")
                    .font(.system(size: 12))
                    .foregroundColor(.oraTextSecondary)
            }
            Spacer()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
