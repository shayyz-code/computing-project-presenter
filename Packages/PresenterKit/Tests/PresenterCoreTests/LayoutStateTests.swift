import CoreGraphics
import Foundation
import Testing

@testable import PresenterCore

@MainActor
@Suite("LayoutState")
struct LayoutStateTests {

    @Test("Starts with the deck dominant")
    func defaults() {
        let layout = LayoutState()
        #expect(layout.deckFraction == LayoutState.defaultDeckFraction)
        #expect(layout.mirrorIsTrailing)
        #expect(layout.collapsed == .none)
        #expect(layout.showsDeck && layout.showsMirror)
    }

    @Test("The deck never becomes the smaller pane")
    func fractionClampsLow() {
        // A presenter app whose deck is smaller than the mirror has its
        // priorities inverted — the same reasoning that capped the mirror's
        // width after HSplitView was found to starve the first pane.
        let layout = LayoutState()
        layout.setDeckFraction(0.1)
        #expect(layout.deckFraction == LayoutState.minimumDeckFraction)
    }

    @Test("The mirror never becomes a sliver")
    func fractionClampsHigh() {
        // Past the cap the mirror is too narrow to read as a phone. Collapsing
        // is the honest way to hide it, and it stops capture too.
        let layout = LayoutState()
        layout.setDeckFraction(0.99)
        #expect(layout.deckFraction == LayoutState.maximumDeckFraction)
    }

    @Test("A nonsense fraction falls back rather than corrupting the layout")
    func rejectsNonFinite() {
        // A NaN reaching a width makes every later comparison false and the
        // panes stop laying out at all.
        let layout = LayoutState(deckFraction: .nan)
        #expect(layout.deckFraction == LayoutState.defaultDeckFraction)

        layout.setDeckFraction(.infinity)
        #expect(layout.deckFraction.isFinite)
    }

    @Test("Swapping moves the mirror, and keeps the collapse with the pane")
    func swapSides() {
        // Content swaps, not labels: someone who moves the mirror left expects
        // the mirror on the left, not a relabelled deck. And a collapsed mirror
        // stays collapsed across a swap rather than reappearing on the far side.
        let layout = LayoutState()
        layout.toggleCollapse(.mirror)
        layout.swapSides()

        #expect(!layout.mirrorIsTrailing)
        #expect(layout.collapsed == .mirror)
        #expect(!layout.showsMirror)
    }

    @Test("Collapsing hides one pane and is reversible")
    func collapseToggles() {
        let layout = LayoutState()

        layout.toggleCollapse(.mirror)
        #expect(!layout.showsMirror)
        #expect(layout.showsDeck, "collapsing one pane must not hide the other")

        layout.toggleCollapse(.mirror)
        #expect(layout.showsMirror, "a collapse the user cannot undo is a trap")
    }

    @Test("Collapsing the other pane replaces rather than stacks")
    func collapseIsExclusive() {
        // Both collapsed at once would leave an empty window with no way back.
        let layout = LayoutState()
        layout.toggleCollapse(.mirror)
        layout.toggleCollapse(.deck)

        #expect(layout.collapsed == .deck)
        #expect(layout.showsMirror)
        #expect(!layout.showsDeck)
    }

    @Test("Collapsing the mirror is what tells the pane to stop capture")
    func collapseStopsCapture() {
        // A hidden mirror that keeps streaming leaves the macOS capture
        // indicator lit, which reads as the app still watching your screen.
        let layout = LayoutState()
        #expect(layout.showsMirror)
        layout.toggleCollapse(.mirror)
        #expect(!layout.showsMirror)
    }

    @Test("Widths account for collapse", arguments: [800.0, 1280.0, 2560.0])
    func widths(total: CGFloat) {
        let layout = LayoutState(deckFraction: 0.7)
        #expect(abs(layout.deckWidth(forTotal: total) - total * 0.7) < 0.01)

        layout.toggleCollapse(.mirror)
        #expect(layout.deckWidth(forTotal: total) == total, "the deck takes the window")

        layout.toggleCollapse(.deck)
        #expect(layout.deckWidth(forTotal: total) == 0)
    }

    @Test("A zero-width window yields zero rather than NaN")
    func degenerateWidth() {
        // A pane can be laid out at zero size for a frame during a resize.
        #expect(LayoutState().deckWidth(forTotal: 0) == 0)
    }
}

@Suite("Layout persistence")
struct LayoutPersistenceTests {

    @Test("Layout round-trips through a snapshot")
    func roundTrip() throws {
        let snapshot = SessionSnapshot(
            deckPath: "/tmp/a.pptx", deckFraction: 0.6, mirrorIsTrailing: false,
            collapsedPane: .mirror)
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(SessionSnapshot.self, from: data) == snapshot)
    }

    @Test("A snapshot written before layout existed still restores")
    func decodesOlderSnapshot() throws {
        // The upgrade path. Without tolerant decoding, adding a field would
        // discard every existing session — the deck and slide position someone
        // had open would silently vanish on first launch of the new build.
        let json = """
            {"deckPath":"/tmp/a.pptx","slidePosition":7,"showsNotes":false}
            """
        let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: Data(json.utf8))

        #expect(snapshot.deckPath == "/tmp/a.pptx")
        #expect(snapshot.slidePosition == 7)
        #expect(!snapshot.showsNotes)
        // And the new fields take their defaults rather than failing.
        #expect(snapshot.deckFraction == LayoutState.defaultDeckFraction)
        #expect(snapshot.mirrorIsTrailing)
        #expect(snapshot.collapsedPane == .none)
    }

    @Test("An empty snapshot still decodes")
    func decodesEmpty() throws {
        let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: Data("{}".utf8))
        #expect(snapshot.deckPath == nil)
        #expect(snapshot.slidePosition == 1)
    }
}
