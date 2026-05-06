-- vzu-crews/server/main.lua
-- Phase 1 wiring: exports + internal events for vzu-heists.
-- Lifecycle event handlers (createCrew/invitePlayer/etc.) land in Phase 2.
-- Spec: VEC-22 resource-spec §2.1, §2.5.

-- Modules are loaded as globals via fxmanifest server_scripts ordering.
local Config = _G.VzuCrewsConfig
local state = _G.VzuCrewsState
local bank = _G.VzuCrewsBank
local audit = _G.VzuCrewsAudit
local redis = _G.VzuCrewsRedis

-- Backend selection at boot time. Operator may override via convar.
local function bootRedisBackend()
    local mode = "null"
    if _G.GetConvar then
        local convar = _G.GetConvar("vzu-crews:redisBackend", "")
        if convar and convar ~= "" then
            mode = convar
        end
    end
    redis.configure(mode)
    if _G.print then
        _G.print(string.format("[vzu-crews] redis backend = %s (available=%s)",
            redis.backend(), tostring(redis.available())))
    end
end

if _G.AddEventHandler then
    _G.AddEventHandler("onResourceStart", function(resourceName)
        if _G.GetCurrentResourceName and resourceName == _G.GetCurrentResourceName() then
            bootRedisBackend()
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Read exports
-- ---------------------------------------------------------------------------

local function getCrew(crewId)
    return state._readCrewRow(crewId)
end

local function getCrewByCitizen(citizenid)
    if not _G.MySQL or not _G.MySQL.single then
        return nil
    end
    return _G.MySQL.single.await(
        [[SELECT c.id, c.name, c.leader_citizenid, c.bank_cents, c.reputation,
                 c.split_policy, c.split_config, c.radio_channel, c.status, c.created_at,
                 c.disbanded_at, c.bank_disband_locked_until
          FROM crews c
          INNER JOIN crew_members m ON m.crew_id = c.id
          WHERE m.citizenid = ? AND m.left_at IS NULL AND c.status = 'active'
          LIMIT 1]],
        { citizenid }
    )
end

local function getMembers(crewId)
    if not _G.MySQL or not _G.MySQL.query then
        return {}
    end
    return _G.MySQL.query.await(
        [[SELECT crew_id, citizenid, role, split_weight, joined_at, left_at
          FROM crew_members WHERE crew_id = ? AND left_at IS NULL
          ORDER BY joined_at ASC]],
        { crewId }
    ) or {}
end

local function isLeader(crewId, citizenid)
    local row = state._readCrewRow(crewId)
    if not row then
        return false
    end
    return row.leader_citizenid == citizenid
end

local function getSplitConfig(crewId)
    local row = state._readCrewRow(crewId)
    if not row then
        return nil
    end
    local cfg
    if row.split_config and _G.json then
        local ok, parsed = pcall(_G.json.decode, row.split_config)
        if ok then
            cfg = parsed
        end
    end
    return {
        policy = row.split_policy or "equal",
        weights = (cfg and cfg.weights) or {},
        leaderBonusBps = cfg and cfg.leaderBonusBps or nil,
    }
end

local function getBankCents(crewId)
    local row = state._readCrewRow(crewId)
    return row and row.bank_cents or nil
end

if _G.exports then
    _G.exports("GetCrew", getCrew)
    _G.exports("GetCrewByCitizen", getCrewByCitizen)
    _G.exports("GetMembers", getMembers)
    _G.exports("IsLeader", isLeader)
    _G.exports("GetSplitConfig", getSplitConfig)
    _G.exports("GetBankCents", getBankCents)
    _G.exports("AwardPayout", function(crewId, amountCents, ctx)
        return bank.AwardPayout(crewId, amountCents, ctx)
    end)
    _G.exports("AwardReputation", function(crewId, points, ctx)
        return bank.AwardReputation(crewId, points, ctx)
    end)
    -- v2 seam: stored but never invoked at v1.
    local hookSeq = 0
    _G.exports("RegisterPayoutHook", function(_fn)
        hookSeq = hookSeq + 1
        return { ok = true, hookId = "vc-hook-" .. hookSeq }
    end)
    -- Successor helper exposed for v2; reads only.
    _G.exports("AcquireSuccessorIfLeaderOffline", function(_crewId)
        return nil
    end)
end

-- ---------------------------------------------------------------------------
-- Internal server events (resource-allowlisted)
-- ---------------------------------------------------------------------------

local function isAllowedCaller()
    if not _G.GetInvokingResource then
        return false, ""
    end
    local invoker = _G.GetInvokingResource() or ""
    return Config.internalAllowlist[invoker] == true, invoker
end

local function rejectInvalidInternal(eventName, invoker)
    audit.emitCritical("crew.invalid_internal_call", {
        context = { event = eventName, invoker = invoker or "" },
    })
end

if _G.AddEventHandler then
    _G.AddEventHandler("vzu-crews:internal:awardPayout", function(crewId, amountCents, ctx)
        local ok, invoker = isAllowedCaller()
        if not ok then
            rejectInvalidInternal("awardPayout", invoker)
            return
        end
        bank.AwardPayout(crewId, amountCents, ctx)
    end)

    _G.AddEventHandler("vzu-crews:internal:awardReputation", function(crewId, points, ctx)
        local ok, invoker = isAllowedCaller()
        if not ok then
            rejectInvalidInternal("awardReputation", invoker)
            return
        end
        bank.AwardReputation(crewId, points, ctx)
    end)

    -- Phase 1 stub: vzu-heists will write the heist-lock key in Redis directly via its
    -- own redis adapter; the chokepoint check exists so a future caller can flip it.
    _G.AddEventHandler("vzu-crews:internal:setHeistLock", function(_crewId, _locked, _runId)
        local ok, invoker = isAllowedCaller()
        if not ok then
            rejectInvalidInternal("setHeistLock", invoker)
            return
        end
        -- No-op at Phase 1 — see §7.4 for why state.lua is the only writer.
    end)
end

return {
    -- Re-export for tests / Phase 2 callers that prefer require() over fx exports.
    state = state,
    bank = bank,
    audit = audit,
    redis = redis,
    config = Config,
}
