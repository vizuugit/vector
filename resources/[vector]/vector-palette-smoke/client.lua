-- Smoke test for vector-palette.
-- Boot logs every entry so a stock qbox/FiveM dev server proves the module loads.
-- /vec_palette_card opens the in-engine NUI test card with all 12 swatches.

local function summarize(group, body)
    for token, entry in pairs(body) do
        print(("[vector-palette-smoke] %s.%s -> rgba(%d,%d,%d,%.2f) %s"):format(
            group,
            token,
            entry.r,
            entry.g,
            entry.b,
            entry.a,
            entry.hex
        ))
    end
end

CreateThread(function()
    Wait(0)
    if type(palette) ~= "table" then
        print("[vector-palette-smoke] FAILED: palette table not loaded from vector-palette/palette.lua")
        return
    end
    summarize("world", palette.world)
    summarize("hud", palette.hud)
    summarize("scene", palette.scene)
    print("[vector-palette-smoke] withAlpha(hud.plate, 0.1) ->",
        palette.withAlpha(palette.hud.plate, 0.1).a)
end)

local function flatten()
    local out = {}
    for groupName, body in pairs({ world = palette.world, hud = palette.hud, scene = palette.scene }) do
        for tokenName, entry in pairs(body) do
            out[#out + 1] = {
                group = groupName,
                token = tokenName,
                hex = entry.hex,
                r = entry.r,
                g = entry.g,
                b = entry.b,
                a = entry.a,
                name = entry.name,
            }
        end
    end
    return out
end

local visible = false
local function setVisible(v)
    visible = v
    SetNuiFocus(v, v)
    SendNuiMessage(json.encode({ type = "vector-palette/show", visible = v, swatches = flatten() }))
end

RegisterCommand("vec_palette_card", function()
    setVisible(not visible)
end, false)

RegisterNUICallback("close", function(_, cb)
    setVisible(false)
    cb({ ok = true })
end)
