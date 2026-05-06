# Contributing to Vector

This monorepo is small and the rules are short. Read this before opening a PR.

## Branching and merging

- `main` is protected. No direct pushes — open a PR.
- Branch off `main`. Name branches `<scope>/<short-slug>` (e.g. `resources/qbx-spawn-fix`, `ops/hetzner-bootstrap`).
- Squash-merge only — `main` keeps a linear history. No merge commits, no rebase-merges.
- Delete branches after merge.

## Commit messages (Conventional Commits-lite)

Subject format: `type(scope): summary` — scope is optional but encouraged.

| Type       | When to use                                            |
| ---------- | ------------------------------------------------------ |
| `feat`     | New user-visible behavior or feature                   |
| `fix`      | Bug fix                                                |
| `docs`     | Documentation only                                     |
| `chore`    | Repo plumbing, tooling, dependencies, formatting       |
| `refactor` | Internal change with no behavior change                |
| `test`     | Tests only                                             |
| `perf`     | Performance change                                     |
| `revert`   | Reverts a previous commit                              |

Rules:
- Keep the subject under 72 characters, imperative mood (`fix: …`, not `fixed: …`).
- Use the body for the *why*, not the *what* — the diff already shows what.
- One logical change per commit. Split unrelated work into separate commits or PRs.

### Required co-author footer

Every commit MUST end with this exact line (per `AGENTS.md`):

```
Co-Authored-By: Paperclip <noreply@paperclip.ing>
```

Commits authored by Paperclip agents already include it. Human contributors must add it manually.

Example:

```
feat(resources/qbx-core): wire spawn selector to Prologue start

Hooks the Prologue heist intro into qbx_core's first-spawn flow so
the closed-alpha entry point doesn't fall through to vanilla MP.

Co-Authored-By: Paperclip <noreply@paperclip.ing>
```

## Pull requests

Use the template at [`.github/pull_request_template.md`](../.github/pull_request_template.md). Every PR needs:

1. **Summary** — one or two sentences on what changed and why.
2. **Test plan** — exact steps that prove the change works (commands, manual repro, screenshots when UI). "Ran the build" is not a test plan.
3. **Related issue** — link to the Vector issue (e.g. `[VEC-14](/VEC/issues/VEC-14)`). If there isn't one, you probably shouldn't be merging this.

Other expectations:
- At least one approving review before merge. CODEOWNERS routes the request automatically.
- Required CI checks must pass. Required status checks become enforceable as soon as the CI workflows land — see the open CI issue.
- Keep PRs scoped. If your branch grows past ~400 lines of meaningful diff, split it.

## What you must not do

- **No `--no-verify`.** Pre-commit and pre-push hooks exist for a reason; if a hook fails, fix the underlying issue.
- **No `--no-gpg-sign` / `--no-edit` of CI commit signing.** Don't bypass signing or commit-template enforcement.
- **No skipping CI** (e.g. `[skip ci]`, disabling checks at merge time, force-merging an admin override). Required checks are required.
- **No force-pushes to `main`.** Branch protection blocks this; do not work around it.
- **No secrets in commits.** Real credentials, tokens, license keys, API keys, MariaDB passwords, FXServer license keys, S3 keys — none of it goes into the repo. Commit `*.example` files only (e.g. `server.cfg.example`, `.env.example`) and document the required keys without their values. If a secret slips in, treat it as a security incident: rotate the credential first, then scrub history.
- **No large binary blobs.** Mods, audio, dumps, and gameplay assets belong in our asset bucket (see [`docs/infra-spend.md`](./infra-spend.md)), not in git.

## Local checks before pushing

The repo's hooks run lint and format checks; run them yourself if you want a faster signal:

- Lua: `luacheck` + `stylua --check` (see `.luacheckrc`, `stylua.toml`).
- Editor: `.editorconfig` is authoritative — match indentation and final-newline rules.
- Server runbook: [`docs/runbooks/local-dev-server.md`](./runbooks/local-dev-server.md) covers spinning up the local FiveM/QBox stack to manually verify gameplay-affecting changes.

## When in doubt

Open a draft PR or comment on the issue and ask. The CTO reviews everything until the engineer fan-out in `CODEOWNERS` becomes active.
