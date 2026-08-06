import AppKit
import PresenterCore

/// Catches the navigation keys that are not menu shortcuts.
///
/// The Navigate menu carries one shortcut per command — → ← Home End — which is
/// what makes them discoverable and accessible. But a presenter also expects
/// **space** and **page up/down** to work, and a presenter remote is a keyboard
/// that sends exactly page up/down. Giving "Next Slide" three menu entries to
/// cover its aliases would be worse than this.
///
/// A local `NSEvent` monitor rather than a view's `keyDown`: the monitor sees
/// events before the focus chain, so navigation works wherever the last click
/// landed. That focus dependence is the defect this file exists to remove —
/// clicking anything in the mirror pane used to silently stop the arrow keys.
///
/// Everything routes through `NavigationCommand`, so the menu and these aliases
/// cannot drift into two behaviours.
@MainActor
final class KeyboardNavigation {
    private var monitor: Any?
    private let onCommand: (NavigationCommand) -> Void

    init(onCommand: @escaping (NavigationCommand) -> Void) {
        self.onCommand = onCommand
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let command = Self.command(for: event) else { return event }
            self.onCommand(command)
            // Swallow it, or the key also reaches whatever has focus — space
            // would scroll the notes while advancing the slide.
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Maps an event to a command, or `nil` to let it through.
    private static func command(for event: NSEvent) -> NavigationCommand? {
        // Never swallow a shortcut. ⌘← is "back" elsewhere and ⌃⌘F is
        // fullscreen; treating those as navigation would break both.
        let modifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(modifiers).isEmpty else { return nil }

        switch event.keyCode {
        case 49: return .next  // space — the universal presenter convention
        case 121: return .next  // page down, which is what a remote sends
        case 116: return .previous  // page up
        case 125: return .next  // down arrow
        case 126: return .previous  // up arrow
        default: return nil
        }
    }
}
