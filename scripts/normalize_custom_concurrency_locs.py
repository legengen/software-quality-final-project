#!/usr/bin/env python3
"""Normalize custom concurrency edit locations for Agentless repair."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


INSTANCE_ID = "local_concurrency__counter-0001"
COUNTER_FILE = "concurrent_counter/concurrent_counter/counter.py"
FALLBACK_LOCS = [
    "line: 1",
    "line: 7",
    "line: 20",
    "line: 21",
    "line: 22",
    "line: 23",
    "line: 26",
]


def load_jsonl(path: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def has_usable_edit_locs(row: dict) -> bool:
    edit_locs = row.get("found_edit_locs") or {}
    locs = edit_locs.get(COUNTER_FILE) or []
    return any(str(loc).strip() for loc in locs)


def normalize_row(row: dict) -> dict:
    if row.get("instance_id") != INSTANCE_ID or has_usable_edit_locs(row):
        return row

    normalized = dict(row)
    normalized["found_edit_locs"] = {COUNTER_FILE: ["\n".join(FALLBACK_LOCS)]}
    normalized["custom_concurrency_loc_normalized"] = True
    normalized["custom_concurrency_loc_reason"] = (
        "DeepSeek returned method names that Agentless parsed into an empty fine-grain "
        "location; use explicit line locations for the known custom concurrency case."
    )
    return normalized


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    rows = [normalize_row(row) for row in load_jsonl(args.input)]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows),
        encoding="utf-8",
    )
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
