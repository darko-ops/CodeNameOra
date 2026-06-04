import Foundation
import os
import DromoCore

/// Phase 2 orchestrator. Decodes an analyzable source, runs the DromoCore DSP off
/// the main thread (this is an `actor`), reads ISRC, and returns ONLY the numeric
/// `AnalysisResult`. Decoded audio never leaves this actor (ARCHITECTURE §4).
///
/// Threading: all work happens on the actor's executor, never the main thread, so
/// the UI stays responsive while a library is analyzed in the background (Phase 3
/// will drive this over the long-tail misses).
actor TrackAnalyzer {

    private let core = TrackAnalyzerCore()
    private let log = Logger(subsystem: "com.daed.dromo", category: "analysis")

    struct Outcome {
        let result: AnalysisResult
        let elapsedMs: Int
    }

    /// Returns nil when the source is unanalyzable (DRM/unreadable) or too short.
    func analyze(url: URL) async -> Outcome? {
        let start = DispatchTime.now()

        guard let decoded = await AudioFileLoader.loadMono(url: url) else {
            log.debug("unanalyzable (DRM/unreadable): \(url.lastPathComponent, privacy: .public)")
            return nil
        }

        let isrc = await ISRCReader.isrc(from: url)
        guard let result = core.analyze(
            samples: decoded.samples,
            sampleRate: decoded.sampleRate,
            isrc: isrc,
            durationMs: decoded.durationMs
        ) else { return nil }

        let elapsedMs = Int(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6)
        // Per-track timing informs the pre-analyze-vs-lazy decision (Phase 2 acceptance).
        log.info("""
            analyzed \(url.lastPathComponent, privacy: .public) in \(elapsedMs)ms: \
            \(Int(result.bpm)) BPM (conf \(String(format: "%.2f", result.bpmConfidence)), \
            octave \(result.tempoOctaveFlag.rawValue)), isrc=\(isrc ?? "nil", privacy: .public)
            """)
        return Outcome(result: result, elapsedMs: elapsedMs)
    }
}
