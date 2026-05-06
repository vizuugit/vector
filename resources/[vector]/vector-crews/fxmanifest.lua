fx_version("cerulean")
game("gta5")
lua54("yes")

name("vector-crews")
author("Vector")
description("Server-authoritative crew lifecycle, bank, reputation, payout-from-heists pipeline. See VEC-22.")
version("0.1.0")
repository("https://github.com/vizuugit/vector")

shared_scripts({
    "shared/config.lua",
    "shared/types.lua",
})

server_scripts({
    "@oxmysql/lib/MySQL.lua",
    "server/audit.lua",
    "server/redis.lua",
    "server/state.lua",
    "server/bank.lua",
    "server/main.lua",
})

files({
    "db/0001_create_crews.sql",
    "db/0002_create_crew_members.sql",
    "db/0003_create_crew_cosmetic_unlocks.sql",
})

dependencies({
    "oxmysql",
    "qbx_core",
})

-- Phase 1 ships server-only. Client + NUI land in Phase 2 alongside crew lifecycle UX.
