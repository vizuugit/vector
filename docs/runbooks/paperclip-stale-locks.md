# Paperclip stale execution lock — what to do

When an issue's `executionRunId` / `checkoutRunId` points at a non-terminal run that's no longer active, every modify call from any agent fails with:

```
HTTP 409 / 422
"Issue run ownership conflict"
```

This is a Paperclip platform behavior, not a Vector bug. It has hit at least VEC-93, VEC-128, and (per VEC-166) is expected to recur.

## Root cause

- Paperclip auto-clears the lock when the held run reaches a terminal status (`succeeded` / `failed` / `cancelled` / `timed_out`) — see `clearExecutionRunIfTerminal` in `paperclip/server/src/services/issues.ts`.
- If a heartbeat shell exits **without** finalizing its run, the run row stays `running`, and auto-cleanup never fires.
- There is no server-side reaper that flips wedged `running` rows to `timed_out` after a timeout, so the lock persists indefinitely.

## What CANNOT clear it (don't try)

- `POST /api/issues/:id/checkout` (with or without `force: true`) — agent gets ownership conflict.
- `POST /api/issues/:id/release` — same.
- `PATCH /api/issues/:id` — same.
- `POST /api/issues/:id/comments` — same.
- `request_board_approval` — does NOT bypass run ownership. (Older guidance said it did; that was wrong.)
- `PATCH /api/runs/:id` / `POST /api/runs/:id/finish` / `clear-execution-lock` / `force-checkout` — none of these routes exist.

## What CAN clear it

```
POST /api/issues/:id/admin/force-release[?clearAssignee=true]
Auth: board-type session (human operator), NOT an agent run JWT.
```

- Source: `server/src/routes/issues.ts:3025-3069`. Returns `403 "Board access required"` to any non-board actor — agents (including CEO-agent) cannot call it.
- Effect: unconditionally nulls `checkoutRunId`, `executionRunId`, `executionLockedAt`. Optional `?clearAssignee=true` also nulls `assigneeAgentId`. Writes `issue.admin_force_release` audit event.

## Recommended response when an agent hits this

1. **Don't burn the heartbeat retrying** — agent calls will never succeed against the wedged lock.
2. **Route the next deliverable through a fresh child issue** (`parentId` = blocked issue, new assignee). New child has a clean lock space. Use `inheritExecutionWorkspaceFromIssueId` if the work shares a worktree.
3. **If the parent issue specifically must be modified** (e.g., to record a final decision on the original thread), comment tagging the human operator and ask them to run the force-release. Include the issue UUID, not just the identifier — saves them a lookup.
4. **Update the originally blocked task** to `blocked` with `blockedByIssueIds` pointing at the child carrying the work, OR leave it untouched if you can't write to it. Don't fight the lock.

## When you'd want to escalate upstream (Paperclip)

Two product-side fixes would prevent recurrence — neither is Vector's to ship:

- Run-timeout reaper that marks idle `running` rows as `timed_out`.
- Agent-callable force-release variant gated on idle-time threshold.

If a recurrence costs significant team time, escalate to the operator with a recap so they can file with the Paperclip team.
