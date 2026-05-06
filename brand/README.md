# Vector Zen brand assets

Studio: **Vector Zen Underground** (wordmark `VECTOR ZEN [U]`).
Domain: `vector-zen.com`. Repo / package namespace: `vector-*`.

Identity is synthwave / Miami-Vice — hot magenta + deep purple + cyan accents on black, drop-shadowed badge type, palms + skyline + neon. Pairs deliberately with the GTA-VI Vice City visual cue our clients already think in.

> **Status:** locked by CEO confirmation `a06ec409` on 2026-05-06 (VEC-56). Primary / secondary designation below is the source of truth — don't ad-hoc swap them.

## Assets in this folder

| File | Use | Notes |
| --- | --- | --- |
| `vector-zen-logo.png` | **Primary logo mark (raster)** — README, GitHub org avatar, `vector-zen.com` header, Discord icon, cold-email signature, slide chrome. | 512×512, transparent background. `VZU` monogram badge with `Vector Zen / UNDERGROUND` sub-lockup. No tagline — safe to embed long-term. |
| `vector-zen-logo.svg` | **Primary logo mark (vector wrapper)** — anywhere SVG is supported and crisp edges at large size matter (high-DPI hero, large-format slide, vector-aware print). | Vector-traced badge silhouette (autotrace) used as a clip-path; the illustrated interior (palms, skyline, drop-shadowed letterforms) ships as an embedded high-res raster. Outer edge is crisp at any zoom; interior detail caps at the source raster. Replace with a hand-redrawn `.ai` once a designer or source artwork lands. |
| `vector-zen-logo-mono-light.svg` + `.png` | **Single-color VZU monogram, white-on-dark** — dark UI overlays, embroidery on dark fabric, dark-themed README badges. | 512×512. Typeset in Ubuntu Sans Condensed ExtraBold and autotraced. The illustrated palette is intentionally dropped per the "shapes only, no skyline interior" spec — these are the utility marks for surfaces that can't print colour. |
| `vector-zen-logo-mono-dark.svg` + `.png` | **Single-color VZU monogram, black-on-light** — single-ink print, business cards, light README badges, embroidery on light fabric. | 512×512. Same source path as mono-light; flipped fill colour. |
| `vector-zen-poster.png` | **Marketing tile / social post** — Twitter/X feed posts, LinkedIn posts, pinned posts. | 1254×1254, black background, with tagline `CREATORS OF SCRIPTS AND MLO FOR GTA V & GTA VI UGC`. Tagline ties the asset to the current B2B positioning — re-shoot if the positioning changes. **Not** the OG card — see below. |
| `vector-zen-og-1200x630-landscape.png` | **OG / Twitter / LinkedIn card image (default)** — `<meta property="og:image">` and `<meta name="twitter:image">`. | 1200×630, native landscape composition: synthwave horizon + perspective grid, badge off-center on the right, B2B tagline locked under it. Reads better in feed previews than the letterboxed v1. |
| `vector-zen-og-1200x630.png` | **OG card v1 (letterboxed)** — fallback only. | 1200×630, square poster centered on black canvas. Kept so existing `og:image` references don't break. New surfaces should use the `-landscape` variant above. |
| `favicon/favicon.ico` | **Legacy favicon** — `<link rel="shortcut icon">`. | Multi-resolution ICO (16/32/48). |
| `favicon/vzu-16.png` … `vzu-512.png` | **PNG favicon pack** — modern `<link rel="icon">` and Apple touch icon. | 16, 32, 48, 180 (`apple-touch-icon`), 512 (`maskable`). Derived from the 512 logo via Lanczos resize; legible from 32 up, monogram-readable at 16. |

## Wordmark hierarchy

1. Full lockup — `Vector Zen Underground` (legal/footer/about copy).
2. Studio short — `Vector Zen` (body copy, headlines, conversation).
3. Stylized wordmark — `VECTOR ZEN [U]` (display type, repo header, README h1).
4. Monogram — `VZU` (badge, favicon, watermark, embroidery, small surfaces).

## Production backlog (remaining)

The big-three variant gaps that blocked T-shirts, embroidery, and OG-feed quality have shipped (see VEC-62). Remaining items:

- **Hand-redrawn `.ai`/native-vector source for the badge interior.** The current `vector-zen-logo.svg` keeps the illustrated palms / skyline / drop-shadowed letterforms as an embedded raster (because the badge is illustrated, not glyph-based, and lossless autotrace would lose the painterly character). Replacing the embedded raster with hand-built vector shapes would let the badge stay crisp past ~2K render targets. Needed before any 4096+ print run; not blocking web/T-shirt/embroidery use today (mono variants are fully vector).
- **Discord server icon** — 512×512 monogram on dark, plus an animated variant if we go boosted. File a separate ticket when we boost.

## Don'ts

- **Don't recolor the primary mark.** The magenta/purple/cyan palette is the brand. For surfaces that can't print colour, use the mono variants above — don't desaturate the primary.
- **Don't crop the poster** to use as a logo — it has the tagline baked in, which dates the asset. Use `vector-zen-logo.png` (or `.svg`) for everything that isn't a marketing post.
- **Don't put the primary monogram on a background that fights the inner-fill skyline.** The illustrated badge needs a dark or contrasty backdrop to read; if the surface is light, use `vector-zen-logo-mono-dark.svg` instead.
- **Don't add a wordmark next to the badge** when both are in frame — the primary badge already lockups `Vector Zen / UNDERGROUND` underneath the monogram.
- **Don't typeset "VZU" yourself** for embroidery / single-ink / favicon-style surfaces. Use `vector-zen-logo-mono-{light,dark}.svg` so kerning and stroke weight stay consistent across vendors.
