# ADR-0001 — Python 3.12 managed with uv

Status: accepted · 2026-09-03 (Arren, design review)

## Context
The machine has Python 3.12 and 3.14. The project needs a reproducible environment for CI and for anyone cloning the repo.

## Decision
Pin Python 3.12 (`.python-version`); manage the environment, lockfile, and scripts with `uv`.

## Alternatives considered
- Python 3.14: newest, but compiled dependencies and CI images lag; risk of wheel-build failures for no gain.
- pip + venv: no lockfile; reproducibility depends on discipline.
- Poetry: works, slower, and its lockfile has had cross-platform quirks; uv covers the same ground faster.

## Consequences
- One tool to learn; `uv run` for everything; `uv.lock` committed.
- Revisit the Python pin in 2027 when 3.14 wheels are universal.
