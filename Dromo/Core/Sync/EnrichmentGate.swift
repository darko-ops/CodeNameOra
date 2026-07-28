import Foundation
import Network

/// Decides whether background enrichment may spend the network right now.
///
/// Enrichment is a nice-to-have that runs unprompted, so it must never cost the
/// runner money or battery they didn't agree to: on cellular it stays off unless
/// they explicitly opt in, and it stops entirely when the connection is expensive
/// (personal hotspot) or constrained (Low Data Mode) — conditions the user has
/// already told the system they care about.
///
/// The gate is polled before every lookup rather than sampled once, so walking out
/// of Wi-Fi mid-pass stops the pass at the next track instead of finishing it on
/// cellular.
final class EnrichmentGate: @unchecked Sendable {

    static let shared = EnrichmentGate()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.daed.dromo.enrichment-gate")
    private let lock = NSLock()
    private var path: NWPath?

    /// User opt-in for enrichment over cellular (Settings). Off by default —
    /// spending someone's data plan is a choice they make, not one we make.
    private let cellularKey = "dromo.enrichment.allowCellular"

    var allowsCellular: Bool {
        get { UserDefaults.standard.bool(forKey: cellularKey) }
        set { UserDefaults.standard.set(newValue, forKey: cellularKey) }
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            lock.lock(); self.path = path; lock.unlock()
        }
        monitor.start(queue: queue)
    }

    /// The gate handed to `LibraryEnrichmentPass`.
    var isOpen: @Sendable () async -> Bool {
        { [weak self] in self?.evaluate() ?? false }
    }

    /// `nil` path means the monitor hasn't reported yet — treat that as closed rather
    /// than guessing, since the first pass usually runs seconds after launch.
    private func evaluate() -> Bool {
        lock.lock(); let path = self.path; lock.unlock()
        guard let path, path.status == .satisfied else { return false }
        if path.isExpensive && !allowsCellular { return false }
        if path.isConstrained { return false }              // Low Data Mode
        return true
    }

    /// Plain-language reason enrichment is idle, for the coverage card.
    var pausedReason: String? {
        lock.lock(); let path = self.path; lock.unlock()
        guard let path else { return "Checking your connection…" }
        if path.status != .satisfied { return "Paused — no connection." }
        if path.isConstrained { return "Paused — Low Data Mode is on." }
        if path.isExpensive && !allowsCellular {
            return "Paused on cellular — turn on \"Use cellular data\" to continue."
        }
        return nil
    }
}
