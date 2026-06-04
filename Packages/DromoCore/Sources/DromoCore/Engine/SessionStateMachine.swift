import Foundation

/// Drives the lifecycle of a run: idle → setup → countdown → active ⇄ paused →
/// completed (Section 5.4).
@MainActor
public final class SessionStateMachine: ObservableObject {

    public enum State {
        case idle
        case setup                    // user setting pace target
        case countdown(Int)           // 3-2-1 before start
        case active(Session)
        case paused(Session)
        case completed(Session)
    }

    @Published public private(set) var state: State = .idle

    /// Injectable so callers/tests can control the per-tick delay.
    private let countdownTick: () async -> Void

    public init(countdownTick: @escaping () async -> Void = {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }) {
        self.countdownTick = countdownTick
    }

    // MARK: - Transitions

    public func startSetup() { state = .setup }

    public func beginCountdown(withSession session: Session) {
        state = .countdown(3)
        Task { [weak self] in
            guard let self else { return }
            for i in stride(from: 3, through: 1, by: -1) {
                self.state = .countdown(i)
                await self.countdownTick()
            }
            self.state = .active(session)
        }
    }

    public func pause() {
        if case .active(let session) = state {
            state = .paused(session)
        }
    }

    public func resume() {
        if case .paused(let session) = state {
            state = .active(session)
        }
    }

    public func complete() {
        switch state {
        case .active(let s), .paused(let s):
            var finished = s
            finished.endedAt = Date()
            finished.status = .completed
            state = .completed(finished)
        default:
            break
        }
    }

    public func abandon() {
        switch state {
        case .active(let s), .paused(let s):
            var ended = s
            ended.status = .abandoned
            state = .completed(ended)
        default:
            break
        }
    }

    /// Test seam — `internal`, so only `@testable import` (tests within this
    /// package) can reach it; production callers cannot set state directly.
    func setStateForTesting(_ newState: State) {
        state = newState
    }
}
