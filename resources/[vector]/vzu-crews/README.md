# vzu-crews

Server-authoritative crew lifecycle, persistent crew bank/reputation, and the payout sink that `vzu-heists` settles into.

- Spec: [VEC-22 resource-spec](/VEC/issues/VEC-22#document-resource-spec) (Rev 2, locked).
- Phase tracker: [VEC-37](/VEC/issues/VEC-37) (this resource — Phase 1 walking skeleton).
- Phase 2 (lifecycle UX, client + NUI): not yet filed.

## Phase 1 scope

**In:** migrations, `state.lua` chokepoint, deposit / withdraw / payout pipeline (with §10 Q1 anti-grief cooldown), `AwardPayout` / `AwardReputation` exports with idempotency + ceiling + optional `ctx.txn`, audit emitter, anti-cheat allowlist gate on `vzu-crews:internal:*` events.

**Out (Phase 2):** `createCrew` / `invitePlayer` / `respondInvite` / `kickMember` / `leaveCrew` / `transferLeadership` / `setSplitConfig` server events, radio channel allocation, ox_inventory stash registration, client-side cache, NUI, locales.

## Layout

```
vzu-crews/
├── fxmanifest.lua          server-only at Phase 1
├── shared/
│   ├── config.lua          tunables (cooldown bps, ceilings, denylist, allowlist)
│   └── types.lua           EmmyLua annotations
├── server/
│   ├── audit.lua           fire-and-forget audit emitter + resource-log fallback
│   ├── redis.lua           pluggable adapter (null|inmem|redis-fivem)
│   ├── state.lua           chokepoint — every crews/crew_members write goes through here
│   ├── bank.lua            deposit / withdraw / AwardPayout / AwardReputation
│   └── main.lua            exports + internal-event allowlist gating
├── db/
│   ├── 0001_create_crews.sql
│   ├── 0002_create_crew_members.sql
│   └── 0003_create_crew_cosmetic_unlocks.sql
└── test/
    └── state_validators_spec.lua   pure-lua busted tests, no FiveM runtime
```

## Convars

| Convar | Default | Effect |
| --- | --- | --- |
| `vzu-crews:redisBackend` | `null` | One of `null` / `inmem` / `redis-fivem`. `null` rejects idempotency-required calls with `service_degraded` (matches the spec for missing redis). `inmem` is for single-process dev / local-stack happy-path testing only. |
| `vzu-crews:bigWithdrawPctBps` | (config) | Override §10 Q1 single-withdraw threshold. |
| `vzu-crews:dailyWithdrawPctBps` | (config) | Override §10 Q1 24h cumulative threshold. |
| `vzu-crews:disbandCooldownSeconds` | (config) | Override §10 Q1 cooldown duration. |

## Tests

```
busted resources/[vector]/vzu-crews/test/
```

Pure-Lua validator tests; no FiveM runtime needed. Integration tests run against the [VEC-15](/VEC/issues/VEC-15) local qbox stack (deposit → payout → withdraw, idempotency, cooldown, daily window, redis-down rejection, ceiling fallback, multi-crew txn).

## Architectural rule (CTO review item)

Every write on `crews` / `crew_members` / `crew_cosmetic_unlocks` is funneled through `server/state.lua`. New writers MUST go through the chokepoint or get a CTO-signed ADR. See VEC-22 §7.4.
