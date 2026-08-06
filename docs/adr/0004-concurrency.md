# ADR-0004: Swift 6 language mode, isolation at the boundary

**Status:** Accepted · 2026-08-06

## Context

Both halves of this app are concurrent by nature. Capture delivers frames on background queues owned by ScreenCaptureKit or AVFoundation. Deck conversion shells out to another process and must not block the UI. Both feed a SwiftUI view.

Swift 6 language mode makes data races a compile error rather than an intermittent bug at a bad moment.

## Decision

Swift 6 language mode across the package (`swift-tools-version: 6.0`) and the app target (`SWIFT_VERSION = 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).

Isolation is chosen per type by what the type actually touches:

- **Value types stay `Sendable`.** `Deck`, `Slide`, `SlideNavigator` are plain values that cross boundaries freely.
- **UIKit/AppKit-adjacent protocols are `@MainActor`.** `MirrorSource` vends a `CALayer`; main-actor isolation is what makes that legal rather than a fight with the compiler.
- **`DeckLoader` is `Sendable`** — it does off-main work and returns a value type.

## Consequences

`MirrorSource` being `@MainActor` means capture backends must hop to the main actor to hand over their layer. That is correct — it is where the layer belongs — but backends must not do frame-rate work there. Per-frame processing stays on the capture queue; only the layer handoff and lifecycle cross.

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the app target means SwiftUI code is main-isolated by default, which is where it should be. Package targets do not inherit this; they isolate explicitly.

Isolation is a design decision, not an annotation to sprinkle until it compiles. **`@unchecked Sendable` needs a comment explaining what makes it safe, or it should not be there.** Silencing a strict-concurrency error without understanding it converts a compile error into the runtime bug it was protecting against.

## Alternatives

**Swift 5 mode with warnings** — faster to write, defers the same work, and the failures land at runtime instead. For an app doing live capture in front of an audience, a compile-time guarantee is worth more than the time it costs.
