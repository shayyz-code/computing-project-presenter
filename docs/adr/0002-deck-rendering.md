# ADR-0002: PDF-first deck rendering, with a converter chain for .pptx

**Status:** Accepted · 2026-08-06 — Keynote backend verified against real decks by spike [#16](https://github.com/shayyz-code/computing-project-presenter/issues/16). See *What the spike measured*.

## Context

macOS has no API that renders `.pptx`. The options are all indirect:

1. **Convert to PDF and render with PDFKit.** Needs a converter.
2. **Parse OOXML and draw it ourselves.** Fully native and dependency-free, but a research project on its own, and low fidelity for a long time.
3. **Quick Look thumbnails.** First page only. Not a deck.

Converters available on macOS:

- **LibreOffice** (`soffice --headless --convert-to pdf`) — good `.pptx` fidelity, but a ~1GB Homebrew install.
- **Keynote** via Apple Events — opens `.pptx` and exports PDF, and ships with new Macs.

The app is **distributed to other people**, which rules out requiring a LibreOffice install.

## Decision

A `DeckLoader` protocol with three backends, selected at runtime:

| Input | Backend |
|---|---|
| `.pdf` | `PDFDeckLoader` — passthrough |
| `.pptx` | `LibreOfficeDeckLoader` if `soffice` is present |
| `.pptx` | else `KeynoteDeckLoader` |
| neither available | a real error offering both remedies **plus "export your deck to PDF"** |

PDF passthrough is primary, not a fallback. It always works, needs nothing installed, and is the only path fully testable in CI.

Converted output is cached under `~/Library/Caches/`, keyed by file content hash.

## Consequences

Most people install nothing. Anyone who wants better fidelity installs LibreOffice and the app picks it up automatically. Nobody is stranded: exporting to PDF is a route out of any failure.

**Keynote's UI launches when it is driven by Apple Events** — but less badly than feared. Measured: with `open -g` it does not take focus, and it leaves no document open afterwards. See *What the spike measured*; the retreat to PDF-only is no longer needed on these grounds.

**Keynote is not guaranteed.** It ships with new Macs but is deletable. "Usually available" is the honest claim, which is why the error path names three remedies rather than two.

Apple Events requires `com.apple.security.automation.apple-events` and an `NSAppleEventsUsageDescription`, and prompts on first use. That prompt needs explaining in the UI, not just surfacing.

## What the spike measured

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

### Not observed

Behaviour with Keynote absent — it cannot be uninstalled here, so availability detection was verified positively (`NSWorkspace.urlForApplication(withBundleIdentifier:)` returns the path) and the absent branch is asserted, not observed. It needs a test double.

Apple Events consent was granted to the **terminal**, not to `Presenter.app`. A signed bundle is a different TCC subject, so the prompt shipping users see is not the one seen here — the same caveat that applies to the camera entitlement in ADR-0003.

## Alternatives

**Native OOXML renderer** — the only fully self-contained answer, and interesting in its own right, but it cannot reach usable fidelity in the time available. Not ruled out forever.

**Requiring LibreOffice** — simplest and highest fidelity, and the right call if this were a single-machine tool. The distribution decision rules it out.
