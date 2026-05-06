-- vector-crews/server/redis.lua
-- Thin adapter exposing the subset of Redis commands vector-crews needs:
--   SETNX key value EX ttl  → for crew:payout_seen idempotency markers
--   INCRBY key n + EXPIRE   → for crew:withdraw_window:{crewId}:{utcDate} bucket
--   GET                     → for read-back paths
--
-- Backends
-- --------
--   'redis-fivem' — call exports['redis-fivem']:command. Real prod path; ServerInfra wires it.
--   'inmem'       — single-process map for dev/local-stack happy-path testing.
--                   NOT for prod: a multi-fxserver deployment will desync.
--   'null'        — always reports unavailable. Default so missing wiring fails closed.
--
-- The backend is selected by convar `vector-crews:redisBackend` (default 'null').
-- Spec §4.3 mandates that idempotency-required callers reject with `service_degraded`
-- when this adapter reports unavailable.

local M = _G.VectorCrewsRedis or {}
_G.VectorCrewsRedis = M

local backend = "null"
local store = {}      -- inmem: { [key] = { v=, expireAt= } }
local upstream = nil  -- redis-fivem exports handle when available

local function nowSeconds()
    return os.time()
end

local function ttlExpiry(ttlSeconds)
    if not ttlSeconds or ttlSeconds <= 0 then
        return nil
    end
    return nowSeconds() + ttlSeconds
end

-- ---------------------------------------------------------------------------
-- inmem backend
-- ---------------------------------------------------------------------------

local function inmemPurgeIfExpired(key)
    local entry = store[key]
    if not entry then
        return nil
    end
    if entry.expireAt and entry.expireAt <= nowSeconds() then
        store[key] = nil
        return nil
    end
    return entry
end

local function inmemSetNx(key, value, ttlSeconds)
    if inmemPurgeIfExpired(key) then
        return false
    end
    store[key] = { v = value, expireAt = ttlExpiry(ttlSeconds) }
    return true
end

local function inmemGet(key)
    local entry = inmemPurgeIfExpired(key)
    return entry and entry.v or nil
end

local function inmemIncrBy(key, n, ttlSeconds)
    local entry = inmemPurgeIfExpired(key)
    local v = (entry and tonumber(entry.v) or 0) + (tonumber(n) or 0)
    store[key] = {
        v = tostring(v),
        expireAt = (entry and entry.expireAt) or ttlExpiry(ttlSeconds),
    }
    return v
end

local function inmemDel(key)
    store[key] = nil
    return true
end

local function inmemReset()
    store = {}
end
M._inmemReset = inmemReset

-- ---------------------------------------------------------------------------
-- redis-fivem backend
-- ---------------------------------------------------------------------------

local function ensureUpstream()
    if upstream then
        return upstream
    end
    if not _G.exports then
        return nil
    end
    -- Several FiveM redis resources expose a `:command(...)` style export.
    -- We probe a few well-known names so ServerInfra's choice doesn't bind us here.
    local candidates = { "redis-fivem", "redis", "rcon-redis" }
    for _, name in ipairs(candidates) do
        local ok, exp = pcall(function()
            return _G.exports[name]
        end)
        if ok and exp then
            upstream = exp
            return upstream
        end
    end
    return nil
end

local function redisCommand(...)
    local exp = ensureUpstream()
    if not exp then
        return nil, "redis_resource_missing"
    end
    local ok, res = pcall(function(...)
        return exp:command(...)
    end, ...)
    if not ok then
        return nil, "redis_command_error"
    end
    return res
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---@param mode '"null"'|'"inmem"'|'"redis-fivem"'
function M.configure(mode)
    if mode == "inmem" or mode == "redis-fivem" or mode == "null" then
        backend = mode
        if mode == "inmem" then
            store = {}
        end
    end
end

function M.available()
    if backend == "null" then
        return false
    end
    if backend == "inmem" then
        return true
    end
    if backend == "redis-fivem" then
        return ensureUpstream() ~= nil
    end
    return false
end

function M.backend()
    return backend
end

---@param key string
---@param value string
---@param ttlSeconds integer|nil
---@return boolean ok      true if the key was set (i.e. no prior key), false if it already existed
---@return string|nil error  'service_degraded' when backend unavailable
function M.setNx(key, value, ttlSeconds)
    if not M.available() then
        return false, "service_degraded"
    end
    if backend == "inmem" then
        return inmemSetNx(key, value, ttlSeconds), nil
    end
    -- redis-fivem path
    local res, err = redisCommand("SET", key, value, "NX", "EX", ttlSeconds or 0)
    if err then
        return false, "service_degraded"
    end
    -- Redis returns "OK" on set, nil if key existed.
    return res == "OK" or res == true, nil
end

---@param key string
---@return string|nil value
---@return string|nil error
function M.get(key)
    if not M.available() then
        return nil, "service_degraded"
    end
    if backend == "inmem" then
        return inmemGet(key), nil
    end
    local res, err = redisCommand("GET", key)
    if err then
        return nil, "service_degraded"
    end
    return res, nil
end

---@param key string
---@param n integer
---@param ttlSeconds integer|nil  -- only set on first INCR (when key didn't exist)
---@return integer|nil newValue
---@return string|nil error
function M.incrBy(key, n, ttlSeconds)
    if not M.available() then
        return nil, "service_degraded"
    end
    if backend == "inmem" then
        return inmemIncrBy(key, n, ttlSeconds), nil
    end
    local res, err = redisCommand("INCRBY", key, n)
    if err then
        return nil, "service_degraded"
    end
    if ttlSeconds and ttlSeconds > 0 then
        -- Best-effort EXPIRE; if it fails we surface degraded so caller can decide.
        local _, expireErr = redisCommand("EXPIRE", key, ttlSeconds, "NX")
        if expireErr then
            return tonumber(res), "service_degraded"
        end
    end
    return tonumber(res), nil
end

---@param key string
---@return boolean ok
---@return string|nil error
function M.del(key)
    if not M.available() then
        return false, "service_degraded"
    end
    if backend == "inmem" then
        return inmemDel(key), nil
    end
    local _, err = redisCommand("DEL", key)
    if err then
        return false, "service_degraded"
    end
    return true, nil
end

return M
