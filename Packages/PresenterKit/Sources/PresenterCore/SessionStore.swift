import Foundation

/// What is worth remembering between launches.
///
/// Deliberately small. Every field here has to survive being wrong — a deck that
/// moved, a deck that got shorter, a source that is gone — so the fewer of them
/// the better.
public struct SessionSnapshot: Codable, Equatable, Sendable {
    /// Path rather than a bookmark, which is only safe because App Sandbox is
    /// deliberately off (ADR-0005) so filesystem access is not scoped to the
    /// open-panel grant. **If the app is ever sandboxed for the Mac App Store
    /// this stops resolving and needs a security-scoped bookmark.**
    public var deckPath: String?
    /// 1-based, matching `SlideNavigator.position`.
    public var slidePosition: Int
    public var showsNotes: Bool
    /// Remembered so the source can be pre-selected, **not** reconnected.
    /// Reconnecting on launch would unhide the Simulator uninvited and could
    /// fire a Camera or Screen Recording prompt before the user did anything.
    public var mirrorSourceID: String?

    public init(
        deckPath: String? = nil, slidePosition: Int = 1, showsNotes: Bool = true,
        mirrorSourceID: String? = nil
    ) {
        self.deckPath = deckPath
        self.slidePosition = slidePosition
        self.showsNotes = showsNotes
        self.mirrorSourceID = mirrorSourceID
    }

    public var deckURL: URL? {
        deckPath.map { URL(fileURLWithPath: $0) }
    }

    /// Whether the remembered deck is still where it was.
    ///
    /// Separate from `deckURL` so a caller can restore the rest of the session
    /// and *say which file is missing* rather than silently starting empty.
    public var deckStillExists: Bool {
        guard let deckPath else { return false }
        return FileManager.default.fileExists(atPath: deckPath)
    }
}

/// Somewhere to keep a snapshot.
///
/// A protocol so the degradation rules can be tested against an in-memory store
/// rather than real user defaults — the interesting cases are all about *bad*
/// stored data, and manufacturing those in a shared global would leak between
/// tests.
public protocol SessionStore: Sendable {
    /// The stored snapshot, or `nil` if there is none or it cannot be read.
    ///
    /// Returns `nil` rather than throwing on purpose: a saved session is a
    /// convenience and must never be able to stop the app from launching.
    func load() -> SessionSnapshot?
    func save(_ snapshot: SessionSnapshot)
    func clear()
}

/// The real store.
///
/// `@unchecked Sendable` because `UserDefaults` is documented as thread-safe but
/// not annotated as `Sendable`. That is a statement about the framework rather
/// than a shortcut around the checker — nothing here adds mutable state of its
/// own.
public struct UserDefaultsSessionStore: SessionStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "session.snapshot") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> SessionSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        // Corrupt data is discarded, not surfaced. A snapshot written by an older
        // build with a different shape must not prevent this one from starting.
        return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
    }

    public func save(_ snapshot: SessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}

/// For tests, and for a launch that should not persist anything.
public final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SessionSnapshot?
    /// Set to simulate data written by another version, which must be discarded
    /// rather than crash a launch.
    private var corrupt = false

    public init(_ initial: SessionSnapshot? = nil) {
        self.stored = initial
    }

    public func makeCorrupt() {
        lock.lock()
        defer { lock.unlock() }
        corrupt = true
    }

    public func load() -> SessionSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return corrupt ? nil : stored
    }

    public func save(_ snapshot: SessionSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        stored = snapshot
        corrupt = false
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        stored = nil
        corrupt = false
    }
}

/// What a caller should do with a snapshot, once reality has been checked
/// against it.
///
/// The point of naming these is that a stale session is the *normal* case for a
/// machine that moves between a desk and a lecture theatre — not an edge case —
/// so each outcome gets handled rather than lumped into "failed to restore".
public enum SessionRestoration: Equatable, Sendable {
    /// Nothing stored, or it was unreadable. Launch clean.
    case nothingToRestore
    /// The deck is there. Open it and jump to `position`.
    case restore(deck: URL, position: Int, showsNotes: Bool, mirrorSourceID: String?)
    /// A deck was remembered but is gone. Restore the rest and say which file,
    /// rather than starting empty with no explanation.
    case deckMissing(path: String, showsNotes: Bool, mirrorSourceID: String?)

    /// Reads a store and decides.
    public static func from(_ store: SessionStore) -> SessionRestoration {
        guard let snapshot = store.load() else { return .nothingToRestore }
        guard let path = snapshot.deckPath, !path.isEmpty else { return .nothingToRestore }

        guard snapshot.deckStillExists else {
            return .deckMissing(
                path: path, showsNotes: snapshot.showsNotes,
                mirrorSourceID: snapshot.mirrorSourceID)
        }
        return .restore(
            deck: URL(fileURLWithPath: path),
            // Clamped by the caller against the deck's real slide count: a deck
            // edited down between sessions would otherwise restore past its end.
            // `SlideNavigator` clamps at construction, so passing this through is
            // safe.
            position: max(1, snapshot.slidePosition),
            showsNotes: snapshot.showsNotes,
            mirrorSourceID: snapshot.mirrorSourceID)
    }
}
