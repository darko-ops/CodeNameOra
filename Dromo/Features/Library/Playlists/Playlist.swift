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

    /// `bpmRangeLabel` for display. The lowest bucket starts at 0 so that untagged-free
    /// matching has a lower bound, but "0–125 BPM" shows a modelling artifact to the
    /// runner — nothing in a library sits near 0 BPM. Reads "Under 125 BPM" instead.
    var bpmRangeDisplay: String? {
        guard let lower = lowerBPM else { return nil }
        if lower == 0, let upper = upperBPM { return "Under \(Int(upper)) BPM" }
        return bpmRangeLabel
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
    ///
    /// The accents are one ordinal ramp — cool for easy, warm for hard, at matched
    /// lightness and chroma so the ladder reads as a single scale rather than six
    /// unrelated labels. Each value is a token the design language already carries
    /// (zoneWarmUp, oraSuccess, oraWarning, zonePeak, oraDestructive), so there are no
    /// new constants to keep in step.
    private static let definitions: [(String, String, String, String, Double, Double?, Double)] = [
        ("Warm Up",       "Ease into the run",   "figure.cooldown", "#8FA9C4", 0,   125,  390),
        ("Easy Miles",    "Conversational pace", "figure.walk",     "#85AFC0", 125, 140,  360),
        ("Tempo",         "Comfortably hard",    "figure.run",      "#7FB09A", 140, 152,  315),
        ("Threshold",     "Race-pace effort",    "speedometer",     "#C9A96E", 152, 164,  285),
        ("Intervals",     "Hard repeats",        "bolt.fill",       "#C98A6E", 164, 176,  255),
        ("Sprint Finish", "All-out kick",        "flame.fill",      "#C96E6E", 176, nil,  225)
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

    /// One tempo bucket, independent of whether the library has tracks in it — so a
    /// filter row can offer every window while `playlists(from:)` only yields the
    /// populated ones.
    struct Bucket: Identifiable, Equatable {
        let name: String
        let accentHex: String
        let lower: Double
        let upper: Double?

        var id: String { name }
        var accent: Color { Color(hex: accentHex) }

        /// Short form for a filter chip: "<125", "125–140", "176+".
        var chipLabel: String {
            if lower == 0, let upper { return "<\(Int(upper))" }
            if let upper { return "\(Int(lower))–\(Int(upper))" }
            return "\(Int(lower))+"
        }

        func contains(_ bpm: Double) -> Bool {
            guard bpm > 0, bpm >= lower else { return false }   // untagged never matches
            if let upper { return bpm < upper }
            return true
        }
    }

    /// Every tempo window, in ramp order. The single source of the ranges — filter chips
    /// and BPM tinting read this rather than restating the numbers.
    static var buckets: [Bucket] {
        definitions.map { Bucket(name: $0.0, accentHex: $0.3, lower: $0.4, upper: $0.5) }
    }

    /// The ramp colour for a BPM, for tinting a readout by its bucket. Nil when untagged.
    static func accent(forBPM bpm: Double) -> Color? {
        buckets.first { $0.contains(bpm) }?.accent
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
