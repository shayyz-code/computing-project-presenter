import Foundation
import Testing

@testable import PresenterCore

/// A clock the test drives. This is why the timer takes one: elapsed-time
/// behaviour becomes arithmetic instead of a sleep, so pause/resume
/// accumulation is genuinely verified rather than approximated.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var offset: Duration = .zero
    private let origin = ContinuousClock.now

    func advance(_ amount: Duration) {
        lock.lock()
        defer { lock.unlock() }
        offset += amount
    }

    var instant: ContinuousClock.Instant {
        lock.lock()
        defer { lock.unlock() }
        return origin.advanced(by: offset)
    }
}

@MainActor
@Suite("PresentationTimer")
struct PresentationTimerTests {

    private func makeTimer() -> (PresentationTimer, TestClock) {
        let clock = TestClock()
        return (PresentationTimer(now: { clock.instant }), clock)
    }

    @Test("Starts at zero and stopped")
    func initialState() {
        let (timer, _) = makeTimer()
        #expect(timer.elapsed == .zero)
        #expect(!timer.isRunning)
        #expect(timer.formatted == "00:00")
    }

    @Test("Counts while running")
    func counts() {
        let (timer, clock) = makeTimer()
        timer.start()
        clock.advance(.seconds(90))
        #expect(timer.elapsed == .seconds(90))
        #expect(timer.isRunning)
    }

    @Test("Accumulates across pause and resume rather than restarting")
    func accumulates() {
        // The behaviour that matters most: pausing to answer a question must
        // not lose the count, and resuming must not start over.
        let (timer, clock) = makeTimer()
        timer.start()
        clock.advance(.seconds(60))
        timer.pause()

        // Time passing while paused must not be counted.
        clock.advance(.seconds(600))
        #expect(timer.elapsed == .seconds(60))
        #expect(!timer.isRunning)

        timer.resume()
        clock.advance(.seconds(30))
        #expect(timer.elapsed == .seconds(90))
    }

    @Test("Repeated pauses keep accumulating")
    func repeatedPauses() {
        let (timer, clock) = makeTimer()
        for _ in 0..<5 {
            timer.start()
            clock.advance(.seconds(10))
            timer.pause()
            clock.advance(.seconds(100))
        }
        #expect(timer.elapsed == .seconds(50))
    }

    @Test("start() while running does not restart or double-count")
    func startIsIdempotent() {
        // Wiring this to "presentation mode began" is only safe if a repeated
        // call is harmless.
        let (timer, clock) = makeTimer()
        timer.start()
        clock.advance(.seconds(30))
        timer.start()
        clock.advance(.seconds(30))
        #expect(timer.elapsed == .seconds(60))
    }

    @Test("pause() while stopped does nothing")
    func pauseWhenStopped() {
        let (timer, clock) = makeTimer()
        clock.advance(.seconds(10))
        timer.pause()
        #expect(timer.elapsed == .zero)
    }

    @Test("reset zeroes and stops")
    func reset() {
        let (timer, clock) = makeTimer()
        timer.start()
        clock.advance(.seconds(300))
        timer.reset()

        #expect(timer.elapsed == .zero)
        #expect(!timer.isRunning)

        // And a reset timer that is not restarted stays at zero.
        clock.advance(.seconds(60))
        #expect(timer.elapsed == .zero)
    }

    @Test("Formats mm:ss, rolling to h:mm:ss past an hour")
    func formatting() {
        // Rolls rather than showing "73:20": a presenter glancing at it should
        // not have to divide.
        #expect(PresentationTimer.format(.seconds(0)) == "00:00")
        #expect(PresentationTimer.format(.seconds(9)) == "00:09")
        #expect(PresentationTimer.format(.seconds(65)) == "01:05")
        #expect(PresentationTimer.format(.seconds(599)) == "09:59")
        #expect(PresentationTimer.format(.seconds(3599)) == "59:59")
        #expect(PresentationTimer.format(.seconds(3600)) == "1:00:00")
        #expect(PresentationTimer.format(.seconds(4400)) == "1:13:20")
    }

    @Test("A negative duration formats as zero rather than as nonsense")
    func negativeDuration() {
        #expect(PresentationTimer.format(.seconds(-5)) == "00:00")
    }

    @Test("Navigating slides does not disturb the timer")
    func independentOfNavigation() {
        // The timer measures the talk, not the slide.
        let (timer, clock) = makeTimer()
        var navigator = SlideNavigator(count: 20)
        timer.start()
        clock.advance(.seconds(45))

        for _ in 0..<10 { _ = navigator.advance() }
        _ = navigator.jump(to: 3)

        #expect(timer.elapsed == .seconds(45))
        #expect(timer.isRunning)
    }
}
