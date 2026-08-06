import AppKit
import PresenterCore
import SlideKit
import SwiftUI

/// The left pane: one slide, filling the space, with pinch-zoom and trackpad
/// navigation.
///
/// Hosts an `NSView` rather than drawing in SwiftUI because the gestures need
/// `NSEvent` directly — `scrollWheel` phase tracking in particular has no SwiftUI
/// equivalent that can tell a deliberate swipe from its momentum tail.
struct SlidePane: NSViewRepresentable {
    let renderer: SlideRenderer?
    /// 1-based, matching `SlideNavigator.position` and `Slide.number`.
    let slideNumber: Int
    let state: SlideViewState
    let onNext: () -> Void
    let onPrevious: () -> Void

    func makeNSView(context: Context) -> SlideNSView {
        let view = SlideNSView()
        view.configure(state: state, onNext: onNext, onPrevious: onPrevious)
        return view
    }

    func updateNSView(_ view: SlideNSView, context: Context) {
        view.configure(state: state, onNext: onNext, onPrevious: onPrevious)
        view.show(renderer: renderer, slideNumber: slideNumber)
    }
}

/// Draws the current slide and turns trackpad events into state changes.
final class SlideNSView: NSView {
    private var renderer: SlideRenderer?
    private var slideNumber = 0
    private var state: SlideViewState?
    private var onNext: () -> Void = {}
    private var onPrevious: () -> Void = {}

    private var cachedImage: CGImage?
    /// What `cachedImage` was rendered for. Re-render only when one of these
    /// changes, so a pan does not re-rasterise the page on every event.
    private var cacheKey: CacheKey?

    private struct CacheKey: Equatable {
        let slideNumber: Int
        let width: Int
        let height: Int
        let zoom: CGFloat
        let backingScale: CGFloat
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var wantsUpdateLayer: Bool { false }

    func configure(state: SlideViewState, onNext: @escaping () -> Void, onPrevious: @escaping () -> Void) {
        self.state = state
        self.onNext = onNext
        self.onPrevious = onPrevious
    }

    func show(renderer: SlideRenderer?, slideNumber: Int) {
        let slideChanged = self.slideNumber != slideNumber
        self.renderer = renderer
        self.slideNumber = slideNumber
        // Arriving on a new slide already zoomed into a corner is disorienting,
        // and there is no affordance telling you that is what happened.
        if slideChanged { state?.reset() }
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fill(bounds)

        guard let renderer, slideNumber >= 1, slideNumber <= renderer.pageCount else { return }
        let page = slideNumber - 1

        guard let aspect = try? renderer.aspectRatio(page: page), aspect > 0 else { return }
        let zoom = state?.zoom ?? 1
        let offset = state?.offset ?? .zero
        let fitted = SlideLayout.fittedRect(aspect: aspect, in: bounds)
        guard !fitted.isEmpty else { return }

        // Rendering at the zoomed pixel size is what makes zoom sharp rather than
        // a magnified bitmap — the whole reason SlideRenderer takes a scale.
        let backingScale = window?.backingScaleFactor ?? 2
        let key = CacheKey(
            slideNumber: slideNumber,
            width: Int(fitted.width), height: Int(fitted.height),
            zoom: zoom, backingScale: backingScale)

        if key != cacheKey {
            cachedImage = try? renderer.render(
                page: page, size: fitted.size, scale: backingScale * zoom)
            cacheKey = key
        }
        guard let image = cachedImage else { return }

        let drawn = SlideLayout.drawRect(fitted: fitted, zoom: zoom, offset: offset)

        context.saveGState()
        context.clip(to: fitted)
        context.interpolationQuality = .high
        // This view is flipped (top-left origin, so layout arithmetic reads
        // naturally) but `CGContext.draw` places an image in bottom-left space.
        // Without undoing that, every slide renders upside down. Flipping about
        // the drawn rect keeps the geometry above unchanged.
        context.translateBy(x: 0, y: drawn.minY + drawn.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: drawn)
        context.restoreGState()
    }

    // MARK: - Gestures

    override func magnify(with event: NSEvent) {
        guard let state else { return }
        // NSEvent.magnification is a relative delta, so +1 makes it a factor.
        state.magnify(by: 1 + event.magnification, around: unitPoint(of: event))
        needsDisplay = true
    }

    override func smartMagnify(with event: NSEvent) {
        state?.toggleZoom(around: unitPoint(of: event))
        needsDisplay = true
    }

    /// Two-finger scroll: navigate when fitted, pan when zoomed.
    ///
    /// Without that split, zooming in would strand the presenter on one slide —
    /// the gesture they use to advance would silently stop working.
    override func scrollWheel(with event: NSEvent) {
        guard let state else { return }

        if state.isZoomed {
            let scale = bounds.width > 0 ? bounds.width : 1
            state.pan(
                by: CGSize(
                    width: -event.scrollingDeltaX / scale,
                    height: -event.scrollingDeltaY / scale))
            needsDisplay = true
            return
        }

        // Momentum is the tail of a finished gesture. Acting on it turns one
        // swipe into three slides.
        guard event.momentumPhase == [] else { return }

        switch event.phase {
        case .began:
            swipeAccumulator = 0
            swipeHandled = false
        case .changed:
            guard !swipeHandled else { return }
            swipeAccumulator += event.scrollingDeltaX
            if abs(swipeAccumulator) >= Self.swipeThreshold {
                // One gesture, one slide: latched until the fingers lift.
                swipeHandled = true
                swipeAccumulator > 0 ? onPrevious() : onNext()
            }
        case .ended, .cancelled:
            swipeAccumulator = 0
            swipeHandled = false
        default:
            // A mouse wheel reports no phase. Treat each notch as one step.
            guard abs(event.scrollingDeltaX) > 1 else { return }
            event.scrollingDeltaX > 0 ? onPrevious() : onNext()
        }
    }

    /// Points of horizontal travel before a swipe counts. Low enough to feel
    /// responsive, high enough that a slightly diagonal pan does not advance.
    private static let swipeThreshold: CGFloat = 40
    private var swipeAccumulator: CGFloat = 0
    private var swipeHandled = false

    /// Only zoom keys here. Slide navigation moved to the Navigate menu and a
    /// window-level key monitor, because a view's `keyDown` fires only while that
    /// view is first responder — so clicking anything in the mirror pane used to
    /// stop the arrow keys silently. See `KeyboardNavigation`.
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 29, 82:  // 0 and keypad 0 — back to fit
            state?.reset()
            needsDisplay = true
        default: super.keyDown(with: event)
        }
    }

    /// Cursor position in unit coordinates: (0,0) centre, ±0.5 at the edges.
    /// This is the space `SlideViewState.magnify(by:around:)` anchors in.
    private func unitPoint(of event: NSEvent) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(
            x: (local.x - bounds.midX) / bounds.width,
            y: (local.y - bounds.midY) / bounds.height)
    }

    // Re-render when the window moves to a display with a different backing
    // scale, or the slide is blurry on the projector.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        cacheKey = nil
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }
}
