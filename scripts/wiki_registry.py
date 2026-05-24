#!/usr/bin/env python3
"""Manage recently used Lark LLM Wiki roots under ~/.lark-llm-wiki."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import uuid
from pathlib import Path
from typing import Any


DEFAULT_HOME = Path.home() / ".lark-llm-wiki"
REGISTRY_FILE = "registry.json"
MAX_WIKIS = 50


def now() -> str:
    return dt.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")


def registry_path(home: str | None) -> Path:
    if home:
        return Path(home).expanduser() / REGISTRY_FILE
    return Path(os.environ.get("LARK_LLM_WIKI_HOME", DEFAULT_HOME)).expanduser() / REGISTRY_FILE


def empty_registry() -> dict[str, Any]:
    return {"version": 1, "updated_at": None, "current": None, "wikis": []}


def load(path: Path) -> dict[str, Any]:
    if not path.exists():
        return empty_registry()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"registry is not valid JSON: {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"registry root must be an object: {path}")
    data.setdefault("version", 1)
    data.setdefault("updated_at", None)
    data.setdefault("current", None)
    data.setdefault("wikis", [])
    if not isinstance(data["wikis"], list):
        raise SystemExit(f"registry wikis must be an array: {path}")
    return data


def save(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.{uuid.uuid4().hex}.tmp")
    try:
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        tmp.replace(path)
    finally:
        tmp.unlink(missing_ok=True)


def normalize_entry(entry: dict[str, Any]) -> dict[str, Any]:
    root_node = str(entry["root_node"])
    root_url = str(entry.get("root_url") or f"https://bytedance.larkoffice.com/wiki/{root_node}")
    return {
        "id": root_node,
        "name": str(entry.get("name") or root_node),
        "root_url": root_url,
        "space_id": str(entry.get("space_id") or ""),
        "root_node": root_node,
        "last_accessed_at": str(entry.get("last_accessed_at") or now()),
        "access_count": int(entry.get("access_count") or 0),
        "origin": str(entry.get("origin") or root_url),
    }


def record(data: dict[str, Any], entry: dict[str, Any], timestamp: str) -> dict[str, Any]:
    incoming = normalize_entry(entry)
    existing_by_id = {str(item.get("id") or item.get("root_node")): normalize_entry(item) for item in data["wikis"]}
    current = existing_by_id.get(incoming["id"], incoming)
    current.update(
        {
            "name": incoming["name"],
            "root_url": incoming["root_url"],
            "space_id": incoming["space_id"],
            "root_node": incoming["root_node"],
            "last_accessed_at": timestamp,
            "origin": incoming["origin"],
            "access_count": int(current.get("access_count") or 0) + 1,
        }
    )
    existing_by_id[incoming["id"]] = current
    wikis = sorted(existing_by_id.values(), key=lambda item: item.get("last_accessed_at") or "", reverse=True)
    data["wikis"] = wikis[:MAX_WIKIS]
    data["current"] = incoming["id"]
    data["updated_at"] = timestamp
    return data


def current_entry(data: dict[str, Any]) -> dict[str, Any] | None:
    current_id = data.get("current")
    for item in data["wikis"]:
        normalized = normalize_entry(item)
        if normalized["id"] == current_id:
            return normalized
    if data["wikis"]:
        return normalize_entry(data["wikis"][0])
    return None


def matches(entry: dict[str, Any], selector: str) -> bool:
    lowered = selector.lower()
    fields = [entry["id"], entry["name"], entry["root_url"], entry["root_node"], entry["space_id"]]
    return any(str(field).lower() == lowered for field in fields)


def resolve(data: dict[str, Any], selector: str | None) -> dict[str, Any]:
    if selector is None or selector in {"", "-", "@current", "@recent", "current", "recent", "default"}:
        entry = current_entry(data)
        if entry is None:
            raise SystemExit("no recent Lark LLM Wiki registered")
        return entry
    candidates = [normalize_entry(item) for item in data["wikis"] if matches(normalize_entry(item), selector)]
    if not candidates:
        raise SystemExit(f"no Lark LLM Wiki matches selector: {selector}")
    if len(candidates) > 1:
        names = ", ".join(f"{item['name']}({item['root_node']})" for item in candidates)
        raise SystemExit(f"ambiguous Lark LLM Wiki selector {selector}: {names}")
    return candidates[0]


def emit(entry: dict[str, Any] | dict[str, list[Any]], field: str | None) -> None:
    if field:
        value = entry.get(field) if isinstance(entry, dict) else None
        if value is None:
            raise SystemExit(f"unknown field: {field}")
        sys.stdout.write(str(value) + "\n")
    else:
        sys.stdout.write(json.dumps(entry, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Manage ~/.lark-llm-wiki registry")
    parser.add_argument("--home", default=None, help="Registry directory, default ~/.lark-llm-wiki")
    sub = parser.add_subparsers(dest="command", required=True)

    record_parser = sub.add_parser("record")
    record_parser.add_argument("--root-url", required=True)
    record_parser.add_argument("--name", required=True)
    record_parser.add_argument("--space-id", required=True)
    record_parser.add_argument("--root-node", required=True)
    record_parser.add_argument("--origin", default="")
    record_parser.add_argument("--now", default=None)

    list_parser = sub.add_parser("list")
    list_parser.add_argument("--field", default=None)

    current_parser = sub.add_parser("current")
    current_parser.add_argument("--field", default=None)

    resolve_parser = sub.add_parser("resolve")
    resolve_parser.add_argument("selector", nargs="?")
    resolve_parser.add_argument("--field", default=None)

    forget_parser = sub.add_parser("forget")
    forget_parser.add_argument("selector")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    path = registry_path(args.home)
    data = load(path)
    if args.command == "record":
        timestamp = args.now or now()
        data = record(
            data,
            {
                "root_url": args.root_url,
                "name": args.name,
                "space_id": args.space_id,
                "root_node": args.root_node,
                "origin": args.origin or args.root_url,
            },
            timestamp,
        )
        save(path, data)
        emit(resolve(data, args.root_node), None)
    elif args.command == "list":
        emit({"home": str(path.parent), "wikis": [normalize_entry(item) for item in data["wikis"]]}, args.field)
    elif args.command == "current":
        entry = current_entry(data)
        if entry is None:
            raise SystemExit("no recent Lark LLM Wiki registered")
        emit(entry, args.field)
    elif args.command == "resolve":
        emit(resolve(data, args.selector), args.field)
    elif args.command == "forget":
        entry = resolve(data, args.selector)
        data["wikis"] = [item for item in data["wikis"] if normalize_entry(item)["id"] != entry["id"]]
        data["current"] = normalize_entry(data["wikis"][0])["id"] if data["wikis"] else None
        data["updated_at"] = now()
        save(path, data)
        emit({"forgot": entry, "current": data["current"]}, None)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
