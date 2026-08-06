# Architecture decision records

One decision per file: the context that forced it, what was decided, and what that costs. Consequences are the part worth writing — a decision without them is just a preference.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-project-structure.md) | SwiftUI app over SPM modules, committed project file | Accepted |
| [0002](0002-deck-rendering.md) | PDF-first rendering, converter chain for `.pptx` | **Provisional** — Keynote backend unverified |
| [0003](0003-mirroring-strategy.md) | One layer-vending `MirrorSource`, two capture backends | **Provisional** — device backend unverified |
| [0004](0004-concurrency.md) | Swift 6 language mode, isolation at the boundary | Accepted |
| [0005](0005-distribution.md) | Developer ID, hardened runtime, no App Sandbox | Accepted |

## Provisional means provisional

0002 and 0003 each rest on something not yet observed — whether Keynote's ScriptingBridge export is usable, and whether an unentitled app still sees a USB iPhone as an `AVCaptureDevice` on macOS 27. Each has a `type:spike` issue that resolves it and updates the ADR with what was actually seen.

Do not build on a provisional assumption before its spike lands.

## Changing one

Edit the ADR in the same PR as the code that contradicts it. A decision the codebase has quietly outgrown is worse than no decision, because it still reads as authoritative.
