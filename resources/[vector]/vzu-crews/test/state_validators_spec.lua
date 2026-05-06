-- vzu-crews/test/state_validators_spec.lua
-- Pure-validator tests. No FiveM runtime, no DB, no Redis.
-- Run from repo root with: busted resources/[vector]/vzu-crews/test/
-- Spec: VEC-22 §2.7, §5.4, §10 Q3.

local function loadValidators()
    -- Load state.lua's globals without resolving FiveM paths.
    local here = debug.getinfo(1, "S").source:sub(2)
    local dir = here:match("(.-)/[^/]+$") or "."
    dofile(dir .. "/../server/state.lua")
    return _G.VzuCrewsState.validators
end

describe("vzu-crews validators", function()
    local V

    setup(function()
        V = loadValidators()
    end)

    describe("isValidName", function()
        it("rejects nil and non-strings", function()
            assert.is_false((V.isValidName(nil, {})))
            assert.is_false((V.isValidName(42, {})))
        end)

        it("rejects too-short and too-long names", function()
            assert.is_false((V.isValidName("ab", {})))
            assert.is_false((V.isValidName(string.rep("a", 41), {})))
        end)

        it("accepts a 3-char and 40-char name", function()
            assert.is_true((V.isValidName("abc", {})))
            assert.is_true((V.isValidName(string.rep("a", 40), {})))
        end)

        it("rejects illegal characters", function()
            assert.is_false((V.isValidName("hello!", {})))
            assert.is_false((V.isValidName("a/b", {})))
            assert.is_false((V.isValidName("emoji😀", {})))
        end)

        it("accepts allowed punctuation: space, underscore, hyphen, apostrophe", function()
            assert.is_true((V.isValidName("Tom O'Reilly", {})))
            assert.is_true((V.isValidName("alpha-team_one", {})))
        end)

        it("denies names containing denylist substrings (case-insensitive)", function()
            local denylist = { "vector", "staff", "ballas" }
            assert.is_false((V.isValidName("Vector Heist", denylist)))
            assert.is_false((V.isValidName("ServerStaff", denylist)))
            assert.is_false((V.isValidName("BALLAS Crew", denylist)))
            assert.is_true((V.isValidName("RedlineCrew", denylist)))
        end)
    end)

    describe("isValidSplitConfig", function()
        it("accepts equal with no extra args", function()
            assert.is_true((V.isValidSplitConfig("equal")))
        end)

        it("requires a leader bonus for leader_weighted and bounds it 0..5000", function()
            assert.is_false((V.isValidSplitConfig("leader_weighted")))
            assert.is_true((V.isValidSplitConfig("leader_weighted", nil, 0)))
            assert.is_true((V.isValidSplitConfig("leader_weighted", nil, 5000)))
            assert.is_false((V.isValidSplitConfig("leader_weighted", nil, 5001)))
            assert.is_false((V.isValidSplitConfig("leader_weighted", nil, -1)))
        end)

        it("requires non-empty positive-sum weights for custom", function()
            assert.is_false((V.isValidSplitConfig("custom")))
            assert.is_false((V.isValidSplitConfig("custom", {})))
            assert.is_false((V.isValidSplitConfig("custom", { ABC = 0, DEF = 0 })))
            assert.is_true((V.isValidSplitConfig("custom", { ABC = 100, DEF = 200 })))
        end)

        it("rejects per-member weights outside 0..1000", function()
            assert.is_false((V.isValidSplitConfig("custom", { ABC = 1001 })))
            assert.is_false((V.isValidSplitConfig("custom", { ABC = -1 })))
        end)

        it("rejects unknown policies", function()
            assert.is_false((V.isValidSplitConfig("anarchy")))
        end)
    end)

    describe("computeBankDelta", function()
        it("adds positive deltas", function()
            local newBank, applied, clamped = V.computeBankDelta(1000, 500)
            assert.are.equal(1500, newBank)
            assert.are.equal(500, applied)
            assert.is_false(clamped)
        end)

        it("subtracts deltas that fit", function()
            local newBank, applied, clamped = V.computeBankDelta(1000, -400)
            assert.are.equal(600, newBank)
            assert.are.equal(-400, applied)
            assert.is_false(clamped)
        end)

        it("clamps a loss to zero when clampToZero is set", function()
            local newBank, applied, clamped = V.computeBankDelta(300, -1000, true)
            assert.are.equal(0, newBank)
            assert.are.equal(-300, applied)
            assert.is_true(clamped)
        end)

        it("returns the negative target unmodified when clampToZero is not set", function()
            local newBank, applied, clamped = V.computeBankDelta(300, -1000, false)
            assert.are.equal(-700, newBank)
            assert.are.equal(-1000, applied)
            assert.is_false(clamped)
        end)
    end)

    describe("computeReputationDelta", function()
        it("never goes below zero", function()
            local newRep, applied = V.computeReputationDelta(50, -200)
            assert.are.equal(0, newRep)
            assert.are.equal(-50, applied)
        end)

        it("adds positive deltas", function()
            local newRep, applied = V.computeReputationDelta(10, 5)
            assert.are.equal(15, newRep)
            assert.are.equal(5, applied)
        end)
    end)

    describe("distributeShares", function()
        it("equal split divides cents and assigns remainder to first recipients", function()
            local out = V.distributeShares("equal", 1003, { "A", "B", "C" }, "A")
            assert.are.equal(335, out.A)
            assert.are.equal(334, out.B)
            assert.are.equal(334, out.C)
            assert.are.equal(1003, out.A + out.B + out.C)
        end)

        it("leader_weighted gives the leader a bonus share that sums to amount", function()
            local out = V.distributeShares("leader_weighted", 2000, { "L", "M", "N" }, "L", 5000) -- +50% bonus
            -- leader has 1.5 shares vs 1.0 for each member -> 1.5/(1.5+1+1) = 1.5/3.5
            local total = (out.L or 0) + (out.M or 0) + (out.N or 0)
            assert.are.equal(2000, total)
            assert.is_true(out.L > out.M)
            assert.are.equal(out.M, out.N)
        end)

        it("custom split honors weights and falls back to equal when total weight is zero", function()
            local out = V.distributeShares("custom", 1000, { "A", "B" }, "A", nil, { A = 700, B = 300 })
            assert.are.equal(1000, out.A + out.B)
            assert.is_true(out.A > out.B)

            local fallback = V.distributeShares("custom", 1000, { "A", "B" }, "A", nil, {})
            assert.are.equal(500, fallback.A)
            assert.are.equal(500, fallback.B)
        end)

        it("returns empty table for empty recipients or zero amount", function()
            local empty = V.distributeShares("equal", 1000, {}, "A")
            assert.are.equal(0, (next(empty) and 1) or 0)

            local zero = V.distributeShares("equal", 0, { "A", "B" }, "A")
            assert.are.equal(0, (next(zero) and 1) or 0)
        end)
    end)
end)
