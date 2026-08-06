import CoreGraphics
import Foundation
import ScreenCaptureKit

/// The part of a capturable window that source selection cares about.
///
/// A value type rather than `SCWindow` so the selection rules below can be
/// tested without a GUI session or Screen Recording consent — neither of which
/// CI has. `SimulatorSource` maps the real `SCWindow` list into these, picks
/// one, then finds the original by `id`.
public struct CapturableWindow: Equatable, Sendable, Identifiable {
    public let id: CGWindowID
    public let title: String?
    public let bundleIdentifier: String?
    public let width: Int
    public let height: Int

    public init(
        id: CGWindowID, title: String?, bundleIdentifier: String?, width: Int, height: Int
    ) {
        self.id = id
        self.title = title
        self.bundleIdentifier = bundleIdentifier
        self.width = width
        self.height = height
    }
}

/// Finding the Simulator's device window among everything on screen.
public enum SimulatorWindows {
    /// The bundle identifier of the app that owns Simulator device windows.
    ///
    /// **Not `com.apple.CoreSimulator.SimulatorTrampoline`.** That is the XPC
    /// service which *launches* the Simulator; it owns no windows, so filtering
    /// on it matches nothing — and the symptom is an empty source list rather
    /// than an error, which reads as "capture is broken" instead of "wrong
    /// identifier". Verified against a running Simulator: the process is
    /// `Simulator.app`, whose bundle id is the constant below.
    public static let bundleIdentifier = "com.apple.iphonesimulator"

    /// Every Simulator device window in `windows`, largest first.
    ///
    /// Largest first because the Simulator also owns small helper windows and
    /// the device is the big one; with several simulators booted, all of them
    /// are returned so #24 can list them.
    ///
    /// Known limitation: the Simulator's **"Apple TV Remote"** companion window
    /// is titled and non-zero, so it survives this filter and appears as a
    /// source. Ordering by area keeps the real device first — measured 435x929
    /// against the remote's 155x515 — so taking the first is correct today. A
    /// real source list (#24) needs a better discriminator than size.
    public static func devices(in windows: [CapturableWindow]) -> [CapturableWindow] {
        windows
            .filter { $0.bundleIdentifier == bundleIdentifier }
            // Zero-sized and untitled windows are the Simulator's own chrome,
            // not a device. Capturing one gives a blank pane that looks like a
            // capture failure.
            .filter { $0.width > 0 && $0.height > 0 }
            .filter { !($0.title ?? "").isEmpty }
            .sorted { $0.width * $0.height > $1.width * $1.height }
    }

    /// A window's title is the only place the device identity appears —
    /// `SCWindow` has no concept of a simulator. Titles look like
    /// `"iPhone 17 – iOS 26.4"`.
    public static func displayName(for window: CapturableWindow) -> String {
        let title = (window.title ?? "").trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? "Simulator" : title
    }
}

extension MirrorError {
    /// Maps a ScreenCaptureKit failure onto something the UI can act on.
    ///
    /// The distinction that matters is **denied permission versus anything
    /// else**: they need different remedies and different Settings panes, and
    /// `MirrorSourceKind.needsScreenRecordingPermission` exists precisely so the
    /// UI can send the user to the right one. `SCStream` reports denial as an
    /// error *code* in its own domain rather than a distinct type, so the code
    /// has to be read.
    public static func from(_ error: Error, kind: MirrorSourceKind) -> MirrorError {
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain else {
            return .captureFailed(reason: nsError.localizedDescription)
        }

        switch nsError.code {
        case -3801, -3803:
            // UserDeclined, MissingEntitlements. Recoverable by the user, and
            // the only cases where pointing at System Settings helps.
            return .permissionDenied(kind)
        case -3815, -3817, -3821:
            // NoCaptureSource, UserStopped, SystemStoppedStream — the window
            // went away. Not a failure to fix; a source to reconnect to.
            return .sourceDisappeared(id: "\(nsError.code)")
        default:
            return .captureFailed(reason: nsError.localizedDescription)
        }
    }
}
