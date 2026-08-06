# Spike #22 — CoreMediaIO device visibility

Answers: *does an unentitled app still see a USB iPhone as an `AVCaptureDevice` on macOS 27?*

**Yes.** Full result and its consequences are in [ADR-0003](../../docs/adr/0003-mirroring-strategy.md); the working through is on [issue #22](https://github.com/shayyz-code/computing-project-presenter/issues/22).

Spike code is not expected to survive, per `docs/CONTRIBUTING.md`. This one is kept because the ADR cites measurements that cannot otherwise be re-derived, and because the probe encodes three mistakes worth not repeating.

## Running it

```bash
swiftc -O probe.swift -o probe && ./probe
```

Deliberately built with `swiftc` rather than as part of the package: that yields an ad-hoc/linker-signed binary with no `Info.plist` and no entitlements, which is the condition under test. Building it as an app target would quietly grant it a bundle identity and invalidate the result.

Needs an iPhone **wired, paired, trusted and unlocked**. It is excluded from `make lint` and from CI, both of which only cover `Packages/` and `App/Presenter`.

## What it is careful about, and why

Three earlier versions of this probe produced **false negatives**, each from a different defect. If you modify it, preserve these:

1. **The wait services a run loop.** `RunLoop.current.run(until:)` rather than `Thread.sleep`, plus an explicit `wasConnectedNotification` observer. The device arrives 0.6–2.3 s after the property is set, so a fixed sleep followed by one enumeration is a race — it does sometimes succeed, which is precisely what made the failures look like platform behaviour rather than a timing bug.
2. **One `DiscoverySession` is retained across the whole wait.** Constructing a fresh one per poll iteration discards observation state.
3. **The device is identified by media type, not by name or model.** `hasMediaType(.muxed) && !isContinuityCamera`. A connected iPhone publishes three devices and the screen one is the *least* obvious — see the table in ADR-0003, where `modelID` is inverted from what anyone would guess.

A fourth thing to know rather than guard against: publication is intermittent right after a previous capture session is released. Back-to-back runs succeed about two times in three; leaving ~8 s between them succeeded every time.
