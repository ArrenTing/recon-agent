# ADR-0004 — Agent loop on the Anthropic Python SDK tool runner; no LangChain or LangGraph in the core

Status: accepted · 2026-09-03 (Arren, design review)

## Context
The agent has six tools and one job. The loop must be explainable line by line in an interview, testable with recorded responses, and cheap in dependencies. Some target postings name LangGraph.

## Decision
Use the Anthropic Python SDK directly: `client.beta.messages.tool_runner` with `@beta_tool` functions, `strict` input schemas, `client.messages.parse` for the structured final summary, model `claude-opus-5` with adaptive thinking. Implementation follows the `claude-api` skill's Python documentation, not memory. LangChain and LangGraph are excluded from `src/`. If a target employer requires LangGraph, a bounded `langgraph-variant/` implementation of the same six tools may be added under a separate ADR, kept out of the core.

## Alternatives considered
- LangGraph: good for complex stateful graphs; here it would wrap a single loop in an abstraction that hides the mechanism and adds a large dependency surface.
- LangChain: same, plus API churn.
- LlamaIndex: retrieval-centric; our retrieval is SQL.
- Raw HTTP: re-implements what the SDK already does (retries, streaming, tool plumbing).
- Claude Agent SDK: a filesystem and shell coding harness; the wrong shape for a database-tool agent.

## Consequences
- Unit tests mock the SDK; the eval hits the real API only with `RECON_EVAL_LIVE=1`.
- The README can show the loop in about forty lines, which is the interview asset.
