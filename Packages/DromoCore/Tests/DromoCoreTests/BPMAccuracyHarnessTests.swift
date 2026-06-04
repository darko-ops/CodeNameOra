import XCTest
import AVFoundation
@testable import DromoCore

/// Phase-7 measurement harness. Runs the REAL analysis pipeline over a ground-truth
/// set of owned audio files and emits the accuracy report. Auto-skips unless a
/// ground-truth CSV is provided, so it never blocks CI / synthetic runs.
///
/// Usage (on a Mac, or adapted on-device):
///   DROMO_BPM_GROUNDTRUTH=/path/groundtruth.csv \
///   DROMO_BPM_REPORT=/path/findings/bpm-accuracy.md \
///   swift test --filter BPMAccuracyHarnessTests
///
/// CSV columns (header optional): path,true_bpm,difficulty
/// `path` is absolute or relative to the CSV's directory. `true_bpm` MUST be an
/// independent source — never the engine under test.
///
/// NOTE: the BPM algorithm is identical vDSP on macOS and iOS, so this measures real
/// *accuracy* faithfully. Per-track time is captured but device battery/CPU still
/// needs an on-device run.
final class BPMAccuracyHarnessTests: XCTestCase {

    func testMeasureRealLibrary() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let csvPath = env["DROMO_BPM_GROUNDTRUTH"] else {
            throw XCTSkip("Set DROMO_BPM_GROUNDTRUTH=<csv> to run the Phase-7 measurement.")
        }

        let csv = try String(contentsOfFile: csvPath, encoding: .utf8)
        let baseDir = (csvPath as NSString).deletingLastPathComponent
        let core = TrackAnalyzerCore()
        var results: [GroundTruthResult] = []

        for raw in csv.split(separator: "\n") {
            let cols = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cols.count >= 3, let trueBPM = Double(cols[1]) else { continue }  // skips header
            let path = cols[0].hasPrefix("/") ? cols[0] : baseDir + "/" + cols[0]
            let url = URL(fileURLWithPath: path)
            guard let decoded = try? await decodeMono(url) else {
                print("⚠️ could not decode \(url.lastPathComponent)")
                continue
            }
            let start = Date()
            guard let result = core.analyze(samples: decoded.samples, sampleRate: decoded.sampleRate)
            else { continue }
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            results.append(GroundTruthResult(
                trackID: url.lastPathComponent, trueBPM: trueBPM, difficulty: cols[2],
                detectedBPM: result.bpm, confidence: result.bpmConfidence,
                octaveFlag: result.tempoOctaveFlag, analysisMs: ms))
        }

        XCTAssertFalse(results.isEmpty, "no decodable ground-truth tracks found")
        let report = BPMAccuracy.evaluate(results)
        let markdown = Self.markdown(report, rows: results)
        print("\n" + markdown)
        if let out = env["DROMO_BPM_REPORT"] {
            try markdown.write(toFile: out, atomically: true, encoding: .utf8)
            print("wrote report → \(out)")
        }
    }

    // MARK: - Decode (mirrors the app's AudioFileLoader settings)

    private struct Decoded { let samples: [Float]; let sampleRate: Double }

    private func decodeMono(_ url: URL) async throws -> Decoded? {
        let rate = 22_050.0
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

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
        return samples.isEmpty ? nil : Decoded(samples: samples, sampleRate: rate)
    }

    // MARK: - Report formatting

    static func markdown(_ r: BPMAccuracyReport, rows: [GroundTruthResult]) -> String {
        func pct(_ x: Double) -> String { String(format: "%.0f%%", x * 100) }
        func f(_ x: Double) -> String { String(format: "%.1f", x) }

        var s = "# Phase 7 — BPM Accuracy Results (measured)\n\n"
        s += "**Verdict: \(r.verdict.rawValue)**  ·  n=\(r.count)\n\n"
        s += "| Metric | Value |\n|---|---|\n"
        s += "| Exact match (±1 BPM) | \(pct(r.exactMatchRate)) |\n"
        s += "| Octave-corrected match (±2) | \(pct(r.octaveCorrectedMatchRate)) |\n"
        s += "| Mean abs error (raw) | \(f(r.meanAbsErrorRaw)) BPM |\n"
        s += "| Median abs error (raw) | \(f(r.medianAbsErrorRaw)) BPM |\n"
        s += "| Mean abs error (octave-corrected) | \(f(r.meanAbsErrorOctaveCorrected)) BPM |\n"
        s += "| Median abs error (octave-corrected) | \(f(r.medianAbsErrorOctaveCorrected)) BPM |\n"
        s += "| High-confidence error rate | \(pct(r.highConfidenceErrorRate)) |\n"
        s += "| Low-confidence error rate | \(pct(r.lowConfidenceErrorRate)) |\n"
        s += "| Confidence predicts error? | \(r.confidencePredictsError ? "yes" : "no") |\n"
        s += "| Octave-flag recall (on octave errors) | \(pct(r.octaveFlagRecall)) |\n\n"

        s += "## By difficulty\n\n| Difficulty | n | Octave match | Mean abs err |\n|---|---|---|---|\n"
        for (tag, stat) in r.byDifficulty.sorted(by: { $0.key < $1.key }) {
            s += "| \(tag) | \(stat.count) | \(pct(stat.octaveMatchRate)) | \(f(stat.meanAbsErrorOctaveCorrected)) BPM |\n"
        }

        s += "\n## Per-track\n\n| Track | Difficulty | True | Detected | Conf | Octave | |err| | ms |\n"
        s += "|---|---|---|---|---|---|---|---|\n"
        for row in rows {
            s += "| \(row.trackID) | \(row.difficulty) | \(f(row.trueBPM)) | \(f(row.detectedBPM)) "
            s += "| \(f(row.confidence)) | \(row.octaveFlag.rawValue) "
            s += "| \(f(BPMAccuracy.octaveCorrectedError(row))) | \(row.analysisMs.map(String.init) ?? "—") |\n"
        }
        return s
    }
}
