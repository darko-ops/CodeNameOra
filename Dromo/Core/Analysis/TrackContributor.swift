import Foundation
import Network
import UIKit
import DromoCore

/// Analyzes tracks the runner owns and publishes the tempo to the Global Track Table,
/// so a runner who only streams the same recording inherits it without analyzing
/// anything (ARCHITECTURE §6 analyze-once-globally).
///
/// Everything expensive or irreversible is gated:
///   · `ContributionPolicy` decides whether ANY result may be published — closed until
///     accuracy is measured, so today this service analyzes nothing and uploads nothing;
///   · `DeviceConditions` keeps decoding off battery, off cellular, and out of runs;
///   · only the numbers leave — never audio, never a title (§4/§5).
///
/// The app owns the plumbing; the decisions live in `ContributionPlanner`, where they
/// are testable without a device.
@MainActor
final class TrackContributor: ObservableObject {

    /// Runner opt-in, on top of the policy gate. Both must say yes.
    private static let enabledKey = "dromo.contribute.enabled"
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    struct Progress: Equatable {
        var done = 0
        var total = 0
        var published = 0
    }

    @Published private(set) var progress: Progress?
    /// Why nothing is running, in the runner's words.
    @Published private(set) var hold: ContributionPlanner.Hold?

    private let analyzer = TrackAnalyzer()
    private let api: TrackTableAPI
    private let cache = GRDBTrackFactsCache()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.daed.dromo.contributor")
    private var path: NWPath?
    private var task: Task<Void, Never>?
    /// Set while a run is in progress — analysis must never compete with a session.
    static var isSessionActive = false

    init(api: TrackTableAPI = HTTPTrackTableClient(baseURL: LibrarySync.baseURL)) {
        self.api = api
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.path = path }
        }
        monitor.start(queue: queue)
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    var conditions: DeviceConditions {
        DeviceConditions(
            isCharging: UIDevice.current.batteryState == .charging
                || UIDevice.current.batteryState == .full,
            isOnUnmeteredNetwork: path?.status == .satisfied && !(path?.isExpensive ?? true),
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            isSessionActive: Self.isSessionActive)
    }

    /// Analyze and publish what the policy and the phone currently allow.
    ///
    /// `resolveIdentity` and `analyzableURL` come from the music provider — the same
    /// calls the live session uses, so a track that can't be identified here couldn't
    /// have been paced there either.
    func run(tracks: [Track],
             analyzableURL: @escaping (String) async -> URL?,
             resolveIdentity: @escaping (String) async -> String?) {
        guard Self.isEnabled, ContributionPolicy.current.allowsContribution else {
            hold = ContributionPolicy.current.verdict == .red ? .verdictRed : .verdictPending
            return
        }
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            var candidates: [ContributionCandidate] = []
            for track in tracks {
                if Task.isCancelled { return }
                let url = await analyzableURL(track.id)
                let isrc = await resolveIdentity(track.id)
                candidates.append(ContributionCandidate(
                    trackID: track.id,
                    identity: isrc.map { IdentityKey(isrc: $0) },
                    isAnalyzable: url != nil))
            }

            let plan = ContributionPlanner.plan(candidates: candidates,
                                                conditions: self.conditions,
                                                alreadyKnown: await self.knownIdentities(candidates))
            self.hold = plan.hold
            guard !plan.batch.isEmpty else { return }

            self.progress = Progress(done: 0, total: plan.batch.count, published: 0)
            var published = 0
            for (index, candidate) in plan.batch.enumerated() {
                if Task.isCancelled { break }
                // Conditions are re-checked every track: unplugging mid-batch should
                // stop it, not finish it on battery.
                guard self.conditions.isCharging, !self.conditions.isSessionActive else {
                    self.hold = .notCharging
                    break
                }
                if let url = await analyzableURL(candidate.trackID),
                   var result = await self.analyzer.analyze(url: url)?.result {
                    result.isrc = candidate.identity?.isrc ?? result.isrc
                    // The gate, applied per result: a low-confidence reading is kept
                    // locally and never shared.
                    if ContributionPolicy.current.mayPublish(result),
                       let facts = try? await self.api.populate(result) {
                        await self.cache.put(facts)
                        published += 1
                    }
                }
                self.progress = Progress(done: index + 1, total: plan.batch.count,
                                         published: published)
            }
            self.progress = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        progress = nil
    }

    /// Recordings the shared table already holds — skipped, since re-analyzing them
    /// spends battery to learn what everyone already knows.
    private func knownIdentities(_ candidates: [ContributionCandidate]) async -> Set<String> {
        var known: Set<String> = []
        for candidate in candidates {
            if let identity = candidate.identity, await cache.get(identity) != nil {
                known.insert(identity.storageKey)
            }
        }
        return known
    }
}
