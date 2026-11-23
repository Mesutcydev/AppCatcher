#!/usr/bin/env python3
"""Generate the AppCatcher app icon: 1024x1024, opaque, full-bleed.

Renders dark graphite canvas + mint->aqua->violet gradient bent-scoop glyph
with a glowing sparkle at the catch point. iOS masks the shape; we ship an
opaque square. Supersampled 2x for crisp edges.
"""
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 2048  # supersample
OUT = 1024


def lerp(a, b, t): return a + (b - a) * t


def hexrgb(h):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


# ---- palette -------------------------------------------------------------
CANVAS_TOP = hexrgb('#10141F')
CANVAS_BOT = hexrgb('#030407')
MINT = np.array(hexrgb('#5AF2C0'), dtype=float)
AQUA = np.array(hexrgb('#38BDF8'), dtype=float)
VIOLET = np.array(hexrgb('#8B7CF6'), dtype=float)

# ---- background gradient (vertical) + two radial glows --------------------
y = np.linspace(0, 1, S)[:, None, None]
bg = np.empty((S, S, 3), dtype=float)
for c in range(3):
    bg[..., c] = lerp(CANVAS_TOP[c], CANVAS_BOT[c], y[..., 0])

def radial(_S, cx, cy, r, color, strength):
    yy, xx = np.mgrid[0:_S, 0:_S]
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
    m = np.clip(1 - d, 0, 1) ** 2.2   # shape (S, S)
    for c in range(3):
        bg[..., c] += color[c] * m * strength

radial(S, 0.22 * S, 0.16 * S, 0.62 * S, AQUA, 0.085)
radial(S, 0.86 * S, 0.92 * S, 0.72 * S, VIOLET, 0.075)

# ---- glyph: thick bent scoop with gradient along the path ------------------
canvas = np.array(bg, dtype=np.uint8)
img = Image.fromarray(canvas, 'RGB')
draw = ImageDraw.Draw(img, 'RGBA')

def catmull(pts, n=120):
    """Smooth closed-ish curve through control points (not closed here)."""
    pts = list(pts)
    out = []
    for i in range(len(pts) - 1):
        p0 = pts[max(i - 1, 0)]
        p1 = pts[i]
        p2 = pts[i + 1]
        p3 = pts[min(i + 2, len(pts) - 1)]
        for j in range(n):
            t = j / n
            t2 = t * t
            t3 = t2 * t
            x = 0.5 * ((2 * p1[0]) +
                       (-p0[0] + p2[0]) * t +
                       (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 +
                       (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) +
                       (-p0[1] + p2[1]) * t +
                       (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 +
                       (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    return out

# Control points for the scoop: tail low-left -> sweep right -> head up-left.
controls = [
    (0.16 * S, 0.80 * S),
    (0.42 * S, 0.74 * S),
    (0.66 * S, 0.64 * S),
    (0.84 * S, 0.46 * S),
    (0.82 * S, 0.30 * S),
    (0.68 * S, 0.24 * S),
    (0.54 * S, 0.30 * S),
    (0.50 * S, 0.42 * S),
]
path = catmull(controls, n=90)

W = int(0.085 * S)          # stroke width
visible = np.zeros((S, S), dtype=bool)
for idx, (px, py) in enumerate(path):
    t = idx / len(path)
    # gradient: mint -> aqua -> violet along the curve
    if t < 0.5:
        col = MINT * (1 - t * 2) + AQUA * (t * 2)
    else:
        col = AQUA * (1 - (t - 0.5) * 2) + VIOLET * ((t - 0.5) * 2)
    r, g, b = col.astype(int)
    draw.ellipse([px - W / 2, py - W / 2, px + W / 2, py + W / 2],
                 fill=(r, g, b, 255))

# ---- sparkle at the catch point ------------------------------------------
sx, sy = 0.50 * S, 0.44 * S
spark = Image.new('RGBA', (S, S), (0, 0, 0, 0))
sd = ImageDraw.Draw(spark, 'RGBA')

def glow(cx, cy, base_r, color, layers=6):
    for i in range(layers):
        rr = base_r * (1 + i * 0.42)
        a = int(255 * (1 / (i + 1)) ** 1.4)
        sd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr],
                   fill=(*color, a))

glow(sx, sy, int(0.14 * S), (90, 242, 192))   # mint glow
W2 = int(0.055 * S)
for ang in range(0, 360, 45):
    a = math.radians(ang)
    x1 = sx + math.cos(a) * W2 * 3.2
    y1 = sy + math.sin(a) * W2 * 3.2
    x2 = sx - math.cos(a) * W2 * 3.2
    y2 = sy - math.sin(a) * W2 * 3.2
    sd.line([x1, y1, x2, y2], fill=(230, 255, 246, 255), width=W2)
sd.ellipse([sx - W2, sy - W2, sx + W2, sy + W2], fill=(240, 255, 250, 255))
spark = spark.filter(ImageFilter.GaussianBlur(6))
img = Image.alpha_composite(img.convert('RGBA'), spark).convert('RGB')

# softly vignette the very corners for depth (still fully opaque)
img = img.filter(ImageFilter.GaussianBlur(0.001))  # no-op guard

img = img.resize((OUT, OUT), Image.LANCZOS)
img.save('Resources/AppIcon.png', 'PNG')
print('wrote Resources/AppIcon.png', img.size)

# ---- numeric verification --------------------------------------------------
arr = np.asarray(img)
alpha_ok = True  # RGB only canvas; image fully opaque by construction
mean = arr.mean(axis=2)
# 48x48 ASCII luminance map so we can "see" the layout without viewing it
H, Wd = mean.shape
cell = max(1, H // 48)
g = " .:-=+*#%@"
for r in range(0, H, cell):
    row = ""
    for c in range(0, Wd, cell):
        blk = mean[r:r + cell, c:c + cell].mean()
        row += g[min(len(g) - 1, int(blk / 256 * len(g)))]
    print(row)
print('corner luminance (should be dark, not 255):',
      int(mean[20, 20]), int(mean[20, 1003]), int(mean[1003, 1003]))