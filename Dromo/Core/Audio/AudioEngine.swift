import AVFoundation

/// Two-deck audio engine for gapless, equal-power crossfades between *local*
/// audio files (Section 5.3 / Phase 2).
///
/// Two `AVAudioPlayerNode`s feed the main mixer; a transition ramps one up while
/// the other ramps down. This is for Dromo-owned local audio (cached tracks); when
/// playback is delegated to Spotify / Apple Music those apps own the audio and
/// can't be sample-crossfaded, so `CrossfadeController` no-ops for them.
final class AudioEngine {

    private let engine = AVAudioEngine()
    private let players = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private var active = 0          // index of the audible player
    private var prepared = false
    private var rampTask: Task<Void, Never>?

    func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func prepareIfNeeded() {
        guard !prepared else { return }
        configureSession()
        for player in players {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: nil)
            player.volume = 0
        }
        engine.prepare()
        try? engine.start()
        prepared = true
    }

    /// Starts `url` on the idle deck and equal-power crossfades to it.
    func crossfade(toFileAt url: URL, duration: TimeInterval) {
        guard let file = try? AVAudioFile(forReading: url) else { return }
        prepareIfNeeded()

        let incoming = players[1 - active]
        let outgoing = players[active]

        incoming.stop()
        incoming.scheduleFile(file, at: nil, completionHandler: nil)
        incoming.volume = 0
        incoming.play()

        rampTask?.cancel()
        rampTask = Task { [weak self] in
            await self?.ramp(incoming: incoming, outgoing: outgoing, duration: duration)
        }
        active = 1 - active
    }

    func stop() {
        rampTask?.cancel()
        players.forEach { $0.stop() }
        engine.stop()
        prepared = false
    }

    private func ramp(incoming: AVAudioPlayerNode, outgoing: AVAudioPlayerNode, duration: TimeInterval) async {
        let steps = 25
        let stepNanos = UInt64(max(0.01, duration) / Double(steps) * 1_000_000_000)
        for i in 0...steps {
            if Task.isCancelled { return }
            let gains = CrossfadeCurve.gains(progress: Double(i) / Double(steps))
            incoming.volume = Float(gains.incoming)
            outgoing.volume = Float(gains.outgoing)
            try? await Task.sleep(nanoseconds: stepNanos)
        }
        outgoing.stop()
    }
}
