import Foundation

@MainActor final class WatchViewModel: ObservableObject {
    @Published var currentBPM: Double = 0
    // TODO(Phase 4): consume WatchConnectivity updates.
}
