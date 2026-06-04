import Foundation
import DromoCore

/// GRDB-backed, BPM-indexed track cache (Section 5.3 / Phase 2).
/// Conforms to DromoCore.BPMLibraryProviding — the concrete impl the engine queries.
actor BPMLibrary: BPMLibraryProviding {
    func tracks(nearBPM bpm: Double, tolerance: Double) async -> [Track] {
        // TODO(Phase 2): query the SQLite BPM index.
        []
    }
}
