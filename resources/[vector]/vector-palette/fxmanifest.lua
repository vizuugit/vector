fx_version("cerulean")
game("gta5")
lua54("yes")

name("vector-palette")
author("Vector")
description("Single source of truth for the Vector color palette (Lua/JS/CSS).")
version("0.1.0")
repository("https://github.com/vizuugit/vector")

shared_script("palette.lua")

files({
    "palette.js",
    "palette.css",
    "src/tokens.json",
})
