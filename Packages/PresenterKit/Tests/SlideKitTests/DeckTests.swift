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
}
