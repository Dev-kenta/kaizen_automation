# GitHub PR スクリーンショットツール

Playwrightを使用してGitHub PRのスクリーンショットを自動撮影するツールです。

## 機能

- CSVファイルから複数のPR番号を読み込み
- GitHub CLIの認証情報を利用した自動ログイン
- PRページ全体のスクリーンショット撮影
- 順次処理による安定した実行
- エラーハンドリングと処理結果の統計表示
- **スクリーンショットから自動PDF生成**

## 必要な環境

- Node.js (v14以上推奨)
- npm
- GitHub CLI (`gh`)

## セットアップ

### 1. 依存関係のインストール

```bash
cd pr_screenshot
npm install
```

### 2. Playwrightブラウザのインストール

```bash
npx playwright install chromium
```

### 3. GitHub CLIの認証

まだ認証していない場合は、以下のコマンドで認証してください：

```bash
gh auth login
```

## 使用方法

### CSVファイルの準備

PR番号を含むCSVファイルを用意してください。以下のような形式に対応しています：

**形式1: シンプルなPR番号リスト**
```csv
pr_number
1234
5678
9012
```

**形式2: git logの出力（#数字を自動抽出）**
```csv
hash,date,message
abc123,2025-01-14,Merge pull request #15703 from feature/branch
def456,2025-01-15,Merge pull request #15704 from fix/bug
```

このツールは各行から `#数字` の形式を自動的に検出してPR番号を抽出します。

### 実行

```bash
# デフォルトのCSVファイル（pr_list.csv）を使用
./run.sh

# カスタムCSVファイルを指定
./run.sh /path/to/custom_pr_list.csv

# または直接Node.jsスクリプトを実行
node screenshot_pr.js /Users/kataoka/Downloads/pr_list.csv
```

## 出力

### スクリーンショット

スクリーンショットは `screenshots/` ディレクトリに保存されます：

```
screenshots/
├── pr-15703.png
├── pr-15704.png
└── pr-15705.png
```

ファイル名形式: `pr-{PR番号}.png`

### PDF

スクリーンショット撮影完了後、各スクリーンショットから個別PDFが自動生成されます：

```
pr_screenshot/
├── screenshots/
│   ├── pr-15703.png
│   ├── pr-15704.png
│   └── pr-15705.png
└── pdfs/           ← PDF専用ディレクトリ
    ├── pr-15703.pdf
    ├── pr-15704.pdf
    └── pr-15705.pdf
```

- ファイル名形式: `pr-{PR番号}.pdf`
- 保存場所: `pdfs/` ディレクトリ（専用ディレクトリ）
- 内容: 各スクリーンショットが1ページのPDFとして生成

#### 手動でPDF生成する場合

既存のスクリーンショットからPDFを再生成したい場合：

```bash
cd pr_screenshot
node create_pdf.js
```

## 処理の流れ

1. GitHub CLIの認証確認
2. CSVファイルからPR番号を読み込み
3. Playwrightでブラウザを起動（初回はログイン必要）
4. GitHub認証状態を確認
5. 各PRに対して順次：
   - PRページにアクセス
   - ページ全体のスクリーンショットを撮影
   - `screenshots/pr-{番号}.png` に保存
6. 処理結果の統計を表示
7. 各スクリーンショットから個別PDFを自動生成
   - `screenshots/pr-{番号}.pdf` として保存

## 設定のカスタマイズ

`screenshot_pr.js` の定数を編集することで設定を変更できます：

```javascript
// 対象リポジトリ
const REPO = 'basicinc/formrun';

// スクリーンショット保存先
const SCREENSHOTS_DIR = path.join(__dirname, 'screenshots');

// デフォルトのCSVファイル
const DEFAULT_CSV_FILE = path.join(__dirname, 'pr_list.csv');
```

## トラブルシューティング

### GitHub CLIが認証されていないエラー

```bash
gh auth login
```

を実行して認証してください。

### Playwrightブラウザがインストールされていない

```bash
npx playwright install chromium
```

を実行してブラウザをインストールしてください。

### スクリーンショットが失敗する

- ネットワーク接続を確認してください
- PR番号が正しいか確認してください
- GitHubのレート制限に引っかかっている可能性があります（少し待ってから再実行）

## ライセンス

ISC
