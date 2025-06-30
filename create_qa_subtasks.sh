#!/bin/bash

# QA実施タスク作成スクリプト
# Usage: ./create_qa_subtasks.sh

set -e

# 設定
REPO="basicinc/formrun"

echo "=== QA実施タスク作成スクリプト ==="
echo "対象リポジトリ: $REPO"
echo ""

# 対話形式で各種設定を入力
echo -n "親Issue番号を入力してください: "
read PARENT_ISSUE

echo -n "参照元Issue番号を入力してください: "
read SOURCE_ISSUE

echo -n "除外するIssue番号をスペース区切りで入力してください（なければEnter）: "
read EXCLUDE_ISSUES

echo -n "追加するプレフィクスを入力してください（デフォルト: [QA実施]）: "
read PREFIX
if [ -z "$PREFIX" ]; then
    PREFIX="[QA実施]"
fi

echo ""
echo "=== 設定確認 ==="
echo "親Issue: #$PARENT_ISSUE"
echo "参照元Issue: #$SOURCE_ISSUE"
echo "除外Issue: $EXCLUDE_ISSUES"
echo "プレフィクス: $PREFIX"
echo ""

echo -n "この設定で続行しますか？ (y/N): "
read CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "処理を中止しました。"
    exit 0
fi

echo ""

# Step 1: 参照元Issueからサブタスクを抽出
echo "Step 1: Issue #$SOURCE_ISSUE からサブタスクを抽出中..."
ISSUE_BODY=$(gh issue view $SOURCE_ISSUE --repo $REPO --json body | jq -r '.body')
echo "Issue本文の一部:"
echo "$ISSUE_BODY" | head -10
echo ""

# 複数のパターンでIssue番号を抽出
SUBTASK_NUMBERS=$(echo "$ISSUE_BODY" | grep -oE "(#[0-9]+|issues/[0-9]+|/issues/[0-9]+)" | grep -oE "[0-9]+" | sort -u)

echo "見つかったサブタスク: $SUBTASK_NUMBERS"
echo ""

# Step 2: 除外Issueをフィルタリング
echo "Step 2: 除外Issueをフィルタリング中..."
FILTERED_ISSUES=""
for issue in $SUBTASK_NUMBERS; do
    if ! echo "$EXCLUDE_ISSUES" | grep -w "$issue" > /dev/null; then
        FILTERED_ISSUES="$FILTERED_ISSUES $issue"
    else
        echo "  - 除外: #$issue"
    fi
done

echo "処理対象のIssue:$FILTERED_ISSUES"
echo ""

# Step 3: 各Issueの情報を取得してQAタスクを作成
echo "Step 3: QA実施タスクを作成中..."
CREATED_ISSUES=""

for issue_num in $FILTERED_ISSUES; do
    echo -n "  - Issue #$issue_num の情報を取得中..."
    
    # Issueのタイトルを取得
    ORIGINAL_TITLE=$(gh issue view $issue_num --repo $REPO --json title -q .title)
    echo " タイトル: $ORIGINAL_TITLE"
    
    # [独自ドメインフォーム]のプレフィックスを削除
    CLEAN_TITLE=$(echo "$ORIGINAL_TITLE" | sed -E 's/^\[独自ドメインフォーム\] ?//')
    
    # QA実施タスクのタイトル
    QA_TITLE="$PREFIX $CLEAN_TITLE"
    
    # QA実施タスクの本文
    QA_BODY="Parent Issue: #$PARENT_ISSUE

関連Issue: #$issue_num"
    
    # Issueを作成
    echo -n "    QA実施タスクを作成中..."
    NEW_ISSUE=$(gh issue create --repo $REPO --title "$QA_TITLE" --body "$QA_BODY" --label "QA" --web=false | grep -o "[0-9]*$")
    echo " 作成完了: #$NEW_ISSUE"
    
    CREATED_ISSUES="$CREATED_ISSUES $NEW_ISSUE"
done

echo ""
echo "作成されたIssue:$CREATED_ISSUES"
echo ""

# Step 4: 親IssueにサブタスクとしてリンクをMD追加
echo "Step 4: Issue #$PARENT_ISSUE にサブタスクを追加中..."

# 親Issueの現在の本文を取得
CURRENT_BODY=$(gh issue view $PARENT_ISSUE --repo $REPO --json body -q .body)

# 新しい本文を作成
NEW_BODY="$CURRENT_BODY"
for issue in $CREATED_ISSUES; do
    NEW_BODY="$NEW_BODY
- [ ] #$issue"
done

# 一時ファイルに保存
TEMP_FILE="/tmp/issue_body_$$.txt"
echo "$NEW_BODY" > "$TEMP_FILE"

# 親Issueを更新
gh issue edit $PARENT_ISSUE --repo $REPO --body-file "$TEMP_FILE"
rm -f "$TEMP_FILE"

echo "Issue #$PARENT_ISSUE の更新完了"
echo ""

# Step 5: 完了メッセージ
echo "=== 処理完了 ==="
echo "作成されたQA実施タスク:"
for issue in $CREATED_ISSUES; do
    echo "  - #$issue"
done
echo "作成されたIssueのURL:"
for issue in $CREATED_ISSUES; do
    echo "  https://github.com/$REPO/issues/$issue"
done