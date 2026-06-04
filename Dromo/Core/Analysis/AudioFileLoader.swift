import Foundation
import AVFoundation

/// Decodes an **analyzable** audio source to mono Float PCM at a fixed analysis
/// rate. Returns nil for DRM-protected assets (Phase 0: `AVAssetReader` can't read
/// them) — those are never analyzed and fall through to the Phase 6 catalog.
///
/// The decoded samples live only on the stack of the caller; nothing here persists
/// or transmits audio (ARCHITECTURE §4).
enum AudioFileLoader {

    /// Target analysis rate. Lower than CD rate — enough for BPM/chroma, cheaper,
    /// and it discards HF codec detail (helps fingerprint stability across formats).
    static let analysisSampleRate = 22_050.0

    struct Decoded {
        let samples: [Float]
        let durationMs: Int
        let sampleRate: Double
    }

    static func loadMono(url: URL) async -> Decoded? {
        let asset = AVURLAsset(url: url)

        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: analysisSampleRate,
            AVNumberOfChannelsKey: 1
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }   // false ⇒ protected/unreadable

        var samples: [Float] = []
        while let sb = output.copyNextSampleBuffer() {
            if let bb = CMSampleBufferGetDataBuffer(sb) {
                var length = 0
                var ptr: UnsafeMutablePointer<Int8>?
                CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil,
                                            totalLengthOut: &length, dataPointerOut: &ptr)
                if let ptr {
                    let count = length / MemoryLayout<Float>.size
                    ptr.withMemoryRebound(to: Float.self, capacity: count) {
                        samples.append(contentsOf: UnsafeBufferPointer(start: $0, count: count))
                    }
                }
            }
            CMSampleBufferInvalidate(sb)
        }
        reader.cancelReading()
        guard !samples.isEmpty else { return nil }

        let durationMs: Int
        if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite {
            durationMs = Int(seconds * 1000)
        } else {
            durationMs = Int(Double(samples.count) / analysisSampleRate * 1000)
        }
        return Decoded(samples: samples, durationMs: durationMs, sampleRate: analysisSampleRate)
    }
}
