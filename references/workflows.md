# Lark LLM Wiki Workflow Index

Detailed workflows are split so agents only load the file they need. Each file
follows the Karpathy-style split between immutable `raw/` sources and durable
compiled `wiki/` knowledge.

- Init/bootstrap and registry: see `references/workflows/init-bootstrap.md`.
- Stage/import: see `references/workflows/stage-import.md`.
- Source compile / ingest: see `references/workflows/compile.md`.
- Query and answer writeback: see `references/workflows/query-writeback.md`.
- Lint, audit, repair, graph, drift: see `references/workflows/lint-audit-drift.md`.
- 内嵌 sheet reading rules are in `references/workflows/compile.md` and
  `references/workflows/query-writeback.md`.

Use `references/karpathy-principles.md` for the conceptual boundary and
`references/schema.md` for node tree, metadata, `INDEX`, `SOURCES`, and page
contracts.
