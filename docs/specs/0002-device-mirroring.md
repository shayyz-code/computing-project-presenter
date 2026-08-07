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

### Identity across a refresh

A source's `id` must survive it disappearing and returning, because a selection is remembered between launches. **A Simulator's `CGWindowID` does not survive** — quit and relaunch it and the id changes — so identity comes from the device name in the window title. A physical device keeps its `uniqueID`, which is already stable.

Discovery **polls**, roughly every two seconds. There is nothing to observe: `SCShareableContent` publishes no change notification, and `AVCaptureDevice.wasConnectedNotification` covers only the device half of the list.

### Rotation

A rotation is reconfigured, not restarted: `SCStream.updateConfiguration` keeps the stream alive, where a stop-and-start would drop frames, re-trigger the capture indicator and look like a reconnection. Detected by polling the window's shape, because no notification exists for a window resizing.

### Device framing

The Simulator window **includes the device chassis** — the iPhone 17 window is 435x929 around a smaller screen — so capturing the window gives the wrapped-device look for free, and the pane only has to avoid stretching it.

A physical device does not: CoreMediaIO vends the raw screen (1284x2778 measured in spike #22) with no chassis, so `DeviceChassis` draws one — a rounded body with the screen inset by a proportional bezel and concentric corner radii.

Deliberately geometry rather than artwork: no notch, no Dynamic Island, no per-model metrics. Those need real assets and a device database, and everything proportional means one implementation serves a 200pt pane and a projector alike.

**Only the device path is framed.** A Simulator window already contains its bezel; drawing another would put a phone inside a phone. The Simulator's *macOS window chrome* — title bar and toolbar — is cropped at the capture stage with `SCStreamConfiguration.sourceRect`, so the two sources read as the same kind of object without either being double-framed.
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

Run against an iPhone 13 Pro Max over USB and a booted iPhone 17 Simulator, 2026-08-07 — [#71](https://github.com/shayyz-code/sidecar/issues/71). A box is ticked only where something was *observed*; where a run produced no verdict it says so, because an untested criterion that reads as passing is worse than one that reads as failing.

- [ ] A booted Simulator appears in the source list within ~2s of booting
- [x] Selecting it shows live video at ≥ 20 fps averaged over 10 s — **38.1 fps**. Recorded the mirror pane at 60 fps under synthetic motion and counted non-duplicate frames with `ffmpeg mpdecimate`; 381 distinct frames in 10 s. Motion is required: ScreenCaptureKit delivers on change, so a still home screen legitimately produces almost none
- [x] A USB-connected iPhone appears within ~3s and mirrors at ≥ 20 fps over 10 s — **appeared in 0.15 s, 435 frames in 10 s = 43.5 fps** at 1284x2778, measured with `Spikes/22-coremediaio/probe.swift` widened to a 10 s window
- [x] The source list offers the phone's **screen**, never its Continuity camera or Desk View — the machine publishes **five** capture devices (`Shayy`, `Shayy Camera`, `Shayy Desk View Camera`, `FaceTime HD Camera`, `OBS Virtual Camera`) and the picker listed only `Shayy`
- [ ] A device that does not appear shows a retrying state, not a permanent "no device"
- [ ] Rotating the device updates the image without restarting capture — **no verdict.** The run was invalid: capture had already failed before the rotation, so the post-rotation error was [#81](https://github.com/shayyz-code/sidecar/issues/81), not a rotation failure. Must be re-run from a known-good stream
- [ ] The image is aspect-correct at every pane width; letterboxed, never stretched or cropped
- [ ] Denying Screen Recording shows an explaining state with a working Settings link
- [x] Denying Camera does the same, pointing at the **Camera** pane — reached by signing a hardened build *without* `com.apple.security.device.camera`, which is the only way to produce a denial without revoking a real grant
- [ ] Shutting down a mirrored Simulator shows a reconnect state, not a frozen frame
- [ ] Unplugging a mirrored device does the same
- [ ] `stop()` releases the stream — no capture indicator persists after switching sources. **Not measurable by screenshot**: taking one lights the indicator itself
- [ ] **FAILS** — switching sources ten times leaks neither memory nor capture sessions. Memory is clean (rss bounded and non-monotonic across 30 switches, `leaks` flat at 64 bytes). Capture sessions are not: after ~30 switches `SimulatorSource` stops producing frames and never recovers without restarting the app. [#81](https://github.com/shayyz-code/sidecar/issues/81)

## Testing

Almost none of this runs in CI: capture needs TCC grants and a GUI session. Tag and exclude, and verify by hand against the iPhone 17 Simulator and a physical device.

What *can* be tested in CI is the pure logic around it — `MirrorSourceKind` permission mapping, source-list diffing, id stability.

The leak criterion needs deliberate checking, and **memory instrumentation alone will pass it wrongly**. `leaks` stayed flat at 64 bytes and rss stayed bounded across 30 switches while capture was quietly dying — the handles are reachable, so nothing reports them as leaked. Check by *using* the app after N switches, not by reading a memory graph.

Two measurement traps found doing this, both of which produced confident wrong answers before being caught:

- **Screen-region capture records whatever is on top.** A `screencapture -R` of a window's frame silently returns the window in front of it. Capture by `CGWindowID` instead. The first frame-rate recording measured an editor sitting over the app.
- **An `NSAlert` is a separate window.** Enumerate *all* of a process's windows before concluding a dialog did not appear; a helper that grabs "the main window" will miss it and report a silent failure that is not there.

## Out of scope

Input forwarding to the Simulator. Recording. Wireless device capture. Android.
