import Foundation
import Testing

@testable import SlideKit

/// Fixtures are hand-built by `Fixtures/make-fixtures.py` rather than exported
/// from Keynote or PowerPoint. A tool-exported deck has contiguous notes and
/// sequential slide ordering — precisely the shape that hides both bugs these
/// tests exist to catch.
private func fixture(_ name: String) throws -> URL {
    let url = Bundle.module.resourceURL?
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(name)
    guard let url, FileManager.default.fileExists(atPath: url.path) else {
        throw FixtureError.missing(name)
    }
    return url
}

private enum FixtureError: Error { case missing(String) }

@Suite("PPTXMetadata")
struct PPTXMetadataTests {

    // MARK: - Trap 1: slide order

    @Test("Slide order follows sldIdLst, not filename order")
    func ordering() throws {
        // shuffled-order.pptx lists slide3, slide1, slide2 in that order, and
        // each slide's notes record the author position it should land at. A
        // reader that sorts filenames produces 1, 2, 3 and fails here.
        let metadata = try PPTXMetadata.read(try fixture("shuffled-order.pptx"))

        #expect(metadata.slides.count == 3)
        #expect(metadata.slides.map(\.number) == [1, 2, 3])
        #expect(metadata.slides[0].notes == "author position 1")
        #expect(metadata.slides[1].notes == "author position 2")
        #expect(metadata.slides[2].notes == "author position 3")
    }

    // MARK: - Trap 2: notes are not positional

    @Test("Sparse notes land on the slides that own them")
    func sparseNotes() throws {
        // The criterion spec 0001 names verbatim: notes on 1, 3, 4 and none on
        // 2, 5. The fixture maps notesSlide2.xml to slide 3, so index-mapping
        // notes parts to slides puts slide 3's notes on slide 2 and fails.
        let metadata = try PPTXMetadata.read(try fixture("sparse-notes.pptx"))

        #expect(metadata.slides.count == 5)
        #expect(metadata.slides[0].notes == "Notes for slide 1")
        #expect(metadata.slides[1].notes == nil)
        #expect(metadata.slides[2].notes == "Notes for slide 3")
        #expect(metadata.slides[3].notes == "Notes for slide 4")
        #expect(metadata.slides[4].notes == nil)
    }

    @Test("Slides are addressable by author-facing number")
    func lookupByNumber() throws {
        let metadata = try PPTXMetadata.read(try fixture("sparse-notes.pptx"))
        let deck = metadata.deck(sourceURL: try fixture("sparse-notes.pptx"))

        #expect(deck[number: 3]?.notes == "Notes for slide 3")
        #expect(deck[number: 2]?.notes == nil)
        #expect(deck[number: 6] == nil)
    }

    // MARK: - Notes text

    @Test("Notes join their runs, and blank notes read as nil")
    func notesText() throws {
        let metadata = try PPTXMetadata.read(try fixture("multiline-notes.pptx"))

        #expect(metadata.slides[0].notes == "First line\nSecond line")
        // Whitespace-only notes are nil, so the UI has one "no notes" state
        // rather than two that look the same.
        #expect(metadata.slides[1].notes == nil)
    }

    // MARK: - Compression methods

    @Test("A STORED entry is read, not treated as deflate")
    func storedEntry() throws {
        // sparse-notes.pptx writes ppt/slides/slide3.xml uncompressed. A survey
        // of 61 real decks found 1219 stored entries, 82 of them .xml — an
        // inflate-only reader returns garbage for those and reports no error.
        let url = try fixture("sparse-notes.pptx")
        let archive = try ZipArchive(url: url)

        let slide = try archive.data(for: "ppt/slides/slide3.xml")
        #expect(slide != nil)
        let text = String(decoding: slide ?? Data(), as: UTF8.self)
        #expect(text.contains("<p:sld"))

        // And the deflated parts still work in the same archive.
        let presentation = try archive.data(for: "ppt/presentation.xml")
        #expect(presentation != nil)
        #expect(String(decoding: presentation ?? Data(), as: UTF8.self).contains("p:sldId"))
    }

    // MARK: - Failure paths

    @Test("An empty sldIdLst is emptyDeck, not a zero-slide success")
    func emptyDeck() throws {
        let url = try fixture("empty-deck.pptx")
        #expect(throws: DeckLoadingError.emptyDeck(url)) {
            try PPTXMetadata.read(url)
        }
    }

    @Test("A truncated file is unreadableFile, not a crash")
    func truncatedFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("truncated-\(UUID().uuidString).pptx")
        // Real zip magic, then nothing — the shape most likely to walk a reader
        // off the end of its buffer.
        try Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: DeckLoadingError.unreadableFile(url)) {
            try PPTXMetadata.read(url)
        }
    }

    @Test("A file that is not a zip at all is unreadableFile")
    func notAZip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("plain-\(UUID().uuidString).pptx")
        try Data("this is not a presentation".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: DeckLoadingError.unreadableFile(url)) {
            try PPTXMetadata.read(url)
        }
    }

    @Test("A missing file is unreadableFile")
    func missingFile() throws {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).pptx")
        #expect(throws: DeckLoadingError.unreadableFile(url)) {
            try PPTXMetadata.read(url)
        }
    }
}

/// The XML scanning is exercised directly as well as through the fixtures: these
/// are the shapes where a plausible-looking scanner quietly does the wrong thing.
@Suite("PPTXMetadata parsing")
struct PPTXMetadataParsingTests {

    @Test("sldIdLst is not mistaken for sldId")
    func elementNameBoundary() {
        // `<p:sldIdLst>` starts with `<p:sldId`. A prefix match picks up the
        // container and produces one phantom slide with no r:id.
        let xml = """
            <p:sldIdLst>
              <p:sldId id="256" r:id="rId2"/>
              <p:sldId id="257" r:id="rId3"/>
            </p:sldIdLst>
            """
        #expect(PPTXMetadata.slideRelationshipIDs(in: xml) == ["rId2", "rId3"])
    }

    @Test("Relationship targets resolve relative to the declaring part")
    func targetNormalisation() {
        #expect(
            PPTXMetadata.normalise("../notesSlides/notesSlide1.xml", base: "ppt/slides")
                == "ppt/notesSlides/notesSlide1.xml")
        #expect(PPTXMetadata.normalise("slides/slide1.xml", base: "ppt") == "ppt/slides/slide1.xml")
        // An absolute target is package-rooted, not filesystem-rooted.
        #expect(PPTXMetadata.normalise("/ppt/slides/slide1.xml", base: "ppt") == "ppt/slides/slide1.xml")
        #expect(PPTXMetadata.normalise("./slide1.xml", base: "ppt/slides") == "ppt/slides/slide1.xml")
    }

    @Test("Only a notesSlide relationship counts as notes")
    func notesTargetSelection() {
        let rels = """
            <Relationships>
              <Relationship Id="rId1" Target="../slideLayouts/slideLayout2.xml"/>
              <Relationship Id="rId2" Target="../notesSlides/notesSlide7.xml"/>
            </Relationships>
            """
        #expect(PPTXMetadata.notesTarget(in: rels) == "../notesSlides/notesSlide7.xml")

        let layoutOnly = """
            <Relationships>
              <Relationship Id="rId1" Target="../slideLayouts/slideLayout2.xml"/>
            </Relationships>
            """
        #expect(PPTXMetadata.notesTarget(in: layoutOnly) == nil)
    }

    @Test("Escaped characters in notes are decoded")
    func entityDecoding() {
        let xml = "<a:t>if a &lt; b &amp;&amp; c &gt; d</a:t>"
        #expect(PPTXMetadata.notesText(in: xml) == "if a < b && c > d")
    }

    @Test("Notes with no runs are nil")
    func noRuns() {
        #expect(PPTXMetadata.notesText(in: "<p:notes></p:notes>") == nil)
    }
}
