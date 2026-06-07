import Foundation
import MusicKit

/// Resolves a recording's ISRC from the Apple Music **catalog** — the only identity
/// path for DRM / cloud tracks.
///
/// A streaming `MPMediaItem` carries no `assetURL` and no id3 `TSRC` tag, so the
/// file-based `ISRCReader` returns nil for it. But it *does* carry a `playbackStoreID`
/// (the catalog ID), and a `MusicCatalogResourceRequest<Song>` by that ID returns the
/// recording's `isrc` — a stable key we can store in the Global Track Table. Without
/// this, a streaming-only library can never key into the shared BPM commons.
///
/// Catalog reads require the MusicKit capability (developer token, auto-provided when
/// the App ID has the MusicKit service enabled) and an authorized user. Everything
/// degrades to `nil` on any failure, so callers cleanly fall back to existing behavior.
///
/// Results are cached per store ID for the resolver's lifetime. NB: batching via
/// `MusicCatalogResourceRequest(matching:memberOf:)` is the obvious next optimization
/// for large libraries — this first cut resolves one ID at a time to match the
/// existing per-track identity loop.
actor CatalogISRCResolver {

    /// storeID → isrc. A cached `nil` means "looked up, no ISRC" (don't retry).
    private var cache: [String: String?] = [:]
    private var authorized: Bool?

    func isrc(forStoreID storeID: String) async -> String? {
        let storeID = storeID.trimmingCharacters(in: .whitespaces)
        // "0" / empty is MediaPlayer's sentinel for "not a catalog item".
        guard !storeID.isEmpty, storeID != "0" else { return nil }
        if let cached = cache[storeID] { return cached }

        guard await ensureAuthorized() else {
            cache[storeID] = .some(nil)
            return nil
        }

        do {
            let request = MusicCatalogResourceRequest<Song>(
                matching: \.id, equalTo: MusicItemID(storeID))
            let response = try await request.response()
            let isrc = response.items.first?.isrc
            cache[storeID] = .some(isrc)
            return isrc
        } catch {
            cache[storeID] = .some(nil)
            return nil
        }
    }

    private func ensureAuthorized() async -> Bool {
        if let authorized { return authorized }
        // Idempotent: no prompt when already authorized.
        let status: MusicAuthorization.Status =
            MusicAuthorization.currentStatus == .authorized
            ? .authorized
            : await MusicAuthorization.request()
        let ok = (status == .authorized)
        authorized = ok
        return ok
    }
}
