#!/usr/bin/env python3
"""Upsert rows in Lark LLM Wiki INDEX markdown tables."""

from __future__ import annotations

import argparse
import sys

from lark_markdown import normalize_lark_tables


SOURCE_HEADERS = ["Page", "Source ID", "Type", "Summary", "Compiled Into", "Status", "Last Updated"]
CATALOG_HEADERS = ["Page", "Summary", "Source Count", "Last Updated", "Review State"]
DECISION_HEADERS = ["Page", "Summary", "Status", "Last Updated", "Review State"]
DISPUTED_HEADERS = ["Page", "Claim", "Status", "Last Updated", "Needs Human Review"]
AUDIT_HEADERS = ["Page", "Target Source", "Status", "Last Updated"]
SECTION_HEADERS = {
    "Sources": SOURCE_HEADERS,
    "Concepts": CATALOG_HEADERS,
    "Entities": CATALOG_HEADERS,
    "Comparisons": CATALOG_HEADERS,
    "Overviews": CATALOG_HEADERS,
    "Syntheses": CATALOG_HEADERS,
    "Decisions": DECISION_HEADERS,
    "Disputed": DISPUTED_HEADERS,
    "Audits": AUDIT_HEADERS,
}


def escape_cell(value: str) -> str:
    return (value or "-").replace("\n", " ").replace("|", "\\|").strip() or "-"


def split_row(line: str) -> list[str]:
    stripped = line.strip()
    if not (stripped.startswith("|") and stripped.endswith("|")):
        return []
    body = stripped[1:-1]
    cells: list[str] = []
    buf: list[str] = []
    escaped = False
    for ch in body:
        if escaped:
            if ch == "|":
                buf.append(ch)
            else:
                buf.append("\\")
                buf.append(ch)
            escaped = False
        elif ch == "\\":
            escaped = True
        elif ch == "|":
            cells.append("".join(buf).strip())
            buf = []
        else:
            buf.append(ch)
    if escaped:
        buf.append("\\")
    cells.append("".join(buf).strip())
    return cells


def is_separator(line: str) -> bool:
    cells = split_row(line)
    return bool(cells) and all(set(cell.replace(":", "").strip()) <= {"-"} for cell in cells)


def render_row(values: dict[str, str], headers: list[str]) -> str:
    return "| " + " | ".join(escape_cell(values.get(header, "-")) for header in headers) + " |"


def source_values(args: argparse.Namespace) -> dict[str, str]:
    return {
        "Page": args.page,
        "Source ID": args.source_id,
        "Type": args.type,
        "Summary": args.summary,
        "Compiled Into": args.compiled_into,
        "Status": args.status,
        "Last Updated": args.last_updated,
    }


def row_values(args: argparse.Namespace, headers: list[str]) -> dict[str, str]:
    if headers == SOURCE_HEADERS:
        return source_values(args)
    if headers == CATALOG_HEADERS:
        return {
            "Page": args.page,
            "Summary": args.summary,
            "Source Count": args.source_count,
            "Last Updated": args.last_updated,
            "Review State": args.review_state,
        }
    if headers == DECISION_HEADERS:
        return {
            "Page": args.page,
            "Summary": args.summary,
            "Status": args.status,
            "Last Updated": args.last_updated,
            "Review State": args.review_state,
        }
    if headers == DISPUTED_HEADERS:
        return {
            "Page": args.page,
            "Claim": args.claim,
            "Status": args.status,
            "Last Updated": args.last_updated,
            "Needs Human Review": args.needs_human_review,
        }
    if headers == AUDIT_HEADERS:
        return {
            "Page": args.page,
            "Target Source": args.target_source,
            "Status": args.status,
            "Last Updated": args.last_updated,
        }
    raise SystemExit("unsupported INDEX section")


def find_section(lines: list[str], section: str) -> tuple[int, int]:
    heading = f"## {section}"
    start = None
    for index, line in enumerate(lines):
        if line.strip() == heading:
            start = index
            break
    if start is None:
        lines.extend(["", heading, ""])
        return len(lines) - 2, len(lines)
    end = len(lines)
    for index in range(start + 1, len(lines)):
        if lines[index].startswith("## "):
            end = index
            break
    return start, end


def upsert(text: str, section: str, headers: list[str], key_column: str, values: dict[str, str]) -> str:
    text = normalize_lark_tables(text)
    lines = text.splitlines()
    _, section_end = find_section(lines, section)
    header_index = None
    for index in range(max(0, section_end - 1), -1, -1):
        if lines[index].startswith("## "):
            break
        cells = split_row(lines[index])
        if [cell.lower() for cell in cells] == [header.lower() for header in headers]:
            header_index = index
            break
    if header_index is None:
        start, section_end = find_section(lines, section)
        insertion = start + 1
        while insertion < section_end and lines[insertion].strip():
            insertion += 1
        lines[insertion:insertion] = [
            "",
            "| " + " | ".join(headers) + " |",
            "| " + " | ".join("---" for _ in headers) + " |",
        ]
        header_index = insertion + 1
        section_end += 3

    if header_index + 1 >= len(lines) or not is_separator(lines[header_index + 1]):
        lines.insert(header_index + 1, "| " + " | ".join("---" for _ in headers) + " |")
        section_end += 1

    key_index = headers.index(key_column)
    key_value = values[key_column]
    row = render_row(values, headers)
    index = header_index + 2
    replaced = False
    while index < section_end:
        cells = split_row(lines[index])
        if not cells:
            break
        if len(cells) > key_index and cells[key_index] == key_value and not replaced:
            lines[index] = row
            replaced = True
        elif len(cells) > key_index and cells[key_index] == key_value:
            del lines[index]
            section_end -= 1
            continue
        index += 1
    if not replaced:
        lines.insert(index, row)
    return "\n".join(lines).rstrip() + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Upsert an INDEX table row")
    parser.add_argument("--section", required=True)
    parser.add_argument("--key-column", required=True)
    parser.add_argument("--page", required=True)
    parser.add_argument("--source-id", default="-")
    parser.add_argument("--type", default="-")
    parser.add_argument("--summary", default="-")
    parser.add_argument("--compiled-into", default="-")
    parser.add_argument("--status", default="-")
    parser.add_argument("--source-count", default="-")
    parser.add_argument("--review-state", default="-")
    parser.add_argument("--claim", default="-")
    parser.add_argument("--needs-human-review", default="-")
    parser.add_argument("--target-source", default="-")
    parser.add_argument("--last-updated", default="-")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.section not in SECTION_HEADERS:
        raise SystemExit(f"unknown section: {args.section}")
    headers = SECTION_HEADERS[args.section]
    if args.key_column not in headers:
        raise SystemExit(f"unknown key column: {args.key_column}")
    if args.section == "Sources" and (args.source_id == "-" or args.type == "-"):
        raise SystemExit("--source-id and --type are required for Sources")
    sys.stdout.write(upsert(sys.stdin.read(), args.section, headers, args.key_column, row_values(args, headers)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
