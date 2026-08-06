import Testing

@testable import PresenterCore

@MainActor
@Suite("PresentationState")
struct PresentationStateTests {

    @Test("Starts windowed, honouring the stored preference")
    func initialState() {
        #expect(PresentationState(showsNotesWindowed: true).showsNotes)
        #expect(!PresentationState(showsNotesWindowed: false).showsNotes)
        #expect(!PresentationState().isFullscreen)
    }

    @Test("Entering fullscreen hides notes even with the preference on")
    func fullscreenHidesNotes() {
        // The core rule. On one display the projector shows whatever is on
        // screen, so presenting must not carry the windowed preference in.
        let mode = PresentationState(showsNotesWindowed: true)
        mode.didEnterFullscreen()

        #expect(mode.isFullscreen)
        #expect(!mode.showsNotes)
    }

    @Test("Notes can be revealed during a presentation")
    func canRevealInFullscreen() {
        // For the laptop-only case, where there is no audience display.
        let mode = PresentationState(showsNotesWindowed: false)
        mode.didEnterFullscreen()
        mode.toggleNotes()
        #expect(mode.showsNotes)
    }

    @Test("The safe default reasserts on every entry")
    func defaultReassertsOnReentry() {
        // The failure this prevents: notes revealed in one session, then a
        // later presentation starts with your script in front of a room.
        let mode = PresentationState(showsNotesWindowed: true)

        mode.didEnterFullscreen()
        mode.toggleNotes()
        #expect(mode.showsNotes, "precondition: revealed")

        mode.didExitFullscreen()
        mode.didEnterFullscreen()
        #expect(!mode.showsNotes, "re-entering must hide notes again")
    }

    @Test("Toggling in fullscreen leaves the windowed preference untouched")
    func fullscreenToggleDoesNotClobberPreference() {
        let mode = PresentationState(showsNotesWindowed: true)
        mode.didEnterFullscreen()
        mode.toggleNotes()  // hide, then reveal, then hide again
        mode.toggleNotes()
        mode.toggleNotes()

        mode.didExitFullscreen()
        #expect(mode.showsNotesWindowed, "the windowed preference is not a presentation setting")
        #expect(mode.showsNotes)
    }

    @Test("Toggling while windowed does not leak into the next presentation")
    func windowedToggleDoesNotLeak() {
        let mode = PresentationState(showsNotesWindowed: false)
        mode.toggleNotes()
        #expect(mode.showsNotes, "precondition: shown while windowed")

        mode.didEnterFullscreen()
        #expect(!mode.showsNotes)
    }

    @Test("Exiting restores whatever the windowed preference was")
    func exitRestoresWindowedState() {
        for preference in [true, false] {
            let mode = PresentationState(showsNotesWindowed: preference)
            mode.didEnterFullscreen()
            mode.didExitFullscreen()
            #expect(mode.showsNotes == preference)
        }
    }

    @Test("Repeated notifications do not corrupt the state")
    func repeatedNotifications() {
        // AppKit can deliver these more than once, and a window observer may be
        // attached twice across a scene rebuild. Neither may flip anything.
        let mode = PresentationState(showsNotesWindowed: true)
        mode.didEnterFullscreen()
        mode.toggleNotes()
        mode.didEnterFullscreen()  // again
        #expect(!mode.showsNotes, "a repeated entry re-applies the safe default")

        mode.didExitFullscreen()
        mode.didExitFullscreen()
        #expect(!mode.isFullscreen)
        #expect(mode.showsNotes)
    }
}
