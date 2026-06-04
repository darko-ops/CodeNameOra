import Foundation
import DromoCore

/// Loads saved-run summaries for the Library list and supports deletion.
@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var summaries: [SessionSummary] = []
    @Published private(set) var stats = DashboardStats()
    @Published private(set) var isLoading = false

    private let repository = SessionRepository()
    private let statsRepository = StatsRepository()

    func load() async {
        isLoading = true
        summaries = (try? await repository.summaries()) ?? []
        stats = (try? await statsRepository.load()) ?? DashboardStats()
        isLoading = false
    }

    func delete(_ id: String) async {
        try? await repository.delete(id: id)
        await load()
    }

    func fullSession(_ id: String) async -> Session? {
        try? await repository.fullSession(id: id)
    }
}
