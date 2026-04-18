# soseki-manuscripts

夏目漱石自筆の漢詩原稿・草稿コレクション用の IIIF / GitHub Pages プロジェクトです。

## 主要用途
- `master.xlsx` と `images_master.xlsx` から `master.json` を更新
- `images/` から `manifests/` を再生成
- GitHub リポジトリへ一括 push
- GitHub Pages で公開

## 推奨ディレクトリ構成
```text
soseki-manuscripts/
├── images/
├── manifests/
├── master.json
├── completed_texts.json
├── master.xlsx
├── images_master.xlsx
├── build_master_json_portable.py
├── build_manifests_portable.py
├── 改动后就双击.command
├── 新设备先点我.command
├── requirements.txt
├── .gitignore
└── README.md
```

## 初回セットアップ
### macOS / Linux
```bash
python3 -m pip install -r requirements.txt
chmod +x build_master_json_portable.py
chmod +x build_manifests_portable.py
chmod +x 改动后就双击.command
chmod +x 新设备先点我.command
```

または:

```bash
./新设备先点我.command
```

## 日常使用
### 変更対象
- `master.xlsx`
- `images_master.xlsx`
- `images/` 以下の画像

### 実行
```bash
./改动后就双击.command
```

このコマンドは自動で以下を行います。

1. `master.json` の更新
2. `manifests/` の更新
3. `git add -A`
4. `git commit`
5. `git push origin main`

## 別のPCで使う手順
```bash
git clone <your-repo-url>
cd soseki-manuscripts
./新设备先点我.command
./改动后就双击.command
```

## 必要環境
- Python 3
- Git
- GitHub push 権限
- Python パッケージ:
  - `openpyxl`
  - `Pillow`

## 注意
- `.auto_state/` はローカル状態保存用です。Git 管理しません。
- GitHub Pages の反映には通常 1〜2 分かかります。
- 画像や manifest 更新直後は、ブラウザで強制再読み込みすると確認しやすいです。

## トラブル時の確認
```bash
git status
python3 --version
python3 -m pip install -r requirements.txt
```
