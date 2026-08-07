import CoreGraphics
import Foundation
import Testing

@testable import SlideKit

/// Writes a real PDF to a temporary file. Built in memory rather than committed
/// as a binary fixture, so a test states the page count it needs instead of
/// asserting against whatever a checked-in file happens to contain.
private func makePDF(pages: Int) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("deck-\(UUID().uuidString).pdf")
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
        throw TestError.couldNotBuild
    }
    var box = CGRect(x: 0, y: 0, width: 640, height: 360)
    guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
        throw TestError.couldNotBuild
    }
    for _ in 0..<pages {
        context.beginPDFPage(nil)
        context.setFillColor(gray: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        context.endPDFPage()
    }
    context.closePDF()
    try (data as Data).write(to: url)
    return url
}

private enum TestError: Error { case couldNotBuild }

/// Stands in for an installed converter, so format support is tested against a
/// stated fact rather than against whatever the machine happens to have.
private struct InstalledConverter: DeckConverter {
    let name = "Stub"
    func isAvailable() -> Bool { true }
    func convert(_ pptx: URL, to pdf: URL) async throws {}
}

@Suite("PDFDeckLoader")
struct PDFDeckLoaderTests {

    @Test("Builds a deck with one slide per page")
    func loadsPages() async throws {
        let url = try makePDF(pages: 5)
        defer { try? FileManager.default.removeItem(at: url) }

        let deck = try await PDFDeckLoader().load(url)
        #expect(deck.count == 5)
        #expect(deck.slides.map(\.number) == [1, 2, 3, 4, 5])
        #expect(deck.sourceURL == url)
    }

    @Test("A PDF has no speaker notes")
    func noNotes() async throws {
        // Not an omission: a PDF carries none, and the notes pane treats that as
        // "show nothing" rather than an empty box.
        let url = try makePDF(pages: 3)
        defer { try? FileManager.default.removeItem(at: url) }

        let deck = try await PDFDeckLoader().load(url)
        #expect(deck.slides.allSatisfy { $0.notes == nil })
    }

    @Test("Slides are addressable by author-facing number")
    func lookupByNumber() async throws {
        let url = try makePDF(pages: 4)
        defer { try? FileManager.default.removeItem(at: url) }

        let deck = try await PDFDeckLoader().load(url)
        #expect(deck[number: 1]?.number == 1)
        #expect(deck[number: 4]?.number == 4)
        #expect(deck[number: 5] == nil)
        #expect(deck[number: 0] == nil)
    }

    @Test("A corrupt file is unreadableFile, not a rendering error")
    func corruptFile() async throws {
        // Before this loader existed, a corrupt PDF surfaced
        // SlideRenderingError.renderFailed, which the UI had no case for and
        // printed as a raw enum instead of a remedy.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bad-\(UUID().uuidString).pdf")
        try Data("this is not a PDF".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: DeckLoadingError.unreadableFile(url)) {
            try await PDFDeckLoader().load(url)
        }
    }

    @Test("A missing file is unreadableFile")
    func missingFile() async throws {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).pdf")
        await #expect(throws: DeckLoadingError.unreadableFile(url)) {
            try await PDFDeckLoader().load(url)
        }
    }

    @Test("A zero-page PDF cannot be constructed, so it arrives as unreadable")
    func zeroPageIsUnreachable() async throws {
        // Recorded rather than faked. Two routes were tried:
        //
        //   1. CGContext with no beginPDFPage — CoreGraphics emits an implicit
        //      page, so the result has pageCount 1, not 0.
        //   2. A hand-written PDF whose page tree is `/Count 0` with no `/Kids`
        //      — PDFDocument(url:) returns nil for it.
        //
        // So `emptyDeck` is unreachable for PDFs and the file presents as
        // unreadable. The guard stays in the loader because "pageCount == 0
        // renders a blank pane" is the failure spec 0001 forbids, and that
        // should not rest on PDFKit continuing to behave this way.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zero-\(UUID().uuidString).pdf")
        let pdf = """
            %PDF-1.4
            1 0 obj
            << /Type /Catalog /Pages 2 0 R >>
            endobj
            2 0 obj
            << /Type /Pages /Kids [] /Count 0 >>
            endobj
            trailer
            << /Size 3 /Root 1 0 R >>
            %%EOF
            """
        try Data(pdf.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: DeckLoadingError.unreadableFile(url)) {
            try await PDFDeckLoader().load(url)
        }
    }

    @Test("canLoad accepts .pdf case-insensitively and rejects other formats")
    func canLoad() async {
        let loader = PDFDeckLoader()
        #expect(await loader.canLoad(URL(fileURLWithPath: "/tmp/a.pdf")))
        #expect(await loader.canLoad(URL(fileURLWithPath: "/tmp/a.PDF")))
        #expect(await !loader.canLoad(URL(fileURLWithPath: "/tmp/a.pptx")))
        #expect(await !loader.canLoad(URL(fileURLWithPath: "/tmp/a.key")))
    }

    @Test("Loading a non-PDF reports the format rather than mis-parsing it")
    func wrongFormat() async throws {
        let url = URL(fileURLWithPath: "/tmp/deck.key")
        await #expect(throws: DeckLoadingError.noLoaderAvailable(fileExtension: "key")) {
            try await PDFDeckLoader().load(url)
        }
    }
}

@Suite("DeckOpener")
struct DeckOpenerTests {

    @Test("Opens a PDF, using the file itself for rendering")
    func opensPDF() async throws {
        let url = try makePDF(pages: 3)
        defer { try? FileManager.default.removeItem(at: url) }

        let opened = try await DeckOpener().open(url)
        #expect(opened.deck.count == 3)
        // A PDF is its own renderable; nothing is converted.
        #expect(opened.renderableURL == url)
    }

    @Test("Reports an unsupported format rather than guessing")
    func unsupportedFormat() async throws {
        let url = URL(fileURLWithPath: "/tmp/deck.key")
        #expect(await !DeckOpener().canOpen(url))
        await #expect(throws: DeckLoadingError.noLoaderAvailable(fileExtension: "key")) {
            try await DeckOpener().open(url)
        }
    }

    @Test("Recognises both supported formats")
    func recognisesFormats() async {
        let opener = DeckOpener()
        // A .pdf needs nothing installed, so this holds everywhere.
        #expect(await opener.canOpen(URL(fileURLWithPath: "/tmp/a.pdf")))
        #expect(await !opener.canOpen(URL(fileURLWithPath: "/tmp/a.txt")))

        // A .pptx is only openable when a converter exists, so a converter is
        // injected rather than assumed. This test previously asserted `true`
        // against the ambient machine and passed locally while failing on CI,
        // where neither LibreOffice nor Keynote is installed — the code was
        // right and the test was measuring the developer's laptop.
        let withConverter = DeckOpener(
            pptx: PPTXDeckLoader(converters: [InstalledConverter()]))
        #expect(await withConverter.canOpen(URL(fileURLWithPath: "/tmp/a.pptx")))
    }

    @Test("Without a converter, a .pptx is honestly unopenable")
    func pptxNeedsAConverter() async {
        // The behaviour CI exposed, asserted deliberately: with nothing
        // installed the answer is no, which is what drives the error naming
        // install-LibreOffice, use-Keynote, or export-to-PDF.
        let bare = DeckOpener(pptx: PPTXDeckLoader(converters: []))
        #expect(await !bare.canOpen(URL(fileURLWithPath: "/tmp/a.pptx")))
    }

    @Test("A corrupt PDF surfaces as a deck error, not a rendering one")
    func corruptThroughOpener() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bad-\(UUID().uuidString).pdf")
        try Data("nope".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: DeckLoadingError.self) {
            try await DeckOpener().open(url)
        }
    }
}
