import Foundation
import Accelerate

/// Tempo + rhythmic features from mono PCM, the Phase-0 recommended engine:
/// spectral-flux **onset envelope** → **autocorrelation** tempo, with a perceptual
/// tempo prior and parabolic peak interpolation. Pure (operates on a sample array,
/// no I/O) so it is unit-testable on synthetic signals without a device.
public struct OnsetTempoAnalyzer {

    public var frame = 1024
    public var hop = 512
    public var minBPM = 60.0
    public var maxBPM = 200.0
    /// Perceptual tempo prior (log-Gaussian) — biases octave choice toward how
    /// humans hear tempo, so 120 wins over its 60/240 harmonics. Center/sigma in
    /// natural-log space.
    public var priorCenterBPM = 125.0
    public var priorSigma = 0.55

    public init() {}

    public struct Features: Equatable, Sendable {
        public let bpm: Double
        public let confidence: Double
        public let octaveFlag: AnalysisResult.OctaveFlag
        public let beatOffsetMs: Int?
        public let energy: Double
        public let beatStrength: Double
    }

    public func analyze(samples: [Float], sampleRate: Double) -> Features? {
        guard sampleRate > 0, samples.count >= frame * 4 else { return nil }
        let env = onsetEnvelope(samples)
        guard env.count > 8 else { return nil }
        let fps = sampleRate / Double(hop)
        return tempo(env: env, fps: fps, samples: samples)
    }

    // MARK: - Onset envelope (spectral flux via vDSP real FFT)

    private func onsetEnvelope(_ samples: [Float]) -> [Float] {
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
        env.reserveCapacity(samples.count / hop)

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

            var flux: Float = 0
            for i in 0..<half {
                let d = mag[i] - prevMag[i]
                if d > 0 { flux += d }   // half-wave rectified: emphasize onsets
            }
            env.append(flux)
            prevMag = mag
            pos += hop
        }
        return env
    }

    // MARK: - Tempo via autocorrelation of the onset envelope

    private func prior(forBPM bpm: Double) -> Double {
        let x = log(bpm / priorCenterBPM) / priorSigma
        return exp(-0.5 * x * x)
    }

    private func tempo(env: [Float], fps: Double, samples: [Float]) -> Features {
        var mean: Float = 0
        vDSP_meanv(env, 1, &mean, vDSP_Length(env.count))
        let e = env.map { Double($0 - mean) }   // mean-removed

        func autocorr(_ lag: Int) -> Double {
            let n = e.count - lag
            guard n > 0 else { return 0 }
            var s = 0.0
            for i in 0..<n { s += e[i] * e[i + lag] }
            return s / Double(n)
        }

        let minLag = max(1, Int((60.0 / maxBPM) * fps))
        let maxLag = min(e.count - 1, Int((60.0 / minBPM) * fps))

        // Salience = autocorrelation × perceptual tempo prior.
        var salience = [Double](repeating: -.greatestFiniteMagnitude, count: maxLag + 1)
        var best = minLag
        if maxLag > minLag {
            for lag in minLag...maxLag {
                let bpm = 60.0 * fps / Double(lag)
                salience[lag] = autocorr(lag) * prior(forBPM: bpm)
                if salience[lag] > salience[best] { best = lag }
            }
        }

        // Parabolic interpolation around the winning lag → sub-frame precision.
        var refined = Double(best)
        if best > minLag, best < maxLag {
            let a = salience[best - 1], b = salience[best], c = salience[best + 1]
            let denom = a - 2 * b + c
            if abs(denom) > 1e-12 {
                let delta = 0.5 * (a - c) / denom
                if delta > -1, delta < 1 { refined = Double(best) + delta }
            }
        }
        let bpm = refined > 0 ? 60.0 * fps / refined : 0

        // Confidence: how far the winning salience stands above the mean salience.
        let window = salience[minLag...maxLag].filter { $0 > -.greatestFiniteMagnitude }
        let avg = window.isEmpty ? 0 : window.reduce(0, +) / Double(window.count)
        let peak = salience[best]
        let confidence = max(0, min(1, (peak - avg) / (abs(peak) + 1e-9)))

        // Octave flags — record (don't fix) a strong competing half/double tempo.
        let strongHalf = best * 2 <= maxLag && salience[best * 2] >= peak * 0.8     // bpm/2 plausible
        let strongDouble = best / 2 >= minLag && salience[best / 2] >= peak * 0.8   // bpm*2 plausible
        let flag: AnalysisResult.OctaveFlag =
            (strongHalf && strongDouble) ? .ambiguous : strongHalf ? .half : strongDouble ? .double : .none

        // Beat offset: first onset reaching half the envelope max.
        var maxEnv: Float = 0
        vDSP_maxv(env, 1, &maxEnv, vDSP_Length(env.count))
        var beatOffsetMs: Int?
        if maxEnv > 0, let idx = env.firstIndex(where: { $0 >= 0.5 * maxEnv }) {
            beatOffsetMs = Int(Double(idx) / fps * 1000)
        }

        // Energy (RMS) + beat strength (prominence of the strongest onsets).
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        let energy = Double(min(1, rms * 4))
        let sorted = env.sorted(by: >)
        let k = max(1, env.count / 20)
        let topMean = sorted.prefix(k).reduce(0, +) / Float(k)
        let beatStrength = maxEnv > 0 ? Double(min(1, topMean / maxEnv)) : 0

        return Features(bpm: bpm, confidence: confidence, octaveFlag: flag,
                        beatOffsetMs: beatOffsetMs, energy: energy, beatStrength: beatStrength)
    }
}
