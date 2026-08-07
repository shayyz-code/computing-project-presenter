import Foundation
import Testing

@testable import SlideKit

@Suite("Deck")
struct DeckTests {
    private func makeDeck(numbers: [Int]) -> Deck {
        Deck(
            title: "Fixture",
            slides: numbers.map { Slide(number: $0) },
            sourceURL: URL(fileURLWithPath: "/tmp/fixture.pdf")
        )
    }

    @Test("Looks slides up by author-facing number, not array offset")
    func subscriptUsesSlideNumber() {
        // Numbers deliberately do not start at 1 or run contiguously: PPTX slide
        // order comes from p:sldIdLst, so a Deck must never assume offset == number.
        let deck = makeDeck(numbers: [3, 7, 11])

        #expect(deck[number: 3]?.number == 3)
        #expect(deck[number: 7]?.number == 7)
        #expect(deck[number: 11]?.number == 11)
        #expect(deck[number: 1] == nil)
        #expect(deck[number: 2] == nil)
    }

    @Test("Reports count and emptiness")
    func countAndEmptiness() {
        #expect(makeDeck(numbers: []).isEmpty)
        #expect(makeDeck(numbers: []).count == 0)
        #expect(makeDeck(numbers: [1, 2]).count == 2)
        #expect(!makeDeck(numbers: [1, 2]).isEmpty)
    }

    @Test("Carries notes only for slides that have them")
    func sparseNotes() {
        // The M1 fixture case: some slides annotated, others bare.
        let deck = Deck(
            title: "Sparse",
            slides: [
                Slide(number: 1, notes: "opening"),
                Slide(number: 2),
                Slide(number: 3, notes: "demo here"),
            ],
            sourceURL: URL(fileURLWithPath: "/tmp/sparse.pptx")
        )

        #expect(deck[number: 1]?.notes == "opening")
        #expect(deck[number: 2]?.notes == nil)
        #expect(deck[number: 3]?.notes == "demo here")
    }

    @Test("hasNotes distinguishes a deck with notes from one without")
    func hasNotes() {
        // A PDF carries none, and a notes pane over one would be a permanently
        // empty box. Gating on the deck rather than the current slide also stops
        // the pane flickering while navigating a deck with sparse notes.
        let withNotes = Deck(
            title: "d",
            slides: [Slide(number: 1), Slide(number: 2, notes: "something")],
            sourceURL: URL(fileURLWithPath: "/tmp/d.pptx"))
        #expect(withNotes.hasNotes)

        let without = Deck(
            title: "d", slides: [Slide(number: 1), Slide(number: 2)],
            sourceURL: URL(fileURLWithPath: "/tmp/d.pdf"))
        #expect(!without.hasNotes)

        // Whitespace-only notes are normalised to nil upstream, but an empty
        // string must not count either.
        let empty = Deck(
            title: "d", slides: [Slide(number: 1, notes: "")],
            sourceURL: URL(fileURLWithPath: "/tmp/d.pdf"))
        #expect(!empty.hasNotes)
    }
}
