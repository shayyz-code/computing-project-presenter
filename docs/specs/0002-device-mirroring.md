# Spec 0002: Device mirroring

**Milestone:** M2 Mirror · **Module:** `MirrorKit` · **Decides:** [ADR-0003](../adr/0003-mirroring-strategy.md)

## Goal

Show a live iOS screen in the right pane — a booted Simulator or a USB-connected device — at a frame rate that makes a demo watchable.

> **Spike resolved.** `DeviceSource` is real: an unentitled app sees a USB iPhone at 13–40 fps, device-native resolution, no entitlement. See ADR-0003 for the measurements and for the three constraints that shape the implementation — the Continuity decoy, notification-driven arrival, and intermittent republication. The QuickTime-window fallback is retained for a device that will not come up, not as the primary path.

## Behaviour

### Discovering sources

Sources are listed live: booted Simulators, connected iOS devices, and an "other window" option. Booting a Simulator or plugging in a phone updates the list without a relaunch.

Each source has a stable `id` across refreshes, so a selection survives one disappearing and coming back.

### Capturing

- **Simulator / window** — ScreenCaptureKit into an `AVSampleBufferDisplayLayer`. Simulator windows are found by filtering `SCShareableContent` on **`com.apple.iphonesimulator`**.

  > This spec previously named `com.apple.CoreSimulator.SimulatorTrampoline`, which is wrong. That is the XPC service which *launches* the Simulator; it owns no windows, so filtering on it matches nothing. The symptom is an empty source list rather than an error, so it reads as "capture is broken" instead of "wrong identifier". Verified against a running Simulator, whose window is owned by `Simulator.app` (`com.apple.iphonesimulator`) and titled like `"iPhone 17 – iOS 26.4"`.

  Filter out zero-sized and untitled windows too — the Simulator owns chrome windows that are not the device, and capturing one gives a blank pane indistinguishable from a failure.

  **The Simulator must be visible.** A hidden app (⌘H) is not drawn, so capture starts cleanly and delivers zero frames with no error anywhere. Unhide it before capturing — `NSRunningApplication.unhide()` restores its windows without activating it, so focus stays with the presenter.

  **Treat "no first frame" as a failure.** Since a silent zero-frame stream is indistinguishable from success at the API level, the source waits for a first frame and reports an explanation if none arrives. Without that, every cause of this class — hidden app, another Space, anything future — presents as an unexplained black pane.

### Device framing

The Simulator window **includes the device chassis** — the iPhone 17 window is 435x929 around a smaller screen — so capturing the window gives the wrapped-device look for free, and the pane only has to avoid stretching it.

A physical device does not: CoreMediaIO vends the raw screen (1284x2778 measured in spike #22) with no chassis. Matching the Simulator's presentation on the device path (#25) therefore needs a synthetic frame drawn around the feed. That is a constraint on #25, not a task before it.
- **Device** — CoreMediaIO + `AVCaptureSession` into an `AVCaptureVideoPreviewLayer`.

Both vend a `CALayer` through `MirrorSource`, so one host view displays either.

### Presenting the image

Aspect-fit, never stretched — a distorted phone looks broken. Device rotation is followed without restarting capture. The pane letterboxes rather than cropping.

The mirror is read-only. Clicks do not pass through.

### Permissions

Screen Recording for Simulator and window capture; Camera for the device path. Different prompts, different Settings panes.

**A denied permission shows an explaining state with a button to the correct Settings pane.** Not a blank pane, not a spinner, not silence. This is the single most likely thing to go wrong on someone else's machine, and it is recoverable if the app says what happened.

### Losing a source

A Simulator shutting down or a cable being pulled mid-presentation surfaces `sourceDisappeared` and shows a "reconnect" state. It does not crash, hang, or silently freeze the last frame — a frozen frame is worse than an error, because the presenter keeps talking to a dead image.

## Acceptance criteria

- [ ] A booted Simulator appears in the source list within ~2s of booting
- [ ] Selecting it shows live video at ≥ 20 fps averaged over 10 s
- [ ] A USB-connected iPhone appears within ~3s of the property being set and mirrors live at ≥ 20 fps averaged over 10 s
- [ ] The source list offers the phone's **screen**, never its Continuity camera or Desk View
- [ ] A device that does not appear shows a retrying state, not a permanent "no device" — publication is intermittent after a previous session
- [ ] Rotating the device updates the image without restarting capture
- [ ] The image is aspect-correct at every pane width; letterboxed, never stretched or cropped
- [ ] Denying Screen Recording shows an explaining state with a working Settings link
- [ ] Denying Camera does the same, pointing at the **Camera** pane, not Screen Recording
- [ ] Shutting down a mirrored Simulator shows a reconnect state, not a frozen frame
- [ ] Unplugging a mirrored device does the same
- [ ] `stop()` releases the stream — no capture indicator persists after switching sources
- [ ] Switching sources ten times leaks neither memory nor capture sessions

## Testing

Almost none of this runs in CI: capture needs TCC grants and a GUI session. Tag and exclude, and verify by hand against the iPhone 17 Simulator and a physical device.

What *can* be tested in CI is the pure logic around it — `MirrorSourceKind` permission mapping, source-list diffing, id stability.

The leak criterion needs deliberate checking: switch sources repeatedly with Instruments attached, and confirm the macOS capture indicator disappears when it should.

## Out of scope

Input forwarding to the Simulator. Recording. Wireless device capture. Android.
