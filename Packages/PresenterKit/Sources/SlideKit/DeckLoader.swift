import Foundation

/// Something that can turn a file on disk into a `Deck`.
///
/// Three conformances are planned, tried in the order described by ADR-0002:
/// PDF passthrough (always available), LibreOffice (preferred for `.pptx` when
/// installed), Keynote (the no-install fallback). None are implemented yet —
/// they land in M1, and the Keynote path is gated on a spike.
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
