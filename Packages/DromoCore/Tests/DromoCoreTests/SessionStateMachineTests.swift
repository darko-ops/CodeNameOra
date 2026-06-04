import XCTest
@testable import DromoCore

@MainActor
final class SessionStateMachineTests: XCTestCase {

    private func makeSession() -> Session {
        Session(startedAt: Date(timeIntervalSince1970: 1_000_000), targetPace: 360)
    }

    func test_startSetup_movesToSetup() {
        let sm = SessionStateMachine()
        sm.startSetup()
        guard case .setup = sm.state else { return XCTFail("expected .setup, got \(sm.state)") }
    }

    func test_pauseResume_togglesBetweenActiveAndPaused() {
        let sm = SessionStateMachine()
        sm.beginActiveForTesting(makeSession())

        sm.pause()
        guard case .paused = sm.state else { return XCTFail("expected .paused, got \(sm.state)") }

        sm.resume()
        guard case .active = sm.state else { return XCTFail("expected .active, got \(sm.state)") }
    }

    func test_complete_fromActive_marksCompletedWithEndDate() {
        let sm = SessionStateMachine()
        sm.beginActiveForTesting(makeSession())

        sm.complete()
        guard case .completed(let session) = sm.state else {
            return XCTFail("expected .completed, got \(sm.state)")
        }
        XCTAssertEqual(session.status, .completed)
        XCTAssertNotNil(session.endedAt)
    }

    func test_abandon_fromPaused_marksAbandoned() {
        let sm = SessionStateMachine()
        sm.beginActiveForTesting(makeSession())
        sm.pause()

        sm.abandon()
        guard case .completed(let session) = sm.state else {
            return XCTFail("expected .completed, got \(sm.state)")
        }
        XCTAssertEqual(session.status, .abandoned)
    }

    func test_pause_fromIdle_isNoOp() {
        let sm = SessionStateMachine()
        sm.pause()
        guard case .idle = sm.state else { return XCTFail("expected .idle, got \(sm.state)") }
    }

    func test_beginCountdown_eventuallyBecomesActive() async {
        // Instant tick so the countdown resolves without real delay.
        let sm = SessionStateMachine(countdownTick: {})
        sm.beginCountdown(withSession: makeSession())

        guard case .countdown = sm.state else {
            return XCTFail("expected initial .countdown, got \(sm.state)")
        }

        // Let the spawned countdown Task run to completion.
        for _ in 0..<1000 {
            if case .active = sm.state { break }
            await Task.yield()
        }
        guard case .active = sm.state else {
            return XCTFail("expected .active after countdown, got \(sm.state)")
        }
    }
}

// Test-only helper to jump straight to the active state.
@MainActor
extension SessionStateMachine {
    func beginActiveForTesting(_ session: Session) {
        // Jump straight to .active for transition tests that don't care about
        // the countdown animation.
        setStateForTesting(.active(session))
    }
}
