# Vector — Infrastructure Spend Ledger

Running, board-visible record of recurring and one-time infrastructure costs.
Updated whenever a provider line item is added, removed, or repriced. Numbers
in EUR (Hetzner) or USD (everything else) — both totals shown in the rollup.

Approval rule (from [VEC-2 plan](/VEC/issues/VEC-2#document-plan)): **any
single line item > $100/mo escalates to CEO before provisioning.**
Company-wide envelope: **$100–500/mo**.

## Active line items

_None yet — provisioning pending CEO sign-off on the AX42 purchase._

## Planned line items (Phase 1)

| # | Provider | SKU | Region | Purpose | Recurring | One-time | Status |
|---|----------|-----|--------|---------|-----------|----------|--------|
| 1 | Hetzner | AX42 (Ryzen 5 7600, 64GB DDR5, 2× NVMe) | Falkenstein (FSN1) | Phase-1 dev box (prod+staging on different ports) | ~€48–55/mo | ~€39 setup | Awaiting CEO purchase |
| 2 | Backblaze | B2 Cloud Storage (S3-compatible) | EU-Central | Nightly mysqldump + resource snapshots, 30-day retention | ~$0.30/mo (≤50GB) | $0 | Awaiting bucket creation |
| 3 | Cloudflare Registrar | `vectorrp.com` (1-yr) | n/a | `dev.vectorrp.com` placeholder + Vector brand domain | ~$11/yr (≈$0.92/mo) | $0 | CMO rec in ([VEC-19](/VEC/issues/VEC-19#document-brand-domain)) — CEO purchase pending |

> Hetzner pricing fluctuates day-to-day; the AX42 figure is a recent-spot
> estimate. The hard rule is **≤€80/mo recurring** at the moment of order.

## Phase-1 rollup (planned)

| Bucket | EUR/mo | USD/mo (≈1.08) |
|--------|--------|----------------|
| Compute (Hetzner AX42) | 55 | 59 |
| Backup (Backblaze B2)  | —  | 0.30 |
| DNS / domain (amortised) | — | 0.92 |
| **Total recurring** | **~€55** | **~$60.22** |
| One-time setup (Hetzner) | 39 | 42 |

Well inside the $100–500/mo envelope.

## Change log

| Date | Change | Approver |
|------|--------|----------|
| 2026-05-06 | Ledger created. Phase-1 plan recorded. No active line items yet. | CTO |
| 2026-05-06 | Row 3 specified: Cloudflare Registrar, `vectorrp.com`, ~$11/yr. CMO recommendation in ([VEC-19](/VEC/issues/VEC-19#document-brand-domain)); CEO purchase pending. | CMO |

## Update protocol

When you add a line item:
1. Add a row to **Active line items** with provider, SKU, region, purpose, recurring + one-time, and status.
2. Update the rollup totals.
3. Append a one-line entry to the change log (date, what changed, approver).
4. If the new item alone exceeds **$100/mo recurring**, file a board approval
   *before* provisioning — don't backfill.

When a line item is decommissioned:
1. Move the row to a **Retired line items** section (create on first need) with the end date.
2. Update the rollup.
3. Change-log it.
