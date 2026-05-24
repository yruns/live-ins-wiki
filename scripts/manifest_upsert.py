#!/usr/bin/env python3
"""Upsert a row in the Lark LLM Wiki SOURCES markdown table."""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass

from lark_markdown import normalize_lark_tables


HEADERS = [
    "source_id",
    "title",
    "kind",
    "raw_node",
    "origin",
    "imported_at",
    "updated_at",
    "checksum",
    "extraction",
    "source_page",
    "compiled_into",
    "compile_status",
    "audit_status",
    "review_state",
]


@dataclass
class Row:
    values: dict[str, str]

    @classmethod
    def from_args(cls, args: argparse.Namespace) -> "Row":
        return cls({name: getattr(args, name.replace("-", "_"), "-") or "-" for name in HEADERS})

    @property
    def source_id(self) -> str:
        return self.values["source_id"]

    def to_markdown(self) -> str:
        return "| " + " | ".join(escape_cell(self.values[name]) for name in HEADERS) + " |"

    def merged_with(self, existing: dict[str, str]) -> "Row":
        merged: dict[str, str] = {}
        for name in HEADERS:
            incoming = self.values.get(name, "-") or "-"
            current = existing.get(name, "-") or "-"
            if name == "source_id":
                merged[name] = incoming
            elif name == "imported_at":
                merged[name] = current if current != "-" else incoming
            elif incoming == "-":
                merged[name] = current
            else:
                merged[name] = incoming
        return Row(merged)


def escape_cell(value: str) -> str:
    return value.replace("\n", " ").replace("|", "\\|").strip()


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


def table_header() -> str:
    return "| " + " | ".join(HEADERS) + " |"


def table_separator() -> str:
    return "| " + " | ".join("---" for _ in HEADERS) + " |"


def is_manifest_header(cells: list[str]) -> bool:
    lowered = [cell.lower() for cell in cells]
    return lowered[:6] == HEADERS[:6] and "compile_status" in lowered and "audit_status" in lowered


def row_values(header: list[str], cells: list[str]) -> dict[str, str]:
    values = {name: "-" for name in HEADERS}
    for index, name in enumerate(header):
        key = name.lower()
        if key in values and index < len(cells):
            values[key] = cells[index] or "-"
    return values


def upsert(text: str, row: Row) -> str:
    text = normalize_lark_tables(text)
    lines = text.splitlines()
    header_index = None
    header: list[str] = HEADERS
    for index, line in enumerate(lines):
        cells = split_row(line)
        if is_manifest_header(cells):
            header_index = index
            header = [cell.lower() for cell in cells]
            break

    if header_index is None:
        base = text.rstrip()
        prefix = base + "\n\n" if base else ""
        return prefix + "\n".join([table_header(), table_separator(), row.to_markdown()]) + "\n"

    lines[header_index] = table_header()
    if header_index + 1 >= len(lines) or not is_separator(lines[header_index + 1]):
        lines.insert(header_index + 1, table_separator())
    else:
        lines[header_index + 1] = table_separator()

    insert_at = header_index + 2
    index = insert_at
    replaced = False
    while index < len(lines):
        cells = split_row(lines[index])
        if not cells:
            break
        current = row_values(header, cells)
        if current["source_id"] == row.source_id and not replaced:
            lines[index] = row.merged_with(current).to_markdown()
            replaced = True
        elif current["source_id"] == row.source_id:
            del lines[index]
            continue
        else:
            lines[index] = Row(current).to_markdown()
        index += 1

    if not replaced:
        lines.insert(index, row.to_markdown())

    return "\n".join(lines).rstrip() + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Upsert a SOURCES manifest row")
    for name in HEADERS:
        parser.add_argument(f"--{name.replace('_', '-')}", required=name == "source_id", default="-")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    row = Row.from_args(args)
    sys.stdout.write(upsert(sys.stdin.read(), row))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
