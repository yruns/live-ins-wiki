#!/usr/bin/env python3
"""把常见本地文件抽取成 Markdown，供 Lark LLM Wiki 编译使用。"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime
from pathlib import Path
from typing import Iterable
from xml.etree import ElementTree


TEXT_EXTS = {".md", ".markdown", ".txt", ".log"}
CSV_EXTS = {".csv", ".tsv"}
DOCX_NS = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
PPTX_NS = {"a": "http://schemas.openxmlformats.org/drawingml/2006/main"}


def read_text(path: Path) -> str:
    data = path.read_bytes()
    for encoding in ("utf-8", "utf-8-sig", "gb18030", "latin-1"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace")


def trim(text: str, max_chars: int) -> str:
    if max_chars <= 0 or len(text) <= max_chars:
        return text
    omitted = len(text) - max_chars
    return text[:max_chars].rstrip() + f"\n\n> 已截断，剩余 {omitted} 个字符未写入。"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def sha256_text(text: str) -> str:
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()


def redact_local_path(path: Path) -> str:
    home = Path.home().resolve()
    try:
        return "~/" + str(path.resolve().relative_to(home))
    except ValueError:
        return str(path)


def extraction_profile(kind: str) -> tuple[str, str]:
    if kind in {"csv", "tsv", "xlsx"}:
        return "text_plus_tables", "images, charts, comments, formulas"
    if kind == "pdf":
        return "text_only", "images, charts, annotations, scanned_pages_without_ocr"
    if kind == "pptx":
        return "text_only", "images, charts, speaker_notes, embedded_objects"
    if kind == "docx":
        return "text_only", "images, charts, comments, footnotes, embedded_objects"
    if kind in {"doc", "ppt"}:
        return "text_only", "images, charts, comments, speaker_notes, embedded_objects"
    return "text_only", "none_detected"


def markdown_header(path: Path, kind: str, extracted_text: str, include_local_path: bool) -> str:
    stat = path.stat()
    completeness, missing = extraction_profile(kind)
    lines = [
        f"# {path.name}",
        "",
        "## 本地抽取元数据",
        "",
        "- source_type: local_file",
        f"- original_filename: {path.name}",
        f"- file_type: {kind}",
        f"- size_bytes: {stat.st_size}",
        f"- sha256_file: {sha256_file(path)}",
        f"- sha256_extracted_text: {sha256_text(extracted_text)}",
        f"- extraction_completeness: {completeness}",
        f"- missing_modalities: {missing}",
    ]
    if include_local_path:
        lines.append(f"- local_path: {redact_local_path(path)}")
    lines.extend(
        [
            f"- extracted_at: {datetime.now().astimezone().isoformat(timespec='seconds')}",
            "- extractor: scripts/extract_local_file.py",
            "",
        ]
    )
    return "\n".join(lines)


def csv_to_markdown(path: Path, max_rows: int) -> str:
    delimiter = "\t" if path.suffix.lower() == ".tsv" else ","
    rows: list[list[str]] = []
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f, delimiter=delimiter)
        for idx, row in enumerate(reader):
            if idx > max_rows:
                break
            rows.append([cell.strip() for cell in row])
    if not rows:
        return "_空表格_"

    width = max(len(row) for row in rows)
    rows = [row + [""] * (width - len(row)) for row in rows]
    header = rows[0]
    body = rows[1:]

    def esc(cell: str) -> str:
        return cell.replace("|", "\\|").replace("\n", " ")

    lines = [
        "| " + " | ".join(esc(cell) for cell in header) + " |",
        "| " + " | ".join("---" for _ in header) + " |",
    ]
    lines.extend("| " + " | ".join(esc(cell) for cell in row) + " |" for row in body)
    if len(body) >= max_rows:
        lines.append(f"\n> 表格仅展示前 {max_rows} 行。")
    return "\n".join(lines)


def xlsx_to_markdown(path: Path, max_rows: int) -> str:
    try:
        import openpyxl  # type: ignore
    except Exception:
        return xlsx_text_fallback(path)

    workbook = openpyxl.load_workbook(path, read_only=True, data_only=True)
    parts = []
    for sheet in workbook.worksheets:
        parts.append(f"## Sheet: {sheet.title}\n")
        rows = []
        for idx, row in enumerate(sheet.iter_rows(values_only=True), start=1):
            if idx > max_rows:
                break
            rows.append(["" if cell is None else str(cell) for cell in row])
        if rows:
            tmp = path.with_suffix(".csv")
            width = max(len(row) for row in rows)
            rows = [row + [""] * (width - len(row)) for row in rows]
            header = rows[0]
            lines = [
                "| " + " | ".join(cell.replace("|", "\\|") for cell in header) + " |",
                "| " + " | ".join("---" for _ in header) + " |",
            ]
            for row in rows[1:]:
                lines.append("| " + " | ".join(cell.replace("|", "\\|") for cell in row) + " |")
            if len(rows) >= max_rows:
                lines.append(f"\n> Sheet 仅展示前 {max_rows} 行。")
            parts.append("\n".join(lines))
        else:
            parts.append("_空 Sheet_")
    return "\n\n".join(parts)


def xlsx_text_fallback(path: Path) -> str:
    texts = []
    with zipfile.ZipFile(path) as zf:
        for name in sorted(zf.namelist()):
            if name.startswith("xl/worksheets/") and name.endswith(".xml"):
                root = ElementTree.fromstring(zf.read(name))
                values = [elem.text or "" for elem in root.iter() if elem.text and elem.text.strip()]
                texts.append(f"## {name}\n\n" + "\n".join(values))
    return "\n\n".join(texts) if texts else "_未抽取到可读文本_"


def docx_to_markdown(path: Path) -> str:
    with zipfile.ZipFile(path) as zf:
        xml = zf.read("word/document.xml")
    root = ElementTree.fromstring(xml)
    lines = []
    for paragraph in root.findall(".//w:p", DOCX_NS):
        texts = [node.text or "" for node in paragraph.findall(".//w:t", DOCX_NS)]
        line = "".join(texts).strip()
        if line:
            lines.append(line)
    return "\n\n".join(lines) if lines else "_未抽取到可读文本_"


def pptx_to_markdown(path: Path) -> str:
    parts = []
    with zipfile.ZipFile(path) as zf:
        slide_names = sorted(
            name
            for name in zf.namelist()
            if name.startswith("ppt/slides/slide") and name.endswith(".xml")
        )
        for idx, name in enumerate(slide_names, start=1):
            root = ElementTree.fromstring(zf.read(name))
            texts = [node.text or "" for node in root.findall(".//a:t", PPTX_NS)]
            body = "\n".join(text.strip() for text in texts if text and text.strip())
            parts.append(f"## Slide {idx}\n\n{body or '_空白页_'}")
    return "\n\n".join(parts) if parts else "_未抽取到可读文本_"


def pdf_to_markdown(path: Path) -> str:
    try:
        from pypdf import PdfReader  # type: ignore

        reader = PdfReader(str(path))
        parts = []
        for idx, page in enumerate(reader.pages, start=1):
            text = page.extract_text() or ""
            parts.append(f"## Page {idx}\n\n{text.strip() or '_未抽取到文本_'}")
        return "\n\n".join(parts)
    except Exception as exc:
        if shutil.which("pdftotext"):
            with tempfile.NamedTemporaryFile(suffix=".txt") as tmp:
                subprocess.run(["pdftotext", str(path), tmp.name], check=True)
                return read_text(Path(tmp.name))
        return f"_PDF 文本抽取失败: {exc}_"


def office_legacy_to_markdown(path: Path) -> str:
    if not shutil.which("textutil"):
        return "_缺少可转换旧版 Office 文件的本地工具 textutil_"
    result = subprocess.run(
        ["textutil", "-convert", "txt", "-stdout", str(path)],
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        message = result.stderr.strip() or "textutil 转换失败"
        return f"_{message}_"
    return result.stdout


def json_to_markdown(path: Path) -> str:
    value = json.loads(read_text(path))
    return "```json\n" + json.dumps(value, ensure_ascii=False, indent=2) + "\n```"


def extract_body(path: Path, max_rows: int) -> tuple[str, str]:
    ext = path.suffix.lower()
    if ext in TEXT_EXTS:
        return ext.lstrip(".") or "text", read_text(path)
    if ext in CSV_EXTS:
        return ext.lstrip("."), csv_to_markdown(path, max_rows)
    if ext == ".xlsx":
        return "xlsx", xlsx_to_markdown(path, max_rows)
    if ext == ".docx":
        return "docx", docx_to_markdown(path)
    if ext == ".pptx":
        return "pptx", pptx_to_markdown(path)
    if ext == ".pdf":
        return "pdf", pdf_to_markdown(path)
    if ext in {".doc", ".ppt"}:
        return ext.lstrip("."), office_legacy_to_markdown(path)
    if ext == ".json":
        return "json", json_to_markdown(path)
    return "unknown", f"_暂不支持该文件类型: {ext or '(no extension)'}_"


def main() -> int:
    parser = argparse.ArgumentParser(description="把本地文件抽取成 Markdown")
    parser.add_argument("file", type=Path)
    parser.add_argument("-o", "--output", type=Path)
    parser.add_argument("--max-rows", type=int, default=200)
    parser.add_argument("--max-chars", type=int, default=200_000)
    parser.add_argument("--include-local-path", action="store_true", help="写入脱敏后的本机路径，仅用于本地调试")
    args = parser.parse_args()

    path = args.file.expanduser().resolve()
    if not path.exists():
        print(f"文件不存在: {path}", file=sys.stderr)
        return 2
    if not path.is_file():
        print(f"不是普通文件: {path}", file=sys.stderr)
        return 2

    kind, body = extract_body(path, args.max_rows)
    body = body.strip()
    markdown = markdown_header(path, kind, body, args.include_local_path) + trim(body, args.max_chars) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(markdown, encoding="utf-8")
    else:
        sys.stdout.write(markdown)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
