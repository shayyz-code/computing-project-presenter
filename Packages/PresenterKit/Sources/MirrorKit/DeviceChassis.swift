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
/// Deliberately geometry rather than artwork. No notch, no Dynamic Island, no
/// per-model metrics — those need real assets and a device database, and a clean
/// bezel already reads as "a phone". Everything here is proportional to the
/// screen, so it is resolution-independent and has no device list to maintain.
public enum DeviceChassis {

    /// Bezel thickness as a fraction of the screen's short edge.
    ///
    /// Roughly matches a modern iPhone's borders. Proportional rather than fixed
    /// so it looks the same whether the pane is 200pt or 2000pt wide.
    public static let bezelRatio: CGFloat = 0.028

    /// Outer corner radius as a fraction of the short edge.
    public static let cornerRatio: CGFloat = 0.09

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
}
