# vector-palette-smoke

Tiny stub resource that proves [`vector-palette`](../vector-palette) loads cleanly into a stock qbox/FiveM dev server and that both its Lua and JS/CSS exports work end-to-end.

## What it does

- Boot: prints every palette entry to the server console (`[vector-palette-smoke] world.softBlack -> rgba(11,12,14,1.00) #0B0C0E`) so a startup error in `vector-palette` is visible without joining the server.
- Runtime: `/vec_palette_card` toggles a NUI overlay that renders all 12 swatches with name, hex, and alpha. The overlay HTML imports `palette.css` from the sibling resource — confirming the CSS export is consumable from a real NUI bundle.
- The palette table is shared via `shared_script("@vector-palette/palette.lua")` so this resource never duplicates a hex literal.

## How to run (local dev server)

1. Make sure `vector-palette` and `vector-palette-smoke` are present in the txAdmin recipe's resources directory (symlink or copy from this repo into `~/dev/vzu/server-local/txData/Qbox_F913B4.base/resources/`).
2. In `server.cfg` (or via txAdmin), add:

   ```
   ensure vector-palette
   ensure vector-palette-smoke
   ```

3. Boot the stack per [docs/runbooks/local-dev-server.md](../../../docs/runbooks/local-dev-server.md).
4. Join with the FiveM client. Confirm the boot log shows 12 entries.
5. Run `/vec_palette_card` in the chat. The test card overlays the screen.
6. Take an in-engine screenshot at midnight (around 00:00 game time, using `/time 0` or similar) per the AGENTS.md visual-truth gate, and attach it to [VEC-28](/VEC/issues/VEC-28).

## What it intentionally does not do

- No HUD layout. That's `vector-hud`, deferred per [VEC-21 §10](/VEC/issues/VEC-21#document-art-direction).
- No persistence, no events fired off-resource. Pure presentation.

## License

MIT.
