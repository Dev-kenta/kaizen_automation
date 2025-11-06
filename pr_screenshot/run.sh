#!/bin/bash

set -e

# スクリプトのディレクトリに移動
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== GitHub PR スクリーンショットツール ==="
echo ""

# Node.jsのインストールチェック
if ! command -v node &> /dev/null; then
    echo -e "${RED}エラー: Node.jsがインストールされていません${NC}"
    echo "以下のURLからNode.jsをインストールしてください:"
    echo "  https://nodejs.org/"
    exit 1
fi

NODE_VERSION=$(node --version)
echo -e "${GREEN}✓${NC} Node.js: $NODE_VERSION"

# npmのインストールチェック
if ! command -v npm &> /dev/null; then
    echo -e "${RED}エラー: npmがインストールされていません${NC}"
    exit 1
fi

NPM_VERSION=$(npm --version)
echo -e "${GREEN}✓${NC} npm: $NPM_VERSION"

# GitHub CLIのインストールチェック
if ! command -v gh &> /dev/null; then
    echo -e "${RED}エラー: GitHub CLIがインストールされていません${NC}"
    echo "以下のコマンドでインストールしてください:"
    echo "  brew install gh"
    exit 1
fi

GH_VERSION=$(gh --version | head -n 1)
echo -e "${GREEN}✓${NC} $GH_VERSION"

# node_modulesのチェック
if [ ! -d "node_modules" ]; then
    echo ""
    echo -e "${YELLOW}依存関係をインストールしています...${NC}"
    npm install
    echo -e "${GREEN}✓${NC} 依存関係のインストールが完了しました"
fi

# Playwrightブラウザのチェック
if [ ! -d "$HOME/.cache/ms-playwright" ] && [ ! -d "$HOME/Library/Caches/ms-playwright" ]; then
    echo ""
    echo -e "${YELLOW}Playwrightブラウザをインストールしています...${NC}"
    npx playwright install chromium
    echo -e "${GREEN}✓${NC} Playwrightブラウザのインストールが完了しました"
fi

# CSVファイルの確認
CSV_FILE="${1:-pr_list.csv}"

if [ ! -f "$CSV_FILE" ]; then
    echo ""
    echo -e "${RED}エラー: CSVファイルが見つかりません: $CSV_FILE${NC}"
    echo ""
    echo "使い方:"
    echo "  $0 [CSVファイルパス]"
    echo ""
    echo "例:"
    echo "  $0 pr_list.csv"
    echo "  $0 /path/to/custom_pr_list.csv"
    exit 1
fi

echo -e "${GREEN}✓${NC} CSVファイル: $CSV_FILE"
echo ""

# メインスクリプトを実行
node screenshot_pr.js "$CSV_FILE"
