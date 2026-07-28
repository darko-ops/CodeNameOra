import SwiftUI
import DromoCore

/// "How much of your library can Dromo pace to?" — the number that turns the fallback
/// catalog from a crutch into a bridge. It starts low (a streaming library is DRM-
/// locked; see findings/ios-analyzability.md) and climbs as background enrichment
/// resolves BPM, so the runner can watch their own music take over.
///
/// Reads the enrichment cache directly rather than taking a snapshot from a session,
/// so it's honest even before the first run of the day.
@MainActor
final class LibraryCoverageModel: ObservableObject {
    @Published private(set) var coverage = LibraryCoverage(total: 0, tagged: 0)
    @Published private(set) var isLoading = false

    private let enriched = EnrichedBPMStore()

    /// `library` is the coordinator's fetched provider library — the same list the
    /// session pool is built from, so this card and the run can't disagree.
    func load(library: [Track]) async {
        isLoading = true
        defer { isLoading = false }
        let bpmByID = await enriched.all()
        // A track counts as covered when EITHER the provider gave us a tempo or
        // enrichment found one — the same test the pool builder applies.
        let entries = library.map {
            LibraryEntry(localID: $0.id,
                         providerBPM: $0.bpm > 0 ? $0.bpm : (bpmByID[$0.id] ?? 0))
        }
        coverage = LibraryCoverage.measure(entries: entries)
    }
}

struct LibraryCoverageCard: View {
    let library: [Track]
    @StateObject private var model = LibraryCoverageModel()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("TEMPO COVERAGE")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.oraTextMuted)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(model.coverage.tagged)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.oraTextPrimary)
                    .monospacedDigit()
                Text("of \(model.coverage.total) tracks")
                    .font(.system(size: 13))
                    .foregroundColor(.oraTextSecondary)
            }

            meter

            Text(model.coverage.summary)
                .font(.system(size: 12))
                .foregroundColor(.oraTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.oraSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task(id: library.count) { await model.load(library: library) }
    }

    /// Fills toward "your library carries the run" rather than toward 100%: hitting
    /// every track is neither achievable nor the point.
    private var meter: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.oraSurfaceElevated)
                Capsule()
                    .fill(model.coverage.carriesSession() ? Color.zoneSteady : Color.zoneWarmUp)
                    .frame(width: max(0, min(1, model.coverage.fraction)) * geo.size.width)
            }
        }
        .frame(height: 8)
        .animation(.easeInOut(duration: 0.4), value: model.coverage)
    }
}
