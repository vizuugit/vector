# ADR-0001: Server platform — FiveM (CitizenFX)

- Status: **Accepted** — 2026-05-05
- Authors: CTO
- Supersedes: —
- Related: VEC-2 (technical roadmap & platform pick)

## Context

Vector ships a flagship multiplayer GTA V server plus content/mods around it. We had to pick the runtime layer the entire product sits on:

- **FiveM (CitizenFX)** — the dominant GTA V multiplayer platform. Mature, large player base, big resource ecosystem (qbox, ox_lib, etc.), permissive to small studios, runs Lua-first server scripting.
- **RAGE Multiplayer** — smaller community, more flexible client capabilities, but a fraction of the player pool.
- **alt:V** — modern architecture, JS/C# friendly, but the smallest community of the three and a steeper player-acquisition climb.
- **Vanilla GTA V single-player mods only** — sidesteps the multiplayer problem entirely but cuts off the largest revenue lever (a flagship server).

## Decision

We build on **FiveM** for v0 through closed alpha (D60) and beyond, using **qbox** as the resource baseline.

## Rationale

1. **Player pool.** FiveM's installed base is roughly an order of magnitude larger than RAGE MP and alt:V combined. For a new studio, "where the players already are" beats every other technical merit. This is the dominant factor.
2. **Resource ecosystem.** qbox + ox_lib + the wider FiveM resource catalog mean we are not building a framework; we are *integrating* one. That moves a 6-month tax off our roadmap.
3. **MIT-aligned core.** qbox is MIT-licensed, which matches our owned-code license posture and avoids GPL-style obligations on our gameplay code.
4. **Hiring.** The pool of experienced FiveM Lua devs is the largest of the three. RAGE/alt:V hires are scarcer and more expensive.
5. **Cfx.re platform terms.** Cfx.re explicitly tolerates community-monetized servers (donations, cosmetics) provided no Rockstar IP is sold. This matches our "free mods, monetize the server experience" posture.

## Consequences

### Accepted trade-offs

- We inherit FiveM's anti-cheat ceiling (EAC + server-side checks). That is "good enough", not "great".
- Lua-first server scripting; we accept Lua as the primary language and bring in C# / JS only for specific resources where Lua is a poor fit.
- We tie ourselves to Cfx.re's TOS evolution. If Cfx.re changes its monetization rules, we feel it.

### Locked-in choices that follow from this ADR

- Database = MariaDB (FiveM-native default, qbox compatibility).
- Cache / queue layer = Redis.
- CI Lua linting = `luacheck` + `stylua`. See [`.luacheckrc`](../../.luacheckrc) and [`stylua.toml`](../../stylua.toml).
- Hosting = Hetzner dedicated, monthly cap $200–$400 (see [`docs/infra-spend.md`](../infra-spend.md)).
- Server scripting language defaults to Lua. New resources MUST justify any non-Lua choice in the resource README.

### Reversibility

Switching platforms post-launch is expensive but not impossible. Code at the **gameplay-design** layer (economies, jobs, scenarios) survives a port; code at the **framework / resource** layer mostly does not. We keep that boundary clean: gameplay logic in our own resources, framework calls behind thin adapters under `resources/_lib/`.

## Alternatives considered

### RAGE Multiplayer

Pros: more powerful client modding, different aesthetic direction. Cons: ~10x smaller player base, worse hiring, weaker resource ecosystem. Verdict: **rejected**. Player pool dominates.

### alt:V

Pros: modern architecture, first-class JS/C#. Cons: smallest community of the three, steepest user-acquisition climb, less third-party content. Verdict: **rejected** for v0. Possible future re-evaluation if alt:V meaningfully grows its player base.

### Single-player mods only

Pros: zero server infra. Cons: forecloses the flagship server, which is the central revenue pillar. Verdict: **rejected** as the *core* path. Premium SP mods may still ship as a side product within Rockstar's tolerance window — that decision lives outside this ADR.

## Validation / next decisions

- Once closed alpha is live (target D60), revisit anti-cheat posture and decide whether to extend EAC with server-side telemetry or invest in a third-party layer.
- ADR-0002 will cover the resource-loading and asset-pipeline conventions on top of this platform pick.
