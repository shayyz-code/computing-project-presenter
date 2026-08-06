import Foundation

/// A movement through the deck, named once so the menu and the keyboard cannot
/// describe it differently.
///
/// Without this the mapping from input to action lives twice — once in the menu
/// and once in a view's `keyDown` — and two implementations that agree today
/// drift tomorrow.
///
/// The menu is the primary path, and not only for discoverability. Menu key
/// equivalents are dispatched by the **menu system rather than the focus
/// chain**, so navigation keeps working wherever the click landed. A view's
/// `keyDown` only fires when that view is first responder, which is why slide
/// navigation used to stop silently after clicking anything in the mirror pane.
public enum NavigationCommand: String, CaseIterable, Sendable {
    case next
    case previous
    case first
    case last

    /// Applies the command.
    ///
    /// - Returns: whether the position changed. `false` at a boundary, which is
    ///   what lets a caller distinguish "did nothing" from "moved" — advancing
    ///   off the last slide must not wrap and must not exit the presentation.
    @discardableResult
    public func apply(to navigator: inout SlideNavigator) -> Bool {
        let before = navigator.position
        switch self {
        case .next:
            return navigator.advance()
        case .previous:
            return navigator.retreat()
        case .first:
            navigator.jump(to: 1)
        case .last:
            navigator.jump(to: navigator.count)
        }
        return navigator.position != before
    }

    /// Menu title.
    public var title: String {
        switch self {
        case .next: "Next Slide"
        case .previous: "Previous Slide"
        case .first: "First Slide"
        case .last: "Last Slide"
        }
    }

    /// Whether this command moves to a different slide rather than stepping,
    /// so the caller knows to reset zoom rather than assume it.
    public var isJump: Bool {
        self == .first || self == .last
    }
}
