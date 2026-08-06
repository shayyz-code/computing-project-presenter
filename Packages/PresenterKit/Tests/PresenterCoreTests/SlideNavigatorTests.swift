import Testing

@testable import PresenterCore

// Note: `#expect` expands its argument into a closure over an immutable binding,
// so a mutating call cannot appear directly inside the macro. Results are bound
// to a local first throughout this suite.
@Suite("SlideNavigator")
struct SlideNavigatorTests {
    @Test("Moves forward and back within range")
    func movesWithinRange() {
        var nav = SlideNavigator(count: 3)
        #expect(nav.position == 1)

        let advanced = nav.advance()
        #expect(advanced)
        #expect(nav.position == 2)

        let retreated = nav.retreat()
        #expect(retreated)
        #expect(nav.position == 1)
    }

    @Test("Refuses to move past either end, and says so")
    func stopsAtBoundaries() {
        var nav = SlideNavigator(count: 2)

        let retreatedFromStart = nav.retreat()
        #expect(!retreatedFromStart)
        #expect(nav.position == 1)

        let advancedToEnd = nav.advance()
        #expect(advancedToEnd)
        let advancedPastEnd = nav.advance()
        #expect(!advancedPastEnd)
        #expect(nav.position == 2)
    }

    @Test("An empty deck is navigable without trapping")
    func emptyDeck() {
        // Reachable in real use: a PDF that opened but contained no pages.
        var nav = SlideNavigator(count: 0)

        #expect(nav.position == 0)
        #expect(nav.isAtStart)
        #expect(nav.isAtEnd)

        let advanced = nav.advance()
        #expect(!advanced)
        let retreated = nav.retreat()
        #expect(!retreated)

        nav.jump(to: 5)
        #expect(nav.position == 0)
    }

    @Test("Jumping clamps instead of failing", arguments: [(-4, 1), (0, 1), (2, 2), (9, 4)])
    func jumpClamps(target: Int, expected: Int) {
        var nav = SlideNavigator(count: 4)
        nav.jump(to: target)
        #expect(nav.position == expected)
    }

    @Test("An out-of-range starting position is clamped at construction")
    func initialPositionClamped() {
        #expect(SlideNavigator(count: 3, position: 99).position == 3)
        #expect(SlideNavigator(count: 3, position: -1).position == 1)
    }

    @Test("A negative count is treated as empty")
    func negativeCount() {
        let nav = SlideNavigator(count: -2)
        #expect(nav.count == 0)
        #expect(nav.position == 0)
    }
}
