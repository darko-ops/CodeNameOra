import Foundation

/// Which tempo sources this build can actually reach.
///
/// The enrichment chain silently omits a source whose credentials are missing, which is
/// correct — but it meant a build with no usable source ran a pass that could never
/// answer, forever, with nothing on screen to say why. Tracks simply stayed untagged and
/// the runner had no way to tell a slow lookup from an impossible one.
///
/// This makes that state nameable, so it can be shown and tested.
struct TempoSources: Equatable {
    /// Tempo by artist + title. The only source that works for DRM streaming libraries,
    /// where there is no audio to analyse and no tag to read.
    let hasGetSongBPM: Bool
    /// The shared Global Track Table, keyed by recording identity.
    let hasTrackTable: Bool
    /// Spotify's audio-features. Restricted for new apps, so present-but-forbidden is
    /// normal; it is never the source to rely on.
    let hasSpotify: Bool

    /// The platform's own BPM tag is always available — it needs no credentials — but it
    /// only answers for tracks that already carry one, so it cannot tag a library on its
    /// own. "Can we look anything up?" means a remote source.
    var canLookUpTempo: Bool { hasGetSongBPM || hasTrackTable || hasSpotify }

    static func current(
        getSongBPMKey: String = Config.getSongBPMKey,
        spotifyClientID: String = Config.spotifyClientID,
        spotifyClientSecret: String = Config.spotifyClientSecret,
        trackTableConfigured: Bool = LibrarySync.isConfigured
    ) -> TempoSources {
        TempoSources(
            hasGetSongBPM: !getSongBPMKey.isEmpty,
            hasTrackTable: trackTableConfigured,
            hasSpotify: !spotifyClientID.isEmpty && !spotifyClientSecret.isEmpty)
    }

    /// What to tell the runner when their library can't be tagged. Nil when at least one
    /// source can answer — a slow lookup needs no explanation, only an impossible one does.
    var unavailableReason: String? {
        guard !canLookUpTempo else { return nil }
        return "Tempo lookup isn't set up in this build, so songs without a BPM tag "
            + "can't be matched to your pace yet."
    }
}
