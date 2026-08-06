import Foundation

/// Elapsed time for a talk.
///
/// Measures the *presentation*, not the slide: navigating does not disturb it,
/// because what a presenter wants to know is how long they have been speaking.
///
/// The clock is injected. A timer that reads the real clock can only be tested
/// by sleeping, which makes the suite both slow and flaky — a three-second
/// assertion costs three seconds and still fails on a loaded machine. With the
/// clock as a parameter, elapsed-time behaviour becomes ordinary arithmetic and
/// pause/resume accumulation is actually verified rather than smoke-checked.
@MainActor
@Observable
public final class PresentationTimer {
    /// Accumulated time from previous runs. Kept separate from the current run
    /// so pausing to answer a question does not lose the count.
    private var accumulated: Duration = .zero
    private var startedAt: ContinuousClock.Instant?
    private let now: @Sendable () -> ContinuousClock.Instant

    public init(now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.now = now
    }

    public var isRunning: Bool { startedAt != nil }

    /// Total time this timer has been running, across every pause and resume.
    public var elapsed: Duration {
        guard let startedAt else { return accumulated }
        return accumulated + (now() - startedAt)
    }

    /// Begins timing. Idempotent: calling it while running does not restart or
    /// double-count, so wiring it to "presentation mode began" is safe even if
    /// that fires more than once.
    public func start() {
        guard startedAt == nil else { return }
        startedAt = now()
    }

    /// Stops timing, keeping the elapsed total.
    public func pause() {
        guard let startedAt else { return }
        accumulated += now() - startedAt
        self.startedAt = nil
    }

    public func resume() { start() }

    /// Back to zero and stopped.
    public func reset() {
        accumulated = .zero
        startedAt = nil
    }

    /// `mm:ss`, rolling to `h:mm:ss` past an hour.
    ///
    /// Rolls rather than showing `73:20`, because a presenter glancing at it
    /// should not have to divide.
    public var formatted: String { Self.format(elapsed) }

    static func format(_ duration: Duration) -> String {
        let total = max(0, Int(duration.components.seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}
