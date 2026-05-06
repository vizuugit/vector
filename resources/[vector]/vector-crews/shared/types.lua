-- vector-crews/shared/types.lua
-- Doc-comment type annotations only. No runtime side-effects.
-- Spec: VEC-22 resource-spec §2.7.

---@alias CrewSplitPolicy "equal" | "leader_weighted" | "custom"
---@alias CrewStatus "active" | "disbanded"
---@alias CrewMemberRole "leader" | "member"
---@alias CrewPayoutKind "gain" | "loss"

---@class Crew
---@field id integer
---@field name string
---@field leaderCitizenid string
---@field bankCents integer            -- only included server-side and on bankUpdated push
---@field reputation integer
---@field splitPolicy CrewSplitPolicy
---@field radioChannel integer|nil
---@field status CrewStatus
---@field createdAt string
---@field bankDisbandLockedUntil string|nil

---@class CrewMember
---@field crewId integer
---@field citizenid string
---@field role CrewMemberRole
---@field splitWeight integer          -- 0..1000
---@field joinedAt string
---@field leftAt string|nil

---@class CrewSplitConfig
---@field policy CrewSplitPolicy
---@field weights table<string, integer>  -- citizenid → weight, used when policy='custom'
---@field leaderBonusBps integer|nil      -- 0..5000, used when policy='leader_weighted'

---@class CrewAwardCtx
---@field sourceTag string                -- e.g. 'heist'
---@field sourceRunId string              -- uuid; idempotency key
---@field payoutKind CrewPayoutKind|nil   -- defaults to 'gain'
---@field recipients string[]|nil         -- citizenids alive-at-settle (for split)
---@field txn any|nil                     -- oxmysql txn handle; when set, mutator joins caller's txn

---@class CrewAwardResult
---@field ok boolean
---@field bankCentsAfter integer|nil
---@field perMemberCents table<string, integer>|nil
---@field duplicate boolean|nil
---@field clamped boolean|nil
---@field error string|nil

---@class CrewRepResult
---@field ok boolean
---@field reputationAfter integer|nil
---@field duplicate boolean|nil
---@field error string|nil

---@class CrewBankDeltaCtx
---@field reason string                   -- 'deposit' | 'withdraw' | 'payout' | 'sabotage_loss'
---@field actorCitizenid string|nil       -- player who initiated, nil for resource-driven
---@field sourceTag string|nil
---@field sourceRunId string|nil
---@field clampToZero boolean|nil         -- payout loss path opts in
---@field txn any|nil

return {}
