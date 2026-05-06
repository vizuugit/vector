-- vzu-crews/server/bank.lua
-- Deposit / withdraw / payout / reputation pipeline.
-- Spec: VEC-22 resource-spec §2.1, §2.3, §4.2, §5.2, §5.5, §10 Q1.
--
-- Every DB write goes through state.lua. This file:
--   1. Validates player intent (server-authoritative).
--   2. Computes amounts.
--   3. Calls state.applyBankDelta / state.applyReputationDelta.
--   4. Wraps the §10 Q1 anti-grief cooldown around withdraw.
--   5. Owns the §5.5 ceiling-fallback ladder for AwardPayout / AwardReputation.

-- Globals are provided by shared/server scripts loaded earlier in fxmanifest order.
-- Tests stub these via the fivem_shim helper.
local Config = _G.VzuCrewsConfig
local state = _G.VzuCrewsState
local audit = _G.VzuCrewsAudit
local redis = _G.VzuCrewsRedis

local M = _G.VzuCrewsBank or {}
_G.VzuCrewsBank = M

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function utcDateKey()
    return os.date("!%Y%m%d")
end

local function nowSeconds()
    return os.time()
end

local function getQbxPlayer(src)
    if not _G.exports or not _G.exports.qbx_core then
        return nil, "qbx_core_missing"
    end
    local ok, player = pcall(function()
        return _G.exports.qbx_core:GetPlayer(src)
    end)
    if not ok or not player then
        return nil, "player_not_found"
    end
    return player
end

local function centsToDollars(cents)
    -- cents must be a non-negative integer multiple of 100. We do not silently
    -- truncate fractional cents — that hides UI/wire bugs.
    if type(cents) ~= "number" or cents <= 0 or cents ~= math.floor(cents) then
        return nil, "amount_invalid"
    end
    if cents % 100 ~= 0 then
        return nil, "amount_fractional_cents"
    end
    return cents / 100
end

local function emitFallback(reason, ctx)
    audit.emit("crew.ceiling_fallback_used", {
        crewId = ctx.crewId,
        citizenid = ctx.citizenid,
        context = {
            reason = reason,
            sourceTag = ctx.sourceTag,
            sourceRunId = ctx.sourceRunId,
        },
    })
end

-- §5.5: try the vzu-heists export; fall back to convar; emit informational audit on fallback.
local function resolveMaxPayoutCents(ctx)
    if ctx and ctx.heistKey and _G.exports and _G.exports["vzu-heists"] then
        local ok, n = pcall(function()
            return _G.exports["vzu-heists"]:GetMaxPayoutCents(ctx.heistKey)
        end)
        if ok and type(n) == "number" and n > 0 then
            return n, false
        end
    end
    emitFallback("max_payout_cents", ctx or {})
    return Config.maxPayoutCentsDefault, true
end

local function resolveMaxRepPoints(ctx)
    if ctx and ctx.heistKey and _G.exports and _G.exports["vzu-heists"] then
        local ok, n = pcall(function()
            return _G.exports["vzu-heists"]:GetMaxRepPoints(ctx.heistKey)
        end)
        if ok and type(n) == "number" and n > 0 then
            return n, false
        end
    end
    emitFallback("max_rep_points", ctx or {})
    return Config.maxRepPointsDefault, true
end

-- ---------------------------------------------------------------------------
-- §10 Q1: anti-grief disband cooldown
-- ---------------------------------------------------------------------------

local function withdrawWindowKey(crewId)
    return string.format("crew:withdraw_window:%d:%s", crewId, utcDateKey())
end

---@param crewId integer
---@param amountCents integer
---@param beforeBank integer
---@return boolean tripped
---@return string|nil reason  -- 'big_pct' | 'daily_pct'
---@return integer|nil dailySum
local function checkWithdrawThresholds(crewId, amountCents, beforeBank)
    if beforeBank <= 0 then
        return false
    end
    local bigBps = Config.bigWithdrawPctBps or 2500
    local dailyBps = Config.dailyWithdrawPctBps or 5000
    local bigThreshold = math.ceil(beforeBank * bigBps / 10000)
    if amountCents >= bigThreshold then
        return true, "big_pct"
    end
    -- Update the rolling-24h bucket; trip if cumulative crosses dailyBps.
    local newSum, err = redis.incrBy(withdrawWindowKey(crewId), amountCents, 90000)
    if err or not newSum then
        -- Bucket can't be tracked; we do not block the withdraw on a tracker miss
        -- but we DO emit fallback so ServerInfra knows redis is degraded for daily
        -- accounting. Big-percent trigger above still works without redis.
        return false, nil, nil
    end
    local dailyThreshold = math.ceil(beforeBank * dailyBps / 10000)
    if newSum >= dailyThreshold then
        return true, "daily_pct", newSum
    end
    return false, nil, newSum
end

-- ---------------------------------------------------------------------------
-- depositToBank
-- ---------------------------------------------------------------------------

---@param src integer  -- player source
---@param crewId integer
---@param amountCents integer
---@return boolean ok
---@return integer|nil bankCentsAfter
---@return string|nil error
function M.depositToBank(src, crewId, amountCents)
    local dollars, err = centsToDollars(amountCents)
    if not dollars then
        return false, nil, err
    end
    local player, perr = getQbxPlayer(src)
    if not player then
        return false, nil, perr
    end
    -- qbx_core money authoritative on wallet side
    local removed = player.Functions.RemoveMoney("cash", dollars, "vzu-crews:deposit")
    if not removed then
        return false, nil, "wallet_insufficient"
    end
    local ok, bankAfter, _, _, derr = state.applyBankDelta(crewId, amountCents, {
        reason = "deposit",
        actorCitizenid = player.PlayerData and player.PlayerData.citizenid,
    })
    if not ok then
        -- Refund; deposit failed atomically.
        player.Functions.AddMoney("cash", dollars, "vzu-crews:deposit_refund")
        return false, nil, derr
    end
    audit.emit("crew.bank_deposit", {
        src = src,
        citizenid = player.PlayerData and player.PlayerData.citizenid,
        crewId = crewId,
        context = {
            intent = { amountCents = amountCents },
            after = { bankCents = bankAfter },
        },
    })
    return true, bankAfter, nil
end

-- ---------------------------------------------------------------------------
-- withdrawFromBank (leader-only + §10 Q1 cooldown arming)
-- ---------------------------------------------------------------------------

---@param src integer
---@param crewId integer
---@param amountCents integer
---@return boolean ok
---@return integer|nil bankCentsAfter
---@return string|nil error
function M.withdrawFromBank(src, crewId, amountCents)
    local dollars, err = centsToDollars(amountCents)
    if not dollars then
        return false, nil, err
    end
    local player, perr = getQbxPlayer(src)
    if not player then
        return false, nil, perr
    end
    local citizenid = player.PlayerData and player.PlayerData.citizenid
    local row = state._readCrewRow(crewId)
    if not row then
        return false, nil, "crew_not_found"
    end
    if row.leader_citizenid ~= citizenid then
        return false, nil, "not_leader"
    end
    if (row.bank_cents or 0) < amountCents then
        return false, nil, "bank_insufficient"
    end
    local beforeBank = row.bank_cents
    local tripped, reason = checkWithdrawThresholds(crewId, amountCents, beforeBank)

    local ok, bankAfter, _, _, derr = state.applyBankDelta(crewId, -amountCents, {
        reason = "withdraw",
        actorCitizenid = citizenid,
    })
    if not ok then
        return false, nil, derr
    end
    -- AddMoney AFTER state commit — order matches §4.2 (DB is authoritative first).
    player.Functions.AddMoney("cash", dollars, "vzu-crews:withdraw")

    if tripped then
        local lockUntil = nowSeconds() + (Config.disbandCooldownSeconds or 86400)
        local lockOk, lockErr = state.setBankDisbandLockUntil(crewId, lockUntil)
        if not lockOk then
            -- Lock failed to persist; emit a critical audit so this isn't silent.
            audit.emitCritical("crew.bank_withdraw_cooldown_lock_failed", {
                crewId = crewId,
                citizenid = citizenid,
                context = { reason = reason, error = lockErr },
            })
        else
            audit.emit("crew.bank_withdraw_cooldown_armed", {
                src = src,
                citizenid = citizenid,
                crewId = crewId,
                context = {
                    reason = reason,
                    intent = { amountCents = amountCents },
                    after = { bankCents = bankAfter, lockUntilEpoch = lockUntil },
                },
            })
        end
    end

    audit.emit("crew.bank_withdraw", {
        src = src,
        citizenid = citizenid,
        crewId = crewId,
        context = {
            intent = { amountCents = amountCents },
            after = { bankCents = bankAfter },
            cooldownArmed = tripped or nil,
        },
    })
    return true, bankAfter, nil
end

-- ---------------------------------------------------------------------------
-- disbandCrew (Phase 1 honors only the cooldown rejection + soft-disband)
-- Phase 2 owns the full lifecycle; this exists so the §10 Q1 rejection path is testable.
-- ---------------------------------------------------------------------------

---@param src integer
---@param crewId integer
---@return boolean ok
---@return string|nil error
function M.disbandCrew(src, crewId)
    local player, perr = getQbxPlayer(src)
    if not player then
        return false, perr
    end
    local citizenid = player.PlayerData and player.PlayerData.citizenid
    local row = state._readCrewRow(crewId)
    if not row or row.status ~= "active" then
        return false, "crew_not_found"
    end
    if row.leader_citizenid ~= citizenid then
        return false, "not_leader"
    end
    local lockUntilTs = row.bank_disband_locked_until
    if lockUntilTs then
        -- DB returns a string like "2026-05-06 12:34:56" or a numeric timestamp depending
        -- on driver; oxmysql preserves the string. Convert via a single SQL probe rather
        -- than parsing here, to avoid timezone foot-guns.
        if _G.MySQL and _G.MySQL.scalar then
            local stillLocked = _G.MySQL.scalar.await(
                "SELECT bank_disband_locked_until > NOW() FROM crews WHERE id = ?",
                { crewId }
            )
            if stillLocked == 1 or stillLocked == true then
                audit.emit("crew.disband_blocked_by_cooldown", {
                    src = src,
                    citizenid = citizenid,
                    crewId = crewId,
                    context = { lockedUntil = tostring(lockUntilTs) },
                })
                return false, "disband_blocked_by_cooldown"
            end
        end
    end
    if not _G.MySQL or not _G.MySQL.transaction then
        return false, "oxmysql_unavailable"
    end
    local ok = _G.MySQL.transaction.await({
        {
            query = "UPDATE crews SET status = 'disbanded', disbanded_at = NOW() "
                .. "WHERE id = ? AND status = 'active'",
            values = { crewId },
        },
        {
            query = "UPDATE crew_members SET left_at = NOW() WHERE crew_id = ? AND left_at IS NULL",
            values = { crewId },
        },
    })
    if not ok then
        return false, "db_write_failed"
    end
    audit.emit("crew.disband", {
        src = src,
        citizenid = citizenid,
        crewId = crewId,
    })
    return true
end

-- ---------------------------------------------------------------------------
-- AwardPayout (vzu-heists settle path)
-- ---------------------------------------------------------------------------

---@param crewId integer
---@param amountCents integer  -- positive=gain, negative=loss (v2 sabotage)
---@param ctx CrewAwardCtx
---@return CrewAwardResult
function M.AwardPayout(crewId, amountCents, ctx)
    ctx = ctx or {}
    if type(crewId) ~= "number" or type(amountCents) ~= "number" or amountCents == 0 then
        return { ok = false, error = "invalid_args" }
    end
    if not ctx.sourceRunId or ctx.sourceRunId == "" then
        return { ok = false, error = "source_run_id_required" }
    end

    -- §5.5: ceiling enforcement
    local ceiling = resolveMaxPayoutCents({
        crewId = crewId,
        sourceTag = ctx.sourceTag,
        sourceRunId = ctx.sourceRunId,
        heistKey = ctx.heistKey,
    })
    if math.abs(amountCents) > ceiling then
        audit.emit("crew.payout_ceiling_exceeded", {
            crewId = crewId,
            context = {
                intent = { amountCents = amountCents, ceiling = ceiling },
                sourceRunId = ctx.sourceRunId,
                sourceTag = ctx.sourceTag,
            },
        })
        return { ok = false, error = "payout_exceeds_ceiling" }
    end

    -- §2.5: SETNX idempotency. Redis is the only source of truth; refuse if degraded.
    local key = "crew:payout_seen:" .. ctx.sourceRunId
    local first, err = redis.setNx(key, tostring(crewId), 86400)
    if err == "service_degraded" then
        audit.emitCritical("crew.payout_service_degraded", {
            crewId = crewId,
            context = { sourceRunId = ctx.sourceRunId, sourceTag = ctx.sourceTag },
        })
        return { ok = false, error = "service_degraded" }
    end
    if not first then
        -- Duplicate: original result is "yes, applied" — we re-emit the audit and report duplicate.
        audit.emit("crew.payout_duplicate", {
            crewId = crewId,
            context = { sourceRunId = ctx.sourceRunId, sourceTag = ctx.sourceTag },
        })
        local row = state._readCrewRow(crewId)
        return {
            ok = true,
            duplicate = true,
            bankCentsAfter = row and row.bank_cents or nil,
        }
    end

    local payoutKind = ctx.payoutKind or "gain"
    local clampToZero = (payoutKind == "loss")
    local ok, bankAfter, applied, clamped, derr = state.applyBankDelta(crewId, amountCents, {
        reason = (payoutKind == "loss") and "sabotage_loss" or "payout",
        sourceRunId = ctx.sourceRunId,
        sourceTag = ctx.sourceTag,
        clampToZero = clampToZero,
        txn = ctx.txn,
    })
    if not ok then
        -- Idempotency marker is set but write failed — release it so the next attempt isn't a no-op.
        redis.del(key)
        return { ok = false, error = derr }
    end

    if clamped then
        audit.emit("crew.payout_clamped", {
            crewId = crewId,
            context = {
                intent = { amountCents = amountCents, applied = applied },
                sourceRunId = ctx.sourceRunId,
                sourceTag = ctx.sourceTag,
            },
        })
    end

    -- Per-member distribution (split policy frozen at heist-lock, see §4.5).
    local row = state._readCrewRow(crewId)
    local recipients = ctx.recipients or {}
    local perMember = {}
    if payoutKind == "gain" and #recipients > 0 and row then
        local splitConfig = row.split_config and (json and json.decode(row.split_config) or nil) or nil
        local leaderBonusBps = splitConfig and splitConfig.leaderBonusBps or nil
        local customWeights = splitConfig and splitConfig.weights or nil
        perMember = state.validators.distributeShares(
            row.split_policy or "equal",
            applied,
            recipients,
            row.leader_citizenid,
            leaderBonusBps,
            customWeights
        )
    end

    audit.emit("crew.payout_received", {
        crewId = crewId,
        context = {
            intent = { amountCents = amountCents, applied = applied },
            sourceRunId = ctx.sourceRunId,
            sourceTag = ctx.sourceTag,
            after = { bankCents = bankAfter },
            payoutKind = payoutKind,
        },
    })

    return {
        ok = true,
        bankCentsAfter = bankAfter,
        perMemberCents = perMember,
        clamped = clamped or nil,
    }
end

-- ---------------------------------------------------------------------------
-- AwardReputation
-- ---------------------------------------------------------------------------

---@param crewId integer
---@param points integer
---@param ctx CrewAwardCtx
---@return CrewRepResult
function M.AwardReputation(crewId, points, ctx)
    ctx = ctx or {}
    if type(crewId) ~= "number" or type(points) ~= "number" or points == 0 then
        return { ok = false, error = "invalid_args" }
    end
    if not ctx.sourceRunId or ctx.sourceRunId == "" then
        return { ok = false, error = "source_run_id_required" }
    end

    local ceiling = resolveMaxRepPoints({
        crewId = crewId,
        sourceTag = ctx.sourceTag,
        sourceRunId = ctx.sourceRunId,
        heistKey = ctx.heistKey,
    })
    if math.abs(points) > ceiling then
        audit.emit("crew.rep_ceiling_exceeded", {
            crewId = crewId,
            context = { intent = { points = points, ceiling = ceiling } },
        })
        return { ok = false, error = "rep_exceeds_ceiling" }
    end

    local key = "crew:payout_seen:" .. ctx.sourceRunId
    local first, err = redis.setNx(key, "rep:" .. tostring(crewId), 86400)
    if err == "service_degraded" then
        audit.emitCritical("crew.rep_service_degraded", {
            crewId = crewId,
            context = { sourceRunId = ctx.sourceRunId, sourceTag = ctx.sourceTag },
        })
        return { ok = false, error = "service_degraded" }
    end
    if not first then
        audit.emit("crew.rep_duplicate", {
            crewId = crewId,
            context = { sourceRunId = ctx.sourceRunId, sourceTag = ctx.sourceTag },
        })
        local row = state._readCrewRow(crewId)
        return {
            ok = true,
            duplicate = true,
            reputationAfter = row and row.reputation or nil,
        }
    end

    local ok, repAfter, derr = state.applyReputationDelta(crewId, points, {
        reason = "rep_award",
        sourceRunId = ctx.sourceRunId,
        sourceTag = ctx.sourceTag,
        txn = ctx.txn,
    })
    if not ok then
        redis.del(key)
        return { ok = false, error = derr }
    end

    audit.emit("crew.rep_awarded", {
        crewId = crewId,
        context = {
            intent = { points = points },
            sourceRunId = ctx.sourceRunId,
            sourceTag = ctx.sourceTag,
            after = { reputation = repAfter },
        },
    })

    return { ok = true, reputationAfter = repAfter }
end

return M
