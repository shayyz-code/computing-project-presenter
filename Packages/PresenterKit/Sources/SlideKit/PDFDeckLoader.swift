import Foundation
import PDFKit

/// Opens a `.pdf` as a deck.
///
/// The always-works path: no converter, no external application, nothing to
/// install. It is also the only loader fully exercisable in CI, which is why
/// ADR-0002 makes PDF the primary format rather than a fallback.
public struct PDFDeckLoader: DeckLoader {

    public init() {}

    public func canLoad(_ url: URL) async -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    public func load(_ url: URL) async throws -> Deck {
        guard url.pathExtension.lowercased() == "pdf" else {
            throw DeckLoadingError.noLoaderAvailable(fileExtension: url.pathExtension)
        }
        guard let document = PDFDocument(url: url) else {
            throw DeckLoadingError.unreadableFile(url)
        }

        // Defensive rather than reachable. PDFKit refuses to open a PDF whose
        // page tree is empty — verified by hand-writing one with `/Count 0` and
        // no `/Kids`, which `PDFDocument(url:)` returns nil for — so a zero-page
        // file arrives as `unreadableFile` above. The guard stays because
        // "pageCount == 0 renders a blank pane" is the failure spec 0001
        // forbids, and it should not depend on PDFKit continuing to behave this
        // way.
        guard document.pageCount > 0 else {
            throw DeckLoadingError.emptyDeck(url)
        }

        // A PDF carries no speaker notes, so every slide has none. The notes
        // pane already treats that as "show nothing" rather than an empty box.
        let slides = (1...document.pageCount).map { Slide(number: $0, notes: nil) }
        return Deck(
            title: url.deletingPathExtension().lastPathComponent,
            slides: slides,
            sourceURL: url)
    }
}

/// A deck ready to present: its structure, and a file that can be rendered.
///
/// The two are not always the same file. A `.pptx` is read for structure and
/// converted for pixels; a `.pdf` is both. Carrying them together is what lets
/// callers stop caring which they were given.
public struct OpenedDeck: Sendable {
    public let deck: Deck
    /// The PDF to render from — the source file itself for a `.pdf`, the
    /// converted output for a `.pptx`.
    public let renderableURL: URL

    public init(deck: Deck, renderableURL: URL) {
        self.deck = deck
        self.renderableURL = renderableURL
    }
}

/// One entry point for opening any supported deck.
///
/// Before this, callers branched on the file extension themselves and the two
/// paths drifted: `.pptx` went through a loader and reported `emptyDeck` and
/// `unreadableFile` properly, while `.pdf` skipped the loader entirely — so a
/// corrupt PDF surfaced a raw rendering error and a page-less one drew a blank
/// pane with no explanation at all.
public struct DeckOpener: Sendable {
    private let pdf: PDFDeckLoader
    private let pptx: PPTXDeckLoader

    public init(pdf: PDFDeckLoader = PDFDeckLoader(), pptx: PPTXDeckLoader = PPTXDeckLoader()) {
        self.pdf = pdf
        self.pptx = pptx
    }

    /// Whether anything here can open this file at all.
    public func canOpen(_ url: URL) async -> Bool {
        // Not `||`: the short-circuit operand is an autoclosure, which cannot
        // carry an async call.
        if await pdf.canLoad(url) { return true }
        return await pptx.canLoad(url)
    }

    public func open(_ url: URL) async throws -> OpenedDeck {
        if await pdf.canLoad(url) {
            return OpenedDeck(deck: try await pdf.load(url), renderableURL: url)
        }
        if await pptx.canLoad(url) {
            // Structure from the .pptx itself, pixels from the conversion. The
            // page-count cross-check lives in the loader, so a converter that
            // silently dropped slides is caught before this returns.
            return OpenedDeck(
                deck: try await pptx.load(url),
                renderableURL: try await pptx.convertedPDF(for: url))
        }
        throw DeckLoadingError.noLoaderAvailable(fileExtension: url.pathExtension)
    }
}
