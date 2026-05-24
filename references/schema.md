# Lark LLM Wiki 结构

初始化或维护 Lark 版 LLM Wiki 时使用这个结构。它必须是真实的 Lark Wiki 节点树，不是单个文档里的标题层级，也不是随意新建的独立知识库空间。

## 核心目录

```text
AGENTS.md
INDEX
LOG
raw/
  requirements/
  meetings/
  articles/
  repos/
  assets/
wiki/
  sources/
  entities/
  concepts/
  comparisons/
  overviews/
  decisions/
```

上面的每一项都是 Wiki 节点。整棵树必须挂在已有大知识库的某个用户确认父节点下面，以文件 / 子文件形式展开。`raw/` 和 `wiki/` 这类分类名是父节点，用来形成可见的目录树。

## 页面类型

- `Source`：对一个 raw 文档或一组来源的编译摘要。
- `Entity`：产品、服务、模块、人员、表、API 或系统的稳定页面。
- `Concept`：规则、原则、模式、不变量或术语的稳定页面。
- `Comparison`：值得保存的对比型查询结果。
- `Overview`：综合三个及以上来源后值得保存的概览。
- `Decision`：ADR 风格决策页，包含背景、决策、备选方案和影响。

## 必需元数据块

每个生成的 wiki 页面顶部都放这个块：

```markdown
> type: source | entity | concept | comparison | overview | decision
> domain: <domain-or-cross>
> source: <mention-doc or source URL/token>
> last_compiled: YYYY-MM-DD
> confidence: high | medium | low
> review_state: draft | reviewed | locked
```

## 操作规则

- raw 页面是事实来源，导入和编译时不要覆盖 raw 内容。
- 不随意创建独立知识库空间；新项目入口必须是已有大知识库节点下的子节点。
- 已经是 Wiki 节点的来源页，应挂到 `raw/...` 下作为 Wiki 快捷方式。
- 普通 `docx/doc` 文档如果还不是 Wiki 节点，也应优先通过 Wiki 节点创建接口挂成快捷方式；移动进 Wiki 需要用户明确批准。
- 本地文件来源必须保留上传后的原始文件 token，并记录本地解析产物。编译页不能只引用本地路径。
- wiki 页面是编译产物，保持精炼，并保留来源依据。
- `INDEX` 是内容地图。新增或重命名页面时必须更新。
- `LOG` 只能追加。记录日期、操作类型、页面和简短摘要。
- 冲突是一等信息。把竞争性结论保留在 `Disputed` 小节，不要静默选择一边。
- 高价值查询输出应作为 `Comparison`、`Overview`、`Concept` 或 `Decision` 页面提出写回建议。

## Lint 检查

手动或定时运行检查。关注：

- 页面是否存在于 `INDEX`
- `INDEX` 目标是否仍可读取
- 生成页面是否有元数据
- 是否保留来源链接
- 是否存在孤儿 `Concept` / `Entity`
- 是否存在重复概念
- 来源修改时间是否过期，能获取时检查
- 低置信度结论是否缺少 review
- 是否有未解决的 `Disputed` 小节
