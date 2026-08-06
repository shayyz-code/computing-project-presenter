import CoreGraphics
import Testing

@testable import PresenterCore

@MainActor
@Suite("SlideViewState")
struct SlideViewStateTests {

    @Test("Starts fitted and not zoomed")
    func initialState() {
        let state = SlideViewState()
        #expect(state.zoom == 1.0)
        #expect(state.offset == .zero)
        #expect(!state.isZoomed)
    }

    @Test("Zoom clamps at both ends")
    func zoomClamps() {
        let state = SlideViewState()

        // A fitted slide must never shrink inside its pane.
        state.magnify(by: 0.1)
        #expect(state.zoom == SlideViewState.minimumZoom)

        state.magnify(by: 1000)
        #expect(state.zoom == SlideViewState.maximumZoom)
    }

    @Test("Pinching out and back lands exactly on fit")
    func roundTripReturnsToFit() {
        // The lower clamp does this work: pinching out drives zoom into
        // minimumZoom rather than approaching it, so no residue accumulates.
        let state = SlideViewState()
        for _ in 0..<40 { state.magnify(by: 1.05) }
        for _ in 0..<40 { state.magnify(by: 1 / 1.05) }

        #expect(state.zoom == SlideViewState.minimumZoom)
        #expect(!state.isZoomed)
    }

    @Test("A hair above fit does not count as zoomed")
    func epsilonAroundFit() {
        // The case the epsilon in isZoomed actually exists for, and which the
        // round-trip test above does NOT reach because clamping snaps to exactly
        // 1.0. A zoom that lands just above fit without hitting the clamp is
        // visually fitted, but an exact `zoom > 1` would call it zoomed — which
        // silently switches two-finger scroll from navigating to panning and
        // strands the presenter on one slide with no way to advance.
        let state = SlideViewState()
        state.setZoom(1.00001)
        #expect(state.zoom > SlideViewState.minimumZoom, "precondition: not clamped away")
        #expect(!state.isZoomed, "a hair above fit must still navigate, not pan")

        // And a real zoom still registers.
        state.setZoom(1.5)
        #expect(state.isZoomed)
    }

    @Test("Magnifying about a point keeps that point fixed")
    func anchorStaysPut() {
        let state = SlideViewState()
        let anchor = CGPoint(x: 0.25, y: -0.1)

        state.magnify(by: 2, around: anchor)

        // The content under the anchor must not move. Offset grows with the
        // slide, so the anchor's position relative to content is unchanged.
        // At zoom 2 from centre: offset = (0 - 0.25) * 2 + 0.25 = -0.25
        #expect(abs(state.offset.x - (-0.25)) < 0.0001)
        #expect(abs(state.offset.y - 0.1) < 0.0001)
    }

    @Test("A fitted slide cannot be panned at all")
    func noPanWhenFitted() {
        // At zoom 1 the slide exactly covers the pane, so any offset would show
        // a bar of empty pane — which on a projector reads as a broken slide.
        let state = SlideViewState()
        state.pan(by: CGSize(width: 5, height: -3))
        #expect(state.offset == .zero)
    }

    @Test("Pan clamps so the slide always covers the pane", arguments: [2.0, 4.0, 8.0])
    func panClampsAtEveryZoom(zoomLevel: CGFloat) {
        let state = SlideViewState()
        state.setZoom(zoomLevel)

        state.pan(by: CGSize(width: 100, height: 100))
        let limit = (zoomLevel - 1) / 2
        #expect(abs(state.offset.x - limit) < 0.0001)
        #expect(abs(state.offset.y - limit) < 0.0001)

        state.pan(by: CGSize(width: -100, height: -100))
        #expect(abs(state.offset.x - (-limit)) < 0.0001)
        #expect(abs(state.offset.y - (-limit)) < 0.0001)
    }

    @Test("Zooming back out re-clamps an offset that is no longer reachable")
    func zoomOutReclampsOffset() {
        // Pan to the far corner at high zoom, then zoom out. The old offset is
        // outside the new limit; leaving it would show empty pane at the edge.
        let state = SlideViewState()
        state.setZoom(8)
        state.pan(by: CGSize(width: 100, height: 100))
        #expect(state.offset.x > 3)

        state.setZoom(2)
        #expect(state.offset.x <= 0.5 + 0.0001)
        #expect(state.offset.y <= 0.5 + 0.0001)
    }

    @Test("reset returns to fit and centre")
    func resetClearsEverything() {
        let state = SlideViewState()
        state.setZoom(6)
        state.pan(by: CGSize(width: 10, height: 10))

        state.reset()

        #expect(state.zoom == 1.0)
        #expect(state.offset == .zero)
        #expect(!state.isZoomed)
    }

    @Test("Double-tap toggles between fit and 2x")
    func toggle() {
        let state = SlideViewState()

        state.toggleZoom()
        #expect(state.zoom == 2.0)
        #expect(state.isZoomed)

        state.toggleZoom()
        #expect(state.zoom == 1.0)
        #expect(!state.isZoomed)
    }

    @Test("Non-finite and non-positive input is ignored rather than corrupting state")
    func rejectsBadInput() {
        // NSEvent.magnification can produce these at gesture boundaries; a NaN
        // reaching `zoom` makes every later comparison false and freezes the pane.
        let state = SlideViewState()
        state.setZoom(4)
        let before = state.zoom

        state.magnify(by: .nan)
        state.magnify(by: .infinity)
        state.magnify(by: 0)
        state.magnify(by: -2)
        #expect(state.zoom == before)

        state.pan(by: CGSize(width: CGFloat.nan, height: 0))
        #expect(state.offset.x.isFinite)
    }
}

@Suite("SlideLayout")
struct SlideLayoutTests {
    private let pane = CGRect(x: 0, y: 0, width: 1000, height: 600)  // 5:3

    @Test("A wider slide letterboxes top and bottom")
    func widerThanPane() {
        // 16:9 into 5:3 — pins to width, bars above and below.
        let rect = SlideLayout.fittedRect(aspect: 16.0 / 9.0, in: pane)
        #expect(rect.width == 1000)
        #expect(abs(rect.height - 562.5) < 0.01)
        #expect(rect.height < pane.height, "must letterbox, not overflow")
        #expect(abs(rect.midX - pane.midX) < 0.01)
        #expect(abs(rect.midY - pane.midY) < 0.01)
    }

    @Test("A taller slide pillarboxes left and right")
    func tallerThanPane() {
        // 4:3 into 5:3 — pins to height, bars either side.
        let rect = SlideLayout.fittedRect(aspect: 4.0 / 3.0, in: pane)
        #expect(rect.height == 600)
        #expect(abs(rect.width - 800) < 0.01)
        #expect(rect.width < pane.width)
        #expect(abs(rect.midX - pane.midX) < 0.01)
    }

    @Test(
        "The slide never exceeds the pane at any aspect", arguments: [0.2, 0.5, 1.0, 1.33, 1.78, 2.35, 5.0])
    func neverOverflows(aspect: CGFloat) {
        // The cropping/stretching criterion, checked across the range rather
        // than at one convenient value.
        let rect = SlideLayout.fittedRect(aspect: aspect, in: pane)
        #expect(rect.width <= pane.width + 0.01)
        #expect(rect.height <= pane.height + 0.01)
        // And aspect is preserved — no stretching.
        #expect(abs(rect.width / rect.height - aspect) < 0.001)
    }

    @Test("Degenerate input yields an empty rect rather than NaN geometry")
    func degenerate() {
        #expect(SlideLayout.fittedRect(aspect: 0, in: pane) == .zero)
        #expect(SlideLayout.fittedRect(aspect: .nan, in: pane) == .zero)
        // A pane can be laid out at zero size for a frame during a resize.
        #expect(SlideLayout.fittedRect(aspect: 1.5, in: .zero) == .zero)
    }

    @Test("At fit, the drawn rect equals the fitted rect")
    func drawAtFit() {
        let fitted = SlideLayout.fittedRect(aspect: 16.0 / 9.0, in: pane)
        let drawn = SlideLayout.drawRect(fitted: fitted, zoom: 1, offset: .zero)
        #expect(abs(drawn.origin.x - fitted.origin.x) < 0.001)
        #expect(abs(drawn.width - fitted.width) < 0.001)
    }

    @Test("Zooming grows the drawn rect about the centre")
    func drawZoomed() {
        let fitted = SlideLayout.fittedRect(aspect: 16.0 / 9.0, in: pane)
        let drawn = SlideLayout.drawRect(fitted: fitted, zoom: 2, offset: .zero)
        #expect(abs(drawn.width - fitted.width * 2) < 0.001)
        // Centre stays put, so zoom does not slide the image sideways.
        #expect(abs(drawn.midX - fitted.midX) < 0.001)
        #expect(abs(drawn.midY - fitted.midY) < 0.001)
    }

    @Test("Offset moves the drawn rect in fitted-slide units")
    func drawOffset() {
        let fitted = SlideLayout.fittedRect(aspect: 16.0 / 9.0, in: pane)
        let drawn = SlideLayout.drawRect(
            fitted: fitted, zoom: 2, offset: CGPoint(x: 0.25, y: 0))
        // A quarter of a fitted width, moved opposite the pan direction.
        #expect(abs(drawn.midX - (fitted.midX - fitted.width * 0.25)) < 0.001)
    }
}
