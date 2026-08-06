import Foundation

/// Reads slide order and speaker notes out of a `.pptx`.
///
/// This is structure only — it says which slides exist, in which order, and what
/// notes belong to each. Rendering is a separate concern: the pixels come from a
/// converted PDF (ADR-0002), and nothing here depends on that having happened.
///
/// Two rules in here are easy to get wrong in a way that *looks* correct, which
/// is why each is spelled out at the point it applies. Both are specified in
/// `docs/specs/0001-slide-rendering.md`.
public struct PPTXMetadata {
    public let title: String
    public let slides: [Slide]

    /// Reads structure from a `.pptx` on disk.
    ///
    /// - Throws: `DeckLoadingError.unreadableFile` if the file is not a readable
    ///   OOXML package, `DeckLoadingError.emptyDeck` if it contains no slides.
    public static func read(_ url: URL) throws -> PPTXMetadata {
        let archive: ZipArchive
        do {
            archive = try ZipArchive(url: url)
        } catch {
            throw DeckLoadingError.unreadableFile(url)
        }

        guard let presentationData = try? archive.data(for: "ppt/presentation.xml"),
            let presentation = String(data: presentationData, encoding: .utf8)
        else {
            throw DeckLoadingError.unreadableFile(url)
        }

        // TRAP 1: order comes from <p:sldIdLst>, not from sorting slide1.xml,
        // slide2.xml, … A deck whose slides were reordered after creation still
        // has ascending filenames, so the filename shortcut renders a wrong deck
        // that looks entirely fine.
        let relationshipIDs = slideRelationshipIDs(in: presentation)
        guard !relationshipIDs.isEmpty else { throw DeckLoadingError.emptyDeck(url) }

        let relationships =
            (try? archive.data(for: "ppt/_rels/presentation.xml.rels"))
            .flatMap { $0 }
            .flatMap { String(data: $0, encoding: .utf8) }
            .map(targetsByRelationshipID) ?? [:]

        var slides: [Slide] = []
        // Author-facing numbering: position in sldIdLst order, counting from 1.
        // `Deck.subscript(number:)` looks slides up by this, never by array index.
        for (index, relationshipID) in relationshipIDs.enumerated() {
            guard let target = relationships[relationshipID] else { continue }
            let slidePath = normalise(target, base: "ppt")
            slides.append(
                Slide(
                    number: index + 1,
                    notes: notes(forSlideAt: slidePath, in: archive)
                )
            )
        }

        guard !slides.isEmpty else { throw DeckLoadingError.emptyDeck(url) }

        return PPTXMetadata(
            title: url.deletingPathExtension().lastPathComponent,
            slides: slides
        )
    }

    /// A `Deck` over the same structure, for callers that have a renderable file.
    public func deck(sourceURL: URL) -> Deck {
        Deck(title: title, slides: slides, sourceURL: sourceURL)
    }

    // MARK: - Notes

    /// TRAP 2: notes are not positional. `notesSlide1.xml` belongs to slide 1
    /// only when every slide before it also has notes — and sparse notes are the
    /// normal case, not an edge case. In one real 53-slide lecture deck only 9
    /// slides carried notes, and `notesSlide3.xml` belonged to **slide 9**.
    /// Index-mapping would put slide 9's notes on slide 3: wrong, and plausible
    /// enough to ship.
    ///
    /// So resolve through the slide's *own* relationships part every time.
    private static func notes(forSlideAt slidePath: String, in archive: ZipArchive) -> String? {
        let name = (slidePath as NSString).lastPathComponent
        let directory = (slidePath as NSString).deletingLastPathComponent
        let relationshipPath = "\(directory)/_rels/\(name).rels"

        guard let relationshipData = try? archive.data(for: relationshipPath),
            let relationships = String(data: relationshipData, encoding: .utf8),
            let target = notesTarget(in: relationships)
        else {
            // No notes relationship is the common case, not a failure.
            return nil
        }

        let notesPath = normalise(target, base: directory)
        guard let notesData = try? archive.data(for: notesPath),
            let notes = String(data: notesData, encoding: .utf8)
        else {
            return nil
        }

        return notesText(in: notes)
    }

    // MARK: - XML scanning
    //
    // Scanning specific attributes rather than modelling the document. These
    // files are machine-generated and the shapes needed are narrow and stable;
    // a full XML model would be more code for no more correctness here.

    /// `r:id` values from `<p:sldId .../>` elements, **in document order**.
    static func slideRelationshipIDs(in xml: String) -> [String] {
        elements(named: "p:sldId", in: xml).compactMap { attribute("r:id", in: $0) }
    }

    /// `Id` → `Target` for every `<Relationship>` in a rels part.
    static func targetsByRelationshipID(_ xml: String) -> [String: String] {
        var result: [String: String] = [:]
        for element in elements(named: "Relationship", in: xml) {
            if let id = attribute("Id", in: element), let target = attribute("Target", in: element) {
                result[id] = target
            }
        }
        return result
    }

    /// The `Target` of the first relationship pointing at a notes slide.
    static func notesTarget(in xml: String) -> String? {
        for element in elements(named: "Relationship", in: xml) {
            guard let target = attribute("Target", in: element) else { continue }
            // Match on the target rather than the relationship Type URI: the
            // Type is long and namespace-versioned, the target is not.
            if target.contains("notesSlide") { return target }
        }
        return nil
    }

    /// Visible text of a notes part: `<a:t>` run contents, one line per run.
    ///
    /// Returns `nil` rather than `""` when there is nothing to show, so the UI
    /// has one "no notes" state instead of two that look identical.
    static func notesText(in xml: String) -> String? {
        var lines: [String] = []
        var remainder = Substring(xml)

        while let open = remainder.range(of: "<a:t>"),
            let close = remainder.range(of: "</a:t>", range: open.upperBound..<remainder.endIndex)
        {
            let line = remainder[open.upperBound..<close.lowerBound]
            lines.append(decodeEntities(String(line)))
            remainder = remainder[close.upperBound...]
        }

        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// The five predefined XML entities. Numeric character references are left
    /// alone deliberately — they are rare in notes and mis-decoding them would be
    /// worse than showing them.
    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return
            text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            // Ampersand last: doing it first would corrupt the others.
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Whole start-tags named `name`, in document order.
    private static func elements(named name: String, in xml: String) -> [Substring] {
        var result: [Substring] = []
        var remainder = Substring(xml)
        let opening = "<\(name)"

        while let start = remainder.range(of: opening) {
            // Guard against `<p:sldIdLst` matching a search for `<p:sldId`.
            let afterName = start.upperBound
            if afterName < remainder.endIndex {
                let next = remainder[afterName]
                guard
                    next == " " || next == ">" || next == "/" || next == "\n" || next == "\r"
                        || next == "\t"
                else {
                    remainder = remainder[afterName...]
                    continue
                }
            }
            guard
                let end = remainder.range(
                    of: ">", range: start.upperBound..<remainder.endIndex)
            else { break }
            result.append(remainder[start.lowerBound..<end.upperBound])
            remainder = remainder[end.upperBound...]
        }

        return result
    }

    /// A double-quoted attribute value from within a single start-tag.
    private static func attribute(_ name: String, in element: Substring) -> String? {
        guard let nameRange = element.range(of: "\(name)=\"") else { return nil }
        guard
            let closing = element.range(
                of: "\"", range: nameRange.upperBound..<element.endIndex)
        else { return nil }
        return String(element[nameRange.upperBound..<closing.lowerBound])
    }

    /// Resolves a relationship target to a package path.
    ///
    /// Targets are relative to the part that declared them, so
    /// `../notesSlides/notesSlide1.xml` from `ppt/slides` is
    /// `ppt/notesSlides/notesSlide1.xml`.
    static func normalise(_ target: String, base: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }

        var components = base.split(separator: "/").map(String.init)
        for component in target.split(separator: "/").map(String.init) {
            switch component {
            case "..": if !components.isEmpty { components.removeLast() }
            case ".", "": continue
            default: components.append(component)
            }
        }
        return components.joined(separator: "/")
    }
}
