#!/usr/bin/env python3
"""Generate App/Sidecar/Assets.xcassets/AppIcon.appiconset from one master render.

The icon is drawn rather than checked in as opaque binaries, so it can be
re-tuned by editing numbers instead of by opening a design tool. Run it after
any change here:

    python3 Tools/make-app-icon.py

Requires Pillow (`pip3 install pillow`). Nothing at build time depends on it —
the generated PNGs are committed.

## The mark

Sidecar's whole idea is *a deck and a live phone side by side in one window*, so
the icon is literally that: a slide card on the left, a phone on the right. Two
shapes and nothing else, because the smallest required rendering is 16x16 and
anything more detailed turns to mush there.
"""

import json
import pathlib

from PIL import Image, ImageDraw

MASTER = 1024
OUT = pathlib.Path("App/Sidecar/Assets.xcassets/AppIcon.appiconset")

# macOS app icons do not fill their canvas: the rounded body sits inside a
# margin that the system relies on for shadows and for optical alignment with
# every other icon in the Dock.
BODY_INSET = 100
BODY_RADIUS = 185

BG_TOP = (47, 107, 255)  # the accent blue already used for Open Deck
BG_BOTTOM = (23, 32, 92)
CARD = (246, 248, 255)
CARD_RULE = (196, 206, 232)
PHONE_BODY = (16, 18, 26)
PHONE_SCREEN = (128, 206, 255)
SHADOW = (10, 14, 40)


def rounded(size, radius, fill):
    """A rounded rect as its own image, so it can be composited with alpha."""
    im = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(im).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=fill)
    return im


def master():
    im = Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0))

    # Vertical gradient, drawn a row at a time. Cheap and exact at this size.
    grad = Image.new("RGBA", (MASTER, MASTER))
    gd = ImageDraw.Draw(grad)
    for y in range(MASTER):
        t = y / (MASTER - 1)
        gd.line(
            [(0, y), (MASTER, y)],
            fill=tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)) + (255,),
        )

    body = MASTER - BODY_INSET * 2
    mask = rounded((body, body), BODY_RADIUS, (255, 255, 255, 255)).split()[3]
    im.paste(grad.crop((BODY_INSET, BODY_INSET, MASTER - BODY_INSET, MASTER - BODY_INSET)),
             (BODY_INSET, BODY_INSET), mask)

    # --- the two shapes -------------------------------------------------
    # Sized against the body, not the canvas, so the margin stays honest.
    # The card is landscape and the phone is portrait; that contrast is what
    # makes the pair readable at 16px, where neither shape has any detail left.
    # Laid out as one group and then centred, rather than positioned
    # independently: placing each by eye left the pair sitting noticeably left
    # of centre, which is obvious in a Dock full of centred icons.
    card_w, card_h = round(body * 0.46), round(body * 0.345)
    phone_w, phone_h = round(body * 0.235), round(body * 0.50)
    gap = round(body * 0.055)
    group_w = card_w + gap + phone_w
    group_x = BODY_INSET + (body - group_w) // 2

    card_x = group_x
    card_y = BODY_INSET + round(body * 0.33)
    phone_x = group_x + card_w + gap
    phone_y = BODY_INSET + round(body * 0.25)

    # One soft shadow under both, so they sit on the gradient rather than
    # floating over it.
    shadow = Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    off = round(body * 0.018)
    sd.rounded_rectangle(
        [card_x, card_y + off, card_x + card_w, card_y + card_h + off],
        round(body * 0.035), fill=SHADOW + (90,))
    sd.rounded_rectangle(
        [phone_x, phone_y + off, phone_x + phone_w, phone_y + phone_h + off],
        round(body * 0.055), fill=SHADOW + (110,))
    im.alpha_composite(Image.alpha_composite(Image.new("RGBA", im.size, (0, 0, 0, 0)), shadow))

    d = ImageDraw.Draw(im)
    d.rounded_rectangle(
        [card_x, card_y, card_x + card_w, card_y + card_h],
        round(body * 0.035), fill=CARD + (255,))

    # Two rules standing in for slide content. Deliberately not three or more:
    # they vanish below 64px, and more of them just muddies the card.
    rule_x = card_x + round(card_w * 0.12)
    for i, frac in enumerate((0.30, 0.52)):
        w = card_w * (0.62 if i == 0 else 0.44)
        y = card_y + round(card_h * frac)
        d.rounded_rectangle(
            [rule_x, y, rule_x + round(w), y + round(card_h * 0.085)],
            round(card_h * 0.045), fill=CARD_RULE + (255,))

    d.rounded_rectangle(
        [phone_x, phone_y, phone_x + phone_w, phone_y + phone_h],
        round(body * 0.055), fill=PHONE_BODY + (255,))
    bez = round(phone_w * 0.075)
    d.rounded_rectangle(
        [phone_x + bez, phone_y + bez, phone_x + phone_w - bez, phone_y + phone_h - bez],
        round(body * 0.042), fill=PHONE_SCREEN + (255,))

    return im


# macOS wants both scales of five sizes.
SPECS = [(s, scale) for s in (16, 32, 128, 256, 512) for scale in (1, 2)]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    src = master()
    images = []
    for size, scale in SPECS:
        px = size * scale
        name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
        src.resize((px, px), Image.LANCZOS).save(OUT / name)
        images.append({"size": f"{size}x{size}", "idiom": "mac",
                       "filename": name, "scale": f"{scale}x"})

    (OUT / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")

    catalog = OUT.parent / "Contents.json"
    catalog.write_text(
        json.dumps({"info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")
    print(f"wrote {len(images)} renderings to {OUT}")


if __name__ == "__main__":
    main()
