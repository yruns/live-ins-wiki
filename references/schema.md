# Lark LLM Wiki Schema

这个 schema 描述 Lark-native LLM Wiki 的默认目录、页面类型、元数据、引用和建页规则。目标 Wiki 初始化后，应把这些规则写入目标 Wiki 的 `AGENTS.md`，让它成为该 Wiki 的 runtime schema。

## 节点树

所有条目都是真实 Lark Wiki 节点：

```text
AGENTS.md
INDEX
LOG
SOURCES
raw/
  docs/
  articles/
  repos/
  meetings/
  assets/
  extracts/
  manifests/
wiki/
  sources/
  entities/
  concepts/
  comparisons/
  overviews/
  decisions/
  syntheses/
  disputed/
  audits/
```

不要把 requirements 作为默认 raw 子目录。产品或工程场景确实需要时，把它作为用户确认后的 domain extension，而不是默认 schema。

## 页面类型

- `source`：单个来源的摘要、key claims、实体、概念、更新记录和 coverage audit。
- `entity`：产品、服务、模块、人员、表、API、系统等稳定对象。
- `concept`：术语、规则、原则、模式、不变量。
- `comparison`：多对象或多方案对比。
- `overview`：跨三个及以上来源的主题概览。
- `decision`：ADR 风格决策和取舍记录。
- `synthesis`：由 query 产生、可复用的多来源回答。
- `disputed`：互相冲突或需要人工确认的 claims。
- `audit`：source coverage、引用完整性、健康检查或 lint 结果。

## YAML frontmatter

所有 `wiki/` 下的生成页都使用 YAML frontmatter，不使用 blockquote metadata。

```markdown
---
type: concept
slug: concepts/<stable-slug>
title: ""
aliases: []
status: draft              # staged | extracted | draft | compiled | reviewed | locked | deprecated
review_state: unreviewed   # unreviewed | reviewed | needs-human-review
last_compiled: "YYYY-MM-DDTHH:MM:SS+08:00"
last_verified: null
source_refs:
  - source_id: SRC-YYYY-MM-DD-001
    raw_node: ""
    source_page: ""
    claim_ids: []
confidence: medium         # low | medium | high
contradiction_state: none  # none | disputed | superseded
related_pages: []
---
```

`source_refs` 必须是复数。概念页、实体页、综述页和决策页通常来自多个 source，不能只保留最后一个来源。

## Source ID

推荐格式：

```text
SRC-YYYY-MM-DD-001
```

同一天重复导入时递增尾号。脚本可以生成候选 ID，最终以 `SOURCES` manifest 中的唯一记录为准。

## SOURCES manifest

`SOURCES` 是可解析的 source manifest，按表格维护：

```markdown
| source_id | title | kind | raw_node | origin | imported_at | updated_at | checksum | extraction | source_page | compiled_into | compile_status | audit_status | review_state |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
```

`imported_at` 是不可变的首次导入时间；后续 stage / compile / audit / drift 更新只改 `updated_at` 和对应状态字段。

状态含义：

- `staged`：来源已进入 `raw`，还没有可用抽取或 source page。
- `extracted`：本地文件或复杂来源已抽取文本，仍未完成跨页编译。
- `compiled`：关键 claims 已进入相关 `wiki/` 页。
- `compiled_unverified`：页面已更新，但 coverage audit 未完成，不能当作完成状态。
- `audited`：完成 coverage audit。
- `drifted`：raw source 与 manifest 中的 checksum、导出文本或修改时间不一致。
- `deprecated`：来源不再作为当前事实依据，但不能删除历史记录。

Drift 字段建议：

- 本地文件：`sha256(file bytes)`、`sha256(extracted text)`、`extractor`。
- Lark doc/wiki：`node_token`、`obj_token`、可获得时记录修改时间或导出文本 checksum。
- Drift 后依赖页面标记 `needs_reverification`，不要直接覆盖 reviewed claims。

## 引用规则

事实性段落必须有 `source_refs` 支撑。回答用户时优先引用 compiled page；如果 compiled page 缺少证据，再回退 raw。

推荐 claim 表：

```markdown
## Atomic Claims

| Claim ID | Claim | Source refs | Confidence | Notes |
|---|---|---|---|---|
| C1 | ... | SRC-2026-05-24-001 | high | Directly stated |
```

自然语言段落中的引用格式：

```markdown
[source: SRC-2026-05-24-001, claim: C1]
[source: SRC-2026-05-24-002, raw: raw/docs/<title>]
```

如果某句话是 LLM 综合推断，标记为 inference，并列出支撑来源。

## 命名、别名和合并

- Metadata 中使用稳定 `slug`，建议 lower-kebab-case，例如 `concepts/agentic-coding`。
- Lark 页面标题可以是中文或自然语言，但同一 slug 只能有一个 canonical page。
- 每页维护 `aliases`。
- 建页前先查 `INDEX`、`SOURCES` 和 aliases；存在近似页面时更新旧页，不重复创建。
- 合并 reviewed / locked 页面前，先给出 merge plan 并征求用户确认。
- 内部链接使用 Markdown 链接指向 Lark 节点 URL，同时保留 slug：
  ```markdown
  [Concept: Agentic Coding](https://.../wiki/...)
  ```

## 建页阈值

`entity` 页只在满足任一条件时创建：

- 它是至少两个来源的核心对象。
- 它经常出现在用户问题里。
- 它参与 comparison、decision 或 disputed claim。
- 用户明确要求追踪。

`concept` 页只在满足任一条件时创建：

- 它出现在至少两个来源。
- 它是解释 decision、comparison、overview 的必要概念。
- 它是用户定义的领域基础术语。

Passing mention 不建页，放在 source page 的 `Mentioned but not tracked`。

## Disputed

冲突是一等信息。不要静默覆盖旧结论。

```markdown
## Disputed Claims

| Claim | Existing support | New conflicting support | Conflict type | Current resolution | Needs human review |
|---|---|---|---|---|---|
```

冲突类型可用：`date mismatch`、`definition mismatch`、`metric mismatch`、`policy mismatch`、`factual contradiction`、`source reliability`。

## 导出兼容

虽然存储在 Lark Wiki 中，所有页面仍应尽量保持 Markdown export compatible：

- YAML frontmatter 可被导出保留。
- Lark node URL 是物理链接；slug 是逻辑链接。
- `INDEX`、`LOG`、`SOURCES` 使用稳定 Markdown 表格或小节格式，便于脚本和 LLM 读取。

## Graph / Backlink

Lark 版没有 Obsidian graph，但仍要维护逻辑图：

- `source_refs` 形成 source -> page 的 support edge。
- Markdown 链接形成 page -> page 的 relation edge。
- `related_pages` 形成显式 cross-link。
- Health / lint 应报告 orphan pages、broken links、重复 aliases / slugs、提及频繁但未建页的概念。
- 不因为 broken link 自动创建页面；先报告修 link、合并、删除或建页选项。
