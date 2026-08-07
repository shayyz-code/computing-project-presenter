import CoreGraphics
import Foundation

/// How the two panes are arranged.
///
/// Lives here rather than in the view because every rule below has a way of
/// going wrong that is worth a test — a ratio that drifts past a usable width, a
/// collapsed pane that cannot be recovered, a swap that loses which side was
/// collapsed.
@MainActor
@Observable
public final class LayoutState {
    /// Fraction of the window given to the **deck**, before any collapse.
    public private(set) var deckFraction: CGFloat
    /// Whether the mirror sits on the right (the default) or the left.
    public private(set) var mirrorIsTrailing: Bool
    public private(set) var collapsed: CollapsedPane

    public nonisolated enum CollapsedPane: String, Codable, Sendable {
        case none
        case deck
        case mirror
    }

    /// The deck is the primary content, so it never drops below half.
    ///
    /// A presenter app whose deck is the smaller pane has its priorities
    /// inverted — the same reasoning that put a `maxWidth` on the mirror after
    /// `HSplitView` was found to hand the first pane its bare minimum.
    public nonisolated static let minimumDeckFraction: CGFloat = 0.5
    /// Past this the mirror is a sliver rather than a phone. Collapse it
    /// instead, which at least stops capture.
    public nonisolated static let maximumDeckFraction: CGFloat = 0.85
    public nonisolated static let defaultDeckFraction: CGFloat = 0.68

    public init(
        deckFraction: CGFloat = LayoutState.defaultDeckFraction,
        mirrorIsTrailing: Bool = true,
        collapsed: CollapsedPane = .none
    ) {
        self.deckFraction = Self.clamp(deckFraction)
        self.mirrorIsTrailing = mirrorIsTrailing
        self.collapsed = collapsed
    }

    public func setDeckFraction(_ fraction: CGFloat) {
        deckFraction = Self.clamp(fraction)
    }

    /// Swaps which side each pane is on.
    ///
    /// Swaps *content*, not labels: a presenter who moves the mirror to the left
    /// expects the mirror to be on the left, not a relabelled deck. The collapse
    /// state travels with the pane rather than with the side, so swapping while
    /// the mirror is collapsed leaves the mirror collapsed.
    public func swapSides() {
        mirrorIsTrailing.toggle()
    }

    public func toggleCollapse(_ pane: CollapsedPane) {
        guard pane != .none else { return }
        collapsed = collapsed == pane ? .none : pane
    }

    public func expandAll() {
        collapsed = .none
    }

    /// Whether the mirror is on screen at all.
    ///
    /// The pane uses this to stop capture when collapsed: a hidden mirror that
    /// keeps streaming leaves the macOS capture indicator lit, which reads as
    /// the app still watching your screen.
    public var showsMirror: Bool { collapsed != .mirror }
    public var showsDeck: Bool { collapsed != .deck }

    /// Deck width for a given total, accounting for collapse.
    public func deckWidth(forTotal total: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        switch collapsed {
        case .deck: return 0
        case .mirror: return total
        case .none: return total * deckFraction
        }
    }

    nonisolated static func clamp(_ fraction: CGFloat) -> CGFloat {
        guard fraction.isFinite else { return defaultDeckFraction }
        return min(max(fraction, minimumDeckFraction), maximumDeckFraction)
    }
}
