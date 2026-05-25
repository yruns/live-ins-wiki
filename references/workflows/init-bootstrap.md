# Init, Bootstrap, And Target Selection

## When to read

Read this for initialization, bootstrap, recent-Wiki selection, write-target
confirmation, or any request that mentions an existing Lark/Feishu Wiki root.
This workflow keeps the Karpathy-style Wiki as a real node tree instead of a
single aggregation document.

## Workflow

1. Confirm the target is a real `/wiki/` document node supplied by the user or
   selected from registry with the write-safety rules below. It must not be a
   normal doc URL and must not be an implicit example from chat history.
2. Initialization has exactly one default path: bootstrap the user-specified
   node itself. Run:

   ```bash
   scripts/lark_wiki.sh wiki-bootstrap-root WIKI_ROOT_NODE_URL_OR_TOKEN [ROOT_TITLE]
   ```

   初始化只有一个操作路径：do not create an extra `LLM Wiki` child unless the
   user explicitly asks for a nested entry.
3. Before bootstrap, inspect the root layer. If it contains only zero children
   or standard children, continue. Standard children are:
   `AGENTS.md`, `INDEX`, `LOG`, `SOURCES`, `raw`, and `wiki`.
4. If 非标准子节点 / non-standard children exist, stop. List them and
   询问用户是否删除或移动. Do not mix business documents and the Wiki operating
   schema at the root.
5. Bootstrap creates or confirms this full node tree:

   ```text
   AGENTS.md
   INDEX
   LOG
   SOURCES
   raw/docs
   raw/articles
   raw/repos
   raw/meetings
   raw/assets
   raw/extracts
   raw/manifests
   wiki/sources
   wiki/entities
   wiki/concepts
   wiki/comparisons
   wiki/overviews
   wiki/decisions
   wiki/syntheses
   wiki/disputed
   wiki/audits
   ```

6. New or rebuilt `INDEX` and `SOURCES` must be Feishu spreadsheet nodes. Legacy
   doc tables are fallback only.
7. After successful bootstrap, record root URL, name, `space_id`, and root node
   in `~/.lark-llm-wiki/registry.json`.
8. 初始化后不要运行 `wiki-health`. Use script success plus
   轻量 `wiki-structure-lint` if verification is needed. 不要默认运行完整 `wiki-health`;
   只有用户明确提出 health、完整健康检查或复杂诊断时才运行。

## Target selection rules

1. Read-only operations may use registry current or a unique registry name after
   stating which Wiki was selected.
2. Write operations need a root/name/`@current` in the current user request, or
   an explicit confirmation of the registry current target and planned writes.
3. If registry is empty, current is missing, or a name matches multiple Wikis,
   ask for the target before reading or writing.
4. A successful root resolution may update the registry; this is operational
   state, not semantic Wiki content.

## Failure handling

- Missing Wiki permissions: run `scripts/lark_wiki.sh wiki-auth-write` and ask
  the user to complete auth.
- Dirty root: stop before creation and ask what to move/delete.
- Partial bootstrap: rerun `wiki-bootstrap-root`; standard sheet repair is
  designed to be idempotent.
- Full health is slow or hanging: stop it and switch to targeted checks such as
  root stat, `SOURCES` lint, `INDEX` row, and selected compiled page reads.
