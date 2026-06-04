// THROWAWAY SPIKE — Phase 0, Task 0.2. NOT part of the Dromo app target.
// Demonstrates the *recommended* engine (Apple-native AVFoundation + Accelerate/vDSP) is feasible:
// load PCM → spectral-flux onset envelope → autocorrelation tempo → bpm/confidence/octave/energy.
// Run `BPMEstimatorSpike.validate(against:)` on owned files. See ../findings/analysis-engine.md.

import Foundation
import AVFoundation
import Accelerate

enum BPMEstimatorSpike {

    struct Estimate {
        let bpm: Double
        let confidence: Double      // 0…1, peak prominence of the autocorrelation
        let octaveAmbiguous: Bool   // a competing ½×/2× peak was nearly as strong
        let altBpm: Double?         // the competing octave candidate, if any
        let energy: Double          // 0…1, normalized RMS
        let beatStrength: Double    // 0…1, prominence of onset peaks
    }

    static let minBPM = 60.0
    static let maxBPM = 200.0
    static let sampleRate = 22_050.0
    static let frame = 1_024
    static let hop = 512

    // MARK: - Entry

    static func estimate(fileURL: URL) -> Estimate? {
        guard let samples = loadMonoSamples(url: fileURL) else { return nil }
        let env = onsetEnvelope(samples: samples)
        guard env.count > 8 else { return nil }
        let fps = sampleRate / Double(hop)
        return tempo(from: env, fps: fps, samples: samples)
    }

    // MARK: - Load + downmix to mono @ sampleRate

    private static func loadMonoSamples(url: URL) -> [Float]? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }   // returns false on protected assets

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
        return samples.isEmpty ? nil : samples
    }

    // MARK: - Spectral-flux onset envelope (vDSP real FFT)

    private static func onsetEnvelope(samples: [Float]) -> [Float] {
        let log2n = vDSP_Length(log2(Double(frame)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: frame)
        vDSP_hann_window(&window, vDSP_Length(frame), Int32(vDSP_HANN_NORM))

        let half = frame / 2
        var prevMag = [Float](repeating: 0, count: half)
        var realp = [Float](repeating: 0, count: half)
        var imagp = [Float](repeating: 0, count: half)
        var env: [Float] = []

        var pos = 0
        while pos + frame <= samples.count {
            var windowed = [Float](repeating: 0, count: frame)
            Array(samples[pos..<pos + frame]).withUnsafeBufferPointer {
                vDSP_vmul($0.baseAddress!, 1, window, 1, &windowed, 1, vDSP_Length(frame))
            }

            var mag = [Float](repeating: 0, count: half)
            windowed.withUnsafeBufferPointer { wptr in
                wptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cptr in
                    realp.withUnsafeMutableBufferPointer { rp in
                        imagp.withUnsafeMutableBufferPointer { ip in
                            var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                            vDSP_ctoz(cptr, 2, &split, 1, vDSP_Length(half))
                            vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                            vDSP_zvabs(&split, 1, &mag, 1, vDSP_Length(half))
                        }
                    }
                }
            }

            // Spectral flux = Σ positive bin-to-bin magnitude increases (onset emphasis).
            var flux: Float = 0
            for i in 0..<half {
                let d = mag[i] - prevMag[i]
                if d > 0 { flux += d }
            }
            env.append(flux)
            prevMag = mag
            pos += hop
        }
        return env
    }

    // MARK: - Tempo via autocorrelation of the onset envelope

    private static func tempo(from env: [Float], fps: Double, samples: [Float]) -> Estimate {
        var mean: Float = 0
        vDSP_meanv(env, 1, &mean, vDSP_Length(env.count))
        let e = env.map { $0 - mean }   // mean-remove so autocorrelation isn't dominated by DC

        func autocorr(_ lag: Int) -> Double {
            let n = e.count - lag
            guard n > 0 else { return 0 }
            var sum = 0.0
            for i in 0..<n { sum += Double(e[i]) * Double(e[i + lag]) }
            return sum / Double(n)
        }

        let minLag = max(1, Int((60.0 / maxBPM) * fps))   // fastest tempo → smallest lag
        let maxLag = Int((60.0 / minBPM) * fps)
        var scores: [Int: Double] = [:]
        var best = (lag: minLag, score: -Double.greatestFiniteMagnitude)
        for lag in minLag...maxLag {
            let s = autocorr(lag)
            scores[lag] = s
            if s > best.score { best = (lag, s) }
        }
        let bpm = 60.0 * fps / Double(best.lag)

        // Confidence = how far the winning peak stands above the average lag score.
        let vals = Array(scores.values)
        let avg = vals.reduce(0, +) / Double(vals.count)
        let confidence = max(0, min(1, (best.score - avg) / (abs(best.score) + 1e-9)))

        // Octave ambiguity: is the ½× (or 2×) tempo peak nearly as strong? Record, don't "fix".
        var ambiguous = false
        var alt: Double?
        if let hs = scores[best.lag * 2], hs > best.score * 0.8 { ambiguous = true; alt = bpm / 2 }
        let doubleLag = best.lag / 2
        if doubleLag >= minLag, let ds = scores[doubleLag], ds > best.score * 0.8 {
            ambiguous = true; alt = bpm * 2
        }

        // Energy (RMS) + beat strength (prominence of top onset peaks).
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        let sortedEnv = env.sorted(by: >)
        let topK = Array(sortedEnv.prefix(max(1, env.count / 20)))
        let peak = Double(sortedEnv.first ?? 1)
        let beatStrength = peak > 0 ? Double(topK.reduce(0, +) / Float(topK.count)) / peak : 0

        return Estimate(bpm: bpm, confidence: confidence,
                        octaveAmbiguous: ambiguous, altBpm: alt,
                        energy: Double(min(1, rms * 4)), beatStrength: min(1, beatStrength))
    }

    // MARK: - Validation harness (Task 0.2 acceptance)

    /// Run against owned files of known BPM and print the accuracy table.
    /// NOTE: here we pick the octave interpretation closest to the known BPM purely to measure
    /// the detector's *raw* accuracy. In the product, octave resolves against live cadence (Phase 4).
    static func validate(against set: [(url: URL, knownBPM: Double)]) {
        print("\n| Track | Known | Detected | Conf | Octave | |err| | ±2? |")
        print("|---|:---:|:---:|:---:|:---:|:---:|:---:|")
        var errors: [Double] = []
        var within2 = 0
        for t in set {
            guard let est = estimate(fileURL: t.url) else {
                print("| \(t.url.lastPathComponent) | \(Int(t.knownBPM)) | FAILED | — | — | — | — |")
                continue
            }
            let candidates = [est.bpm, est.altBpm].compactMap { $0 }
            let detected = candidates.min { abs($0 - t.knownBPM) < abs($1 - t.knownBPM) } ?? est.bpm
            let err = abs(detected - t.knownBPM)
            errors.append(err)
            if err <= 2 { within2 += 1 }
            print(String(format: "| %@ | %.0f | %.1f | %.2f | %@ | %.1f | %@ |",
                         t.url.lastPathComponent, t.knownBPM, detected, est.confidence,
                         est.octaveAmbiguous ? "amb" : "-", err, err <= 2 ? "✅" : "❌"))
        }
        guard !errors.isEmpty else { return }
        let mae = errors.reduce(0, +) / Double(errors.count)
        print(String(format: "\nMAE: %.2f BPM · within ±2: %d/%d (%.0f%%)",
                     mae, within2, errors.count, Double(within2) / Double(errors.count) * 100))
    }
}
