import Foundation

/// Whether the app is presenting, and what the audience is allowed to see.
///
/// Named `PresentationState` rather than `PresentationMode` because SwiftUI
/// already exports a `PresentationMode` — the legacy `presentationMode`
/// environment binding — and the collision makes every use site in a SwiftUI
/// file ambiguous. Renaming beats qualifying it everywhere.
///
/// The rule this exists for: **on a single display, whatever is on screen is
/// what a projector mirrors.** So speaker notes and the elapsed timer are hidden
/// in fullscreen by default, per `docs/specs/0003-presenter-shell.md`.
///
/// It lives here rather than in the view because the failure mode is real and
/// asymmetric — showing your script to a room is embarrassing and irreversible,
/// where a missing note costs one keystroke — and a rule like that deserves
/// tests rather than a hope.
@MainActor
@Observable
public final class PresentationState {
    public private(set) var isFullscreen = false

    /// The windowed preference. Persisted by the app; never changed by entering
    /// or leaving fullscreen, so a presentation cannot quietly rewrite it.
    public var showsNotesWindowed: Bool

    /// Whether notes were explicitly revealed during *this* fullscreen session.
    ///
    /// Reset on every entry rather than remembered. A preference left on last
    /// week must not put notes in front of an audience today, so the safe
    /// default reasserts each time instead of persisting.
    public private(set) var showsNotesInFullscreen = false

    public init(showsNotesWindowed: Bool = true) {
        self.showsNotesWindowed = showsNotesWindowed
    }

    /// Whether the notes pane should be on screen right now.
    public var showsNotes: Bool {
        isFullscreen ? showsNotesInFullscreen : showsNotesWindowed
    }

    /// Called from `NSWindow.didEnterFullScreenNotification`.
    ///
    /// Driven by the window rather than by the menu item on purpose: fullscreen
    /// can be entered from the menu, ⌃⌘F, the green button or the Window menu,
    /// and a flag this type set itself would be wrong for three of them —
    /// leaving notes on screen exactly when they must not be.
    public func didEnterFullscreen() {
        isFullscreen = true
        showsNotesInFullscreen = false
    }

    public func didExitFullscreen() {
        isFullscreen = false
    }

    /// Toggles notes for whichever mode is active, leaving the other alone.
    public func toggleNotes() {
        if isFullscreen {
            showsNotesInFullscreen.toggle()
        } else {
            showsNotesWindowed.toggle()
        }
    }
}
