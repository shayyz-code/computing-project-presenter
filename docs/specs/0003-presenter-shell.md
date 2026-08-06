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

### Fullscreen

Fullscreen hides all chrome — toolbar, thumbnails, window frame. Escape exits. The split ratio is preserved on entry and exit.

### Timer

Elapsed time from the start of presentation mode. Pause, resume, reset. Visible to the presenter, never on the audience display.

### Notes

Speaker notes for the current slide, in a pane that can be hidden. Empty notes show nothing rather than an empty box taking up space.

### Restoring

Reopening restores the last deck, the slide it was on, the layout and the selected mirror source — if the source still exists. A missing source restores the layout with the pane in its "choose a source" state, rather than failing to launch.

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
