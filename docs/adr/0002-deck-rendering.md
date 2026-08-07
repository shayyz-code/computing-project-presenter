# ADR-0002: PDF-first deck rendering, LibreOffice for .pptx

**Status:** Accepted · 2026-08-06 · **amended 2026-08-07** — the Keynote backend was removed, [#79](https://github.com/shayyz-code/sidecar/issues/79). See *Why Keynote was dropped*. Spike [#16](https://github.com/shayyz-code/sidecar/issues/16)'s measurements are kept below because they are largely what justified removing it.

## Context

macOS has no API that renders `.pptx`. The options are all indirect:

1. **Convert to PDF and render with PDFKit.** Needs a converter.
2. **Parse OOXML and draw it ourselves.** Fully native and dependency-free, but a research project on its own, and low fidelity for a long time.
3. **Quick Look thumbnails.** First page only. Not a deck.

Converters available on macOS:

- **LibreOffice** (`soffice --headless --convert-to pdf`) — good `.pptx` fidelity, but a ~1GB Homebrew install.
- **Keynote** via Apple Events — opens `.pptx` and exports PDF, and ships with new Macs.

The app was originally **distributed to other people**, which ruled out requiring a LibreOffice install. That premise has since changed — see *Why Keynote was dropped*.

## Decision

A `DeckLoader` protocol with two backends, selected at runtime:

| Input | Backend |
|---|---|
| `.pdf` | `PDFDeckLoader` — passthrough |
| `.pptx` | `LibreOfficeConverter` if `soffice` is present |
| neither available | a real error naming **two** remedies: install LibreOffice, or export the deck to PDF |

PDF passthrough is primary, not a fallback. It always works, needs nothing installed, and is the only path fully testable in CI.

Converted output is cached under `~/Library/Caches/`, keyed by file content hash.

`PPTXDeckLoader` still takes a *list* of converters. One ships; the list is the injection point the tests use, and adding a second backend should be a change of contents rather than of shape.

## Consequences

**A `.pptx` needs LibreOffice.** That is a real cost and the error path has to carry it — naming the `brew` command, not just the concept. Exporting to PDF remains the route out of any failure, and needs nothing installed.

**Fidelity is now one thing rather than two.** Whatever LibreOffice renders is what the presenter sees, on every machine. The previous chain could silently produce a *different, worse* result depending on what happened to be installed — which is the failure mode you discover on a projector.

## Why Keynote was dropped

Keynote was the no-install fallback. Removing it in [#79](https://github.com/shayyz-code/sidecar/issues/79) rests on one premise change and three measurements.

**The premise.** This ADR justified Keynote with *"the app is distributed to other people."* [ADR-0005](0005-distribution.md) now records that there is no Apple Developer Program enrollment, so there is no notarized download — the install path is `git clone && make run`. That audience already has Xcode 26. `brew install --cask libreoffice` is a far smaller ask of them than of someone opening a DMG. The fallback was built for a user who no longer exists.

**It cannot import every valid `.pptx`.** Keynote refuses this project's own deck outright — *"The file format is invalid"* — while LibreOffice converts the same file without complaint ([#77](https://github.com/shayyz-code/sidecar/issues/77)). A fallback that fails on the deck you actually have is not a fallback.

**It degrades output silently.** Measured in spike #16 and recorded below: Keynote ignores fonts embedded under `ppt/fonts/*.fntdata` and substitutes. Text reflows, and in the sample three lines became five and overflowed their shape. Nothing warns anyone; it just looks wrong on a projector.

**It cost a permission and a failure mode.** A third TCC prompt, an entitlement, an `NSAppleEventsUsageDescription`, and a LaunchServices-then-Apple-Events ordering whose correctness was load-bearing. When Keynote raised a modal the script could not see, the app sat on a spinner while the event ran toward a 300s timeout ([#76](https://github.com/shayyz-code/sidecar/issues/76)).

A footnote for anyone tempted to restore it: the `com.apple.security.automation.apple-events` entitlement turned out **not to be checked** on the send path — measured four ways in [#71](https://github.com/shayyz-code/sidecar/issues/71). Automation consent is what gates it. So the entitlement was never buying what this ADR claimed it was.

## What the spike measured

> **Historical.** This section describes the Keynote backend as it existed before [#79](https://github.com/shayyz-code/sidecar/issues/79) removed it. Nothing here describes current code — `KeynoteConverter` is gone. It is kept because the fidelity and timing numbers are what justified the removal, and because a future reader proposing to add Keynote back deserves to find the measurements rather than repeat the spike.

Resolved. Keynote exports `.pptx` to PDF correctly and quickly — **but only if Keynote opens the file through LaunchServices first.**

### The Apple Events open does not work, and fails silently

`tell application "Keynote" to open POSIX file "…"` fails. Keynote is sandboxed and a bare POSIX path carries no sandbox extension token, so it cannot read the file. It raises a modal — *"deck.pptx" can't be imported. The file couldn't be opened.* — and **the AppleEvent times out rather than returning an error**. First encounter cost a 300-second hang with `-1712` and no indication of cause.

`KeynoteDeckLoader` must therefore open with `NSWorkspace.open(_:withApplicationAt:configuration:)` and use Apple Events **only** for the export. `open -g` equivalence matters too: with it, the frontmost application is unchanged across a conversion.

**This substantially weakens the "Keynote's UI launches" consequence recorded below.** Keynote does launch, but it does not take focus and it leaves no document open afterwards.

### Correctness and speed

Slide counts were checked against `<p:sldId>` entries read straight out of `ppt/presentation.xml`, so ground truth depends on neither converter. Three real decks, all exact — 8/8, 7/7, 53/53.

| | Keynote | LibreOffice |
|---|---|---|
| 8-slide talk | 3.1 s | 1.4 s |
| 7-slide template | 2.3 s | 3.1 s |
| 53-slide lecture deck | 2.9 s | 6.0 s |

Keynote's figures include launching the app. LibreOffice's **first ever** invocation took **321 s** creating its user profile — that is what a new user pays on their first deck-open, and it is why spec 0001's progress requirement is not optional.

### Fidelity: equivalent until the deck embeds fonts

For decks using system fonts the two are equivalent — the 53-slide deck yielded the same 14 embedded fonts from both, and visually near-identical pages.

They diverge when the `.pptx` embeds fonts under `ppt/fonts/*.fntdata`:

| Source | LibreOffice | Keynote |
|---|---|---|
| `Ballpoint`, embedded | `BAAAAA+Ballpoint-Regular` | `AAAAAB+Helvetica` |

**Keynote ignores embedded fonts and substitutes.** The substitute is wider, text reflows, and in the sample three lines became five and overflowed their shape — visibly broken on a projector. This is the concrete reason LibreOffice stays ahead of Keynote in the chain rather than a general assumption about fidelity.

Not one-sided: on that same slide LibreOffice dropped most of a vector arrow that Keynote drew correctly.

### Not observed at the time — both since resolved

Behaviour with Keynote absent was asserted rather than observed. Moot now: the backend is gone, and `PPTXDeckLoader` takes injected converters, so the empty-chain branch is covered by a test double rather than by the ambient machine.

Apple Events consent had been granted to the **terminal**, not to the app bundle, so the prompt shipping users would see was not the one measured. Resolved in [#71](https://github.com/shayyz-code/sidecar/issues/71) against a hardened, signed build with the app as the TCC subject — and it produced the finding that killed the backend's last justification: the entitlement is not checked on the send path at all.

## Alternatives

**Native OOXML renderer** — the only fully self-contained answer, and interesting in its own right, but it cannot reach usable fidelity in the time available. Not ruled out forever, and it is now the *only* route to opening a `.pptx` with nothing installed.

**Keeping Keynote as a fallback** — what this ADR originally decided. Removed in [#79](https://github.com/shayyz-code/sidecar/issues/79); the reasoning is under *Why Keynote was dropped*. Reconsider if the app is ever distributed as a notarized download again, since that restores the premise — but not before [#77](https://github.com/shayyz-code/sidecar/issues/77) explains why Keynote refuses valid decks.
