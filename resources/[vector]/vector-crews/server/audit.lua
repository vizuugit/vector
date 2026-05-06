-- vector-crews/server/audit.lua
-- Fire-and-forget audit emitter per VEC-22 spec §4.2 step 5 and §5.1.
--
-- Contract:
--   * Emit `vector-crews:audit` with a §5.1-shape payload.
--   * Never await any consumer. The DB is already authoritative.
--   * On emit error or known anticheat-down state, write ONE resource-log line
--     `(citizenid, eventType, ts, payloadHash)` so an audit-substrate outage is
--     still recoverable from the resource log / Loki at the resource layer.
--   * Steps 6–7 (cache invalidate, push) MUST NOT block on audit success.

local M = _G.VectorCrewsAudit or {}
_G.VectorCrewsAudit = M

local function nowIsoUtc()
    -- os.date("!%Y-%m-%dT%H:%M:%SZ") on Lua 5.4 yields ISO-8601 UTC.
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function hashPayload(payload)
    -- We don't pull a real hash dep at v1; a stable string fingerprint is enough
    -- for the fallback log to deduplicate / correlate with Loki entries.
    local ts = payload.ts or "?"
    local et = payload.eventType or "?"
    local cid = payload.citizenid or "?"
    local crewId = payload.crewId or "?"
    return string.format("%s|%s|%s|%s", ts, et, tostring(cid), tostring(crewId))
end

local function anticheatRunning()
    if not _G.GetResourceState then
        return false
    end
    return _G.GetResourceState("vector-anticheat") == "started"
end

---@param eventType string
---@param payload table  -- must follow §5.1 shape minus ts/resource (auto-filled)
function M.emit(eventType, payload)
    payload = payload or {}
    payload.ts = payload.ts or nowIsoUtc()
    payload.resource = "vector-crews"
    payload.eventType = eventType

    local emitted = false
    if _G.TriggerEvent then
        local ok = pcall(_G.TriggerEvent, "vector-crews:audit", payload)
        emitted = ok
    end

    -- Fallback: if no handler was even reachable, write a single line to the
    -- resource log so the event survives an audit-substrate outage.
    if not emitted or not anticheatRunning() then
        local cid = payload.citizenid or "-"
        local fingerprint = hashPayload(payload)
        if _G.print then
            _G.print(
                string.format(
                    "[vector-crews:audit-fallback] cid=%s eventType=%s ts=%s fp=%s",
                    tostring(cid),
                    eventType,
                    payload.ts,
                    fingerprint
                )
            )
        end
    end
end

-- Convenience: critical-flag emit. Same shape, exists for callsite clarity.
---@param eventType string
---@param payload table
function M.emitCritical(eventType, payload)
    payload = payload or {}
    payload.severity = "critical"
    M.emit(eventType, payload)
end

return M
