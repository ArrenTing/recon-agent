# ADR-0005 — Rules before the model; the agent proposes, only a human books

Status: accepted · 2026-09-03 (Arren, design review)

## Context
This is a money system with an LLM in it. The credibility of the project rests on two boundaries being real, not aspirational.

## Decision
1. The deterministic matcher (`rules.py`) runs first; the agent receives only what it left open.
2. Agent tools may write only `match_proposals`, `match_lines`, and `exceptions`, always with status `proposed`. `allocations`, `invoices.status`, and `payments.status` are written only by `booking.py`, which is called only by `review.py` on an explicit human confirm carrying an actor. Enforced by module structure, by permanent negative tests, and in v2 by separate database roles.
3. Guards on tolerance, currency, size, and confidence are code in `agent/guards.py`; the prompt is advisory.

## Alternatives considered
- Auto-book high-confidence agent matches: a faster demo, but it removes the boundary that makes the project defensible and turns "false bookings" from a measured metric into a live risk.
- Model first with rules as a fallback: more expensive, less deterministic, and the eval loses its control group.
- Prompt-only guardrails: the injection test exists precisely because prompts are not enforcement.

## Consequences
- The review step is mandatory in the demo; the README explains why in one paragraph.
- The eval defines a false booking as a proposal that would book wrongly if confirmed; the guard layer must keep it at zero.
- Any change adding a write path from the agent to booked state is treated as a High security finding.
