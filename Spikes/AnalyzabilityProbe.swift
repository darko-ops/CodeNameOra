// THROWAWAY SPIKE — Phase 0, Task 0.1. NOT part of the Dromo app target.
// Drop into a scratch iOS app and call `AnalyzabilityProbe.run()` ON A DEVICE.
// It reports, per source, whether decoded PCM is obtainable. See ../findings/ios-analyzability.md.

import Foundation
import AVFoundation
import MediaPlayer

enum AnalyzabilityProbe {

    struct Result {
        let source: String
        let assetURLPresent: Bool?      // nil = N/A for this source
        let pcmReadable: Bool
        let note: String
    }

    /// Run every probe and print a markdown table to the console.
    static func run(importedFileURL: URL? = nil) async {
        var results: [Result] = []

        // Source #1 — a file imported into the app sandbox.
        if let url = importedFileURL {
            results.append(probeLocalFile(url))
        } else {
            results.append(Result(source: "Imported app file", assetURLPresent: nil,
                                  pcmReadable: false, note: "no importedFileURL passed — supply one"))
        }

        // Sources #2–#5 — the on-device Music library (mixed DRM-free + Apple Music items).
        results.append(contentsOf: await probeMusicLibrary(limit: 40))

        printTable(results)
    }

    // MARK: - Local imported file (expected: PCM YES)

    private static func probeLocalFile(_ url: URL) -> Result {
        do {
            let file = try AVAudioFile(forReading: url)
            let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                    sampleRate: file.fileFormat.sampleRate,
                                    channels: 1, interleaved: false)!
            let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 4096)!
            try file.read(into: buf)
            return Result(source: "Imported app file", assetURLPresent: nil,
                          pcmReadable: buf.frameLength > 0,
                          note: "read \(buf.frameLength) frames @ \(Int(file.fileFormat.sampleRate))Hz")
        } catch {
            return Result(source: "Imported app file", assetURLPresent: nil,
                          pcmReadable: false, note: "AVAudioFile error: \(error.localizedDescription)")
        }
    }

    // MARK: - Music library (assetURL is the gate; AVAssetReader is the proof)

    private static func probeMusicLibrary(limit: Int) async -> [Result] {
        let status = await withCheckedContinuation { c in
            MPMediaLibrary.requestAuthorization { c.resume(returning: $0) }
        }
        guard status == .authorized else {
            return [Result(source: "Music library", assetURLPresent: nil,
                           pcmReadable: false, note: "authorization not granted (\(status.rawValue))")]
        }

        let items = MPMediaQuery.songs().items ?? []
        guard !items.isEmpty else {
            return [Result(source: "Music library", assetURLPresent: nil,
                           pcmReadable: false, note: "library empty (expected in Simulator)")]
        }

        var withURL = 0
        var readable = 0
        var sample: [Result] = []

        for item in items.prefix(limit) {
            let hasURL = item.assetURL != nil
            if hasURL { withURL += 1 }
            var ok = false
            var note = hasURL ? "assetURL present" : "assetURL nil → DRM/cloud, not analyzable"
            if let url = item.assetURL {
                ok = canDecode(url)
                if ok { readable += 1 }
                note += ok ? " → AVAssetReader OK" : " → AVAssetReader FAILED (protected?)"
            }
            // Keep a few representative rows for the printed table.
            if sample.count < 8 {
                let label = (item.title ?? "?") + " — " + (item.albumTitle ?? "?")
                sample.append(Result(source: "Lib: \(label)", assetURLPresent: hasURL,
                                     pcmReadable: ok, note: note))
            }
        }

        let total = min(limit, items.count)
        let summary = Result(
            source: "Music library SUMMARY",
            assetURLPresent: nil, pcmReadable: readable > 0,
            note: "\(withURL)/\(total) had assetURL; \(readable)/\(total) decoded → " +
                  "analyzable fraction ≈ \(total > 0 ? readable * 100 / total : 0)%")
        return sample + [summary]
    }

    /// Attempt to pull one buffer of decoded PCM through AVAssetReader.
    private static func canDecode(_ url: URL) -> Bool {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return false }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return false }
        reader.add(output)
        guard reader.startReading() else { return false }
        let buffer = output.copyNextSampleBuffer()   // nil on protected assets
        reader.cancelReading()
        return buffer != nil
    }

    // MARK: - Output

    private static func printTable(_ results: [Result]) {
        print("\n| Source | assetURL? | PCM readable? | Note |")
        print("|---|:---:|:---:|---|")
        for r in results {
            let url = r.assetURLPresent.map { $0 ? "yes" : "no" } ?? "—"
            print("| \(r.source) | \(url) | \(r.pcmReadable ? "✅" : "❌") | \(r.note) |")
        }
        print("")
    }
}
