-- vzu-heists/test/state_machine_test.lua
-- Pure-Lua unit tests for the heist state machine.
-- Run from the repo root with:  lua resources/[vector]/vzu-heists/test/state_machine_test.lua
-- Spec: VEC-23 resource-spec §2.1 (transitions), §2.2 (deadlines), §6.2 (recovery).

package.path = table.concat({
    "resources/[vector]/vzu-heists/?.lua",
    "resources/[vector]/vzu-heists/?/init.lua",
    package.path,
}, ";")

local SM = require("server.state_machine")

-- ---------------------------------------------------------------------------
-- Tiny test framework — one in-process suite, plain asserts, deterministic.

local cases, failures = {}, {}
local function test(name, fn)
    cases[#cases + 1] = { name = name, fn = fn }
end
local function assertEq(actual, expected, msg)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(msg or "assertEq", tostring(expected), tostring(actual)), 2)
    end
end
local function assertTrue(cond, msg)
    if not cond then
        error(msg or "assertTrue", 2)
    end
end
local function assertNil(v, msg)
    if v ~= nil then
        error((msg or "assertNil") .. ": got " .. tostring(v), 2)
    end
end

-- ---------------------------------------------------------------------------
-- Test fixtures: deps that the state machine accepts.

local function newClock()
    local clk = { now = 1000 }
    function clk:tick()
        return self.now
    end
    function clk:advance(ms)
        self.now = self.now + ms
    end
    return clk
end

local function newStore()
    local rows = {}
    local nextId = 0
    return {
        rows = rows,
        insert = function(row)
            nextId = nextId + 1
            local r = {}
            for k, v in pairs(row) do
                r[k] = v
            end
            r.id = nextId
            rows[nextId] = r
            return nextId
        end,
        update = function(id, fields)
            assert(rows[id], "update: missing row " .. tostring(id))
            for k, v in pairs(fields) do
                if v == false then
                    rows[id][k] = nil
                else
                    rows[id][k] = v
                end
            end
        end,
        findInFlight = function()
            local out = {}
            for _, r in pairs(rows) do
                if r.status ~= "done" and r.status ~= "aborted" and r.status ~= "forfeit" then
                    out[#out + 1] = r
                end
            end
            table.sort(out, function(a, b)
                return a.id < b.id
            end)
            return out
        end,
        lastEndedAt = function(_templateKey, _crewId)
            return 0
        end,
        -- Test-only helpers:
        seed = function(row)
            nextId = nextId + 1
            row.id = nextId
            rows[nextId] = row
            return nextId
        end,
    }
end

local function newAuditSink()
    local events = {}
    local sink = function(e)
        events[#events + 1] = e
    end
    return events, sink
end

local function newCrewsStub(opts)
    opts = opts or {}
    local awardedRuns = {}
    return {
        crewByCitizen = opts.crew or { id = 7, members = { "CID-A", "CID-B" }, leader = "CID-A" },
        getCrewByCitizen = function(_)
            return opts.crew or { id = 7, members = { "CID-A", "CID-B" }, leader = "CID-A" }
        end,
        getCrewById = function(crewId)
            local crew = opts.crewById and opts.crewById[crewId]
                or (opts.crew or { id = 7, members = { "CID-A", "CID-B" } })
            return crew
        end,
        isLeader = function(citizenid, _)
            return citizenid == (opts.leader or "CID-A")
        end,
        allocateBucket = function(_, runId)
            if opts.bucketFails then
                return nil, "bucket_pool_full"
            end
            return 2000 + runId
        end,
        releaseBucket = function(_)
            return true
        end,
        awardPayout = function(_, runId, cents, _)
            awardedRuns[runId] = cents
            if opts.payoutFails then
                return false, "ledger_down"
            end
            return true
        end,
        awardReputation = function(_, _, _)
            return true
        end,
        lookupAwardedPayout = function(runId)
            if opts.crashedPostPayout and opts.crashedPostPayout[runId] then
                return opts.crashedPostPayout[runId]
            end
            return awardedRuns[runId]
        end,
        _awarded = awardedRuns,
    }
end

local DEFAULT_TEMPLATE = {
    template_version = 1,
    key = "jewelry_score",
    public_name = "Vangelico Score",
    crew_size_min = 2,
    crew_size_max = 4,
    cooldowns = { global_seconds = 3600, per_crew_seconds = 7200 },
    bucket_strategy = { mode = "hybrid", interior_phase = "Execute", return_to_zero = "Escape" },
    payout = { base_cents = 80000, cap_cents = 240000, split_policy = "crew_split_config" },
    reputation = { base_points = 80, cap_points = 200 },
    stages = {},
    loot_table = {},
    modifiers = {},
    observers = {},
}

local function newRegistry(template)
    local byKey = { [template.key] = template }
    return {
        get = function(key)
            -- Accept both `Registry.get(key)` and `Registry:get(key)` styles.
            if type(key) == "table" then
                return nil
            end
            return byKey[key]
        end,
        keys = function()
            local out = {}
            for k in pairs(byKey) do
                out[#out + 1] = k
            end
            return out
        end,
    }
end

local function newRig(opts)
    opts = opts or {}
    local clock = newClock()
    local store = newStore()
    local audit, auditSink = newAuditSink()
    local crews = newCrewsStub(opts)
    local registry = newRegistry(opts.template or DEFAULT_TEMPLATE)
    local sm = SM.new({
        clock = function()
            return clock:tick()
        end,
        store = store,
        audit = auditSink,
        crews = crews,
        registry = registry,
        log = function() end,
    })
    return {
        sm = sm,
        clock = clock,
        store = store,
        audit = audit,
        crews = crews,
        registry = registry,
    }
end

local function eventsOfType(audit, kind)
    local out = {}
    for _, e in ipairs(audit) do
        if e.event == kind then
            out[#out + 1] = e
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Happy path: Brief → Prep → Execute → Escape → Settle → done.

test("happy path Brief→Prep→Execute→Escape→Settle→done", function()
    local rig = newRig()
    local sm, store, clock, audit, crews = rig.sm, rig.store, rig.clock, rig.audit, rig.crews

    local runId, err = sm:acceptHeist("CID-A", "jewelry_score")
    assertNil(err)
    assertEq(store.rows[runId].status, "brief", "row in brief on accept")
    local started = eventsOfType(audit, "RunStarted")
    assertEq(#started, 1, "one RunStarted audit emitted")

    -- Both members must declare ready before Brief→Prep.
    sm:declareReady("CID-B", runId) -- partial — leader still pending
    assertEq(store.rows[runId].status, "brief", "still in brief after one member ready")
    sm:declareReady("CID-A", runId)
    assertEq(store.rows[runId].status, "prep", "Brief→Prep when all ready")

    sm:enterScore("CID-A", runId)
    assertEq(store.rows[runId].status, "execute", "Prep→Execute via enterScore")
    assertTrue(store.rows[runId].bucket_id ~= nil, "bucket allocated on Execute entry")

    sm:declareEscape("CID-A", runId)
    assertEq(store.rows[runId].status, "escape", "Execute→Escape")
    assertNil(store.rows[runId].bucket_id, "bucket released to 0 on Escape entry")

    clock:advance(1000)
    sm:declareSettle("CID-A", runId)
    assertEq(store.rows[runId].status, "done", "Settle→done")
    assertEq(store.rows[runId].payout_cents, 80000, "payout_cents recorded")
    assertEq(store.rows[runId].reputation_points, 80, "rep_points recorded")
    assertTrue(crews._awarded[runId] ~= nil, "vzu-crews:AwardPayout called")
    assertTrue(#eventsOfType(audit, "PayoutSettled") == 1, "PayoutSettled audit emitted")
end)

-- ---------------------------------------------------------------------------
-- §2.1 failure edges, all wired.

test("Brief — cancel by leader → aborted", function()
    local rig = newRig()
    local runId = rig.sm:acceptHeist("CID-A", "jewelry_score")
    rig.sm:cancelBrief("CID-A", runId)
    assertEq(rig.store.rows[runId].status, "aborted")
    assertEq(rig.store.rows[runId].abort_reason, "cancelled_by_leader")
end)

test("Brief — timeout → aborted at 5min", function()
    local rig = newRig()
    local runId = rig.sm:acceptHeist("CID-A", "jewelry_score")
    rig.clock:advance(5 * 60 * 1000 + 1)
    rig.sm:tick()
    assertEq(rig.store.rows[runId].status, "aborted")
    assertEq(rig.store.rows[runId].abort_reason, "timeout")
end)

test("Prep — crew_lock_fail → aborted (member churn at enterScore)", function()
    local rig = newRig({ crew = { id = 7, members = { "CID-A", "CID-B" }, leader = "CID-A" } })
    local runId = rig.sm:acceptHeist("CID-A", "jewelry_score")
    rig.sm:declareReady("CID-A", runId)
    rig.sm:declareReady("CID-B", runId)
    -- Simulate member churn: vzu-crews now reports a smaller crew when we
    -- try to lock at enterScore.
    rig.crews.getCrewById = function(_)
        return { id = 7, members = { "CID-A" } }
    end
    rig.sm:enterScore("CID-A", runId)
    assertEq(rig.store.rows[runId].status, "aborted")
    assertEq(rig.store.rows[runId].abort_reason, "crew_lock_fail")
end)

test("Prep — crew_lock_fail → aborted (bucket allocator empty)", function()
    local rig = newRig({ bucketFails = true })
    local runId = rig.sm:acceptHeist("CID-A", "jewelry_score")
    rig.sm:declareReady("CID-A", runId)
    rig.sm:declareReady("CID-B", runId)
    rig.sm:enterScore("CID-A", runId)
    assertEq(rig.store.rows[runId].status, "aborted")
    assertEq(rig.store.rows[runId].abort_reason, "bucket_pool_full")
end)

test("Prep — timeout → aborted at 10min", function()
    local rig = newRig()
    local runId = rig.sm:acceptHeist("CID-A", "jewelry_score")
    rig.sm:declareReady("CID-A", runId)
    rig.sm:declareReady("CID-B", runId)
    rig.clock:advance(10 * 60 * 1000 + 1)
    rig.sm:tick()
    assertEq(rig.store.rows[runId].status, "aborted")
    assertEq(rig.store.rows[runId].abort_reason, "timeout")
end)

test("Execute — all_crew_offline → aborted (bucket freed, no payout)", function()
    local rig = newRig()
    local runId = rig.sm:acceptHeist("CID-A", "jewelry_score")
    rig.sm:declareReady("CID-A", runId)
    rig.sm:declareReady("CID-B", runId)
    rig.sm:enterScore("CID-A", runId)
    rig.sm:noteAllCrewOffline(runId)
    assertEq(rig.store.rows[runId].status, "aborted")
    assertEq(rig.store.rows[runId].abort_reason, "all_crew_offline")
    assertNil(rig.store.rows[runId].bucket_id, "bucket released")
    assertNil(rig.crews._awarded[runId], "no payout on aborted Execute")
end)

test("Execute — timeout → forfeit at 25min", function()
    local rig = newRig()
    local runId = rig.sm:acceptHeist("CID-A", "jewelry_score")
    rig.sm:declareReady("CID-A", runId)
    rig.sm:declareReady("CID-B", runId)
    rig.sm:enterScore("CID-A", runId)
    rig.clock:advance(25 * 60 * 1000 + 1)
    rig.sm:tick()
    assertEq(rig.store.rows[runId].status, "forfeit")
    assertEq(rig.store.rows[runId].abort_reason, "timeout")
end)

test("Execute — leader_kick → forfeit", function()
    local rig = newRig()
    local runId = rig.sm:acceptHeist("CID-A", "jewelry_score")
    rig.sm:declareReady("CID-A", runId)
    rig.sm:declareReady("CID-B", runId)
    rig.sm:enterScore("CID-A", runId)
    rig.sm:leaderKick("CID-A", runId)
    assertEq(rig.store.rows[runId].status, "forfeit")
    assertEq(rig.store.rows[runId].abort_reason, "leader_kick")
end)

test("Escape — all_crew_offline → forfeit (loot lost)", function()
    local rig = newRig()
    local runId = rig.sm:acceptHeist("CID-A", "jewelry_score")
    rig.sm:declareReady("CID-A", runId)
    rig.sm:declareReady("CID-B", runId)
    rig.sm:enterScore("CID-A", runId)
    rig.sm:declareEscape("CID-A", runId)
    rig.sm:noteAllCrewOffline(runId)
    assertEq(rig.store.rows[runId].status, "forfeit")
    assertEq(rig.store.rows[runId].abort_reason, "all_crew_offline")
end)

test("Escape — timeout → forfeit at 8min", function()
    local rig = newRig()
    local runId = rig.sm:acceptHeist("CID-A", "jewelry_score")
    rig.sm:declareReady("CID-A", runId)
    rig.sm:declareReady("CID-B", runId)
    rig.sm:enterScore("CID-A", runId)
    rig.sm:declareEscape("CID-A", runId)
    rig.clock:advance(8 * 60 * 1000 + 1)
    rig.sm:tick()
    assertEq(rig.store.rows[runId].status, "forfeit")
    assertEq(rig.store.rows[runId].abort_reason, "timeout")
end)

test("Settle — payout failure → forfeit (no double-pay)", function()
    local rig = newRig({ payoutFails = true })
    local runId = rig.sm:acceptHeist("CID-A", "jewelry_score")
    rig.sm:declareReady("CID-A", runId)
    rig.sm:declareReady("CID-B", runId)
    rig.sm:enterScore("CID-A", runId)
    rig.sm:declareEscape("CID-A", runId)
    rig.sm:declareSettle("CID-A", runId)
    assertEq(rig.store.rows[runId].status, "forfeit")
    assertTrue(rig.store.rows[runId].abort_reason:find("settle_payout_failed") ~= nil)
end)

-- ---------------------------------------------------------------------------
-- Per-state deadline expiry — assert at the per-state ceiling per §2.2.

test("deadline ceilings match spec §2.2", function()
    local stateCases = {
        {
            state = "brief",
            ms = 5 * 60 * 1000,
            terminal = "aborted",
            reason = "timeout",
            arrange = function(rig)
                return (rig.sm:acceptHeist("CID-A", "jewelry_score"))
            end,
        },
        {
            state = "prep",
            ms = 10 * 60 * 1000,
            terminal = "aborted",
            reason = "timeout",
            arrange = function(rig)
                local id = rig.sm:acceptHeist("CID-A", "jewelry_score")
                rig.sm:declareReady("CID-A", id)
                rig.sm:declareReady("CID-B", id)
                return id
            end,
        },
        {
            state = "execute",
            ms = 25 * 60 * 1000,
            terminal = "forfeit",
            reason = "timeout",
            arrange = function(rig)
                local id = rig.sm:acceptHeist("CID-A", "jewelry_score")
                rig.sm:declareReady("CID-A", id)
                rig.sm:declareReady("CID-B", id)
                rig.sm:enterScore("CID-A", id)
                return id
            end,
        },
        {
            state = "escape",
            ms = 8 * 60 * 1000,
            terminal = "forfeit",
            reason = "timeout",
            arrange = function(rig)
                local id = rig.sm:acceptHeist("CID-A", "jewelry_score")
                rig.sm:declareReady("CID-A", id)
                rig.sm:declareReady("CID-B", id)
                rig.sm:enterScore("CID-A", id)
                rig.sm:declareEscape("CID-A", id)
                return id
            end,
        },
    }
    for _, c in ipairs(stateCases) do
        local rig = newRig()
        local id = c.arrange(rig)

        -- One ms before deadline: should NOT have expired.
        rig.clock:advance(c.ms - 1)
        rig.sm:tick()
        assertEq(rig.store.rows[id].status, c.state, ("%s: not expired before ceiling"):format(c.state))

        -- Cross the deadline: should expire.
        rig.clock:advance(2)
        rig.sm:tick()
        assertEq(rig.store.rows[id].status, c.terminal, ("%s: expired at ceiling → %s"):format(c.state, c.terminal))
        assertEq(rig.store.rows[id].abort_reason, c.reason)
    end
end)

-- ---------------------------------------------------------------------------
-- §6.2 boot recovery — eight crash cases.

test("boot recovery handles all eight crash cases (§6.2)", function()
    local rig = newRig({
        crashedPostPayout = { [6] = 150000 }, -- run 6 had AwardPayout commit before crash
    })
    -- Seed the store with one row in each crash-state (skip terminal IDs we
    -- don't expect the scan to touch).
    local function seed(status, extra)
        local row = {
            crew_id = 7,
            template_key = "jewelry_score",
            template_version = 1,
            status = status,
            started_at_ms = 0,
        }
        if extra then
            for k, v in pairs(extra) do
                row[k] = v
            end
        end
        return rig.store.seed(row)
    end
    local idBrief = seed("brief")
    local idPrep = seed("prep")
    local idExecute = seed("execute", { bucket_id = 2001 })
    local idEscape = seed("escape")
    local idSettlePre = seed("settle")
    local idSettlePost = seed("settle")
    -- Match crashedPostPayout map: post-payout case is the 6th seeded row.
    assertEq(idSettlePost, 6, "expected idSettlePost == 6 to match crashedPostPayout map")
    local idReconcile = seed("reconcile")

    local outcomes = rig.sm:bootRecover()
    local byId = {}
    for _, o in ipairs(outcomes) do
        byId[o.runId] = o
    end

    -- 1. brief → aborted / server_crash_brief
    assertEq(rig.store.rows[idBrief].status, "aborted")
    assertEq(rig.store.rows[idBrief].abort_reason, "server_crash_brief")
    -- 2. prep → aborted / server_crash_prep
    assertEq(rig.store.rows[idPrep].status, "aborted")
    assertEq(rig.store.rows[idPrep].abort_reason, "server_crash_prep")
    -- 3. execute → forfeit / server_crash_execute (bucket released)
    assertEq(rig.store.rows[idExecute].status, "forfeit")
    assertEq(rig.store.rows[idExecute].abort_reason, "server_crash_execute")
    assertNil(rig.store.rows[idExecute].bucket_id)
    -- 4. escape → forfeit / server_crash_escape
    assertEq(rig.store.rows[idEscape].status, "forfeit")
    assertEq(rig.store.rows[idEscape].abort_reason, "server_crash_escape")
    -- 5. settle pre-payout → forfeit / server_crash_settle_pre_payout
    assertEq(rig.store.rows[idSettlePre].status, "forfeit")
    assertEq(rig.store.rows[idSettlePre].abort_reason, "server_crash_settle_pre_payout")
    -- 6. settle post-payout → reconcile / server_crash_settle_post_payout
    assertEq(rig.store.rows[idSettlePost].status, "reconcile")
    assertEq(rig.store.rows[idSettlePost].abort_reason, "server_crash_settle_post_payout")
    -- 7-8. reconcile + terminal rows are no-ops (terminal-pending and terminal).
    assertEq(rig.store.rows[idReconcile].status, "reconcile")
    assertEq(byId[idReconcile].after, "reconcile")
    assertEq(byId[idReconcile].reason, "noop")

    -- Seed a terminal done/aborted row to exercise the terminal-noop branch.
    local idDone = rig.store.seed({
        crew_id = 7,
        template_key = "jewelry_score",
        template_version = 1,
        status = "done",
        started_at_ms = 0,
    })
    -- store.findInFlight excludes terminals, so a fresh scan must not modify
    -- the done row even when seeded mid-test.
    local outcomes2 = rig.sm:bootRecover()
    for _, o in ipairs(outcomes2) do
        assertTrue(o.runId ~= idDone, "terminal-done rows are excluded from scan")
    end

    -- ReconcileEntered audit must fire exactly once for the post-payout case.
    local reconEntered = eventsOfType(rig.audit, "ReconcileEntered")
    assertEq(#reconEntered, 1, "ReconcileEntered audit emitted once")
    assertEq(reconEntered[1].run_id, idSettlePost)
end)

-- ---------------------------------------------------------------------------
-- Acceptance check from VEC-34: scripted acceptHeist for a stub crew inserts
-- a Brief row AND emits RunStarted to the audit channel.

test("acceptHeist scripted: Brief row inserted + RunStarted audit", function()
    local rig = newRig()
    local runId, err = rig.sm:acceptHeist("CID-A", "jewelry_score")
    assertNil(err)
    assertEq(rig.store.rows[runId].status, "brief")
    assertEq(rig.store.rows[runId].crew_id, 7)
    assertEq(rig.store.rows[runId].template_key, "jewelry_score")
    assertEq(rig.store.rows[runId].template_version, 1)
    local started = eventsOfType(rig.audit, "RunStarted")
    assertEq(#started, 1, "RunStarted on audit channel")
    assertEq(started[1].run_id, runId)
    assertEq(started[1].crew_id, 7)
    assertEq(started[1].severity, "audit")
end)

-- ---------------------------------------------------------------------------
-- v2 hook registrars are present and accept fns without invocation at MVP.

test("v2 hooks register without invocation", function()
    local rig = newRig()
    local invoked = false
    rig.sm:registerModifier("seasonal_double", function()
        invoked = true
    end)
    rig.sm:registerStateObserver(function()
        invoked = true
    end)
    -- Drive a full happy path; observers must NOT be invoked at MVP.
    local runId = rig.sm:acceptHeist("CID-A", "jewelry_score")
    rig.sm:declareReady("CID-A", runId)
    rig.sm:declareReady("CID-B", runId)
    rig.sm:enterScore("CID-A", runId)
    rig.sm:declareEscape("CID-A", runId)
    rig.sm:declareSettle("CID-A", runId)
    assertEq(invoked, false, "MVP v2 hooks register but never fire")
end)

-- ---------------------------------------------------------------------------
-- Runner.

local passed = 0
for _, c in ipairs(cases) do
    local ok, errMsg = pcall(c.fn)
    if ok then
        passed = passed + 1
        print(("  OK   %s"):format(c.name))
    else
        failures[#failures + 1] = { name = c.name, err = errMsg }
        print(("  FAIL %s\n       %s"):format(c.name, errMsg))
    end
end

print(("\n%d/%d passed"):format(passed, #cases))
if #failures > 0 then
    os.exit(1)
end
