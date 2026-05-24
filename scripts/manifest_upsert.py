#!/usr/bin/env python3
"""Upsert a row in the Lark LLM Wiki SOURCES markdown table."""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass


HEADERS = [
    "source_id",
    "title",
    "kind",
    "raw_node",
    "origin",
    "imported_at",
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


def escape_cell(value: str) -> str:
    return value.replace("\n", " ").replace("|", "\\|").strip()


def split_row(line: str) -> list[str]:
    stripped = line.strip()
    if not (stripped.startswith("|") and stripped.endswith("|")):
        return []
    cells = [cell.strip().replace("\\|", "|") for cell in stripped.strip("|").split("|")]
    return cells


def is_separator(line: str) -> bool:
    cells = split_row(line)
    return bool(cells) and all(set(cell.replace(":", "").strip()) <= {"-"} for cell in cells)


def table_header() -> str:
    return "| " + " | ".join(HEADERS) + " |"


def table_separator() -> str:
    return "| " + " | ".join("---" for _ in HEADERS) + " |"


def upsert(text: str, row: Row) -> str:
    lines = text.splitlines()
    header_index = None
    for index, line in enumerate(lines):
        if [cell.lower() for cell in split_row(line)] == HEADERS:
            header_index = index
            break

    if header_index is None:
        base = text.rstrip()
        prefix = base + "\n\n" if base else ""
        return prefix + "\n".join([table_header(), table_separator(), row.to_markdown()]) + "\n"

    if header_index + 1 >= len(lines) or not is_separator(lines[header_index + 1]):
        lines.insert(header_index + 1, table_separator())

    insert_at = header_index + 2
    index = insert_at
    replaced = False
    while index < len(lines):
        cells = split_row(lines[index])
        if not cells:
            break
        if len(cells) >= 1 and cells[0] == row.source_id:
            lines[index] = row.to_markdown()
            replaced = True
            break
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
