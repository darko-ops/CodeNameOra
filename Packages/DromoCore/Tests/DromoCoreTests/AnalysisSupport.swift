import Foundation
@testable import DromoCore

/// Synthetic signal generators so the analyzer can be validated deterministically
/// on CI/macOS without any audio files or a device.
enum SynthAudio {

    /// A click train at `bpm`: each beat is a short decaying broadband burst (so the
    /// FFT spectral-flux registers an onset). Deterministic (no RNG).
    static func clickTrain(bpm: Double, seconds: Double, sampleRate: Double) -> [Float] {
        let n = Int(seconds * sampleRate)
        var s = [Float](repeating: 0, count: n)
        let period = Int(sampleRate * 60.0 / bpm)
        guard period > 0 else { return s }
        let burst = 64
        var beat = 0
        while beat < n {
            for j in 0..<burst where beat + j < n {
                // Decaying alternating impulse → broadband, deterministic.
                let decay = Float(1.0 - Double(j) / Double(burst))
                s[beat + j] = (j % 2 == 0 ? 1 : -1) * decay
            }
            beat += period
        }
        return s
    }

    /// A steady sine at `hz` (single dominant pitch class) for fingerprint tests.
    static func sine(hz: Double, seconds: Double, sampleRate: Double, amplitude: Float = 0.8) -> [Float] {
        let n = Int(seconds * sampleRate)
        return (0..<n).map { amplitude * Float(sin(2 * Double.pi * hz * Double($0) / sampleRate)) }
    }
}
