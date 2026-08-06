#!/usr/bin/env python3
"""Build the .pptx fixtures for PPTXMetadataTests.

Run from this directory:

    python3 make-fixtures.py

Not run by CI — the fixtures are committed. This exists so they are
reproducible and reviewable rather than opaque binaries.

Why hand-built rather than exported from Keynote or PowerPoint: a tool-exported
deck has contiguous notes and sequential slide ordering, which is exactly the
shape that hides both bugs these fixtures exist to catch. Spec 0001 requires
the fixture be built by hand for this reason.

Only the parts PPTXMetadata actually reads are included. A real .pptx carries
slide layouts, masters, themes and a content-types part; none of that
participates in resolving order or notes, so including it would be noise in a
file reviewers are meant to be able to reason about.
"""

import zipfile

PRESENTATION = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:sldIdLst>
{entries}
  </p:sldIdLst>
</p:presentation>
"""

RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
{entries}
</Relationships>
"""

SLIDE = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
  xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld><p:spTree><p:sp><p:txBody>
    <a:p><a:r><a:t>{title}</a:t></a:r></a:p>
  </p:txBody></p:sp></p:spTree></p:cSld>
</p:sld>
"""

NOTES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
  xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld><p:spTree><p:sp><p:txBody>
{paras}
  </p:txBody></p:sp></p:spTree></p:cSld>
</p:notes>
"""


def para(text):
    return f"    <a:p><a:r><a:t>{text}</a:t></a:r></a:p>"


def presentation_xml(slide_parts, rids=None):
    """slide_parts is in AUTHOR order.

    rids, when given, is the rId to cite for each author position. Real decks do
    NOT have rId order matching author order — PowerPoint assigns an rId when a
    slide is created and never renumbers on reorder. Fixtures that let the two
    coincide cannot detect a reader which ignores sldIdLst, because sorting the
    rIds happens to give the right answer.
    """
    if rids is None:
        rids = [f"rId{i + 1}" for i in range(len(slide_parts))]
    entries = "\n".join(
        f'    <p:sldId id="{256 + i}" r:id="{rid}"/>'
        for i, rid in enumerate(rids)
    )
    return PRESENTATION.format(entries=entries)


def presentation_rels(slide_parts, rids=None):
    """Maps each rId to its slide part. Emitted in rId order, as a real deck is,
    so the file's own layout gives no hint of author order."""
    if rids is None:
        rids = [f"rId{i + 1}" for i in range(len(slide_parts))]
    kind = ("http://schemas.openxmlformats.org/officeDocument/2006/"
            "relationships/slide")
    pairs = sorted(zip(rids, slide_parts), key=lambda p: p[0])
    entries = "\n".join(
        f'  <Relationship Id="{rid}" Type="{kind}" Target="{part}"/>'
        for rid, part in pairs
    )
    return RELS.format(entries=entries)


def slide_rels(notes_part):
    kind = ("http://schemas.openxmlformats.org/officeDocument/2006/"
            "relationships/notesSlide")
    entry = (f'  <Relationship Id="rId1" Type="{kind}" '
             f'Target="{notes_part}"/>')
    return RELS.format(entries=entry)


def write(name, files, stored=()):
    """files: {path: text}. stored: paths to write uncompressed (method 0)."""
    with zipfile.ZipFile(name, "w") as z:
        for path, text in files.items():
            method = (zipfile.ZIP_STORED if path in stored
                      else zipfile.ZIP_DEFLATED)
            z.writestr(zipfile.ZipInfo(path), text, compress_type=method)
    print(f"wrote {name}")


def sparse_notes():
    """5 slides, notes on 1, 3 and 4 only — the case spec 0001 names.

    The mapping is deliberately non-positional: notesSlide1 -> slide 1, but
    notesSlide2 -> slide 3 and notesSlide3 -> slide 4. Index-mapping notes
    parts to slides puts slide 3's notes on slide 2 and fails the test, which
    is the entire point of this fixture.

    ppt/slides/slide3.xml is written STORED rather than deflated. Real decks
    mix both methods (a survey of 61 found 1219 stored entries, 82 of them
    .xml), and an inflate-only reader returns garbage for those with no error.
    """
    parts = [f"slides/slide{i}.xml" for i in range(1, 6)]
    # Non-sequential rIds, as a real deck has. Author order here does match
    # filename order -- this fixture is about notes, not ordering -- but the rIds
    # must not be sortable into it, or a reader that ignores sldIdLst passes.
    rids = ["rId4", "rId9", "rId2", "rId11", "rId6"]
    files = {
        "ppt/presentation.xml": presentation_xml(parts, rids),
        "ppt/_rels/presentation.xml.rels": presentation_rels(parts, rids),
    }
    for i in range(1, 6):
        files[f"ppt/slides/slide{i}.xml"] = SLIDE.format(title=f"Slide {i}")

    # slide -> notes part. Note the gap: no notesSlide for slides 2 and 5.
    notes_for = {1: "notesSlide1.xml", 3: "notesSlide2.xml",
                 4: "notesSlide3.xml"}
    for slide, notes_part in notes_for.items():
        files[f"ppt/slides/_rels/slide{slide}.xml.rels"] = slide_rels(
            f"../notesSlides/{notes_part}")
        files[f"ppt/notesSlides/{notes_part}"] = NOTES.format(
            paras=para(f"Notes for slide {slide}"))

    # Slides 2 and 5 have a rels part but no notesSlide relationship, which is
    # what a real deck looks like — the part exists for layout refs.
    for slide in (2, 5):
        files[f"ppt/slides/_rels/slide{slide}.xml.rels"] = RELS.format(
            entries="")

    write("sparse-notes.pptx", files, stored={"ppt/slides/slide3.xml"})


def shuffled_order():
    """Author order deliberately differs from filename order.

    sldIdLst references slide3, slide1, slide2 in that order, so a reader that
    sorts filenames produces 1, 2, 3 and gets the deck wrong while looking
    entirely correct. Notes text carries the expected author position so a
    mis-ordered read is unambiguous in the failure message.
    """
    parts = ["slides/slide3.xml", "slides/slide1.xml", "slides/slide2.xml"]
    # rIds deliberately out of order too, so neither filename order NOR rId
    # order yields the author's sequence. Sorting either one gives slide1,
    # slide2, slide3 -- the wrong deck -- which is what makes this fixture able
    # to fail rather than merely pass.
    rids = ["rId7", "rId3", "rId5"]
    files = {
        "ppt/presentation.xml": presentation_xml(parts, rids),
        "ppt/_rels/presentation.xml.rels": presentation_rels(parts, rids),
    }
    # file slide3 is author position 1, slide1 is 2, slide2 is 3
    author_position = {3: 1, 1: 2, 2: 3}
    for file_number, position in author_position.items():
        files[f"ppt/slides/slide{file_number}.xml"] = SLIDE.format(
            title=f"file slide{file_number}")
        files[f"ppt/slides/_rels/slide{file_number}.xml.rels"] = slide_rels(
            f"../notesSlides/notesSlide{file_number}.xml")
        files[f"ppt/notesSlides/notesSlide{file_number}.xml"] = NOTES.format(
            paras=para(f"author position {position}"))

    write("shuffled-order.pptx", files)


def empty_deck():
    """A structurally valid .pptx with an empty sldIdLst -> emptyDeck."""
    files = {
        "ppt/presentation.xml": presentation_xml([]),
        "ppt/_rels/presentation.xml.rels": presentation_rels([]),
    }
    write("empty-deck.pptx", files)


def multiline_notes():
    """Notes spanning several <a:t> runs, plus a slide whose notes are blank.

    Blank notes must read as nil rather than "", so "has no notes" is one
    state in the UI instead of two that look identical.
    """
    parts = ["slides/slide1.xml", "slides/slide2.xml"]
    files = {
        "ppt/presentation.xml": presentation_xml(parts),
        "ppt/_rels/presentation.xml.rels": presentation_rels(parts),
    }
    for i in (1, 2):
        files[f"ppt/slides/slide{i}.xml"] = SLIDE.format(title=f"Slide {i}")
        files[f"ppt/slides/_rels/slide{i}.xml.rels"] = slide_rels(
            f"../notesSlides/notesSlide{i}.xml")

    files["ppt/notesSlides/notesSlide1.xml"] = NOTES.format(
        paras="\n".join([para("First line"), para("Second line")]))
    # whitespace only -> nil
    files["ppt/notesSlides/notesSlide2.xml"] = NOTES.format(
        paras=para("   "))

    write("multiline-notes.pptx", files)


if __name__ == "__main__":
    sparse_notes()
    shuffled_order()
    empty_deck()
    multiline_notes()
