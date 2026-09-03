# Tooling — what we use, what we considered, why not

Status: accepted 2026-09-03. Each row is a decision a hiring manager may ask about; the "why not" column is the interview answer.

| Need | Choice | Considered | Why not the others |
|---|---|---|---|
| Language runtime | **Python 3.12** | 3.14 (installed), 3.11 | 3.14 is weeks old; some compiled wheels (psycopg, pydantic-core, numpy for the eval report) lag new releases and CI images are thinner. 3.12 is the current LTS-like default in job postings. Revisit in 2027. |
| Env, deps, lockfile | **uv** | pip + venv, Poetry, pipenv | One tool for venv, resolve, lock, run, and Python version pinning; 10–100× faster installs so CI stays quick; `uv.lock` is deterministic. Poetry is fine but slower and its lock has had cross-platform quirks. pip alone has no lockfile. |
| Web framework | **FastAPI** | Django, Flask, Litestar | Type-driven validation via Pydantic is the point of the API surface; auto OpenAPI docs are useful in the README. Django brings an ORM, admin, and auth we don't want yet (ORM would fight SQLAlchemy). Flask needs add-ons for validation. Litestar is good but less recognised in postings. |
| Validation / schemas | **Pydantic v2** | dataclasses, attrs, marshmallow | Pydantic models double as FastAPI bodies, as the tool input schemas for the Anthropic SDK, and as the parse target for structured outputs. One schema language across all three boundaries. |
| ORM / migrations | **SQLAlchemy 2.0 + Alembic** | Django ORM, raw SQL + psycopg, SQLModel, Tortoise | SQLAlchemy 2 has typed models, explicit transactions and row locks (`with_for_update`) that the booking transaction needs. Alembic is the standard migration tool for it. Raw SQL loses model typing and makes tests verbose. SQLModel hides SQLAlchemy behind Pydantic and gets awkward exactly at locking/transactions. |
| Database | **PostgreSQL 16** | SQLite, MySQL, MongoDB | Money needs `NUMERIC`, check constraints, row locks, transactional integrity, and later per-role grants; Postgres has all of it and is the default in the postings targeted. SQLite lacks real concurrency and role separation (used for unit tests only). MongoDB has no cross-document constraints for a ledger. MySQL would work; Postgres is the stronger portfolio signal. |
| Money type | **`Decimal` ↔ `NUMERIC(19,4)`** | float, integer minor units | Float is disqualifying in finance. Integer minor units (Carbon's approach) are exact and fast but hurt readability in SQL and need per-currency scale handling; NUMERIC(19,4) is the textbook finance schema and reads naturally. |
| LLM SDK | **Anthropic Python SDK** (tool runner, structured outputs) | LangChain, LangGraph, LlamaIndex, raw HTTP | The SDK's tool runner is the loop, visible and explainable in an interview. LangChain/LangGraph add an abstraction layer that hides the loop and adds a large dependency surface for a five-tool agent; postings that name LangGraph can be served by a bounded variant branch later (ADR-0004). LlamaIndex is retrieval-centric; retrieval here is SQL. Raw HTTP means re-implementing streaming, retries, and tool plumbing the SDK already does. |
| Model | **`claude-opus-5`**, adaptive thinking | Sonnet 5, Haiku 4.5 | Correctness on money beats cost; the eval records cost so the trade-off is measured, not assumed. A cost-tier comparison (Opus vs Sonnet at same prompt) is a good README table for v1. |
| Tests | **pytest + hypothesis + freezegun** | unittest, nose | Property-based tests are the right tool for matcher invariants ("never across currencies", "allocations never exceed remaining"). pytest is what every posting expects. |
| Lint / format / types | **ruff + mypy --strict** | black + flake8 + isort, pylint, pyright | ruff replaces black/flake8/isort in one fast tool. mypy strict is the recognised bar; pyright is equally good but mypy is what CI templates and postings name. |
| CLI | **Typer** | argparse, click | Typer builds on click with type hints, matches the Pydantic/FastAPI style, and gives `--help` for free. argparse is fine but verbose. |
| Logging | **structlog** | stdlib logging, loguru | Key-value JSON logs that a reviewer can grep; stdlib logging is configured underneath. loguru is pleasant but non-standard in enterprise shops. |
| Review page | **Jinja2 + htmx served by FastAPI** | React/Vite, Streamlit, no UI | One template and a few endpoints; no build step, no node toolchain in a Python repo. React would double the work for a page with two buttons. Streamlit is quick but looks like a notebook, not a service. |
| Containers | **Docker Compose** (api + postgres) | bare local Postgres, devcontainer | `docker compose up` is the 90-second demo. Compose is enough; a devcontainer can come later. |
| CI | **GitHub Actions** | none, GitLab CI | Runs on push: ruff, mypy, pytest with coverage; manual/scheduled job runs the live eval with a repository secret and uploads the results JSON. Free for public repos, expected by reviewers. |
| Eval reporting | **pandas (eval only)** | polars, hand-rolled | pandas only inside `evals/` for the results table; keeps the service dependency set small. polars is faster but unnecessary at 300 rows. |
| Secrets | **`.env` + `python-dotenv`, SDK reads `ANTHROPIC_API_KEY`** | config files, Vault | Local tool; environment variables are the standard, and the SDK reads the key itself. `.env.example` documents keys with placeholders. |

## Things deliberately not in v1

- **Embeddings / vector search.** Matching is amount-and-name-driven; SQL with normalised aliases is more precise and auditable than semantic similarity. If vendor-name fuzziness turns out to need it, a `pg_trgm` index is the next step, not a vector store.
- **A queue (Celery/RQ).** Runs are minutes long and user-triggered; a background task in FastAPI is enough. Add a queue only if runs become concurrent.
- **Auth.** Local tool bound to localhost; README states it. Auth arrives with the `users` table in v2.
- **A JS frontend.** Proves nothing new for the target roles and doubles maintenance.
