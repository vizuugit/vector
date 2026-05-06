# Local FiveM dev server — operations runbook

The day-to-day dev environment for D1–D30. Lives outside this repo at
`/home/vizuu3d/dev/vzu/server-local/` on the CTO's WSL2 box. Hetzner provisioning
([VEC-9](/VEC/issues/VEC-9)) is deferred until we need the server reachable from
outside that machine.

> **TL;DR for the board:** `cd ~/dev/vzu/server-local && docker compose up -d` to
> start. `docker compose down` to stop. `http://localhost:40120` is txAdmin (the
> web UI). `http://localhost:8080` is Adminer (the database UI). The FiveM server
> itself listens on port `30120`.

## What is running

Three Docker containers on the bridge network `vzu_net`:

| Container     | Image                       | Purpose                                     | Host port |
| ------------- | --------------------------- | ------------------------------------------- | --------- |
| `vzu_fivem`   | `traskin/fxserver:latest`   | FXServer + bundled txAdmin web panel        | 30120 tcp/udp (game), 40120 tcp (txAdmin) |
| `vzu_mariadb` | `mariadb:11`                | Database for `oxmysql` and qbox resources   | 3306 tcp  |
| `vzu_adminer` | `adminer:latest`            | Web UI for browsing the database            | 8080 tcp  |

`vzu_fivem` has a 6 GB memory cap and timezone `America/Sao_Paulo`. All three
have `restart: unless-stopped`, so they come back up after a host reboot until
you explicitly `docker compose down`.

### Volumes (local bind mounts)

| Path on host                                            | Mounted at      | What's in it                                                          |
| ------------------------------------------------------- | --------------- | --------------------------------------------------------------------- |
| `~/dev/vzu/server-local/txData/`                        | `/txData`       | txAdmin profile + the active recipe `Qbox_F913B4.base/` (server.cfg, resources, cache) |
| `~/dev/vzu/server-local/mariadb-data/`                  | `/var/lib/mysql`| MariaDB on-disk data files                                            |
| `~/dev/vzu/server-local/data/`                          | (unused)        | Reserved, currently empty                                             |

`txData/` and `mariadb-data/` are gitignored locally and **must never be committed** —
they contain credentials, bcrypt hashes, and the live database.

### Network topology

```
host (WSL2)                          docker bridge: vzu_net
┌─────────────────────┐              ┌──────────────────────────────┐
│ Windows host        │              │  vzu_fivem (FXServer/txAdmin)│
│   FiveM client ─────┼─ 30120 ──▶  │   ↳ talks to mariadb:3306    │
│   Browser ──────────┼─ 40120 ──▶  │  vzu_mariadb (MariaDB 11)    │
│   Browser ──────────┼─ 8080 ───▶  │  vzu_adminer                 │
└─────────────────────┘              └──────────────────────────────┘
```

WSL2 forwards localhost ports to the Windows host automatically, so the FiveM
client running on Windows connects to `localhost:30120` and reaches the
container. If a port appears unreachable from Windows, see
[Connecting from the Windows host](#connecting-from-the-windows-host).

## Environment contract (`.env`)

The compose file requires these variables (see `~/dev/vzu/server-local/.env` —
**do not commit, do not paste anywhere**):

| Variable           | Purpose                                                     |
| ------------------ | ----------------------------------------------------------- |
| `LICENSE_KEY`      | Cfx.re server license key (legacy — also baked into `server.cfg`, see [Known issues](#known-issues)) |
| `DB_NAME`          | MariaDB database name                                       |
| `DB_USER`          | MariaDB application user                                    |
| `DB_PASSWORD`      | MariaDB application user password                           |
| `DB_ROOT_PASSWORD` | MariaDB root password                                       |
| `DB_PORT`          | Host port for MariaDB (default `3306`)                      |
| `FXSERVER_PORT`    | Host port for FXServer (default `30120`)                    |
| `TXADMIN_PORT`     | Host port for txAdmin web panel (default `40120`)           |
| `ADMINER_PORT`     | Host port for Adminer (default `8080`)                      |
| `RCON_PASSWORD`    | RCON password for FXServer (set, but RCON is unused locally)|

When migrating to the monorepo (see [Migration path](#migration-path-into-the-monorepo)),
ship a committed `.env.example` with these names and `<redacted>` placeholders, and
keep the real `.env` outside the repo.

## Daily operations

All commands run from `~/dev/vzu/server-local/` unless noted.

### Start everything

```bash
cd ~/dev/vzu/server-local
docker compose up -d
```

`up -d` starts in the background. First start after a reboot takes ~20–40s
before the FXServer reports "Started resource" lines. txAdmin is reachable
faster (it boots before resources load).

### Stop everything

```bash
docker compose down
```

Containers stop, volumes stay. Safe — no data loss.

### Restart a single service

```bash
docker compose restart fivem      # FXServer + txAdmin
docker compose restart mariadb    # database (will re-trigger fivem reconnect)
docker compose restart adminer    # DB browser
```

### Check status

```bash
docker compose ps
```

Healthy looks like:

```
vzu_mariadb   Up 5 minutes (healthy)   0.0.0.0:3306->3306/tcp
vzu_fivem     Up 5 minutes             0.0.0.0:30120->30120/tcp, 0.0.0.0:30120->30120/udp, 0.0.0.0:40120->40120/tcp
vzu_adminer   Up 5 minutes             0.0.0.0:8080->8080/tcp
```

### View logs

```bash
docker compose logs -f fivem      # follow FXServer logs in real time
docker compose logs --tail=100 fivem
docker compose logs mariadb
```

The FXServer log is also written to disk at
`~/dev/vzu/server-local/txData/default/logs/fxserver.log` (rotated daily).

### Inspect MariaDB via Adminer

Open `http://localhost:8080` in a browser.

- **System:** MySQL
- **Server:** `mariadb` (the container name; Adminer is on the same `vzu_net`)
- **Username / Password / Database:** values from `.env` (`DB_USER` / `DB_PASSWORD` / `DB_NAME`, or `root` / `DB_ROOT_PASSWORD`)

### Connect to MariaDB from the host shell

```bash
docker compose exec mariadb mariadb -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME"
```

…where the env vars are loaded from `.env` (the compose CLI does this for you,
but plain `mariadb` does not — `source .env` first if you need them in your
shell).

### txAdmin web panel

Open `http://localhost:40120`. Log in as `Vizuu_3D` (master admin) — credentials
are stored as bcrypt hashes in `txData/admins.json` and the password is set via
the txAdmin web UI, not the file.

From txAdmin you can:
- start, stop, restart the FXServer
- live-tail the server console and run server commands
- toggle resources on the fly
- inspect the player list, kick, ban, message
- run periodic and one-shot scheduled tasks

### Apply database migrations

We do not yet have a migration runner. Today, migrations are applied manually:

1. Open Adminer → connect to the DB.
2. Paste the SQL from the relevant file under `db/` (forward-only, see
   monorepo conventions in [VEC-2 plan](/VEC/issues/VEC-2#document-plan) §3).
3. Verify with a `SELECT` and commit the migration file to the repo.

A scripted runner is tracked separately and will land before public alpha.

### Add or change a resource

Resources live under `~/dev/vzu/server-local/txData/Qbox_F913B4.base/resources/`.
The category folders (`[ox]`, `[qbx]`, `[vzu]`, …) are convention-only — FXServer
loads resources by `ensure` lines in `server.cfg`.

To add or update a resource:

1. Drop the resource into the right `[category]/` folder.
2. Add `ensure resource_name` to `server.cfg` (or rely on `ensure [category]`
   which loads everything in that folder).
3. From txAdmin's live console, run `refresh` then `ensure resource_name`.
4. Watch `docker compose logs -f fivem` for `Started resource …` and any errors.

For resources we own (e.g. `vzu_circuit_hack`), source-of-truth is the monorepo;
the version in `txData/` is a deployed copy. Don't edit the deployed copy
directly — see [Migration path](#migration-path-into-the-monorepo).

## Connecting from the Windows host

WSL2 forwards `localhost` ports to Windows by default, so:

- Open the FiveM client → "Direct connect" → `localhost:30120`.
- Open `http://localhost:40120` in a Windows browser for txAdmin.
- Open `http://localhost:8080` in a Windows browser for Adminer.

If a port is unreachable from Windows but works inside WSL:

```powershell
# from an elevated Windows PowerShell, list portproxy rules
netsh interface portproxy show all
# typically you don't need any — WSL2 mirrored networking handles this on Win11
```

WSL2 networking quirks worth knowing:
- The WSL VM's IP changes every boot. Don't hard-code it — use `localhost`.
- Windows Firewall sometimes blocks new ports the first time. Allow when prompted.
- Docker Desktop and `dockerd` inside WSL are different — confirm with
  `docker context ls` which one is active.

## Backups

Backup story for this dev box is **lazy** — it's a dev environment and we have
the recipe + DB schema in the monorepo. If you want a snapshot before risky
work:

```bash
# Database snapshot
docker compose exec -T mariadb mariadb-dump --all-databases -u root -p"$DB_ROOT_PASSWORD" \
  > ~/backups/vzu-dev-$(date +%Y%m%d-%H%M%S).sql

# txData snapshot (recipe + cache + logs)
tar -C ~/dev/vzu/server-local -czf ~/backups/vzu-txdata-$(date +%Y%m%d-%H%M%S).tar.gz txData/
```

Production backup posture (nightly mysqldump + resource snapshot to
S3-compatible bucket, 30-day retention, tested restore drill) is the Hetzner
phase deliverable, not this dev box. See [VEC-9](/VEC/issues/VEC-9).

## Known issues

### `sv_licenseKey` is hard-coded in `server.cfg`

`txData/Qbox_F913B4.base/server.cfg` has a literal Cfx.re license key on the
`sv_licenseKey` line. The recipe was generated by txAdmin before the company
existed, so the key was inlined.

- **Today:** fine — `txData/` is gitignored locally and never leaves the box.
- **Monorepo migration:** we **must** strip this line, replace with
  `sv_licenseKey "${LICENSE_KEY}"` (already exported via `.env`), and confirm
  via `grep -r 'cfxk_' .` in CI before any commit lands.

### `mysql_connection_string` has the password inline

Same file, same problem:

```
set mysql_connection_string "mysql://vzu:vzu_local_change_me@mariadb/vzu_dev?…"
```

The literal password here is a placeholder (`vzu_local_change_me`), not the
real one — but the pattern is wrong. Migration must rewrite this to use
`${DB_USER}` / `${DB_PASSWORD}` / `${DB_NAME}` from `.env`.

### Recurring "Server list query returned an error" log lines

FXServer periodically logs:

```
[ citizen-server-impl] Server list query returned an error: ...
endpoint https://185.153.176.47:30120/... context deadline exceeded
```

This is FXServer's master-list listing daemon trying to phone home on the
public IP it sees. Port 30120 is **not** open to the internet on this box, so
the probes time out. **Benign for a local dev box.** It will go away in the
Hetzner phase ([VEC-9](/VEC/issues/VEC-9)) when the server is actually
reachable, or sooner by setting `sv_master1 ""` in `server.cfg` to opt out of
the master list.

### Resources from Circuit Hack still load

`server.cfg` lines 93–94 still `ensure vzu_circuit_hack` and
`ensure vzu_circuit_hack_test_zone` (the second has an inline comment "remove
esta linha quando terminar as capturas promo"). They start cleanly today.
Provenance and keep/fork/scrub call live in the companion document
[circuit-hack-inventory.md](circuit-hack-inventory.md).

### Test-zone resource is loaded by default

`server.cfg` includes `ensure vzu_circuit_hack_test_zone` with a comment
"remove esta linha quando terminar as capturas promo". This is a dev-only test
bench that injects characters, money, and vehicles. Acceptable on the local box;
**must be scrubbed** before any public-facing or alpha-ready build.

## Migration path into the monorepo

Per [VEC-2 plan](/VEC/issues/VEC-2#document-plan) §3, this folder maps onto the
monorepo as follows. The cutover happens once [VEC-10](/VEC/issues/VEC-10) lands
the monorepo skeleton (already underway; this repo *is* that skeleton).

| Today (`~/dev/vzu/server-local/`)                       | Monorepo destination                                  | Notes |
| ------------------------------------------------------- | ----------------------------------------------------- | ----- |
| `docker-compose.yml`                                    | `ops/dev-server/docker-compose.yml`                   | Move as-is, update path refs. |
| `.env`                                                  | **stays outside repo**                                | Commit `ops/dev-server/.env.example` instead. |
| `txData/Qbox_F913B4.base/server.cfg`                    | `server/server.cfg` (templated)                       | Strip license key, strip mysql password, switch to `${VAR}` substitution. |
| `txData/Qbox_F913B4.base/{ox,qbx,voice,misc,permissions}.cfg` | `server/`                                       | Move as-is, no secrets in these. |
| `txData/Qbox_F913B4.base/resources/[ox]/*`              | `resources/[ox]/*` (vendored, with `VENDORED.md`)     | Pin upstream commit per resource. |
| `txData/Qbox_F913B4.base/resources/[qbx]/*`             | `resources/[qbx]/*` (vendored, with `VENDORED.md`)    | Pin upstream commit per resource. |
| `txData/Qbox_F913B4.base/resources/[vzu]/vzu_circuit_hack/` | `resources/[vzu]/vzu_circuit_hack/`               | Source-of-truth move, treat the txData copy as a deploy artifact afterwards. |
| `txData/Qbox_F913B4.base/resources/[vzu]/vzu_circuit_hack_test_zone/` | `tools/dev-bench/vzu_circuit_hack_test_zone/` | Dev-only, never `ensure`d in prod. |
| `txData/Qbox_F913B4.base/resources/[vzu]/*.zip`         | (delete)                                              | Old release artifact, GitHub release is canonical. |
| `txData/admins.json`                                    | **stays outside repo**                                | Bcrypt hashes are still secrets. |
| `mariadb-data/`                                         | **stays outside repo**                                | Live DB — `.gitignore` already covers it. |
| `data/`                                                 | (delete)                                              | Empty, unused. |

Once cut over, the daily flow becomes:

```bash
cd <monorepo>
docker compose -f ops/dev-server/docker-compose.yml --env-file ops/dev-server/.env up -d
```

…and the txData volume continues to live outside the repo on the dev box, just
as it does today.

A pre-commit hook (or CI grep) for `cfxk_`, `mysql://`, and `password.*=` should
land alongside the cutover so a future careless commit can't leak the recipe's
secrets.

## Quick reference

| Task                       | Command                                                        |
| -------------------------- | -------------------------------------------------------------- |
| Start                      | `docker compose up -d`                                         |
| Stop                       | `docker compose down`                                          |
| Status                     | `docker compose ps`                                            |
| Tail FXServer log          | `docker compose logs -f fivem`                                 |
| txAdmin                    | `http://localhost:40120`                                       |
| Adminer                    | `http://localhost:8080`                                        |
| FiveM connect              | Direct connect → `localhost:30120`                             |
| DB shell                   | `docker compose exec mariadb mariadb -u root -p"$DB_ROOT_PASSWORD"` |
| Force-rebuild a container  | `docker compose up -d --force-recreate <service>`              |
| Wipe & restart DB (destructive) | `docker compose down && rm -rf mariadb-data/ && docker compose up -d` — **deletes all DB data** |
