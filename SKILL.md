---
name: llm-wiki-lark
description: 当用户要创建、维护、导入、查询或检查一个基于真实 Lark/飞书知识库节点树的 LLM Wiki 时使用，包括 Lark docs/wiki、本地 PDF/CSV/Markdown/Office 文件、来源快捷方式、编译知识页和 lark-cli 类文件操作封装。
metadata:
  requires:
    bins: ["lark-cli", "jq", "python3"]
---

# Lark LLM Wiki

使用本 skill 维护一个存放在 Lark/飞书知识库目录树中的 LLM Wiki。它不是本地文件夹，也不是一个聚合所有链接的单独文档，也不是随意新建的独立知识库空间。

## 核心思想

把 Lark Wiki 节点当成文件和目录来操作：

- `raw/` 存来源材料；当来源本身已经是 Wiki 节点时，使用 Wiki 快捷方式挂载。
- `wiki/` 存 agent 编译后的知识页面。
- `INDEX` 是可导航的内容索引。
- `LOG` 是追加式变更记录。
- `AGENTS.md` 是结构约定和操作契约。

agent 应该在导入时完成知识编译，而不是每次查询都重新发现所有信息。

唯一合法产物是真实的 Wiki 节点树。把多个文档链接塞进一个 Lark 文档，不算 Lark LLM Wiki。

在创建、导入、移动或创建快捷方式之前，必须确认目标属于哪个 Wiki。如果用户当前请求没有明确目标 Wiki space、根节点或父节点，先询问目标 Wiki；不要根据示例、最近命令或个人默认空间推断。

新建的 LLM Wiki 项目必须挂在某个已有的大知识库节点下面，以“文件 / 子文件”的形式展开。不能随意创建独立知识库空间，也不要在知识空间根部创建无父节点的入口。

新增来源通常分两类处理：

- Lark docs 或 Wiki：先解析 URL。Wiki 来源和普通 `docx/doc` 来源都优先以 Wiki 快捷方式挂到 `raw/...`；只有用户明确要求“移动进 Wiki”时才使用移动接口。
- 本地文件：先把原始文件上传到用户指定的 Lark 位置，再用本地工具或脚本解析文件内容，并把解析结果编译到 `wiki/...`。不要只上传文件而不解析，也不要只解析本地文件而不保存原始文件。

## 初始化

1. 确认认证状态：
   ```bash
   scripts/lark_wiki.sh auth
   ```
2. 加载 helper 函数：
   ```bash
   # 需要在 bash 中 source；直接命令模式可用 ./scripts/lark_wiki.sh、bash scripts/lark_wiki.sh，或 sh/zsh 入口自动转 bash。
   source scripts/lark_wiki.sh
   ```
3. 新建 Wiki 前，按需读取 `references/schema.md` 和 `references/workflows.md`。
4. 初始化结构优先使用专用脚本，参数必须是已有知识库里的 Wiki 文档节点：
   ```bash
   scripts/init_lark_wiki_tree.sh "$WIKI_DOC_NODE_URL" "LLM Wiki"
   ```

## Helper 函数

包装脚本在 `lark-cli` 之上提供类本地文件操作：

```bash
lw_search "query" 10
lw_stat "$DOC_OR_WIKI_URL"
lw_cat "$DOC_OR_WIKI_URL"
lw_export "$DOC_OR_WIKI_URL" /tmp/page.md
lw_write "$DOC_OR_WIKI_URL" page.md
lw_append "$DOC_OR_WIKI_URL" page.md
lw_replace_section "$DOC_OR_WIKI_URL" "## Section" section.md
lw_wiki_check_write_auth
scripts/init_lark_wiki_tree.sh "$WIKI_DOC_NODE_URL" "团队 LLM Wiki"
lw_wiki_init_tree "$SPACE_ID" "团队 LLM Wiki" "$CONFIRMED_PARENT_NODE_TOKEN"
lw_wiki_list_children "$SPACE_ID" "$PARENT_NODE_TOKEN"
lw_wiki_create_node "$SPACE_ID" "$CONFIRMED_PARENT_NODE_TOKEN" "Concept: 检索" page.md
lw_wiki_add_source_shortcut "$SPACE_ID" "$RAW_PARENT_NODE" "$SOURCE_WIKI_URL"
lw_wiki_query "$LLM_WIKI_ROOT_URL" "GLUP 是什么" 30 12000
lw_wiki_import_doc_shortcut "$LLM_WIKI_ROOT_URL" "$SOURCE_DOC_OR_WIKI_URL" docs
lw_wiki_create_shortcut "$SPACE_ID" "$RAW_PARENT_NODE" "$ORIGIN_NODE_TOKEN" docx "来源标题"
lw_wiki_import_local_file "$LLM_WIKI_ROOT_URL" ./report.pdf assets
lw_upload_file ./report.pdf "$DRIVE_FOLDER_TOKEN"
lw_extract_local ./report.pdf /tmp/report.md
lw_prepare_local_source ./report.pdf "$DRIVE_FOLDER_TOKEN" /tmp/report.md
lw_log_entry INGEST "wiki/concepts/foo" "新增有来源支撑的定义"
```

输入可能是 `/wiki/` URL 时，用 `lw_resolve` 解析。它会把 Wiki 节点解析到背后的 `obj_token` 和类型，再进行文档读写。

Wiki 写操作需要 `wiki:wiki` 或 `wiki:node:create` 之一。如果缺失，停止操作并运行 `lw_wiki_auth_write`；不要退化成普通 Lark 文档。

本地文件解析由 `scripts/extract_local_file.py` 执行，支持常见的 `.pdf`、`.csv`、`.tsv`、`.md`、`.txt`、`.docx`、`.pptx`、`.xlsx`、`.json`，以及系统工具可转换的 `.doc` / `.ppt`。复杂文件可改用更专业的本地命令，但仍必须先上传原始文件。

## 标准流程

### Init

在用户确认过的“大知识库父节点”下面创建项目入口节点，然后在该入口节点下建立这棵子树：

```text
<root>/
  AGENTS.md
  INDEX
  LOG
  raw/
    articles/
    docs/
    repos/
    meetings/
    assets/
  wiki/
    sources/
    entities/
    concepts/
    comparisons/
    overviews/
    decisions/
```

全新建树时优先使用 `scripts/init_lark_wiki_tree.sh WIKI_DOC_NODE_URL ROOT_TITLE`。它会先解析文档节点并拿到 `space_id` / `node_token`，再调用底层 `lw_wiki_init_tree SPACE_ID ROOT_TITLE CONFIRMED_PARENT_NODE_TOKEN`。页面分类和元数据块参考 `references/schema.md`。

### Import

先确认目标 Wiki 和 `raw` 分类父节点；目标不清楚时，先问用户，再调用任何写 API。

优先使用 Lark 原生引用：

- 已存在的 Wiki 页面：用 `lw_wiki_add_source_shortcut` 在 `raw/...` 下创建快捷方式。
- 普通 `docx/doc` URL：同样用 `lw_wiki_add_source_shortcut` 在 `raw/...` 下创建 Wiki 快捷方式，不要用单文档链接表伪装。
- 移动云文档进 Wiki 只在用户明确要求时使用 `lw_wiki_move_doc_to_wiki`；这会改变文档所在位置，不能作为默认导入方式。
- 本地文件：优先用 `lw_wiki_import_local_file "$LLM_WIKI_ROOT_URL" FILE assets` 串联上传原件、创建 `raw/...` 快捷方式、抽取文本、生成 `wiki/sources/...` 编译页并更新索引；若要拆成原子步骤，必须先上传原始文件到用户指定的 Lark Drive 文件夹或约定的 raw 文件位置，再运行 `lw_extract_local` 或其他本地工具解析内容，最后把解析出的 Markdown 编译到 `wiki/...`。
- 外部网页：先 webclip 或转换到 Lark，再作为真实节点或经过批准的导入项放入 Wiki 树。

### Compile

Import 只负责把 raw 来源放进真实 Lark Wiki 树；Compile 才是 LLM Wiki 的核心。LLM 要读取 raw 来源，把新信息整合进已有 `wiki/`，而不是只写一个摘要或只建立检索索引。

1. 先读 `INDEX` 和相关 `wiki/*` 页面，理解已有实体、概念、对比、综述和决策。
2. 读取 raw 来源；本地文件用上传后的 raw 文件和本地抽取文本作为来源。
3. 由 LLM 判断要更新哪些页面：一个来源可能更新 `wiki/sources`、多个 `wiki/entities`、`wiki/concepts`、`wiki/comparisons` 或 `wiki/overviews`。
4. 明确标出新增事实、扩展已有页面、与旧结论冲突的地方；冲突写入 `Disputed`，不要静默选择一边。
5. 更新 `INDEX` 中页面的一句话摘要、来源和日期；追加 `LOG`。
6. 如果生成内容会覆盖已 review 或 locked 的页面，暂停并请求批准。

### Recall / Query

不要把 `lw_wiki_query` 当成 RAG 召回器。它只生成给 LLM 阅读的上下文包，不做规则打分、不替 LLM 判断相关性。

1. 运行 `lw_wiki_query "$LLM_WIKI_ROOT_URL" "问题" 30 12000` 收集上下文包：`INDEX`、近期 `LOG`、wiki catalog、编译页正文和 raw catalog。
2. LLM 先读 `INDEX` 和 `wiki/*` 编译页，自行判断哪些页面回答问题；如果编译层覆盖不足，再从 raw catalog 选择少量原始来源读取。
3. 回答用户时优先引用编译页；引用 raw 来源时说明这是回退核对。
4. 如果答案形成了新的对比、分析或可复用结论，应建议或按用户要求写回 `wiki/comparisons`、`wiki/overviews`、`wiki/concepts` 或 `wiki/decisions`，让查询也能反哺知识库。

### Lint

Lint 也应由 LLM 执行语义判断，而不是只跑结构规则。检查 `INDEX` 一致性、来源可访问性、元数据、重复概念、孤儿页面、缺失交叉引用、过期结论、未解决冲突、raw 来源漂移和应该新增的问题/来源。删除只作为建议提出，不自动执行。

## 安全规则

- 不能隐式选择目标 Wiki。新增文档、创建页面、导入来源、移动文档或创建快捷方式前，必须向用户确认目标 Wiki space、父节点和项目入口。
- 不能随意创建独立知识库。LLM Wiki 必须挂在已有大知识库节点下，以文件 / 子文件形式展开。
- 不能直接把 `/wiki/` token 当 doc token 用，必须先解析。
- 导入时不能覆盖 raw 来源。
- 不能用一个文档加链接来代表 Wiki；必须保留节点树。
- 普通文档默认以 Wiki 快捷方式导入；移动进 Wiki 前必须获得用户明确批准。
- 本地文件导入必须保留原始文件：先上传到用户指定 Lark 位置，再解析并编译进知识库。
- 生成事实必须有来源支撑。
- 遇到冲突时显式标记，不要静默选择一边。
- 个人或团队文档默认使用 `--as user`，除非用户要求 bot 资产。
- 破坏性写入前展示简短写入计划：目标页面、写入模式和原因。
