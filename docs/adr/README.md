# Architecture decision records

One decision per file: the context that forced it, what was decided, and what that costs. Consequences are the part worth writing — a decision without them is just a preference.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-project-structure.md) | SwiftUI app over SPM modules, committed project file | Accepted |
| [0002](0002-deck-rendering.md) | PDF-first rendering, converter chain for `.pptx` | Accepted — Keynote backend verified by [#16](https://github.com/shayyz-code/computing-project-presenter/issues/16) |
| [0003](0003-mirroring-strategy.md) | One layer-vending `MirrorSource`, two capture backends | Accepted — device backend verified by [#22](https://github.com/shayyz-code/computing-project-presenter/issues/22) |
| [0004](0004-concurrency.md) | Swift 6 language mode, isolation at the boundary | Accepted |
| [0005](0005-distribution.md) | Developer ID, hardened runtime, no App Sandbox | Accepted |

## Provisional means provisional

Nothing is provisional now. Both spikes have landed — [#16](https://github.com/shayyz-code/computing-project-presenter/issues/16) (Keynote export) and [#22](https://github.com/shayyz-code/computing-project-presenter/issues/22) (CoreMediaIO device capture) — and each updated its ADR with what was actually observed rather than what was expected.

Do not build on a provisional assumption before its spike lands. If a future ADR goes provisional, it names its spike here.

Both spikes are worth reading for how they failed before they succeeded:

- **#22 produced three false negatives in a row**, every one a defect in the probe rather than a fact about the platform. A spike reporting "it doesn't work" deserves the same scrutiny as one reporting success — a wrong negative quietly deletes a feature.
- **#16's first attempt hung for 300 seconds** and reported only `-1712`. The cause was a modal dialog Keynote had raised where the script could not see it. When automation times out, look at what the app is *showing* before concluding what it cannot *do*.

## Changing one

Edit the ADR in the same PR as the code that contradicts it. A decision the codebase has quietly outgrown is worse than no decision, because it still reads as authoritative.
