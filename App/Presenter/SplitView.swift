import PresenterCore
import SwiftUI

/// Two panes and a draggable divider.
///
/// Replaces `HSplitView`, which exposes no way to read or set its ratio — so a
/// persisted layout was impossible with it, and it does not divide
/// proportionally either: it hands the first pane its minimum and gives
/// everything else to the second, which is why the deck used to end up the
/// smallest thing on screen.
///
/// Widths come from `LayoutState`, so the clamping and collapse rules are tested
/// in `PresenterCore` rather than living in a view.
struct SplitView<Deck: View, Mirror: View>: View {
    let layout: LayoutState
    @ViewBuilder var deck: Deck
    @ViewBuilder var mirror: Mirror

    /// Wide enough to grab without hunting, narrow enough not to read as a gap.
    private static var dividerWidth: CGFloat { 8 }

    var body: some View {
        GeometryReader { geometry in
            let total = geometry.size.width
            let deckWidth = layout.deckWidth(forTotal: total - Self.dividerWidth)

            HStack(spacing: 0) {
                if layout.mirrorIsTrailing {
                    deckPane(width: deckWidth)
                    divider(total: total)
                    mirrorPane()
                } else {
                    mirrorPane()
                    divider(total: total)
                    deckPane(width: deckWidth)
                }
            }
        }
    }

    @ViewBuilder
    private func deckPane(width: CGFloat) -> some View {
        if layout.showsDeck {
            deck.frame(width: layout.showsMirror ? width : nil)
                .frame(maxWidth: layout.showsMirror ? nil : .infinity)
        }
    }

    @ViewBuilder
    private func mirrorPane() -> some View {
        if layout.showsMirror {
            mirror.frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func divider(total: CGFloat) -> some View {
        // No divider when one pane is collapsed: dragging it would resize a pane
        // that is not visible, which is a control that appears to do nothing.
        if layout.showsDeck, layout.showsMirror {
            Rectangle()
                .fill(.separator)
                .frame(width: Self.dividerWidth)
                .contentShape(.rect)
                .onHover { inside in
                    // The cursor is the only affordance a plain divider has.
                    if inside {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(coordinateSpace: .global)
                        .onChanged { value in
                            guard total > 0 else { return }
                            // Derived from the pointer's absolute position
                            // rather than accumulated deltas: accumulating
                            // drifts away from the cursor once the clamp starts
                            // rejecting movement, so the divider stops tracking
                            // the hand holding it.
                            let x = value.location.x - (NSApp.keyWindow?.frame.minX ?? 0)
                            let fraction =
                                layout.mirrorIsTrailing ? x / total : (total - x) / total
                            layout.setDeckFraction(fraction)
                        }
                )
        }
    }
}
