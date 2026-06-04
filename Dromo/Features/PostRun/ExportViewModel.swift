import Foundation
import DromoCore

/// Drives the post-run export actions (Strava upload, Health save) and tracks
/// each one's status for the summary UI.
@MainActor
final class ExportViewModel: ObservableObject {

    enum Status: Equatable {
        case idle, working, done(String), failed(String)
    }

    @Published var strava: Status = .idle
    @Published var health: Status = .idle

    private let stravaService: StravaService
    private let healthManager = HealthKitManager()

    init() {
        self.stravaService = StravaService()
    }

    var stravaConfigured: Bool { StravaConfig.isConfigured }

    func exportToStrava(_ session: Session?) {
        guard let session, strava != .working else { return }
        strava = .working
        Task {
            do {
                let id = try await stravaService.upload(session: session)
                strava = .done("Uploaded · id \(id)")
            } catch {
                strava = .failed(error.localizedDescription)
            }
        }
    }

    func saveToHealth(_ session: Session?) {
        guard let session, health != .working else { return }
        health = .working
        Task {
            do {
                try await healthManager.save(session: session)
                health = .done("Saved to Health")
            } catch {
                health = .failed(error.localizedDescription)
            }
        }
    }
}
