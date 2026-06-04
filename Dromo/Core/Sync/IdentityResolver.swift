import Foundation
import DromoCore

/// Computes a track's identity key (ARCHITECTURE §6): ISRC preferred (instant, from
/// metadata), else an acoustic fingerprint. Cheaper than full analysis — fingerprint
/// skips tempo/feature extraction — so the common path (ISRC present → server lookup)
/// touches no DSP at all.
enum IdentityResolver {

    static func key(for url: URL) async -> IdentityKey {
        if let isrc = await ISRCReader.isrc(from: url) {
            return IdentityKey(isrc: isrc)
        }
        // No ISRC: fingerprint the audio. (A later full analysis on a server MISS
        // re-decodes — acceptable; the ISRC path, which dominates mainstream
        // libraries, avoids decoding entirely.)
        if let decoded = await AudioFileLoader.loadMono(url: url),
           let fingerprint = ChromaFingerprinter().fingerprint(
               samples: decoded.samples, sampleRate: decoded.sampleRate) {
            return IdentityKey(fingerprint: fingerprint)
        }
        return IdentityKey()   // unanalyzable / unreadable
    }
}
