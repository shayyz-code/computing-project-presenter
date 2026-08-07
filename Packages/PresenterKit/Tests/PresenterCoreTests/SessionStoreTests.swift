import Foundation
import Testing

@testable import PresenterCore

/// Makes a real file so `deckStillExists` is answering about the filesystem
/// rather than about a mock. The degradation rules are entirely about a file
/// being there or not, so faking that would test nothing.
private func temporaryDeck() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("deck-\(UUID().uuidString).pdf")
    try Data("%PDF-1.4".utf8).write(to: url)
    return url
}

@Suite("SessionSnapshot")
struct SessionSnapshotTests {

    @Test("Round-trips through encode and decode unchanged")
    func roundTrip() throws {
        let original = SessionSnapshot(
            deckPath: "/tmp/deck.pptx", slidePosition: 7, showsNotes: false,
            mirrorSourceID: "simulator-505")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)
        #expect(decoded == original)
    }

    @Test("An empty session is legal and round-trips")
    func emptyRoundTrip() throws {
        // Quitting with no deck open must not produce something that fails to
        // decode on the next launch.
        let empty = SessionSnapshot()
        let data = try JSONEncoder().encode(empty)
        #expect(try JSONDecoder().decode(SessionSnapshot.self, from: data) == empty)
    }

    @Test("deckStillExists answers about the real filesystem")
    func existence() throws {
        let url = try temporaryDeck()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(SessionSnapshot(deckPath: url.path).deckStillExists)
        #expect(!SessionSnapshot(deckPath: "/nonexistent/\(UUID().uuidString)").deckStillExists)
        #expect(!SessionSnapshot(deckPath: nil).deckStillExists)
        #expect(!SessionSnapshot(deckPath: "").deckStillExists)
    }
}

@Suite("SessionStore")
struct SessionStoreTests {

    @Test("Saving then loading returns what was saved")
    func saveLoad() {
        let store = InMemorySessionStore()
        #expect(store.load() == nil)

        let snapshot = SessionSnapshot(deckPath: "/tmp/a.pdf", slidePosition: 3)
        store.save(snapshot)
        #expect(store.load() == snapshot)
    }

    @Test("Clearing removes it")
    func clear() {
        let store = InMemorySessionStore(SessionSnapshot(deckPath: "/tmp/a.pdf"))
        store.clear()
        #expect(store.load() == nil)
    }

    @Test("UserDefaults store round-trips in an isolated suite")
    func userDefaultsRoundTrip() throws {
        // A named suite rather than .standard, so the test cannot pollute real
        // preferences or be polluted by them.
        let suiteName = "presenter.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsSessionStore(defaults: defaults)
        #expect(store.load() == nil)

        let snapshot = SessionSnapshot(deckPath: "/tmp/b.pptx", slidePosition: 12, showsNotes: false)
        store.save(snapshot)
        #expect(store.load() == snapshot)

        store.clear()
        #expect(store.load() == nil)
    }

    @Test("Unreadable stored data is discarded rather than thrown")
    func corruptDataIsDiscarded() throws {
        // The firm rule: a saved session is a convenience and must never be able
        // to stop the app from launching. A snapshot written by a build with a
        // different shape lands here.
        let suiteName = "presenter.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Data("not json at all".utf8), forKey: "session.snapshot")
        #expect(UserDefaultsSessionStore(defaults: defaults).load() == nil)
    }
}

@Suite("SessionRestoration")
struct SessionRestorationTests {

    @Test("Nothing stored means launch clean")
    func nothingStored() {
        #expect(SessionRestoration.from(InMemorySessionStore()) == .nothingToRestore)
    }

    @Test("A snapshot with no deck means launch clean")
    func noDeckRemembered() {
        // Quitting with nothing open should not produce a restore attempt.
        let store = InMemorySessionStore(SessionSnapshot(slidePosition: 4, showsNotes: false))
        #expect(SessionRestoration.from(store) == .nothingToRestore)

        let blank = InMemorySessionStore(SessionSnapshot(deckPath: ""))
        #expect(SessionRestoration.from(blank) == .nothingToRestore)
    }

    @Test("An existing deck restores with its position and preferences")
    func restoresDeck() throws {
        let url = try temporaryDeck()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = InMemorySessionStore(
            SessionSnapshot(
                deckPath: url.path, slidePosition: 7, showsNotes: false,
                mirrorSourceID: "simulator-505"))

        #expect(
            SessionRestoration.from(store)
                == .restore(
                    deck: url, position: 7, showsNotes: false, mirrorSourceID: "simulator-505"))
    }

    @Test("A deck that moved reports which file, and keeps the rest")
    func deckMissing() {
        // The case that matters for a machine that moved. Starting empty with no
        // explanation would leave the user guessing.
        let path = "/nonexistent/\(UUID().uuidString).pptx"
        let store = InMemorySessionStore(
            SessionSnapshot(
                deckPath: path, slidePosition: 9, showsNotes: false, mirrorSourceID: "device-1"))

        #expect(
            SessionRestoration.from(store)
                == .deckMissing(path: path, showsNotes: false, mirrorSourceID: "device-1"))
    }

    @Test("Corrupt storage launches clean rather than failing")
    func corruptStorage() throws {
        let url = try temporaryDeck()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = InMemorySessionStore(SessionSnapshot(deckPath: url.path))
        store.makeCorrupt()
        #expect(SessionRestoration.from(store) == .nothingToRestore)
    }

    @Test("A nonsense saved position is floored at the first slide")
    func positionFloor() throws {
        // Belt to the SlideNavigator braces: it clamps at construction, so a
        // saved zero or negative cannot land out of range — but passing garbage
        // through would still be sloppy.
        let url = try temporaryDeck()
        defer { try? FileManager.default.removeItem(at: url) }

        for saved in [0, -1, Int.min] {
            let store = InMemorySessionStore(
                SessionSnapshot(deckPath: url.path, slidePosition: saved))
            guard case .restore(_, let position, _, _) = SessionRestoration.from(store) else {
                Issue.record("expected a restore for saved position \(saved)")
                return
            }
            #expect(position == 1)
        }
    }

    @Test("A position past a shortened deck is clamped by the navigator")
    func shortenedDeck() throws {
        // The deck was edited between sessions and now has fewer slides. Restore
        // hands the saved position on; SlideNavigator is what makes it safe.
        let url = try temporaryDeck()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = InMemorySessionStore(
            SessionSnapshot(deckPath: url.path, slidePosition: 14))
        guard case .restore(_, let position, _, _) = SessionRestoration.from(store) else {
            Issue.record("expected a restore")
            return
        }

        let navigator = SlideNavigator(count: 8, position: position)
        #expect(navigator.position == 8, "a saved position past the end must clamp")
    }

    @Test("A remembered mirror source is carried but not acted on")
    func mirrorSourceRemembered() throws {
        // Carried so the UI can pre-select it. Connecting on launch would unhide
        // the Simulator uninvited and could fire a permission prompt before the
        // user did anything — so this type reports it and stops there.
        let url = try temporaryDeck()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = InMemorySessionStore(
            SessionSnapshot(deckPath: url.path, mirrorSourceID: "device-38DA121C"))
        guard case .restore(_, _, _, let sourceID) = SessionRestoration.from(store) else {
            Issue.record("expected a restore")
            return
        }
        #expect(sourceID == "device-38DA121C")
    }
}
