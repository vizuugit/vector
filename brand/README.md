# Vector brand assets

Two-tier brand architecture: the publisher (VZU Studio) and the product (Vector RP).

| Layer | Marks | Where |
|---|---|---|
| **Publisher** | Vector Zen Underground · VZU Studio · `VZU` monogram | this dir (root `brand/`) — synthwave/Miami-Vice tone |
| **Product** | Vector RP — sub-brand for the FiveM RP server | [`brand/vector-rp/`](./vector-rp/README.md) — grounded crime-drama tone |

The publisher is the studio behind the products. The product is what the audience plays. Different audiences, different tones — keep them separate.

## Quick rules

- **Publisher palette is magenta-purple-cyan synthwave.** Don't recolor.
- **Product palette is charcoal + cyan + sodium-amber.** No magenta. Ever.
- **Endorsement lockup** lives under product; it's `Vector RP — by VZU Studio` styled in the product tone with a small VZU monogram. Use it on long-form (YouTube, blog headers, Patreon hero, OG cards on the product domain).

## Tier 2 status (2026-05-07)

The publisher pack lives on `feat/vec-62-brand-variants` (PR pending merge to main). The product pack lives on `feat/vector-rp-brand-pack` (this branch). When the publisher pack lands on main, the product endorsement lockup will be updated to embed the canonical VZU monogram SVG instead of the current typeset stand-in.

## See also

- [`vector-rp/README.md`](./vector-rp/README.md) — product brand pack, asset map, do/don't rules.
