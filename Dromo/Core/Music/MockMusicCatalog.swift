import Foundation
import DromoCore

/// A dense, BPM-spanning catalog of fake tracks (110–186 BPM) used to demo the
/// pace→BPM→track loop without a live Spotify connection. On device this is
/// replaced by the user's real library fetched through `SpotifyProvider`.
enum MockMusicCatalog {
    static let tracks: [Track] = make()

    private static func make() -> [Track] {
        // (title, artist, bpm) — roughly two tracks every 6 BPM across the range.
        let seeds: [(String, String, Double)] = [
            ("Low Tide", "Kaiso", 112),
            ("Slow Burn", "Mira Vale", 116),
            ("Coast Road", "Nightform", 120),
            ("Easy Current", "Pale Hours", 124),
            ("Steady Hands", "Volta", 128),
            ("Even Keel", "The Lernetwork", 130),
            ("Warm Up", "Cassette Sky", 132),
            ("Open Lane", "Marrow", 136),
            ("Pulse Width", "Auto Vox", 138),
            ("Tarmac", "Greyline", 140),
            ("Cadence", "Iris Motor", 142),
            ("Forward Lean", "Halberd", 144),
            ("Tempo Run", "Neon Field", 146),
            ("Push Off", "Saint Atlas", 148),
            ("Threshold", "Vantablack", 150),
            ("Negative Split", "Dyad", 152),
            ("Redline", "Coral Drift", 154),
            ("Surge", "Mono Lake", 156),
            ("Kick Drum Heart", "Ferro", 158),
            ("Overdrive", "Helia", 160),
            ("Full Tilt", "Brusco", 162),
            ("Hammer Down", "Aphelion", 164),
            ("Breakaway", "Tigerstripe", 166),
            ("Final Lap", "Komodo", 168),
            ("Kick Higher", "Voss", 170),
            ("Sprint Finish", "Maxx Output", 172),
            ("All Out", "Razorback", 175),
            ("Lactic", "Sundowner", 178),
            ("Heart Rate Max", "Apex Theory", 181),
            ("Photo Finish", "Concorde", 184),
            ("Kick It Open", "Velocideck", 186)
        ]

        return seeds.enumerated().map { index, seed in
            Track(
                id: "spotify:demo:\(index)",
                title: seed.0,
                artist: seed.1,
                bpm: seed.2,
                energyLevel: min(1, 0.4 + (seed.2 - 110) / 160),
                durationSeconds: 200,
                provider: .spotify
            )
        }
    }
}
