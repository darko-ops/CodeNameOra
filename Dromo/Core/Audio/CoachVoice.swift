import Foundation
import AVFoundation
import DromoCore

/// Speaks `CoachCue`s over the running music.
///
/// Ducking, not pausing: the same `.duckOthers` route `PaceAlertPlayer` uses lowers the
/// music for the length of the sentence and restores it after. The music never stops,
/// which is the whole premise of Phase 7 — coaching sits ON the DJ, not in place of it.
///
/// The engine decides WHEN (and refuses to speak during a crossfade); this type only
/// decides how it sounds. Cue selection stays in DromoCore where it is testable without
/// audio hardware.
@MainActor
final class CoachVoice: NSObject, AVSpeechSynthesizerDelegate {

    /// Runner opt-in. Off by default: an app that starts talking unprompted mid-run
    /// has made a decision that wasn't its to make.
    private static let enabledKey = "dromo.coach.enabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ cue: CoachCue) {
        guard Self.isEnabled else { return }
        // Never queue up a backlog: if the previous cue is still going, this one is
        // already stale — a split announced two splits late is worse than silence.
        guard !synthesizer.isSpeaking else { return }

        duck(true)
        let utterance = AVSpeechUtterance(string: cue.spoken)
        // Slightly brisk and a touch loud: it competes with music and wind, and a
        // runner shouldn't have to concentrate to catch it.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.04
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.15      // let the duck settle before the voice
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    /// Stop mid-sentence — used when the run ends or the runner pauses, so the coach
    /// doesn't keep talking to someone who has stopped.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        duck(false)
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.duck(false) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
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
            // Best-effort, exactly as with the pace beeps: a ducking failure must never
            // stall a run. Worst case the cue is quiet under the music.
        }
    }
}
