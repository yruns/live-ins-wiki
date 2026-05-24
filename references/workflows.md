# Lark LLM Wiki 工作流

## Init

1. 用 `lw_wiki_check_write_auth` 检查 Wiki 写权限；缺失时用 `lw_wiki_auth_write` 授权。
2. 如果请求里没有明确目标大知识库、父节点和项目入口，先让用户确认。
3. 新建树时优先运行 `scripts/init_lark_wiki_tree.sh WIKI_DOC_NODE_URL ROOT_TITLE`，其中 `WIKI_DOC_NODE_URL` 必须是已有大知识库里的文档节点。
4. 底层命令是 `lw_wiki_init_tree SPACE_ID ROOT_TITLE PARENT_NODE_TOKEN`，但 `SPACE_ID` 和 `PARENT_NODE_TOKEN` 应由脚本从文档节点解析出来，不要手写猜测。
5. 不要创建独立知识库空间，不要在知识空间根部创建无父节点入口。
6. 把项目入口节点和分类节点 token 记录在项目笔记或环境变量里，不要写进通用 skill。

## Import

1. 用 `lw_search` 或用户提供的 URL 定位来源文档。
2. 调用任何创建、移动或快捷方式 API 前，先确认目标大知识库、项目入口和 raw 分类父节点。
3. 对已经是 Wiki 页面或普通 `docx/doc` 的来源，用 `lw_wiki_add_source_shortcut` 在 `raw/...` 下创建快捷方式。
4. 不要创建一个塞满链接的单文档索引；也不要默认移动普通文档。只有用户明确要求移动时，才用 `lw_wiki_move_doc_to_wiki`。
5. 对本地文件，优先用 `lw_wiki_import_local_file LLM_WIKI_ROOT_URL FILE assets` 串联上传原件、创建 raw 快捷方式、抽取文本、生成 `wiki/sources` 编译页并登记索引；如果拆成原子步骤，先确认上传位置，用 `lw_upload_file FILE DRIVE_FOLDER_TOKEN` 上传原始文件，再用 `lw_extract_local FILE OUTPUT.md` 抽取内容。
6. 对外部页面，先 webclip 或转换到 Lark，再作为真实节点或经过批准的导入项放入 Wiki 树。
7. 在 `INDEX` 或 raw manifest 节点中登记导入的来源、上传文件 token 和解析产物位置。

## Compile

1. Compile 是 LLM 语义工作，不是脚本索引。先读 `INDEX` 和相关 `wiki/*`，再读 raw 来源。
2. 本地文件来源使用上传后的 raw 文件和解析出的 Markdown；如果只有本地路径、没有上传记录，先停止并上传原始文件。
3. 识别来源类型、领域、实体、概念、决策、冲突和可复用问题。
4. 新建或更新任何编译页面前，先确认目标项目入口或具体父节点。
5. 用 `lw_wiki_create_node` 和 `lw_write` 在 `wiki/...` 下创建或更新 `Source`、`Entity`、`Concept`、`Comparison`、`Overview` 或 `Decision` 页面。一个来源可以更新多个页面。
6. 更新 `INDEX` 的页面链接、一句话摘要、来源和日期。
7. 追加一条 `LOG`。
8. 任何破坏性改写前，先给出 diff 风格摘要；冲突写入 `Disputed`，不要静默选择一边。

## Local Files

1. 适用类型：`.pdf`、`.csv`、`.tsv`、`.md`、`.txt`、`.docx`、`.pptx`、`.xlsx`，以及系统工具可转换的 `.doc` / `.ppt`。
2. 必须先上传原始文件到用户指定 Lark 位置，或通过 `lw_wiki_import_local_file` 上传后在 `raw/assets` 创建快捷方式；上传失败时不要继续写入 Wiki。
3. 解析优先使用 `scripts/extract_local_file.py`；必要时可调用更专业的本地工具，例如 PDF OCR、表格脚本、文档/幻灯片解析器。
4. 解析结果是编译输入，不等同于最终知识页；agent 还需要提炼事实、实体、概念、决策和冲突，再写入 `wiki/...`。
5. 编译页的 `source` 字段同时记录上传后的 Lark 文件和本地解析产物，方便追溯。

## Query

1. 首选 `lw_wiki_query LLM_WIKI_ROOT_URL "问题" 30 12000`。这个命令只生成上下文包：`INDEX`、近期 `LOG`、wiki catalog、编译页正文、raw catalog。
2. 由 LLM 阅读上下文包并选择相关页面；不要在脚本里写一套 Python/正则/BM25 规则替代 LLM 判断。
3. 当编译页覆盖不足时，再从 raw catalog 中选择少量原始来源调用 `lw_cat` 读取。本地上传文件应优先通过对应 `wiki/sources` 编译页命中。
4. 用有来源依据的结论回答，并附 Lark 页面引用。回答要区分“编译页结论”和“raw 原文片段”。
5. 如果回答形成可复用沉淀，除非用户已经要求持久化，否则先询问是否写回。

## Lint

1. 读取 `INDEX`、`LOG`、wiki catalog 和关键 `wiki/*` 页面。
2. 由 LLM 做语义健康检查：矛盾结论、过期声明、孤儿页、缺失交叉引用、重要概念没有页面、低置信度页面、raw 来源漂移、数据缺口和下一步来源建议。
3. 结构检查可以用 `lw_wiki_list_children` 辅助，但它不是主要判断层。
4. 先报告错误，再报告警告，最后给建议。不自动删除。只有用户要求时才写入。
