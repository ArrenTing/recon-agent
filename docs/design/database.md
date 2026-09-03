# Database design — v1 (first go; extend later by ADR)

Status: **v1 accepted 2026-09-03.** PostgreSQL 16. UUID primary keys (`gen_random_uuid()`), `timestamptz` for instants, `date` for business dates, `NUMERIC(19,4)` for money, `CHAR(3)` ISO 4217 for currency. All tables have `created_at timestamptz not null default now()`.

## 1. Entity map

```
vendors 1──* vendor_aliases
vendors 1──* invoices
invoices *──* payments        via match_lines (proposed)  and  allocations (booked)
match_proposals 1──* match_lines
agent_runs 1──* match_proposals (when proposed_by = agent)
payments / invoices 0..1──* exceptions
everything ──▶ audit_events (append-only)
```

Two many-to-many tables on purpose: `match_lines` is what was *proposed*; `allocations` is what was *booked*. They are never merged, so "what did the model say" and "what is true in the ledger" stay separable — that separation is the whole point of the project.

## 2. Tables

### vendors
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| canonical_name | text not null unique | display name |

### vendor_aliases
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| vendor_id | uuid fk → vendors on delete cascade | |
| alias | text not null | as seen on a statement |
| normalized | text not null unique | `normalise(alias)`; the lookup key for rule R2 |

### invoices
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| vendor_id | uuid fk → vendors | |
| invoice_number | text not null | unique per vendor |
| amount | numeric(19,4) not null check (amount > 0) | |
| currency | char(3) not null | |
| issued_on | date not null | |
| due_on | date not null check (due_on >= issued_on) | |
| status | enum invoice_status not null default 'open' | open, partially_paid, paid, void |
| source_ref | text | import batch / file name |
| unique (vendor_id, invoice_number) | | |

### payments
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| counterparty_raw | text not null | untrusted text from the statement |
| amount | numeric(19,4) not null check (amount > 0) | |
| currency | char(3) not null | |
| posted_on | date not null | |
| memo | text | untrusted text |
| bank_ref | text not null unique | idempotent import key |
| status | enum payment_status not null default 'unmatched' | unmatched, partially_allocated, allocated, exception |
| source_ref | text | |

### agent_runs
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| started_at / finished_at | timestamptz | |
| model | text not null | e.g. claude-opus-5 |
| prompt_version | text not null | from prompts.py |
| input_tokens / output_tokens | integer | |
| cost_usd | numeric(10,6) | |
| tool_calls | integer | |
| status | enum run_status | running, succeeded, failed, budget_exceeded |
| error | text | |

### match_proposals
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| kind | enum match_kind not null | exact, partial, combined, fee_adjusted |
| confidence | numeric(4,3) not null check (0 ≤ confidence ≤ 1) | |
| reason | text not null | model's or rule's explanation, shown to reviewer |
| proposed_by | enum proposer not null | rules, agent |
| agent_run_id | uuid fk → agent_runs, null when rules | check: agent ⇔ run id present |
| status | enum proposal_status not null default 'proposed' | proposed, confirmed, rejected, superseded |
| decided_by | text | actor string (v1: free text; v2: users table) |
| decided_at | timestamptz | |
| decision_note | text | reviewer's reason on reject |

### match_lines
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| proposal_id | uuid fk → match_proposals on delete cascade | |
| invoice_id | uuid fk → invoices | |
| payment_id | uuid fk → payments | |
| allocated_amount | numeric(19,4) not null check (> 0) | |
| currency | char(3) not null | must equal invoice and payment currency (service check + test) |
| unique (proposal_id, invoice_id, payment_id) | | |

### allocations  (the ledger of truth — written only by booking.py)
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| invoice_id | uuid fk → invoices | |
| payment_id | uuid fk → payments | |
| amount | numeric(19,4) not null check (> 0) | |
| currency | char(3) not null | |
| proposal_id | uuid fk → match_proposals not null | provenance |
| booked_by | text not null | human actor |
| booked_at | timestamptz not null default now() | |

Invariants (enforced in `booking.py` inside a `FOR UPDATE` transaction, and by tests; DB trigger is a v2 ADR candidate):
- Σ allocations.amount per invoice ≤ invoices.amount
- Σ allocations.amount per payment ≤ payments.amount
- allocations.currency = invoices.currency = payments.currency

### exceptions
| column | type | notes |
|---|---|---|
| id | uuid pk | |
| payment_id | uuid fk null | |
| invoice_id | uuid fk null | check: at least one of the two |
| reason | text not null | |
| raised_by | enum raiser not null | rules, agent, human, guard |
| status | enum exception_status default 'open' | open, resolved |
| resolved_by / resolved_at / resolution | text / timestamptz / text | |

### audit_events (append-only)
| column | type | notes |
|---|---|---|
| id | bigint identity pk | ordering |
| at | timestamptz not null default now() | |
| actor | text not null | human actor, `rules`, `agent:<run_id>`, `guard` |
| entity_type | text not null | invoice, payment, proposal, allocation, exception |
| entity_id | uuid not null | |
| action | text not null | imported, proposed, confirmed, rejected, booked, flagged, resolved |
| payload | jsonb | before/after or the proposal snapshot |

No UPDATE or DELETE on this table from the application; v2 ADR: revoke those grants from the app role.

## 3. Indexes (v1)

- `invoices (vendor_id, status)`; `invoices (currency, amount)` — candidate lookup for rules and search tools
- `payments (status)`; `payments (currency, amount)`; `payments (posted_on)`
- `vendor_aliases (normalized)` (unique already)
- `match_lines (invoice_id)`, `match_lines (payment_id)`
- `allocations (invoice_id)`, `allocations (payment_id)`
- `match_proposals (status, created_at)` — the review queue
- `audit_events (entity_type, entity_id, at)`

## 4. Why these choices (short form; ADRs carry the long form)

- **Two link tables** (`match_lines` vs `allocations`): keeps proposed and booked separable; lets the eval count "false bookings" as proposals that *would* have booked wrongly, independent of what a reviewer did.
- **Stored invoice/payment status** rather than a view: simpler queries for the review page and search tools; recomputed inside the booking transaction; an invariant test compares stored status to derived status across the whole table.
- **`bank_ref` unique**: makes CSV import idempotent, which matters for the eval harness re-running.
- **Actor as text in v1**: no users table until auth exists (v2). Avoids building auth for a local tool.
- **UUIDs**: safe to generate client-side in tests and the dataset generator; no sequence coupling.
- **`NUMERIC(19,4)` not integer minor units**: standard for finance schemas and readable in SQL; four decimals cover FX rounding cases. Integer micro-units (used at Carbon) are the alternative; the ADR records the trade-off.

## 5. Deferred to v2 (each needs an ADR)

- Separate DB roles: `recon_agent` (read + insert on proposals/lines/exceptions) and `recon_booking` (insert on allocations, update statuses).
- DB-level triggers for the allocation sum invariants and the audit append-only rule.
- `users` table and real auth; `decided_by`/`booked_by` become FKs.
- Multi-entity (company) scoping.
- Soft delete / void flows for invoices and payment reversals.
