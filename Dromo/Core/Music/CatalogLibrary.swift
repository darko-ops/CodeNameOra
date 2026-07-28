import Foundation
import DromoCore

/// Resolves fallback-catalog tracks to audio that can actually play.
///
/// `FallbackCatalog` in DromoCore describes the catalog — pre-tagged `TrackFacts`
/// spanning 110–190 BPM — but facts are not sound. A catalog track is only a real
/// candidate once a licensed audio file for it ships in the app bundle, so this type
/// is the single place that answers "can we play `catalog:170`?".
///
/// Until assets are bundled, `stockedTracks` is empty and the session pool is exactly
/// the runner's own library — today's behaviour, no dead weight in the pool. Drop the
/// audio into `Resources/Catalog/` and the day-one guarantee turns on with no other
/// code change: the pool spans every cadence and `CatalogPlaybackController` plays it.
///
/// Naming contract: `catalog:<bpm>` ⇒ `Catalog/catalog-<bpm>.m4a` in the main bundle.
struct CatalogLibrary {

    static let shared = CatalogLibrary()

    /// Subdirectory inside the bundle holding catalog audio.
    private let directory = "Catalog"
    private let fileExtension = "m4a"
    private let bundle: Bundle

    init(bundle: Bundle = .main) { self.bundle = bundle }

    /// The audio file for a catalog id, or nil when that track isn't stocked.
    func url(forTrackID id: String) -> URL? {
        guard let bpm = Self.bpm(fromCatalogID: id) else { return nil }
        return bundle.url(forResource: "catalog-\(bpm)", withExtension: fileExtension,
                          subdirectory: directory)
    }

    func canPlay(trackID: String) -> Bool { url(forTrackID: trackID) != nil }

    /// The catalog entries that have audio behind them — what the pool may admit.
    /// Empty until assets ship, which is why an unstocked build behaves exactly as
    /// before rather than filling the pool with tracks that can only be skipped.
    var stockedTracks: [TrackFacts] {
        FallbackCatalog.tracks.filter { canPlay(trackID: $0.id) }
    }

    /// True when the day-one guarantee is actually backed by audio. The UI must not
    /// promise "start with Dromo's mixes" while this is false.
    var isStocked: Bool { !stockedTracks.isEmpty }

    /// `catalog:170` → `170`. Returns nil for library ids (numeric persistent ids).
    static func bpm(fromCatalogID id: String) -> Int? {
        guard id.hasPrefix("catalog:") else { return nil }
        return Int(id.dropFirst("catalog:".count))
    }

    static func isCatalogID(_ id: String) -> Bool { id.hasPrefix("catalog:") }
}
