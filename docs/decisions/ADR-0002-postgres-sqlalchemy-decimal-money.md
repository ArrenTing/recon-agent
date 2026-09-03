# ADR-0002 — PostgreSQL 16 with SQLAlchemy 2 + Alembic; money as Decimal / NUMERIC(19,4)

Status: accepted · 2026-09-03 (Arren, design review)

## Context
The service books money against invoices. It needs exact arithmetic, check constraints, row-level locking for the booking transaction, idempotent imports, and later per-role grants that separate the agent path from the booking path.

## Decision
PostgreSQL 16 as the only production database; SQLAlchemy 2.0 typed models with explicit sessions and `with_for_update()`; Alembic migrations; all money columns `NUMERIC(19,4)` with `CHECK (amount > 0)`, all money in Python as `decimal.Decimal`, currency as `CHAR(3)` on every money-bearing row. SQLite is allowed only for unit tests of repositories.

## Alternatives considered
- SQLite in production: no role separation, weak concurrency, no true NUMERIC.
- MongoDB: no cross-document constraints; a ledger needs them.
- Integer minor units (cents or micro-units): exact and fast, and what Carbon used. Rejected for v1 because NUMERIC reads naturally in SQL and handles four-decimal FX rounding without per-currency scale tables. Recorded so the trade-off can be discussed.
- float: disqualifying for money.
- Django ORM / SQLModel: Django brings a framework we do not want; SQLModel hides SQLAlchemy exactly where locking and transactions need to be explicit.

## Consequences
- Docker Compose is required for local runs; tests stay fast on SQLite.
- Every amount passes through a Decimal boundary at ingest; a test fails on any `float(` in money code.
- Migrations accompany every schema change.
