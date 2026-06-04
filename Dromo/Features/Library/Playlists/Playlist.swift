import SwiftUI
import DromoCore

/// A curated, BPM-bucketed grouping of tracks. Unlike `Track` (which lives in
/// DromoCore because the engine needs it), playlists are a purely presentational
/// way to browse the connected library by run intensity, so they live in the app.
struct Playlist: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let systemImage: String
    let accentHex: String
    /// Tempo playlists set a BPM window; ordinary playlists (library/popular) leave
    /// `lowerBPM` nil. Inclusive lower bound, exclusive upper bound.
    let lowerBPM: Double?
    let upperBPM: Double?
    /// Intensity-appropriate target pace (sec/km) for starting a run from a tempo
    /// playlist. nil for ordinary playlists (they use the app default).
    let suggestedPaceSecPerKm: Double?
    let tracks: [Track]

    init(id: String, name: String, subtitle: String, systemImage: String, accentHex: String,
         lowerBPM: Double? = nil, upperBPM: Double? = nil,
         suggestedPaceSecPerKm: Double? = nil, tracks: [Track]) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accentHex = accentHex
        self.lowerBPM = lowerBPM
        self.upperBPM = upperBPM
        self.suggestedPaceSecPerKm = suggestedPaceSecPerKm
        self.tracks = tracks
    }

    var accent: Color { Color(hex: accentHex) }

    /// "110–125 BPM" / "176+ BPM" — the tempo window, or nil for non-tempo playlists.
    var bpmRangeLabel: String? {
        guard let lower = lowerBPM else { return nil }
        if let upper = upperBPM { return "\(Int(lower))–\(Int(upper)) BPM" }
        return "\(Int(lower))+ BPM"
    }

    func contains(_ bpm: Double) -> Bool {
        guard let lower = lowerBPM, bpm >= lower else { return false }
        if let upper = upperBPM { return bpm < upper }
        return true
    }
}

/// The fixed set of specialized running playlists. Each bucket maps to a run
/// intensity; tracks flow into the bucket whose BPM window they fall in.
enum PlaylistCatalog {

    /// (name, subtitle, SF Symbol, accent hex, lowerBPM, upperBPM?, targetPace sec/km).
    /// Pace rises with intensity: Warm Up 6:30/km → Sprint Finish 3:45/km.
    private static let definitions: [(String, String, String, String, Double, Double?, Double)] = [
        ("Warm Up",       "Ease into the run",   "figure.cooldown", "#4FC3F7", 0,   125,  390),
        ("Easy Miles",    "Conversational pace", "figure.walk",     "#66BB6A", 125, 140,  360),
        ("Tempo",         "Comfortably hard",    "figure.run",      "#9CCC65", 140, 152,  315),
        ("Threshold",     "Race-pace effort",    "speedometer",     "#FFCA28", 152, 164,  285),
        ("Intervals",     "Hard repeats",        "bolt.fill",       "#FF7043", 164, 176,  255),
        ("Sprint Finish", "All-out kick",        "flame.fill",      "#EF5350", 176, nil,  225)
    ]

    /// Builds playlists from a library, keeping only buckets that have tracks.
    static func playlists(from library: [Track]) -> [Playlist] {
        definitions.compactMap { name, subtitle, image, hex, lower, upper, pace in
            let matched = matching(library, lower: lower, upper: upper)
            guard !matched.isEmpty else { return nil }
            return Playlist(
                id: name,
                name: name,
                subtitle: subtitle,
                systemImage: image,
                accentHex: hex,
                lowerBPM: lower,
                upperBPM: upper,
                suggestedPaceSecPerKm: pace,
                tracks: matched
            )
        }
    }

    private static func matching(_ library: [Track], lower: Double, upper: Double?) -> [Track] {
        library
            .filter { track in
                guard track.bpm > 0, track.bpm >= lower else { return false }  // skip untagged
                if let upper { return track.bpm < upper }
                return true
            }
            .sorted { $0.bpm < $1.bpm }
    }

    /// The playlist a given BPM falls into — used for a track's "best for" zone.
    static func zone(forBPM bpm: Double) -> (name: String, subtitle: String, accentHex: String)? {
        definitions
            .first { _, _, _, _, lower, upper, _ in
                bpm >= lower && (upper.map { bpm < $0 } ?? true)
            }
            .map { ($0.0, $0.1, $0.3) }
    }
}
