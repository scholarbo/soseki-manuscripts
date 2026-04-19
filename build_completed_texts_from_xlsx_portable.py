#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build completed_texts.json from soseki-manuscripts-text-master.xlsx.
Primary sheet: 主页完成テクスト
"""

from __future__ import annotations
import json
from pathlib import Path
import sys

try:
    import openpyxl
except ImportError:
    print("Missing dependency: openpyxl", file=sys.stderr)
    raise

REPO = Path(__file__).resolve().parent
XLSX = REPO / "soseki-manuscripts-text-master.xlsx"
OUTPUT = REPO / "completed_texts.json"
SHEET_NAME = "主页完成テクスト"

REQUIRED_HEADERS = ["id", "title", "source", "text", "text_kanbun", "body", "text_block"]

def norm(v):
    if v is None:
        return ""
    if isinstance(v, str):
        return v.replace("\r\n", "\n").replace("\r", "\n").strip()
    return str(v).strip()

def main():
    if not XLSX.exists():
        raise FileNotFoundError(f"Missing workbook: {XLSX}")

    wb = openpyxl.load_workbook(XLSX, data_only=True)
    if SHEET_NAME not in wb.sheetnames:
        raise KeyError(f"Missing sheet: {SHEET_NAME}")

    ws = wb[SHEET_NAME]
    headers = [norm(ws.cell(1, c).value) for c in range(1, ws.max_column + 1)]
    header_map = {h: i + 1 for i, h in enumerate(headers) if h}

    missing = [h for h in REQUIRED_HEADERS if h not in header_map]
    if missing:
        raise KeyError(f"Missing headers in {SHEET_NAME}: {', '.join(missing)}")

    rows = []
    seen = set()

    for r in range(2, ws.max_row + 1):
        row = {h: ws.cell(r, header_map[h]).value for h in header_map.keys()}
        work_id = norm(row.get("id") or row.get("work_id"))
        if not work_id:
            continue

        status = norm(row.get("status")).lower()
        if status and status not in {"ready", "published", "ok", "1", "true"}:
            continue

        item = {
            "id": work_id.zfill(3),
            "title": norm(row.get("title")),
            "text_block": norm(row.get("text_block") or row.get("text") or row.get("body") or row.get("text_kanbun")),
            "source": norm(row.get("source")),
            "text": norm(row.get("text") or row.get("body") or row.get("text_kanbun") or row.get("text_block")),
            "text_kanbun": norm(row.get("text_kanbun") or row.get("text") or row.get("text_block")),
            "body": norm(row.get("body") or row.get("text") or row.get("text_kanbun") or row.get("text_block")),
        }

        # keep a few extra fields when available
        for extra in ["work_id", "witness_id", "version_id", "display_mode_default", "title_raw", "title_kundoku", "text_kundoku", "note"]:
            val = norm(row.get(extra))
            if val:
                item[extra] = val

        if item["id"] in seen:
            raise ValueError(f"Duplicate id in {SHEET_NAME}: {item['id']}")
        seen.add(item["id"])
        rows.append(item)

    rows.sort(key=lambda x: x["id"])

    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)

    print(f"Wrote {OUTPUT.name} ({len(rows)} items) from {XLSX.name} / {SHEET_NAME}")

if __name__ == "__main__":
    main()
