"""Generate MirrorSpeed app icons (indigo gradient + white shield).

Outputs to assets/icon/:
  app_icon.png        1024 full-bleed (legacy launcher / iOS / Windows / Play master)
  app_icon_fg.png     1024 transparent, shield centered in safe zone (adaptive foreground)
  app_icon_bg.png     1024 gradient square (adaptive background)
  play_store_512.png   512 Play Store hi-res icon
"""
import os
from PIL import Image, ImageDraw

SS = 4                      # supersample factor for smooth edges
BRAND      = (0x63, 0x66, 0xF1)   # #6366F1 indigo-500
BRAND_DARK = (0x4F, 0x46, 0xE5)   # #4F46E5 indigo-600
WHITE      = (255, 255, 255, 255)

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")
os.makedirs(OUT, exist_ok=True)


def gradient(size):
    """Diagonal gradient BRAND (top-left) -> BRAND_DARK (bottom-right)."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(int(BRAND[i] + (BRAND_DARK[i] - BRAND[i]) * t) for i in range(3))
    return img


def shield_polygon(cx, cy, w, h):
    """Return a list of points for a rounded shield centred at (cx,cy)."""
    x0, x1 = cx - w / 2, cx + w / 2
    ty = cy - h / 2          # top
    by = cy + h / 2          # bottom tip
    my = cy + h * 0.08       # where straight sides end and curve begins
    r = w * 0.16             # top corner radius

    import math
    pts = []
    # top edge (left corner arc -> right corner arc)
    # left top corner
    for a in range(180, 90 - 1, -3):
        pts.append((x0 + r + r * math.cos(math.radians(a)), ty + r + r * math.sin(math.radians(a)) * -1 + r*0))
    # simpler: build manually
    pts = []
    # start at left side just below top-left corner
    # top-left corner (quarter circle)
    for a in range(180, 271, 5):
        pts.append((x0 + r - r * math.cos(math.radians(180 - a)), ty + r - r * math.sin(math.radians(a - 180))))
    # we'll instead use a clean explicit construction below
    pts = []
    # Top-left rounded corner
    cx_tl, cy_tl = x0 + r, ty + r
    for a in range(180, 270, 6):
        pts.append((cx_tl + r * math.cos(math.radians(a)), cy_tl + r * math.sin(math.radians(a))))
    # Top-right rounded corner
    cx_tr, cy_tr = x1 - r, ty + r
    for a in range(270, 360, 6):
        pts.append((cx_tr + r * math.cos(math.radians(a)), cy_tr + r * math.sin(math.radians(a))))
    # right straight down to my
    pts.append((x1, my))
    # right curve to bottom tip (quadratic bezier: P0=(x1,my) ctrl=(x1, by*.92+cy*0.08) P2=tip)
    P0 = (x1, my); P2 = (cx, by); C = (x1, cy + h * 0.40)
    for i in range(1, 21):
        t = i / 20
        x = (1 - t) ** 2 * P0[0] + 2 * (1 - t) * t * C[0] + t ** 2 * P2[0]
        y = (1 - t) ** 2 * P0[1] + 2 * (1 - t) * t * C[1] + t ** 2 * P2[1]
        pts.append((x, y))
    # left curve from tip up to (x0,my)
    P0 = (cx, by); P2 = (x0, my); C = (x0, cy + h * 0.40)
    for i in range(1, 21):
        t = i / 20
        x = (1 - t) ** 2 * P0[0] + 2 * (1 - t) * t * C[0] + t ** 2 * P2[0]
        y = (1 - t) ** 2 * P0[1] + 2 * (1 - t) * t * C[1] + t ** 2 * P2[1]
        pts.append((x, y))
    return pts


def draw_shield(size, scale, pad_frac):
    """Transparent image with a white shield. scale = shield height fraction."""
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    h = big * scale
    w = h * 0.82
    pts = shield_polygon(big / 2, big / 2, w, h)
    d.polygon(pts, fill=WHITE)
    return img.resize((size, size), Image.LANCZOS)


def rounded_mask(size, radius_frac):
    big = size * SS
    m = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(m)
    r = int(big * radius_frac)
    d.rounded_rectangle([0, 0, big - 1, big - 1], radius=r, fill=255)
    return m.resize((size, size), Image.LANCZOS)


def build():
    S = 1024
    grad = gradient(S)

    # adaptive background (full square gradient)
    grad.save(os.path.join(OUT, "app_icon_bg.png"))

    # adaptive foreground: shield smaller (safe zone ~ inner 66%)
    fg = draw_shield(S, scale=0.42, pad_frac=0)
    fg.save(os.path.join(OUT, "app_icon_fg.png"))

    # full-bleed master: gradient + shield (shield ~58% height)
    shield = draw_shield(S, scale=0.56, pad_frac=0)
    full = grad.convert("RGBA")
    full.alpha_composite(shield)
    full.convert("RGB").save(os.path.join(OUT, "app_icon.png"))

    # Play Store 512 (rounded slightly is fine; Play masks it). Keep full square.
    play = full.convert("RGB").resize((512, 512), Image.LANCZOS)
    play.save(os.path.join(OUT, "play_store_512.png"))

    print("icons written to", os.path.abspath(OUT))
    for f in ["app_icon.png", "app_icon_fg.png", "app_icon_bg.png", "play_store_512.png"]:
        im = Image.open(os.path.join(OUT, f))
        print(" ", f, im.size, im.mode)


if __name__ == "__main__":
    build()
