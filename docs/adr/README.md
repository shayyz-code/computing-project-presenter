# Architecture decision records

One decision per file: the context that forced it, what was decided, and what that costs. Consequences are the part worth writing — a decision without them is just a preference.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-project-structure.md) | SwiftUI app over SPM modules, committed project file | Accepted |
| [0002](0002-deck-rendering.md) | PDF-first rendering, converter chain for `.pptx` | **Provisional** — Keynote backend unverified |
| [0003](0003-mirroring-strategy.md) | One layer-vending `MirrorSource`, two capture backends | Accepted — device backend verified by [#22](https://github.com/shayyz-code/computing-project-presenter/issues/22) |
| [0004](0004-concurrency.md) | Swift 6 language mode, isolation at the boundary | Accepted |
| [0005](0005-distribution.md) | Developer ID, hardened runtime, no App Sandbox | Accepted |

## Provisional means provisional

0002 still rests on something not yet observed: whether Keynote's ScriptingBridge export is usable, and at what fidelity. Its `type:spike` issue resolves it and updates the ADR with what was actually seen.

Do not build on a provisional assumption before its spike lands.

0003 was provisional on the same terms and is now Accepted — spike [#22](https://github.com/shayyz-code/computing-project-presenter/issues/22) measured the device path against real hardware. Worth noting how it went: the spike produced **three false negatives in a row**, each from a defect in the probe rather than a fact about the platform. A spike that reports "it doesn't work" deserves the same scrutiny as one that reports success, because a wrong negative quietly deletes a feature.

## Changing one

Edit the ADR in the same PR as the code that contradicts it. A decision the codebase has quietly outgrown is worse than no decision, because it still reads as authoritative.
