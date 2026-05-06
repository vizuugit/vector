# VECTOR ZEN [U]

An independent dev studio building **mods, scripts, MLOs, and 3D models for GTA-RP / UGC**. Our clients are FiveM server owners — we deliver products to them; we are not currently operating a public server of our own.

> **Status:** day-zero scaffold. The studio is shipping its first products from this repo and working in the open. Brand wordmark: **`VECTOR ZEN [U]`**. Repository, package, and resource names continue to use the `vector-*` namespace.

## Mission

Be the dev studio FiveM server owners trust to ship the things they cannot build themselves: bespoke gameplay scripts, MLOs, vehicle and character models, art-direction-coherent UGC. Each product earns its own keep; we work in public so prospective clients can audit the engineering before they buy.

## Tech stack — internal dev/test rig

This studio runs a local FiveM/QBox dev server purely as **internal infrastructure for building, integrating, and validating client-bound products**. It is a dev rig, not a flagship product.

| Layer            | Choice                                  | Notes                                                    |
| ---------------- | --------------------------------------- | -------------------------------------------------------- |
| Target platform  | FiveM (CitizenFX)                       | See [ADR-0001](docs/adr/0001-platform-decision.md).      |
| Resource base    | qbox                                    | MIT-licensed core, fork-ready, dominant in client repos. |
| Server scripting | Lua (resources), some C# / JS as needed |                                                          |
| Database         | MariaDB                                 | The FiveM-native default. Migrations live in [`db/`](db).|
| Cache            | Redis                                   | For sessions, queues, server-side state.                 |
| Anti-cheat       | EAC + server-side checks                | Posture inherited so our products integrate cleanly.     |
| Dev hosting      | Local + low-cost cloud (cap tracked)    | See [`docs/infra-spend.md`](docs/infra-spend.md).        |
| CI               | GitHub Actions                          | Lua lint (luacheck + stylua) + format. CI lands later.   |

We optimize this rig for *parity with realistic client servers* — if a script ships against this stack, it should drop into a typical qbox-based RP server with minimal integration work.

## Repo layout

```
vector/
├── server/                # FiveM server config + recipe (txAdmin templates, server.cfg fragments)
├── resources/             # FiveM resources (qbox + our own vector-* products)
├── db/                    # SQL migrations (forward-only)
├── tools/                 # asset converters, deploy scripts, dev helpers
├── ops/                   # Ansible playbooks, terraform, runbooks-adjacent automation
├── docs/                  # ADRs, runbooks, onboarding, infra ledger
├── .github/workflows/     # CI (added in a follow-up issue)
├── CODEOWNERS
└── README.md
```

## License

[MIT](LICENSE) for code we own.

Vendored third-party content (qbox, community resources, art assets) keeps its own licenses. Each vendored resource lives under `resources/<name>/` with its upstream `LICENSE` and a short `VENDORED.md` noting source, version, and any local patches.

## A note on Rockstar / Take-Two IP

This studio does not redistribute Rockstar Games assets. Our products integrate with FiveM and require clients/players to supply their own legitimately-acquired GTA V install. We avoid monetizing Rockstar IP directly. Free and commercial mods that interoperate with FiveM follow the FiveM Terms of Service and the Cfx.re platform rules.

## Contributing

This repo is public, but the team is currently 1 (CTO). We are not yet accepting outside PRs. Expect that to change — the door is *intended* to open, just not today.

When it does open, the rules will be:

- One feature/fix per PR. PR description explains why.
- All Lua passes `luacheck` and `stylua` (config in [`.luacheckrc`](.luacheckrc) and [`stylua.toml`](stylua.toml)).
- No vendored binaries without a tracked source and license.
- No commits that touch `db/` and `resources/` in the same PR. Migrations land alone.

## Architecture decisions

ADRs live in [`docs/adr/`](docs/adr). Start with [`0001-platform-decision.md`](docs/adr/0001-platform-decision.md). Note that ADR-0001 was originally written under a "flagship server" framing; the platform pick (FiveM + qbox) still stands under the current B2B positioning. See the leading note in that ADR for context.

## Where work is tracked

Issues, roadmap, and decisions are tracked outside this repo in our internal Paperclip workspace. User-visible product milestones will be mirrored into this repo's Issues as products approach release.
