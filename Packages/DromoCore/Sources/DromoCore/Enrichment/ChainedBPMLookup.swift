import Foundation

/// Tries multiple BPM sources in order, returning the first hit. Lets the app prefer
/// Spotify Audio Features (best coverage) and fall back to GetSongBPM if Spotify's
/// (deprecation-prone) endpoint returns nothing.
public struct ChainedBPMLookup: BPMLookup {
    private let lookups: [BPMLookup]

    public init(_ lookups: [BPMLookup]) {
        self.lookups = lookups
    }

    public func bpm(title: String, artist: String) async -> Double? {
        for lookup in lookups {
            if let bpm = await lookup.bpm(title: title, artist: artist) { return bpm }
        }
        return nil
    }
}
