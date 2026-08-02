import SwiftUI
import DromoCore

/// The Sound tab — the music home for the connected service.
///
/// Ordered by what the product is for: browsing by intensity comes first, because
/// matching music to effort is the reason the app exists. The five training zones are a
/// ramp (recovery → VO2 max), so they're a one-column ladder rather than a grid — a grid
/// reads left-right-down, which makes an ordered scale look arbitrary.
///
/// Each ladder row has two targets: the row opens the playlist, ▶ starts a run at that
/// intensity. The second is what connects this tab to Go instead of leaving Sound a
/// dead-end browser.
struct PlaylistsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var nowPlaying: NowPlayingController
    @StateObject private var vm = PlaylistsViewModel()
    @State private var showingCreate = false
    @State private var renameTarget: Playlist?
    @State private var renameText = ""
    @State private var deleteTarget: Playlist?
    @State private var showingAllTracks = false
    @State private var showingAllPlaylists = false

    private let userPlaylistCap = 6

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    if let p = coordinator.enrichmentProgress, p.done < p.total {
                        enrichmentBanner(p)
                    }
                    zoneLadder
                    yourPlaylistsSection
                    highEnergySection
                    allTracksCard
                }
                .padding(.vertical, Spacing.lg)
            }
            .background(Color.oraBackground.ignoresSafeArea())
            .navigationTitle("Sound")
            .navigationBarTitleDisplayMode(.large)
            // Without these the title renders against SwiftUI's own light-scheme
            // assumptions and disappears into the bar.
            .toolbarBackground(Color.oraSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            // One search, not two: the field here hands its query to All tracks rather
            // than filtering a shelf the runner would then have to leave.
            .searchable(text: $vm.query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search songs, artists, BPM")
            .onSubmit(of: .search) { showingAllTracks = true }
            .navigationDestination(isPresented: $showingAllTracks) {
                AllTracksView(vm: vm)
            }
        }
        .preferredColorScheme(.dark)
        .task { await vm.load(from: coordinator.library) }
        .sheet(isPresented: $showingCreate) {
            CreatePlaylistView(tracks: vm.libraryTracks) { name, ids in
                await vm.createPlaylist(name: name, trackIDs: ids)
            }
        }
        .alert("Rename playlist",
               isPresented: Binding(get: { renameTarget != nil },
                                    set: { if !$0 { renameTarget = nil } })) {
            TextField("Playlist name", text: $renameText)
            Button("Save") {
                if let target = renameTarget {
                    Task { await vm.renamePlaylist(id: target.id, name: renameText) }
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .alert("Delete playlist?",
               isPresented: Binding(get: { deleteTarget != nil },
                                    set: { if !$0 { deleteTarget = nil } })) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    Task { await vm.deletePlaylist(target.id) }
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text(deleteTarget.map { "“\($0.name)” will be removed." } ?? "")
        }
    }

    // MARK: - Run by zone (the ladder)

    private var zoneLadder: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                OraLabel("Run by zone")
                Text("Pick a training zone — Dromo sets your target pace to match.")
                    .font(.system(size: 12))
                    .foregroundColor(.oraTextSecondary)
            }
            .padding(.horizontal, Spacing.screen)

            if vm.zonePlaylists.isEmpty {
                // Two different nothings: no music at all, versus music that has no
                // tempo yet. Saying "connect a library" to someone who just connected
                // one reads as the app not noticing.
                Text(vm.libraryTracks.isEmpty
                     ? "Connect a music service and your songs will sort themselves into zones."
                     : "Working out the tempo of your songs — they'll appear here as Dromo tags them.")
                    .font(.system(size: 13))
                    .foregroundColor(.oraTextMuted)
                    .padding(.horizontal, Spacing.screen)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(vm.zonePlaylists.enumerated()), id: \.element.id) { i, playlist in
                        zoneRow(playlist)
                        if i < vm.zonePlaylists.count - 1 {
                            Divider()
                                .overlay(Color.oraSurfaceElevated)
                                .padding(.leading, Spacing.md + 3 + Spacing.md)
                        }
                    }
                }
                .oraCard(padding: nil)
                .padding(.horizontal, Spacing.screen)

                Text("Tap a row to see its tracks · ▶ starts a run at that pace.")
                    .font(.system(size: 12))
                    .foregroundColor(.oraTextMuted)
                    .padding(.horizontal, Spacing.screen)
            }
        }
    }

    private func zoneRow(_ playlist: Playlist) -> some View {
        ZStack {
            // Behind the content, so ▶ keeps its own hit region. Same pattern the
            // sessions list uses.
            NavigationLink(destination: PlaylistDetailView(playlist: playlist)) { EmptyView() }
                .opacity(0)

            HStack(spacing: Spacing.md) {
                // A rail rather than a gradient tile with a 38pt glyph: in a ladder the
                // colour's job is to place the row on the scale, not to be an icon.
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(playlist.accent)
                    .frame(width: 3, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.oraTextPrimary)
                    Text(subtitle(for: playlist))
                        .font(.system(size: 12))
                        .foregroundColor(.oraTextSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Spacing.sm)

                if let pace = playlist.suggestedPaceSecPerKm {
                    VStack(spacing: 0) {
                        // Bare value: the unit is the label underneath, so paceString's
                        // own "/km" suffix would print it twice.
                        Text(PaceMath.paceValue(secondsPerKm: pace, metric: true))
                            .font(.system(size: 15, weight: .bold))
                            .tracking(-0.3)
                            .foregroundColor(playlist.accent)
                            .monospacedDigit()
                        Text("/km")
                            .font(.system(size: 10))
                            .foregroundColor(.oraTextMuted)
                    }

                    Button {
                        coordinator.requestRun(from: playlist)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.oraTextPrimary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.oraSurfaceElevated))
                            // Drawn at 32, tappable at 44, so the row's two targets
                            // don't fight each other.
                            .contentShape(Circle().inset(by: -6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "Start run at \(PaceMath.paceValue(secondsPerKm: pace, metric: true)) per kilometre")
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }

    /// "Under 125 BPM · 42 tracks" — the lowest bucket starts at 0 in the model, which
    /// is a matching bound rather than a tempo anyone runs at.
    private func subtitle(for playlist: Playlist) -> String {
        let count = "\(playlist.tracks.count) track\(playlist.tracks.count == 1 ? "" : "s")"
        guard let range = playlist.bpmRangeDisplay else { return count }
        return "\(range) · \(count)"
    }

    // MARK: - Your playlists

    private var yourPlaylistsSection: some View {
        let shown = showingAllPlaylists
            ? vm.userPlaylists
            : Array(vm.userPlaylists.prefix(userPlaylistCap))

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                OraLabel("Your playlists")
                Spacer()
                if vm.userPlaylists.count > userPlaylistCap {
                    Button(showingAllPlaylists ? "Show less" : "See all") {
                        withAnimation(.easeInOut(duration: 0.2)) { showingAllPlaylists.toggle() }
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.oraTextSecondary)
                }
            }
            .padding(.horizontal, Spacing.screen)

            VStack(spacing: 0) {
                if vm.userPlaylists.isEmpty {
                    Text("No playlists yet — create one for your next session.")
                        .font(.system(size: 13))
                        .foregroundColor(.oraTextMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.md)
                } else {
                    ForEach(shown) { playlist in
                        userPlaylistRow(playlist)
                        Divider()
                            .overlay(Color.oraSurfaceElevated)
                            .padding(.leading, Spacing.md + 40 + Spacing.md)
                    }
                }
                createRow
            }
            .oraCard(padding: nil)
            .padding(.horizontal, Spacing.screen)
        }
    }

    private func userPlaylistRow(_ playlist: Playlist) -> some View {
        NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
            HStack(spacing: Spacing.md) {
                tile(systemImage: "music.note.list")
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.oraTextPrimary)
                        .lineLimit(1)
                    Text(playlist.trackSummary)
                        .font(.system(size: 12))
                        .foregroundColor(.oraTextSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                chevron
            }
            .padding(Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renameText = playlist.name
                renameTarget = playlist
            } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) {
                deleteTarget = playlist
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    /// Creating is the last row of the same card rather than its own accent button: it's
    /// a low-frequency action that was outranking the library it sat above.
    private var createRow: some View {
        Button { showingCreate = true } label: {
            HStack(spacing: Spacing.md) {
                tile(systemImage: "plus")
                Text("Create playlist")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.oraTextSecondary)
                Spacer(minLength: 0)
            }
            .padding(Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - High energy

    /// Stays a horizontal shelf: it's a capped 15-item editorial selection, not the
    /// library, so it has an end the runner can actually reach.
    @ViewBuilder
    private var highEnergySection: some View {
        if !vm.highEnergy.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    OraLabel("High energy")
                    Spacer()
                    NavigationLink(destination: AllTracksView(vm: vm)) {
                        Text("See all")
                            .font(.system(size: 12))
                            .foregroundColor(.oraTextSecondary)
                    }
                }
                .padding(.horizontal, Spacing.screen)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(Array(vm.highEnergy.enumerated()), id: \.element.id) { i, track in
                            Button {
                                nowPlaying.play(tracks: vm.highEnergy, startAt: i)
                            } label: {
                                trackCell(track)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.screen)
                }
            }
        }
    }

    private func trackCell(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TrackArtwork(track: track, size: 118, cornerRadius: 14)
            Text(track.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.oraTextPrimary)
                .lineLimit(1)
            Text(track.artist)
                .font(.system(size: 12))
                .foregroundColor(.oraTextSecondary)
                .lineLimit(1)
            if track.bpm > 0 {
                Text("\(Int(track.bpm)) BPM")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.zoneSteady)
                    .monospacedDigit()
            }
        }
        .frame(width: 118, alignment: .leading)
    }

    // MARK: - All tracks entry

    /// Replaces the old "From your library" carousel, which scrolled sideways through
    /// the whole library with no search and no end.
    private var allTracksCard: some View {
        NavigationLink(destination: AllTracksView(vm: vm)) {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("All tracks")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.oraTextPrimary)
                    // Both numbers, because they diverge: Spotify hands over a library
                    // with no tempo at all, so "1,842 tagged" alone would read as most
                    // of the library having gone missing.
                    Text(vm.libraryTracks.isEmpty
                         ? "Connect a service to browse your library"
                         : "\(vm.libraryTracks.count) songs · \(vm.taggedCount) with tempo")
                        .font(.system(size: 12))
                        .foregroundColor(.oraTextSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                chevron
            }
            .oraRuledCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.screen)
    }

    // MARK: - Shared bits

    private func tile(systemImage: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.oraSurfaceElevated)
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundColor(.oraTextSecondary)
        }
        .frame(width: 40, height: 40)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.oraTextMuted)
    }

    // MARK: - Enrichment banner

    private func enrichmentBanner(_ p: LibraryEnrichmentPass.Progress) -> some View {
        HStack(spacing: Spacing.sm) {
            ProgressView().tint(.zoneSteady)
            (Text("Building your tempo profile… ")
                .foregroundColor(.oraTextSecondary)
             + Text("\(p.done)/\(p.total)")
                .foregroundColor(.oraTextPrimary))
                .font(.system(size: 13))
                .monospacedDigit()
            Spacer()
        }
        .oraCard(radius: 12)
        .padding(.horizontal, Spacing.screen)
    }
}
