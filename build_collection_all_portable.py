#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent
MASTER_JSON = REPO_ROOT / "master.json"
COLLECTION_JSON = REPO_ROOT / "collection-all.json"
BASE_URL = "https://scholarbo.github.io/soseki-manuscripts"


def clean(value) -> str:
    if value is None:
        return ""
    return str(value).strip()


def load_json(path: Path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def main():
    if not MASTER_JSON.exists():
        raise FileNotFoundError(f'缺少文件: {MASTER_JSON}')

    rows = load_json(MASTER_JSON)
    items = []
    for row in rows:
        title = clean(row.get('title'))
        manifests = row.get('manifest_list') or []
        for m in manifests:
            manifest_url = clean(m.get('manifest_url'))
            witness_id = clean(m.get('witness_id'))
            if not manifest_url:
                continue
            label = title
            if witness_id and len(manifests) > 1:
                if '第1版' not in label and '第2版' not in label and 'w0' not in label:
                    suffix = witness_id.replace('w', '')
                    try:
                        n = int(suffix)
                        label = f"{title} 第{n}版"
                    except Exception:
                        label = f"{title} {witness_id}"
            items.append({
                'id': manifest_url,
                'type': 'Manifest',
                'label': {'ja': [label or Path(manifest_url).stem]},
            })

    collection = {
        '@context': 'http://iiif.io/api/presentation/3/context.json',
        'id': f'{BASE_URL}/collection-all.json',
        'type': 'Collection',
        'label': {'ja': ['漱石漢詩原稿・草稿コレクション']},
        'summary': {'ja': ['master.json に基づいて自動生成された manifest コレクション。']},
        'items': items,
    }

    with open(COLLECTION_JSON, 'w', encoding='utf-8') as f:
        json.dump(collection, f, ensure_ascii=False, indent=2)

    print(f'已更新: {COLLECTION_JSON}')
    print(f'共写入 {len(items)} 个 manifest 引用')


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(f'错误: {e}', file=sys.stderr)
        sys.exit(1)
