# Spike #16 — Keynote `.pptx` → PDF export

Answers: *can we drive Keynote via Apple Events to export a usable PDF from a `.pptx`?*

**Yes, but only if Keynote opens the file through LaunchServices first.** Result and consequences in [ADR-0002](../../docs/adr/0002-deck-rendering.md); working through on [issue #16](https://github.com/shayyz-code/computing-project-presenter/issues/16).

```bash
./convert.sh deck.pptx out.pdf
```

## The trap

`tell application "Keynote" to open POSIX file "…"` **does not work**, and fails in the worst available way. Keynote is sandboxed; a bare POSIX path carries no sandbox extension token, so it cannot read the file. It puts up a modal —

> "deck.pptx" can't be imported. The file couldn't be opened.

— and the AppleEvent **times out** instead of returning an error. First observation of this cost a 300-second hang with `-1712` and no indication of cause. Opening the same file with `open -a Keynote` succeeds immediately, which is what isolated the sandbox as the variable rather than the file.

So: open through LaunchServices (`NSWorkspace.open`), export through Apple Events. `open -g` keeps Keynote off the foreground — verified, the frontmost application is unchanged across a conversion.

## Measured

Three real decks, against slide counts read straight out of `ppt/presentation.xml` (`<p:sldId>` entries) so the ground truth depends on neither converter:

| Deck | Slides | Keynote pages | LibreOffice pages | Keynote total | LibreOffice (warm) |
|---|---|---|---|---|---|
| 8-slide talk | 8 | 8 | 8 | 3.1 s | 1.4 s |
| 7-slide template, embedded font | 7 | 7 | 7 | 2.3 s | 3.1 s |
| 53-slide lecture deck | 53 | 53 | 53 | 2.9 s | 6.0 s |

Keynote times include launching the app. LibreOffice's **first ever** invocation took **321 s** building its user profile; the 6.0 s figure is the same deck re-run warm.

## Fidelity

Equivalent for decks using system fonts — the 53-slide deck produced the same 14 embedded fonts from both converters and visually near-identical pages (Keynote resolves a slide-number field where LibreOffice resolves the header text).

They diverge when the `.pptx` **embeds** fonts under `ppt/fonts/*.fntdata`:

| | Source | LibreOffice | Keynote |
|---|---|---|---|
| Font | `Ballpoint` (embedded) | `BAAAAA+Ballpoint-Regular` | `AAAAAB+Helvetica` |

Keynote ignores the embedded font and substitutes. The substitute is wider, so text reflows — in the sample, three lines became five and overflowed the shape containing them. That is visibly broken on a projector, and it is the reason LibreOffice stays first in the chain.

Not one-sided: on the same slide LibreOffice dropped most of a vector arrow that Keynote drew correctly.

## Untested by construction

Behaviour with Keynote absent. It cannot be uninstalled here, so `canLoad` availability detection was verified positively — `NSWorkspace.urlForApplication(withBundleIdentifier: "com.apple.iWork.Keynote")` returns the path, and `open -Ra Keynote` is the shell equivalent used above — and the absent branch is asserted, not observed.

The Apple Events consent prompt was granted to the **terminal**, not to `Presenter.app`. A signed app bundle is a different TCC subject, so the prompt shipping users see is not the one seen here.
