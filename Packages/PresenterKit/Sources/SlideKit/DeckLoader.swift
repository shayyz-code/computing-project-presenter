import Foundation

/// Something that can turn a file on disk into a `Deck`.
///
/// Two conformances, tried in the order described by ADR-0002: PDF passthrough
/// (always available) and LibreOffice (for `.pptx`, when installed). A Keynote
/// backend was the third and was removed in #79 — the distribution decision it
/// depended on had changed, and it could not import every valid `.pptx`.
public protocol DeckLoader: Sendable {
    /// Whether this loader can handle the file, accounting for whatever external
    /// tool it needs actually being present on this machine.
    func canLoad(_ url: URL) async -> Bool

    func load(_ url: URL) async throws -> Deck
}

/// Why a deck could not be opened. Every case carries enough detail for the UI to
/// offer a real remedy rather than a dead end.
public enum DeckLoadingError: Error, Equatable, Sendable {
    /// No loader on this machine can handle the file.
    case noLoaderAvailable(fileExtension: String)
    /// A converter exists but failed.
    case conversionFailed(loader: String, reason: String)
    case unreadableFile(URL)
    case emptyDeck(URL)
}
