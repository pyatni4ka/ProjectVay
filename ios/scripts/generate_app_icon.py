#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter


SIZE = 1024
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "Assets.xcassets" / "AppIcon.appiconset"


def lerp(a: int, b: int, t: float) -> int:
    return int(a + (b - a) * t)


def make_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    for y in range(size):
        t = y / max(size - 1, 1)
        row = (
            lerp(top[0], bottom[0], t),
            lerp(top[1], bottom[1], t),
            lerp(top[2], bottom[2], t),
        )
        for x in range(size):
            pixels[x, y] = row
    return image


def draw_symbol(canvas: Image.Image, stroke: tuple[int, int, int]) -> None:
    draw = ImageDraw.Draw(canvas)
    width = 64
    cx = SIZE // 2
    roof_top = 295
    roof_left = cx - 220
    roof_right = cx + 220
    body_top = 450
    body_bottom = 760
    body_left = cx - 210
    body_right = cx + 210

    draw.line(
        [(roof_left, body_top), (cx, roof_top), (roof_right, body_top)],
        fill=stroke,
        width=width,
        joint="curve",
    )
    draw.rounded_rectangle(
        [body_left, body_top, body_right, body_bottom],
        radius=96,
        outline=stroke,
        width=width,
    )

    box_left = cx - 95
    box_top = 530
    box_right = cx + 95
    box_bottom = 715
    draw.rounded_rectangle(
        [box_left, box_top, box_right, box_bottom],
        radius=28,
        outline=stroke,
        width=52,
    )
    draw.line([(box_left, box_top + 95), (box_right, box_top + 95)], fill=stroke, width=34)
    draw.line([(cx, box_top), (cx, box_bottom)], fill=stroke, width=34)


def add_glow(image: Image.Image, color: tuple[int, int, int], alpha: int, radius: int, offset: tuple[int, int]) -> None:
    overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    cx = SIZE // 2 + offset[0]
    cy = SIZE // 2 + offset[1]
    draw.ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius],
        fill=(*color, alpha),
    )
    overlay = overlay.filter(ImageFilter.GaussianBlur(80))
    image.alpha_composite(overlay)


def make_icon(
    top: tuple[int, int, int],
    bottom: tuple[int, int, int],
    accent: tuple[int, int, int],
    symbol: tuple[int, int, int],
    out_name: str,
) -> None:
    base = make_gradient(SIZE, top, bottom).convert("RGBA")
    add_glow(base, accent, alpha=130, radius=290, offset=(-120, -60))
    add_glow(base, (255, 255, 255), alpha=55, radius=200, offset=(170, -180))
    add_glow(base, accent, alpha=80, radius=240, offset=(190, 190))
    draw_symbol(base, stroke=symbol)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    base.save(OUTPUT_DIR / out_name, format="PNG")


def main() -> None:
    make_icon(
        top=(57, 88, 76),
        bottom=(245, 190, 126),
        accent=(124, 214, 168),
        symbol=(251, 252, 250),
        out_name="AppIcon-Light.png",
    )
    make_icon(
        top=(24, 30, 35),
        bottom=(58, 72, 88),
        accent=(110, 202, 160),
        symbol=(246, 248, 247),
        out_name="AppIcon-Dark.png",
    )
    make_icon(
        top=(52, 82, 70),
        bottom=(211, 160, 99),
        accent=(116, 212, 164),
        symbol=(252, 251, 245),
        out_name="AppIcon-Tinted.png",
    )


if __name__ == "__main__":
    main()
