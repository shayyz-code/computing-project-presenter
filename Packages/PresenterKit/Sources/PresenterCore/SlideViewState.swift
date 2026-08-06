import CoreGraphics
import Foundation

/// Zoom and pan for the slide pane.
///
/// This is deliberately plain state rather than logic living in the `NSView`.
/// The rules below are the ones that go wrong in front of an audience — a slide
/// dragged off the pane looks identical to a crash — and none of them should
/// need a window, a trackpad or a running app to test.
///
/// Coordinates: `offset` is in *fitted-slide units*, where the fitted slide is
/// 1×1. That keeps the state independent of pane size, so a window resize does
/// not have to rewrite it.
@MainActor
@Observable
public final class SlideViewState {
    /// 1.0 is fit-to-pane. Never below: a slide smaller than its pane is a
    /// presentation bug, not a feature.
    public static let minimumZoom: CGFloat = 1.0
    /// Past this, a slide is a handful of pixels and the gesture feels broken.
    public static let maximumZoom: CGFloat = 8.0

    public private(set) var zoom: CGFloat = 1.0
    public private(set) var offset: CGPoint = .zero

    public init() {}

    /// True when the view is magnified at all.
    ///
    /// The epsilon matters: repeated pinch deltas accumulate float error, so an
    /// exact `zoom > 1.0` leaves the view "zoomed" by 1e-16 after pinching back
    /// out — which would silently switch two-finger scroll from navigating to
    /// panning and strand the presenter on one slide.
    public var isZoomed: Bool { zoom > Self.minimumZoom + 0.0001 }

    /// Multiplies the zoom, keeping `anchor` fixed on screen.
    ///
    /// - Parameters:
    ///   - factor: relative change, so `NSEvent.magnification + 1` passes straight in.
    ///   - anchor: the point to keep still, in unit coordinates where (0,0) is the
    ///     centre of the pane and ±0.5 are its edges. Passing `.zero` zooms about
    ///     the centre.
    public func magnify(by factor: CGFloat, around anchor: CGPoint = .zero) {
        guard factor.isFinite, factor > 0 else { return }
        let target = (zoom * factor).clamped(to: Self.minimumZoom...Self.maximumZoom)
        guard target != zoom else { return }

        // Keeping a point fixed means the content under it must not move: as the
        // slide grows by `target/zoom`, the offset to that point grows with it.
        // Without this, pinching drifts toward the centre and feels wrong even
        // though the zoom value is correct.
        let growth = target / zoom
        offset.x = (offset.x - anchor.x) * growth + anchor.x
        offset.y = (offset.y - anchor.y) * growth + anchor.y

        zoom = target
        clampOffset()
    }

    /// Sets zoom directly, keeping `anchor` fixed. Used by double-tap.
    public func setZoom(_ newZoom: CGFloat, around anchor: CGPoint = .zero) {
        guard newZoom.isFinite, zoom > 0 else { return }
        magnify(by: newZoom / zoom, around: anchor)
    }

    /// Pans by a delta in fitted-slide units.
    public func pan(by delta: CGSize) {
        guard delta.width.isFinite, delta.height.isFinite else { return }
        offset.x += delta.width
        offset.y += delta.height
        clampOffset()
    }

    /// Back to fit. Called on slide change so you never arrive zoomed into the
    /// corner of a slide you have not seen yet.
    public func reset() {
        zoom = Self.minimumZoom
        offset = .zero
    }

    /// Toggles between fit and `zoomedLevel`, for double-tap.
    public func toggleZoom(to zoomedLevel: CGFloat = 2.0, around anchor: CGPoint = .zero) {
        if isZoomed {
            reset()
        } else {
            setZoom(zoomedLevel, around: anchor)
        }
    }

    /// Keeps the slide covering the pane.
    ///
    /// At zoom `z` the slide is `z` times the pane, so the visible window can
    /// travel `(z - 1) / 2` from centre in each direction before an edge comes
    /// inside the pane. At zoom 1 that is 0, which is what pins a fitted slide
    /// centred and makes `pan` a no-op rather than a way to push the slide off
    /// screen.
    private func clampOffset() {
        let limit = max(0, (zoom - 1) / 2)
        offset.x = offset.x.clamped(to: -limit...limit)
        offset.y = offset.y.clamped(to: -limit...limit)
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Where the slide goes inside the pane.
///
/// Lives here rather than in the view because it is arithmetic with a spec
/// behind it — "aspect-correct at every pane width, letterboxed, never stretched
/// or cropped" — and that is worth a test rather than an eyeball. The view calls
/// these and draws the result.
public enum SlideLayout {
    /// The largest rect of `aspect` (width ÷ height) that fits inside `bounds`,
    /// centred. Letterboxes: the returned rect never exceeds `bounds` on either
    /// axis, so a slide is never cropped and never stretched.
    public static func fittedRect(aspect: CGFloat, in bounds: CGRect) -> CGRect {
        guard aspect > 0, aspect.isFinite, bounds.width > 0, bounds.height > 0 else { return .zero }

        let paneAspect = bounds.width / bounds.height
        let size: CGSize =
            aspect > paneAspect
            // Slide is wider than the pane: pin to width, bars top and bottom.
            ? CGSize(width: bounds.width, height: bounds.width / aspect)
            // Taller: pin to height, bars left and right.
            : CGSize(width: bounds.height * aspect, height: bounds.height)

        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height)
    }

    /// Where to draw the slide given zoom and pan.
    ///
    /// `offset` is in fitted-slide units, so it is independent of pane size and
    /// survives a window resize without recalculation.
    public static func drawRect(
        fitted: CGRect, zoom: CGFloat, offset: CGPoint
    ) -> CGRect {
        let width = fitted.width * zoom
        let height = fitted.height * zoom
        return CGRect(
            x: fitted.midX - width / 2 - offset.x * fitted.width,
            y: fitted.midY - height / 2 - offset.y * fitted.height,
            width: width,
            height: height)
    }
}
