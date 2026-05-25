# Compile Source Into Wiki

## When to read

Read this for compile, ingest, source digestion, cross-page updates, mutation
plans, `compiled_unverified`, source pages, and any request where the user wants
the LLM to maintain the Wiki from a source. This is the core Karpathy-style LLM
Wiki workflow.

## Workflow

Default flow:

```text
stage -> compile context pack -> human checkpoint -> write pages -> INDEX/SOURCES/LOG -> structure lint
```

Do not stop after `wiki-compile-source-plan` unless the user only asked for a
plan. The command gathers context; the LLM must still do the semantic work.

1. Read runtime rules from `AGENTS.md`, then read `INDEX`, `SOURCES`, and recent
   `LOG`.
2. Run or inspect:

   ```bash
   scripts/lark_wiki.sh wiki-compile-source-plan "$ROOT" "$SOURCE_ID_OR_TITLE"
   ```

3. Read the source's raw shortcut, extraction page, and existing
   `wiki/sources/<source>` page if one exists.
4. Select affected compiled pages from `wiki/entities`, `wiki/concepts`,
   `wiki/comparisons`, `wiki/overviews`, `wiki/decisions`, `wiki/syntheses`,
   and `wiki/disputed`. Prefer updating existing pages over making duplicates.
5. Human checkpoint before mutating cross-page state:
   - 5-10 条 key takeaways.
   - likely affected existing pages.
   - new entities/concepts that might deserve pages.
   - conflicts with old claims.
   - suggested emphasis or scope.
   - items requiring user judgment.
6. After user confirmation or reasonable default continuation, write pages:
   - create or update `wiki/sources/<source>`;
   - update relevant entity/concept pages;
   - update overviews/comparisons/decisions/syntheses when the source changes a
     broader topic;
   - create/update `wiki/disputed` for contradictions;
   - create/update `wiki/audits/<source-id>-coverage` when needed.
7. Every factual paragraph or claim table row needs `source_refs`. If a statement
   is inference, mark it as inference and cite supporting source refs.
8. Use stable claim IDs on the source page. Claim IDs let later audit, drift, and
   disputed pages reference precise statements.
9. Add links/backlinks in prose and `related_pages` so the Wiki becomes a graph,
   not isolated summaries.

## Page writing details

1. `wiki/sources/<source>` should include summary, key claims, entities,
   concepts, pages updated, claims excluded, conflicts, open questions, and
   coverage audit status.
2. Entity/concept pages should accumulate evidence across sources. Do not replace
   old support with the latest source.
3. Overview/comparison/synthesis pages should explain how sources relate, where
   they agree, and where they differ.
4. Disputed pages are first-class pages. Do not silently overwrite reviewed
   claims when a new source conflicts.
5. Passing mentions stay on the source page unless they meet the page-creation
   thresholds in `references/schema.md`.

## Directory synchronization

After writing pages, do 目录同步 immediately.

1. For every real created or updated compiled page, upsert the corresponding
   `INDEX` spreadsheet sheet/section. Use helper commands such as:

   ```bash
   scripts/lark_wiki.sh wiki-index-upsert-page "$ROOT" Concepts "wiki/concepts/foo" "summary" 2
   scripts/lark_wiki.sh wiki-index-upsert-page "$ROOT" Overviews "wiki/overviews/bar" "summary" 3
   scripts/lark_wiki.sh wiki-index-upsert-audit "$ROOT" "wiki/audits/src-coverage" "SRC-YYYY-MM-DD-001"
   ```

2. `INDEX.Page` must be a canonical plain path, not a Markdown link.
3. `INDEX` and `SOURCES` new/rebuilt state is spreadsheet-based. Legacy Markdown
   tables are fallback only.
4. `Compiled Into` and `compiled_into` multi-value refs must be 可点击 and split
   by cell-internal 换行, not commas or semicolons.
5. `Last Updated` and `SOURCES.updated_at` must use
   `YYYY-MM-DDTHH:MM:SS+08:00`.
6. Update the `INDEX` Sources row by `Source ID`, then update `SOURCES`:
   `source_page`, `compiled_into`, `compile_status`, `audit_status`, and
   `review_state`.
7. Append a `LOG` compile event with a stable heading timestamp.

## Completion gate

1. Run:

   ```bash
   scripts/lark_wiki.sh wiki-structure-lint "$ROOT"
   ```

2. `INDEX` Page rows and real `wiki/*` directory children must be 双向完全一致.
   Missing real page rows or stale `INDEX` rows are failures.
3. Before coverage audit and structure lint both pass, use
   `SOURCES.compile_status=compiled_unverified`.
4. Use `compiled` only when key claims are integrated and audited. Use `audited`
   only when coverage audit is complete.
5. If full `wiki-health` is needed, read
   `references/workflows/lint-audit-drift.md`; full health is not a replacement
   for per-compile structure lint.

## Karpathy alignment

Karpathy-style compile means the LLM actually maintains the Wiki. The source can
touch 5-15 pages, update cross-links, record disagreements, and leave a better
knowledge system behind. A source summary alone is not enough.
