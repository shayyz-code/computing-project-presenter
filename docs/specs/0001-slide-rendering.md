# Spec 0001: Slide rendering

**Milestone:** M1 Slides · **Module:** `SlideKit` · **Decides:** [ADR-0002](../adr/0002-deck-rendering.md)

## Goal

Open a deck and show any slide in it, at display quality, fast enough that advancing feels instant.

## Behaviour

### Opening

`.pdf` opens directly. `.pptx` converts to PDF first — LibreOffice when `soffice` is present, otherwise Keynote. Conversion result is cached by file content hash, so reopening the same deck is instant and editing it invalidates the cache.

Conversion is slow enough to need progress. Anything over ~500 ms shows it, and the ceiling is much higher than steady-state timings suggest: spike #16 measured **321 s** for LibreOffice's first-ever invocation while it built its user profile, against 6 s for the same deck warm. A first-time user hits that on their first deck-open, so progress must be indeterminate-safe and never look hung.

**Keynote must be opened through LaunchServices, not Apple Events.** `NSWorkspace.open` hands Keynote a sandbox extension token for the file; a bare POSIX path over Apple Events does not, and Keynote responds with a modal dialog while the AppleEvent times out. Export over Apple Events once the document is open. See [ADR-0002](../adr/0002-deck-rendering.md).

### Ordering

Slide order comes from `<p:sldIdLst>` in `ppt/presentation.xml`, resolved through `ppt/_rels/presentation.xml.rels`.

**Not** from sorting `slide1.xml`, `slide2.xml`, … Any deck whose slides were reordered after creation will render wrong if this shortcut is taken, and the failure is silent — the deck looks fine, just out of order.

### Notes

Notes resolve through each slide's own `ppt/slides/_rels/slideN.xml.rels` to its `notesSlide` part, and the text comes from `<a:t>` runs.

**Not** by index. `notesSlide1.xml` belongs to slide 1 only when every preceding slide has notes. In a deck where slides 1, 3 and 4 are annotated and 2 and 5 are bare, positional mapping puts slide 3's notes on slide 2 — plausible enough to ship and wrong in front of an audience.

### Rendering

PDF page → `CGImage` at the display's backing scale. An LRU cache holds recently rendered pages and prefetches ±2 from the current position, so advancing does not wait on a render.

**The cache is bounded by bytes, not by page count.** A rendered page costs roughly `width × height × 4`, which swings about 9× with where it is shown — ~4 MB in a window, ~10 MB fullscreen at 2×, ~35 MB fullscreen on a large external display. A page count safe on a projector would waste most of the budget in a window; one generous in a window would reach gigabytes in fullscreen. Bytes self-adjust.

**The page on screen is never evicted.** Under a budget smaller than the working set, a plain LRU drops the visible slide and makes every advance a guaranteed miss — a cache that costs more than it saves.

**A geometry change purges rather than ageing out.** Moving to another display misses naturally, since size and scale are in the key, but leaving the old entries to be evicted gradually would starve the new scale of budget exactly when it needs room.

Prefetch runs off the main actor and is fire-and-forget: it must never delay a keypress, and a failure needs no handling because the synchronous path renders on demand. It is skipped while zoomed, where the neighbours would be cached at a zoom the presenter is about to leave.

### Failing

Every failure names a remedy. No deck loader available for a `.pptx` offers three: install LibreOffice, use Keynote, or export to PDF. A corrupt file says so rather than showing an empty deck.

## Acceptance criteria

- [ ] A `.pdf` opens and every page is reachable
- [ ] A `.pptx` opens on a machine with **no LibreOffice installed**
- [ ] Converting through Keynote does not take focus — the frontmost app is unchanged across a conversion, and no Keynote document is left open
- [ ] A `.pptx` that embeds fonts under `ppt/fonts/*.fntdata` prefers LibreOffice when available; Keynote substitutes and text reflows out of its shape
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

Sparse notes are not merely hypothetical: a real 53-slide lecture deck used in spike #16 carried notes on only **9** slides, and its `notesSlide3.xml` belongs to **slide 9**. Positional mapping puts slide 9's notes on slide 3. The fixture just makes the case small enough to assert.

**A fixture must also make its rIds unsortable into author order.** `<p:sldId r:id="…">` entries cite relationship ids, and PowerPoint assigns an rId when a slide is created and never renumbers on reorder — so in a real deck rId order and author order are unrelated. A fixture where they coincide cannot detect a reader that ignores `sldIdLst`, because sorting the rIds happens to give the right answer. `make-fixtures.py` therefore uses ids like `rId7, rId3, rId5`. This was found by mutation-testing the fixtures: an early version passed against a reader that sorted instead of reading document order.

Ground truth for slide count is `<p:sldId>` entries in `ppt/presentation.xml`, read directly from the zip. Asserting a converter's page count against another converter's tests neither.

**Zip entries are not all deflated.** Across 61 real decks: 8311 DEFLATE entries and 1219 STORED, of which 82 were `.xml` — exactly the parts a metadata reader fetches. Treating everything as deflate returns garbage for those and reports no error, so at least one fixture carries a STORED `.xml` part.

Fixture-based tests run in CI. Conversion tests need `soffice` or Keynote consent, so they are tagged and excluded — verify those by hand.

## Out of scope

Editing decks. Transitions and animations. Embedded video. Live PowerPoint or Keynote sync.
