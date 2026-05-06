# Logs — where they live, how to tail them

Inventory of every log surface on the inherited dev box, and the one-liner
that gets you to each. Operating context (start the box, ports, env vars)
lives in the [local-dev-server runbook](../runbooks/local-dev-server.md).

## TL;DR

```bash
cd ~/dev/vzu/server-local

# All three services, follow live
docker compose logs -f

# Just FXServer (where 99% of the action is)
docker compose logs -f fivem

# Filter to your resource
docker compose logs -f fivem | grep -E "vzu_my_resource|script:vzu_my_resource"

# MariaDB
docker compose logs -f mariadb
```

For richer FXServer logs (player chat, kicks, joins, console commands), use
the **txAdmin live console** at `http://localhost:40120` → Live Console.

## Log surfaces

The box runs three containers (`vzu_fivem`, `vzu_mariadb`, `vzu_adminer`) and
each writes both to its own files inside its container/volume **and** to
docker's stdout. Docker's stdout is what `docker compose logs` shows.

| Source           | docker stdout name | On-disk path (host)                                            | Rotation     |
| ---------------- | ------------------ | -------------------------------------------------------------- | ------------ |
| FXServer console | `fivem`            | `txData/default/logs/fxserver.log`                             | Daily        |
| FXServer history | `fivem`            | `txData/default/logs/fxserver_<date>_<idx>.log`                | Daily roll   |
| Player events    | `fivem`            | `txData/default/logs/server.log`                               | Daily        |
| txAdmin admin    | `fivem`            | `txData/default/logs/admin.log`                                | Daily        |
| FXServer history (CLI) | `fivem`      | `txData/default/logs/fxserver.history`                         | Append-only  |
| MariaDB error    | `mariadb`          | inside container at `/var/log/mysql/error.log` (default off)   | None         |
| MariaDB query    | `mariadb`          | inside container, only if `general_log = ON`                   | None         |
| Adminer access   | `adminer`          | docker stdout only                                             | None         |

### Why two paths per source

`docker compose logs` is the JSON-formatted stdout buffer, capped by docker's
default rotation (10MB × 3 files per container on most setups). Useful for
recent context and for grepping multiple services at once.

`txData/default/logs/*.log` is FXServer's own structured per-day log,
preserved for as long as txAdmin keeps them (default: 7 days). Useful for
"what happened on Tuesday afternoon" forensics. The `.history` file is
FXServer's REPL command history.

If you need something older than ~24h and outside docker's rotation, check
the on-disk files first.

## FXServer (the main one)

```bash
# Live tail
docker compose logs -f fivem

# Last 200 lines, no follow
docker compose logs --tail=200 fivem

# Last hour
docker compose logs --since=1h fivem

# Filter to a resource
docker compose logs -f fivem | grep -E "vzu_circuit_hack|script:vzu_circuit_hack"

# Errors and warnings only
docker compose logs -f fivem | grep -iE "error|warn|exception|^scripterror"
```

The on-disk version (more durable, slightly different format):

```bash
tail -f ~/dev/vzu/server-local/txData/default/logs/fxserver.log
ls -lh ~/dev/vzu/server-local/txData/default/logs/  # see what's available
```

### Inside the container

Sometimes you want to inspect the running FXServer process:

```bash
docker compose exec fivem bash
# inside container:
ps -ef | grep -E "FXServer|node"
ls /opt/cfx-server/    # FXServer install
ls /txData/             # mounted from host
```

### Resource-level scripting errors

When a Lua script crashes:

```
SCRIPT ERROR: @vzu_my_resource/server/main.lua:42: attempt to index a nil value (global 'frob')
> stack traceback:
>   …
```

These appear in `docker compose logs -f fivem` and on the txAdmin live
console. The `@<resource>/<file>:<line>` prefix tells you exactly where to
look. Client-side errors are in the FiveM client's `F8` console, not here.

## MariaDB

```bash
# stdout (startup, replication, fatal errors)
docker compose logs -f mariadb

# Connect to query system tables
source .env
docker compose exec -T mariadb mariadb \
  -u root -p"$DB_ROOT_PASSWORD" \
  -e "SHOW VARIABLES LIKE '%log%';"
```

### Slow queries (when something's lagging the server tick)

```bash
docker compose exec -T mariadb mariadb -u root -p"$DB_ROOT_PASSWORD" \
  -e "SET GLOBAL slow_query_log = 'ON'; SET GLOBAL long_query_time = 0.5;"

# trigger your suspected-slow workflow, then:
docker compose exec mariadb cat /var/lib/mysql/$(hostname)-slow.log
```

Don't leave `slow_query_log` on indefinitely on a long-running box — it
fills disk. Off by default; flip on for debugging, off after.

### General query log (every query)

```bash
docker compose exec -T mariadb mariadb -u root -p"$DB_ROOT_PASSWORD" \
  -e "SET GLOBAL general_log = 'ON'; SET GLOBAL general_log_file = '/var/lib/mysql/general.log';"

docker compose exec mariadb tail -f /var/lib/mysql/general.log
```

Same warning — it's *every* query, including framework chatter. Off after
debugging.

## oxmysql

`oxmysql` is the Lua/JS bridge between FXServer resources and MariaDB. It
doesn't have a separate log file — its output lands in the FXServer log
prefixed with `[oxmysql]`:

```bash
docker compose logs -f fivem | grep -E "\[oxmysql\]|oxmysql:"
```

Common patterns:

- `[oxmysql] [ERROR] Code: …` — query failed, message follows. Usually a
  bad SQL string or a missing column.
- `[oxmysql] [WARNING] Query took … ms` — slow query, see MariaDB section
  above.

To turn on per-query timing (noisy):

```
# in server.cfg (or set at runtime via the live console)
set mysql_debug "*"
set mysql_slow_query_warning 100   # ms threshold for the WARNING line
```

## txAdmin

The web panel at `http://localhost:40120` has its own log views:

- **Live Console** — what FXServer is printing right now, plus a command
  prompt. Same content as `docker compose logs -f fivem` but interactive.
- **Server Log** — FXServer events (resource start/stop, console commands,
  scheduled tasks).
- **Admin Log** — admin actions (kicks, bans, console-command runs by
  whom). Backed by `txData/default/logs/admin.log`.
- **Player Log** — joins, leaves, deaths, chat. Backed by
  `txData/default/logs/server.log`.

Same data is also reachable from the host:

```bash
tail -f ~/dev/vzu/server-local/txData/default/logs/admin.log
tail -f ~/dev/vzu/server-local/txData/default/logs/server.log
```

## Adminer

Adminer is a stateless web UI; its only log is HTTP request lines on stdout:

```bash
docker compose logs -f adminer
```

Useful when "I can't log in to Adminer" — confirms requests are reaching the
container and shows the HTTP status it returned.

## Centralised log shipping (not yet)

Today: nothing. Logs live where the docker daemon and the txData volume put
them, period.

Phase-1 deliverable on [VEC-9](/VEC/issues/VEC-9) is a remote sink — Loki or
Grafana Cloud free-tier, with a `promtail`-style collector tailing the
container stdout streams and the on-disk `txData/default/logs/`. That's what
will give us "show me every error across all environments for the last 30
days" — until then, ssh + grep.

## Common patterns

```bash
# What just failed?
docker compose logs --since=10m fivem | grep -iE "error|exception" | tail -20

# Did my resource start cleanly?
docker compose logs --tail=500 fivem | grep -E "Started resource (vzu_|<name>)"

# Did MariaDB come up healthy?
docker compose ps mariadb       # look for "(healthy)"
docker compose logs --tail=50 mariadb | grep -iE "ready for connections|error"

# Server didn't boot at all
docker compose logs --tail=100 fivem | head -50    # FXServer startup banner
docker compose ps                                   # are containers even up?

# Player joined but nothing happened
docker compose logs -f fivem | grep -E "joined|spawned|chargen|ox_inventory"
```

## Acceptance bar for "this is a real bug"

Before opening an issue:

- exact log lines copy-pasted (with the timestamps)
- which container produced them (`fivem` / `mariadb` / `adminer`)
- a minimal repro: "start the server, do X, observe Y"
- whether the same lines appear in a clean restart (rule out stale state)

If you can't get to that bar from the docker stdout buffer, check the
on-disk `txData/default/logs/` files for older context.
