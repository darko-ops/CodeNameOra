import SwiftUI
import DromoCore

/// Build a playlist for a specific session: name it and pick tracks from the library.
struct CreatePlaylistView: View {
    let tracks: [Track]
    /// (name, ordered track ids) → caller persists.
    var onCreate: (String, [String]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected: Set<String> = []
    @State private var search = ""
    @State private var showingNamePrompt = false

    private var filtered: [Track] {
        guard !search.isEmpty else { return tracks }
        return tracks.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
            $0.artist.localizedCaseInsensitiveContains(search)
        }
    }

    private var orderedSelectedIDs: [String] {
        tracks.filter { selected.contains($0.id) }.map(\.id)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Pick songs, then tap Create to name your playlist.  ·  \(selected.count) selected")
                    .font(.system(size: 12))
                    .foregroundColor(.oraTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.screen)
                    .padding(.vertical, Spacing.sm)

                List(filtered) { track in
                    Button { toggle(track.id) } label: { row(track) }
                        .listRowBackground(Color.oraSurface)
                        .listRowSeparatorTint(Color.oraSurfaceElevated)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .searchable(text: $search, prompt: "Search your library")
            }
            .background(Color.oraBackground.ignoresSafeArea())
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { showingNamePrompt = true }
                        .fontWeight(.semibold)
                        .disabled(selected.isEmpty)   // just need at least one song
                }
            }
            .toolbarBackground(Color.oraSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("Name your playlist", isPresented: $showingNamePrompt) {
                TextField("Playlist name", text: $name)
                Button("Create") { finalize() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(selected.count) song\(selected.count == 1 ? "" : "s")")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func finalize() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty ? "New Playlist" : trimmed
        let ids = orderedSelectedIDs
        Task { await onCreate(finalName, ids); dismiss() }
    }

    private func row(_ track: Track) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: selected.contains(track.id) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundColor(selected.contains(track.id) ? .zoneSteady : .oraTextMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.oraTextPrimary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundColor(.oraTextSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
