-- vector-heists/client/main.lua
-- State-cache reducer: ingests vector-heists:client:state pushes from the
-- server and exposes derived read-only exports (§4.2). Client never trusts a
-- value it didn't receive via push — these exports are convenience accessors
-- over the cache, not authoritative.

local activeRun = nil -- last :state push for the local player's run
local jobBoard = {} -- last :jobBoard push (templateKey → entry)
local cooldowns = {} -- last :state-derived cooldown view

RegisterNetEvent("vector-heists:client:state", function(payload)
    if payload == nil then
        activeRun = nil
        return
    end
    -- Terminal pushes (done/aborted/forfeit/reconcile) clear the cache so
    -- GetMyActiveRun reflects "no run" once the server says so.
    local s = payload.state
    if s == "done" or s == "aborted" or s == "forfeit" or s == "reconcile" then
        activeRun = nil
        return
    end
    activeRun = {
        runId = payload.runId,
        templateKey = payload.templateKey,
        state = payload.state,
        stageIdx = payload.stageIdx,
        deadlineAt = payload.deadlineAt,
        members = payload.members,
        bucketId = payload.bucketId,
    }
end)

RegisterNetEvent("vector-heists:client:jobBoard", function(entries)
    jobBoard = {}
    if type(entries) ~= "table" then
        return
    end
    for _, e in ipairs(entries) do
        if e and e.templateKey then
            jobBoard[e.templateKey] = e
            if e.cooldownRemainingSeconds and e.cooldownRemainingSeconds > 0 then
                cooldowns[e.templateKey] = e.cooldownRemainingSeconds
            else
                cooldowns[e.templateKey] = nil
            end
        end
    end
end)

RegisterNetEvent("vector-heists:client:settle", function(_payload)
    -- Settle event carries cents — handled by the NUI cash-counter (VEC-35
    -- integration child). Foundation just clears the active-run cache.
    activeRun = nil
end)

-- §4.2 client exports — read-only convenience over the cache.

exports("GetMyActiveRun", function()
    if not activeRun then
        return nil
    end
    return {
        runId = activeRun.runId,
        templateKey = activeRun.templateKey,
        state = activeRun.state,
        stageIdx = activeRun.stageIdx,
    }
end)

exports("GetJobBoard", function()
    local out = {}
    for _, e in pairs(jobBoard) do
        out[#out + 1] = e
    end
    return out
end)

exports("GetMyCooldowns", function()
    local out = {}
    for k, v in pairs(cooldowns) do
        out[k] = v
    end
    return out
end)
