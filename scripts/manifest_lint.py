#!/usr/bin/env python3
"""Lint the SOURCES manifest table using the same parser as upsert."""

from __future__ import annotations

import sys
from collections import Counter
from collections.abc import Iterable

from manifest_upsert import is_manifest_header, is_separator, normalize_lark_tables, row_values, split_row


COMPLETE_AUDIT_STATUSES = {"audited", "complete", "completed"}


def meaningful(value: str | None) -> bool:
    return bool(value and value != "-")


def manifest_rows(text: str) -> tuple[bool, list[dict[str, str]]]:
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
        return False, []

    rows: list[dict[str, str]] = []
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
            rows.append(values)
    return True, rows


def lint(rows: Iterable[dict[str, str]]) -> list[str]:
    findings: list[str] = []
    rows = list(rows)
    source_ids = [row.get("source_id", "-") for row in rows if meaningful(row.get("source_id"))]
    for source_id, count in sorted(Counter(source_ids).items()):
        if count > 1:
            findings.append(f"FAIL SOURCES duplicate source_id: {source_id}")

    for row in rows:
        source_id = row.get("source_id", "-")
        compile_status = row.get("compile_status", "-")
        audit_status = row.get("audit_status", "-")
        compiled_into = row.get("compiled_into", "-")
        if compile_status in {"staged", "extracted"}:
            findings.append(
                "WARN SOURCES has staged/extracted rows; "
                f"source_id={source_id}; status={compile_status}"
            )
        if compile_status == "compiled" and audit_status not in COMPLETE_AUDIT_STATUSES:
            findings.append(
                "FAIL SOURCES compile_status=compiled but audit_status is incomplete; "
                f"source_id={source_id}; audit_status={audit_status}"
            )
        if compile_status == "compiled" and not meaningful(compiled_into):
            findings.append(
                "FAIL SOURCES compile_status=compiled but compiled_into is empty; "
                f"source_id={source_id}"
            )
    return findings


def main() -> int:
    has_header, rows = manifest_rows(sys.stdin.read())
    if not has_header:
        print("FAIL SOURCES manifest table header missing")
        return 0
    findings = lint(rows)
    if findings:
        print("\n".join(findings))
    else:
        print("OK SOURCES manifest state is consistent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
