import CoreGraphics
import Foundation
import Testing

@testable import SlideKit

/// Counts calls and hands back images of a chosen size, so cache behaviour can
/// be exercised with no PDF and no filesystem — which is what issue #18 means by
/// "unit-tested without a real PDF".
private final class StubRenderer: SlideRenderer, @unchecked Sendable {
    let pageCount: Int
    /// Bytes each produced image should occupy, so budget maths is exact rather
    /// than dependent on real page geometry.
    private let pixelsPerSide: Int
    private let lock = NSLock()
    private var calls: [Int] = []
    var failingPages: Set<Int> = []

    init(pageCount: Int, pixelsPerSide: Int = 100) {
        self.pageCount = pageCount
        self.pixelsPerSide = pixelsPerSide
    }

    var callLog: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    var callCount: Int { callLog.count }

    func aspectRatio(page: Int) throws -> CGFloat { 16.0 / 9.0 }

    func render(page: Int, size: CGSize, scale: CGFloat) throws -> CGImage {
        lock.lock()
        calls.append(page)
        let shouldFail = failingPages.contains(page)
        lock.unlock()

        if shouldFail {
            throw SlideRenderingError.renderFailed(page: page, reason: "stub failure")
        }
        guard
            let context = CGContext(
                data: nil, width: pixelsPerSide, height: pixelsPerSide, bitsPerComponent: 8,
                bytesPerRow: pixelsPerSide * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue),
            let image = context.makeImage()
        else {
            throw SlideRenderingError.renderFailed(page: page, reason: "stub context")
        }
        return image
    }

    /// Bytes one stub image occupies, for writing exact budgets.
    var bytesPerImage: Int { pixelsPerSide * pixelsPerSide * 4 }
}

private let size = CGSize(width: 100, height: 100)

@Suite("CachingSlideRenderer")
struct CachingSlideRendererTests {

    @Test("A repeat request does not reach the wrapped renderer")
    func cacheHit() throws {
        let stub = StubRenderer(pageCount: 10)
        let cache = CachingSlideRenderer(wrapping: stub)

        _ = try cache.render(page: 3, size: size, scale: 2)
        _ = try cache.render(page: 3, size: size, scale: 2)
        _ = try cache.render(page: 3, size: size, scale: 2)

        #expect(stub.callCount == 1, "rendered \(stub.callCount) times instead of once")
    }

    @Test("Different pages, sizes and scales are distinct entries")
    func keyIncludesGeometry() throws {
        let stub = StubRenderer(pageCount: 10)
        let cache = CachingSlideRenderer(wrapping: stub)

        _ = try cache.render(page: 1, size: size, scale: 2)
        _ = try cache.render(page: 2, size: size, scale: 2)
        // A different scale is a different image, so it must not hit.
        _ = try cache.render(page: 1, size: size, scale: 3)

        #expect(stub.callCount == 3)
    }

    @Test("Exceeding the budget evicts the least recently used page")
    func lruEviction() throws {
        let stub = StubRenderer(pageCount: 10)
        // Room for exactly three images.
        let cache = CachingSlideRenderer(wrapping: stub, budgetBytes: stub.bytesPerImage * 3)

        for page in 0..<3 { _ = try cache.render(page: page, size: size, scale: 2) }
        #expect(cache.cachedPageCount == 3)

        // Touch page 0 so page 1 becomes the oldest.
        _ = try cache.render(page: 0, size: size, scale: 2)
        // Page 3 pushes one out, and the victim must be 1 rather than whichever
        // the dictionary happened to yield.
        _ = try cache.render(page: 3, size: size, scale: 2)

        let before = stub.callCount
        _ = try cache.render(page: 1, size: size, scale: 2)
        #expect(stub.callCount == before + 1, "page 1 should have been the evicted one")

        let afterZero = stub.callCount
        _ = try cache.render(page: 0, size: size, scale: 2)
        #expect(stub.callCount == afterZero, "page 0 was touched and must have survived")
    }

    @Test("The page on screen is never evicted")
    func pinnedPageSurvives() async throws {
        // A naive LRU under budget pressure evicts the visible page, making every
        // advance a guaranteed miss — a cache that costs more than it saves.
        //
        // The pressure has to come from prefetch, because rendering another page
        // would move the pin to it. And prefetch is detached, so this must wait
        // for the inserts to actually land: an earlier version of this test
        // asserted before any pressure had been applied and passed against a
        // build with the pinning removed entirely.
        let stub = StubRenderer(pageCount: 10)
        let cache = CachingSlideRenderer(wrapping: stub, budgetBytes: stub.bytesPerImage * 2)

        _ = try cache.render(page: 5, size: size, scale: 2)
        cache.prefetch(around: 5, size: size, scale: 2)

        // Four neighbours contending for one free slot; wait until the budget is
        // saturated and the dust has settled.
        try await waitUntil { cache.cachedPageCount >= 2 }
        try await Task.sleep(for: .milliseconds(300))
        #expect(cache.cachedBytes <= stub.bytesPerImage * 2, "precondition: budget is saturated")

        let before = stub.callCount
        _ = try cache.render(page: 5, size: size, scale: 2)
        #expect(stub.callCount == before, "the displayed page must survive eviction pressure")
    }

    @Test("A geometry change purges rather than leaving stale entries to age out")
    func geometryChangePurges() throws {
        let stub = StubRenderer(pageCount: 10)
        let cache = CachingSlideRenderer(wrapping: stub)

        for page in 0..<4 { _ = try cache.render(page: page, size: size, scale: 2) }
        #expect(cache.cachedPageCount == 4)

        // Moving to a display with a different backing scale. Every entry is now
        // the wrong size, and holding them would starve the new scale of budget
        // exactly when it needs room.
        _ = try cache.render(page: 0, size: size, scale: 3)
        #expect(cache.cachedPageCount == 1, "old-scale entries should be gone")
        #expect(cache.cachedBytes == stub.bytesPerImage)
    }

    @Test("A single page larger than the whole budget is served but not stored")
    func oversizedPage() throws {
        let stub = StubRenderer(pageCount: 5)
        let cache = CachingSlideRenderer(wrapping: stub, budgetBytes: stub.bytesPerImage / 2)

        // Must still return an image — the pane has to draw something.
        _ = try cache.render(page: 0, size: size, scale: 2)
        #expect(cache.cachedPageCount == 0, "storing it would evict everything and still not fit")
    }

    @Test("A failing render does not poison the cache")
    func failureDoesNotPoison() throws {
        let stub = StubRenderer(pageCount: 5)
        stub.failingPages = [2]
        let cache = CachingSlideRenderer(wrapping: stub)

        #expect(throws: SlideRenderingError.self) {
            try cache.render(page: 2, size: size, scale: 2)
        }

        // The next attempt must retry rather than return a cached failure.
        stub.failingPages = []
        _ = try cache.render(page: 2, size: size, scale: 2)
        #expect(cache.cachedPageCount == 1)
    }

    @Test("Prefetch warms the neighbours")
    func prefetchWarmsNeighbours() async throws {
        let stub = StubRenderer(pageCount: 20)
        let cache = CachingSlideRenderer(wrapping: stub)

        _ = try cache.render(page: 10, size: size, scale: 2)
        cache.prefetch(around: 10, size: size, scale: 2)

        // Prefetch is detached, so wait for it to settle rather than assuming.
        try await waitUntil { cache.cachedPageCount >= 5 }

        // 8, 9, 11, 12 plus the rendered 10.
        #expect(cache.cachedPageCount == 5)
        #expect(Set(stub.callLog) == Set([8, 9, 10, 11, 12]))
    }

    @Test("Prefetch clamps at both ends of the deck")
    func prefetchClamps() async throws {
        let stub = StubRenderer(pageCount: 3)
        let cache = CachingSlideRenderer(wrapping: stub)

        _ = try cache.render(page: 0, size: size, scale: 2)
        cache.prefetch(around: 0, size: size, scale: 2)
        try await waitUntil { cache.cachedPageCount >= 3 }

        // Never negative, never past the last page.
        #expect(stub.callLog.allSatisfy { $0 >= 0 && $0 < 3 })
        #expect(cache.cachedPageCount == 3)
    }

    @Test("Prefetch does not re-render what is already cached")
    func prefetchSkipsCached() async throws {
        let stub = StubRenderer(pageCount: 20)
        let cache = CachingSlideRenderer(wrapping: stub)

        _ = try cache.render(page: 10, size: size, scale: 2)
        cache.prefetch(around: 10, size: size, scale: 2)
        try await waitUntil { cache.cachedPageCount >= 5 }
        let firstPass = stub.callCount

        cache.prefetch(around: 10, size: size, scale: 2)
        try await Task.sleep(for: .milliseconds(200))
        #expect(stub.callCount == firstPass, "a second prefetch should be a no-op")
    }

    @Test("pageCount and aspectRatio pass through")
    func passThrough() throws {
        let stub = StubRenderer(pageCount: 42)
        let cache = CachingSlideRenderer(wrapping: stub)
        #expect(cache.pageCount == 42)
        #expect(abs(try cache.aspectRatio(page: 0) - 16.0 / 9.0) < 0.001)
    }
}

/// Polls a condition instead of sleeping a guessed interval, so the detached
/// prefetch work is awaited rather than raced.
private func waitUntil(
    timeout: Duration = .seconds(3), _ condition: @Sendable () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("condition not met within \(timeout)")
}
