# Karpathy-Style LLM Wiki Principles

## When to read

Read this first when deciding whether a task belongs in this skill, when a
workflow feels like generic RAG, or when a reference/workflow needs to stay
aligned with Karpathy's LLM Wiki idea.

## Workflow

1. Treat the Wiki as a compounding knowledge layer, not a retrieval cache.
   Every ingest, query, synthesis, conflict, and correction should have a path
   to become durable `wiki/` content when it has reuse value.
2. Preserve raw sources separately. `raw/` is source material and provenance;
   it is not edited to fit the current interpretation.
3. Let the LLM do the maintenance work. The human chooses sources, asks
   questions, reviews emphasis, and resolves judgment calls; the LLM writes
   summaries, updates cross-links, maintains indexes, and repairs stale pages.
4. Prefer one source at a time for ingest. A single source can update many
   pages: source summary, entities, concepts, overviews, comparisons, decisions,
   disputed claims, and LOG.
5. Keep compiled pages human-readable. Even when Lark spreadsheet is the
   machine-writable state for `INDEX` and `SOURCES`, the Wiki should still feel
   like readable Markdown knowledge, not only a database.
6. Use query as a maintenance loop. A good answer should either cite existing
   compiled pages or become a new synthesis/overview/comparison/decision page.
7. Use lint to improve the Wiki, not only to produce a report. Lint should lead
   to repair plans: pages to update, refs to add/remove, disputes to create, and
   items needing human approval.

## Non-goals

- Generic RAG over chunks.
- A single Lark doc containing links.
- Local-only Obsidian or Git vault behavior.
- Fully automatic ETL that hides semantic changes from the human.
- Governance-heavy bookkeeping that prevents the LLM from actually maintaining
  the Wiki.

## Operating posture

- Start light: stage source, compile source, query, write back useful answers,
  lint occasionally.
- Escalate only when needed: coverage audit, drift audit, graph audit, semantic
  repair, and full `wiki-health`.
- Keep provenance visible: `source_refs`, `SOURCES`, `INDEX`, `LOG`, and stable
  slugs should let a human inspect why a page says what it says.
