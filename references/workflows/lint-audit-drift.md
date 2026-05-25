# Lint, Audit, Repair, Graph, And Drift

## When to read

Read this for `wiki-structure-lint`, `wiki-health`, coverage audit, semantic
lint, repair planning, graph/backlink audit, source drift, and stalled or
inconsistent Wiki states. These workflows keep the Karpathy-style Wiki healthy
without turning every ingest into heavy governance.

## Workflow

1. Pick the lightest check that can answer the question.
2. For every compile, run structure lint. 每次 Compile 后必须运行:

   ```bash
   scripts/lark_wiki.sh wiki-structure-lint "$ROOT"
   ```

3. Use full `wiki-health` only when the user asks for health, full diagnosis, or
   a broad integrity check. 完整 `wiki-health` is heavier and reads more nodes.
4. Use semantic lint when the issue requires LLM judgment: contradictions, stale
   claims, weak citations, orphan concepts, or missing cross-links.
5. Use coverage audit to decide whether a source's key claims actually entered
   compiled pages.
6. Use drift audit when raw source hashes, exported text, or source metadata may
   have changed.

## Structure lint

`wiki-structure-lint` is a deterministic fast gate:

1. Read `INDEX` spreadsheet sheets/sections.
2. List real `wiki/*` child nodes.
3. Compare `INDEX.Page` canonical plain paths with real pages.
4. Fail if `INDEX` has a stale page.
5. Fail if a real page is missing from `INDEX`.
6. Require 双向完全一致 before marking a compile as `compiled`.

Structure lint does not inspect semantic truth, claim quality, or source drift.

## Health

Use health only when warranted. It checks:

- standard node tree exists;
- `SOURCES`, `INDEX`, and `LOG` are readable;
- `raw` sources have manifest rows;
- compiled pages have YAML frontmatter and `source_refs`;
- empty/stub/duplicate pages;
- `SOURCES.compile_status=compiled` without audit support;
- escaped pipes and Lark table exports through parsers, not grep.

If health hangs on Lark document reads, stop it and switch to targeted checks:
root stat, `SOURCES` manifest lint, target source status, `INDEX` row, and
selected page reads. Do not leave a health process running.

## Coverage audit

Coverage audit asks whether a staged/extracted source truly became compiled
knowledge.

1. Read the source page and raw/extraction material.
2. List the important claims.
3. For each claim, classify:
   - included in compiled pages;
   - excluded with reason;
   - partial;
   - disputed;
   - needs human review.
4. Check whether target pages have `source_refs`.
5. Create or update `wiki/audits/<source-id>-coverage` when useful.
6. Update `SOURCES.audit_status` and keep `compile_status=compiled_unverified`
   until audit is complete.

## Semantic lint and repair

`lw_wiki_lint_plan ROOT` gives an LLM lint package. The output must not be only a
report. It must include:

- observations;
- proposed repairs;
- pages to update;
- refs to add/remove;
- disputes to create/update;
- items requiring human approval.

Repair rules:

1. Do not delete or overwrite reviewed/locked content without a plan.
2. Prefer adding source support, clarifying scope, or moving conflict to
   `wiki/disputed` over silently replacing claims.
3. If a high-frequency entity/concept lacks a page, propose the page and source
   support before creating it.
4. If a page is too long, propose a split with backlinks and redirects.
5. After applying repairs that affect real pages, update `INDEX`, append `LOG`,
   and run structure lint.

## Graph / backlink audit

Graph audit checks whether the Wiki remains navigable:

- orphan pages;
- broken internal links;
- duplicate aliases/slugs;
- pages with zero outbound links;
- frequently mentioned entities/concepts without canonical pages;
- support edges from `source_refs`;
- missing backlinks between concept/entity/overview pages.

Do not create pages automatically from broken links. First propose repair:
rename, merge, delete link, create page, or add alias.

## Source drift

Drift audit checks whether raw source state has changed:

- local file `sha256(file bytes)`;
- local extracted text hash;
- Lark node token / obj token;
- available modified timestamp;
- exported text checksum.

When drift is detected:

1. Mark source as `drifted`.
2. Mark dependent compiled pages `needs_reverification`.
3. Append a `LOG` drift event.
4. Recompile with `references/workflows/compile.md`.
5. Do not directly overwrite reviewed claims.

## Karpathy alignment

Lint exists to make the Wiki better: add missing links, repair stale claims,
move conflicts into disputed pages, and keep query answers reliable. It should
not become paperwork that prevents the LLM from maintaining the knowledge layer.
