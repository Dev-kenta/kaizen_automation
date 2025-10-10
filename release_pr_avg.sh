#!/usr/bin/env bash
set -euo pipefail

# 使い方:
#   ./release_pr_avg.sh 2025-01-01 2025-06-30
#
# 第1引数: 開始日 (YYYY-MM-DD)
# 第2引数: 終了日 (YYYY-MM-DD)

if [ $# -ne 2 ]; then
  echo "Usage: $0 <start-date:YYYY-MM-DD> <end-date:YYYY-MM-DD>"
  exit 1
fi

START_DATE="$1"
END_DATE="$2"

# ISO形式に変換（終了日はその日の末尾まで含める想定で、時刻は23:59:59に固定）
START_ISO="${START_DATE}T00:00:00Z"
END_ISO="${END_DATE}T23:59:59Z"

REPO="basicinc/formrun"
BASE_BRANCH="release"
TITLE_KEYWORD="本番リリース"

# === 対象リリースPR番号を抽出 ===
PR_NUMBERS=$(
  gh pr list \
    --repo "$REPO" \
    --base "$BASE_BRANCH" \
    --state merged \
    --limit 1000 \
    --json number,mergedAt,title \
  | jq -r --arg start "$START_ISO" --arg end "$END_ISO" --arg kw "$TITLE_KEYWORD" '
      .[]
      | select(
          (.title | contains($kw)) and
          (.mergedAt >= $start and .mergedAt <= $end)
        )
      | .number
    '
)

if [ -z "$PR_NUMBERS" ]; then
  echo "対象期間(${START_DATE}〜${END_DATE})に一致するリリースPRは 0 件でした。"
  exit 0
fi

# === 各PRの本文から #1234 の数を数えて平均を計算 ===
total=0
count_prs=0

echo "各PRの含有PR数 (#番号 の個数):"
while IFS= read -r pr; do
  body=$(gh pr view "$pr" --repo "$REPO" --json body --jq '.body // ""')
  count=$(printf "%s" "$body" | grep -oE '#[0-9]+' | wc -l | tr -d ' ')
  echo "  #$pr: ${count}"
  total=$((total + count))
  count_prs=$((count_prs + 1))
done <<< "$PR_NUMBERS"

avg=$(awk -v t="$total" -v n="$count_prs" 'BEGIN{ if(n>0){printf "%.2f", t/n}else{print 0} }')

echo ""
echo "対象PR件数: ${count_prs}"
echo "合計参照数: ${total}"
echo "平均(含まれたPR数/リリースPR): ${avg}"

