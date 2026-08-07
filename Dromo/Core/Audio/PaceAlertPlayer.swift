import Foundation
import AVFoundation
import DromoCore

/// Sounds the pace-deviation cues (`PaceAlertMonitor.PaceAlert`) and ducks other audio
/// — the running music — so the cue is audible over it.
///
/// Chimes rather than beeps. This fires every 15 s for as long as someone is off pace,
/// which is often enough that a sharp electronic blip stops being information and starts
/// being a reason to turn the feature off. So each cue is a struck note with a soft
/// attack and a natural decay — audible over music without demanding anything.
///
/// The two are distinct in BOTH direction and register, so they're unmistakable mid-run
/// without looking at the phone:
///   • too slow → a **rising** fifth in the upper register ("pick it up")
///   • too fast → a **falling** fifth, lower and warmer ("ease off")
///
/// Ducking uses `AVAudioSession`'s `.duckOthers`: activating our session lowers the
/// Music app's volume; deactivating it (after the cue) restores it. Best-effort —
/// an audio hiccup must never interrupt a run.
@MainActor
final class PaceAlertPlayer: NSObject, AVAudioPlayerDelegate {

    private let slow: AVAudioPlayer?
    private let fast: AVAudioPlayer?
    private let session = AVAudioSession.sharedInstance()

    override init() {
        // too slow → rising fifth, D5 → A5. Up and bright reads as "more".
        slow = try? AVAudioPlayer(data: ToneSynth.chime([
            .init(frequency: 587.33, start: 0,    duration: 0.55),
            .init(frequency: 880.00, start: 0.16, duration: 0.85),
        ]))
        // too fast → falling fifth, A4 → D4. Down and dark reads as "less", and the
        // lower register keeps the "ease off" cue from itself sounding urgent.
        fast = try? AVAudioPlayer(data: ToneSynth.chime([
            .init(frequency: 440.00, start: 0,    duration: 0.55),
            .init(frequency: 293.66, start: 0.16, duration: 1.00),
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

/// Minimal in-memory chime synthesizer → 16-bit mono PCM WAV `Data`, playable directly by
/// `AVAudioPlayer(data:)`.
///
/// Notes are mixed, not sequenced, so they can overlap: a note's decay rings on under the
/// one after it. That overlap is most of what separates a chime from two beeps in a row.
enum ToneSynth {

    /// One struck note.
    struct Voice {
        /// Pitch, in Hz.
        var frequency: Double
        /// When it is struck, in seconds from the start of the cue.
        var start: TimeInterval
        /// How long it rings. The decay is exponential, so this is the audible tail
        /// rather than a hard cutoff.
        var duration: TimeInterval
        var gain: Double = 1
    }

    /// ~12 ms of fade-in. Long enough that a note swells rather than clicks, short enough
    /// that it still reads as struck rather than faded up.
    private static let attack: TimeInterval = 0.012
    /// Peak amplitude. Well under full scale: the cue only has to be heard over ducked
    /// music, and the loudness at which a repeated sound becomes irritating is a good way
    /// below the loudness at which it becomes clear.
    private static let peak = 0.28
    /// Relative levels of the 2nd and 3rd harmonics. A pure sine sounds synthetic and a
    /// bright one sounds shrill; a little of each partial gives the note some body.
    private static let partials = [1.0, 0.16, 0.05]

    static func chime(_ voices: [Voice], sampleRate: Double = 44_100) -> Data {
        let span = voices.map { $0.start + $0.duration }.max() ?? 0
        guard span > 0 else { return encodeWAV(samples: [], sampleRate: Int(sampleRate)) }
        var mix = [Double](repeating: 0, count: Int(span * sampleRate))

        for voice in voices {
            let offset = Int(voice.start * sampleRate)
            let count = min(Int(voice.duration * sampleRate), mix.count - offset)
            guard count > 0 else { continue }
            // Ring out to roughly a thirtieth of the strike over the note's length, which
            // is the decay of something struck rather than something switched off.
            let tau = voice.duration / 3.5
            for i in 0..<count {
                let t = Double(i) / sampleRate
                let envelope = min(1, t / attack) * exp(-t / tau)
                var value = 0.0
                for (harmonic, level) in partials.enumerated() {
                    value += level * sin(2 * .pi * voice.frequency * Double(harmonic + 1) * t)
                }
                mix[offset + i] += value * envelope * voice.gain * peak
            }
        }

        // Overlapping voices sum, so clamp — a cue that clipped would be exactly the
        // harsh edge this whole design is avoiding.
        let samples = mix.map { Int16(max(-1, min(1, $0)) * Double(Int16.max)) }
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
