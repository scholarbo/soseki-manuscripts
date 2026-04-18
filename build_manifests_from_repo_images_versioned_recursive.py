#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
以本地 GitHub 仓库目录为基准，递归扫描 images/ 目录并生成 IIIF manifest
- 扫描目录：/Users/fengbo/GitHub/soseki-manuscripts/images
- 生成目录：/Users/fengbo/GitHub/soseki-manuscripts/manifests
- master.json：/Users/fengbo/GitHub/soseki-manuscripts/master.json
- completed_texts.json：/Users/fengbo/GitHub/soseki-manuscripts/completed_texts.json

支持：
    001-w01.jpg             -> manifest-001-w01.json
    067/067-w01.jpg         -> manifest-067-w01.json
    067/067-w02.jpg         -> manifest-067-w02.json

说明：
- 图片 URL 统一写为：
    https://scholarbo.github.io/soseki-manuscripts/images/...
- metadata 按基础作品号读取，如 067-w01 / 067-w02 都按 067 去读
"""

from __future__ import annotations
import json
import re
from pathlib import Path
from PIL import Image

REPO_ROOT = Path("/Users/fengbo/GitHub/soseki-manuscripts")
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

def sort_key(path: Path):
    rel = path.relative_to(IMAGES_DIR).as_posix()
    stem = path.stem
    m = re.match(r"^(\d+)(.*)$", stem)
    if m:
        return (int(m.group(1)), m.group(2), rel)
    return (10**9, stem, rel)

def parse_stem(stem: str) -> tuple[str, str, str]:
    stem = clean(stem)
    m = re.match(r"^(\d+)(.*)$", stem)
    if not m:
        return stem, "", stem
    work_id = m.group(1).zfill(3)
    rest = clean(m.group(2))
    variant_suffix = rest if rest else ""
    manifest_key = f"{work_id}{variant_suffix}"
    return work_id, variant_suffix, manifest_key

def load_json_map(path: Path) -> dict:
    if not path.exists():
        return {}
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    result = {}
    if isinstance(data, list):
        for item in data:
            item_id = clean(item.get("id", ""))
            if item_id:
                result[item_id.zfill(3)] = item
    elif isinstance(data, dict):
        # 兼容以对象形式保存的情况
        for k, v in data.items():
            result[str(k).zfill(3)] = v
    return result

def build_metadata(work_id: str, variant_suffix: str, master_map: dict, text_map: dict) -> list:
    master_info = master_map.get(work_id, {})
    text_info = text_map.get(work_id, {})

    metadata = []

    title = clean(master_info.get("title", "")) or clean(text_info.get("title", ""))
    source = clean(master_info.get("source", ""))
    version = clean(master_info.get("version", ""))
    date_day = clean(master_info.get("date_day", ""))
    date_month = clean(master_info.get("date_month", ""))
    date_year = clean(master_info.get("date_year", ""))

    text_kanbun = clean(text_info.get("text_kanbun", ""))
    body = clean(text_info.get("body", ""))

    def add(label: str, value: str):
        if value:
            metadata.append({
                "label": {"ja": [label]},
                "value": {"ja": [value.replace("\n", "<br/>")]}
            })

    add("題名", title)

    if date_day:
        add("制作日", date_day)
    elif date_month:
        add("制作月", date_month)
    elif date_year:
        add("制作年", date_year)

    add("所蔵", source)

    effective_version = version
    if variant_suffix:
        variant_label = variant_suffix.lstrip("-")
        effective_version = f"{effective_version} / {variant_label}" if effective_version else variant_label
    add("版本", effective_version)

    add("漢詩本文", text_kanbun)
    add("本文・訓読", body)

    return metadata

def build_manifest(work_id: str, variant_suffix: str, manifest_key: str, image_path: Path, master_map: dict, text_map: dict) -> dict:
    with Image.open(image_path) as im:
        width, height = im.size

    base_title = clean(master_map.get(work_id, {}).get("title", "")) or clean(text_map.get(work_id, {}).get("title", "")) or work_id
    display_title = base_title
    if variant_suffix:
        display_title = f"{base_title} ({variant_suffix.lstrip('-')})"

    rel_path = image_path.relative_to(IMAGES_DIR).as_posix()
    image_url = f"{BASE_URL}/images/{rel_path}"

    manifest_id = f"manifest-{manifest_key}"
    canvas_id = f"canvas-{manifest_key}"
    annotation_page_id = f"page-{manifest_key}"
    annotation_id = f"anno-{manifest_key}"

    fmt = image_path.suffix.lower().lstrip(".")
    if fmt == "jpg":
        fmt = "jpeg"

    return {
        "@context": "http://iiif.io/api/presentation/3/context.json",
        "id": f"{BASE_URL}/manifests/{manifest_id}.json",
        "type": "Manifest",
        "label": {"ja": [display_title]},
        "metadata": build_metadata(work_id, variant_suffix, master_map, text_map),
        "items": [
            {
                "id": f"{BASE_URL}/manifests/{canvas_id}",
                "type": "Canvas",
                "label": {"ja": [display_title]},
                "height": height,
                "width": width,
                "items": [
                    {
                        "id": f"{BASE_URL}/manifests/{annotation_page_id}",
                        "type": "AnnotationPage",
                        "items": [
                            {
                                "id": f"{BASE_URL}/manifests/{annotation_id}",
                                "type": "Annotation",
                                "motivation": "painting",
                                "body": {
                                    "id": image_url,
                                    "type": "Image",
                                    "format": f"image/{fmt}",
                                    "height": height,
                                    "width": width
                                },
                                "target": f"{BASE_URL}/manifests/{canvas_id}"
                            }
                        ]
                    }
                ]
            }
        ]
    }

def main():
    if not IMAGES_DIR.exists():
        raise SystemExit(f"未找到图片目录：{IMAGES_DIR}")

    MANIFEST_DIR.mkdir(parents=True, exist_ok=True)

    files = [p for p in IMAGES_DIR.rglob("*") if p.is_file() and p.suffix.lower() in IMAGE_EXTS]
    files.sort(key=sort_key)

    if not files:
        raise SystemExit("images 及其子目录中未找到带图片扩展名的文件。")

    master_map = load_json_map(MASTER_JSON)
    text_map = load_json_map(COMPLETED_TEXTS_JSON)

    print(f"已递归扫描到图片文件 {len(files)} 个")
    print(f"master.json 条目数: {len(master_map)}")
    print(f"completed_texts.json 条目数: {len(text_map)}")

    count = 0
    for img in files:
        work_id, variant_suffix, manifest_key = parse_stem(img.stem)
        manifest = build_manifest(work_id, variant_suffix, manifest_key, img, master_map, text_map)
        out_path = MANIFEST_DIR / f"manifest-{manifest_key}.json"
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)
        count += 1
        print(f"已生成: {out_path}")

    print(f"共生成 {count} 个 manifest")

if __name__ == "__main__":
    main()
