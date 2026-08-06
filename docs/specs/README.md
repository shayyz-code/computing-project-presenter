# Specs

What each capability must do, as criteria you can check rather than intentions you can agree with.

| Spec | Capability | Milestone |
|---|---|---|
| [0001](0001-slide-rendering.md) | Slide rendering | M1 Slides |
| [0002](0002-device-mirroring.md) | Device mirroring | M2 Mirror |
| [0003](0003-presenter-shell.md) | Presenter shell | M3 Presenter Shell |

## Specs vs ADRs

A spec says *what must be true*. An [ADR](../adr/) says *what we chose and what it cost*. When a spec's criteria and an ADR's decision disagree, one of them is out of date — resolve that before writing more code.

## Criteria are checkable

"Renders slides correctly" is not a criterion. "Given a deck with notes on slides 1, 3, 4 and none on 2, 5 — notes land on 1, 3, 4" is: you can build the fixture and run it.

Several criteria describe failure rather than success — a denied permission, an unplugged device, a corrupt file, an empty deck. Those are the ones that decide whether the app is usable on someone else's machine, and they are the ones that go missing when specs are written from the happy path.
