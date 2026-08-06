# ADR-0002: PDF-first deck rendering, with a converter chain for .pptx

**Status:** Provisional · 2026-08-06 — the Keynote backend is unverified. See *Open question* below.

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

**Keynote's UI launches when it is driven by Apple Events.** For a presenter app, another application's window appearing is worse than a permission prompt. It is survivable only because conversion happens at deck-open, never mid-presentation. If a spike shows this is uglier than expected, PDF-only for `.pptx`-without-LibreOffice is an acceptable retreat.

**Keynote is not guaranteed.** It ships with new Macs but is deletable. "Usually available" is the honest claim, which is why the error path names three remedies rather than two.

Apple Events requires `com.apple.security.automation.apple-events` and an `NSAppleEventsUsageDescription`, and prompts on first use. That prompt needs explaining in the UI, not just surfacing.

## Open question

The Keynote export path is **unverified**: whether ScriptingBridge export works as expected, what the fidelity is, and how intrusive the UI launch feels. A `type:spike` issue resolves this before M1 implementation, and updates this ADR with what was observed. Until then this decision is provisional.

## Alternatives

**Native OOXML renderer** — the only fully self-contained answer, and interesting in its own right, but it cannot reach usable fidelity in the time available. Not ruled out forever.

**Requiring LibreOffice** — simplest and highest fidelity, and the right call if this were a single-machine tool. The distribution decision rules it out.
