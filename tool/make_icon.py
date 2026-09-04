#!/usr/bin/env python3
"""Regenerate every derived image from the source art in art/.

Sources (hand-made, never written by this script):
    art/mascot-source/penny_<pose>.png   the six poses, ~1254px, RGBA
    art/mascot-source/icon_source.png    the launcher crop: breathing room
                                         above the leaves, body bleeding off
                                         the bottom edge

Outputs (generated, never hand-edited):
    assets/mascot/penny_<pose>.png       512px, quantised — what ships
    assets/icon/app_icon.png             iOS: whole square, opaque cream
    assets/icon/app_icon_adaptive.png    Android: mascot inside the safe
                                         centre 2/3, transparent
    assets/splash/penny_mark.png         the whole mascot, trimmed

Run after changing any source art:   python3 tool/make_icon.py
"""

import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art", "mascot-source")

# Penny's ground colour. The launcher icon sits on it, never on transparency —
# a transparent icon picks up whatever the launcher is showing behind it.
GROUND = (255, 248, 241, 255)

# An Android adaptive icon only guarantees the centre 2/3 of its foreground
# survives the launcher's mask, so the face has to fit inside that. iOS shows
# the whole square. The same crop framed for one is visibly wrong on the other,
# which is why these are two files rather than one.
#
# The art is a crop that bleeds off its own bottom edge. Centring it inside the
# safe zone puts that cut edge in the middle of the frame with empty space
# under it, which reads as a sticker someone tore in half. Bottom-aligning to
# the canvas instead sends the cut off the edge, where the mask hides it, and
# the icon reads as a face rising into the frame — which is the whole point of
# cropping it in the first place.
ADAPTIVE_WIDTH = 0.72


def path(*parts):
    return os.path.join(ROOT, *parts)


def trimmed(im):
    """The image cropped to its own alpha bounding box.

    Source padding varies per pose, so framing has to work off what is actually
    drawn rather than off the canvas it was drawn on.
    """
    box = im.getbbox()
    return im.crop(box) if box else im


def shrink_poses(size=512, colors=128):
    """Downscale and quantise the six poses.

    The sources are ~900 KB each and the largest the app ever draws one is 160
    logical pixels. Shipping the originals would put ~5.5 MB of PNG in the APK
    for no visible difference.
    """
    out = path("assets", "mascot")
    os.makedirs(out, exist_ok=True)
    total_before = total_after = 0

    for name in sorted(os.listdir(SRC)):
        if not name.startswith("penny_"):
            continue
        source = os.path.join(SRC, name)
        im = Image.open(source).convert("RGBA")
        im.thumbnail((size, size), Image.LANCZOS)
        # FASTOCTREE is the one PIL quantiser that keeps the alpha channel;
        # flat cartoon art loses nothing visible at 128 colours.
        im = im.quantize(colors=colors, method=Image.FASTOCTREE)

        dest = os.path.join(out, name)
        im.save(dest, optimize=True)
        total_before += os.path.getsize(source)
        total_after += os.path.getsize(dest)
        print(f"  {name:24} {os.path.getsize(dest) / 1024:6.0f} KB")

    print(f"  {'':24} {(total_before - total_after) / 1024 / 1024:6.2f} MB saved")


def make_icons(size=1024):
    """Both launcher framings, from the one piece of icon art."""
    source = Image.open(os.path.join(SRC, "icon_source.png")).convert("RGBA")

    # iOS: the art already bleeds off the bottom, so it fills the square as
    # drawn. Flattened onto the ground — remove_alpha_ios would otherwise
    # composite it onto white.
    ios = Image.new("RGBA", (size, size), GROUND)
    ios.alpha_composite(source.resize((size, size), Image.LANCZOS))
    ios.convert("RGB").save(path("assets", "icon", "app_icon.png"), optimize=True)

    # Android adaptive: scaled by WIDTH so the leaves and eyes land inside the
    # guaranteed centre, then bottom-aligned to the canvas so the coin's cut
    # edge runs off it and the mask takes the blame.
    art = trimmed(source)
    scale = (size * ADAPTIVE_WIDTH) / art.width
    art = art.resize(
        (round(art.width * scale), round(art.height * scale)), Image.LANCZOS
    )
    adaptive = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    adaptive.alpha_composite(art, ((size - art.width) // 2, size - art.height))
    adaptive.save(path("assets", "icon", "app_icon_adaptive.png"), optimize=True)
    print("  app_icon.png + app_icon_adaptive.png")


def make_splash(height=512):
    """The launch mark: the whole mascot, never a crop.

    A crop that bleeds off its frame reads as cut off when it floats on a
    splash screen with nothing beneath it.
    """
    im = trimmed(Image.open(os.path.join(SRC, "penny_default.png")).convert("RGBA"))
    scale = height / im.height
    im = im.resize((round(im.width * scale), height), Image.LANCZOS)
    im = im.quantize(colors=128, method=Image.FASTOCTREE)
    os.makedirs(path("assets", "splash"), exist_ok=True)
    im.save(path("assets", "splash", "penny_mark.png"), optimize=True)
    print(f"  penny_mark.png  {im.width}x{im.height}")


if __name__ == "__main__":
    print("mascot:")
    shrink_poses()
    print("icons:")
    make_icons()
    print("splash:")
    make_splash()
