# Spec 0003: Presenter shell

**Milestone:** M3 Presenter Shell · **Module:** `PresenterCore` + app target

## Goal

Run a whole presentation without touching another application.

## Behaviour

### Layout

Deck left, mirror right, draggable split. The ratio persists between launches. Sides can be swapped — some people demo more than they present. Either pane can be collapsed entirely, and collapsing the mirror stops capture rather than hiding a still-running stream.

### Navigating

Arrow keys, space, and page up/down advance and retreat. Home and End jump to the ends. A thumbnail strip allows jumping directly.

Advancing off the last slide does nothing visible — it does not wrap to the start, and it does not exit the presentation. Both would be surprising mid-talk. `SlideNavigator.advance()` already returns `false` here so the caller can decide; the decision is "nothing".

Presenter remotes appear as keyboards sending page up/down, so they work without special handling.

### Session restore

The deck, slide position and notes visibility come back on relaunch. **The mirror source is remembered but not reconnected** — connecting would unhide the Simulator uninvited and could fire a Camera or Screen Recording prompt before the user had done anything, so the source is pre-selected and waits for a click.

Degradation is the design, because a stale session is the *normal* case for a machine that moves between a desk and a lecture theatre:

| Saved state | Behaviour |
|---|---|
| Deck moved or deleted | Restore the rest; the empty state **names the missing file** |
| Deck now shorter than the saved position | Clamped by `SlideNavigator`'s construction rule |
| Mirror source gone | Deck restores; source left unselected |
| Corrupt saved data | Discarded; launch proceeds |

**A saved session is a convenience and must never prevent the app from launching.** That is why `SessionStore.load()` returns `nil` rather than throwing.

The stored value is a plain path, which only works because App Sandbox is deliberately off (ADR-0005). **If the app is ever sandboxed for the Mac App Store a stored path stops resolving and needs a security-scoped bookmark** — the sort of thing that breaks silently at the worst moment.

Restoring a `.pptx` is normally instant because conversions are content-hash cached, but a cleared cache means a full reconversion on launch — up to the 321 s cold-LibreOffice case. The converting state covers it and ⌘O still works meanwhile.

## Keyboard navigation

Every navigation action has a menu item, and that is not only for discoverability: **menu key equivalents are dispatched by the menu system rather than the focus chain**, so they keep working wherever the last click landed. A view's `keyDown` fires only while that view is first responder, which made navigation stop silently after clicking in the mirror pane.

The menu carries one shortcut per command — → ← Home End. Space, page up/down and ↑↓ are aliases a presenter and a presenter remote also expect, caught by a local `NSEvent` monitor rather than by giving each command three menu entries. Everything routes through `NavigationCommand`, so menu and keyboard cannot describe different behaviour.

Unmodified keys as shortcuts are captured **app-wide**. There are no text fields today — notes are read-only — and space-advances is the universal presenter convention, so this is the right trade. Whoever adds a text field must revisit it.

Advancing on the last slide does nothing: no wrap, no exit from fullscreen. Both would be surprising mid-talk.

## Fullscreen

Fullscreen hides all chrome — toolbar, thumbnails, window frame. Escape exits. The split ratio is preserved on entry and exit.

### Timer

Elapsed time from the start of presentation mode. Pause, resume, reset. Visible to the presenter, never on the audience display.

### Notes

Speaker notes for the current slide, in a pane that can be hidden. Empty notes show nothing rather than an empty box taking up space.

### Restoring

Reopening restores the last deck, the slide it was on, the layout and the selected mirror source — if the source still exists. A missing source restores the layout with the pane in its "choose a source" state, rather than failing to launch.

## Session restore

The deck, slide position and notes visibility come back on relaunch. **The mirror source is remembered but not reconnected** — connecting would unhide the Simulator uninvited and could fire a Camera or Screen Recording prompt before the user had done anything, so the source is pre-selected and waits for a click.

Degradation is the design, because a stale session is the *normal* case for a machine that moves between a desk and a lecture theatre:

| Saved state | Behaviour |
|---|---|
| Deck moved or deleted | Restore the rest; the empty state **names the missing file** |
| Deck now shorter than the saved position | Clamped by `SlideNavigator`'s construction rule |
| Mirror source gone | Deck restores; source left unselected |
| Corrupt saved data | Discarded; launch proceeds |

**A saved session is a convenience and must never prevent the app from launching.** That is why `SessionStore.load()` returns `nil` rather than throwing.

The stored value is a plain path, which only works because App Sandbox is deliberately off (ADR-0005). **If the app is ever sandboxed for the Mac App Store a stored path stops resolving and needs a security-scoped bookmark** — the sort of thing that breaks silently at the worst moment.

Restoring a `.pptx` is normally instant because conversions are content-hash cached, but a cleared cache means a full reconversion on launch — up to the 321 s cold-LibreOffice case. The converting state covers it and ⌘O still works meanwhile.

## Keyboard navigation

Every navigation action has a menu item, and that is not only for discoverability: **menu key equivalents are dispatched by the menu system rather than the focus chain**, so they keep working wherever the last click landed. A view's `keyDown` fires only while that view is first responder, which made navigation stop silently after clicking in the mirror pane.

The menu carries one shortcut per command — → ← Home End. Space, page up/down and ↑↓ are aliases a presenter and a presenter remote also expect, caught by a local `NSEvent` monitor rather than by giving each command three menu entries. Everything routes through `NavigationCommand`, so menu and keyboard cannot describe different behaviour.

Unmodified keys as shortcuts are captured **app-wide**. There are no text fields today — notes are read-only — and space-advances is the universal presenter convention, so this is the right trade. Whoever adds a text field must revisit it.

Advancing on the last slide does nothing: no wrap, no exit from fullscreen. Both would be surprising mid-talk.

## Fullscreen

Fullscreen **hides notes and the timer**, because on a single display whatever is on screen is what a projector mirrors. ⇧⌘N reveals them for the laptop-only case.

**The safe default reasserts on every entry.** Revealing notes applies to that presentation only; leaving and re-entering hides them again. A preference left on last week must not put a script in front of a room today, and the failure is asymmetric — exposure is embarrassing and irreversible, a missing note costs one keystroke.

Fullscreen state is read from `NSWindow.didEnterFullScreenNotification`, never from a flag the app sets itself: fullscreen is reachable from the menu item, ⌃⌘F, the green button and the Window menu, and a self-managed flag is wrong for three of them.

Escape exits, because that is what a presenter reaches for — native macOS fullscreen does not do this by default.

The display is kept awake with `NSActivityIdleDisplaySleepDisabled` while presenting, released on exit **and** on window close. An unbalanced assertion keeps the display awake for the process lifetime.

## Presenter-only surfaces

Speaker notes and the elapsed timer must **never** reach an audience display. They live in `NotesPane`, kept a separate view from the deck so that moving it to a presenter-only window when multi-display lands (#31) is a reparenting rather than a rewrite.

A slide with no notes shows **nothing** — not a labelled empty box, which reads as "something failed to load". A `.pdf` deck carries no notes at all, so the pane is absent rather than permanently blank.

## Acceptance criteria

- [ ] Dragging the split resizes both panes; the ratio survives a relaunch
- [ ] Swapping sides swaps content, not just labels
- [ ] Collapsing the mirror pane stops capture — the macOS capture indicator goes away
- [ ] Arrows, space and page up/down all navigate
- [ ] A presenter remote advances and retreats
- [ ] Advancing on the last slide does nothing — no wrap, no exit
- [ ] Retreating on the first slide does nothing
- [ ] Home and End reach the ends of any deck
- [ ] Clicking a thumbnail jumps to that slide
- [ ] Fullscreen hides all chrome; Escape exits; ratio is preserved across both
- [ ] The timer starts with presentation mode and survives slide changes
- [ ] Notes follow the current slide, and a slide without notes shows nothing
- [ ] Relaunching restores deck, position, layout and source
- [ ] Relaunching with the previous source gone restores everything else and prompts for a source
- [ ] Every keyboard action has a menu item — discoverable, and accessible

## Testing

Navigation, layout state and persistence are pure logic in `PresenterCore` and test fully in CI, including the boundary cases above.

Fullscreen, remotes and restore-after-relaunch need manual verification. A full rehearsal — open a deck, mirror a Simulator, present start to finish — is the real test, and the one that catches what unit tests do not.

## Out of scope

Multi-display presenter view — M4. Drawing or laser pointer. Audience-facing timer. Recording.
