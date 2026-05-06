-- vzu-crews/shared/config.lua
-- Spec: VEC-22 resource-spec §10 Q1 (cooldown), §5.5 (ceilings), §10 Q3 (denylist).
-- Phase 1 surface only — lifecycle (createCrew/invite/etc.) config keys stub here for Phase 2.

-- Exposed both as a global for FiveM script ordering and as a return value for `require`/tests.
VzuCrewsConfig = _G.VzuCrewsConfig or {}

-- §10 Q1: anti-grief withdraw cooldown thresholds (basis points = 1/100th of a percent).
VzuCrewsConfig.bigWithdrawPctBps = 2500            -- 25% per-action trigger
VzuCrewsConfig.dailyWithdrawPctBps = 5000          -- 50% / 24h cumulative trigger
VzuCrewsConfig.disbandCooldownSeconds = 86400      -- 24h disband lock once tripped

-- §5.5: anti-cheat ceiling fallbacks when vzu-heists isn't loaded yet.
-- Sized to the highest configured MVP heist tier per VEC-18 mode pitch.
VzuCrewsConfig.maxPayoutCentsDefault = 5 * 100 * 1000   -- $5,000.00 in cents
VzuCrewsConfig.maxRepPointsDefault = 100

-- §5.4 invariant
VzuCrewsConfig.maxMembers = 6

-- §2.3 createCrew validation (Phase 2 use, included here so all config lives in one file)
VzuCrewsConfig.nameMinLen = 3
VzuCrewsConfig.nameMaxLen = 40
VzuCrewsConfig.namePattern = "^[A-Za-z0-9 _%-']+$"

-- §10 Q3 static denylist (case-insensitive substring match in createCrew validator).
-- CMO can edit this list without code changes.
VzuCrewsConfig.nameDenylist = {
    -- Vector brand strings
    "vector",
    -- Staff impersonation
    "staff",
    "admin",
    "moderator",
    "mod",
    "owner",
    "developer",
    -- Vanilla GTA gangs (lore-impersonation)
    "ballas",
    "families",
    "vagos",
    "marabunta",
    "lost mc",
    "aztecas",
}

-- §2.5: resources allowed to invoke vzu-crews:internal:* events.
-- Adding here is a code change + ADR per §10 risks ("vzu-heists resource-allowlist drift").
VzuCrewsConfig.internalAllowlist = {
    ["vzu-heists"] = true,
}

return VzuCrewsConfig
