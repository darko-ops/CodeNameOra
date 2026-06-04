import Foundation

/// Abstraction over the BPM-indexed track library (Section 5.3 / BPMLibrary).
///
/// The concrete, GRDB-backed implementation lives in the app target; the core
/// engine and its tests depend only on this protocol.
public protocol BPMLibraryProviding: Sendable {
    /// Returns tracks whose BPM is within `tolerance` of `bpm`.
    func tracks(nearBPM bpm: Double, tolerance: Double) async -> [Track]
}
