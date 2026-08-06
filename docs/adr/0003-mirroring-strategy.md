# ADR-0003: One layer-vending MirrorSource protocol, two capture backends

**Status:** Provisional · 2026-08-06 — the device backend is unverified. See *Open question* below.

## Context

The right pane must show a booted iOS Simulator and a USB-connected iOS device. macOS provides no way to embed another app's window inside ours, so both must be captured.

- **Simulator** — a window like any other. ScreenCaptureKit captures it.
- **Physical device** — a different mechanism entirely. Setting `kCMIOHardwarePropertyAllowScreenCaptureDevices` exposes connected iOS devices as CoreMediaIO DAL devices, which then appear to `AVCaptureDevice`. This is how QuickTime's "New Movie Recording" offers an iPhone as a source.

Two capture APIs producing two different frame types, feeding one view.

## Decision

A single protocol, **`@MainActor`-isolated, vending a `CALayer`**:

```swift
@MainActor
public protocol MirrorSource: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var kind: MirrorSourceKind { get }
    func start() async throws -> CALayer
    func stop() async
}
```

Backends: `SimulatorSource` and `WindowSource` over ScreenCaptureKit, feeding an `AVSampleBufferDisplayLayer`; `DeviceSource` over CoreMediaIO + `AVCaptureSession`, vending an `AVCaptureVideoPreviewLayer`. One `NSViewRepresentable` hosts whatever comes back.

## Consequences

Returning a layer rather than unifying on `AsyncStream<CMSampleBuffer>` is deliberate. The device path gets `AVCaptureVideoPreviewLayer` almost for free; routing it through `AVCaptureVideoDataOutput` purely to match the other backend's frame type would be more code for no benefit the host view can use.

`@MainActor` rather than `Sendable` is what makes this legal. Layers are main-thread bound; isolating the protocol keeps the layer from crossing an isolation boundary, which strict concurrency would otherwise reject.

The mirror is **read-only**. Clicks do not pass through to the Simulator, and cannot reach a physical device at all. Forwarding synthetic events to the Simulator is possible but out of scope; the presenter drives the device directly.

**The two kinds sit behind different permissions** — Screen Recording for capture, Camera for the device path, since AVFoundation treats it as a camera. `MirrorSourceKind.needsScreenRecordingPermission` encodes this so the UI sends people to the right System Settings pane.

## Open question

Apple has been narrowing DAL in favour of CoreMediaIO camera extensions, and the iOS-screen path has been special-cased for QuickTime before. **The constant existing in the macOS 26.5 SDK proves it compiles, not that an unentitled third-party app still sees a paired iPhone at runtime on macOS 27.**

A `type:spike` issue resolves this before any device code, and updates this ADR with what was observed.

**If the device path is closed**, the fallback is: the user opens QuickTime Player with the device as its movie-recording source, and we mirror *that window* through `WindowSource`. Clumsy, and it needs onboarding to explain — but it collapses everything to one backend and keeps the product's promise. The protocol above survives either outcome, which is why design does not wait on the spike.

## Alternatives

**Window choreography** — leave the Simulator in its own window and position it beside ours with the Accessibility API. Keeps interactivity and needs no capture permission, but does nothing for physical devices, breaks fullscreen presentation, and is fragile. Rejected: capture is required for devices regardless, so this would mean maintaining two unrelated mechanisms.

**Unifying on `CMSampleBuffer`** — one frame type everywhere, at the cost of a data-output pipeline on the device path that the host view gains nothing from.
