fx_version("cerulean")
game("gta5")
lua54("yes")

name("vector-palette-smoke")
author("Vector")
description("Renders a 12-swatch test card to prove vector-palette loads cleanly (Lua + NUI).")
version("0.1.0")

dependency("vector-palette")

shared_script("@vector-palette/palette.lua")

client_scripts({
    "client.lua",
})

ui_page("ui/index.html")

files({
    "ui/index.html",
    "ui/test-card.js",
})
