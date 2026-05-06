fx_version("cerulean")
game("gta5")
lua54("yes")

name("vzu-heists")
author("Vector")
description("Heist state machine, mission templates, bucket allocator, and heist_runs storage. See VEC-23.")
version("0.1.0")
repository("https://github.com/vizuugit/vector")

shared_scripts({
    "shared/types.lua",
})

server_scripts({
    "@oxmysql/lib/MySQL.lua",
    "server/state_machine.lua",
    "server/main.lua",
})

client_scripts({
    "client/main.lua",
})

files({
    "db/0001_create_heist_runs.sql",
})

dependencies({
    "oxmysql",
})
