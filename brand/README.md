# Vector Zen brand assets

Studio: **Vector Zen Underground** (wordmark `VECTOR ZEN [U]`).
Domain: `vector-zen.com`. Repo / package namespace: `vector-*`.

Identity is synthwave / Miami-Vice — hot magenta + deep purple + cyan accents on black, drop-shadowed badge type, palms + skyline + neon. Pairs deliberately with the GTA-VI Vice City visual cue our clients already think in.

> **Status:** locked by CEO confirmation `a06ec409` on 2026-05-06 (VEC-56). Primary / secondary designation below is the source of truth — don't ad-hoc swap them.

## Assets in this folder

| File | Use | Notes |
| --- | --- | --- |
| `vector-zen-logo.png` | **Primary logo mark** — README, GitHub org avatar, `vector-zen.com` header, Discord icon, cold-email signature, slide chrome. | 512×512, transparent background. `VZU` monogram badge with `Vector Zen / UNDERGROUND` sub-lockup. No tagline — safe to embed long-term. |
| `vector-zen-poster.png` | **Marketing tile / social post** — Twitter/X feed posts, LinkedIn posts, pinned posts. | 1254×1254, black background, with tagline `CREATORS OF SCRIPTS AND MLO FOR GTA V & GTA VI UGC`. Tagline ties the asset to the current B2B positioning — re-shoot if the positioning changes. **Not** the OG card — see below. |
| `vector-zen-og-1200x630.png` | **OG / Twitter / LinkedIn card image** — `<meta property="og:image">` and `<meta name="twitter:image">`. | 1200×630, poster centered on black canvas. Use everywhere a link-preview asset is needed. |
| `favicon/favicon.ico` | **Legacy favicon** — `<link rel="shortcut icon">`. | Multi-resolution ICO (16/32/48). |
| `favicon/vzu-16.png` … `vzu-512.png` | **PNG favicon pack** — modern `<link rel="icon">` and Apple touch icon. | 16, 32, 48, 180 (`apple-touch-icon`), 512 (`maskable`). Derived from the 512 logo via Lanczos resize; legible from 32 up, monogram-readable at 16. SVG-source replacement is on the production backlog. |

## Wordmark hierarchy

1. Full lockup — `Vector Zen Underground` (legal/footer/about copy).
2. Studio short — `Vector Zen` (body copy, headlines, conversation).
3. Stylized wordmark — `VECTOR ZEN [U]` (display type, repo header, README h1).
4. Monogram — `VZU` (badge, favicon, watermark, embroidery, small surfaces).

## What's missing (production backlog)

These are needed before the primary mark gets used in places where PNG won't cut it. Tracked separately; not a blocker for ship-on-day-one usage.

- **Vector source** — `.svg` (or `.ai` + exported `.svg`) of the badge so we can rescale / recolor without ladder edges. Required before T-shirts, embroidery, large print, and high-DPI hero use.
- **Monochrome variants** — single-color white-on-dark and black-on-light for embroidery, single-ink print, dark UI overlays, light README badges.
- **Reflowed OG card (landscape native)** — current `vector-zen-og-1200x630.png` letterboxes the square poster onto black. A native landscape composition (skyline runs full width, monogram off-center) reads better in feeds.
- **Discord server icon** — 512×512 monogram on dark, plus an animated variant if we go boosted.

Source artwork is held by the founder. When the Lead Designer role lands, variant production becomes their first ticket.

## Don'ts

- **Don't recolor.** The magenta/purple/cyan palette is the brand. Greyscale only via the monochrome variant once it exists.
- **Don't crop the poster** to use as a logo — it has the tagline baked in, which dates the asset. Use `vector-zen-logo.png` for everything that isn't a marketing post.
- **Don't put the monogram on a background that fights the inner-fill skyline.** Badge needs dark or contrasty backdrop to read.
- **Don't add a wordmark next to the badge** when both are in frame — the badge already lockups `Vector Zen / UNDERGROUND` underneath the monogram.
