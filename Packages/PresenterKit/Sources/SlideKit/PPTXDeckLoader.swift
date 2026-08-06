import CryptoKit
import Foundation

/// Opens a `.pptx` by converting it to PDF and reading its structure from the
/// original zip.
///
/// The split is deliberate and is what makes the result trustworthy: **pixels
/// come from the converted PDF, structure comes from the `.pptx` itself.**
/// Slide order and notes are read by `PPTXMetadata` from `<p:sldIdLst>` and the
/// per-slide rels, so neither depends on a converter getting them right.
public struct PPTXDeckLoader: DeckLoader {
    private let converters: [DeckConverter]
    private let cache: ConversionCache

    /// Chain order per ADR-0002: LibreOffice first because it honours fonts
    /// embedded in the `.pptx`, Keynote second because it needs no install.
    public init(
        converters: [DeckConverter] = [LibreOfficeConverter(), KeynoteConverter()],
        cache: ConversionCache = ConversionCache()
    ) {
        self.converters = converters
        self.cache = cache
    }

    public func canLoad(_ url: URL) async -> Bool {
        guard url.pathExtension.lowercased() == "pptx" else { return false }
        return converters.contains { $0.isAvailable() }
    }

    public func load(_ url: URL) async throws -> Deck {
        guard url.pathExtension.lowercased() == "pptx" else {
            throw DeckLoadingError.noLoaderAvailable(fileExtension: url.pathExtension)
        }

        // Structure first. It is cheap, it does not need a converter, and a file
        // that is not a readable package should fail before an app is launched.
        let metadata = try PPTXMetadata.read(url)

        let pdf = try await convertedPDF(for: url)

        // Cross-check. `<p:sldIdLst>` is the authoritative slide count, so a
        // converter that silently dropped slides — or stopped part way — is
        // caught here instead of presenting a short deck to an audience.
        let renderer = try PDFSlideRenderer(url: pdf)
        guard renderer.pageCount == metadata.slides.count else {
            throw DeckLoadingError.conversionFailed(
                loader: "PPTXDeckLoader",
                reason: """
                    converted to \(renderer.pageCount) pages but the deck declares \
                    \(metadata.slides.count) slides
                    """)
        }

        return metadata.deck(sourceURL: url)
    }

    /// The converted PDF for a deck, converting only if the cache misses.
    ///
    /// Public so a caller that needs the pixels — the app, building a
    /// `PDFSlideRenderer` — can reuse the same cached file rather than
    /// converting twice.
    public func convertedPDF(for url: URL) async throws -> URL {
        if let cached = try cache.cachedPDF(for: url) { return cached }

        let destination = try cache.destination(for: url)
        var failures: [String] = []

        for converter in converters where converter.isAvailable() {
            do {
                try await converter.convert(url, to: destination)
                return destination
            } catch {
                // Try the next backend rather than giving up: an unavailable or
                // broken converter should not sink an open that another can do.
                failures.append("\(converter.name): \(error)")
            }
        }

        if failures.isEmpty {
            // Nothing was installed. The error names every remedy, including the
            // one needing no install at all, per ADR-0002.
            throw DeckLoadingError.noLoaderAvailable(fileExtension: url.pathExtension)
        }
        throw DeckLoadingError.conversionFailed(
            loader: "PPTXDeckLoader", reason: failures.joined(separator: "; "))
    }
}

/// Converted PDFs, keyed by the content of the source deck.
///
/// Content-hashed rather than path-keyed so that reopening is instant and
/// *editing* the deck reconverts — a modification date would be fooled by a
/// touch, and a path alone would serve a stale render forever.
public struct ConversionCache: Sendable {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory =
            directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.codewithshayy.presenter/converted", isDirectory: true)
    }

    public func destination(for source: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(try key(for: source)).appendingPathExtension("pdf")
    }

    public func cachedPDF(for source: URL) throws -> URL? {
        let candidate = try destination(for: source)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// SHA-256 of the file's bytes. Read in chunks so a large deck does not have
    /// to be resident all at once.
    private func key(for source: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: source) else {
            throw DeckLoadingError.unreadableFile(source)
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
