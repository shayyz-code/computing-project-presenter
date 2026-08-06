# ADR-0005: Developer ID with hardened runtime, App Sandbox off

**Status:** Accepted · 2026-08-06

## Context

The app ships to other people, so it must be signed and notarized — Gatekeeper blocks unsigned apps, and "right-click, Open" is not an install story.

That leaves the sandbox question. The app needs three capabilities that interact badly with sandboxing:

1. **Screen Recording** via ScreenCaptureKit — works sandboxed.
2. **Camera** for device capture — works sandboxed with `com.apple.security.device.camera`.
3. **Apple Events to Keynote** for `.pptx` conversion — the awkward one. A sandboxed app scripting another app needs `com.apple.security.temporary-exception.apple-events`, an entitlement whose name is a warning about its own longevity.

There is also `soffice`, invoked as a subprocess. A sandboxed app cannot execute an arbitrary Homebrew binary outside its container.

## Decision

**Developer ID distribution, hardened runtime on, App Sandbox off.**

Entitlements: `com.apple.security.device.camera`, `com.apple.security.automation.apple-events`.

## Consequences

The sandbox buys its security value mainly on the Mac App Store, which this app is not going to. Outside it, sandboxing here would cost a temporary-exception entitlement for Apple Events and break subprocess conversion entirely — real functionality lost for a boundary that is not being enforced against anything in particular. Hardened runtime plus notarization still gives Gatekeeper what it wants and users a signed, scannable binary.

**Not a permanent door closed.** Going to the Mac App Store later would mean dropping the LibreOffice backend, taking the Apple Events exception, and re-testing capture under the sandbox. Worth knowing that is the price rather than discovering it.

**Three permission prompts across first use** — Screen Recording, Camera, Apple Events — each at a different moment, each capable of being denied. First-run onboarding that explains them before macOS asks is part of the product, not polish. **A denied permission must produce an explaining UI state with a link to the right Settings pane; a blank pane is a bug.**

Notarization requires an Apple Developer account. CI builds unsigned (`CODE_SIGNING_ALLOWED=NO`) so contributors without one can still build and test.

## Alternatives

**Sandboxed + Mac App Store** — the widest-trust distribution, at the cost of the LibreOffice backend and a fragile entitlement. Reconsider only if `.pptx` fidelity stops depending on external converters.

**Unsigned, build-from-source only** — free, and fine for one machine. Contradicts the decision that this is distributable.
