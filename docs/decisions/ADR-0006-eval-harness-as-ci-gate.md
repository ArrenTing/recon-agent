# ADR-0006 — The evaluation harness is a CI regression gate

Status: accepted · 2026-09-03 (Arren, design review)

## Context
Prompt and rule changes are easy to make and hard to judge by eye. The project's claim is that changes are measured.

## Decision
A seeded synthetic dataset with ground truth is checked in. `evals/run_eval.py` runs ingest, rules, and agent, then scores precision, recall, F1 (overall and by kind), exception recall, false bookings, tokens, cost, and wall time. It writes `evals/results/<date>-<sha>.json` and exits non-zero when false bookings > 0 or F1 < baseline minus tolerance from `evals/baseline.json`. CI runs unit tests on every push and the live eval on manual trigger or schedule with a repository secret. Baseline changes are explicit commits by Arren.

## Alternatives considered
- Manual spot checks: not credible and not repeatable.
- Real bank data: privacy and NDA problems; synthetic data with documented noise types is safer and lets the eval target specific failure modes.
- LLM-as-judge scoring: unnecessary when ground truth is known exactly.

## Consequences
- Every prompt or rule change carries a results file; the history is part of the portfolio.
- A live eval costs money; the job is manual or scheduled, never on every push.
