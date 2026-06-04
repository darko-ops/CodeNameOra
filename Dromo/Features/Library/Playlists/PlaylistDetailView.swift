import SwiftUI
import DromoCore

/// The tracks inside one playlist, with a "Start run" that drives a live session
/// from exactly these tracks. Tapping a row plays it via the Now Playing player.
struct PlaylistDetailView: View {
    let playlist: Playlist

    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var nowPlaying: NowPlayingController
    @State private var showLiveHUD = false

    /// Default target when a playlist has no intensity (user/library playlists): 5:30/km.
    private let defaultPaceSecPerKm: Double = 330

    /// Tempo playlists auto-set their target pace from their intensity band; others
    /// fall back to the default.
    private var targetPaceSecPerKm: Double {
        playlist.suggestedPaceSecPerKm ?? defaultPaceSecPerKm
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                header
                startRunButton
                trackList
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, Spacing.lg)
        }
        .background(Color.oraBackground.ignoresSafeArea())
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.oraSurface, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(isPresented: $showLiveHUD) {
            LiveHUDView(vm: LiveSessionViewModel(
                tracks: playlist.tracks,
                targetPaceSecPerKm: targetPaceSecPerKm,
                provider: coordinator.musicProvider))
        }
    }

    private var startRunButton: some View {
        Button { showLiveHUD = true } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "play.fill")
                Text(playlist.suggestedPaceSecPerKm != nil
                     ? "Start run · \(PaceMath.paceString(secondsPerKm: targetPaceSecPerKm, metric: true))"
                     : "Start run with this playlist")
            }
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(playlist.tracks.isEmpty ? Color.oraSurfaceElevated : Color.zoneSteady)
            .foregroundColor(playlist.tracks.isEmpty ? .oraTextMuted : .black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(playlist.tracks.isEmpty)
    }

    private var header: some View {
        HStack(spacing: Spacing.md) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(
                    colors: [playlist.accent, playlist.accent.opacity(0.5)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 84, height: 84)
                .overlay(
                    Image(systemName: playlist.systemImage)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.white))
            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.subtitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.oraTextPrimary)
                if let range = playlist.bpmRangeLabel {
                    Text(range)
                        .font(.system(size: 13))
                        .foregroundColor(playlist.accent)
                }
                Text("\(playlist.tracks.count) tracks")
                    .font(.system(size: 12))
                    .foregroundColor(.oraTextMuted)
            }
            Spacer()
        }
    }

    private var trackList: some View {
        VStack(spacing: 0) {
            ForEach(Array(playlist.tracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    nowPlaying.play(tracks: playlist.tracks, startAt: index)
                } label: {
                    TrackRow(track: track, accent: playlist.accent)
                }
                .buttonStyle(.plain)
                if index < playlist.tracks.count - 1 {
                    Divider().overlay(Color.oraSurfaceElevated)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(Color.oraSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
