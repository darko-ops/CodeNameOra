import Foundation
import AVFoundation

/// Reads the recording's ISRC from file metadata when present (ARCHITECTURE §6:
/// ISRC is the primary identity key). Best-effort — many files carry no ISRC, in
/// which case identity falls back to the acoustic fingerprint.
enum ISRCReader {

    static func isrc(from url: URL) async -> String? {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.metadata) else { return nil }

        // ID3 TSRC frame.
        let id3 = AVMetadataItem.metadataItems(
            from: metadata,
            filteredByIdentifier: .id3MetadataInternationalStandardRecordingCode)
        if let item = id3.first, let value = try? await item.load(.stringValue) {
            return normalize(value)
        }

        // Some encoders stash ISRC in a user-text/comment key (e.g. "ISRC").
        for item in metadata {
            if let key = item.commonKey?.rawValue ?? item.key as? String,
               key.uppercased().contains("ISRC"),
               let value = try? await item.load(.stringValue) {
                return normalize(value)
            }
        }
        return nil
    }

    private static func normalize(_ raw: String) -> String? {
        // ISRC is exactly 12 alphanumerics (e.g. USRC17607839); strip dashes/spaces.
        let stripped = raw.uppercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
        let result = String(String.UnicodeScalarView(stripped))
        return result.count == 12 ? result : nil
    }
}
