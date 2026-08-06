# ADR-0006: Liquid Glass, and macOS 26 as the floor

**Status:** Accepted · 2026-08-06

## Context

A presenter app is on screen for an hour with an audience watching. The chrome around the deck should recede — the deck is the content, everything else is scaffolding. Translucent materials are exactly the affordance for that: present enough to find, quiet enough to ignore.

macOS 26 ships Liquid Glass as the system answer. `NSGlassEffectView` and `NSGlassEffectContainerView` in AppKit, `.glass` and `.glassProminent` button styles in SwiftUI. Using it means the app looks like the OS instead of like an approximation of it, and it means not hand-rolling blur that will look dated the moment the system moves on.

**But every one of those APIs is `macOS 26.0`, and the app currently targets macOS 15.0.** That is the decision this ADR exists for. Adopting Liquid Glass is not a styling choice that can be made view by view; it is a platform floor.

## Decision

**Adopt Liquid Glass as the app's visual language. Raise the minimum to macOS 26.0.**

- `Packages/PresenterKit/Package.swift` — `platforms: [.macOS(.v26)]`
- `App/Presenter.xcodeproj` — `MACOSX_DEPLOYMENT_TARGET = 26.0`, both configurations

No `if #available` branching. One code path, one look.

## Consequences

**People on macOS 15 cannot run the app at all.** Not a degraded appearance — it will not launch. This is the price of the decision and it is worth stating without softening, because ADR-0005 commits to distributing this to other people and this narrows who "other people" can be. It was chosen over availability branching deliberately: two visual paths means the fallback is what most users would actually see, and it is the path least likely to be tested.

**No dual-path UI.** Nothing to branch, nothing to test twice, no fallback that quietly rots because the developer's machine never takes it.

**Glass over a bright slide is the risk to watch.** Translucency samples what is behind it. Controls that read clearly over a dark placeholder can wash out over a white slide — which is the common case for a deck. Contrast must be checked against a real, bright deck rather than the development placeholder, or this ships looking fine to whoever built it and poor to whoever uses it.

**Not everything should be glass.** `SlidePane` draws an opaque slide edge to edge; translucency behind it samples nothing and costs compositing. Glass belongs on chrome — controls, panels, empty states — not on content.

**Sibling glass elements need a `GlassEffectContainer`.** Independent glass views stack their sampling and read as muddy where they meet. The container is what makes several elements behave as one material.

**The app is now tied to a yearly OS release.** ADR-0005's distribution story narrows to macOS 26+, and each macOS release is a compatibility question rather than a free ride.

## Alternatives

**Conditional `#available` with a `.regularMaterial` fallback** — keeps macOS 15 users. Rejected: it doubles the UI paths, and since the fallback covers every machine below 26, it becomes the appearance most people see while receiving the least attention. A design decision that only applies on the newest OS is not really a design decision.

**Hand-rolled `NSVisualEffectView` blur** — available far back and needs no floor raise. Rejected: it is not Liquid Glass, it re-implements what the system now provides, and it will read as a dated imitation next to real system chrome.

**Stay on macOS 15, no translucency** — costs nothing and keeps the widest reach. Rejected on the grounds in *Context*: chrome that competes with the deck is a real problem for this particular app, and the system has a real answer to it.
