import CoreGraphics
import Foundation

/// Keeps rendered pages around so advancing a slide does not wait on a
/// rasterisation.
///
/// A decorator over `SlideRenderer` rather than a change to `PDFSlideRenderer`:
/// it stays backend-agnostic, so a future `OOXMLSlideRenderer` gets caching for
/// free, and the whole thing is testable against a stub with no PDF involved.
public final class CachingSlideRenderer: SlideRenderer, @unchecked Sendable {
    private let wrapped: SlideRenderer
    private let budgetBytes: Int

    /// Guards every field below. Prefetch runs off the main actor, so this is
    /// load-bearing rather than defensive.
    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    /// Least-recently-used first, so eviction pops from the front.
    private var usageOrder: [Key] = []
    private var totalBytes = 0
    /// The page currently being displayed. Never evicted.
    private var pinnedPage: Int?
    /// The geometry of the last render request, used to spot a display change.
    private var currentGeometry: Geometry?

    private struct Key: Hashable {
        let page: Int
        let width: Int
        let height: Int
        let scale: CGFloat
    }

    private struct Geometry: Equatable {
        let width: Int
        let height: Int
        let scale: CGFloat
    }

    private struct Entry {
        let image: CGImage
        let bytes: Int
    }

    /// - Parameters:
    ///   - wrapping: the renderer that does the actual work.
    ///   - budgetBytes: how much image data to hold. Bytes rather than a page
    ///     count on purpose — see `defaultBudgetBytes`.
    public init(wrapping: SlideRenderer, budgetBytes: Int = CachingSlideRenderer.defaultBudgetBytes) {
        self.wrapped = wrapping
        self.budgetBytes = max(0, budgetBytes)
    }

    /// 256 MB.
    ///
    /// The budget is in bytes because a page's cost swings by roughly 9× with
    /// where it is being shown — about 4 MB in a window on a laptop, 10 MB
    /// fullscreen at 2×, 35 MB fullscreen on a large external display. A page
    /// count safe on the projector would waste most of memory in a window, and
    /// one generous in a window would run to gigabytes in fullscreen. Bytes
    /// self-adjust: roughly 25 pages windowed, 7 on a big display.
    public static let defaultBudgetBytes = 256 << 20

    /// How many pages either side of the current one to warm.
    public static let prefetchRadius = 2

    public var pageCount: Int { wrapped.pageCount }

    public func aspectRatio(page: Int) throws -> CGFloat {
        // Cheap and already just arithmetic over the page box; caching it would
        // add invalidation surface for nothing.
        try wrapped.aspectRatio(page: page)
    }

    public func render(page: Int, size: CGSize, scale: CGFloat) throws -> CGImage {
        let key = Key(
            page: page, width: Int(size.width.rounded()), height: Int(size.height.rounded()),
            scale: scale)
        let geometry = Geometry(width: key.width, height: key.height, scale: key.scale)

        lock.lock()
        // A geometry change means the window resized or moved to a display with
        // a different backing scale. Every existing entry is now the wrong size,
        // and leaving them to age out would hold the budget precisely when the
        // new size needs room — so drop them outright.
        if let currentGeometry, currentGeometry != geometry {
            entries.removeAll()
            usageOrder.removeAll()
            totalBytes = 0
        }
        currentGeometry = geometry
        // The page being asked for is the page being displayed.
        pinnedPage = page

        if let hit = entries[key] {
            touch(key)
            lock.unlock()
            return hit.image
        }
        lock.unlock()

        // Rendered outside the lock: rasterising is the slow part, and holding
        // the lock across it would serialise a prefetch behind the visible page.
        let image = try wrapped.render(page: page, size: size, scale: scale)

        lock.lock()
        insert(image: image, for: key)
        lock.unlock()
        return image
    }

    /// Warms the pages either side of `page`, off the caller's thread.
    ///
    /// Fire-and-forget by design: it must never delay a keypress, and a failure
    /// needs no handling because `render` will simply rasterise on demand. Errors
    /// are swallowed for that reason and no other.
    public func prefetch(around page: Int, size: CGSize, scale: CGFloat) {
        let radius = Self.prefetchRadius
        let pages = ((page - radius)...(page + radius))
            .filter { $0 != page && $0 >= 0 && $0 < wrapped.pageCount }

        for neighbour in pages {
            Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                let key = Key(
                    page: neighbour, width: Int(size.width.rounded()),
                    height: Int(size.height.rounded()), scale: scale)

                // The locked work sits in synchronous helpers: Swift 6 forbids
                // NSLock from an async context, and holding a lock across a
                // suspension point would be wrong regardless.
                guard !self.isCached(key) else { return }

                guard let image = try? wrapped.render(page: neighbour, size: size, scale: scale)
                else { return }

                self.storeIfGeometryStillCurrent(image: image, for: key)
            }
        }
    }

    private func isCached(_ key: Key) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[key] != nil
    }

    /// Stores a prefetched image, unless the window changed size while it was
    /// rendering — in which case it is already stale and inserting it would
    /// evict something still useful.
    private func storeIfGeometryStillCurrent(image: CGImage, for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        guard currentGeometry == Geometry(width: key.width, height: key.height, scale: key.scale)
        else { return }
        insert(image: image, for: key)
    }

    /// Current cache size in bytes. For tests and diagnostics.
    public var cachedBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalBytes
    }

    public var cachedPageCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    // MARK: - Cache bookkeeping
    //
    // Every caller below holds `lock`.

    private func insert(image: CGImage, for key: Key) {
        let bytes = image.height * image.bytesPerRow
        // A single page larger than the whole budget would evict everything and
        // still not fit, so it is used but not stored.
        guard bytes <= budgetBytes else { return }

        if entries[key] != nil { remove(key) }
        entries[key] = Entry(image: image, bytes: bytes)
        usageOrder.append(key)
        totalBytes += bytes
        evictUntilWithinBudget()
    }

    private func touch(_ key: Key) {
        guard let index = usageOrder.firstIndex(of: key) else { return }
        usageOrder.remove(at: index)
        usageOrder.append(key)
    }

    private func evictUntilWithinBudget() {
        var index = 0
        while totalBytes > budgetBytes, index < usageOrder.count {
            let candidate = usageOrder[index]
            // Never evict the page on screen. A budget smaller than the working
            // set would otherwise drop the visible slide and make every advance
            // a guaranteed miss — a cache that costs more than it saves.
            if candidate.page == pinnedPage {
                index += 1
                continue
            }
            remove(candidate)
        }
    }

    private func remove(_ key: Key) {
        if let entry = entries.removeValue(forKey: key) {
            totalBytes -= entry.bytes
        }
        if let index = usageOrder.firstIndex(of: key) {
            usageOrder.remove(at: index)
        }
    }
}
