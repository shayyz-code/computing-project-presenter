import QuartzCore

/// Where a mirrored image comes from.
public enum MirrorSourceKind: String, CaseIterable, Sendable {
    /// A booted iOS Simulator window, captured with ScreenCaptureKit.
    case simulator
    /// A USB-connected iOS device, captured with CoreMediaIO + AVFoundation.
    case device
    /// Any other window on the system, chosen through `SCContentSharingPicker`.
    /// Also the fallback route for physical devices if the CoreMediaIO path is
    /// closed on this OS version — see ADR-0003.
    case window

    /// Whether this kind needs Screen Recording consent rather than Camera consent.
    public var needsScreenRecordingPermission: Bool {
        switch self {
        case .simulator, .window: true
        case .device: false
        }
    }
}

/// A live image that can be shown in the right-hand pane.
///
/// Main-actor isolated on purpose: every conformance ultimately vends a `CALayer`
/// (`AVSampleBufferDisplayLayer` for the ScreenCaptureKit paths,
/// `AVCaptureVideoPreviewLayer` for the device path), and layers are main-thread
/// bound. Isolating the protocol keeps the layer from crossing an isolation
/// boundary, which is what strict concurrency would otherwise reject.
@MainActor
public protocol MirrorSource: AnyObject {
    /// Stable across a discovery refresh, so the UI can keep a selection.
    var id: String { get }
    var displayName: String { get }
    var kind: MirrorSourceKind { get }

    /// Begins capture and returns the layer to display. Callers own presentation;
    /// the source owns the pixels.
    func start() async throws -> CALayer

    func stop() async
}

/// Why a mirror source could not start.
///
/// `permissionDenied` is deliberately distinct from the failure cases: a denied
/// TCC prompt is recoverable by the user, and the UI must say so rather than
/// showing an empty pane. See `docs/specs/0002-device-mirroring.md`.
public enum MirrorError: Error, Equatable, Sendable {
    case permissionDenied(MirrorSourceKind)
    case sourceDisappeared(id: String)
    case captureFailed(reason: String)
    case unsupportedOnThisSystem(reason: String)
}
