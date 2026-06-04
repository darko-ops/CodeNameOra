import Foundation

/// Routes feedback to the correct store, enforcing the two-jobs separation
/// (ARCHITECTURE §8): objective signals go to the shared Global Track Table;
/// subjective signals go to the private per-user layer. Neither path can touch the
/// other's store — that separation is the whole point.
public actor FeedbackRouter {
    private let api: TrackTableAPI
    private let preferences: PreferenceStoring
    private let clientID: String

    public init(api: TrackTableAPI, preferences: PreferenceStoring, clientID: String) {
        self.api = api
        self.preferences = preferences
        self.clientID = clientID
    }

    /// Objective → Global Track Table confirm/correction. Never writes preferences.
    @discardableResult
    public func reportObjective(_ signal: ObjectiveSignal, trackID: String) async -> TrackFacts? {
        try? await api.confirm(trackID: trackID, signal: signal, clientID: clientID)
    }

    /// Subjective → private per-user store. Never calls the global API.
    public func reportSubjective(_ signal: SubjectiveSignal, trackID: String) async {
        await preferences.record(signal, trackID: trackID)
    }

    /// Current taste weights, for feeding the Phase-4 engine's `preferences`.
    public func preferenceWeights() async -> [String: Double] {
        await preferences.weights()
    }
}
