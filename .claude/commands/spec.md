---
description: Turn an issue into a spec under docs/specs/, cross-linked both ways
argument-hint: <issue number>
---

Write a spec for issue **#$ARGUMENTS**.

Read the issue first (`gh issue view $ARGUMENTS`), plus any ADR it touches and any existing spec it overlaps. If a spec already covers this, extend that one — do not add a second document describing the same capability.

Write to `docs/specs/NNNN-<slug>.md`, taking the next free number, and follow the shape the existing specs use: goal, behaviour, acceptance criteria, testing, out of scope.

**Behaviour** describes what the user observes, not how it is built. Implementation choices belong in an ADR.

**Acceptance criteria** must be checkable. The test is whether someone could build a fixture and run it. Cover the failure cases explicitly — denied permissions, missing files, disconnected hardware, empty inputs. Those decide whether the app works on someone else's machine, and they are what goes missing when specs are written from the happy path.

**Testing** says honestly what cannot run in CI and how it gets verified instead. Capture needs TCC grants and a GUI session; converters need `soffice` or Keynote consent. Do not write criteria that pretend otherwise.

**Out of scope** is worth real thought — it is what stops the milestone growing quietly.

If the capability depends on an unresolved spike, say so at the top and name what happens under each outcome.

Then link both ways: add the spec to `docs/specs/README.md`, and comment on the issue with the path.
