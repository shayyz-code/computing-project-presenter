# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS app for presenting a software project: the deck renders in the left pane, a live iOS screen — Simulator or a USB-connected device — in the right. The point is that a demo is part of the deck rather than an alt-tab away from it.

Distributed to other people, not just built for one machine. That constraint drives several decisions below (converter choice, permission UX, no hard external dependencies).

## Commands

Run from the repo root. Every command here has been executed and works.

| Command | Does |
|---|---|
| `make bootstrap` | Resolve package dependencies |
| `make build` | Build `Presenter.app` (Debug, unsigned) into `.build/xcode` |
| `make test` | Run the whole package suite |
| `make lint` | Check formatting, changes nothing |
| `make format` | Reformat sources in place |
| `make run` | Build and launch |
| `make clean` | Remove build products |

Running a subset — `--filter` takes a regex matched against test IDs, so it accepts a target, a suite, or a single test:

```bash
swift test --package-path Packages/PresenterKit --filter "SlideKitTests"   # one target
swift test --package-path Packages/PresenterKit --filter "SlideNavigator"  # one suite
swift test --package-path Packages/PresenterKit --filter "jumpClamps"      # one test
```

Linting is `swift format`, which ships with the Swift 6 toolchain — there is no SwiftLint and nothing to install. `.swift-format` pins 4-space indentation because swift-format defaults to 2 while Xcode emits 4.

## Layout

```
Packages/PresenterKit/    all logic, as SPM library targets
  Sources/SlideKit/       decks: loading, conversion, page rendering
  Sources/MirrorKit/      the right pane: screen and device capture
  Sources/PresenterCore/  session state, navigation, persistence
App/
  Presenter.xcodeproj     one thin app target
  Presenter/              SwiftUI shell, entitlements
docs/{adr,specs}/
```

**Put logic in `Packages/`, not in the app target.** That is what lets `swift test` run the suite without Xcode-version coupling, and it keeps the `.pbxproj` static.

**The `.pbxproj` is committed on purpose.** The app target uses a `PBXFileSystemSynchronizedRootGroup`, so adding a Swift file under `App/Presenter/` is picked up automatically and never edits the project file. If you find yourself producing a large `.pbxproj` diff, something has gone wrong — check that before committing it.

## Things that will bite you

**PPTX slide order is not filename order.** It comes from `<p:sldIdLst>` in `ppt/presentation.xml`, resolved through `ppt/_rels/presentation.xml.rels`. Sorting `slide1.xml`, `slide2.xml`, … gives the wrong deck for any file where slides were reordered.

**PPTX notes are not mapped positionally.** `notesSlide1.xml` is not slide 1's notes as soon as any slide lacks notes. Resolve through each `ppt/slides/_rels/slideN.xml.rels`. `Deck` therefore keys slides by an author-facing `number`, never by array offset. Real numbers: one 53-slide deck had notes on 9 slides, with `notesSlide3.xml` belonging to slide 9.

**Not every zip entry in a `.pptx` is deflated.** A survey of 61 real decks found 1219 STORED entries alongside 8311 DEFLATE — and 82 of the STORED ones were `.xml`, the parts a reader actually fetches. `ZipArchive` switches on the compression method; an inflate-only reader returns garbage for those and reports no error.

**A PPTX fixture whose rIds sort into author order tests nothing.** `<p:sldId r:id="…">` cites relationship ids, and PowerPoint never renumbers them on reorder, so real rId order is arbitrary. If a fixture uses `rId1, rId2, rId3` in author order, a reader that sorts instead of honouring document order still passes. `Tests/SlideKitTests/Fixtures/make-fixtures.py` uses deliberately shuffled ids; verify a fixture can fail before trusting that it passes.

**Keynote will not open a file handed to it over Apple Events.** Keynote is sandboxed, and a bare POSIX path in `tell application "Keynote" to open POSIX file "…"` carries no sandbox extension token — Keynote raises a modal *"can't be imported. The file couldn't be opened."* and **the AppleEvent times out instead of returning an error**, so a naive caller hangs for its full timeout with only `-1712` to show. Open with `NSWorkspace.open` (LaunchServices passes the token), then use Apple Events only to export. Backgrounded (`open -g`) it does not steal focus. Probe in `Spikes/16-keynote/`.

**When Apple Events times out, look at what the app is showing.** Keynote reports nothing to the script while a modal is up. Read the dialog out of the accessibility tree — `System Events` → `every window whose subrole is "AXDialog"` → its `static text` — before concluding the operation is unsupported.

**A flipped `NSView` draws `CGImage`s upside down.** `isFlipped = true` gives top-left origin so layout arithmetic reads naturally, but `CGContext.draw(_:in:)` places images in bottom-left space — so every slide renders inverted. `SlidePane` flips about the drawn rect before drawing. This shipped undetected in #45 because rendering was only ever verified by sampling pixels in tests; **look at the app** before believing a rendering path works.

**`#expect` cannot contain a mutating call.** The macro expands its argument into a closure over an immutable binding, so `#expect(nav.advance())` fails to compile with "cannot use mutating member on immutable value". Bind the result first:

```swift
let advanced = nav.advance()
#expect(advanced)
```

**`MirrorSource` is `@MainActor`, not `Sendable`.** Every conformance vends a `CALayer`, and layers are main-thread bound; isolating the protocol keeps the layer from crossing an isolation boundary, which strict concurrency would otherwise reject.

**A hidden app produces no frames, and ScreenCaptureKit reports no error about it.** If the Simulator is hidden (⌘H) its windows still appear in `SCShareableContent`, still yield a valid `SCWindow`, and `SCContentFilter` plus `startCapture()` both succeed — but the window server is not drawing it, so `didOutputSampleBuffer` is never called and the pane sits black. `SimulatorSource` calls `NSRunningApplication.unhide()` first (which does *not* activate the app, so focus is kept) and then waits for a first frame, failing with an explanation if none arrives. **Diagnose "black pane" by checking frame delivery before suspecting the layer** — layer sizing, frame-status filtering and display-immediately were all investigated first and none of them was the cause.

**The Simulator's windows are owned by `com.apple.iphonesimulator`, not `SimulatorTrampoline`.** `com.apple.CoreSimulator.SimulatorTrampoline` is the XPC service that *launches* the Simulator and owns no windows, so filtering `SCShareableContent` on it matches nothing — and the symptom is an empty source list rather than an error, which reads as "capture is broken". Spec 0002 named the wrong one until #23. Also skip zero-sized and untitled windows: the Simulator owns chrome that is not the device, and capturing it gives a blank pane.

**A connected iPhone publishes three capture devices, and the screen is the least obvious one.** `Shayy Camera` and `Shayy Desk View Camera` are Continuity — the phone's *lens*. The screen device is bare `Shayy`, and its `modelID` is the literal string `iOS Device` while the **decoys** carry `iPhone14,3`. So `modelID.hasPrefix("iPhone")` picks exactly the wrong device and mirrors the room. All three report `.external`. The only correct test is `hasMediaType(.muxed) && !isContinuityCamera && deviceType != .deskViewCamera`.

**The device is published asynchronously, so enumerating once is a race.** After setting `kCMIOHardwarePropertyAllowScreenCaptureDevices`, the iPhone appears 0.6–2.3s later. A one-shot enumeration sometimes wins that race, which is worse than always losing — it produced intermittent false negatives during spike #22. Observe `AVCaptureDevice.wasConnectedNotification` with a serviced run loop (`RunLoop.current.run(until:)`, not `Thread.sleep`) and retain one `DiscoverySession` rather than rebuilding it per poll. Treat absence as transient: publication is flaky for a few seconds after a previous capture session is released.

**Screen Recording and Camera are different permissions.** Simulator and window capture go through ScreenCaptureKit (Screen Recording); physical device capture goes through AVFoundation (Camera). `MirrorSourceKind.needsScreenRecordingPermission` encodes this — getting it backwards sends the user to the wrong System Settings pane. A denied permission must produce an explaining UI state, never a blank pane.

## What CI can and cannot run

CI runs `swift test` over `Packages/` plus an `xcodebuild build`. It cannot run capture tests (they need TCC grants and a GUI session) or converter tests (they need `soffice` installed, or Keynote automation consent). Those are tagged and excluded. Do not try to make them run on a runner — verify them manually against the hardware.

## Workflow

Issues first, then a branch, then a small PR, then squash merge. The repo is squash-only with auto-delete-branch, and the squash commit takes the **PR title**, so PR titles must be valid conventional commits.

- Branches: `feat|fix|docs|chore/<issue#>-slug`
- Commit and PR title scopes: `slidekit`, `mirrorkit`, `core`, `app`, `docs`, `ci`, `claude`
- Every PR body carries `Closes #N`

Decisions live in `docs/adr/` and acceptance criteria in `docs/specs/`. If you are about to make an architectural choice that contradicts an ADR, update the ADR in the same PR rather than quietly diverging.

## Current state

M0 (foundations) only. `SlideKit` and `MirrorKit` contain declarations and no implementations — no deck loader and no capture backend exist yet.

**Both spikes are resolved and every ADR is Accepted**, so M1 and M2 can be built as designed.

- **CoreMediaIO.** An unentitled app *does* see a USB iPhone as an `AVCaptureDevice` on macOS 27: 13–40 fps at device-native resolution, no private entitlement needed. `DeviceSource` is real. Measurements and the three implementation constraints are in `docs/adr/0003-mirroring-strategy.md`; probe in `Spikes/22-coremediaio/`.
- **Keynote export.** Works, at exact slide counts and comparable speed to LibreOffice, provided the file is opened through LaunchServices rather than Apple Events. LibreOffice stays first in the chain because Keynote ignores fonts embedded in the `.pptx` and substitutes, which reflows text out of its shape. See `docs/adr/0002-deck-rendering.md`; probe in `Spikes/16-keynote/`.

Both were verified against a signed-app TCC subject **only by proxy** — consent was granted to the terminal, not to `Presenter.app`. Re-verify camera and Apple Events against a Developer ID, hardened-runtime build before M4 ships.
