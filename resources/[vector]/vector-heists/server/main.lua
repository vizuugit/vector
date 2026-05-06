-- vector-heists/server/main.lua
-- Wires the pure state-machine module to the CitizenFX runtime: oxmysql for
-- persistence, FiveM events for intents, exports for read-only queries, a
-- timed thread for deadline enforcement, and a boot-time migration + recovery
-- pass.
-- Spec: VEC-23 resource-spec §4 (events + exports), §5 (DB), §6 (recovery).

local SM = _G.VectorHeists_SM or require("server.state_machine")

local RESOURCE = "vector-heists"
local TICK_INTERVAL_MS = 1000

-- ---------------------------------------------------------------------------
-- Migration runner. Apply db/*.sql once at resource start. We track applied
-- files in vector_heists_migrations (auto-created) so re-running the resource
-- is idempotent. Apply via the qbox-standard oxmysql driver.

local function applyMigrations()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS vector_heists_migrations (
            file_name  VARCHAR(255) NOT NULL,
            applied_at DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
            PRIMARY KEY (file_name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    local files = { "db/0001_create_heist_runs.sql" }
    for _, name in ipairs(files) do
        local applied = MySQL.scalar.await("SELECT 1 FROM vector_heists_migrations WHERE file_name = ?", { name })
        if not applied then
            local sql = LoadResourceFile(RESOURCE, name)
            assert(sql and #sql > 0, "vector-heists: migration file missing: " .. name)
            MySQL.query.await(sql)
            MySQL.query.await("INSERT INTO vector_heists_migrations (file_name) VALUES (?)", { name })
            print(("[vector-heists] applied migration %s"):format(name))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Adapters: clock, store, audit, crews, registry, log.

local function nowMs()
    return math.floor(GetGameTimer())
end

local function msToDateTime(ms)
    if not ms then
        return nil
    end
    return os.date("!%Y-%m-%d %H:%M:%S", math.floor(ms / 1000))
end

local Store = {}

function Store.insert(row)
    local id = MySQL.insert.await(
        [[INSERT INTO heist_runs
            (crew_id, template_key, template_version, status, started_at)
          VALUES (?, ?, ?, ?, ?)]],
        {
            row.crew_id,
            row.template_key,
            row.template_version,
            row.status,
            msToDateTime(row.started_at_ms),
        }
    )
    return id
end

function Store.update(id, fields)
    local cols, args = {}, {}
    -- The state machine uses `false` (SM.NULL) as the explicit "set to NULL"
    -- sentinel — Lua table literals would otherwise drop nil keys entirely.
    local function arg(v)
        if v == false then
            return nil
        end
        return v
    end
    for k, v in pairs(fields) do
        if k == "ended_at_ms" then
            cols[#cols + 1] = "ended_at = ?"
            args[#args + 1] = msToDateTime(arg(v))
        elseif k == "settled_at_ms" then
            cols[#cols + 1] = "settled_at = ?"
            args[#args + 1] = msToDateTime(arg(v))
        elseif
            k == "bucket_id"
            or k == "payout_cents"
            or k == "reputation_points"
            or k == "abort_reason"
            or k == "status"
        then
            cols[#cols + 1] = k .. " = ?"
            args[#args + 1] = arg(v)
        end
    end
    if #cols == 0 then
        return
    end
    args[#args + 1] = id
    MySQL.query.await(("UPDATE heist_runs SET %s WHERE id = ?"):format(table.concat(cols, ", ")), args)
end

function Store.findInFlight()
    return MySQL.query.await([[
        SELECT id, crew_id, template_key, template_version, status, bucket_id
          FROM heist_runs
         WHERE status NOT IN ('done','aborted','forfeit','reconcile')
            OR status = 'reconcile'
    ]]) or {}
end

function Store.lastEndedAt(templateKey, crewId)
    local row
    if crewId then
        row = MySQL.single.await(
            [[SELECT UNIX_TIMESTAMP(ended_at) * 1000 AS ms FROM heist_runs
               WHERE template_key = ? AND crew_id = ? AND status = 'done'
               ORDER BY ended_at DESC LIMIT 1]],
            { templateKey, crewId }
        )
    else
        row = MySQL.single.await(
            [[SELECT UNIX_TIMESTAMP(ended_at) * 1000 AS ms FROM heist_runs
               WHERE template_key = ? AND status = 'done'
               ORDER BY ended_at DESC LIMIT 1]],
            { templateKey }
        )
    end
    return row and row.ms or 0
end

local Audit = function(event)
    if event.push then
        -- §4.4 client:state push. Only crew members receive it.
        local netIds = exports["vector-crews"]:GetCrewNetIds(event.crew_id) or {}
        for _, src in ipairs(netIds) do
            TriggerClientEvent("vector-heists:client:state", src, {
                runId = event.run_id,
                templateKey = event.template_key,
                state = event.details.state,
                stageIdx = event.details.stage_idx,
                deadlineAt = event.details.deadline_at_ms,
                members = event.details.members,
                bucketId = event.details.bucket_id,
            })
        end
        return
    end
    -- §4.5 server-internal audit channel. The Loki sink wires VEC-35.
    TriggerEvent("vector-heists:server:audit", event)
end

local Crews = {
    getCrewByCitizen = function(citizenid)
        return exports["vector-crews"]:GetCrewByCitizen(citizenid)
    end,
    getCrewById = function(crewId)
        return exports["vector-crews"]:GetCrewById(crewId)
    end,
    isLeader = function(citizenid, crewId)
        return exports["vector-crews"]:IsLeader(citizenid, crewId)
    end,
    -- VEC-35 owns the bucket allocator; the foundation hands out a deterministic
    -- per-run id so the state machine can be exercised end-to-end without it.
    allocateBucket = function(crewId, runId)
        return 1000 + (runId % 64000)
    end,
    releaseBucket = function(_bucketId)
        return true
    end,
    awardPayout = function(crewId, runId, payoutCents, splits)
        return exports["vector-crews"]:AwardPayout(crewId, runId, payoutCents, splits)
    end,
    awardReputation = function(crewId, runId, repPoints)
        return exports["vector-crews"]:AwardReputation(crewId, runId, repPoints)
    end,
    -- §6.2 pre/post payout discriminator. Wires through to vector-crews's audit
    -- log via VEC-22's API; until that lands the boot scan will always treat
    -- crashed-Settle as pre-payout (forfeit, no double-pay risk).
    lookupAwardedPayout = function(runId)
        if exports["vector-crews"] and exports["vector-crews"].LookupAwardedPayout then
            return exports["vector-crews"]:LookupAwardedPayout(runId)
        end
        return nil
    end,
}

-- Template registry. The mechanics child (VEC-35) ships the real templates
-- under templates/*.lua; the foundation provides an empty registry surface so
-- the resource boots cleanly and exports return [].
local Registry
Registry = {
    _byKey = {},
    -- state_machine.new requires a registry with a function-call `get(key)`,
    -- so this is plain function-call style; we never use `Registry:get(...)`.
    get = function(key)
        return Registry._byKey[key]
    end,
    keys = function()
        local out = {}
        for k in pairs(Registry._byKey) do
            out[#out + 1] = k
        end
        table.sort(out)
        return out
    end,
    register = function(template)
        assert(template and template.key, "registry.register: template.key required")
        Registry._byKey[template.key] = template
    end,
}

local Log = function(level, msg, ctx)
    print(("[vector-heists][%s] %s %s"):format(level, msg, ctx and json.encode(ctx) or ""))
end

local sm

-- ---------------------------------------------------------------------------
-- Read-only exports (§4.1).

exports("GetActiveRunForCrew", function(crewId)
    return sm and sm:getActiveRunForCrew(crewId) or nil
end)
exports("GetTemplate", function(key)
    return Registry.get(key)
end)
exports("GetTemplates", function()
    return Registry.keys()
end)
exports("GetCooldownRemainingSeconds", function(crewId, templateKey)
    return sm and sm:getCooldownRemainingSeconds(crewId, templateKey) or 0
end)

exports("RegisterModifier", function(name, fn)
    return sm and sm:registerModifier(name, fn)
end)
exports("RegisterStateObserver", function(fn)
    return sm and sm:registerStateObserver(fn)
end)

-- Internal export for the mechanics child to load templates.
exports("RegisterTemplate", function(template)
    return Registry.register(template)
end)

-- ---------------------------------------------------------------------------
-- Server intent events (§4.3). All accept intents only; values flow back via
-- vector-heists:client:state push, never via event reply.

local function citizenidFor(src)
    if exports.qbx_core and exports.qbx_core.GetPlayer then
        local p = exports.qbx_core:GetPlayer(src)
        return p and p.PlayerData and p.PlayerData.citizenid or nil
    end
    return nil
end

local INTENT_HANDLERS = {
    ["vector-heists:server:acceptHeist"] = function(cid, payload)
        return sm:acceptHeist(cid, payload.templateKey)
    end,
    ["vector-heists:server:cancelBrief"] = function(cid, payload)
        return sm:cancelBrief(cid, payload.runId)
    end,
    ["vector-heists:server:declareReady"] = function(cid, payload)
        return sm:declareReady(cid, payload.runId)
    end,
    ["vector-heists:server:enterScore"] = function(cid, payload)
        return sm:enterScore(cid, payload.runId)
    end,
    ["vector-heists:server:declareEscape"] = function(cid, payload)
        return sm:declareEscape(cid, payload.runId)
    end,
    ["vector-heists:server:declareSettle"] = function(cid, payload)
        return sm:declareSettle(cid, payload.runId)
    end,
    ["vector-heists:server:reportLoot"] = function(cid, payload)
        return sm:reportLoot(cid, payload.runId, payload.lootEntityNetId)
    end,
    ["vector-heists:server:reportPosition"] = function(cid, payload)
        return sm:reportPosition(cid, payload.runId, payload.x, payload.y, payload.z, payload.t)
    end,
}

for eventName, handler in pairs(INTENT_HANDLERS) do
    RegisterNetEvent(eventName, function(payload)
        local cid = citizenidFor(source)
        if not cid then
            return
        end
        local ok, err = handler(cid, payload or {})
        if not ok and err then
            Log("warn", eventName, { citizenid = cid, err = err })
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Boot. Apply migrations, instantiate the state machine, scan for crashed
-- runs, then start the deadline-enforcement tick.

AddEventHandler("onResourceStart", function(name)
    if name ~= GetCurrentResourceName() then
        return
    end

    applyMigrations()

    sm = SM.new({
        clock = nowMs,
        store = Store,
        audit = Audit,
        crews = Crews,
        registry = Registry,
        log = Log,
    })

    local outcomes = sm:bootRecover()
    Log("info", "boot_recover_done", { outcomes = #outcomes })

    Citizen.CreateThread(function()
        while true do
            Wait(TICK_INTERVAL_MS)
            if sm then
                sm:tick(nowMs())
            end
        end
    end)
end)
