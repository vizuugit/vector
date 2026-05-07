# Vector RP brand pack

Sub-brand of **VZU Studio** (publisher). Tier 1 + Tier 2 assets for the Vector RP product.

## Architecture

| Layer | Mark | Tone | Where it lives |
|---|---|---|---|
| Publisher | Vector Zen Underground · VZU Studio · `VZU` monogram | Synthwave / Miami-Vice (purple-magenta-cyan) | `brand/` (parent dir, when `feat/vec-62` lands on main) |
| **Product** | **Vector RP** | Grounded crime-drama, cold scale, single neon-accent | `brand/vector-rp/` (this dir) |
| Endorsement | `Vector RP — by VZU Studio` lockup | Product tone, small VZU monogram | `endorsement-lockup{,-stacked}.svg` here |

The Rockstar precedent applies: R\* (publisher) is synthwave-flavored; GTA V (product) is grounded. Don't bring synthwave into Vector RP — the product is *real devs, real RP, no cosplay*.

## Color tokens

```json
--rp-bg          #0F1318   charcoal — base
--rp-bg-tint     #1A1F26   raised surface
--rp-fg          #D2F8FF   pale cyan — body text on dark
--rp-fg-muted    #8A98A2   secondary text
--rp-accent      #2BCAD0   cyan — HUD chrome, brand primitives, watermark
--rp-accent-warm #E89542   sodium amber — heist/violence beats, danger frames
--rp-error       #C04545   deep blood-red
--rp-success     #3FA37A   muted teal-green
```

See `palette.json` for the canonical source.

## Do / Don't

- **Cool accent (`#2BCAD0`)** — HUD chrome, calm beats, idle frames, brand UI primitives, watermark.
- **Warm accent (`#E89542`)** — heist/violence beats, street-light frames, danger thumbnails, end-card on intense moments.

- DO use the cool accent on the wordmark and watermark canon — those are brand-mark, not chrome.
- DON'T saturate both accents in the same frame — pick one per shot. Both saturated reads jokey/branded, kills grounded vibe.
- DON'T use warm accent on long-form / dev-vlog endorsement card — that's VZU synthwave territory, lockup follows VZU canon.
- DON'T edge toward magenta-purple under any reading — that's VZU exclusive (per [VEC-62](https://github.com/vizuugit/vector/issues)).
- DON'T mint new wordmark variants in the warm accent. Warm is a frame-level token, not a mark variant.

## Asset map

### Wordmark family

| File | Purpose | Canvas |
|---|---|---|
| `wordmark.svg` / `.png` | Final transparent-canvas wordmark | 1600×520 |
| `wordmark-v1.svg` / `.png` | Tier 1 chip primitive (charcoal panel baked in) — for badge/chip use cases | 1600×520 |
| `wordmark-short.svg` / `.png` | `VEC` short — favicon, mobile-feed watermark fallback | 640×520 |
| `wordmark-mono-light.svg` / `.png@512` | White-on-dark single-color | 1600×520 |
| `wordmark-mono-dark.svg` / `.png@512` | Black-on-light single-color | 1600×520 |

### Endorsement lockup

| File | Purpose | Canvas |
|---|---|---|
| `endorsement-lockup-dark.svg` / `.png` | Horizontal, **for dark substrate** — `Vector RP \| by VZU Studio` | 1600×280 |
| `endorsement-lockup-light.svg` / `.png` | Horizontal, **for light substrate** (PR template, README, docs sites, light social cards) | 1600×280 |
| `endorsement-lockup-stacked-dark.svg` / `.png` | Stacked, dark substrate | 1000×500 |
| `endorsement-lockup-stacked-light.svg` / `.png` | Stacked, light substrate | 1000×500 |

Naming follows the `wordmark-mono-{light,dark}` pattern: the suffix names the **substrate** the lockup composes onto, not the chip color. `-dark` keeps STUDIO in pale-cyan (`#D2F8FF`) for charcoal/night surfaces; `-light` switches STUDIO + RP + the separator to charcoal (`#0F1318`) so the lockup stays legible on white/cream/light-gradient surfaces. VZU keeps its cyan accent in both variants.

Currently typeset-only. Once `feat/vec-62` (VZU brand pack) lands on main, the `VZU` text will be replaced by an `<image href="../vector-zen-logo-mono-light.svg">` reference for the canonical monogram.

### Watermark family (1080×1920 for shorts)

| File | Use on | Notes |
|---|---|---|
| `watermark-shorts-v1.png` | Default chip — most footage | Locked Tier 1 canon. Top-left at `translate(72, 246)`. |
| `watermark-light.png` | Light footage (daytime exterior, bright snow) | Higher chip opacity (0.92) for contrast |
| `watermark-dark.png` | Dark footage (night scenes, interiors) | Lower chip opacity (0.55) so it doesn't punch a hole |

**Position canon:** top-left at `translate(72, 246)`, chip 420×96, 80% group opacity. Spec doc originally said "top-right OR bottom-left" — that was wrong; top-right collides with TikTok's For You search icon, bottom-left collides with caption/audio strip. Top-left is the only clean safe area on TikTok. See [VEC-164](https://github.com/vizuugit/vector/issues) for the full UX trace.

### Palette

| File | Purpose |
|---|---|
| `palette.json` | Final Tier 2 token set with HUD-future tokens |
| `palette-v1.json` | Tier 1 token set (kept for back-compat reference) |

### OG card

`og-1200x630.png` — landscape OG. Charcoal gradient, no synthwave horizon (that's VZU territory). Wordmark + endorsement + tagline.

## Rendering caveats

- **Don't use `font-stretch: condensed`** in any SVG that gets rendered through cairosvg. The Ubuntu Sans Condensed face isn't selected; cairosvg falls back to ExtraBold (~30% wider) and glyphs collide. Use shape-based separators (`<circle>`) instead of text-glyph bullets when relying on font metrics for positioning.
- **Pixel-verify every PNG export.** SVG that looks fine in the browser can render with collisions in cairosvg. The Tier 1 wordmark hit this twice; the Tier 2 OG card hit it once. Empirical glyph-extent sampling beats spec-math every time.
- **`<image href>` to sibling SVG** requires `unsafe=True` in cairosvg or the embedded asset silently drops. Verify via center-pixel sample after render.
- **Mono-light wordmarks need chroma-stripping post-process.** White-on-transparent text rendered through cairosvg picks up cleartype-style subpixel AA, which composites onto charcoal as visible cyan/yellow fringes on glyph edges. The render script (`tools/render-brand.py`) detects `mono` in the filename and forces `R=G=B=max(R,G,B)` per pixel, which collapses the fringe to neutral grey at the same brightness without darkening the glyphs. Black-on-transparent does not need this.

## Rendering

Renders all PNGs from the SVGs and pixel-verifies the assets that need it:

```bash
.tmp-render-venv/bin/python tools/render-brand.py [target...]
```

`target` defaults to `all`. Per-target verifications:

- `wordmark-mono-{light,dark}` → reports max chroma over `#0F1318` / `#FFFFFF` (target: edge band < 6).
- `endorsement-lockup{,-stacked}-{light,dark}` → reports the visible gap between the right edge of `VZU` and the left edge of `STUDIO` (target: <30 horizontal, <20 stacked).
- `watermark-{light,dark,shorts-v1}` → bullet/separator clearance is verified structurally; the script does not need to re-measure since all watermark variants share the same mark geometry copied from `watermark-shorts-v1`.
