#!/usr/bin/env python3
"""Generate store logo PNGs for the asset catalog.

Each logo is a 128x128 rounded-rect with the store's brand color
and its short name/initials rendered in white.
"""

import os
import math
from PIL import Image, ImageDraw, ImageFont

STORES = {
    "store_pyaterochka":  {"bg": "#E42313", "text": "5ка"},
    "store_perekrestok":  {"bg": "#1B8C3A", "text": "ПК"},
    "store_magnit":       {"bg": "#D5202E", "text": "М"},
    "store_lenta":        {"bg": "#1E3A8A", "text": "Л"},
    "store_okey":         {"bg": "#F5A623", "text": "ОК"},
    "store_vkusvill":     {"bg": "#5DB534", "text": "ВВ"},
    "store_metro":        {"bg": "#003D7C", "text": "MЕ"},
    "store_dixy":         {"bg": "#ED1C24", "text": "Дк"},
    "store_fixprice":     {"bg": "#FFD600", "text": "FP", "fg": "#222222"},
    "store_samokat":      {"bg": "#FF5722", "text": "СМ"},
    "store_yandexlavka":  {"bg": "#FFCC00", "text": "YL", "fg": "#222222"},
    "store_auchan":       {"bg": "#E21A22", "text": "АШ"},
    "store_ozonfresh":    {"bg": "#005BFF", "text": "OF"},
}

SIZE = 128
RADIUS = 28

ASSETS_DIR = os.path.join(
    os.path.dirname(__file__), "..", "ios", "Assets.xcassets", "StoreLogos"
)


def round_rect_mask(size, radius):
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), (size[0] - 1, size[1] - 1)], radius=radius, fill=255)
    return mask


def find_font(size):
    """Try to find a good system font, falling back to default."""
    candidates = [
        "/System/Library/Fonts/SFCompact.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/Library/Fonts/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default()


def generate_logo(store_name, cfg):
    bg = cfg["bg"]
    fg = cfg.get("fg", "#FFFFFF")
    text = cfg["text"]

    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Rounded rectangle background
    draw.rounded_rectangle(
        [(0, 0), (SIZE - 1, SIZE - 1)],
        radius=RADIUS,
        fill=bg,
    )

    # Text
    font_size = 48 if len(text) <= 2 else 36
    font = find_font(font_size)

    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (SIZE - tw) / 2 - bbox[0]
    ty = (SIZE - th) / 2 - bbox[1]

    draw.text((tx, ty), text, fill=fg, font=font)

    return img


def main():
    for store_name, cfg in STORES.items():
        imageset_dir = os.path.join(ASSETS_DIR, f"{store_name}.imageset")
        os.makedirs(imageset_dir, exist_ok=True)

        img = generate_logo(store_name, cfg)
        out_path = os.path.join(imageset_dir, "logo.png")
        img.save(out_path, "PNG")
        print(f"  {store_name}: {out_path} ({os.path.getsize(out_path)} bytes)")

    print("\nDone! All store logos generated.")


if __name__ == "__main__":
    main()
