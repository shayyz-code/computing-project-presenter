import PresenterCore
import SwiftUI

@main
struct SidecarApp: App {
    /// Navigation requests reach the window through a notification rather than
    /// shared state, matching how Open Deck and the presentation commands
    /// already work.
    private func post(_ command: NavigationCommand) {
        NotificationCenter.default.post(
            name: .navigateRequested, object: nil, userInfo: ["command": command.rawValue])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1280, height: 760)
        .commands {
            // Replaces the default New Item group, which a presenter app has no
            // use for, with the one command it does need.
            CommandGroup(replacing: .newItem) {
                Button("Open Deck…") {
                    NotificationCenter.default.post(name: .openDeckRequested, object: nil)
                }
                .keyboardShortcut("o")
            }
            CommandGroup(after: .toolbar) {
                // Discoverable rather than gesture-only. ⌃⌘F is the system
                // fullscreen shortcut, so this reinforces the habit instead of
                // competing with it.
                Button("Enter Presentation Mode") {
                    NotificationCenter.default.post(name: .togglePresentationRequested, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.control, .command])

                Button("Show Speaker Notes") {
                    NotificationCenter.default.post(name: .toggleNotesRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            // Navigation lives in the menu, not only in the slide view.
            //
            // Menu key equivalents are dispatched by the menu system rather than
            // the focus chain, so these keep working wherever the last click
            // landed. A view's keyDown only fires while that view is first
            // responder, which is why navigation used to stop silently after
            // clicking anything in the mirror pane.
            //
            // The shortcuts are unmodified, so they are captured app-wide. There
            // are no text fields today — notes are read-only — and space-advances
            // is the universal presenter convention, so this is the right trade.
            // Whoever adds a text field will need to revisit it.
            CommandGroup(after: .sidebar) {
                Button("Swap Sides") {
                    NotificationCenter.default.post(name: .swapSidesRequested, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])

                Button("Collapse Mirror") {
                    NotificationCenter.default.post(name: .collapseMirrorRequested, object: nil)
                }
                .keyboardShortcut("m", modifiers: [.command, .control])

                Button("Collapse Slides") {
                    NotificationCenter.default.post(name: .collapseDeckRequested, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .control])
            }

            CommandMenu("Navigate") {
                Button(NavigationCommand.next.title) { post(.next) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button(NavigationCommand.previous.title) { post(.previous) }
                    .keyboardShortcut(.leftArrow, modifiers: [])

                Divider()

                Button(NavigationCommand.first.title) { post(.first) }
                    .keyboardShortcut(.home, modifiers: [])
                Button(NavigationCommand.last.title) { post(.last) }
                    .keyboardShortcut(.end, modifiers: [])
            }
        }
    }
}
