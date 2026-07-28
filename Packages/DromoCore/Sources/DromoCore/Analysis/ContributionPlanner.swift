import Foundation

/// One track that could be analyzed and contributed.
public struct ContributionCandidate: Sendable, Equatable {
    public let trackID: String
    /// Recording identity — a fact with no identity can't be shared or reused.
    public let identity: IdentityKey?
    /// Does the platform expose decodable audio? `MPMediaItem.assetURL == nil` means
    /// DRM, and DRM means no (see findings/ios-analyzability.md — never circumvented).
    public let isAnalyzable: Bool

    public init(trackID: String, identity: IdentityKey?, isAnalyzable: Bool) {
        self.trackID = trackID
        self.identity = identity
        self.isAnalyzable = isAnalyzable
    }
}

/// The state of the phone right now. Analysis decodes whole songs, which is the most
/// expensive thing Dromo does — it belongs on power and unmetered network, never in
/// the middle of someone's day.
public struct DeviceConditions: Sendable, Equatable {
    public var isCharging: Bool
    public var isOnUnmeteredNetwork: Bool
    public var isLowPowerMode: Bool
    /// A run in progress. Analysis must never compete with the session for CPU.
    public var isSessionActive: Bool

    public init(isCharging: Bool = false, isOnUnmeteredNetwork: Bool = false,
                isLowPowerMode: Bool = false, isSessionActive: Bool = false) {
        self.isCharging = isCharging
        self.isOnUnmeteredNetwork = isOnUnmeteredNetwork
        self.isLowPowerMode = isLowPowerMode
        self.isSessionActive = isSessionActive
    }
}

/// Decides what to analyze, and says plainly why it decided nothing.
public enum ContributionPlanner {

    /// Why a batch is empty — surfaced in Settings so the feature never looks broken
    /// when it is simply waiting for the right moment.
    public enum Hold: Sendable, Equatable {
        case verdictPending
        case verdictRed
        case sessionActive
        case notCharging
        case meteredNetwork
        case lowPowerMode
        case nothingToDo

        public var label: String {
            switch self {
            case .verdictPending: return "Waiting on Dromo's accuracy check"
            case .verdictRed:     return "Turned off — analysis didn't meet the accuracy bar"
            case .sessionActive:  return "Paused during your run"
            case .notCharging:    return "Waiting until you're charging"
            case .meteredNetwork: return "Waiting for Wi-Fi"
            case .lowPowerMode:   return "Paused in Low Power Mode"
            case .nothingToDo:    return "Nothing left to analyze"
            }
        }
    }

    public struct Plan: Sendable, Equatable {
        public var batch: [ContributionCandidate] = []
        /// Set when the batch is empty; nil when there's work to do.
        public var hold: Hold?
        /// Candidates excluded because the platform won't decode them (DRM).
        public var unanalyzable = 0
        /// Excluded because the recording is already known to the shared table.
        public var alreadyKnown = 0
        /// Excluded for want of an identity to key the fact by.
        public var noIdentity = 0
        /// Left for a later batch.
        public var deferred = 0
    }

    /// `alreadyKnown` is the set of identities the table already holds — analyzing
    /// them again would spend the battery to learn what everyone already knows.
    public static func plan(
        candidates: [ContributionCandidate],
        policy: ContributionPolicy = .current,
        conditions: DeviceConditions,
        alreadyKnown: Set<String> = [],
        batchLimit: Int = 20
    ) -> Plan {
        var plan = Plan()

        // The verdict outranks everything: with the valve closed there is nothing to
        // schedule, whatever the phone is doing.
        switch policy.verdict {
        case .pending: plan.hold = .verdictPending; return plan
        case .red:     plan.hold = .verdictRed; return plan
        case .yellow, .green: break
        }

        // A run owns the device. Battery and thermals come next.
        if conditions.isSessionActive { plan.hold = .sessionActive; return plan }
        if conditions.isLowPowerMode { plan.hold = .lowPowerMode; return plan }
        if !conditions.isCharging { plan.hold = .notCharging; return plan }
        if !conditions.isOnUnmeteredNetwork { plan.hold = .meteredNetwork; return plan }

        var batch: [ContributionCandidate] = []
        for candidate in candidates {
            guard candidate.isAnalyzable else { plan.unanalyzable += 1; continue }
            guard let identity = candidate.identity, identity.isValid else {
                plan.noIdentity += 1
                continue
            }
            guard !alreadyKnown.contains(identity.storageKey) else {
                plan.alreadyKnown += 1
                continue
            }
            if batch.count < batchLimit { batch.append(candidate) } else { plan.deferred += 1 }
        }

        plan.batch = batch
        if batch.isEmpty { plan.hold = .nothingToDo }
        return plan
    }
}
