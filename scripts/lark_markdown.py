#!/usr/bin/env python3
"""Helpers for Lark-flavored Markdown exports."""

from __future__ import annotations

import re
from html.parser import HTMLParser


class _LarkTableParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.rows: list[list[str]] = []
        self._row: list[str] | None = None
        self._cell: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "lark-tr":
            self._row = []
        elif tag == "lark-td" and self._row is not None:
            self._cell = []

    def handle_data(self, data: str) -> None:
        if self._cell is not None:
            self._cell.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "lark-td" and self._row is not None and self._cell is not None:
            self._row.append(" ".join("".join(self._cell).split()) or "-")
            self._cell = None
        elif tag == "lark-tr" and self._row is not None:
            self.rows.append(self._row)
            self._row = None


def _escape_cell(value: str) -> str:
    return (value or "-").replace("\n", " ").replace("|", "\\|").strip() or "-"


def _render_markdown_table(rows: list[list[str]]) -> str:
    if not rows:
        return ""
    width = max(len(row) for row in rows)
    padded = [row + ["-"] * (width - len(row)) for row in rows]
    rendered = ["| " + " | ".join(_escape_cell(cell) for cell in padded[0]) + " |"]
    rendered.append("| " + " | ".join("---" for _ in range(width)) + " |")
    rendered.extend("| " + " | ".join(_escape_cell(cell) for cell in row) + " |" for row in padded[1:])
    return "\n".join(rendered)


def normalize_lark_tables(text: str) -> str:
    """Convert Lark `<lark-table>` blocks in exported Markdown to pipe tables."""

    def replace(match: re.Match[str]) -> str:
        parser = _LarkTableParser()
        parser.feed(match.group(0))
        rendered = _render_markdown_table(parser.rows)
        return rendered if rendered else match.group(0)

    return re.sub(r"<lark-table\b[\s\S]*?</lark-table>", replace, text)


def embedded_sheet_tokens(text: str) -> list[str]:
    """Return unique sheet tokens referenced by Lark `<sheet token=...>` embeds."""

    seen: set[str] = set()
    tokens: list[str] = []
    for match in re.finditer(r"<sheet\b[^>]*\btoken=(?:\"([^\"]+)\"|'([^']+)'|([^\s>]+))[^>]*>", text):
        token = next(group for group in match.groups() if group)
        if token not in seen:
            seen.add(token)
            tokens.append(token)
    return tokens


def canonical_ref_key(value: str) -> str:
    """Normalize a ref cell to the logical key used by INDEX/SOURCES upserts."""

    text = (value or "").strip().replace("<br>", "\n").split("\n", 1)[0].strip()
    markdown = re.fullmatch(r"\[([^\]]+)\]\([^)]+\)", text)
    if markdown:
        return markdown.group(1).strip()
    hyperlink = re.fullmatch(r"=?HYPERLINK\(\s*\"[^\"]+\"\s*,\s*\"([^\"]+)\"\s*\)", text, flags=re.I)
    if hyperlink:
        return hyperlink.group(1).strip()
    return text
