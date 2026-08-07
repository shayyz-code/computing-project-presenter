# ADR-0005: Developer ID with hardened runtime, App Sandbox off

**Status:** Accepted · 2026-08-06 · **amended 2026-08-07** — there is no Apple Developer Program enrollment, so nothing is signed for distribution or notarized. **Build from source is the only install path.** See *What enrollment blocks, measured*. The decision below stands as intent, not as what ships.

## Context

The app ships to other people, so it must be signed and notarized — Gatekeeper blocks unsigned apps, and "right-click, Open" is not an install story.

That leaves the sandbox question. The app needs three capabilities that interact badly with sandboxing:

1. **Screen Recording** via ScreenCaptureKit — works sandboxed.
2. **Camera** for device capture — works sandboxed with `com.apple.security.device.camera`.
3. ~~**Apple Events to Keynote** for `.pptx` conversion~~ — moot since [#79](https://github.com/shayyz-code/sidecar/issues/79) removed the Keynote backend. Nothing sends Apple Events now, which is one fewer entitlement and one fewer prompt.

There is also `soffice`, invoked as a subprocess. A sandboxed app cannot execute an arbitrary Homebrew binary outside its container.

## Decision

**Developer ID distribution, hardened runtime on, App Sandbox off** — as intent. Blocked on enrollment; see below.

Entitlement: `com.apple.security.device.camera`, and only that. Verified load-bearing in [#71](https://github.com/shayyz-code/sidecar/issues/71) — a hardened build signed without it is denied and lands in the "Camera access is off" state. Bundle identifier `com.codewithshayy.sidecar` — see [ADR-0006](0006-design-language.md) for why it was settled before notarisation.

## What enrollment blocks, measured

There is no paid Apple Developer Program account, so there is no Developer ID certificate and no notarization. This is not a matter of configuration; it is a purchase.

The one certificate on the development machine is a free-Apple-ID **Apple Development** identity. It signs, and it enables the hardened runtime — which is what made the entitlement verification in #71 possible. It does **not** satisfy Gatekeeper:

```
$ spctl -a -vv Sidecar.app
Sidecar.app: rejected
origin=Apple Development: … (8DZ7UT2AYX)
```

The signature is valid on disk and satisfies its own Designated Requirement. Gatekeeper still refuses it, because assessment wants a Developer ID chain plus a notarization ticket. So a downloaded build would be blocked regardless of how carefully it was signed. **That is measured, not inferred from "no enrollment".**

**Therefore: build from source.** `git clone && make run`. It needs Xcode 26, which is a real cost, but it is honest — no quarantine workaround to talk anyone through, and nothing that trains a user to bypass Gatekeeper.

That narrowed audience is also what made [#79](https://github.com/shayyz-code/sidecar/issues/79) correct: ADR-0002 kept a Keynote fallback so that people who install nothing could still open a `.pptx`. Someone who has already installed Xcode can run one `brew` command.

**The configuration stays.** `ENABLE_HARDENED_RUNTIME = YES`, the camera entitlement, and the usage strings are all still in place, and `make build-signed` exercises them. Enrolling later is a signing change, not a redesign.

One thing enrollment will still owe: hardened runtime turns on **library validation**, so a Debug-configuration build aborts at launch with `Library not loaded: @rpath/Sidecar.debug.dylib` unless nested dylibs are signed with the same identity first. `make build-signed` does this. A release pipeline must too.

## Consequences

The sandbox buys its security value mainly on the Mac App Store, which this app is not going to. Outside it, sandboxing would break subprocess conversion entirely — real functionality lost for a boundary that is not being enforced against anything in particular.

**Not a permanent door closed.** Going to the Mac App Store later would mean dropping the LibreOffice backend and re-testing capture under the sandbox. Cheaper than it was: with Keynote gone there is no Apple Events exception to take.

**Two permission prompts across first use** — Screen Recording and Camera. Was three; Apple Events left with the Keynote backend. Each arrives at a different moment and each can be denied. **A denied permission must produce an explaining UI state with a link to the right Settings pane; a blank pane is a bug.** Both denial states are implemented and were confirmed on screen in #71 — the Camera one by signing without the entitlement, which is the only way to reach it.

**TCC grants are keyed to the signing identity**, not to the binary hash. Measured in #71: re-signing with a different identity re-prompts for Screen Recording, while dozens of ad-hoc rebuilds under one identity never did. Anyone changing how the app is signed should expect every user to re-grant.

`make build` stays unsigned (`CODE_SIGNING_ALLOWED=NO`) so CI, which has no certificate, can still build. Signing lives in `make build-signed`.

**The audience is narrower than "anyone with a Mac".** [ADR-0006](0006-design-language.md) sets the floor at macOS 26.0 to adopt Liquid Glass, so macOS 15 users cannot run this at all. That was chosen knowingly; it is recorded here because "distributed to other people" is this ADR's premise and it now means fewer people.

## Alternatives

**Sandboxed + Mac App Store** — the widest-trust distribution, at the cost of the LibreOffice backend. Reconsider only if `.pptx` rendering stops depending on an external converter, which realistically means the native OOXML renderer in ADR-0002.

**Ad-hoc signed DMG with documented quarantine removal** — reaches people without Xcode. Rejected: it means talking every user through `xattr -dr com.apple.security.quarantine`, which is both a bad first impression and a habit worth not teaching. Build-from-source asks more but lies about nothing.

**~~Unsigned, build-from-source only~~** — recorded here as rejected, on the grounds that it "contradicts the decision that this is distributable." It is now what ships. The premise changed rather than the reasoning being wrong: without enrollment, distributable was never on the table.
