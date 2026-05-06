# vector-palette

Single source of truth for the Vector color palette across HUD, NUI, marketing, and Discord embeds.

> **Binding source:** [VEC-21 §3 art-direction](/VEC/issues/VEC-21#document-art-direction). Any change to the palette requires a CEO-approved revision of that document. The PR description for a palette change MUST link the approval.

## Why this exists

The whole project shares one palette. When the same color is duplicated across resources, theme files, NUI bundles, and a Discord bot, drift is inevitable and cheaters/regressions notice the seam first. This module is the **only** place hex literals live. Every other consumer pulls a named token.

## Layout

```
resources/[vector]/vector-palette/
├── src/tokens.json     # source of truth — humans edit this
├── palette.lua         # generated — Lua consumers (server + client resources)
├── palette.js          # generated — NUI bundle / web / Discord
├── palette.css         # generated — NUI HTML, marketing site
├── fxmanifest.lua
└── README.md
```

`palette.lua`, `palette.js`, and `palette.css` are **generated artifacts**. They are committed so consumers don't need a build step at boot, but every CI run regenerates them and fails if the result drifts from `src/tokens.json` (see [Drift gate](#drift-gate)).

Run the generator manually after editing `src/tokens.json`:

```sh
node scripts/build-palette.js
```

## Lua API

```lua
local palette = exports["vector-palette"]:get() -- (or `require` if you use ox_lib)
-- direct shared_script consumption:
-- local palette = require("@vector-palette/palette")

-- entries are { r, g, b, a, hex, name }
local plate = palette.hud.plate
DrawRect(0.5, 0.95, 0.4, 0.05, plate.r, plate.g, plate.b, math.floor(plate.a * 255))

-- alpha override (returns a new table, original is frozen):
local fadedPlate = palette.withAlpha(palette.hud.plate, 0.1) -- VEC-21 execute-phase fade
```

The returned palette is **read-only**. Attempting `palette.hud.plate = ...` raises an error pointing back to `src/tokens.json`.

## JS / CSS API

```js
const { palette, withAlpha } = require("vector-palette/palette.js");
// palette.hud.alert.hex === "#E0173B"
// withAlpha(palette.hud.plate, 0.1).a === 0.1
```

```css
@import url("/resources/[vector]/vector-palette/palette.css");

.alert-banner {
  background: var(--vec-hud-alert);
  color: var(--vec-hud-text);
}
.faded-plate {
  background: var(--vec-hud-plate-rgba); /* uses default alpha */
}
```

For each token the CSS exposes three custom properties:

- `--vec-<group>-<token>` — the hex literal
- `--vec-<group>-<token>-rgba` — `rgba(r, g, b, a)` ready to drop into `background`/`color`
- `--vec-<group>-<token>-alpha` — the default alpha, when callers want to pass it to `rgba()` themselves

## Tokens

See [VEC-21 §3](/VEC/issues/VEC-21#document-art-direction) for the binding values. Quick reference (re-derived by the generator from `src/tokens.json`):

| Token | Hex | Default α | Usage |
|---|---|---|---|
| `world.softBlack` | `#0B0C0E` | 1.0 | base black |
| `world.asphalt` | `#1F2226` | 1.0 | environment dark grey |
| `world.concrete` | `#4A4E55` | 1.0 | environment mid grey |
| `world.bone` | `#F2EDE3` | 1.0 | environment off-white |
| `hud.text` | `#F2EDE3` | 1.0 | default HUD text |
| `hud.plate` | `#0B0C0E` | 0.6 | HUD background plate |
| `hud.money` | `#5DB07A` | 1.0 | money/positive economy |
| `hud.alert` | `#E0173B` | 1.0 | hostile / failure |
| `hud.warning` | `#FFB347` | 0.7 | caution / soft warning |
| `scene.sodium` | `#FF8A2B` | 1.0 | sodium streetlight accent |
| `scene.policeBlue` | `#2A6BFF` | 1.0 | police siren / cold accent |
| `scene.jewelryNeon` | `#FF3D8B` | 1.0 | jewelry-store neon |

## CI gates

Two CI lints back this module. Both live in `tools/` and are wired into the lint stage of CI ([VEC-13](/VEC/issues/VEC-13)) when that workflow lands.

### Drift gate

```sh
node scripts/build-palette.js --check
```

Re-runs the generator in dry-run mode and fails if the committed `palette.lua`, `palette.js`, or `palette.css` differ from what `src/tokens.json` would produce. Forces every palette change to come from `src/tokens.json`.

### Reject-hex gate

```sh
node tools/lint-reject-hex.js
```

Scans the entire repo (excluding `resources/[vector]/vector-palette/**`, vendored resources, and lockfiles) for any of the rejected hex literals listed in `src/tokens.json::rejectHex`. The current no-list is the gamer-RGB block called out in [VEC-21 §3.4](/VEC/issues/VEC-21#document-art-direction): `#A020F0`, `#9B30FF`, `#FF0000`, `#00FF00`, `#0000FF`. Add to that list (and re-justify in VEC-21) if more colors need to be banned.

## Smoke resource

`resources/[vector]/vector-palette-smoke/` is a tiny stub that loads both the Lua and the JS/CSS exports and renders an in-engine test card with all 12 swatches. Use it for the visual-truth gate per [AGENTS.md](/VEC/agents/fivem-dev) — start it from the smoke resource's README and screenshot at midnight in-engine.

## License

MIT (`LICENSE` in repo root). Vector-owned code.
