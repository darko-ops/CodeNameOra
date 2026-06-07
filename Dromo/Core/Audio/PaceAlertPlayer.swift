import Foundation
import AVFoundation
import DromoCore

/// Sounds the pace-deviation beeps (`PaceAlertMonitor.PaceAlert`) and ducks other audio
/// — the running music — so the cue is audible over it.
///
/// The two cues are deliberately distinct in BOTH pitch contour and rhythm so they're
/// unmistakable mid-run without looking at the phone:
///   • too slow → three quick **ascending** blips ("pick it up")
///   • too fast → two slower **descending** tones ("ease off")
///
/// Ducking uses `AVAudioSession`'s `.duckOthers`: activating our session lowers the
/// Music app's volume; deactivating it (after the beep) restores it. Best-effort —
/// an audio hiccup must never interrupt a run.
@MainActor
final class PaceAlertPlayer: NSObject, AVAudioPlayerDelegate {

    private let slow: AVAudioPlayer?
    private let fast: AVAudioPlayer?
    private let session = AVAudioSession.sharedInstance()

    override init() {
        // too slow → ascending, urgent (C5 → E5 → G5)
        slow = try? AVAudioPlayer(data: ToneSynth.wav(segments: [
            .tone(523, 0.09), .silence(0.05),
            .tone(659, 0.09), .silence(0.05),
            .tone(784, 0.11),
        ]))
        // too fast → descending, calmer (G5 → C5)
        fast = try? AVAudioPlayer(data: ToneSynth.wav(segments: [
            .tone(784, 0.16), .silence(0.07),
            .tone(523, 0.22),
        ]))
        super.init()
        slow?.delegate = self
        fast?.delegate = self
        slow?.prepareToPlay()
        fast?.prepareToPlay()
    }

    func play(_ alert: PaceAlertMonitor.PaceAlert) {
        duck(true)
        let player = (alert == .tooSlow) ? slow : fast
        player?.currentTime = 0
        if player?.play() != true {
            duck(false)   // nothing to play → don't leave the music ducked
        }
    }

    // MARK: AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.duck(false) }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.duck(false) }
    }

    // MARK: - Ducking

    private func duck(_ on: Bool) {
        do {
            if on {
                try session.setCategory(.playback, options: [.duckOthers])
                try session.setActive(true)
            } else {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            }
        } catch {
            // Best-effort: never let a ducking failure crash or stall a run.
        }
    }
}

/// Minimal in-memory tone synthesizer → 16-bit mono PCM WAV `Data`, playable directly by
/// `AVAudioPlayer(data:)`. Each tone gets a short fade in/out to avoid clicks.
enum ToneSynth {
    enum Segment {
        case tone(Double, Double)   // frequency (Hz), duration (s)
        case silence(Double)        // duration (s)
    }

    static func wav(segments: [Segment], sampleRate: Double = 44_100) -> Data {
        var samples: [Int16] = []
        let fadeLen = Int(0.005 * sampleRate)   // ~5 ms

        for segment in segments {
            switch segment {
            case .silence(let duration):
                samples.append(contentsOf: repeatElement(0, count: Int(duration * sampleRate)))
            case .tone(let frequency, let duration):
                let count = Int(duration * sampleRate)
                let fade = min(fadeLen, count / 2)
                for i in 0..<count {
                    let t = Double(i) / sampleRate
                    var amplitude = 0.6
                    if i < fade {
                        amplitude *= Double(i) / Double(fade)
                    } else if i >= count - fade {
                        amplitude *= Double(count - i) / Double(fade)
                    }
                    let value = sin(2 * .pi * frequency * t) * amplitude
                    let clamped = max(-1, min(1, value))
                    samples.append(Int16(clamped * Double(Int16.max)))
                }
            }
        }
        return encodeWAV(samples: samples, sampleRate: Int(sampleRate))
    }

    private static func encodeWAV(samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        let dataSize = samples.count * 2
        let byteRate = sampleRate * 2

        func ascii(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }

        ascii("RIFF"); u32(UInt32(36 + dataSize)); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1)                 // PCM, mono
        u32(UInt32(sampleRate)); u32(UInt32(byteRate)); u16(2); u16(16)
        ascii("data"); u32(UInt32(dataSize))
        for sample in samples {
            var x = sample.littleEndian
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
        }
        return data
    }
}
