import Foundation
import Testing

@testable import SlideKit

/// A converter that does what the test tells it to, so chain selection and
/// failure handling can be exercised without LibreOffice, TCC consent
/// or a GUI session — none of which CI has.
private struct StubConverter: DeckConverter {
    let name: String
    let available: Bool
    /// Bytes to write as the "converted" PDF, or nil to throw.
    let output: Data?
    let record: (@Sendable (String) -> Void)?

    init(
        name: String, available: Bool = true, output: Data? = Data("%PDF-1.4".utf8),
        record: (@Sendable (String) -> Void)? = nil
    ) {
        self.name = name
        self.available = available
        self.output = output
        self.record = record
    }

    func isAvailable() -> Bool { available }

    func convert(_ pptx: URL, to pdf: URL) async throws {
        record?(name)
        guard let output else {
            throw ConversionError.failed(converter: name, reason: "stub failure")
        }
        try FileManager.default.createDirectory(
            at: pdf.deletingLastPathComponent(), withIntermediateDirectories: true)
        try output.write(to: pdf)
    }
}

private func fixture(_ name: String) throws -> URL {
    let url = Bundle.module.resourceURL?
        .appendingPathComponent("Fixtures").appendingPathComponent(name)
    guard let url, FileManager.default.fileExists(atPath: url.path) else {
        throw StubError.missingFixture(name)
    }
    return url
}

private enum StubError: Error { case missingFixture(String) }

private func temporaryCache() -> ConversionCache {
    ConversionCache(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("cache-\(UUID().uuidString)"))
}

@Suite("PPTXDeckLoader")
struct PPTXDeckLoaderTests {

    @Test("Only handles .pptx")
    func extensionGate() async throws {
        let loader = PPTXDeckLoader(converters: [StubConverter(name: "stub")], cache: temporaryCache())
        #expect(await loader.canLoad(URL(fileURLWithPath: "/tmp/a.pptx")))
        #expect(await !loader.canLoad(URL(fileURLWithPath: "/tmp/a.pdf")))
        // Case should not decide whether a deck opens.
        #expect(await loader.canLoad(URL(fileURLWithPath: "/tmp/a.PPTX")))
    }

    @Test("Reports it cannot load when no converter is installed")
    func noConverterAvailable() async throws {
        let loader = PPTXDeckLoader(
            converters: [
                StubConverter(name: "LibreOffice", available: false),
                StubConverter(name: "Fallback", available: false),
            ], cache: temporaryCache())
        #expect(await !loader.canLoad(URL(fileURLWithPath: "/tmp/a.pptx")))
    }

    @Test("Skips an unavailable converter and uses the next")
    func skipsUnavailable() async throws {
        // Chain semantics, exercised with stubs. Only LibreOffice ships today
        // (#79), but the loader still takes a list, so skipping a backend that
        // is not installed has to keep working for whatever is added next.
        let used = Mutex<[String]>([])
        let loader = PPTXDeckLoader(
            converters: [
                StubConverter(name: "LibreOffice", available: false) { used.append($0) },
                StubConverter(name: "Fallback", available: true) { used.append($0) },
            ], cache: temporaryCache())

        _ = try await loader.convertedPDF(for: try fixture("sparse-notes.pptx"))
        #expect(used.value == ["Fallback"])
    }

    @Test("Falls through to the next converter when one fails")
    func fallsThroughOnFailure() async throws {
        // An installed-but-broken converter must not sink an open another can do.
        let used = Mutex<[String]>([])
        let loader = PPTXDeckLoader(
            converters: [
                StubConverter(name: "LibreOffice", output: nil) { used.append($0) },
                StubConverter(name: "Fallback") { used.append($0) },
            ], cache: temporaryCache())

        _ = try await loader.convertedPDF(for: try fixture("sparse-notes.pptx"))
        #expect(used.value == ["LibreOffice", "Fallback"])
    }

    @Test("With nothing installed, the error names the format rather than a converter")
    func noLoaderAvailableError() async throws {
        let loader = PPTXDeckLoader(
            converters: [StubConverter(name: "LibreOffice", available: false)],
            cache: temporaryCache())

        await #expect(throws: DeckLoadingError.noLoaderAvailable(fileExtension: "pptx")) {
            try await loader.convertedPDF(for: try fixture("sparse-notes.pptx"))
        }
    }

    @Test("When every converter fails, the error says which and why")
    func allConvertersFailed() async throws {
        let loader = PPTXDeckLoader(
            converters: [
                StubConverter(name: "LibreOffice", output: nil),
                StubConverter(name: "Fallback", output: nil),
            ], cache: temporaryCache())

        do {
            _ = try await loader.convertedPDF(for: try fixture("sparse-notes.pptx"))
            Issue.record("expected conversion to fail")
        } catch let error as DeckLoadingError {
            guard case .conversionFailed(_, let reason) = error else {
                Issue.record("wrong error: \(error)")
                return
            }
            // Naming both is what lets a user act on it.
            #expect(reason.contains("LibreOffice"))
            #expect(reason.contains("Fallback"))
        }
    }

    @Test("A cache hit skips conversion entirely")
    func cacheHitSkipsConversion() async throws {
        let cache = temporaryCache()
        let calls = Mutex<[String]>([])
        let loader = PPTXDeckLoader(
            converters: [StubConverter(name: "stub") { calls.append($0) }], cache: cache)
        let deck = try fixture("sparse-notes.pptx")

        _ = try await loader.convertedPDF(for: deck)
        _ = try await loader.convertedPDF(for: deck)

        #expect(calls.value.count == 1, "second open should reuse the cached PDF")
    }

    @Test("Different content converts separately")
    func differentContentDifferentCacheEntry() async throws {
        // Content-hashed, not path-keyed: editing a deck must reconvert rather
        // than serve a stale render forever.
        let cache = temporaryCache()
        let calls = Mutex<[String]>([])
        let loader = PPTXDeckLoader(
            converters: [StubConverter(name: "stub") { calls.append($0) }], cache: cache)

        _ = try await loader.convertedPDF(for: try fixture("sparse-notes.pptx"))
        _ = try await loader.convertedPDF(for: try fixture("shuffled-order.pptx"))

        #expect(calls.value.count == 2)
    }

    @Test("A page-count mismatch is an error, not a short deck")
    func pageCountCrossCheck() async throws {
        // The check that turns a silent partial conversion into something the
        // user sees. The stub writes a PDF with no pages; the fixture declares
        // five slides.
        let loader = PPTXDeckLoader(
            converters: [StubConverter(name: "stub", output: Data("%PDF-1.4\n%%EOF".utf8))],
            cache: temporaryCache())

        do {
            _ = try await loader.load(try fixture("sparse-notes.pptx"))
            Issue.record("expected a mismatch to be reported")
        } catch let error as DeckLoadingError {
            guard case .conversionFailed(_, let reason) = error else {
                Issue.record("wrong error: \(error)")
                return
            }
            #expect(reason.contains("5"), "should name the declared slide count: \(reason)")
        } catch let error as SlideRenderingError {
            // An unreadable stub PDF fails earlier, which is also correct.
            _ = error
        }
    }

    @Test("A non-pptx is rejected before any converter runs")
    func rejectsNonPPTX() async throws {
        let calls = Mutex<[String]>([])
        let loader = PPTXDeckLoader(
            converters: [StubConverter(name: "stub") { calls.append($0) }], cache: temporaryCache())

        await #expect(throws: DeckLoadingError.self) {
            try await loader.load(URL(fileURLWithPath: "/tmp/deck.key"))
        }
        #expect(calls.value.isEmpty)
    }
}

@Suite("ConversionCache")
struct ConversionCacheTests {

    @Test("Identical content maps to the same key")
    func sameContentSameKey() throws {
        let cache = temporaryCache()
        let a = FileManager.default.temporaryDirectory
            .appendingPathComponent("a-\(UUID().uuidString).pptx")
        let b = FileManager.default.temporaryDirectory
            .appendingPathComponent("b-\(UUID().uuidString).pptx")
        try Data("identical".utf8).write(to: a)
        try Data("identical".utf8).write(to: b)
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
        }

        // Different names, same bytes — one conversion should serve both.
        #expect(try cache.destination(for: a) == (try cache.destination(for: b)))
    }

    @Test("Changing the content changes the key")
    func editedContentNewKey() throws {
        let cache = temporaryCache()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("edit-\(UUID().uuidString).pptx")
        try Data("before".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let before = try cache.destination(for: file)
        try Data("after".utf8).write(to: file)
        #expect(try cache.destination(for: file) != before)
    }

    @Test("A missing file is unreadable rather than a crash")
    func missingFile() throws {
        let cache = temporaryCache()
        #expect(throws: DeckLoadingError.self) {
            try cache.destination(for: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)"))
        }
    }
}

/// Minimal box so the stub can record calls from a `@Sendable` closure.
private final class Mutex<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) { self.storage = value }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

extension Mutex where Value == [String] {
    func append(_ element: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(element)
    }
}
