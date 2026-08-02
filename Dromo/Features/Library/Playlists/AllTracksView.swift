import SwiftUI
import DromoCore

/// Where the library actually becomes browsable — searchable, filterable by tempo, and
/// sorted by BPM by default.
///
/// This replaces the old "From your library" horizontal shelf, which scrolled sideways
/// through thousands of tracks with no search and no end. Sorting by tempo is the point
/// of the screen, so it is the default rather than an option.
///
/// Shares `PlaylistsViewModel` with the tab rather than owning its own, so the query
/// typed in the Sound tab's field arrives here already applied — one search, not two.
struct AllTracksView: View {
    @ObservedObject var vm: PlaylistsViewModel
    @EnvironmentObject private var nowPlaying: NowPlayingController

    private var results: [Track] { vm.filteredTracks }

    var body: some View {
        VStack(spacing: 0) {
            filterChips
            resultBar
            Divider().overlay(Color.oraBorder)
            list
        }
        .background(Color.oraBackground.ignoresSafeArea())
        .navigationTitle("All tracks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.oraSurface, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .searchable(text: $vm.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search songs, artists, BPM")
    }

    // MARK: - BPM filter chips

    /// Reads its windows from `PlaylistCatalog`, so the chips and the zone ladder are
    /// visibly the same taxonomy and the ranges are stated in exactly one place.
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                chip(label: "All BPM", tint: .oraTextSecondary,
                     isSelected: vm.bpmFilter == nil) {
                    vm.bpmFilter = nil
                }
                ForEach(PlaylistCatalog.zones) { zone in
                    chip(label: zone.chipLabel, tint: zone.accent,
                         isSelected: vm.bpmFilter == zone) {
                        // Single-select, and tapping the active chip clears it.
                        vm.bpmFilter = (vm.bpmFilter == zone) ? nil : zone
                    }
                }
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, Spacing.sm)
        }
    }

    private func chip(label: String, tint: Color, isSelected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(isSelected ? .oraButtonText : tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? Color.oraButtonFill : Color.oraSurface)
                )
                .overlay(
                    Capsule().strokeBorder(isSelected ? .clear : Color.oraBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label == "All BPM" ? label : "\(label) BPM")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Result bar

    private var resultBar: some View {
        HStack {
            Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                .font(.system(size: 12))
                .foregroundColor(.oraTextSecondary)
                .monospacedDigit()
            Spacer()
            Menu {
                Picker("Sort", selection: $vm.sort) {
                    ForEach(PlaylistsViewModel.TrackSort.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(vm.sort.rawValue)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.oraTextSecondary)
            }
            .accessibilityLabel("Sort by \(vm.sort.rawValue)")
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.bottom, Spacing.sm)
    }

    // MARK: - Results

    @ViewBuilder
    private var list: some View {
        if results.isEmpty {
            emptyState
        } else {
            List(Array(results.enumerated()), id: \.element.id) { index, track in
                Button {
                    // The queue matches what's on screen, so "next" means the next row
                    // the runner can see rather than the next in some hidden order.
                    nowPlaying.play(tracks: results, startAt: index)
                } label: {
                    TrackRow(track: track)
                }
                .listRowBackground(Color.oraSurface)
                .listRowSeparatorTint(Color.oraSurfaceElevated)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Spacer()
            Text(emptyMessage)
                .font(.system(size: 14))
                .foregroundColor(.oraTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Names the reason there's nothing, so the runner knows which control to relax.
    private var emptyMessage: String {
        let q = vm.activeQuery.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { return "No tracks match “\(q)”." }
        if vm.bpmFilter != nil { return "Nothing in your library at this tempo yet." }
        return "No tracks yet — connect a music service to fill this in."
    }
}
