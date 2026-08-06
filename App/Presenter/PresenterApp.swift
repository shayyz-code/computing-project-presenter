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
                Button("Show Speaker Notes") {
                    NotificationCenter.default.post(name: .toggleNotesRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }
}
