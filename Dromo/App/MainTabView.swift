import SwiftUI
import DromoCore

/// The home shell once a provider is connected: a tab bar — Home, Go (start a run),
/// Sound (playlists), You (history/profile). Active session / summary take over
/// full-screen from `RootView`.
struct MainTabView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var nowPlaying: NowPlayingController

    private enum Tab { case home, go, sound, you }
    @State private var tab: Tab = .home

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)

            SessionSetupView()
                .tabItem { Label("Go", systemImage: "figure.run") }
                .tag(Tab.go)

            PlaylistsView()
                .tabItem { Label("Sound", systemImage: "waveform") }
                .tag(Tab.sound)

            LibraryView(showsDoneButton: false)
                .tabItem { Label("You", systemImage: "person.fill") }
                .tag(Tab.you)
        }
        .tint(.zoneSteady)
        // Starting a run from the Sound tab's tempo ladder lands on Go with the pace
        // already set. SessionSetupView consumes the request and clears it.
        .onChange(of: coordinator.runRequest) { request in
            if request != nil { tab = .go }
        }
        .overlay(alignment: .bottom) {
            if let track = nowPlaying.current, !nowPlaying.isExpanded {
                miniPlayer(track)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.bottom, 52)   // sit just above the tab bar
            }
        }
        // A tap that produces no sound has to say why. Spotify playback runs through the
        // runner's own Spotify app, which can be asleep or unavailable, and silence with
        // no explanation is indistinguishable from a broken app.
        .alert("Can't play that yet",
               isPresented: Binding(get: { nowPlaying.playbackError != nil },
                                    set: { if !$0 { nowPlaying.playbackError = nil } })) {
            Button("OK", role: .cancel) { nowPlaying.playbackError = nil }
        } message: {
            Text(nowPlaying.playbackError ?? "")
        }
        .sheet(isPresented: $nowPlaying.isExpanded) {
            NowPlayingView()
        }
    }

    @ViewBuilder
    private func miniArtwork(_ track: Track) -> some View {
        if let image = nowPlaying.artwork {
            Image(uiImage: image)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            TrackArtwork(track: track, size: 40, cornerRadius: 8)
        }
    }

    private func miniPlayer(_ track: Track) -> some View {
        HStack(spacing: Spacing.sm) {
            miniArtwork(track)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.oraTextPrimary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.oraTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.sm)
            Button { nowPlaying.togglePlayPause() } label: {
                Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.oraTextPrimary)
            }
        }
        .padding(Spacing.sm)
        .background(Color.oraSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { nowPlaying.isExpanded = true }
    }
}
