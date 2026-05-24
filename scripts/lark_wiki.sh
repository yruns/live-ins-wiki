#!/usr/bin/env bash

# 用类文件操作封装真实 Lark Wiki 节点树中的 LLM Wiki。
# 可以 source 后调用函数，也可以直接作为轻量命令行 wrapper 执行。

if [ -n "${BASH_VERSION:-}" ] && [ "${BASH##*/}" = "sh" ]; then
  if (return 0 2>/dev/null); then
    printf 'scripts/lark_wiki.sh 使用 bash 语法；请在 bash 中 source，或直接执行 ./scripts/lark_wiki.sh <command>。\n' >&2
    return 2
  fi
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  printf '缺少 bash，无法运行 scripts/lark_wiki.sh。\n' >&2
  exit 127
fi

if [ -z "${BASH_VERSION:-}" ]; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    case "${ZSH_EVAL_CONTEXT:-}" in
      *:file*)
        printf 'scripts/lark_wiki.sh 使用 bash 语法；请在 bash 中 source，或直接执行 ./scripts/lark_wiki.sh <command>。\n' >&2
        return 2
        ;;
    esac
  elif (return 0 2>/dev/null); then
    printf 'scripts/lark_wiki.sh 使用 bash 语法；请在 bash 中 source，或直接执行 ./scripts/lark_wiki.sh <command>。\n' >&2
    return 2
  fi
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  printf '缺少 bash，无法运行 scripts/lark_wiki.sh。\n' >&2
  exit 127
fi

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
fi

LW_AS="${LARK_WIKI_AS:-user}"
LW_DRY_RUN="${LARK_WIKI_DRY_RUN:-}"
LW_PYTHON="${LLM_WIKI_PYTHON:-}"

_lw_need() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '缺少必需命令: %s\n' "$1" >&2
    return 127
  }
}

_lw_api() {
  _lw_need lark-cli
  local method="$1"
  local path="$2"
  shift 2
  local args=(api "$method" "$path" --as "$LW_AS" "$@" --format json)
  if [[ "$method" != "GET" && ( "$LW_DRY_RUN" == "1" || "$LW_DRY_RUN" == "true" ) ]]; then
    args+=(--dry-run)
  fi
  lark-cli "${args[@]}"
}

_lw_python() {
  if [[ -n "$LW_PYTHON" ]]; then
    printf '%s\n' "$LW_PYTHON"
  elif [[ -x "/Users/bytedance/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3" ]]; then
    printf '%s\n' "/Users/bytedance/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
  else
    command -v python3
  fi
}

_lw_json_node() {
  jq -r '.node // .data.node // .Node // .data.Node // empty'
}

_lw_node_field() {
  local field="$1"
  jq -r --arg field "$field" '
    .data.node[$field] //
    .node[$field] //
    empty
  '
}

_lw_wiki_token_from_url() {
  local input="$1"
  if [[ "$input" =~ /wiki/([^/?#]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    return 1
  fi
}

_lw_doc_token_from_url() {
  local input="$1"
  if [[ "$input" =~ /(docx|doc)/([^/?#]+) ]]; then
    printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    return 1
  fi
}

_lw_read_payload() {
  local source="${1:-}"
  if [[ -n "$source" && "$source" != "-" ]]; then
    cat "$source"
  else
    cat
  fi
}

_lw_doc_field() {
  local field="$1"
  jq -r --arg field "$field" '.data[$field] // .[$field] // empty'
}

_lw_doc_target() {
  local target="$1"
  if _lw_wiki_token_from_url "$target" >/dev/null 2>&1; then
    lw_doc_token "$target"
  else
    printf '%s\n' "$target"
  fi
}

_lw_wiki_node_payload() {
  local obj_type="$1"
  local node_type="$2"
  local parent_node_token="$3"
  local title="$4"
  local origin_node_token="${5:-}"
  jq -n \
    --arg obj_type "$obj_type" \
    --arg node_type "$node_type" \
    --arg parent_node_token "$parent_node_token" \
    --arg title "$title" \
    --arg origin_node_token "$origin_node_token" '
    {
      obj_type: $obj_type,
      node_type: $node_type
    }
    + (if $parent_node_token == "" or $parent_node_token == "-" then {} else {parent_node_token: $parent_node_token} end)
    + (if $title == "" or $title == "-" then {} else {title: $title} end)
    + (if $origin_node_token == "" or $origin_node_token == "-" then {} else {origin_node_token: $origin_node_token} end)
  '
}

_lw_require_parent_node() {
  local parent_node_token="${1:-}"
  local action="$2"
  if [[ -z "$parent_node_token" || "$parent_node_token" == "-" ]]; then
    printf '%s 必须提供用户确认过的父 Wiki 节点 token；不能在知识空间根部或隐式位置创建。\n' "$action" >&2
    return 2
  fi
}

_lw_wiki_emit_created() {
  local kind="$1"
  local title="$2"
  local json="$3"
  printf '%s\n' "$json" | jq -c --arg kind "$kind" --arg title "$title" '
    {
      kind: $kind,
      title: $title,
      space_id: (.data.node.space_id // .node.space_id),
      node_token: (.data.node.node_token // .node.node_token),
      obj_token: (.data.node.obj_token // .node.obj_token),
      obj_type: (.data.node.obj_type // .node.obj_type),
      node_type: (.data.node.node_type // .node.node_type)
    }
  '
}

lw_auth() {
  _lw_need lark-cli
  lark-cli auth status
}

lw_wiki_auth_write() {
  _lw_need lark-cli
  lark-cli auth login --scope "wiki:wiki wiki:node:create"
}

lw_wiki_check_write_auth() {
  _lw_need lark-cli
  _lw_need jq
  local scopes
  scopes="$(lark-cli auth status | jq -r '.scope // ""')"
  if [[ " $scopes " == *" wiki:wiki "* || " $scopes " == *" wiki:node:create "* ]]; then
    printf 'ok: 已具备 Wiki 写权限\n'
    return 0
  fi
  printf '缺少 Wiki 写权限: 需要授权 wiki:wiki 或 wiki:node:create 之一\n' >&2
  printf '运行: lark-cli auth login --scope "wiki:wiki wiki:node:create"\n' >&2
  return 1
}

lw_search() {
  _lw_need lark-cli
  local query="$1"
  local page_size="${2:-10}"
  lark-cli docs +search --as "$LW_AS" --query "$query" --page-size "$page_size" --format json
}

lw_resolve() {
  _lw_need lark-cli
  _lw_need jq
  local target="$1"
  local token
  if token="$(_lw_wiki_token_from_url "$target")"; then
    lark-cli wiki spaces get_node --as "$LW_AS" --params "{\"token\":\"$token\"}" --format json
  else
    printf '{"node":{"obj_token":"%s","obj_type":"docx","title":"","node_type":"direct"}}\n' "$target"
  fi
}

lw_doc_token() {
  _lw_need jq
  lw_resolve "$1" | jq -r '
    .node.obj_token //
    .data.node.obj_token //
    .node.token //
    .data.node.token //
    empty
  '
}

lw_stat() {
  _lw_need jq
  local target="$1"
  if _lw_wiki_token_from_url "$target" >/dev/null 2>&1; then
    lw_resolve "$target" | jq '{title:(.node.title // .data.node.title), obj_type:(.node.obj_type // .data.node.obj_type), obj_token:(.node.obj_token // .data.node.obj_token), space_id:(.node.space_id // .data.node.space_id), node_type:(.node.node_type // .data.node.node_type)}'
  else
    lark-cli docs +fetch --as "$LW_AS" --doc "$target" --format json | jq '{title:(.data.title // .title), doc_id:(.data.doc_id // .doc_id), length:(.data.length // .length), total_length:(.data.total_length // .total_length)}'
  fi
}

lw_cat_json() {
  _lw_need lark-cli
  local target
  target="$(_lw_doc_target "$1")"
  lark-cli docs +fetch --as "$LW_AS" --doc "$target" --format json
}

lw_cat() {
  _lw_need jq
  lw_cat_json "$1" | jq -r '.data.markdown // .markdown // empty'
}

lw_export() {
  local target="$1"
  local output="$2"
  lw_cat "$target" >"$output"
  printf '%s\n' "$output"
}

lw_write() {
  _lw_need lark-cli
  local target
  target="$(_lw_doc_target "$1")"
  local source="${2:--}"
  local markdown
  markdown="$(_lw_read_payload "$source")"
  lark-cli docs +update --as "$LW_AS" --doc "$target" --mode overwrite --markdown "$markdown"
}

lw_append() {
  _lw_need lark-cli
  local target
  target="$(_lw_doc_target "$1")"
  local source="${2:--}"
  local markdown
  markdown="$(_lw_read_payload "$source")"
  lark-cli docs +update --as "$LW_AS" --doc "$target" --mode append --markdown "$markdown"
}

lw_replace_section() {
  _lw_need lark-cli
  local target
  target="$(_lw_doc_target "$1")"
  local title_locator="$2"
  local source="${3:--}"
  local markdown
  markdown="$(_lw_read_payload "$source")"
  lark-cli docs +update --as "$LW_AS" --doc "$target" --mode replace_range --selection-by-title "$title_locator" --markdown "$markdown"
}

lw_wiki_get_node() {
  _lw_need lark-cli
  _lw_need jq
  local token="$1"
  if _lw_wiki_token_from_url "$token" >/dev/null 2>&1; then
    token="$(_lw_wiki_token_from_url "$token")"
  fi
  lark-cli wiki spaces get_node --as "$LW_AS" --params "$(jq -n --arg token "$token" '{token:$token}')" --format json
}

lw_wiki_list_children() {
  _lw_need lark-cli
  _lw_need jq
  local space_id="$1"
  local parent_node_token="${2:-}"
  local page_size="${3:-50}"
  local params
  params="$(jq -n \
    --arg parent_node_token "$parent_node_token" \
    --argjson page_size "$page_size" '
    {page_size: $page_size}
    + (if $parent_node_token == "" or $parent_node_token == "-" then {} else {parent_node_token: $parent_node_token} end)
  ')"
  _lw_api GET "/open-apis/wiki/v2/spaces/$space_id/nodes" --params "$params"
}

lw_wiki_create_node() {
  _lw_need lark-cli
  _lw_need jq
  local space_id="$1"
  local parent_node_token="${2:-}"
  local title="$3"
  local source="${4:-}"
  local data response obj_token
  _lw_require_parent_node "$parent_node_token" "创建 Wiki 节点" || return $?
  data="$(_lw_wiki_node_payload docx origin "$parent_node_token" "$title")"
  response="$(_lw_api POST "/open-apis/wiki/v2/spaces/$space_id/nodes" --data "$data")"
  printf '%s\n' "$response"
  if [[ -n "$source" ]]; then
    obj_token="$(printf '%s\n' "$response" | _lw_node_field obj_token)"
    if [[ -z "$obj_token" ]]; then
      printf '创建节点响应中没有 obj_token，无法写入页面正文\n' >&2
      return 1
    fi
    lw_write "$obj_token" "$source" >/dev/null
  fi
}

lw_wiki_create_shortcut() {
  _lw_need lark-cli
  _lw_need jq
  local space_id="$1"
  local parent_node_token="$2"
  local origin_node_token="$3"
  local obj_type="${4:-docx}"
  local title="${5:-}"
  local data
  _lw_require_parent_node "$parent_node_token" "创建 Wiki 快捷方式" || return $?
  data="$(_lw_wiki_node_payload "$obj_type" shortcut "$parent_node_token" "$title" "$origin_node_token")"
  _lw_api POST "/open-apis/wiki/v2/spaces/$space_id/nodes" --data "$data"
}

lw_wiki_add_source_shortcut() {
  _lw_need jq
  local space_id="$1"
  local parent_node_token="$2"
  local source="$3"
  local title="${4:-}"
  local resolved node_token origin_node_token obj_type resolved_title
  local doc_kind doc_token stat_json

  if ! resolved="$(lw_wiki_get_node "$source" 2>/dev/null)"; then
    if read -r doc_kind doc_token < <(_lw_doc_token_from_url "$source"); then
      obj_type="$doc_kind"
      if [[ "$obj_type" == "doc" ]]; then
        obj_type="doc"
      fi
      if [[ -z "$title" ]]; then
        stat_json="$(lw_stat "$doc_token" 2>/dev/null || true)"
        title="$(printf '%s\n' "$stat_json" | jq -r '.title // empty')"
      fi
      if [[ -z "$title" ]]; then
        title="$doc_token"
      fi
      lw_wiki_create_shortcut "$space_id" "$parent_node_token" "$doc_token" "$obj_type" "$title"
      return $?
    fi
    printf '无法为该来源创建 Wiki 快捷方式：既不是 Wiki 节点，也不是可识别的 doc/docx URL: %s\n' "$source" >&2
    return 3
  fi

  node_token="$(printf '%s\n' "$resolved" | _lw_node_field node_token)"
  origin_node_token="$(printf '%s\n' "$resolved" | _lw_node_field origin_node_token)"
  obj_type="$(printf '%s\n' "$resolved" | _lw_node_field obj_type)"
  resolved_title="$(printf '%s\n' "$resolved" | _lw_node_field title)"

  if [[ -z "$node_token" ]]; then
    printf '解析后的来源没有 node_token: %s\n' "$source" >&2
    return 1
  fi
  if [[ -z "$obj_type" ]]; then
    printf '解析后的来源没有 obj_type: %s\n' "$source" >&2
    return 1
  fi
  if [[ -z "$origin_node_token" ]]; then
    origin_node_token="$node_token"
  fi
  if [[ -z "$title" ]]; then
    title="$resolved_title"
  fi
  lw_wiki_create_shortcut "$space_id" "$parent_node_token" "$origin_node_token" "$obj_type" "$title"
}

lw_wiki_find_child() {
  _lw_need jq
  local space_id="$1"
  local parent_node_token="$2"
  local title="$3"
  lw_wiki_list_children "$space_id" "$parent_node_token" 50 | jq -r --arg title "$title" '
    (.data.items // [])
    | map(select(.title == $title))
    | first
    | if . then {title, node_token, obj_token, obj_type, node_type, url, space_id, parent_node_token} else empty end
  '
}

_lw_truncated_cat() {
  local target="$1"
  local max_chars="${2:-12000}"
  lw_cat "$target" | awk -v max="$max_chars" '
    BEGIN { used = 0; truncated = 0 }
    {
      line = $0 "\n"
      if (used + length(line) > max) {
        remain = max - used
        if (remain > 0) {
          printf "%s", substr(line, 1, remain)
        }
        printf "\n\n[内容已截断；如需完整内容，请单独读取该页面。]\n"
        truncated = 1
        exit
      }
      printf "%s", line
      used += length(line)
    }
    END {
      if (truncated == 0 && used == 0) {
        printf "\n"
      }
    }
  '
}

_lw_wiki_context_print_node() {
  _lw_need jq
  local node_json="$1"
  local path_prefix="$2"
  local max_chars="$3"
  local title node_token obj_token obj_type node_type url
  title="$(printf '%s\n' "$node_json" | jq -r '.title // empty')"
  node_token="$(printf '%s\n' "$node_json" | jq -r '.node_token // empty')"
  obj_token="$(printf '%s\n' "$node_json" | jq -r '.obj_token // empty')"
  obj_type="$(printf '%s\n' "$node_json" | jq -r '.obj_type // empty')"
  node_type="$(printf '%s\n' "$node_json" | jq -r '.node_type // empty')"
  url="$(printf '%s\n' "$node_json" | jq -r '.url // empty')"
  if [[ -z "$title" || -z "$obj_token" ]]; then
    return 0
  fi
  case "$obj_type" in
    doc|docx) ;;
    *) return 0 ;;
  esac
  printf '\n## %s/%s\n\n' "$path_prefix" "$title"
  printf -- '- title: %s\n' "$title"
  printf -- '- path: %s/%s\n' "$path_prefix" "$title"
  printf -- '- url: %s\n' "$url"
  printf -- '- node_token: %s\n' "$node_token"
  printf -- '- obj_token: %s\n' "$obj_token"
  printf -- '- node_type: %s\n\n' "$node_type"
  printf '```markdown\n'
  if ! _lw_truncated_cat "$obj_token" "$max_chars"; then
    printf '无法读取该页面内容。\n'
  fi
  printf '\n```\n'
}

_lw_wiki_context_list_children() {
  _lw_need jq
  local space_id="$1"
  local parent_node_token="$2"
  local path_prefix="$3"
  local children
  children="$(lw_wiki_list_children "$space_id" "$parent_node_token" 50)"
  while IFS= read -r node_json; do
    [[ -n "$node_json" ]] || continue
    printf -- '- %s/%s (%s) [%s/%s]\n' \
      "$path_prefix" \
      "$(printf '%s\n' "$node_json" | jq -r '.title // empty')" \
      "$(printf '%s\n' "$node_json" | jq -r '.url // empty')" \
      "$(printf '%s\n' "$node_json" | jq -r '.obj_type // empty')" \
      "$(printf '%s\n' "$node_json" | jq -r '.node_type // empty')"
  done < <(printf '%s\n' "$children" | jq -c '.data.items[]?')
}

lw_wiki_query() {
  _lw_need jq
  local wiki_root="$1"
  local query="$2"
  local max_pages="${3:-30}"
  local max_chars="${4:-12000}"
  local root_json space_id root_node printed_pages
  local index_json wiki_json wiki_node raw_json raw_node category_json category_node category
  local log_json children node_json

  if [[ -z "$wiki_root" || -z "$query" ]]; then
    printf '用法: lw_wiki_query LLM_WIKI_ROOT_URL QUERY [MAX_COMPILED_PAGES] [MAX_CHARS_PER_PAGE]\n' >&2
    return 2
  fi

  root_json="$(lw_wiki_get_node "$wiki_root")"
  space_id="$(printf '%s\n' "$root_json" | _lw_node_field space_id)"
  root_node="$(printf '%s\n' "$root_json" | _lw_node_field node_token)"
  [[ -n "$space_id" && -n "$root_node" ]] || {
    printf '无法解析 LLM Wiki 根节点: %s\n' "$wiki_root" >&2
    return 1
  }

  printf '# Lark LLM Wiki 查询上下文\n\n'
  printf -- '- query: %s\n' "$query"
  printf -- '- root: %s\n' "$wiki_root"
  printf -- '- space_id: %s\n' "$space_id"
  printf -- '- root_node_token: %s\n' "$root_node"
  printf -- '- max_compiled_pages: %s\n' "$max_pages"
  printf -- '- max_chars_per_page: %s\n\n' "$max_chars"
  printf '> 使用方式：下面只是 Lark Wiki 的上下文包。请由 LLM 先读 INDEX，再根据问题判断需要哪些 wiki 页面；只有编译页覆盖不足时，才按 raw catalog 回读原始来源。\n\n'

  index_json="$(lw_wiki_find_child "$space_id" "$root_node" "INDEX")"
  if [[ -n "$index_json" ]]; then
    printf '# INDEX\n\n```markdown\n'
    _lw_truncated_cat "$(printf '%s\n' "$index_json" | jq -r '.obj_token')" 20000
    printf '\n```\n'
  fi

  log_json="$(lw_wiki_find_child "$space_id" "$root_node" "LOG")"
  if [[ -n "$log_json" ]]; then
    printf '\n# Recent LOG\n\n```markdown\n'
    lw_cat "$(printf '%s\n' "$log_json" | jq -r '.obj_token')" | tail -n "${LLM_WIKI_QUERY_LOG_LINES:-40}"
    printf '\n```\n'
  fi

  wiki_json="$(lw_wiki_find_child "$space_id" "$root_node" "wiki")"
  wiki_node="$(printf '%s\n' "$wiki_json" | jq -r '.node_token // empty')"
  if [[ -n "$wiki_node" ]]; then
    printf '\n# Wiki Catalog\n\n'
    for category in sources concepts entities comparisons overviews decisions; do
      category_json="$(lw_wiki_find_child "$space_id" "$wiki_node" "$category")"
      category_node="$(printf '%s\n' "$category_json" | jq -r '.node_token // empty')"
      if [[ -n "$category_node" ]]; then
        _lw_wiki_context_list_children "$space_id" "$category_node" "wiki/$category"
      fi
    done
  fi

  printf '\n# Compiled Wiki Pages\n'
  printed_pages=0
  if [[ -n "$wiki_node" ]]; then
    for category in sources concepts entities comparisons overviews decisions; do
      category_json="$(lw_wiki_find_child "$space_id" "$wiki_node" "$category")"
      category_node="$(printf '%s\n' "$category_json" | jq -r '.node_token // empty')"
      [[ -n "$category_node" ]] || continue
      children="$(lw_wiki_list_children "$space_id" "$category_node" 50)"
      while IFS= read -r node_json; do
        [[ -n "$node_json" ]] || continue
        if [[ "$printed_pages" -ge "$max_pages" ]]; then
          break 2
        fi
        _lw_wiki_context_print_node "$node_json" "wiki/$category" "$max_chars"
        printed_pages=$((printed_pages + 1))
      done < <(printf '%s\n' "$children" | jq -c '.data.items[]?')
    done
  fi

  raw_json="$(lw_wiki_find_child "$space_id" "$root_node" "raw")"
  raw_node="$(printf '%s\n' "$raw_json" | jq -r '.node_token // empty')"
  if [[ -n "$raw_node" ]]; then
    printf '\n# Raw Catalog\n\n'
    printf '下面只列 raw 来源目录，不自动读取原文。若编译页不足，请让 LLM 根据问题选择少量 raw 页面再调用 `lw_cat` 读取。\n\n'
    for category in docs articles repos meetings assets; do
      category_json="$(lw_wiki_find_child "$space_id" "$raw_node" "$category")"
      category_node="$(printf '%s\n' "$category_json" | jq -r '.node_token // empty')"
      if [[ -n "$category_node" ]]; then
        _lw_wiki_context_list_children "$space_id" "$category_node" "raw/$category"
      fi
    done
  fi
}

lw_wiki_import_doc_shortcut() {
  _lw_need jq
  local wiki_root="$1"
  local source="$2"
  local category="${3:-docs}"
  local title="${4:-}"
  local root_json space_id root_node raw_json raw_node category_json category_node created index_json log_json
  local source_obj_token source_kind source_children existing

  root_json="$(lw_wiki_get_node "$wiki_root")"
  space_id="$(printf '%s\n' "$root_json" | _lw_node_field space_id)"
  root_node="$(printf '%s\n' "$root_json" | _lw_node_field node_token)"
  [[ -n "$space_id" && -n "$root_node" ]] || {
    printf '无法解析 LLM Wiki 根节点: %s\n' "$wiki_root" >&2
    return 1
  }

  raw_json="$(lw_wiki_find_child "$space_id" "$root_node" "raw")"
  raw_node="$(printf '%s\n' "$raw_json" | jq -r '.node_token // empty')"
  [[ -n "$raw_node" ]] || {
    printf 'LLM Wiki 根节点下没有 raw 子节点: %s\n' "$wiki_root" >&2
    return 1
  }

  category_json="$(lw_wiki_find_child "$space_id" "$raw_node" "$category")"
  category_node="$(printf '%s\n' "$category_json" | jq -r '.node_token // empty')"
  [[ -n "$category_node" ]] || {
    printf 'raw 下没有目标分类节点: %s\n' "$category" >&2
    return 1
  }

  if source_json="$(lw_wiki_get_node "$source" 2>/dev/null)"; then
    source_obj_token="$(printf '%s\n' "$source_json" | _lw_node_field obj_token)"
  elif read -r source_kind source_obj_token < <(_lw_doc_token_from_url "$source"); then
    :
  else
    printf '无法解析来源，既不是 Wiki 节点，也不是 doc/docx URL: %s\n' "$source" >&2
    return 3
  fi

  if [[ -n "$source_obj_token" && "$LW_DRY_RUN" != "1" && "$LW_DRY_RUN" != "true" ]]; then
    source_children="$(lw_wiki_list_children "$space_id" "$category_node" 50)"
    existing="$(printf '%s\n' "$source_children" | jq -r --arg token "$source_obj_token" '
      (.data.items // [])
      | map(select(.obj_token == $token))
      | first
      | if . then {title, node_token, url, obj_token, obj_type, node_type, parent_node_token, space_id} else empty end
    ')"
    if [[ -n "$existing" ]]; then
      printf '已存在指向该来源的快捷方式，跳过创建:\n' >&2
      printf '%s\n' "$existing"
      return 0
    fi
  fi

  created="$(lw_wiki_add_source_shortcut "$space_id" "$category_node" "$source" "$title")"
  printf '%s\n' "$created"

  if [[ "$LW_DRY_RUN" == "1" || "$LW_DRY_RUN" == "true" ]]; then
    return 0
  fi

  local shortcut_url shortcut_title source_url today
  shortcut_url="$(printf '%s\n' "$created" | jq -r '.data.node.url // .node.url // empty')"
  shortcut_title="$(printf '%s\n' "$created" | jq -r '.data.node.title // .node.title // empty')"
  source_url="$source"
  today="$(date +%F)"

  index_json="$(lw_wiki_find_child "$space_id" "$root_node" "INDEX")"
  log_json="$(lw_wiki_find_child "$space_id" "$root_node" "LOG")"
  if [[ -n "$(printf '%s\n' "$index_json" | jq -r '.obj_token // empty')" ]]; then
    {
      printf '\n## imported sources\n\n'
      if [[ -n "$shortcut_url" ]]; then
        printf -- '- raw/%s/%s (%s)\n' "$category" "$shortcut_title" "$shortcut_url"
      else
        printf -- '- raw/%s/%s\n' "$category" "$shortcut_title"
      fi
      printf -- '- source: %s\n' "$source_url"
    } | lw_append "$(printf '%s\n' "$index_json" | jq -r '.obj_token')" - >/dev/null
  fi
  if [[ -n "$(printf '%s\n' "$log_json" | jq -r '.obj_token // empty')" ]]; then
    printf '\n%s | IMPORT_SHORTCUT | raw/%s/%s | 以 Wiki 快捷方式导入来源\n' "$today" "$category" "$shortcut_title" |
      lw_append "$(printf '%s\n' "$log_json" | jq -r '.obj_token')" - >/dev/null
  fi
}

lw_wiki_move_doc_to_wiki() {
  _lw_need lark-cli
  _lw_need jq
  local space_id="$1"
  local parent_node_token="$2"
  local obj_token="$3"
  local obj_type="${4:-docx}"
  local apply="${5:-false}"
  _lw_require_parent_node "$parent_node_token" "移动文档进 Wiki" || return $?
  case "$apply" in
    true|false) ;;
    *)
      printf 'apply 必须是 true 或 false\n' >&2
      return 2
      ;;
  esac
  local data
  data="$(jq -n \
    --arg parent_wiki_token "$parent_node_token" \
    --arg obj_token "$obj_token" \
    --arg obj_type "$obj_type" \
    --argjson apply "$apply" '
    {
      parent_wiki_token: $parent_wiki_token,
      obj_token: $obj_token,
      obj_type: $obj_type,
      apply: $apply
    }
  ')"
  _lw_api POST "/open-apis/wiki/v2/spaces/$space_id/nodes/move_docs_to_wiki" --data "$data"
}

lw_upload_file() {
  _lw_need lark-cli
  local file="$1"
  local folder_token="${2:-}"
  local name="${3:-}"
  if [[ ! -f "$file" ]]; then
    printf '本地文件不存在或不是普通文件: %s\n' "$file" >&2
    return 2
  fi
  local file_dir file_name
  file_dir="$(cd "$(dirname "$file")" && pwd)"
  file_name="$(basename "$file")"
  local args=(drive +upload --as "$LW_AS" --file "$file_name")
  if [[ -n "$folder_token" && "$folder_token" != "-" && "$folder_token" != "root" ]]; then
    args+=(--folder-token "$folder_token")
  fi
  if [[ -n "$name" ]]; then
    args+=(--name "$name")
  fi
  if [[ "$LW_DRY_RUN" == "1" || "$LW_DRY_RUN" == "true" ]]; then
    args+=(--dry-run)
  fi
  (cd "$file_dir" && lark-cli "${args[@]}")
}

lw_extract_local() {
  local file="$1"
  local output="${2:-}"
  local py
  py="$(_lw_python)"
  if [[ -z "$py" ]]; then
    printf '缺少 python3，无法解析本地文件\n' >&2
    return 127
  fi
  if [[ -n "$output" && "$output" != "-" ]]; then
    "$py" "$(dirname "${BASH_SOURCE[0]}")/extract_local_file.py" "$file" --output "$output"
    printf '%s\n' "$output"
  else
    "$py" "$(dirname "${BASH_SOURCE[0]}")/extract_local_file.py" "$file"
  fi
}

lw_prepare_local_source() {
  local file="$1"
  local folder_token="${2:-}"
  local output="$3"
  local name="${4:-}"
  local upload_json
  upload_json="$(lw_upload_file "$file" "$folder_token" "$name")"
  printf '%s\n' "$upload_json" >&2
  lw_extract_local "$file" "$output" >/dev/null
  {
    printf '\n\n## Lark 原始文件上传记录\n\n'
    printf '```json\n%s\n```\n' "$upload_json"
  } >>"$output"
  printf '%s\n' "$output"
}

lw_wiki_import_local_file() {
  _lw_need jq
  local wiki_root="$1"
  local file="$2"
  local category="${3:-assets}"
  local title="${4:-}"
  local root_json space_id root_node raw_json raw_node category_json category_node
  local wiki_json wiki_node sources_json sources_node index_json log_json
  local file_abs basename existing_raw upload_json file_token shortcut_json
  local shortcut_title shortcut_url shortcut_node page_title existing_page source_json
  local source_url source_node extracted compiled today did_write

  if [[ ! -f "$file" ]]; then
    printf '本地文件不存在或不是普通文件: %s\n' "$file" >&2
    return 2
  fi
  file_abs="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
  basename="$(basename "$file_abs")"
  if [[ -z "$title" ]]; then
    title="$basename"
  fi

  root_json="$(lw_wiki_get_node "$wiki_root")"
  space_id="$(printf '%s\n' "$root_json" | _lw_node_field space_id)"
  root_node="$(printf '%s\n' "$root_json" | _lw_node_field node_token)"
  [[ -n "$space_id" && -n "$root_node" ]] || {
    printf '无法解析 LLM Wiki 根节点: %s\n' "$wiki_root" >&2
    return 1
  }

  raw_json="$(lw_wiki_find_child "$space_id" "$root_node" "raw")"
  raw_node="$(printf '%s\n' "$raw_json" | jq -r '.node_token // empty')"
  [[ -n "$raw_node" ]] || {
    printf 'LLM Wiki 根节点下没有 raw 子节点: %s\n' "$wiki_root" >&2
    return 1
  }

  category_json="$(lw_wiki_find_child "$space_id" "$raw_node" "$category")"
  category_node="$(printf '%s\n' "$category_json" | jq -r '.node_token // empty')"
  [[ -n "$category_node" ]] || {
    printf 'raw 下没有目标分类节点: %s\n' "$category" >&2
    return 1
  }

  wiki_json="$(lw_wiki_find_child "$space_id" "$root_node" "wiki")"
  wiki_node="$(printf '%s\n' "$wiki_json" | jq -r '.node_token // empty')"
  [[ -n "$wiki_node" ]] || {
    printf 'LLM Wiki 根节点下没有 wiki 子节点: %s\n' "$wiki_root" >&2
    return 1
  }

  sources_json="$(lw_wiki_find_child "$space_id" "$wiki_node" "sources")"
  sources_node="$(printf '%s\n' "$sources_json" | jq -r '.node_token // empty')"
  [[ -n "$sources_node" ]] || {
    printf 'wiki 下没有 sources 子节点\n' >&2
    return 1
  }

  existing_raw="$(lw_wiki_list_children "$space_id" "$category_node" 50 | jq -r --arg title "$title" '
    (.data.items // [])
    | map(select(.title == $title))
    | first
    | if . then {title, node_token, url, obj_token, obj_type, node_type, parent_node_token, space_id} else empty end
  ')"
  if [[ -n "$existing_raw" ]]; then
    shortcut_json="$existing_raw"
    file_token="$(printf '%s\n' "$existing_raw" | jq -r '.obj_token // empty')"
  else
    upload_json="$(lw_upload_file "$file_abs" "" "$title")"
    printf '%s\n' "$upload_json" >&2
    file_token="$(printf '%s\n' "$upload_json" | jq -r '.data.file_token // .file_token // empty')"
    [[ -n "$file_token" ]] || {
      printf '上传响应中没有 file_token，无法创建 raw 快捷方式\n' >&2
      return 1
    }
    shortcut_json="$(lw_wiki_create_shortcut "$space_id" "$category_node" "$file_token" file "$title")"
  fi

  shortcut_title="$(printf '%s\n' "$shortcut_json" | jq -r '.title // .data.node.title // .node.title // empty')"
  shortcut_url="$(printf '%s\n' "$shortcut_json" | jq -r '.url // .data.node.url // .node.url // empty')"
  shortcut_node="$(printf '%s\n' "$shortcut_json" | jq -r '.node_token // .data.node.node_token // .node.node_token // empty')"

  extracted="$(mktemp -t lark-wiki-local-extract.XXXXXX.md)"
  compiled="$(mktemp -t lark-wiki-local-source.XXXXXX.md)"
  lw_extract_local "$file_abs" "$extracted" >/dev/null

  page_title="Source: $title"
  existing_page="$(lw_wiki_find_child "$space_id" "$sources_node" "$page_title")"
  did_write="false"
  if [[ -n "$existing_page" ]]; then
    source_json="$existing_page"
  else
    {
      printf '# %s\n\n' "$page_title"
      printf '## 元数据\n\n'
      printf -- '- source_type: local_file\n'
      printf -- '- file_type: %s\n' "${title##*.}"
      printf -- '- raw_path: raw/%s/%s\n' "$category" "$title"
      if [[ -n "$shortcut_url" ]]; then
        printf -- '- raw_url: %s\n' "$shortcut_url"
      fi
      printf -- '- uploaded_file_token: %s\n' "$file_token"
      printf -- '- local_path: %s\n' "$file_abs"
      printf -- '- compiled_at: %s\n' "$(date +%FT%T%z)"
      printf -- '- extractor: scripts/extract_local_file.py\n\n'
      printf '## 编译摘要\n\n'
      printf -- '- 原始文件已上传到 Lark，并作为 Wiki 快捷方式挂到 `raw/%s`。\n' "$category"
      printf -- '- 本页保留本地抽取文本，后续查询优先读取本页；需要核对版式或附件时读取 raw 文件。\n'
      printf -- '- 如果来源包含个人、账单或凭证信息，向其他页面沉淀事实时只保留最小必要字段。\n\n'
      printf '## 原文抽取\n\n'
      cat "$extracted"
    } >"$compiled"
    source_json="$(lw_wiki_create_node "$space_id" "$sources_node" "$page_title" "$compiled")"
    did_write="true"
  fi

  source_url="$(printf '%s\n' "$source_json" | jq -r '.url // .data.node.url // .node.url // empty')"
  source_node="$(printf '%s\n' "$source_json" | jq -r '.node_token // .data.node.node_token // .node.node_token // empty')"

  if [[ "$did_write" == "true" && "$LW_DRY_RUN" != "1" && "$LW_DRY_RUN" != "true" ]]; then
    today="$(date +%F)"
    index_json="$(lw_wiki_find_child "$space_id" "$root_node" "INDEX")"
    log_json="$(lw_wiki_find_child "$space_id" "$root_node" "LOG")"
    if [[ -n "$(printf '%s\n' "$index_json" | jq -r '.obj_token // empty')" ]]; then
      {
        printf '\n## local imports\n\n'
        if [[ -n "$shortcut_url" ]]; then
          printf -- '- raw/%s/[%s](%s)\n' "$category" "$shortcut_title" "$shortcut_url"
        else
          printf -- '- raw/%s/%s\n' "$category" "$shortcut_title"
        fi
        if [[ -n "$source_url" ]]; then
          printf -- '- compiled: wiki/sources/[%s](%s)\n' "$page_title" "$source_url"
        else
          printf -- '- compiled: wiki/sources/%s\n' "$page_title"
        fi
        printf -- '- file_type: %s\n' "${title##*.}"
      } | lw_append "$(printf '%s\n' "$index_json" | jq -r '.obj_token')" - >/dev/null
    fi
    if [[ -n "$(printf '%s\n' "$log_json" | jq -r '.obj_token // empty')" ]]; then
      printf '\n%s | IMPORT_LOCAL_FILE | raw/%s/%s -> wiki/sources/%s | 上传本地文件原件并编译抽取文本\n' "$today" "$category" "$shortcut_title" "$page_title" |
        lw_append "$(printf '%s\n' "$log_json" | jq -r '.obj_token')" - >/dev/null
    fi
  fi

  rm -f "$extracted" "$compiled"
  jq -n \
    --arg raw_title "$shortcut_title" \
    --arg raw_url "$shortcut_url" \
    --arg raw_node "$shortcut_node" \
    --arg file_token "$file_token" \
    --arg source_title "$page_title" \
    --arg source_url "$source_url" \
    --arg source_node "$source_node" \
    --arg compiled_written "$did_write" \
    '{
      ok: true,
      raw: {title: $raw_title, url: $raw_url, node_token: $raw_node, file_token: $file_token},
      compiled: {title: $source_title, url: $source_url, node_token: $source_node, written: ($compiled_written == "true")}
    }'
}

lw_wiki_init_tree() {
  _lw_need jq
  local space_id="$1"
  local root_title="$2"
  local parent_node_token="${3:-}"
  local today root_json root_node root_obj
  local agents_json agents_obj index_json index_obj log_json log_obj
  local raw_json raw_node raw_obj wiki_json wiki_node wiki_obj
  local child_json child_obj title
  _lw_require_parent_node "$parent_node_token" "初始化 LLM Wiki 子树" || return $?
  today="$(date +%F)"

  root_json="$(lw_wiki_create_node "$space_id" "$parent_node_token" "$root_title")"
  root_node="$(printf '%s\n' "$root_json" | _lw_node_field node_token)"
  root_obj="$(printf '%s\n' "$root_json" | _lw_node_field obj_token)"
  _lw_wiki_emit_created root "$root_title" "$root_json"
  lw_write "$root_obj" - >/dev/null <<EOF
# $root_title

这是 Lark LLM Wiki 的根节点。来源材料和编译页面都以子 Wiki 节点组织，不能用单个文档中的链接替代。
EOF

  agents_json="$(lw_wiki_create_node "$space_id" "$root_node" "AGENTS.md")"
  agents_obj="$(printf '%s\n' "$agents_json" | _lw_node_field obj_token)"
  _lw_wiki_emit_created contract "AGENTS.md" "$agents_json"
  lw_write "$agents_obj" - >/dev/null <<EOF
# AGENTS.md

按 Lark Wiki 节点树维护这个知识库。

- 来源文档已经是 Wiki 节点时，在 raw/ 下创建 Wiki 快捷方式。
- 不要用单个聚合文档替代节点树。
- 编译后的知识放在 wiki/ 下，并保留事实来源。
- 结构和内容变更都记录到 LOG。
EOF

  index_json="$(lw_wiki_create_node "$space_id" "$root_node" "INDEX")"
  index_obj="$(printf '%s\n' "$index_json" | _lw_node_field obj_token)"
  _lw_wiki_emit_created index "INDEX" "$index_json"
  lw_write "$index_obj" - >/dev/null <<EOF
# INDEX

> last_updated: $today

## raw

- raw/articles
- raw/docs
- raw/repos
- raw/meetings
- raw/assets

## wiki

- wiki/sources
- wiki/entities
- wiki/concepts
- wiki/comparisons
- wiki/overviews
- wiki/decisions
EOF

  log_json="$(lw_wiki_create_node "$space_id" "$root_node" "LOG")"
  log_obj="$(printf '%s\n' "$log_json" | _lw_node_field obj_token)"
  _lw_wiki_emit_created log "LOG" "$log_json"
  lw_write "$log_obj" - >/dev/null <<EOF
# LOG

| 日期 | 操作 | 目标 | 摘要 |
| --- | --- | --- | --- |
| $today | INIT | / | 初始化 Lark Wiki 节点树 |
EOF

  raw_json="$(lw_wiki_create_node "$space_id" "$root_node" "raw")"
  raw_node="$(printf '%s\n' "$raw_json" | _lw_node_field node_token)"
  raw_obj="$(printf '%s\n' "$raw_json" | _lw_node_field obj_token)"
  _lw_wiki_emit_created directory "raw" "$raw_json"
  lw_write "$raw_obj" - >/dev/null <<'EOF'
# raw

来源材料放在这个节点下面。已有 Wiki 页面优先用 Wiki 快捷方式挂载。
EOF

  for title in articles docs repos meetings assets; do
    child_json="$(lw_wiki_create_node "$space_id" "$raw_node" "$title")"
    child_obj="$(printf '%s\n' "$child_json" | _lw_node_field obj_token)"
    _lw_wiki_emit_created directory "raw/$title" "$child_json"
    lw_write "$child_obj" - >/dev/null <<EOF
# raw/$title

这里存放 $title 类型的来源快捷方式。
EOF
  done

  wiki_json="$(lw_wiki_create_node "$space_id" "$root_node" "wiki")"
  wiki_node="$(printf '%s\n' "$wiki_json" | _lw_node_field node_token)"
  wiki_obj="$(printf '%s\n' "$wiki_json" | _lw_node_field obj_token)"
  _lw_wiki_emit_created directory "wiki" "$wiki_json"
  lw_write "$wiki_obj" - >/dev/null <<'EOF'
# wiki

编译后的、有来源支撑的知识放在这个节点下面。
EOF

  for title in sources entities concepts comparisons overviews decisions; do
    child_json="$(lw_wiki_create_node "$space_id" "$wiki_node" "$title")"
    child_obj="$(printf '%s\n' "$child_json" | _lw_node_field obj_token)"
    _lw_wiki_emit_created directory "wiki/$title" "$child_json"
    lw_write "$child_obj" - >/dev/null <<EOF
# wiki/$title

编译后的 $title 页面放在这里。
EOF
  done
}

lw_create() {
  _lw_need lark-cli
  local title="$1"
  local parent_kind="$2"
  local parent_token="$3"
  local source="${4:--}"
  local markdown
  markdown="$(_lw_read_payload "$source")"
  case "$parent_kind" in
    folder)
      lark-cli docs +create --as "$LW_AS" --folder-token "$parent_token" --title "$title" --markdown "$markdown"
      ;;
    wiki)
      printf 'lw_create wiki 已废弃，因为缺少 space_id；请使用 lw_wiki_create_node SPACE_ID PARENT_NODE_TOKEN TITLE [INPUT.md|-]\n' >&2
      return 2
      ;;
    space)
      printf 'lw_create space 已废弃；LLM Wiki 必须创建在用户确认过的父 Wiki 节点下，请使用 lw_wiki_create_node SPACE_ID PARENT_NODE_TOKEN TITLE [INPUT.md|-]\n' >&2
      return 2
      ;;
    doc|none)
      lark-cli docs +create --as "$LW_AS" --title "$title" --markdown "$markdown"
      ;;
    *)
      printf 'parent_kind 必须是 doc、none、folder、wiki 或 space\n' >&2
      return 2
      ;;
  esac
}

lw_create_doc() {
  _lw_need lark-cli
  local title="$1"
  local source="${2:--}"
  local markdown
  markdown="$(_lw_read_payload "$source")"
  lark-cli docs +create --as "$LW_AS" --title "$title" --markdown "$markdown"
}

lw_rename() {
  _lw_need lark-cli
  local target
  target="$(_lw_doc_target "$1")"
  local title="$2"
  local markdown
  markdown="$(lw_cat "$target")"
  lark-cli docs +update --as "$LW_AS" --doc "$target" --mode overwrite --markdown "$markdown" --new-title "$title"
}

lw_log_entry() {
  local action="$1"
  local page="$2"
  local summary="$3"
  printf '%s | %s | %s | %s\n' "$(date +%F)" "$action" "$page" "$summary"
}

lw_usage() {
  cat <<'USAGE'
用法:
  source scripts/lark_wiki.sh
  lw_search QUERY [PAGE_SIZE]
  lw_resolve DOC_OR_WIKI_URL
  lw_stat DOC_OR_WIKI_URL
  lw_cat DOC_OR_WIKI_URL
  lw_export DOC_OR_WIKI_URL OUTPUT.md
  lw_write DOC_OR_WIKI_URL [INPUT.md|-]
  lw_append DOC_OR_WIKI_URL [INPUT.md|-]
  lw_replace_section DOC_OR_WIKI_URL "## Section" [INPUT.md|-]
  lw_wiki_auth_write
  lw_wiki_check_write_auth
  lw_wiki_get_node WIKI_URL_OR_NODE_TOKEN
  lw_wiki_list_children SPACE_ID [PARENT_NODE_TOKEN] [PAGE_SIZE]
  lw_wiki_create_node SPACE_ID PARENT_NODE_TOKEN TITLE [INPUT.md|-]
  lw_wiki_create_shortcut SPACE_ID PARENT_NODE_TOKEN ORIGIN_NODE_TOKEN [OBJ_TYPE] [TITLE]
  lw_wiki_add_source_shortcut SPACE_ID PARENT_NODE_TOKEN WIKI_OR_DOC_URL [TITLE]
  lw_wiki_find_child SPACE_ID PARENT_NODE_TOKEN TITLE
  lw_wiki_query LLM_WIKI_ROOT_URL QUERY [MAX_COMPILED_PAGES] [MAX_CHARS_PER_PAGE]
  lw_wiki_import_doc_shortcut LLM_WIKI_ROOT_URL WIKI_OR_DOC_URL [raw-category] [TITLE]
  lw_wiki_import_local_file LLM_WIKI_ROOT_URL LOCAL_FILE [raw-category] [TITLE]
  lw_wiki_move_doc_to_wiki SPACE_ID PARENT_NODE_TOKEN OBJ_TOKEN [OBJ_TYPE] [APPLY]
  lw_wiki_init_tree SPACE_ID ROOT_TITLE PARENT_NODE_TOKEN
  lw_upload_file LOCAL_FILE [DRIVE_FOLDER_TOKEN] [UPLOAD_NAME]
  lw_extract_local LOCAL_FILE [OUTPUT.md|-]
  lw_prepare_local_source LOCAL_FILE DRIVE_FOLDER_TOKEN OUTPUT.md [UPLOAD_NAME]
  lw_create TITLE doc|none|folder|wiki|space PARENT_TOKEN [INPUT.md|-]
  lw_create_doc TITLE [INPUT.md|-]
  lw_log_entry INGEST|UPDATE|OUTPUT PAGE SUMMARY

规则:
  Wiki 写命令中的 SPACE_ID 和 PARENT_NODE_TOKEN 必须来自用户确认过的目标 Wiki。
  不要把示例、最近命令或 my_library 当成隐式目标。
  LLM Wiki 项目必须作为已有大知识库节点下的子树展开，不能随意在空间根部创建独立入口。

环境变量:
  LARK_WIKI_AS=user|bot   传给 lark-cli 的身份，默认 user。
  LARK_WIKI_DRY_RUN=1     打印原始 API 请求，不执行支持 dry-run 的 Wiki API 写入。
  LLM_WIKI_PYTHON=/path/python3  指定本地文件解析使用的 Python。
USAGE
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd="${1:-help}"
  shift || true
  case "$cmd" in
    auth) lw_auth "$@" ;;
    search) lw_search "$@" ;;
    resolve) lw_resolve "$@" ;;
    token) lw_doc_token "$@" ;;
    stat) lw_stat "$@" ;;
    cat-json) lw_cat_json "$@" ;;
    cat) lw_cat "$@" ;;
    export) lw_export "$@" ;;
    write) lw_write "$@" ;;
    append) lw_append "$@" ;;
    replace-section) lw_replace_section "$@" ;;
    wiki-auth-write) lw_wiki_auth_write "$@" ;;
    wiki-check-write-auth) lw_wiki_check_write_auth "$@" ;;
    wiki-get-node) lw_wiki_get_node "$@" ;;
    wiki-list-children) lw_wiki_list_children "$@" ;;
    wiki-create-node) lw_wiki_create_node "$@" ;;
    wiki-create-shortcut) lw_wiki_create_shortcut "$@" ;;
    wiki-add-source-shortcut) lw_wiki_add_source_shortcut "$@" ;;
    wiki-find-child) lw_wiki_find_child "$@" ;;
    wiki-query) lw_wiki_query "$@" ;;
    wiki-import-doc-shortcut) lw_wiki_import_doc_shortcut "$@" ;;
    wiki-import-local-file) lw_wiki_import_local_file "$@" ;;
    wiki-move-doc-to-wiki) lw_wiki_move_doc_to_wiki "$@" ;;
    wiki-init-tree) lw_wiki_init_tree "$@" ;;
    upload-file) lw_upload_file "$@" ;;
    extract-local) lw_extract_local "$@" ;;
    prepare-local-source) lw_prepare_local_source "$@" ;;
    create) lw_create "$@" ;;
    create-doc) lw_create_doc "$@" ;;
    rename) lw_rename "$@" ;;
    log-entry) lw_log_entry "$@" ;;
    help|-h|--help) lw_usage ;;
    *)
      printf '未知命令: %s\n\n' "$cmd" >&2
      lw_usage >&2
      exit 2
      ;;
  esac
fi
