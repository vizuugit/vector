# Database migrations

How an engineer adds, applies, and verifies a schema change against the
inherited MariaDB. Operating context (start the box, find Adminer, env vars)
lives in the [local-dev-server runbook](../runbooks/local-dev-server.md).

## TL;DR

```bash
# 1. Author a forward-only migration file
$EDITOR db/migrations/0042_add_player_phone_column.sql

# 2. Apply it against the dev DB (today: pipe into the container)
cd ~/dev/vzu/server-local
source .env
docker compose exec -T mariadb mariadb -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
  < <repo>/db/migrations/0042_add_player_phone_column.sql

# 3. Verify
docker compose exec -T mariadb mariadb -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
  -e "DESCRIBE players;"

# 4. Commit the migration file
git add db/migrations/0042_add_player_phone_column.sql
git commit -m "db: add players.phone column"
```

There is **no scripted runner yet**. Each migration file is applied manually
exactly once per environment. Do not edit a migration after it's been applied
anywhere — write a new one.

## Where migrations live

```
<repo>/db/
└── migrations/
    ├── 0001_initial_schema.sql
    ├── 0002_add_indexes.sql
    └── …
```

Conventions:

- **Forward-only.** No `down` migrations. If you need to undo something,
  write a new migration that does the inverse.
- **Numbered, four-digit, monotonic.** `0001`, `0002`, … — the number is the
  apply order. Pad to four digits so we don't run out of sort space.
- **One concern per file.** A column add, an index add, a backfill — each is
  its own file. Don't bundle.
- **Idempotent where cheap.** `CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF
  NOT EXISTS`, `CREATE INDEX IF NOT EXISTS` make re-runs safe in dev when
  someone has already applied a draft. Production won't re-run, but dev will,
  and idempotency saves a lot of "drop the DB and start over" pain.
- **No secrets.** Migration files end up in the public monorepo. Don't seed
  test passwords or admin identifiers.

Naming: `NNNN_<short_imperative>.sql`, e.g.
`0042_add_player_phone_column.sql`. Read at-a-glance is the goal.

## Authoring a migration

1. Pick the next free number. `ls db/migrations | tail -1` shows the highest.
2. Write the SQL. Keep it boring:

   ```sql
   -- 0042: add phone column to players for npwd integration
   ALTER TABLE players
     ADD COLUMN IF NOT EXISTS phone VARCHAR(20) DEFAULT NULL;

   CREATE INDEX IF NOT EXISTS idx_players_phone ON players (phone);
   ```

3. Test it locally (see [Applying](#applying-a-migration) below).
4. Commit with the resource or feature change that needs it. Reviewers
   should never see a code change that depends on a migration that isn't
   in the same PR.

### When the migration comes from a vendored resource

Some 3rd-party resources ship their own SQL (e.g. `qbx_garages/sql/install.sql`).
Don't apply it directly. Instead:

1. Copy the SQL into a new migration file under `db/migrations/`.
2. Add a header comment naming the upstream resource and commit pin:

   ```sql
   -- 0017: qbx_garages — install schema
   -- vendored from: qbx_garages @ <pinned commit from VENDORED.md>
   -- upstream: https://github.com/Qbox-project/qbx_garages/blob/<commit>/sql/install.sql
   ```

3. Apply, commit alongside the resource add. This way our `db/migrations/`
   directory is the **only** authority for the schema state — we never have
   "well, the qbx_garages SQL also got applied at some point" surprises.

## Applying a migration

### Today — manual, against the dev box

```bash
cd ~/dev/vzu/server-local
source .env

# Apply a single file
docker compose exec -T mariadb mariadb \
  -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
  < <repo>/db/migrations/0042_add_player_phone_column.sql
```

The `-T` is important — it disables TTY allocation, which is what lets you
pipe stdin in. Without it, `mariadb` reads from your terminal and blocks.

### Or via Adminer (UI)

1. Open `http://localhost:8080`.
2. Log in (System: MySQL, Server: `mariadb`, creds from `.env`).
3. Pick the database, click "SQL command" in the sidebar.
4. Paste the migration file's contents, click Execute.

Use this for quick exploration; the CLI form above is preferred for "real"
applies because it's scriptable and the file path appears in shell history.

### After scripted runner lands

A migration runner is a follow-up deliverable (sibling issue under
[VEC-2](/VEC/issues/VEC-2)). When it lands, the workflow becomes:

```bash
pnpm db:migrate up         # apply all pending
pnpm db:migrate status     # show applied vs pending
```

…and a `db_migrations` tracking table will record what's been applied.
Until then: **manual, but tracked in git** is the contract.

## Verifying a migration

Always verify against MariaDB after applying. Cheap commands:

```bash
# describe a table
docker compose exec -T mariadb mariadb \
  -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
  -e "DESCRIBE players;"

# show indexes
docker compose exec -T mariadb mariadb \
  -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
  -e "SHOW INDEX FROM players;"

# spot-check data
docker compose exec -T mariadb mariadb \
  -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
  -e "SELECT id, name, phone FROM players LIMIT 5;"
```

If your migration backfills data, **count rows before and after** so you
catch silent zero-rows-affected outcomes:

```sql
SELECT COUNT(*) FROM players WHERE phone IS NULL;
-- run migration
SELECT COUNT(*) FROM players WHERE phone IS NULL;  -- should be lower
```

## Reset / start over (destructive)

When the dev DB is in a state you can't recover and you don't care about
losing data:

```bash
cd ~/dev/vzu/server-local
docker compose down
rm -rf mariadb-data/         # deletes everything in the DB
docker compose up -d
# then re-apply every file in db/migrations/ in order
```

This is dev-only — never even consider this on a Hetzner box. Production
backup/restore posture is a Phase-1 deliverable on [VEC-9](/VEC/issues/VEC-9).

## Backups before risky migrations

For anything that touches existing data (drops a column, type changes,
backfills), snapshot first:

```bash
mkdir -p ~/backups
docker compose exec -T mariadb mariadb-dump \
  --all-databases -u root -p"$DB_ROOT_PASSWORD" \
  > ~/backups/vzu-pre-NNNN-$(date +%Y%m%d-%H%M%S).sql
```

If the migration corrupts something:

```bash
docker compose exec -T mariadb mariadb \
  -u root -p"$DB_ROOT_PASSWORD" \
  < ~/backups/vzu-pre-NNNN-….sql
```

## Common pitfalls

- **`Access denied for user 'root'@'%'`.** You used `$DB_PASSWORD` instead of
  `$DB_ROOT_PASSWORD`, or vice versa. The application user (`$DB_USER`)
  doesn't have CREATE/ALTER privileges on tables it doesn't own; for schema
  changes against vendored tables, use root.
- **`Table … already exists`.** A previous run partially applied. `IF NOT
  EXISTS` clauses prevent this — add them and re-run, or hand-clean the
  half-applied state.
- **Resource won't start after migration.** Check the resource's `fxmanifest`
  for an `init` SQL it expects to run on first start; ours don't auto-create
  schema, but some 3rd-party do and conflict with the migration we wrote.
- **Foreign key errors mid-migration.** MariaDB has `SET FOREIGN_KEY_CHECKS
  = 0;` for the rare case where you legitimately need to defer constraint
  checking. Use sparingly and re-enable in the same file.

## Acceptance bar before merge

A migration is "ready" when:

- the file is numbered, named, and one-concern
- it has been applied against the dev box and verified
- if it backfills data, the verification includes a row-count check
- if it came from a vendored resource, the upstream commit is named in the
  header comment
- the resource code that depends on it is in the same commit/PR
