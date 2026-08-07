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
        // Reads as the surface a window sits on, rather than as a sidebar or a
        // HUD — both of which carry their own tint and would fight the glass.
        view.material = .underWindowBackground
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
}
