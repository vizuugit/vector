-- vzu-heists/server/state_machine.lua
-- Pure-ish state machine for heist runs. No FiveM globals; deps are injected so
-- the test harness can drive the full state graph without a CitizenFX runtime.
-- Spec: VEC-23 resource-spec §2 (states + deadlines), §4.3 (intents), §6 (crash recovery).

local M = {}
M.__index = M

-- Sentinel passed to store.update fields to mean "set this column to SQL NULL".
-- Lua's `bucket_id = nil` in a table literal would disappear from the table
-- entirely, so explicit clears must use a non-nil marker. Stores translate
-- this to NULL (oxmysql arg) or to `nil` (in-memory rows).
M.NULL = false

-- Default per-state deadlines in milliseconds (§2.2). Templates may override.
M.DEFAULT_DEADLINES_MS = {
    brief = 5 * 60 * 1000,
    prep = 10 * 60 * 1000,
    execute = 25 * 60 * 1000,
    escape = 8 * 60 * 1000,
    settle = 30 * 1000,
}

local TERMINAL_STATUSES = {
    done = true,
    aborted = true,
    forfeit = true,
    reconcile = true,
}

local IN_FLIGHT_STATUSES = {
    brief = true,
    prep = true,
    execute = true,
    escape = true,
    settle = true,
}

local function isTerminal(s)
    return TERMINAL_STATUSES[s] == true
end
local function isInFlight(s)
    return IN_FLIGHT_STATUSES[s] == true
end

local function shallowCopy(t)
    if type(t) ~= "table" then
        return t
    end
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

local function deadlineFor(template, status)
    if template and template.deadlines_ms and template.deadlines_ms[status] then
        return template.deadlines_ms[status]
    end
    return M.DEFAULT_DEADLINES_MS[status]
end

---@param deps { clock: fun(): integer, store: table, audit: fun(event: table), crews: table, registry: table, log: fun(level, msg, ctx)? }
function M.new(deps)
    assert(
        deps and deps.clock and deps.store and deps.audit and deps.crews and deps.registry,
        "state_machine.new: missing required dep"
    )
    local self = setmetatable({
        deps = deps,
        runs = {}, -- runId → in-memory HeistRun
        modifiers = {}, -- v2 hook (§4.1, §10.1) — registered, not invoked at MVP
        observers = {}, -- v2 hook (§4.1, §10.2) — registered, not invoked at MVP
        deadlinesMs = M.DEFAULT_DEADLINES_MS,
    }, M)
    self.deps.log = deps.log or function() end
    return self
end

-- ---------------------------------------------------------------------------
-- v2 hook registrars (§4.1). MVP: store the fn but never invoke.

function M:registerModifier(name, fn)
    assert(type(name) == "string" and type(fn) == "function", "registerModifier: name + fn required")
    self.modifiers[name] = fn
end

function M:registerStateObserver(fn)
    assert(type(fn) == "function", "registerStateObserver: fn required")
    self.observers[#self.observers + 1] = fn
end

-- ---------------------------------------------------------------------------
-- Read-only queries (§4.1).

function M:getActiveRunForCrew(crewId)
    for _, run in pairs(self.runs) do
        if run.crew_id == crewId and isInFlight(run.status) then
            return shallowCopy(run)
        end
    end
    return nil
end

function M:getCooldownRemainingSeconds(crewId, templateKey)
    local tpl = self.deps.registry.get(templateKey)
    if not tpl then
        return 0
    end
    local now = self.deps.clock()

    local function remaining(endedAt, windowSeconds)
        if not endedAt or endedAt == 0 then
            return 0
        end
        return math.max(0, math.floor((endedAt + (windowSeconds * 1000) - now) / 1000))
    end

    local globalRemaining = remaining(self.deps.store.lastEndedAt(templateKey, nil), tpl.cooldowns.global_seconds)
    local crewRemaining = remaining(self.deps.store.lastEndedAt(templateKey, crewId), tpl.cooldowns.per_crew_seconds)
    return math.max(globalRemaining, crewRemaining)
end

-- ---------------------------------------------------------------------------
-- Internal helpers.

local function emitAudit(self, run, event, severity, details)
    self.deps.audit({
        resource = "vzu-heists",
        event = event,
        severity = severity or "audit",
        run_id = run and run.id or nil,
        crew_id = run and run.crew_id or nil,
        template_key = run and run.template_key or nil,
        details = details or {},
        ts_ms = self.deps.clock(),
    })
end

local function setDeadline(self, run)
    local ms = deadlineFor(self.deps.registry.get(run.template_key), run.status) or 0
    run.deadline_at_ms = self.deps.clock() + ms
end

local function transitionTo(self, run, status, extra)
    run.status = status
    if extra then
        for k, v in pairs(extra) do
            run[k] = v
        end
    end
    if isInFlight(status) then
        setDeadline(self, run)
    else
        run.deadline_at_ms = nil
    end
end

local function pushState(self, run)
    self.deps.audit({
        resource = "vzu-heists",
        event = "ClientStatePush",
        severity = "info",
        run_id = run.id,
        crew_id = run.crew_id,
        template_key = run.template_key,
        details = {
            state = run.status,
            stage_idx = run.stage_idx,
            deadline_at_ms = run.deadline_at_ms,
            members = run.members,
            bucket_id = run.bucket_id,
        },
        ts_ms = self.deps.clock(),
        push = true,
    })
end

local function dropFromMemory(self, runId)
    self.runs[runId] = nil
end

-- ---------------------------------------------------------------------------
-- Intent: acceptHeist — server creates a run row in Brief.

---@return integer|nil runId, string|nil err
function M:acceptHeist(citizenid, templateKey)
    local crew = self.deps.crews.getCrewByCitizen(citizenid)
    if not crew then
        return nil, "no_crew"
    end
    if not self.deps.crews.isLeader(citizenid, crew.id) then
        return nil, "not_leader"
    end

    local tpl = self.deps.registry.get(templateKey)
    if not tpl then
        return nil, "unknown_template"
    end

    if self:getActiveRunForCrew(crew.id) then
        return nil, "crew_already_running"
    end
    if self:getCooldownRemainingSeconds(crew.id, templateKey) > 0 then
        return nil, "on_cooldown"
    end

    local now = self.deps.clock()
    local runId = self.deps.store.insert({
        crew_id = crew.id,
        template_key = templateKey,
        template_version = tpl.template_version,
        status = "brief",
        started_at_ms = now,
    })

    local run = {
        id = runId,
        crew_id = crew.id,
        template_key = templateKey,
        template_version = tpl.template_version,
        status = "brief",
        stage_idx = 0,
        bucket_id = nil,
        members = shallowCopy(crew.members or { citizenid }),
        ready_set = {},
        loot_picked = {},
        started_at_ms = now,
    }
    setDeadline(self, run)
    self.runs[runId] = run

    emitAudit(self, run, "RunStarted", "audit", { template_version = tpl.template_version })
    pushState(self, run)
    return runId
end

-- ---------------------------------------------------------------------------
-- Intent: cancelBrief.

function M:cancelBrief(citizenid, runId)
    local run = self.runs[runId]
    if not run then
        return false, "no_run"
    end
    if run.status ~= "brief" then
        return false, "not_in_brief"
    end
    if not self.deps.crews.isLeader(citizenid, run.crew_id) then
        return false, "not_leader"
    end

    return self:_endRun(run, "aborted", "cancelled_by_leader")
end

-- ---------------------------------------------------------------------------
-- Intent: declareReady.

function M:declareReady(citizenid, runId)
    local run = self.runs[runId]
    if not run then
        return false, "no_run"
    end
    if run.status ~= "brief" then
        return false, "not_in_brief"
    end

    local inCrew = false
    for _, cid in ipairs(run.members) do
        if cid == citizenid then
            inCrew = true
            break
        end
    end
    if not inCrew then
        return false, "not_in_crew"
    end

    run.ready_set[citizenid] = true

    -- Transition Brief→Prep when every locked member is ready, OR if the leader forces.
    local allReady = true
    for _, cid in ipairs(run.members) do
        if not run.ready_set[cid] then
            allReady = false
            break
        end
    end
    if allReady or self.deps.crews.isLeader(citizenid, run.crew_id) then
        transitionTo(self, run, "prep")
        self.deps.store.update(run.id, { status = "prep" })
        emitAudit(self, run, "PrepEntered", "audit", {})
        pushState(self, run)
    else
        pushState(self, run)
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Intent: enterScore — Prep→Execute (crew lock + bucket allocation).

function M:enterScore(citizenid, runId)
    local run = self.runs[runId]
    if not run then
        return false, "no_run"
    end
    if run.status ~= "prep" then
        return false, "not_in_prep"
    end
    if not self.deps.crews.isLeader(citizenid, run.crew_id) then
        return false, "not_leader"
    end

    -- Crew lock — verify membership against vzu-crews.
    local crew = self.deps.crews.getCrewById(run.crew_id)
    if not crew then
        return self:_endRun(run, "aborted", "crew_lock_fail")
    end
    local liveSet = {}
    for _, cid in ipairs(crew.members or {}) do
        liveSet[cid] = true
    end
    for _, cid in ipairs(run.members) do
        if not liveSet[cid] then
            return self:_endRun(run, "aborted", "crew_lock_fail")
        end
    end

    -- Bucket allocation. Bucket allocator is implemented in VEC-35 mechanics
    -- child; the foundation hands out a deterministic stub id for now.
    local bucketId, err = self.deps.crews.allocateBucket(run.crew_id, run.id)
    if not bucketId then
        return self:_endRun(run, "aborted", err or "crew_lock_fail")
    end

    transitionTo(self, run, "execute", { bucket_id = bucketId, stage_idx = 1 })
    self.deps.store.update(run.id, { status = "execute", bucket_id = bucketId })
    emitAudit(self, run, "ScoreEntry", "audit", { bucket_id = bucketId, crew_size = #run.members })
    emitAudit(self, run, "BucketAllocated", "info", { bucket_id = bucketId })
    pushState(self, run)
    return true
end

-- ---------------------------------------------------------------------------
-- Intent: declareEscape — Execute→Escape (bucket released).

function M:declareEscape(citizenid, runId)
    local run = self.runs[runId]
    if not run then
        return false, "no_run"
    end
    if run.status ~= "execute" then
        return false, "not_in_execute"
    end

    local execStartedAt = (run.deadline_at_ms or self.deps.clock())
        - (deadlineFor(self.deps.registry.get(run.template_key), "execute") or 0)
    local durationMs = self.deps.clock() - execStartedAt
    local releasedBucket = run.bucket_id

    if releasedBucket then
        self.deps.crews.releaseBucket(releasedBucket)
    end
    transitionTo(self, run, "escape", { bucket_id = M.NULL })
    run.bucket_id = nil -- transitionTo wrote `false`; reset to nil so getters see "no bucket"
    self.deps.store.update(run.id, { status = "escape", bucket_id = M.NULL })
    emitAudit(self, run, "ScoreExit", "audit", { duration_ms = durationMs })
    if releasedBucket then
        emitAudit(self, run, "BucketReleased", "info", { bucket_id = releasedBucket })
    end
    pushState(self, run)
    return true
end

-- ---------------------------------------------------------------------------
-- Intent: declareSettle — Escape→Settle→done. Atomic: payout commit then row.

function M:declareSettle(citizenid, runId)
    local run = self.runs[runId]
    if not run then
        return false, "no_run"
    end
    if run.status ~= "escape" then
        return false, "not_in_escape"
    end

    transitionTo(self, run, "settle")
    self.deps.store.update(run.id, { status = "settle" })
    pushState(self, run)

    local payoutCents, repPoints, splits = self:_computePayout(run)

    -- Order matters for §6.4 reconcile semantics: payout is the irreversible
    -- side-effect; mark our own row only after vzu-crews has committed.
    local okPay, errPay = self.deps.crews.awardPayout(run.crew_id, run.id, payoutCents, splits)
    if not okPay then
        return self:_endRun(run, "forfeit", "settle_payout_failed:" .. tostring(errPay))
    end
    run.payout_committed = true
    self.deps.crews.awardReputation(run.crew_id, run.id, repPoints)

    local now = self.deps.clock()
    transitionTo(self, run, "done")
    self.deps.store.update(run.id, {
        status = "done",
        payout_cents = payoutCents,
        reputation_points = repPoints,
        ended_at_ms = now,
        settled_at_ms = now,
    })
    run.payout_cents = payoutCents
    run.reputation_points = repPoints
    run.ended_at_ms = now
    run.settled_at_ms = now

    emitAudit(self, run, "PayoutSettled", "audit", {
        payout_cents = payoutCents,
        reputation_points = repPoints,
        splits = splits,
    })
    pushState(self, run)
    dropFromMemory(self, runId)
    return true
end

-- ---------------------------------------------------------------------------
-- Intent: reportLoot.

function M:reportLoot(citizenid, runId, lootEntityNetId)
    local run = self.runs[runId]
    if not run then
        return false, "no_run"
    end
    if run.status ~= "execute" then
        return false, "not_in_execute"
    end

    -- The mechanics child (VEC-35) wires real entity validation. The
    -- foundation accepts the intent and records it server-side without
    -- revealing cents to the client.
    run.loot_picked[lootEntityNetId] = run.loot_picked[lootEntityNetId] or "pending"
    emitAudit(self, run, "LootPickup", "audit", { entity_net_id = lootEntityNetId })
    return true
end

-- ---------------------------------------------------------------------------
-- Intent: reportPosition (advisory cross-check; never source of truth).

function M:reportPosition(citizenid, runId, x, y, z, t)
    local run = self.runs[runId]
    if not run then
        return false, "no_run"
    end
    if run.status ~= "execute" and run.status ~= "escape" then
        return false, "wrong_state"
    end
    -- Sampling and flag emission live in VEC-35 (mechanics child).
    return true
end

-- ---------------------------------------------------------------------------
-- Failure transitions: leader_kick / all_crew_offline / external aborts.

function M:leaderKick(citizenid, runId)
    local run = self.runs[runId]
    if not run then
        return false, "no_run"
    end
    if run.status ~= "execute" then
        return false, "not_in_execute"
    end
    return self:_endRun(run, "forfeit", "leader_kick")
end

function M:noteAllCrewOffline(runId)
    local run = self.runs[runId]
    if not run then
        return false, "no_run"
    end
    if run.status == "execute" then
        return self:_endRun(run, "aborted", "all_crew_offline")
    elseif run.status == "escape" then
        return self:_endRun(run, "forfeit", "all_crew_offline")
    end
    return false, "wrong_state"
end

-- ---------------------------------------------------------------------------
-- Per-state deadline enforcement loop (§2.2). Drive in production from a
-- Citizen.CreateThread tick; drive from tests directly via this method.

function M:tick(now)
    now = now or self.deps.clock()
    for runId, run in pairs(self.runs) do
        if isInFlight(run.status) and run.deadline_at_ms and now >= run.deadline_at_ms then
            local s = run.status
            if s == "brief" then
                self:_endRun(run, "aborted", "timeout")
            elseif s == "prep" then
                self:_endRun(run, "aborted", "timeout")
            elseif s == "execute" then
                self:_endRun(run, "forfeit", "timeout")
            elseif s == "escape" then
                self:_endRun(run, "forfeit", "timeout")
            elseif s == "settle" then
                -- Settle should not normally hit timeout; if it does, that
                -- means our own settle work hung. Land in reconcile so the
                -- operator runbook (§6.4) can resolve it.
                run.status = "reconcile"
                run.deadline_at_ms = nil
                run.abort_reason = "settle_timeout"
                run.ended_at_ms = now
                self.deps.store.update(runId, {
                    status = "reconcile",
                    abort_reason = "settle_timeout",
                    ended_at_ms = now,
                })
                emitAudit(self, run, "ReconcileEntered", "audit", { template_version = run.template_version })
                pushState(self, run)
                dropFromMemory(self, runId)
            end
        end
    end
end

function M:_endRun(run, terminal, abortReason)
    local now = self.deps.clock()
    local releasedBucket = run.bucket_id
    if releasedBucket then
        self.deps.crews.releaseBucket(releasedBucket)
    end

    run.status = terminal
    run.abort_reason = abortReason
    run.bucket_id = nil
    run.ended_at_ms = now
    run.deadline_at_ms = nil

    self.deps.store.update(run.id, {
        status = terminal,
        bucket_id = M.NULL,
        abort_reason = abortReason,
        ended_at_ms = now,
    })

    if terminal == "aborted" then
        emitAudit(self, run, "RunAborted", "audit", { abort_reason = abortReason })
    elseif terminal == "forfeit" then
        emitAudit(self, run, "RunForfeit", "audit", { abort_reason = abortReason })
    end
    if releasedBucket then
        emitAudit(self, run, "BucketReleased", "info", { bucket_id = releasedBucket })
    end
    pushState(self, run)
    dropFromMemory(self, run.id)
    return true
end

function M:_computePayout(run)
    local tpl = self.deps.registry.get(run.template_key)
    if not tpl then
        return 0, 0, {}
    end
    -- Foundation calibrates flat (base→cap clamp). Real loot-table-weighted
    -- payout calculation lands in VEC-35 (mechanics child).
    local base = tpl.payout and tpl.payout.base_cents or 0
    local cap = tpl.payout and tpl.payout.cap_cents or base
    local payoutCents = math.min(cap, base)
    local repPoints =
        math.min(tpl.reputation and tpl.reputation.cap_points or 0, tpl.reputation and tpl.reputation.base_points or 0)
    local splits = {}
    local share = #run.members > 0 and math.floor(payoutCents / #run.members) or 0
    for _, cid in ipairs(run.members) do
        splits[#splits + 1] = { citizenid = cid, cents = share }
    end
    return payoutCents, repPoints, splits
end

-- ---------------------------------------------------------------------------
-- Boot recovery scan (§6.2). Eight crash cases.

local CRASH_MAP = {
    brief = { terminal = "aborted", reason = "server_crash_brief" },
    prep = { terminal = "aborted", reason = "server_crash_prep" },
    execute = { terminal = "forfeit", reason = "server_crash_execute" },
    escape = { terminal = "forfeit", reason = "server_crash_escape" },
}

---@return { runId: integer, before: string, after: string, reason: string }[]
function M:bootRecover()
    local outcomes = {}
    local rows = self.deps.store.findInFlight() or {}
    local now = self.deps.clock()

    -- §6.2 has eight crash-decision branches. Six write a row, two are no-ops.
    local function decide(before, runId)
        local mapped = CRASH_MAP[before]
        if mapped then
            return mapped.terminal, mapped.reason
        end
        if before == "settle" then
            -- Distinguish pre-payout vs post-payout (§6.2). We consult the
            -- vzu-crews audit log for an AwardPayout matching this runId.
            -- In tests the stub returns nil for pre-payout, an integer for
            -- post-payout.
            local credited = self.deps.crews.lookupAwardedPayout(runId)
            if credited and credited > 0 then
                return "reconcile", "server_crash_settle_post_payout"
            end
            return "forfeit", "server_crash_settle_pre_payout"
        end
        -- Terminal + reconcile rows are no-ops (the eighth/seventh branches).
        -- reconcile is terminal-pending and surfaces to the operator dashboard
        -- (integration child); leave as-is.
        if before == "reconcile" or isTerminal(before) then
            return nil, "noop"
        end
        return nil, "unknown_status"
    end

    for _, row in ipairs(rows) do
        local before = row.status
        local terminal, reason = decide(before, row.id)

        if terminal == nil then
            if reason == "unknown_status" then
                self.deps.log("warn", "boot_recover_unknown_status", { run_id = row.id, status = before })
            else
                outcomes[#outcomes + 1] = { runId = row.id, before = before, after = before, reason = reason }
            end
        else
            local fakeRun = {
                id = row.id,
                crew_id = row.crew_id,
                template_key = row.template_key,
                template_version = row.template_version,
            }
            if terminal == "reconcile" then
                self.deps.store.update(row.id, {
                    status = terminal,
                    abort_reason = reason,
                    ended_at_ms = now,
                })
                emitAudit(self, fakeRun, "ReconcileEntered", "audit", { template_version = row.template_version })
            else
                self.deps.store.update(row.id, {
                    status = terminal,
                    bucket_id = M.NULL,
                    abort_reason = reason,
                    ended_at_ms = now,
                })
                local evt = terminal == "aborted" and "RunAborted" or "RunForfeit"
                emitAudit(self, fakeRun, evt, "audit", { abort_reason = reason })
            end
            outcomes[#outcomes + 1] = { runId = row.id, before = before, after = terminal, reason = reason }
        end
    end

    return outcomes
end

-- Exported for testing / introspection.
M._isTerminal = isTerminal
M._isInFlight = isInFlight

-- Bridge between FiveM (no `require` for sibling server_scripts) and the test
-- harness (uses Lua's standard `require`). FiveM execution sees the module
-- via a global; tests get it via the return value.
if rawget(_G, "package") and not rawget(_G, "VzuHeists_SM") then
    _G.VzuHeists_SM = M
elseif _G then
    _G.VzuHeists_SM = M
end

return M
