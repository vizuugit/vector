-- luacheck config for FiveM (CitizenFX) Lua resources.
-- Tightened in the CI lint issue; this is the day-zero baseline.

std = "lua54"
max_line_length = 120
codes = true

-- FiveM/CitizenFX runtime globals. Add as needed when new resources land.
globals = {
    -- Core CitizenFX
    "Citizen",
    "CreateThread",
    "Wait",
    "AddEventHandler",
    "RegisterNetEvent",
    "TriggerEvent",
    "TriggerServerEvent",
    "TriggerClientEvent",
    "RegisterCommand",
    "GetCurrentResourceName",
    "GetResourcePath",
    "GetResourceState",
    "GetInvokingResource",
    "GetGameTimer",
    "LoadResourceFile",
    "SaveResourceFile",
    "exports",
    "source",
    "PerformHttpRequest",
    "json",
    "msgpack",
    "promise",

    -- oxmysql (server-side; required by any resource with a DB schema)
    "MySQL",

    -- qbox / framework conveniences (extend per-resource overrides if needed)
    "QBX",
    "lib",
    "cache",

    -- fxmanifest.lua DSL keywords
    "fx_version", "game", "lua54",
    "name", "author", "description", "version", "repository",
    "shared_script", "shared_scripts",
    "server_script", "server_scripts",
    "client_script", "client_scripts",
    "files", "dependencies",
}

-- Per-resource overrides go in resources/<name>/.luacheckrc and inherit from
-- this file via `std = "+lua54"` plus extra globals.

ignore = {
    "212", -- Unused argument (common in event handlers).
    "213", -- Unused loop variable.
    "631", -- Line is too long (gov by stylua).
}

exclude_files = {
    "resources/**/vendor/**",
    "resources/**/lib/**/*.min.lua",
}
