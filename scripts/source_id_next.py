#!/usr/bin/env python3
"""Allocate the next daily source_id from a SOURCES markdown table."""

from __future__ import annotations

import argparse
import datetime as dt
import re
import sys

from lark_markdown import normalize_lark_tables


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


def next_source_id(text: str, today: str) -> str:
    text = normalize_lark_tables(text)
    pattern = re.compile(rf"^SRC-{re.escape(today)}-(\d+)$")
    maximum = 0
    for line in text.splitlines():
        cells = split_row(line)
        if not cells:
            continue
        match = pattern.match(cells[0])
        if match:
            maximum = max(maximum, int(match.group(1)))
    return f"SRC-{today}-{maximum + 1:03d}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Allocate the next LLM Wiki source_id")
    parser.add_argument("--date", default=dt.date.today().isoformat(), help="YYYY-MM-DD")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    sys.stdout.write(next_source_id(sys.stdin.read(), args.date) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
