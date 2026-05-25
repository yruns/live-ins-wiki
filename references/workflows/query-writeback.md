# Query And Writeback

## When to read

Read this for questions over the Wiki, selective recall, answer synthesis, raw
fallback, and writing useful answers back into the Wiki. This is the Karpathy
loop where querying also improves the knowledge base.

## Workflow

1. Resolve the target Wiki. Read-only query may use registry current after
   stating it; writeback follows the write-target confirmation rule in
   `references/workflows/init-bootstrap.md`.
2. Run:

   ```bash
   scripts/lark_wiki.sh wiki-query-plan "$ROOT" "question"
   ```

3. Read the returned `INDEX`, `SOURCES`, recent `LOG`, and page catalog. Query is
   index-first selective reading, not top-N chunk stuffing.
4. Choose a small set of likely compiled pages and read them:

   ```bash
   scripts/lark_wiki.sh wiki-read-pages "$PAGE_OR_NODE_URL" "$ANOTHER_PAGE"
   ```

5. If compiled pages lack evidence, choose a small number of raw sources and
   read them with:

   ```bash
   scripts/lark_wiki.sh wiki-read-raw "$RAW_SOURCE_URL"
   ```

6. If a fetched page contains embedded `<sheet token=...>` placeholders, ensure
   sheet contents are expanded before relying on the table.
7. Answer with compiled pages first. If raw fallback is used, say so and treat it
   as a signal that the Wiki may need compile/writeback.

## Writeback decision

Write back when the answer has reuse value:

- `wiki/syntheses`: multi-source analytical answer.
- `wiki/comparisons`: side-by-side evaluation.
- `wiki/overviews`: durable topic overview.
- `wiki/decisions`: decision, tradeoff, or policy conclusion.
- existing concept/entity page: localized durable update.
- `wiki/disputed`: unresolved conflict surfaced during query.

Do not write back passing, one-off, or unsupported speculation.

## Writeback steps

1. Present a small mutation plan: target page, summary of content, source refs,
   `INDEX`/`LOG` rows, and whether any existing claim changes.
2. Write or update the page using normal page templates and `source_refs`.
3. Upsert the relevant `INDEX` row. For a synthesis/comparison/overview, set the
   correct sheet/section and source count.
4. Append a `LOG` query/writeback event.
5. If the answer exposed a compiled-page gap, either update the page immediately
   or mark a repair item in semantic lint.
6. Run `wiki-structure-lint` when writeback creates or deletes real `wiki/*`
   pages. For a narrow update to an existing page, structure lint is still
   recommended when `INDEX` changes.

## Karpathy alignment

In a Karpathy-style LLM Wiki, query is not a disposable chat over documents. A
high-quality answer should either prove the Wiki already knows the answer or
become a durable page so future answers start from stronger compiled knowledge.
