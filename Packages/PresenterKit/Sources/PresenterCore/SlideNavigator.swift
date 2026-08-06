import Foundation

/// Bounds-safe movement through a deck.
///
/// Split out from session state so the awkward cases — empty decks, jumping past
/// the end, advancing off the last slide — are testable without a UI or a loaded
/// file. Positions are 1-based, matching what the presenter sees.
public struct SlideNavigator: Equatable, Sendable {
    public private(set) var position: Int
    public let count: Int

    /// Creates a navigator over `count` slides. A `count` of zero is legal and
    /// leaves `position` at zero, meaning "nothing to show".
    public init(count: Int, position: Int = 1) {
        self.count = max(0, count)
        self.position = self.count == 0 ? 0 : Self.clamp(position, to: self.count)
    }

    public var isAtStart: Bool { count == 0 || position <= 1 }
    public var isAtEnd: Bool { count == 0 || position >= count }

    /// Advances one slide. Returns `false` if already on the last slide, so the
    /// caller can decide whether that ends the presentation.
    @discardableResult
    public mutating func advance() -> Bool {
        guard !isAtEnd else { return false }
        position += 1
        return true
    }

    @discardableResult
    public mutating func retreat() -> Bool {
        guard !isAtStart else { return false }
        position -= 1
        return true
    }

    /// Jumps to a position, clamping into range rather than failing.
    public mutating func jump(to target: Int) {
        guard count > 0 else { return }
        position = Self.clamp(target, to: count)
    }

    private static func clamp(_ value: Int, to count: Int) -> Int {
        min(max(value, 1), count)
    }
}
