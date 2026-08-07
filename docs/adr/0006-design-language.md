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

**Glass over a bright slide was the risk to watch, and the layout prevents it.** Translucency samples what is behind it, so controls that read clearly over a dark placeholder could wash out over a white slide — the common case for a deck.

Checked against the real deck, windowed and fullscreen, with notes revealed: it does not arise. Every glass surface is **adjacent** to the slide rather than overlaid on it — the thumbnail strip and notes sit below the deck in a stack, and the mirror pane's chrome sits over its own background. So glass never samples slide content, and the controls stay legible over a near-white deck.

That is a property of the layout, not a fix, and it is only true while chrome stays adjacent. **Anything that overlays a slide — a fullscreen toolbar, a floating control, a multi-display presenter overlay (#31) — reopens this and must be re-checked against a bright deck.**

**The window itself is translucent, but only while not presenting.** Glass surfaces sample what is behind them, and for a long time that was the app's own opaque background — so the effect was real but sampled nothing interesting, and looked flat next to system chrome. The window now sets `isOpaque = false` over an `NSVisualEffectView` with `.behindWindow` blending, which is what makes the backdrop actually be the desktop.

Two halves that are worthless apart: `.withinWindow` blending samples the app's own content and changes nothing, and any `NSVisualEffectView` inside an opaque window blurs nothing at all.

**Opaque on entering fullscreen.** A translucent window mid-presentation means a projector showing fragments of the desktop around the deck, and a notification banner bleeding through behind it. The switch hooks the fullscreen observers `PresentationController` already keeps for the sleep assertion, so it inherits their property: entering by the green button, the Window menu, or macOS restoring fullscreen at launch is handled identically to the menu item.

Same asymmetry as the speaker notes — pleasant while working, off by default when a room is watching.

**Not everything should be glass.** `SlidePane` draws an opaque slide edge to edge; translucency behind it samples nothing and costs compositing. Glass belongs on chrome — controls, panels, empty states — not on content.

**Sibling glass elements need a `GlassEffectContainer`.** Independent glass views stack their sampling and read as muddy where they meet. The container is what makes several elements behave as one material.

This applies across a *stack*, not just within one card: the thumbnail strip and the notes pane are two bars sitting one above the other, and giving each its own effect was exactly the case the container exists for. Grouping them also moved the outer padding to one place, which fixed notes text clipping at the pane's edge.

**The app is now tied to a yearly OS release.** ADR-0005's distribution story narrows to macOS 26+, and each macOS release is a compatibility question rather than a free ride.

## The product name

**Sidecar.** Apple ships a feature of the same name — iPad as a second display — which is adjacent territory, and that was raised and considered before choosing. Recorded here so a later reader treats it as a decision rather than an oversight to correct.

Nothing collides technically: the bundle identifier is `com.codewithshayy.sidecar`, namespaced to the developer. The cost is discoverability, which the README answers by leading with a one-line description of what the app does and a note distinguishing it from Apple's feature.

Settled before M4 because macOS keys TCC grants and preferences to the bundle identifier: changing it after notarisation would silently revoke every installed copy's Screen Recording and Camera permissions.

## Alternatives

**Conditional `#available` with a `.regularMaterial` fallback** — keeps macOS 15 users. Rejected: it doubles the UI paths, and since the fallback covers every machine below 26, it becomes the appearance most people see while receiving the least attention. A design decision that only applies on the newest OS is not really a design decision.

**Hand-rolled `NSVisualEffectView` blur** — available far back and needs no floor raise. Rejected: it is not Liquid Glass, it re-implements what the system now provides, and it will read as a dated imitation next to real system chrome.

**Stay on macOS 15, no translucency** — costs nothing and keeps the widest reach. Rejected on the grounds in *Context*: chrome that competes with the deck is a real problem for this particular app, and the system has a real answer to it.
