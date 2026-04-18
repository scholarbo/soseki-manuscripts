#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations
import json
import re
import sys
from pathlib import Path
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent
IMAGES_DIR = REPO_ROOT / "images"
MANIFEST_DIR = REPO_ROOT / "manifests"
MASTER_JSON = REPO_ROOT / "master.json"
COMPLETED_TEXTS_JSON = REPO_ROOT / "completed_texts.json"

BASE_URL = "https://scholarbo.github.io/soseki-manuscripts"
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff"}

def clean(s) -> str:
    if s is None:
        return ""
    return str(s).strip()

def load_json(path: Path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def scan_images_recursive():
    found = {}
    for p in IMAGES_DIR.rglob("*"):
        if p.is_file() and p.suffix.lower() in IMAGE_EXTS:
            rel = p.relative_to(IMAGES_DIR).as_posix()
            stem = p.stem
            found[rel] = {"path": p, "rel": rel, "stem": stem}
    return found

def parse_stem(stem: str):
    m = re.match(r"^(\d{3})(?:-(w\d+))?$", stem, flags=re.I)
    if not m:
        return None
    work_id = m.group(1)
    witness_id = (m.group(2) or "w01").lower()
    return work_id, witness_id

def image_size(path: Path):
    with Image.open(path) as im:
        return im.size

def build_metadata(master_entry, witness_id):
    md = []
    def add(label, value):
        if clean(value):
            md.append({"label": {"ja": [label]}, "value": {"ja": [clean(value)]}})
    add("作品ID", master_entry.get("id"))
    add("作品名", master_entry.get("title"))
    add("Witness", witness_id)
    add("source", master_entry.get("source"))
    add("date_year", master_entry.get("date_year"))
    add("date_month", master_entry.get("date_month"))
    add("date_day", master_entry.get("date_day"))
    return md

def main():
    if not IMAGES_DIR.exists():
        raise FileNotFoundError(f"缺少目录: {IMAGES_DIR}")
    if not MASTER_JSON.exists():
        raise FileNotFoundError(f"缺少文件: {MASTER_JSON}")
    if not COMPLETED_TEXTS_JSON.exists():
        raise FileNotFoundError(f"缺少文件: {COMPLETED_TEXTS_JSON}")

    MANIFEST_DIR.mkdir(parents=True, exist_ok=True)

    images = scan_images_recursive()
    print(f"已递归扫描到图片文件 {len(images)} 个")

    master_rows = load_json(MASTER_JSON)
    completed_rows = load_json(COMPLETED_TEXTS_JSON)
    print(f"master.json 条目数: {len(master_rows)}")
    print(f"completed_texts.json 条目数: {len(completed_rows)}")

    master_map = {clean(x.get("id")): x for x in master_rows}
    text_map = {clean(x.get("id")): x for x in completed_rows}

    count = 0
    for rel, info in sorted(images.items()):
        parsed = parse_stem(info["stem"])
        if not parsed:
            continue
        work_id, witness_id = parsed
        img_path = info["path"]
        width, height = image_size(img_path)

        master_entry = master_map.get(work_id, {})
        text_entry = text_map.get(work_id, {})
        manifest_id = f"manifest-{work_id}-{witness_id}"
        manifest_url = f"{BASE_URL}/manifests/{manifest_id}.json"
        image_url = f"{BASE_URL}/images/{rel}"

        canvas_id = f"{manifest_url}/canvas/1"
        anno_page_id = f"{manifest_url}/page/1"
        anno_id = f"{manifest_url}/annotation/1"

        label = clean(master_entry.get("title")) or clean(text_entry.get("title")) or work_id
        original_text = clean(text_entry.get("original")) or clean(text_entry.get("original_text"))
        kundoku_text = clean(text_entry.get("kundoku")) or clean(text_entry.get("kundoku_text"))

        manifest = {
            "@context": "http://iiif.io/api/presentation/3/context.json",
            "id": manifest_url,
            "type": "Manifest",
            "label": {"ja": [label]},
            "metadata": build_metadata(master_entry, witness_id),
            "items": [
                {
                    "id": canvas_id,
                    "type": "Canvas",
                    "width": width,
                    "height": height,
                    "label": {"ja": [label]},
                    "items": [
                        {
                            "id": anno_page_id,
                            "type": "AnnotationPage",
                            "items": [
                                {
                                    "id": anno_id,
                                    "type": "Annotation",
                                    "motivation": "painting",
                                    "target": canvas_id,
                                    "body": {
                                        "id": image_url,
                                        "type": "Image",
                                        "format": "image/jpeg",
                                        "width": width,
                                        "height": height,
                                    },
                                }
                            ],
                        }
                    ],
                }
            ],
        }

        summary_lines = []
        if original_text:
            summary_lines.append("【原文】")
            summary_lines.append(original_text)
        if kundoku_text:
            summary_lines.append("")
            summary_lines.append("【訓読】")
            summary_lines.append(kundoku_text)
        if summary_lines:
            manifest["summary"] = {"ja": ["\n".join(summary_lines)]}

        out_path = MANIFEST_DIR / f"{manifest_id}.json"
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)

        print(f"已生成: {out_path}")
        count += 1

    print(f"共生成 {count} 个 manifest")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"错误: {e}", file=sys.stderr)
        sys.exit(1)
