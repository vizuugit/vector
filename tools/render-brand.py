#!/usr/bin/env python3
"""Render Vector RP brand SVGs to PNG and pixel-verify.

Usage:
    .tmp-render-venv/bin/python tools/render-brand.py [target...]

Targets:
    watermark-light, watermark-dark, watermark-shorts-v1
    wordmark-mono-light, wordmark-mono-dark
    endorsement-lockup-{light,dark}, endorsement-lockup-stacked-{light,dark}
    og-1200x630, all (default)

The wordmark-mono renders use a 2x supersample then PIL Lanczos downscale to
strip cairosvg's subpixel chromatic AA fringe (the bug CMO flagged on Tier 2).
After endorsement-lockup renders the script samples the gap between VZU and
STUDIO and prints it so we can verify Block 4's <30 / <20 px target.
"""

from __future__ import annotations

import io
import sys
from pathlib import Path

import cairosvg
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "brand" / "vector-rp"

# (svg_name, png_name, output_width, supersample_factor)
TARGETS: dict[str, tuple[str, str, int, int]] = {
    "wordmark":                       ("wordmark.svg",                         "wordmark.png",                          1600, 1),
    "wordmark-v1":                    ("wordmark-v1.svg",                      "wordmark-v1.png",                       1600, 1),
    "wordmark-short":                 ("wordmark-short.svg",                   "wordmark-short.png",                     640, 1),
    "wordmark-mono-light":            ("wordmark-mono-light.svg",              "wordmark-mono-light.png",                512, 2),
    "wordmark-mono-dark":             ("wordmark-mono-dark.svg",               "wordmark-mono-dark.png",                 512, 2),
    "watermark-shorts-v1":            ("watermark-shorts-v1.svg",              "watermark-shorts-v1.png",               1080, 1),
    "watermark-light":                ("watermark-light.svg",                  "watermark-light.png",                   1080, 1),
    "watermark-dark":                 ("watermark-dark.svg",                   "watermark-dark.png",                    1080, 1),
    "endorsement-lockup-dark":        ("endorsement-lockup-dark.svg",          "endorsement-lockup-dark.png",           1600, 1),
    "endorsement-lockup-light":       ("endorsement-lockup-light.svg",         "endorsement-lockup-light.png",          1600, 1),
    "endorsement-lockup-stacked-dark":  ("endorsement-lockup-stacked-dark.svg",  "endorsement-lockup-stacked-dark.png",  1000, 1),
    "endorsement-lockup-stacked-light": ("endorsement-lockup-stacked-light.svg", "endorsement-lockup-stacked-light.png", 1000, 1),
    "og-1200x630":                    ("og-1200x630.svg",                      "og-1200x630.png",                       1200, 1),
}


def desaturate_rgba(img: Image.Image) -> Image.Image:
    """Force R=G=B=max(R,G,B) per pixel.

    Strips cairosvg's LCD subpixel AA fringe (the cyan/yellow chroma CMO
    flagged on wordmark-mono-light over #0F1318) without darkening the
    glyph: pure-white pixels stay pure-white, fringe pixels collapse to
    neutral grey at the same brightness.
    """
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            m = max(r, g, b)
            pixels[x, y] = (m, m, m, a)
    return img


def render(svg_name: str, png_name: str, output_width: int, supersample: int) -> Path:
    svg_path = BRAND / svg_name
    png_path = BRAND / png_name
    raw = cairosvg.svg2png(
        url=str(svg_path),
        output_width=output_width * supersample,
        unsafe=True,
    )
    img = Image.open(io.BytesIO(raw)).convert("RGBA")
    if supersample > 1:
        target_h = round(img.height / supersample)
        img = img.resize((output_width, target_h), Image.LANCZOS)
    if "mono" in svg_name:
        img = desaturate_rgba(img)
    img.save(png_path, "PNG", optimize=True)
    return png_path


def gap_between(png_path: Path, x_left: int, x_right: int, y_top: int, y_bottom: int, alpha_threshold: int = 24) -> tuple[int, int, int]:
    """Return (left_glyph_right_edge, right_glyph_left_edge, gap_px) within a y band.

    Scans every column in [x_left, x_right). A column is "lit" if any pixel in
    [y_top, y_bottom) has alpha > threshold. The largest contiguous unlit run
    in the middle is the visible gap; its boundary columns are the right edge
    of the left glyph and the left edge of the right glyph.
    """
    img = Image.open(png_path).convert("RGBA")
    a = img.split()[3]
    px = a.load()
    lit: list[bool] = []
    for x in range(x_left, x_right):
        col_lit = False
        for y in range(y_top, y_bottom):
            if px[x, y] > alpha_threshold:
                col_lit = True
                break
        lit.append(col_lit)

    longest_start = -1
    longest_len = 0
    cur_start = -1
    cur_len = 0
    seen_lit = False
    for i, v in enumerate(lit):
        if v:
            if not seen_lit:
                seen_lit = True
                cur_start = -1
                cur_len = 0
                continue
            if cur_len > longest_len:
                longest_len = cur_len
                longest_start = cur_start
            cur_start = -1
            cur_len = 0
        else:
            if not seen_lit:
                continue
            if cur_start == -1:
                cur_start = i
            cur_len += 1
    # tail unlit doesn't count (right edge)

    if longest_len == 0:
        return (-1, -1, -1)
    left_edge = x_left + longest_start - 1
    right_edge = x_left + longest_start + longest_len
    return (left_edge, right_edge, longest_len)


def chroma_check(png_path: Path, bg_hex: str = "#0F1318") -> tuple[float, float]:
    """Composite png over solid bg and report max chroma + glyph-edge max chroma.

    Returns (whole_image_max_chroma, edge_band_max_chroma) where chroma is
    the per-pixel max(R,G,B) - min(R,G,B). For a true mono mark this should
    be 0 across the whole frame; the Tier 2 mono-light bug showed values
    >40 along glyph edges.
    """
    bg = Image.new("RGB", (1, 1), bg_hex).getpixel((0, 0))
    img = Image.open(png_path).convert("RGBA")
    composed = Image.new("RGB", img.size, bg)
    composed.paste(img, mask=img.split()[3])

    w, h = composed.size
    px = composed.load()
    max_chroma = 0
    edge_max = 0
    sample_step = max(1, min(w, h) // 400)
    for y in range(0, h, sample_step):
        for x in range(0, w, sample_step):
            r, g, b = px[x, y]
            c = max(r, g, b) - min(r, g, b)
            if c > max_chroma:
                max_chroma = c
            # crude edge band: middle vertical 70% of canvas where the glyphs live
            if h * 0.30 < y < h * 0.70 and w * 0.05 < x < w * 0.95:
                if c > edge_max:
                    edge_max = c
    return (float(max_chroma), float(edge_max))


def main(argv: list[str]) -> int:
    requested = argv[1:] or ["all"]
    if "all" in requested:
        requested = list(TARGETS.keys())

    for key in requested:
        if key not in TARGETS:
            print(f"unknown target: {key}", file=sys.stderr)
            continue
        svg_name, png_name, w, ss = TARGETS[key]
        png = render(svg_name, png_name, w, ss)
        size_kb = png.stat().st_size / 1024
        print(f"  rendered {png.name:48s}  {w}px  ({size_kb:6.1f} kB)" + (f"  ss={ss}x" if ss > 1 else ""))

        if key == "wordmark-mono-light":
            mc, ec = chroma_check(png, bg_hex="#0F1318")
            print(f"    chroma max (whole): {mc:5.1f} | edge band: {ec:5.1f}  (target: edge < 6 over #0F1318)")
        elif key == "wordmark-mono-dark":
            mc, ec = chroma_check(png, bg_hex="#FFFFFF")
            print(f"    chroma max (whole): {mc:5.1f} | edge band: {ec:5.1f}  (target: edge < 6 over #FFFFFF)")
        elif key == "endorsement-lockup-dark" or key == "endorsement-lockup-light":
            le, re, gap = gap_between(png, x_left=1000, x_right=1300, y_top=120, y_bottom=170)
            print(f"    VZU/STUDIO gap (horizontal): VZU.right={le}  STUDIO.left={re}  gap={gap}px  (target: <30)")
        elif key == "endorsement-lockup-stacked-dark" or key == "endorsement-lockup-stacked-light":
            le, re, gap = gap_between(png, x_left=350, x_right=600, y_top=330, y_bottom=380)
            print(f"    VZU/STUDIO gap (stacked):    VZU.right={le}  STUDIO.left={re}  gap={gap}px  (target: <20)")
        elif key in ("watermark-light", "watermark-dark", "watermark-shorts-v1"):
            # bullet/glyph clearance: scan the band y=[280..320] over x=[150..400]
            # within the chip region (chip starts at translate(72,246))
            le, re, gap = gap_between(png, x_left=150, x_right=400, y_top=280, y_bottom=320)
            print(f"    VECTOR/RP separator gap: end-of-VECTOR.x={le}  start-of-RP.x={re}  unlit_run={gap}px (sanity)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
