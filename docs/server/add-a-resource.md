# Adding a resource

How an engineer drops a FiveM resource into the dev server, gets it loaded, and
verifies it works. Operating context (start/stop, logs, ports) lives in the
[local-dev-server runbook](../runbooks/local-dev-server.md). Resource provenance
and keep/fork/scrub calls live in the
[circuit-hack-inventory](../runbooks/circuit-hack-inventory.md).

## TL;DR

```bash
# from anywhere
cd ~/dev/vzu/server-local

# 1. Drop the resource into the right category folder
cp -r path/to/my_resource txData/Qbox_F913B4.base/resources/[vzu]/my_resource

# 2. (only if it's not under [vzu]/[ox]/[qbx]/[standalone]/[voice]/[assets])
#    add an explicit ensure line to txData/Qbox_F913B4.base/server.cfg

# 3. Reload via txAdmin live console (http://localhost:40120)
refresh
ensure my_resource

# 4. Tail the log to confirm
docker compose logs -f fivem | grep -E "Started resource my_resource|error"
```

If it `Started resource my_resource` and there are no `script:my_resource`
errors, you're done.

## Where resources live

### Today (inherited dev box)

```
~/dev/vzu/server-local/txData/Qbox_F913B4.base/resources/
├── [cfx-default]/   # FXServer-bundled, do not modify
├── [ox]/            # ox_lib, ox_inventory, oxmysql, ox_target, ox_doorlock, ox_fuel
├── [qbx]/           # qbox base — 48 stock resources
├── [standalone]/    # community resources (Renewed-Banking, illenium-appearance, …)
├── [voice]/         # pma-voice, mm_radio
├── [assets]/        # MLOs / IPLs (e.g. pillbox)
├── [npwd]/          # phone framework (npwd, qbx_npwd)
├── [npwd-apps]/     # phone apps (garages, mail)
└── [vzu]/           # OUR resources — vzu_circuit_hack lives here
```

The `[category]` folders are convention-only — FXServer doesn't care about
their names. `server.cfg` exploits this with bulk-load lines like
`ensure [ox]` that load every resource in that folder.

### After monorepo cutover

Per [VEC-2 plan](/VEC/issues/VEC-2#document-plan) §3:

```
<monorepo>/resources/
├── [vector]/        # OUR resources, source-of-truth
├── [vendor]/        # vendored 3rd-party (each with VENDORED.md, upstream commit pin)
└── …
```

The `txData/Qbox_F913B4.base/resources/` tree becomes a *deploy artifact*
synced from the monorepo. Until that lands, the inherited tree is canonical
for everything that isn't in the monorepo yet.

## Adding a NEW resource (ours)

Use this when you're authoring a new VZU resource from scratch.

1. Pick a name. Convention: `vzu_<short-name>` (e.g. `vzu_circuit_hack`,
   `vzu_anticheat`). Lowercase, snake_case, no dots.

2. Create the folder under `[vzu]/`:

   ```bash
   cd ~/dev/vzu/server-local/txData/Qbox_F913B4.base/resources/[vzu]
   mkdir vzu_my_resource
   cd vzu_my_resource
   ```

3. Add a minimum `fxmanifest.lua`:

   ```lua
   fx_version 'cerulean'
   game 'gta5'

   author 'VZU Studio'
   description 'One-liner describing what this resource does'
   version '0.1.0'

   shared_scripts {
     '@ox_lib/init.lua',  -- if you need ox_lib helpers
   }

   server_scripts {
     'server/main.lua',
   }

   client_scripts {
     'client/main.lua',
   }

   dependencies {
     'ox_lib',
     -- 'oxmysql', -- only if you persist
   }
   ```

4. Sketch the server/client files. Server-authoritative — never trust the
   client for state that affects other players, money, inventory, or
   persistence. The [VEC-2 plan §7](/VEC/issues/VEC-2#document-plan) covers
   the anti-cheat posture.

5. Load it (no `server.cfg` change needed — `ensure [vzu]` already loads
   everything in this folder):

   ```
   refresh
   ensure vzu_my_resource
   ```

   Run those in the **txAdmin live console** at `http://localhost:40120` →
   "Live Console". You can also restart the whole server, but `refresh +
   ensure` is faster.

6. Watch the log:

   ```bash
   docker compose logs -f fivem
   ```

   Look for `Started resource vzu_my_resource`. Errors prefixed with
   `script:vzu_my_resource:` come from your code; errors from
   `citizen-server-impl` are loader-level (manifest syntax, missing
   dependency, etc.).

## Adding a VENDORED resource (3rd-party)

Use this when you want to drop in a community resource (e.g. a job, a UI, a
helper).

1. **Decide the category folder.** Use the existing convention:

   - `[ox]/` — anything from the overextended/ox-org ecosystem
   - `[standalone]/` — generic 3rd-party (jobs, helpers, UIs)
   - `[voice]/` — voice/audio
   - `[assets]/` — MLOs, IPLs, models

2. **Drop the resource in.** Either `git clone <upstream> <category>/<name>`
   or download a release zip and extract.

3. **Pin the upstream version.** This is for the monorepo cutover later, but
   capture it now so we don't lose it. Inside the resource folder:

   ```
   <category>/<name>/VENDORED.md
   ```

   ```md
   # <name>

   - Upstream: https://github.com/owner/repo
   - Pinned commit: abcdef1234
   - License: MIT (or whatever)
   - Local edits: none / list them
   - Dependencies: ox_lib, oxmysql, …
   ```

   If you make local changes, list them. The cutover into the monorepo
   ([VEC-2 plan](/VEC/issues/VEC-2#document-plan) §3) requires every vendored
   resource to ship with this file.

4. **Check dependencies.** Read the resource's `fxmanifest.lua`. Anything in
   `dependencies { … }` must already be loaded earlier in `server.cfg` than
   the new resource. Most things we depend on (`ox_lib`, `oxmysql`,
   `qbx_core`) load before the bulk `[standalone]` group, so it usually
   works without thought — but if you add to `[ox]` or `[qbx]`, mind the
   ordering inside those folders (FXServer loads alphabetically within a
   bulk-ensure).

5. **Database migrations.** If the resource ships an SQL file (look for
   `*.sql` or a `sql/` folder in its repo), do **not** apply it by hand. See
   [migrations.md](migrations.md) for the workflow.

6. Reload: `refresh && ensure <name>` from the txAdmin live console.

## Forcing reload after edits

Once a resource is loaded, edits to its files require a reload:

```
restart vzu_my_resource
```

…from the txAdmin live console. Most editors can hot-reload by saving while
the server is running, but the resource itself doesn't see the change until
`restart`. Lua errors after `restart` come up in the live console
immediately; client-side errors show up in `F8` on the FiveM client.

## Removing a resource

```
stop vzu_my_resource
```

…then delete the folder if you're sure. If the resource has a database
schema, the rows stay until you drop the tables manually — see
[migrations.md](migrations.md).

For shared resources (e.g. removing one from `[standalone]`), check whether
anything else depends on it first:

```bash
grep -rE "dependency.*<name>|@<name>/" \
  ~/dev/vzu/server-local/txData/Qbox_F913B4.base/resources/
```

## Common pitfalls

- **Resource not loading silently.** Check the folder name matches what
  you're `ensure`ing. FXServer logs `Couldn't find resource X` if not.
- **`@ox_lib/init.lua` not found.** `ox_lib` must be loaded *before* the
  resource that depends on it. `[ox]` is bulk-loaded before `[standalone]` and
  `[vzu]` in our `server.cfg`, so this only bites when adding things to `[ox]`
  itself out of alphabetical order.
- **Crashes on join, not on start.** Means the resource starts cleanly but a
  client-side script breaks during player session start. Check `F8` in the
  client.
- **`oxmysql:execute` returns nil.** MariaDB is unhealthy or
  `mysql_connection_string` is wrong. See the runbook's
  [Known issues](../runbooks/local-dev-server.md#known-issues) section.
- **`refresh` doesn't pick up a new resource.** It does — but only if
  FXServer can read the folder. Permissions issue: `chmod -R u+rwX,g+rwX
  <category>/<name>` and try again.

## Acceptance bar before pushing

A resource is "ready" for review when:

- it loads cleanly (no `script:` errors on start)
- a single test client can use the feature end-to-end
- any persistence path round-trips (set value → restart → value still there)
- it doesn't trust client-supplied state for anything that matters
- it has a `VENDORED.md` if it's vendored, or follows our resource skeleton
  (fxmanifest, server/, client/, optional `db/migrations/`) if it's ours
- it's not the only thing keeping `vzu_circuit_hack_test_zone` alive — the
  test zone is dev-only and gets scrubbed before alpha (see
  [inventory](../runbooks/circuit-hack-inventory.md#vzu_circuit_hack_test_zone))
