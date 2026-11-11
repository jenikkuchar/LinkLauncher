#!/usr/bin/env python3
"""Vygeneruje ikonu aplikace (AppIcon) – zaoblený čtverec s přechodem a propojenými
články řetězu (symbol odkazu). Spuštění: python3 scripts/generate-icon.py

Kreslí se v 4× rozlišení a zmenšuje (vyhlazení). Rozměry odpovídají šabloně
macOS ikon: tvar 824 × 824 v plátně 1024 × 1024, poloměr rohu ~185.
Vyžaduje Pillow (pip install pillow).
"""
import json
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 4                      # supersampling
CANVAS = 1024 * S
SHAPE = 824 * S
INSET = (CANVAS - SHAPE) // 2
RADIUS = 185 * S

TOP = (92, 156, 255)       # světle modrá
BOTTOM = (64, 54, 214)     # indigo

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "LinkLauncher", "Assets.xcassets", "AppIcon.appiconset")


def rounded_mask(size, box, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def gradient(size, top, bottom):
    w, h = size
    column = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return column.resize((w, h))


def stadium(size, center, length, height, width, extra=0):
    """Obrys „článku“ (stadionu) jako maska L; extra = rozšíření tahu na obě strany."""
    mask = Image.new("L", size, 0)
    cx, cy = center
    box = (cx - length / 2, cy - height / 2, cx + length / 2, cy + height / 2)
    w = width + 2 * extra
    box = (box[0] - extra, box[1] - extra, box[2] + extra, box[3] + extra)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=(height + 2 * extra) / 2, outline=255, width=round(w))
    return mask


def stroke_path(size, points, width):
    """Tah po čáře s kulatými konci – „štětec“ z kruhů v husté řadě bodů."""
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    r = width / 2
    for x, y in points:
        d.ellipse((x - r, y - r, x + r, y + r), fill=255)
    return mask


def hook_points(center, straight, radius, gap_start, steps=400):
    """Středová čára „otevřeného článku“ (stadion bez horní levé čtvrtiny).
    Začíná na horní hraně (gap_start od středu levého oblouku), vede doprava,
    kolem pravého oblouku, po spodní hraně zpět a končí v nejlevějším bodě."""
    cx, cy = center
    x1, x2 = cx - straight / 2, cx + straight / 2
    pts = []
    for i in range(steps + 1):                        # horní hrana
        x = x1 + gap_start + (x2 - x1 - gap_start) * i / steps
        pts.append((x, cy - radius))
    for i in range(1, steps + 1):                     # pravý oblouk (shora dolů)
        ang = -math.pi / 2 + math.pi * i / steps
        pts.append((x2 + radius * math.cos(ang), cy + radius * math.sin(ang)))
    for i in range(1, steps + 1):                     # spodní hrana
        pts.append((x2 - (x2 - x1) * i / steps, cy + radius))
    for i in range(1, steps // 2 + 1):                # dolní čtvrtina levého oblouku
        ang = math.pi / 2 + (math.pi / 2) * i / (steps // 2)
        pts.append((x1 + radius * math.cos(ang), cy + radius * math.sin(ang)))
    return pts


def chain_symbol(size):
    """Dva otevřené články na jedné ose: konec každého zajíždí do druhého (klasická ikona odkazu)."""
    w, h = size
    cx, cy = w / 2, h / 2
    radius = 0.12 * SHAPE          # poloměr oblouku (středová čára)
    straight = 0.185 * SHAPE         # délka rovné části
    stroke = 0.088 * SHAPE
    shift = 0.155 * SHAPE           # posun středů článků od středu symbolu
    gap = 0.02 * SHAPE

    right = hook_points((cx + shift, cy), straight, radius, gap)
    left = [(2 * cx - x, 2 * cy - y) for x, y in right]   # otočení o 180°
    symbol = ImageChops.lighter(stroke_path(size, right, stroke), stroke_path(size, left, stroke))
    return symbol.rotate(40, resample=Image.BICUBIC, center=(cx, cy))


def render():
    size = (CANVAS, CANVAS)
    box = (INSET, INSET, INSET + SHAPE, INSET + SHAPE)
    shape_mask = rounded_mask(size, box, RADIUS)

    icon = Image.new("RGBA", size, (0, 0, 0, 0))

    # Jemný stín pod tvarem (jako u systémových ikon).
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    shadow_mask = rounded_mask(size, (box[0], box[1] + 10 * S, box[2], box[3] + 10 * S), RADIUS)
    shadow.putalpha(shadow_mask.point(lambda v: v * 0.30).filter(ImageFilter.GaussianBlur(14 * S)))
    icon = Image.alpha_composite(icon, shadow)

    # Tvar s přechodem.
    body = gradient(size, TOP, BOTTOM).convert("RGBA")
    body.putalpha(shape_mask)
    icon = Image.alpha_composite(icon, body)

    # Světlý lesk v horní části.
    gloss = Image.new("RGBA", size, (255, 255, 255, 0))
    gloss_alpha = gradient(size, (46, 46, 46), (0, 0, 0)).convert("L")
    gloss.putalpha(ImageChops.multiply(gloss_alpha, shape_mask))
    icon = Image.alpha_composite(icon, gloss)

    # Symbol: stín a bílé články.
    symbol = chain_symbol(size)
    sym_shadow = Image.new("RGBA", size, (20, 10, 90, 0))
    sym_shadow.putalpha(symbol.point(lambda v: v * 0.35).filter(ImageFilter.GaussianBlur(10 * S)).transform(
        size, Image.AFFINE, (1, 0, 0, 0, 1, -8 * S)))
    icon = Image.alpha_composite(icon, sym_shadow)
    white = Image.new("RGBA", size, (255, 255, 255, 0))
    white.putalpha(symbol)
    icon = Image.alpha_composite(icon, white)

    return icon.resize((1024, 1024), Image.LANCZOS)


SLOTS = [  # (velikost v bodech, scale)
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    master = render()
    images = []
    for points, scale in SLOTS:
        px = points * scale
        name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
        master.resize((px, px), Image.LANCZOS).save(os.path.join(OUT_DIR, name))
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})
    with open(os.path.join(OUT_DIR, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    root = os.path.join(OUT_DIR, "..", "Contents.json")
    with open(root, "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    if len(sys.argv) > 1:
        master.save(sys.argv[1])
    print("Ikona uložena do", os.path.normpath(OUT_DIR))


if __name__ == "__main__":
    main()
