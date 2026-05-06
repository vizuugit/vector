-- vector-crews/server/state.lua
-- Single chokepoint for every write to crews / crew_members / crew_cosmetic_unlocks.
-- Spec: VEC-22 resource-spec §4.2, §7.4. Every other server file MUST go through this module.
--
-- Transaction model
-- -----------------
-- oxmysql ships a queue-style transaction primitive (`MySQL.transaction(queries, cb)`),
-- not an interactive "open a connection" handle. To honor the §4.2 / §7.4 requirement that
-- callers be able to wrap multiple mutations across multiple crews atomically, we expose:
--
--   local txn = state.beginTxn()
--   state.applyBankDelta(crewId, +X, { ..., txn = txn })   -- appends UPDATE to txn.queries
--   state.applyBankDelta(victim, -X, { ..., txn = txn, clampToZero = true })
--   state.commit(txn)                                       -- one MySQL.transaction call
--
-- Without a txn handle, mutators run their own MySQL.transaction (a single-statement txn
-- still goes through transaction so audit/cache step ordering is consistent).
--
-- The CHECK constraint `chk_crews_bank_nonneg` is the durable backstop for
-- bank_cents >= 0. The Lua-side clamp is for nicer error reporting + audit shape;
-- a bug that bypasses the clamp still gets stopped at the DB.

local M = _G.VectorCrewsState or {}
_G.VectorCrewsState = M

local Validators = M.validators or {}
M.validators = Validators

-- ---------------------------------------------------------------------------
-- Pure validators (no FiveM runtime; busted-unit-testable).
-- ---------------------------------------------------------------------------

---@param name string|nil
---@param denylist string[]
---@return boolean ok
---@return string|nil error
function Validators.isValidName(name, denylist)
    if type(name) ~= "string" then
        return false, "name_required"
    end
    local trimmed = name:match("^%s*(.-)%s*$")
    if not trimmed or #trimmed < 3 or #trimmed > 40 then
        return false, "name_length"
    end
    if not trimmed:match("^[A-Za-z0-9 _%-']+$") then
        return false, "name_charset"
    end
    if denylist then
        local lower = trimmed:lower()
        for _, banned in ipairs(denylist) do
            if banned and banned ~= "" and lower:find(banned, 1, true) then
                return false, "name_denylisted"
            end
        end
    end
    return true
end

---@param policy CrewSplitPolicy|string
---@param weights table<string, integer>|nil
---@param leaderBonusBps integer|nil
---@return boolean ok
---@return string|nil error
function Validators.isValidSplitConfig(policy, weights, leaderBonusBps)
    if policy == "equal" then
        return true
    end
    if policy == "leader_weighted" then
        if leaderBonusBps == nil then
            return false, "split_leader_bonus_required"
        end
        if type(leaderBonusBps) ~= "number" or leaderBonusBps < 0 or leaderBonusBps > 5000 then
            return false, "split_leader_bonus_range"
        end
        return true
    end
    if policy == "custom" then
        if type(weights) ~= "table" then
            return false, "split_weights_required"
        end
        local total = 0
        local count = 0
        for _, w in pairs(weights) do
            if type(w) ~= "number" or w < 0 or w > 1000 then
                return false, "split_weight_range"
            end
            total = total + w
            count = count + 1
        end
        if count == 0 or total <= 0 then
            return false, "split_weights_empty"
        end
        return true
    end
    return false, "split_policy_unknown"
end

---@param beforeBank integer
---@param deltaCents integer
---@param clampToZero boolean|nil
---@return integer newBank
---@return integer appliedDelta
---@return boolean clamped
function Validators.computeBankDelta(beforeBank, deltaCents, clampToZero)
    if type(beforeBank) ~= "number" then
        beforeBank = 0
    end
    if type(deltaCents) ~= "number" then
        deltaCents = 0
    end
    local target = beforeBank + deltaCents
    if target < 0 then
        if clampToZero then
            return 0, -beforeBank, true
        end
        -- non-clamped path: caller must pre-validate; we still report what would happen.
        return target, deltaCents, false
    end
    return target, deltaCents, false
end

---@param beforeRep integer
---@param points integer
---@return integer newRep
---@return integer appliedDelta
function Validators.computeReputationDelta(beforeRep, points)
    if type(beforeRep) ~= "number" then
        beforeRep = 0
    end
    if type(points) ~= "number" then
        points = 0
    end
    local target = beforeRep + points
    if target < 0 then
        return 0, -beforeRep
    end
    return target, points
end

---@param policy CrewSplitPolicy|string
---@param amountCents integer
---@param recipients string[]
---@param leaderCitizenid string
---@param leaderBonusBps integer|nil
---@param customWeights table<string, integer>|nil
---@return table<string, integer> perMemberCents
function Validators.distributeShares(
    policy,
    amountCents,
    recipients,
    leaderCitizenid,
    leaderBonusBps,
    customWeights
)
    local out = {}
    if type(recipients) ~= "table" or #recipients == 0 or amountCents == 0 then
        return out
    end
    if policy == "equal" then
        local n = #recipients
        local floor = math.floor
        local each = floor(amountCents / n)
        local rem = amountCents - each * n
        for i = 1, n do
            local cid = recipients[i]
            -- Remainder cents go to the first recipients (deterministic by list order).
            out[cid] = each + (i <= rem and 1 or 0)
        end
        return out
    end
    if policy == "leader_weighted" then
        local bps = leaderBonusBps or 0
        -- Leader takes (1 + bps/10000) shares; everyone else takes 1 share.
        local n = #recipients
        local leaderUnits = 10000 + bps
        local memberUnits = 10000
        local totalUnits = 0
        for _, cid in ipairs(recipients) do
            totalUnits = totalUnits + (cid == leaderCitizenid and leaderUnits or memberUnits)
        end
        if totalUnits <= 0 then
            return out
        end
        local distributed = 0
        for i, cid in ipairs(recipients) do
            local units = cid == leaderCitizenid and leaderUnits or memberUnits
            local share
            if i == n then
                share = amountCents - distributed
            else
                share = math.floor(amountCents * units / totalUnits)
                distributed = distributed + share
            end
            out[cid] = share
        end
        return out
    end
    if policy == "custom" then
        local weights = customWeights or {}
        local totalWeight = 0
        for _, cid in ipairs(recipients) do
            totalWeight = totalWeight + (weights[cid] or 0)
        end
        if totalWeight <= 0 then
            return Validators.distributeShares("equal", amountCents, recipients, leaderCitizenid)
        end
        local distributed = 0
        local n = #recipients
        for i, cid in ipairs(recipients) do
            local w = weights[cid] or 0
            local share
            if i == n then
                share = amountCents - distributed
            else
                share = math.floor(amountCents * w / totalWeight)
                distributed = distributed + share
            end
            out[cid] = share
        end
        return out
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Transaction handle.
-- ---------------------------------------------------------------------------

local function newTxnId()
    -- Simple monotonic id; only used for local correlation, never persisted.
    M._txnSeq = (M._txnSeq or 0) + 1
    return M._txnSeq
end

---@return table txn
function M.beginTxn()
    return { id = newTxnId(), queries = {}, committed = false, rolledBack = false }
end

---@param txn table
---@param query string
---@param values table|nil
local function appendQuery(txn, query, values)
    txn.queries[#txn.queries + 1] = { query = query, values = values or {} }
end

---@param txn table
---@return boolean ok
---@return string|nil error
function M.commit(txn)
    if not txn or txn.committed or txn.rolledBack then
        return false, "txn_invalid_state"
    end
    if #txn.queries == 0 then
        txn.committed = true
        return true
    end
    if not _G.MySQL or not _G.MySQL.transaction then
        return false, "oxmysql_unavailable"
    end
    local ok = _G.MySQL.transaction.await(txn.queries)
    txn.committed = true
    if not ok then
        return false, "txn_commit_failed"
    end
    return true
end

---@param txn table
function M.rollback(txn)
    if not txn or txn.committed then
        return false, "txn_invalid_state"
    end
    txn.queries = {}
    txn.rolledBack = true
    return true
end

-- Internal helper: run a single statement either inside a caller's txn or
-- as its own one-statement transaction.
---@param query string
---@param values table
---@param ctx table|nil
---@return boolean ok
---@return string|nil error
local function runStatement(query, values, ctx)
    if ctx and ctx.txn then
        appendQuery(ctx.txn, query, values)
        return true
    end
    if not _G.MySQL or not _G.MySQL.transaction then
        return false, "oxmysql_unavailable"
    end
    local ok = _G.MySQL.transaction.await({ { query = query, values = values } })
    if not ok then
        return false, "db_write_failed"
    end
    return true
end

-- Internal helper: read crew row outside the txn (oxmysql's queue txn cannot read mid-flight).
---@param crewId integer
---@return table|nil row
local function readCrewRow(crewId)
    if not _G.MySQL or not _G.MySQL.single then
        return nil
    end
    return _G.MySQL.single.await(
        "SELECT id, name, leader_citizenid, bank_cents, reputation, split_policy, split_config, "
            .. "radio_channel, status, created_at, disbanded_at, bank_disband_locked_until "
            .. "FROM crews WHERE id = ?",
        { crewId }
    )
end
M._readCrewRow = readCrewRow -- exposed for bank.lua

-- ---------------------------------------------------------------------------
-- Mutators (every DB write goes through here).
-- ---------------------------------------------------------------------------

---@param crewId integer
---@param deltaCents integer
---@param ctx CrewBankDeltaCtx|nil
---@return boolean ok
---@return integer|nil bankCentsAfter
---@return integer|nil appliedDelta
---@return boolean|nil clamped
---@return string|nil error
function M.applyBankDelta(crewId, deltaCents, ctx)
    ctx = ctx or {}
    if type(crewId) ~= "number" then
        return false, nil, nil, nil, "crew_id_required"
    end
    if type(deltaCents) ~= "number" or deltaCents == 0 then
        return false, nil, nil, nil, "delta_required"
    end
    local row = readCrewRow(crewId)
    if not row then
        return false, nil, nil, nil, "crew_not_found"
    end
    local before = row.bank_cents or 0
    local newBank, applied, clamped = Validators.computeBankDelta(before, deltaCents, ctx.clampToZero)
    if newBank < 0 then
        return false, nil, nil, nil, "insufficient_funds"
    end
    local ok, err = runStatement(
        "UPDATE crews SET bank_cents = bank_cents + ? WHERE id = ? AND status = 'active'",
        { applied, crewId },
        ctx
    )
    if not ok then
        return false, nil, nil, nil, err
    end
    return true, newBank, applied, clamped, nil
end

---@param crewId integer
---@param points integer
---@param ctx CrewBankDeltaCtx|nil
---@return boolean ok
---@return integer|nil reputationAfter
---@return string|nil error
function M.applyReputationDelta(crewId, points, ctx)
    ctx = ctx or {}
    if type(crewId) ~= "number" then
        return false, nil, "crew_id_required"
    end
    if type(points) ~= "number" or points == 0 then
        return false, nil, "delta_required"
    end
    local row = readCrewRow(crewId)
    if not row then
        return false, nil, "crew_not_found"
    end
    local newRep, applied = Validators.computeReputationDelta(row.reputation or 0, points)
    local ok, err = runStatement(
        "UPDATE crews SET reputation = GREATEST(reputation + ?, 0) WHERE id = ? AND status = 'active'",
        { applied, crewId },
        ctx
    )
    if not ok then
        return false, nil, err
    end
    return true, newRep, nil
end

---@param crewId integer
---@param untilEpochSeconds integer|nil  -- nil clears the lock
---@param ctx table|nil
---@return boolean ok
---@return string|nil error
function M.setBankDisbandLockUntil(crewId, untilEpochSeconds, ctx)
    if type(crewId) ~= "number" then
        return false, "crew_id_required"
    end
    local query, values
    if untilEpochSeconds == nil then
        query = "UPDATE crews SET bank_disband_locked_until = NULL WHERE id = ?"
        values = { crewId }
    else
        query = "UPDATE crews SET bank_disband_locked_until = FROM_UNIXTIME(?) WHERE id = ?"
        values = { untilEpochSeconds, crewId }
    end
    return runStatement(query, values, ctx)
end

-- Phase 2 mutators: shape locked, bodies stubbed so callers compile against the chokepoint.
-- Phase 1 callers MUST NOT invoke these. Phase 2 (lifecycle UX) lands the bodies.

---@param crewId integer
---@param citizenid string
---@param op "join"|"leave"|"kick"|"transfer"
---@param ctx table|nil
function M.applyMembershipChange(crewId, citizenid, op, ctx)
    return false, "phase2_not_implemented"
end

---@param crewId integer
---@param sku string
---@param actorCitizenid string|nil
---@param sourceTag string|nil
---@param ctx table|nil
function M.applyCosmeticUnlock(crewId, sku, actorCitizenid, sourceTag, ctx)
    return false, "phase2_not_implemented"
end

---@param crewId integer
---@param policy CrewSplitPolicy|string
---@param weights table<string, integer>|nil
---@param leaderBonusBps integer|nil
---@param ctx table|nil
function M.setSplitConfig(crewId, policy, weights, leaderBonusBps, ctx)
    return false, "phase2_not_implemented"
end

return M
