import SwiftUI

@main
struct PresenterApp: App {
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
        }
    }
}
