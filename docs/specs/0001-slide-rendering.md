# Spec 0001: Slide rendering

**Milestone:** M1 Slides · **Module:** `SlideKit` · **Decides:** [ADR-0002](../adr/0002-deck-rendering.md)

## Goal

Open a deck and show any slide in it, at display quality, fast enough that advancing feels instant.

## Behaviour

### Opening

`.pdf` opens directly. `.pptx` converts to PDF first — LibreOffice when `soffice` is present, otherwise Keynote. Conversion result is cached by file content hash, so reopening the same deck is instant and editing it invalidates the cache.

Conversion is slow enough to need progress. Anything over ~500 ms shows it.

### Ordering

Slide order comes from `<p:sldIdLst>` in `ppt/presentation.xml`, resolved through `ppt/_rels/presentation.xml.rels`.

**Not** from sorting `slide1.xml`, `slide2.xml`, … Any deck whose slides were reordered after creation will render wrong if this shortcut is taken, and the failure is silent — the deck looks fine, just out of order.

### Notes

Notes resolve through each slide's own `ppt/slides/_rels/slideN.xml.rels` to its `notesSlide` part, and the text comes from `<a:t>` runs.

**Not** by index. `notesSlide1.xml` belongs to slide 1 only when every preceding slide has notes. In a deck where slides 1, 3 and 4 are annotated and 2 and 5 are bare, positional mapping puts slide 3's notes on slide 2 — plausible enough to ship and wrong in front of an audience.

### Rendering

PDF page → `CGImage` at the display's backing scale. An LRU cache holds recently rendered pages and prefetches ±2 from the current position, so advancing does not wait on a render.

### Failing

Every failure names a remedy. No deck loader available for a `.pptx` offers three: install LibreOffice, use Keynote, or export to PDF. A corrupt file says so rather than showing an empty deck.

## Acceptance criteria

- [ ] A `.pdf` opens and every page is reachable
- [ ] A `.pptx` opens on a machine with **no LibreOffice installed**
- [ ] A `.pptx` whose `<p:sldIdLst>` order differs from filename order renders in author order
- [ ] Given a fixture with notes on slides 1, 3, 4 and none on 2, 5 — notes land on 1, 3, 4, and slides 2 and 5 report none
- [ ] A deck with zero slides is reported as `DeckLoadingError.emptyDeck`, not rendered as blank
- [ ] A corrupt file produces `unreadableFile`, not a crash
- [ ] With no converter available, the error names all three remedies
- [ ] Reopening an unchanged deck skips conversion; editing it reconverts
- [ ] Advancing through a 40-slide deck shows no visible render delay after the first page
- [ ] Pages render at backing scale — no blurring on Retina

## Testing

The ordering and notes-mapping criteria need a **hand-built fixture**, since decks exported by normal tools tend to have contiguous notes and sequential ordering — exactly the cases that hide these bugs. Build a `.pptx` with sparse notes and a shuffled `sldIdLst` and commit it.

Fixture-based tests run in CI. Conversion tests need `soffice` or Keynote consent, so they are tagged and excluded — verify those by hand.

## Out of scope

Editing decks. Transitions and animations. Embedded video. Live PowerPoint or Keynote sync.
