import Foundation

/// A single slide in a presentation.
///
/// `number` is the slide's position as the author sees it, counting from 1. It is
/// deliberately not the index of the file it came from: PPTX slide order lives in
/// `<p:sldIdLst>` in `ppt/presentation.xml`, not in `slide1.xml`, `slide2.xml`
/// filename order. See `docs/specs/0001-slide-rendering.md`.
public struct Slide: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let number: Int
    /// Speaker notes, if the slide has any. Resolved through the slide's own
    /// relationships part, because notes are not mapped positionally.
    public let notes: String?

    public init(id: UUID = UUID(), number: Int, notes: String? = nil) {
        self.id = id
        self.number = number
        self.notes = notes
    }
}

/// A loaded presentation, in author order.
public struct Deck: Equatable, Sendable {
    public let title: String
    public let slides: [Slide]
    /// The file the deck was loaded from.
    public let sourceURL: URL

    public init(title: String, slides: [Slide], sourceURL: URL) {
        self.title = title
        self.slides = slides
        self.sourceURL = sourceURL
    }

    public var count: Int { slides.count }

    /// Whether any slide carries notes.
    ///
    /// A PDF carries none at all, so a notes pane over one would be a
    /// permanently empty box — the failure spec 0003 forbids. Gating on the
    /// *deck* rather than the current slide also stops the pane flickering in
    /// and out while navigating a deck with sparse notes.
    public var hasNotes: Bool { slides.contains { $0.notes?.isEmpty == false } }
    public var isEmpty: Bool { slides.isEmpty }

    /// The slide at a 1-based position, or `nil` if out of range.
    public subscript(number number: Int) -> Slide? {
        slides.first { $0.number == number }
    }
}
