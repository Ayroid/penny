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
ADAPTIVE_SAFE = 2 / 3

# ...and then a little past it. The 2/3 guarantee is the floor Android
# promises, not what a launcher actually shows — most mask a circle inscribed
# in the full 108dp, so an icon framed to the guarantee looks small in every
# real launcher. This oversizes by 10%, which puts the top of the art just
# outside the guaranteed box. The trade is deliberate: a mask aggressive enough
# to clip it would be clipping the corners off every other icon on the phone.
#
# Two 10% steps, tuned by looking at it rather than derived — 1.10 still read
# small against the launcher's own icons.
ADAPTIVE_OVERSIZE = 1.21


def path(*parts):
    return os.path.join(ROOT, *parts)


def trimmed(im, threshold=8):
    """The image cropped to its own alpha bounding box.

    Thresholded, because `Image.getbbox()` trims on alpha > 0 and the source
    art carries near-invisible noise — stray pixels at alpha 1-8 hugging the
    canvas edge. Invisible on screen, but a bounding box does not care how
    faint a pixel is: the ghost drags the computed centre sideways and inflates
    the width, which scales the mascot down and shifts it off-centre. Measured
    on the candle: 88px of phantom to the left, and 180px of spurious width.

    Source padding varies per pose, so framing has to work off what is actually
    drawn rather than off the canvas it was drawn on.
    """
    alpha = im.getchannel("A").point(lambda v: 255 if v > threshold else 0)
    box = alpha.getbbox()
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

    # Android adaptive: the foreground is 108dp, of which only the centre 72dp
    # — two thirds — is guaranteed to survive the launcher's mask. So pin the
    # art's top to the top of that safe box and let its bottom run to the
    # canvas edge, where the mask crops it. That is the framing the crop was
    # drawn for: a face rising into frame, with the cut edge hidden rather than
    # floating mid-icon. Derived from the guarantee rather than tuned by eye.
    art = trimmed(source)
    safe_top = size * (1 - ADAPTIVE_SAFE) / 2
    scale = ADAPTIVE_OVERSIZE * min(
        (size - safe_top) / art.height,  # tall art: bottom bleeds off
        (size * ADAPTIVE_SAFE) / art.width,  # wide art: width is the limit
    )
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
