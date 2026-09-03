# Architecture — v0 (design review draft, 2026-09-03)

Status: **v0 accepted 2026-09-03 (see §11). No application code yet.**

## 1. The job in one sentence

Take an accounts-payable invoice list and a bank/card payment list, settle everything the rules can settle, let a Claude agent propose the rest with a reason and a confidence, and let a person confirm before anything is booked, while measuring the whole pipeline against a labelled dataset on every change.

## 2. Wireframe

```
                 ┌────────────┐          ┌──────────────┐
  CSV / CLI ───▶ │  Ingest    │ ───────▶ │  PostgreSQL  │◀───────────────────────┐
                 │ (validate, │          │  invoices    │                        │
                 │  Decimal,  │          │  payments    │                        │
                 │  vendors)  │          │  proposals   │                        │
                 └────────────┘          │  allocations │                        │
                                         │  audit       │                        │
                                         └──────┬───────┘                        │
                                                │ open invoices + payments        │
                                                ▼                                 │
                                         ┌──────────────┐  proposals (rules)      │
                                         │ Rules matcher│ ───────────────┐        │
                                         │ (pure fns)   │                │        │
                                         └──────┬───────┘                │        │
                                                │ leftovers only          │        │
                                                ▼                         ▼        │
                                         ┌──────────────┐        ┌──────────────┐ │
                                         │ Agent runner │ tools  │  Proposals   │ │
                                         │ Claude +     │───────▶│  + Exceptions│ │
                                         │ tool runner  │ (read; │  (status:    │ │
                                         │ + guards     │propose)│   proposed)  │ │
                                         └──────────────┘        └──────┬───────┘ │
                                                                        │         │
                                                            human       ▼         │
                                                         ┌──────────────────┐     │
                                                         │ Review (FastAPI  │     │
                                                         │ page or CLI)     │     │
                                                         │ confirm / reject │     │
                                                         └────────┬─────────┘     │
                                                                  │ confirm only   │
                                                                  ▼                │
                                                         ┌──────────────────┐     │
                                                         │ Booking service  │─────┘
                                                         │ writes           │ allocations,
                                                         │ allocations,     │ statuses,
                                                         │ recomputes status│ audit event
                                                         └──────────────────┘

  Eval harness: generate dataset ─▶ Ingest ─▶ Rules ─▶ Agent ─▶ compare proposals
  to ground truth ─▶ results JSON ─▶ CI gate (false bookings = 0, F1 ≥ baseline − tol)
```

The one arrow that matters: nothing reaches `allocations` except the Booking service, and the Booking service only runs from a human confirm.

## 3. Components

| Component | Module | Responsibility | Talks to |
|---|---|---|---|
| Ingest | `recon/ingest.py` | Parse CSV, validate with Pydantic, parse money as Decimal, normalise vendor names into `vendors`/`vendor_aliases`, insert invoices/payments | DB |
| Rules matcher | `recon/rules.py` | Pure functions: given open invoices + unmatched payments, return exact-match proposals. No I/O. | nothing (called by pipeline) |
| Pipeline | `recon/pipeline.py` | Orchestrates ingest → rules → agent for a run; records `agent_runs` | DB, rules, agent |
| Agent runner | `recon/agent/runner.py` | Builds the tool-runner loop with the leftovers as context, collects proposals, enforces guards, records tokens/cost | Anthropic API, tools, guards |
| Agent tools | `recon/agent/tools.py` | `search_invoices`, `search_payments`, `get_invoice`, `get_payment` (read-only); `propose_match`, `flag_exception` (write to proposals/exceptions only) | DB (read), proposals (write) |
| Guards | `recon/agent/guards.py` | Pure checks applied to every proposal before it is saved: tolerance by kind, currency equality, max lines, large-amount auto-exception, confidence floor | nothing |
| Review | `recon/review.py` | List proposals; confirm/reject with actor; on confirm call Booking | DB, Booking |
| Booking | `recon/booking.py` | In one transaction: lock invoice+payment rows, check remaining amounts, write `allocations`, recompute statuses, write `audit_events` | DB |
| API | `recon/api.py` | FastAPI: `/health`, `/imports`, `/runs`, `/proposals`, `/proposals/{id}/confirm|reject`, `/review` HTML page | Ingest, Pipeline, Review |
| CLI | `recon/cli.py` | Typer: `recon load`, `recon run`, `recon review`, `recon eval` | same services as API |
| Eval | `evals/` | Dataset generator, ground truth, scorer, baseline gate | Pipeline (with `RECON_EVAL_LIVE`) |

## 4. Boundaries (the design's spine)

1. **Rules before model.** The agent receives only what `rules.py` left open. Rationale: cheaper, deterministic where determinism is possible, and it gives the eval a control group ("what did the model add over rules?").
2. **Agent proposes, human books.** Agent tools can write `match_proposals`, `match_lines`, `exceptions` with status `proposed`. Only `booking.py`, called from `review.py` on a human confirm, writes `allocations` and changes `invoices.status` / `payments.status`. Enforced by module structure, by tests that assert it, and by DB grants later (ADR-0007 candidate: separate DB roles for agent vs booking).
3. **Money is Decimal.** `NUMERIC(19,4)` in Postgres, `decimal.Decimal` in Python, currency carried on every money-bearing row and checked equal across a match line.
4. **Guards live in code, not prompts.** The prompt asks for careful matching; `guards.py` refuses anything outside tolerance regardless of what the model says. The injection test proves it.

## 5. Matching rules, v1

Given invoice `I` (open or partially paid, remaining `R`) and payment `P` (unmatched), same currency:

- **R1 exact-by-reference:** `P.amount == R` and `I.invoice_number` appears (normalised) in `P.memo` or `P.bank_ref` → exact, confidence 1.0.
- **R2 exact-by-vendor:** `P.amount == R` and `normalise(P.counterparty)` matches a `vendor_aliases.normalized` for `I.vendor` and `I.issued_on ≤ P.posted_on ≤ I.due_on + 30d` → exact, confidence 0.95. If more than one invoice qualifies, R2 does not fire (ambiguity goes to the agent).

Everything else is a leftover for the agent. Normalisation: lowercase, strip punctuation and legal suffixes (`inc`, `ltd`, `llc`, `corp`), collapse whitespace.

## 6. Agent design, v1

- **Context:** system prompt (versioned in `prompts.py`), then a data block listing leftover payments (id, amount, currency, date, memo, counterparty) and a summary of open invoices per vendor. Untrusted fields are always inside the data block, never in the system prompt.
- **Tools:** four read tools with bounded schemas (`limit ≤ 25`, amount and date ranges required for searches, `strict: true`); two write tools. No tool takes free-form SQL or file paths.
- **Loop:** Anthropic SDK tool runner (`client.beta.messages.tool_runner`), model `claude-opus-5`, adaptive thinking, max 40 tool calls per run, structured output (`client.messages.parse`) for the final summary so nothing free-text reaches the DB.
- **Guards (code, per proposal):**

| Kind | Rule |
|---|---|
| exact | sum(lines) == payment amount exactly |
| partial | one invoice, one payment, allocated ≤ remaining, payment fully allocated |
| combined | one payment, 2–6 invoices, sum(lines) == payment amount within 0.01 |
| fee_adjusted | one invoice, one payment, shortfall ≤ max(2 %, 5.00) of invoice remaining |
| any | currency equal on all lines; confidence ≥ 0.5 to save; any line with amount ≥ 10,000 also raises an exception for review |

- **Cost cap:** a run stops at a configured token budget and records `status = failed` with reason; partial proposals are kept.

## 7. Request lifecycle (confirm)

`POST /proposals/{id}/confirm` with `actor` → review loads proposal (must be `proposed`) → booking opens a transaction, `SELECT … FOR UPDATE` on the invoices and payment in its lines → checks each invoice remaining ≥ allocated and payment unallocated ≥ sum → inserts `allocations` → updates invoice statuses (paid if remaining == 0, else partially_paid) and payment status → marks proposal `confirmed` with `decided_by/at` → marks any other `proposed` proposals sharing a payment as `superseded` → writes one `audit_events` row per entity touched → commit. Any failure rolls back everything and returns 409 with the reason.

## 8. Eval harness

Dataset: ~300 invoices across ~40 vendors, ~300 payments, seeded generator with named noise types: vendor alias variants, partial payment, two-invoice combined payment, bank fee shaved, FX rounding (±0.02), duplicate payment, true orphan payment, orphan invoice, memo containing injected instructions. Ground truth lists the correct proposals and the expected exceptions.

Metrics: precision/recall/F1 overall and by kind; exception recall; **false bookings** (a confirmed-if-auto-accepted proposal that contradicts ground truth — must be 0 at the guard level); tokens; cost; wall time. Results are committed; CI fails on false bookings > 0 or F1 below baseline minus tolerance.

## 9. Runtime and non-goals

Docker Compose: `api` (uvicorn) + `db` (Postgres 16). API binds to localhost; no auth in v1 by design. Non-goals for v1: bank integrations, multi-tenant auth, embeddings, a JS frontend, LangGraph in the core.

## 10. Open questions for Arren (decide before code)

1. Invoice status stored and recomputed (chosen) vs. purely derived view? Stored keeps queries simple; the invariant test guards drift.
2. Tolerance numbers in §6: are 2 % / 5.00 / 10,000 the right first guesses from your AP experience?
3. Should R2 (exact-by-vendor) count as "rules" at 0.95, or should anything under 1.0 go to a human? Current design: it is still a proposal a human confirms, so it stays.
4. Do we want separate Postgres roles (agent = read + proposals only; booking = allocations) in v1, or defer to v2? Recommendation: defer, test-enforce in v1, ADR later.

## 11. Decisions taken (2026-09-03, Arren)

1. Invoice status: **stored and recomputed** inside the booking transaction; invariant test compares stored vs derived.
2. Tolerances: **accepted as first guesses** — fee-adjusted shortfall ≤ max(2 %, 5.00); combined rounding 0.01; large-amount flag at 10,000. Revisit after the first eval run.
3. Rule R2 (exact-by-vendor, 0.95): **stays a rule**; a human still confirms.
4. Separate Postgres roles: **v2**, by ADR; test-enforced in v1.
5. Money: **NUMERIC(19,4) / Decimal**; integer minor units recorded as the alternative in ADR-0002.
6. Repo **public from the first commit**.
7. Name: **recon-agent**.
