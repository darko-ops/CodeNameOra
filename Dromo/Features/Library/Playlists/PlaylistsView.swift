import SwiftUI
import DromoCore

/// The Sound tab — a music home for the connected service: your tracks, your
/// playlists, popular, and the pre-built tempo playlists (Warm Up → Sprint Finish).
/// Tap a playlist for its tracks; tap a track for full song details.
struct PlaylistsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var nowPlaying: NowPlayingController
    @StateObject private var vm = PlaylistsViewModel()
    @State private var showingCreate = false
    @State private var renameTarget: Playlist?
    @State private var renameText = ""
    @State private var deleteTarget: Playlist?

    private let twoColumns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    if let p = coordinator.enrichmentProgress, p.done < p.total {
                        enrichmentBanner(p)
                    }
                    yourPlaylistsSection
                    trackSection("From your library", vm.libraryTracks)
                    trackSection("Popular", vm.popular)
                    tempoSection
                }
                .padding(.vertical, Spacing.lg)
            }
            .background(Color.oraBackground.ignoresSafeArea())
            .navigationTitle("Sound")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.oraSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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

    // MARK: - Your playlists (user-created) — 2-col grid (max 6) + create

    private var yourPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header("Your playlists")

            if vm.userPlaylists.isEmpty {
                Text("No playlists yet — create one for your next session.")
                    .font(.system(size: 13))
                    .foregroundColor(.oraTextMuted)
                    .padding(.horizontal, Spacing.screen)
            } else {
                LazyVGrid(columns: twoColumns, spacing: Spacing.md) {
                    ForEach(Array(vm.userPlaylists.prefix(6))) { playlist in
                        NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                            userPlaylistCard(playlist)
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
                }
                .padding(.horizontal, Spacing.screen)
            }

            Button { showingCreate = true } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "plus")
                    Text("Create Playlist")
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.oraSurface)
                .foregroundColor(.zoneSteady)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.top, Spacing.xs)
        }
    }

    private func userPlaylistCard(_ playlist: Playlist) -> some View {
        HStack(spacing: Spacing.sm) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [playlist.accent, playlist.accent.opacity(0.45)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: playlist.systemImage)
                    .font(.system(size: 20, weight: .semibold)).foregroundColor(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.oraTextPrimary)
                    .lineLimit(1)
                Text("\(playlist.tracks.count) tracks")
                    .font(.system(size: 11))
                    .foregroundColor(.oraTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.sm)
        .background(Color.oraSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Enrichment banner

    private func enrichmentBanner(_ p: BPMEnricher.Progress) -> some View {
        HStack(spacing: Spacing.sm) {
            ProgressView().tint(.zoneSteady)
            Text("Building your tempo profile… \(p.done)/\(p.total)")
                .font(.system(size: 13))
                .foregroundColor(.oraTextSecondary)
            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.oraSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Spacing.screen)
    }

    // MARK: - Section headers

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.oraTextPrimary)
            .padding(.horizontal, Spacing.screen)
    }

    // MARK: - Track carousel (library / popular)

    @ViewBuilder
    private func trackSection(_ title: String, _ tracks: [Track]) -> some View {
        if !tracks.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                header(title)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                            Button {
                                nowPlaying.play(tracks: tracks, startAt: i)
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
            TrackArtwork(track: track, size: 132, cornerRadius: 14)
            Text(track.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.oraTextPrimary)
                .lineLimit(1)
            Text("\(Int(track.bpm)) BPM")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.zoneSteady)
        }
        .frame(width: 132)
    }

    // MARK: - Tempo grid (pre-created tempo playlists)

    @ViewBuilder
    private var tempoSection: some View {
        if !vm.tempoPlaylists.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                header("By tempo")
                LazyVGrid(columns: twoColumns, spacing: Spacing.md) {
                    ForEach(vm.tempoPlaylists) { playlist in
                        NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                            tempoCard(playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.screen)
            }
        }
    }

    private func tempoCard(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [playlist.accent, playlist.accent.opacity(0.45)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .aspectRatio(1, contentMode: .fit)
                .overlay(Image(systemName: playlist.systemImage)
                    .font(.system(size: 38, weight: .semibold)).foregroundColor(.white))
            Text(playlist.name)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.oraTextPrimary)
            Text(playlist.bpmRangeLabel ?? playlist.subtitle)
                .font(.system(size: 12))
                .foregroundColor(.oraTextSecondary)
            Text("\(playlist.tracks.count) tracks")
                .font(.system(size: 11))
                .foregroundColor(.oraTextMuted)
        }
    }
}
