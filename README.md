# Vector

A small GTA mod & server dev studio. We build mods, content, and a flagship FiveM server, and we work in the open.

> **Status:** day-zero scaffold. There is no playable server yet. This repo exists so the work is public from the start.

## Mission

Ship a flagship FiveM RP server, premium-but-tasteful mods, and the content that drives players to both. Tech choices serve those three pillars; everything else is overhead.

## Tech stack (target)

| Layer            | Choice                                  | Notes                                                    |
| ---------------- | --------------------------------------- | -------------------------------------------------------- |
| Server platform  | FiveM (CitizenFX)                       | See [ADR-0001](docs/adr/0001-platform-decision.md).      |
| Resource base    | qbox                                    | MIT-licensed core, fork-ready, active community.         |
| Server scripting | Lua (resources), some C# / JS as needed |                                                          |
| Database         | MariaDB                                 | The FiveM-native default. Migrations live in [`db/`](db).|
| Cache            | Redis                                   | For sessions, queues, server-side state.                 |
| Anti-cheat       | EAC + server-side checks                |                                                          |
| Host             | Hetzner dedicated, monthly budget cap   | See [`docs/infra-spend.md`](docs/infra-spend.md).        |
| CI               | GitHub Actions                          | Lua lint (luacheck + stylua) + format. CI lands later.   |

## Repo layout

```
vector/
├── server/                # FiveM server config + recipe (txAdmin templates, server.cfg fragments)
├── resources/             # FiveM resources (qbox + our own)
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

This project does not redistribute Rockstar Games assets. To run the server you supply your own legitimately-acquired GTA V install. We avoid monetizing Rockstar IP directly. Free mods that interoperate with FiveM follow the FiveM Terms of Service and the Cfx.re platform rules.

## Contributing

This repo is public, but the team is currently 1 (CTO). We are not yet accepting outside PRs. Expect that to change — the door is *intended* to open, just not today.

When it does open, the rules will be:

- One feature/fix per PR. PR description explains why.
- All Lua passes `luacheck` and `stylua` (config in [`.luacheckrc`](.luacheckrc) and [`stylua.toml`](stylua.toml)).
- No vendored binaries without a tracked source and license.
- No commits that touch `db/` and `resources/` in the same PR. Migrations land alone.

## Architecture decisions

ADRs live in [`docs/adr/`](docs/adr). Start with [`0001-platform-decision.md`](docs/adr/0001-platform-decision.md).

## Where work is tracked

Issues, roadmap, and decisions are tracked outside this repo. The first 30/60/90-day plan is in our internal Paperclip workspace as `VEC-2`. We will start mirroring user-visible milestones into this repo's Issues once the server has a closed alpha.
