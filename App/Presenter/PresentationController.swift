import AppKit
import PresenterCore
import SwiftUI

/// Bridges AppKit's fullscreen and power-management APIs to `PresentationState`.
///
/// The AppKit half lives here rather than in the view so `PresentationState` stays
/// plain testable state — the visibility rule it enforces is the part with a
/// failure mode worth testing, and it should not need a window to exercise.
@MainActor
@Observable
final class PresentationController {
    let mode: PresentationState

    /// Held while presenting, to keep the display awake.
    ///
    /// Must be balanced exactly. An unbalanced `beginActivity` keeps the display
    /// awake for the whole process lifetime, which surfaces weeks later as "my
    /// laptop stopped sleeping" with nothing obvious to blame.
    private var sleepAssertion: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []
    /// The window to switch between translucent and opaque. Held weakly: the
    /// controller must not keep a closed window alive.
    private weak var window: NSWindow?

    init(showsNotesWindowed: Bool) {
        self.mode = PresentationState(showsNotesWindowed: showsNotesWindowed)
        observeFullscreenChanges()
    }

    /// Enters or leaves fullscreen.
    ///
    /// Only asks the window to toggle — the resulting state comes back through
    /// the notifications below, so every route into fullscreen behaves the same.
    func toggleFullscreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    func toggleNotes() {
        mode.toggleNotes()
    }

    /// Adopts the hosting window and applies the backdrop for the current mode.
    func adopt(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.setBackdropTranslucent(!mode.isFullscreen)
    }

    /// Observes the *window*, not our own menu item.
    ///
    /// Fullscreen can be entered from the menu, ⌃⌘F, the green button, or the
    /// Window menu. A flag this class set itself would be wrong for three of
    /// those — and being wrong here means notes stay on screen in fullscreen,
    /// which is the exposure the whole rule exists to prevent.
    private func observeFullscreenChanges() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.mode.didEnterFullscreen()
                    self?.beginPreventingDisplaySleep()
                    // Opaque while presenting, so the desktop cannot appear
                    // around the deck on a projector.
                    self?.window?.setBackdropTranslucent(false)
                }
            })
        observers.append(
            center.addObserver(
                forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.mode.didExitFullscreen()
                    self?.endPreventingDisplaySleep()
                    self?.window?.setBackdropTranslucent(true)
                }
            })
        // Closing the window while presenting is the other way out, and it must
        // release the assertion too. `deinit` cannot do this: it is nonisolated
        // and every field here is main-actor bound.
        observers.append(
            center.addObserver(
                forName: NSWindow.willCloseNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.endPreventingDisplaySleep() }
            })
    }

    private func beginPreventingDisplaySleep() {
        // Guarded so a repeated notification cannot leak a second assertion.
        guard sleepAssertion == nil else { return }
        sleepAssertion = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated],
            reason: "Presenting a deck")
    }

    private func endPreventingDisplaySleep() {
        guard let sleepAssertion else { return }
        ProcessInfo.processInfo.endActivity(sleepAssertion)
        self.sleepAssertion = nil
    }
}
