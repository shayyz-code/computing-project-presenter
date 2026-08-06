import Testing

@testable import PresenterCore

@Suite("NavigationCommand")
struct NavigationCommandTests {

    @Test("next and previous move one slide")
    func stepping() {
        var navigator = SlideNavigator(count: 10, position: 5)

        // #expect cannot contain a mutating call — the macro closes over an
        // immutable binding — so bind the result first. See CLAUDE.md.
        let advanced = NavigationCommand.next.apply(to: &navigator)
        #expect(advanced)
        #expect(navigator.position == 6)

        let retreated = NavigationCommand.previous.apply(to: &navigator)
        #expect(retreated)
        #expect(navigator.position == 5)
    }

    @Test("first and last reach the ends from anywhere")
    func jumping() {
        var navigator = SlideNavigator(count: 16, position: 7)

        let toLast = NavigationCommand.last.apply(to: &navigator)
        #expect(toLast)
        #expect(navigator.position == 16)

        let toFirst = NavigationCommand.first.apply(to: &navigator)
        #expect(toFirst)
        #expect(navigator.position == 1)
    }

    @Test("Advancing on the last slide does nothing and says so")
    func advanceAtEnd() {
        // No wrap, no exit. Both would be surprising mid-talk, and the return
        // value is how a caller tells "did nothing" from "moved".
        var navigator = SlideNavigator(count: 3, position: 3)
        let advanced = NavigationCommand.next.apply(to: &navigator)
        #expect(!advanced)
        #expect(navigator.position == 3)
    }

    @Test("Retreating on the first slide does nothing and says so")
    func retreatAtStart() {
        var navigator = SlideNavigator(count: 3, position: 1)
        let retreated = NavigationCommand.previous.apply(to: &navigator)
        #expect(!retreated)
        #expect(navigator.position == 1)
    }

    @Test("A jump that changes nothing reports no movement")
    func redundantJump() {
        // Pressing Home twice should not claim to have moved the second time.
        var navigator = SlideNavigator(count: 5, position: 1)
        let moved = NavigationCommand.first.apply(to: &navigator)
        #expect(!moved)
        #expect(navigator.position == 1)
    }

    @Test("Every command is safe on an empty deck", arguments: NavigationCommand.allCases)
    func emptyDeck(command: NavigationCommand) {
        // An empty deck is legal — the app has one before a file is opened — so
        // no command may trap or move off zero.
        var navigator = SlideNavigator(count: 0)
        let moved = command.apply(to: &navigator)
        #expect(!moved)
        #expect(navigator.position == 0)
    }

    @Test("Every command has a menu title", arguments: NavigationCommand.allCases)
    func everyCommandIsPresentable(command: NavigationCommand) {
        // Driven by CaseIterable so adding a command without a title fails here
        // rather than shipping a blank menu item.
        #expect(!command.title.isEmpty)
    }

    @Test("Jumps are distinguished from steps")
    func jumpClassification() {
        // The caller resets zoom on a jump; getting this wrong lands you
        // magnified into the corner of a slide you have not seen.
        #expect(NavigationCommand.first.isJump)
        #expect(NavigationCommand.last.isJump)
        #expect(!NavigationCommand.next.isJump)
        #expect(!NavigationCommand.previous.isJump)
    }

    @Test("Walking the whole deck forwards then back lands where it started")
    func roundTrip() {
        var navigator = SlideNavigator(count: 16, position: 1)
        while NavigationCommand.next.apply(to: &navigator) {}
        #expect(navigator.position == 16)

        while NavigationCommand.previous.apply(to: &navigator) {}
        #expect(navigator.position == 1)
    }
}
