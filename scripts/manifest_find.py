#!/usr/bin/env python3
"""Find an existing SOURCES manifest row for idempotent staging."""

from __future__ import annotations

import argparse
import sys
from collections.abc import Iterable

from manifest_upsert import HEADERS, is_manifest_header, is_separator, normalize_lark_tables, row_values, split_row


def meaningful(value: str | None) -> bool:
    return bool(value and value != "-")


def manifest_rows(text: str) -> Iterable[dict[str, str]]:
    text = normalize_lark_tables(text)
    lines = text.splitlines()
    header: list[str] | None = None
    start = 0
    for index, line in enumerate(lines):
        cells = split_row(line)
        if is_manifest_header(cells):
            header = [cell.lower() for cell in cells]
            start = index + 1
            break
    if header is None:
        return

    for line in lines[start:]:
        cells = split_row(line)
        if not cells:
            if line.strip():
                continue
            break
        if is_separator(line):
            continue
        values = row_values(header, cells)
        if meaningful(values.get("source_id")):
            yield values


def first_match(rows: list[dict[str, str]], field: str, value: str | None) -> dict[str, str] | None:
    if not meaningful(value):
        return None
    for row in rows:
        if row.get(field, "") == value:
            return row
    return None


def token_match(rows: list[dict[str, str]], token: str | None) -> dict[str, str] | None:
    if not meaningful(token):
        return None
    for row in rows:
        haystack = " ".join(
            row.get(field, "")
            for field in ("origin", "raw_node", "extraction", "source_page", "compiled_into")
        )
        if token in haystack:
            return row
    return None


def find_row(rows: list[dict[str, str]], args: argparse.Namespace) -> dict[str, str] | None:
    if args.kind == "local_file":
        if meaningful(args.checksum):
            return first_match(rows, "checksum", args.checksum)
        if meaningful(args.raw_node) and meaningful(args.origin):
            for row in rows:
                if row.get("raw_node") == args.raw_node and row.get("origin") == args.origin:
                    return row
        return first_match(rows, "raw_node", args.raw_node)

    return (
        first_match(rows, "origin", args.origin)
        or token_match(rows, args.obj_token)
        or first_match(rows, "raw_node", args.raw_node)
        or first_match(rows, "checksum", args.checksum)
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Find a SOURCES manifest row")
    parser.add_argument("--origin", default="-")
    parser.add_argument("--raw-node", default="-")
    parser.add_argument("--checksum", default="-")
    parser.add_argument("--kind", default="-")
    parser.add_argument("--obj-token", default="-")
    parser.add_argument("--field", default="source_id")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.field not in HEADERS:
        print(f"unknown manifest field: {args.field}", file=sys.stderr)
        return 2
    row = find_row(list(manifest_rows(sys.stdin.read())), args)
    if row is None:
        return 1
    print(row.get(args.field, "-") or "-")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
