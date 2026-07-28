import Foundation

/// Decorators that make the per-user learning and enrichment stores COLLECTIVE across
/// duplicate copies of a recording: writes are re-keyed to the recording id, reads are
/// expanded back to every current track id. The wrapped store keeps its own contract
/// (privacy, upgrade rules, persistence) — these only translate the key space.
///
/// Why here and not inside each store: the stores shouldn't know the library's shape,
/// and the alias map shouldn't be persisted state they all consult. One translation
/// layer, applied where a store is handed to a consumer.

/// Learned behavioral effectiveness, shared across every copy of a recording: a push
/// that worked from the Spotify copy counts for the Apple Music copy too.
public struct CollectiveEffectivenessStore: EffectivenessStoring {
    private let base: any EffectivenessStoring
    private let aliases: RecordingAliases

    public init(base: any EffectivenessStoring, aliases: RecordingAliases) {
        self.base = base
        self.aliases = aliases
    }

    public func record(_ response: TrackResponse) async {
        await base.record(TrackResponse(trackID: aliases.recordingID(for: response.trackID),
                                        mode: response.mode,
                                        reward: response.reward,
                                        samples: response.samples))
    }

    public func effectiveness(for mode: PaceMode) async -> [String: Double] {
        aliases.expanded(await base.effectiveness(for: mode))
    }

    public func learned(for mode: PaceMode) async -> [String: LearnedEffectiveness] {
        aliases.expanded(await base.learned(for: mode))
    }

    /// Every mode's estimates, expanded — the shape `LiveLoop.updateEffectiveness`
    /// consumes when priming a session with past learning.
    public func allByMode() async -> [PaceMode: [String: LearnedEffectiveness]] {
        var out: [PaceMode: [String: LearnedEffectiveness]] = [:]
        for mode in PaceMode.allCases {
            out[mode] = await learned(for: mode)
        }
        return out
    }

    public func reset() async { await base.reset() }
}

/// Stated taste (likes/skips), shared across every copy of a recording.
public struct CollectivePreferenceStore: PreferenceStoring {
    private let base: any PreferenceStoring
    private let aliases: RecordingAliases

    public init(base: any PreferenceStoring, aliases: RecordingAliases) {
        self.base = base
        self.aliases = aliases
    }

    public func record(_ signal: SubjectiveSignal, trackID: String) async {
        await base.record(signal, trackID: aliases.recordingID(for: trackID))
    }

    public func weights() async -> [String: Double] {
        aliases.expanded(await base.weights())
    }

    public func reset() async { await base.reset() }
}

/// Enrichment results, stored once per recording: a BPM looked up through one app's
/// copy serves every other copy — and whatever copy survives a future re-merge —
/// without a second network request.
public struct CollectiveBPMSink: BPMSink {
    private let base: any BPMSink
    private let aliases: RecordingAliases

    public init(base: any BPMSink, aliases: RecordingAliases) {
        self.base = base
        self.aliases = aliases
    }

    public func store(bpm: Double, trackID: String) async {
        await base.store(bpm: bpm, trackID: aliases.recordingID(for: trackID))
    }

    public func store(_ finding: BPMFinding, trackID: String) async {
        await base.store(finding, trackID: aliases.recordingID(for: trackID))
    }
}
