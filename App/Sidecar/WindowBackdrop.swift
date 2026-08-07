import AppKit
import SwiftUI

/// The blurred desktop behind the app.
///
/// This is what was missing from the glass work: `glassEffect` surfaces were
/// real, but the window was opaque, so they sampled the app's own flat
/// background and nothing else. Behind-window blending is what makes the
/// backdrop actually be the desktop.
///
/// `.withinWindow` blending would sample the app's own content instead and
/// change nothing visible — and this view inside an opaque window blurs nothing
/// at all. The `NSVisualEffectView` and `NSWindow.isOpaque = false` are
/// worthless apart, which is the easy way to half-implement this.
struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        // Lets more of the desktop through than `.underWindowBackground`, which
        // is close to opaque and left the glass surfaces little to sample.
        //
        // Compared against a real desktop rather than picked from the docs.
        // `.hudWindow` is markedly more transparent — text in the window behind
        // stayed legible through the blur — but it carries a dark tint of its
        // own that sits on top of what the glass samples, flattening the
        // contrast the surfaces rely on. `.sidebar` is the most translucent
        // material that stays tint-neutral, which is the side of that trade
        // ADR-0006 argues for: the backdrop belongs under the glass, not in
        // competition with it.
        view.material = .sidebar
        // Keeps blurring when the app is not frontmost. A backdrop that goes
        // flat the moment you click elsewhere draws attention to itself.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Reaches the hosting `NSWindow` from SwiftUI.
///
/// SwiftUI exposes no way to set `isOpaque`, and without it the backdrop above
/// has nothing to blur. A zero-sized view that reports its window is the least
/// invasive route to it.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // `view.window` is nil during makeNSView; it is set once the view joins
        // the hierarchy, so this waits a turn rather than reading nil.
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
    }
}

extension NSWindow {
    /// Whether the desktop shows through.
    ///
    /// Off while presenting. A translucent window mid-talk means a projector
    /// showing fragments of the desktop, and a notification banner bleeding
    /// through behind the deck — the one place this app cannot afford to look
    /// unprofessional. Same asymmetry as the speaker notes: pleasant while
    /// working, off when a room is watching.
    func setBackdropTranslucent(_ translucent: Bool) {
        isOpaque = !translucent
        backgroundColor = translucent ? .clear : .windowBackgroundColor
    }

    /// Runs the backdrop up behind the title bar.
    ///
    /// The title bar is its own surface, and it does not inherit the window's
    /// material. With the window non-opaque it rendered as a clear strip of raw
    /// unblurred desktop sitting above a blurred body — the seam was the giveaway
    /// that the translucency was painted on rather than the window's own.
    ///
    /// `.fullSizeContentView` extends the content view under the title bar so
    /// `WindowBackdrop` covers it, and `titlebarAppearsTransparent` stops AppKit
    /// drawing its own bar on top. Both are needed: the first alone leaves the
    /// bar opaque over the backdrop, the second alone leaves nothing behind it.
    ///
    /// SwiftUI still insets content for the title bar's height, so the panes do
    /// not slide under the traffic lights.
    func extendBackdropUnderTitlebar() {
        titlebarAppearsTransparent = true
        styleMask.insert(.fullSizeContentView)
    }
}
