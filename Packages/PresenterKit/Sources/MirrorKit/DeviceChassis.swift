import CoreGraphics
import Foundation

/// Geometry for drawing a device around a screen feed.
///
/// A Simulator window already contains its own chassis — the iPhone 17 window is
/// 435x929 around a smaller screen — so capturing the window gives the wrapped
/// device for free. A physical device does not: CoreMediaIO vends the raw screen
/// (1284x2778 measured in spike #22) with nothing around it. This is what makes
/// the two read as the same kind of object.
///
/// Deliberately geometry rather than artwork. **No notch and no Dynamic
/// Island** — those need real assets and a device database, and their absence
/// costs nothing because the mirrored screen already draws its own status bar.
/// Everything here is proportional, so it is resolution-independent and has no
/// device list to maintain.
///
/// The proportions are **measured from the Simulator's own chassis** rather than
/// chosen, so the two sources read as the same object. Taken from an iPhone 17
/// Simulator window at 2x: body 828x1714 px, screen inset 31 px, outer corner
/// radius 134 px, four side buttons. Re-measure against a Simulator screenshot
/// if these ever look wrong; do not tune them by eye.
public enum DeviceChassis {

    /// Bezel thickness as a fraction of the chassis' short edge.
    ///
    /// 31/828 measured. The rim below is drawn *inside* this, not added to it.
    public static let bezelRatio: CGFloat = 0.0374

    /// Outer corner radius as a fraction of the short edge.
    ///
    /// 134/828 measured. Much rounder than it looks like it should be — the
    /// earlier 0.09 was guessed, and read as a tablet rather than a phone.
    public static let cornerRatio: CGFloat = 0.1618

    /// A slightly lighter edge on the body, as a fraction of the short edge.
    ///
    /// The Simulator's chassis is not flat black: it has a ~5 px grey rim around
    /// a black bezel. Drawn as a layer border, which insets *inward* from the
    /// body edge, so it consumes part of `bezelRatio` rather than adding to it.
    public static let rimRatio: CGFloat = 0.006

    /// One of the buttons on the side of the phone.
    public struct SideButton: Sendable, Equatable {
        public enum Edge: Sendable, Equatable { case left, right }

        public let edge: Edge
        /// Distance from the **top** of the chassis, as a fraction of its height.
        public let start: CGFloat
        /// Length along the edge, as a fraction of chassis height.
        public let length: CGFloat
    }

    /// How far a button stands proud of the body, as a fraction of the short edge.
    public static let buttonDepthRatio: CGFloat = 0.010

    /// Action button, volume pair, and power — measured off the Simulator.
    ///
    /// Ordered top to bottom. The action button is the short one; on the right
    /// side the single long button is power.
    public static let sideButtons: [SideButton] = [
        SideButton(edge: .left, start: 0.169, length: 0.035),
        SideButton(edge: .left, start: 0.238, length: 0.068),
        SideButton(edge: .left, start: 0.326, length: 0.068),
        SideButton(edge: .right, start: 0.282, length: 0.110),
    ]

    /// The chassis rect for a screen of `aspect` fitted into `bounds`.
    ///
    /// The chassis is what gets fitted — the screen is then inset within it — so
    /// the whole device is always visible rather than its edges being cropped
    /// away by the pane.
    public static func chassisRect(screenAspect aspect: CGFloat, in bounds: CGRect) -> CGRect {
        guard aspect > 0, aspect.isFinite, bounds.width > 0, bounds.height > 0 else { return .zero }

        // The chassis is the screen plus a bezel on every side, so it is slightly
        // wider and taller in the same proportion.
        let shortEdgeIsWidth = aspect < 1
        let bezelFraction = bezelRatio * 2
        let chassisAspect =
            shortEdgeIsWidth
            ? (1 + bezelFraction) / ((1 / aspect) + bezelFraction * aspect)
            : aspect

        let outerAspect = shortEdgeIsWidth ? chassisAspect : aspect
        let paneAspect = bounds.width / bounds.height
        let size: CGSize =
            outerAspect > paneAspect
            ? CGSize(width: bounds.width, height: bounds.width / outerAspect)
            : CGSize(width: bounds.height * outerAspect, height: bounds.height)

        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width, height: size.height)
    }

    /// Where the screen sits inside a chassis.
    public static func screenRect(inChassis chassis: CGRect) -> CGRect {
        guard !chassis.isEmpty else { return .zero }
        let bezel = min(chassis.width, chassis.height) * bezelRatio
        return chassis.insetBy(dx: bezel, dy: bezel)
    }

    /// Outer corner radius for a chassis of this size.
    public static func cornerRadius(forChassis chassis: CGRect) -> CGFloat {
        min(chassis.width, chassis.height) * cornerRatio
    }

    /// Inner (screen) corner radius.
    ///
    /// Concentric with the outer curve — inner radius equals outer minus the
    /// bezel — which is what stops the corners looking subtly wrong.
    public static func screenCornerRadius(forChassis chassis: CGRect) -> CGFloat {
        let bezel = min(chassis.width, chassis.height) * bezelRatio
        return max(0, cornerRadius(forChassis: chassis) - bezel)
    }

    /// Rim thickness for a chassis of this size, never thicker than the bezel it
    /// is drawn inside.
    public static func rimWidth(forChassis chassis: CGRect) -> CGFloat {
        let short = min(chassis.width, chassis.height)
        return min(short * rimRatio, short * bezelRatio)
    }

    /// Where each side button sits, in the same space as `chassis`.
    ///
    /// **`start` is measured from the top of the chassis**, so the arithmetic
    /// runs from `maxY` downward. `LayerHostView` is not flipped, so y grows
    /// upward there; getting this backwards puts the volume buttons by the
    /// speaker, which is precisely the class of mistake that shipped upside-down
    /// slides in #45.
    public static func buttonRects(forChassis chassis: CGRect) -> [CGRect] {
        guard !chassis.isEmpty else { return [] }
        let depth = max(1, min(chassis.width, chassis.height) * buttonDepthRatio)

        return sideButtons.map { button in
            let height = chassis.height * button.length
            let y = chassis.maxY - chassis.height * (button.start + button.length)
            let x = button.edge == .left ? chassis.minX - depth : chassis.maxX
            return CGRect(x: x, y: y, width: depth, height: height)
        }
    }
}
