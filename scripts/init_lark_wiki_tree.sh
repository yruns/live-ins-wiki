#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lark_wiki.sh
source "$SCRIPT_DIR/lark_wiki.sh"

usage() {
  cat <<'USAGE'
用法:
  scripts/init_lark_wiki_tree.sh WIKI_DOC_NODE_URL_OR_TOKEN [ROOT_TITLE]

作用:
  输入一个已有大知识库中的文档节点，自动解析 space_id 和 node_token，
  然后在该节点下面创建 LLM Wiki 子树。
  如果用户指定的节点本身就是 LLM Wiki 根节点，请改用:
    scripts/lark_wiki.sh wiki-bootstrap-root WIKI_ROOT_NODE_URL_OR_TOKEN [ROOT_TITLE]

要求:
  - 参数必须是 /wiki/ 节点 URL 或 wiki node_token，不能是普通 docx URL。
  - 节点必须是文档型 Wiki 节点，obj_type 为 docx 或 doc。
  - 不会在知识空间根部创建入口，也不会创建独立知识库空间。
  - 如果父节点下已经存在同名入口，默认直接返回已有入口并退出 0。
  - 初始化会创建 AGENTS.md、INDEX、LOG、SOURCES、raw/docs、raw/articles、
    raw/repos、raw/meetings、raw/assets、raw/extracts、raw/manifests、
    wiki/sources、wiki/entities、wiki/concepts、wiki/comparisons、
    wiki/overviews、wiki/decisions、wiki/syntheses、wiki/disputed、wiki/audits。

环境变量:
  LLM_WIKI_ROOT_TITLE=LLM Wiki   默认入口标题。
  LARK_WIKI_DRY_RUN=1            仅打印 API 请求，不执行创建。
  LARK_WIKI_AS=user|bot          lark-cli 身份，默认 user。
  LARK_LLM_WIKI_HOME=~/.lark-llm-wiki  最近访问知识库 registry 目录。

示例:
  scripts/init_lark_wiki_tree.sh https://bytedance.larkoffice.com/wiki/IV2OwKLMsiTcRjkA4rHcFViUn4d
  scripts/init_lark_wiki_tree.sh https://bytedance.larkoffice.com/wiki/IV2OwKLMsiTcRjkA4rHcFViUn4d "营收 LLM Wiki"
USAGE
}

die() {
  printf '错误: %s\n' "$*" >&2
  exit 2
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

target="${1:-}"
root_title="${2:-${LLM_WIKI_ROOT_TITLE:-LLM Wiki}}"
dry_run="${LARK_WIKI_DRY_RUN:-}"

[[ -n "$target" ]] || {
  usage >&2
  exit 2
}
if [[ "$target" == http* && "$target" != *"/wiki/"* ]]; then
  die "参数必须是 /wiki/ 节点 URL；不能传普通 doc/docx/sheets/drive URL: $target"
fi

_lw_need jq
_lw_need lark-cli

lw_wiki_check_write_auth >/dev/null

resolved="$(lw_wiki_get_node "$target")"
code="$(printf '%s\n' "$resolved" | jq -r '.code // empty')"
[[ "$code" == "0" ]] || die "无法解析 Wiki 节点: $target"

space_id="$(printf '%s\n' "$resolved" | jq -r '.data.node.space_id // .node.space_id // empty')"
node_token="$(printf '%s\n' "$resolved" | jq -r '.data.node.node_token // .node.node_token // empty')"
node_type="$(printf '%s\n' "$resolved" | jq -r '.data.node.node_type // .node.node_type // empty')"
obj_type="$(printf '%s\n' "$resolved" | jq -r '.data.node.obj_type // .node.obj_type // empty')"
parent_title="$(printf '%s\n' "$resolved" | jq -r '.data.node.title // .node.title // empty')"
parent_url="$(printf 'https://bytedance.larkoffice.com/wiki/%s' "$node_token")"

[[ -n "$space_id" ]] || die "解析结果缺少 space_id"
[[ -n "$node_token" ]] || die "解析结果缺少 node_token"
[[ "$obj_type" == "docx" || "$obj_type" == "doc" ]] || die "父节点必须是文档型 Wiki 节点，当前 obj_type=$obj_type"

if [[ "$node_type" != "origin" ]]; then
  die "父节点必须是 origin Wiki 节点，当前 node_type=$node_type；请传入真实文档节点，不要传快捷方式节点"
fi

printf '目标父节点: %s\n' "${parent_title:-$node_token}" >&2
printf '父节点 URL: %s\n' "$parent_url" >&2
printf 'space_id: %s\n' "$space_id" >&2
printf '将创建入口: %s\n' "$root_title" >&2

if [[ "$dry_run" == "1" || "$dry_run" == "true" ]]; then
  jq -n \
    --arg space_id "$space_id" \
    --arg parent_node_token "$node_token" \
    --arg parent_title "$parent_title" \
    --arg root_title "$root_title" '
    {
      dry_run: true,
      space_id: $space_id,
      parent_node_token: $parent_node_token,
      parent_title: $parent_title,
      root_title: $root_title,
      planned_tree: [
        ($root_title + "/AGENTS.md"),
        ($root_title + "/INDEX"),
        ($root_title + "/LOG"),
        ($root_title + "/SOURCES"),
        ($root_title + "/raw/docs"),
        ($root_title + "/raw/articles"),
        ($root_title + "/raw/repos"),
        ($root_title + "/raw/meetings"),
        ($root_title + "/raw/assets"),
        ($root_title + "/raw/extracts"),
        ($root_title + "/raw/manifests"),
        ($root_title + "/wiki/sources"),
        ($root_title + "/wiki/entities"),
        ($root_title + "/wiki/concepts"),
        ($root_title + "/wiki/comparisons"),
        ($root_title + "/wiki/overviews"),
        ($root_title + "/wiki/decisions"),
        ($root_title + "/wiki/syntheses"),
        ($root_title + "/wiki/disputed"),
        ($root_title + "/wiki/audits")
      ]
    }
  '
  exit 0
fi

existing="$(lw_wiki_list_children "$space_id" "$node_token" 50 | jq -r --arg title "$root_title" '
  (.data.items // [])
  | map(select(.title == $title))
  | first
  | if . then {title, node_token, url, space_id, parent_node_token} else empty end
')"
if [[ -n "$existing" ]]; then
  printf '已存在同名 LLM Wiki 入口，跳过创建:\n' >&2
  existing_url="$(printf '%s\n' "$existing" | jq -r '.url // empty')"
  if [[ -n "$existing_url" ]]; then
    lw_wiki_registry_record "$existing_url" "$root_title" >/dev/null || true
  fi
  printf '%s\n' "$existing"
  exit 0
fi

lw_wiki_init_tree "$space_id" "$root_title" "$node_token"
