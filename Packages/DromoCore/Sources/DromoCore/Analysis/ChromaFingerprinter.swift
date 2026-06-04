import Foundation
import Accelerate

/// Chromaprint-style acoustic fingerprint: a compact, **gain-invariant** summary of
/// the recording's pitch-class (chroma) energy over time. Built to be stable across
/// different encodings of the same master — it works on perceptual chroma, ignores
/// absolute level (per-segment argmax of pitch class), and discards HF codec detail.
///
/// NOTE: this is a native chroma fingerprint, not libchromaprint. It is sufficient
/// for on-device identity + (Phase 3) lookup; swap in libchromaprint later if exact
/// AcoustID interop is required.
public struct ChromaFingerprinter {

    public var frame = 4096
    public var hop = 2048
    public var segments = 16
    public var minHz = 50.0

    public init() {}

    /// A lowercase hex string: one nibble (pitch class 0–11) per time segment.
    public func fingerprint(samples: [Float], sampleRate: Double) -> String? {
        guard sampleRate > 0, samples.count >= frame else { return nil }
        let chroma = chromagram(samples, sampleRate: sampleRate)
        guard !chroma.isEmpty else { return nil }

        var codes: [Int] = []
        let per = max(1, chroma.count / segments)
        var i = 0
        while i < chroma.count, codes.count < segments {
            var sum = [Float](repeating: 0, count: 12)
            for f in chroma[i..<min(i + per, chroma.count)] {
                for p in 0..<12 { sum[p] += f[p] }
            }
            codes.append(argmax(sum))
            i += per
        }
        return codes.map { String(format: "%x", $0 & 0xF) }.joined()
    }

    // MARK: - Chromagram (12 pitch-class energies per frame)

    private func chromagram(_ samples: [Float], sampleRate: Double) -> [[Float]] {
        let log2n = vDSP_Length(log2(Double(frame)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: frame)
        vDSP_hann_window(&window, vDSP_Length(frame), Int32(vDSP_HANN_NORM))

        let half = frame / 2
        // Precompute each FFT bin's pitch class (or -1 to ignore).
        var binPC = [Int](repeating: -1, count: half)
        for bin in 1..<half {
            let hz = Double(bin) * sampleRate / Double(frame)
            if hz < minHz || hz > sampleRate / 2 { continue }
            let midi = 69.0 + 12.0 * log2(hz / 440.0)
            binPC[bin] = ((Int(midi.rounded()) % 12) + 12) % 12
        }

        var realp = [Float](repeating: 0, count: half)
        var imagp = [Float](repeating: 0, count: half)
        var out: [[Float]] = []
        out.reserveCapacity(samples.count / hop)

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
            var chroma = [Float](repeating: 0, count: 12)
            for bin in 1..<half where binPC[bin] >= 0 { chroma[binPC[bin]] += mag[bin] }
            out.append(chroma)
            pos += hop
        }
        return out
    }

    private func argmax(_ v: [Float]) -> Int {
        var idx = 0
        var best = v.first ?? 0
        for (i, x) in v.enumerated() where x > best { best = x; idx = i }
        return idx
    }
}
