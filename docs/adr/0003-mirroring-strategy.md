# ADR-0003: One layer-vending MirrorSource protocol, two capture backends

**Status:** Accepted · 2026-08-06 — device backend verified against hardware by spike [#22](https://github.com/shayyz-code/computing-project-presenter/issues/22). See *What the spike measured*.

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

## What the spike measured

Resolved. Setting `kCMIOHardwarePropertyAllowScreenCaptureDevices` **still works on macOS 27**, and the device path is real. Measured against an iPhone 13 Pro Max (iOS 27) over USB, from a binary that was ad-hoc/linker-signed with **no entitlements and no `Info.plist`**:

| | |
|---|---|
| Appears after | 0.6 – 2.3 s |
| Frame rate | 13 – 40 fps |
| Resolution | 1284x2778 (device native) |
| Entitlement required | **none** |

**No entitlement is required.** That is the finding that decided shippability — QuickTime Player holds no CoreMediaIO or DAL entitlement either; its only temporary exceptions are FairPlay/DRM.

Reproduce with `Spikes/22-coremediaio/probe.swift`.

### Identifying the device — the decoy is the dangerous part

A connected iPhone publishes **three** capture devices, and the two wrong ones look more correct than the right one:

| Device | `localizedName` | `modelID` | muxed | `isContinuityCamera` |
|---|---|---|---|---|
| **screen — the one we want** | `Shayy` | `iOS Device` | yes | false |
| Continuity camera | `Shayy Camera` | `iPhone14,3` | no | **true** |
| Desk View | `Shayy Desk View Camera` | `iPhone14,3` | no | false |

The screen device's `modelID` is the literal string `iOS Device`; it is the *Continuity camera* that carries `iPhone14,3`. So `modelID.hasPrefix("iPhone")` selects **exactly the wrong device** — the phone's rear lens — and mirrors the room while the presenter talks over it. A name-prefix match hits all three, and all three report `deviceType == .external`, so device type discriminates nothing.

The only correct test:

```swift
device.hasMediaType(.muxed) && !device.isContinuityCamera && device.deviceType != .deskViewCamera
```

### Publication is asynchronous and occasionally fails

`DeviceSource` **must observe, not enumerate once.** Three constraints, all measured:

- The device arrives by notification (`AVCaptureDevice.wasConnectedNotification`) after the property is set — not synchronously. A one-shot enumeration is a race.
- The wait must service a run loop. A `Thread.sleep` loop receives no CoreFoundation notifications and never sees the device. This produced two false negatives during the spike before it was caught.
- Publication is **intermittent immediately after a previous capture session is released** — 2/3 back-to-back runs succeeded, 3/3 with an 8 s gap. Absence must be a transient, retryable state, never a permanent "no device" verdict.

Preconditions: wired, paired **and trusted**, unlocked. Note `devicectl`'s `Pairing State: paired` does **not** reflect the trust state screen capture needs — it read `paired` while capture was still unavailable.

## When the device will not come up

Retained deliberately, re-scoped. This is no longer "if the path is closed" — the path is open — but the preconditions above are all things a user can get wrong, and the intermittency is real.

The recovery is: the user opens QuickTime Player with the device as its movie-recording source, and we mirror *that window* through `WindowSource`. Clumsy, and it needs onboarding to explain — but it collapses to one backend and keeps the product's promise. It is a documented fallback for a stuck device, not the primary path.

## Alternatives

**Window choreography** — leave the Simulator in its own window and position it beside ours with the Accessibility API. Keeps interactivity and needs no capture permission, but does nothing for physical devices, breaks fullscreen presentation, and is fragile. Rejected: capture is required for devices regardless, so this would mean maintaining two unrelated mechanisms.

**Unifying on `CMSampleBuffer`** — one frame type everywhere, at the cost of a data-output pipeline on the device path that the host view gains nothing from.
