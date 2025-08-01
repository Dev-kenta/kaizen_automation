#!/bin/bash

# Weekly QA Tasks Checker for PLG projects (Simple Version)
# Usage: ./check_weekly_qa_tasks_simple.sh [MONDAY] [SUNDAY]
# Example: ./check_weekly_qa_tasks_simple.sh 2025-07-14 2025-07-20

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to calculate Sunday from Monday
calculate_sunday() {
    local monday="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        date -j -v+6d -f "%Y-%m-%d" "$monday" "+%Y-%m-%d"
    else
        # Linux
        date -d "$monday + 6 days" "+%Y-%m-%d"
    fi
}

# Set dates from arguments or default to current week
if [ $# -eq 0 ]; then
    # No arguments - use current week
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        MONDAY=$(date -v-monday "+%Y-%m-%d")
        SUNDAY=$(date -v-monday -v+6d "+%Y-%m-%d")
    else
        # Linux
        MONDAY=$(date -d "last monday" "+%Y-%m-%d")
        SUNDAY=$(date -d "last monday + 6 days" "+%Y-%m-%d")
    fi
elif [ $# -eq 1 ]; then
    # One argument - Monday date, calculate Sunday
    MONDAY="$1"
    SUNDAY=$(calculate_sunday "$MONDAY")
elif [ $# -eq 2 ]; then
    # Two arguments - Monday and Sunday
    MONDAY="$1"
    SUNDAY="$2"
else
    echo -e "${RED}エラー: 引数が多すぎます${NC}"
    echo "使用方法: $0 [MONDAY] [SUNDAY]"
    echo "例: $0 2025-07-14 2025-07-20"
    echo "例: $0 2025-07-14"
    echo "例: $0"
    exit 1
fi

# Validate date format
if ! date -j -f "%Y-%m-%d" "$MONDAY" > /dev/null 2>&1 && ! date -d "$MONDAY" > /dev/null 2>&1; then
    echo -e "${RED}エラー: 無効な日付形式です: $MONDAY${NC}"
    echo "YYYY-MM-DD形式で入力してください（例: 2025-07-14）"
    exit 1
fi

if ! date -j -f "%Y-%m-%d" "$SUNDAY" > /dev/null 2>&1 && ! date -d "$SUNDAY" > /dev/null 2>&1; then
    echo -e "${RED}エラー: 無効な日付形式です: $SUNDAY${NC}"
    echo "YYYY-MM-DD形式で入力してください（例: 2025-07-20）"
    exit 1
fi

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}QA Tasks Weekly Report${NC}"
echo -e "${BLUE}Week: $MONDAY ~ $SUNDAY${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Note: Using GraphQL cursor-based pagination to fetch ALL project items
# This ensures no QA tasks are missed regardless of the total number of items in the project
# GraphQL query to get QA tasks from PLG projects
QUERY='query {
  organization(login: "basicinc") {
    projectV2(number: 32) {
      items(first: 100, orderBy: {field: POSITION, direction: ASC}) {
        nodes {
          content {
            ... on Issue {
              number
              title
              state
              labels(first: 10) {
                nodes {
                  name
                }
              }
              assignees(first: 5) {
                nodes {
                  login
                  name
                }
              }
              createdAt
              updatedAt
              closedAt
              url
            }
          }
          fieldValues(first: 20) {
            nodes {
              ... on ProjectV2ItemFieldDateValue {
                date
                field {
                  ... on ProjectV2Field {
                    id
                    name
                  }
                }
              }
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
                field {
                  ... on ProjectV2SingleSelectField {
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}'

# Function to fetch all project items with pagination
fetch_all_project_items() {
    local all_items="[]"
    local has_next_page=true
    local cursor=""
    local page_count=0
    local max_pages=10  # Safety limit to prevent infinite loops
    
    echo "Fetching data from GitHub Projects (with pagination)..." >&2
    
    while [ "$has_next_page" = true ] && [ $page_count -lt $max_pages ]; do
        page_count=$((page_count + 1))
        echo "  Page $page_count を取得中..." >&2
        
        # Build GraphQL query with cursor
        if [ -z "$cursor" ]; then
            # First page
            local query='query {
              organization(login: "basicinc") {
                projectV2(number: 32) {
                  items(first: 100, orderBy: {field: POSITION, direction: ASC}) {
                    pageInfo {
                      hasNextPage
                      endCursor
                    }
                    nodes {
                      content {
                        ... on Issue {
                          number
                          title
                          state
                          labels(first: 10) {
                            nodes {
                              name
                            }
                          }
                          assignees(first: 5) {
                            nodes {
                              login
                              name
                            }
                          }
                          createdAt
                          updatedAt
                          closedAt
                          url
                        }
                      }
                      fieldValues(first: 20) {
                        nodes {
                          ... on ProjectV2ItemFieldDateValue {
                            date
                            field {
                              ... on ProjectV2Field {
                                id
                                name
                              }
                            }
                          }
                          ... on ProjectV2ItemFieldSingleSelectValue {
                            name
                            field {
                              ... on ProjectV2SingleSelectField {
                                name
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }'
        else
            # Subsequent pages
            local query='query {
              organization(login: "basicinc") {
                projectV2(number: 32) {
                  items(first: 100, after: "'$cursor'", orderBy: {field: POSITION, direction: ASC}) {
                    pageInfo {
                      hasNextPage
                      endCursor
                    }
                    nodes {
                      content {
                        ... on Issue {
                          number
                          title
                          state
                          labels(first: 10) {
                            nodes {
                              name
                            }
                          }
                          assignees(first: 5) {
                            nodes {
                              login
                              name
                            }
                          }
                          createdAt
                          updatedAt
                          closedAt
                          url
                        }
                      }
                      fieldValues(first: 20) {
                        nodes {
                          ... on ProjectV2ItemFieldDateValue {
                            date
                            field {
                              ... on ProjectV2Field {
                                id
                                name
                              }
                            }
                          }
                          ... on ProjectV2ItemFieldSingleSelectValue {
                            name
                            field {
                              ... on ProjectV2SingleSelectField {
                                name
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }'
        fi
        
        # Execute GraphQL query
        PAGE_DATA=$(gh api graphql -f query="$query")
        
        if [ $? -ne 0 ]; then
            echo "    エラー: GraphQLクエリが失敗しました" >&2
            break
        fi
        
        # Validate PAGE_DATA
        if ! echo "$PAGE_DATA" | jq . > /dev/null 2>&1; then
            echo "    エラー: 無効なJSONレスポンスを受信" >&2
            break
        fi
        
        # Extract pagination info
        has_next_page=$(echo "$PAGE_DATA" | jq -r '.data.organization.projectV2.items.pageInfo.hasNextPage')
        cursor=$(echo "$PAGE_DATA" | jq -r '.data.organization.projectV2.items.pageInfo.endCursor')
        
        # Extract items from this page
        PAGE_ITEMS=$(echo "$PAGE_DATA" | jq '.data.organization.projectV2.items.nodes')
        
        # Validate PAGE_ITEMS
        if ! echo "$PAGE_ITEMS" | jq . > /dev/null 2>&1; then
            echo "    エラー: 無効なページアイテムデータ" >&2
            break
        fi
        
        items_count=$(echo "$PAGE_ITEMS" | jq 'length')
        echo "    $items_count 件のアイテムを取得" >&2
        
        # Merge items only if PAGE_ITEMS is valid
        if [ "$items_count" -gt 0 ]; then
            all_items=$(echo "$all_items" "$PAGE_ITEMS" | jq -s 'add')
            # Validate merged result
            if ! echo "$all_items" | jq . > /dev/null 2>&1; then
                echo "    エラー: アイテムマージに失敗" >&2
                break
            fi
        fi
        
        # Check if we found our target issues
        found_targets=$(echo "$PAGE_ITEMS" | jq '[.[] | select(.content.number == 18010 or .content.number == 18340 or .content.number == 18140 or .content.number == 18367 or .content.number == 18375)] | length')
        if [ "$found_targets" -gt 0 ]; then
            echo "    対象Issue のうち $found_targets 件を発見！" >&2
        fi
        
        # Break if no more pages
        if [ "$has_next_page" != "true" ]; then
            echo "    最後のページに到達しました" >&2
            break
        fi
    done
    
    if [ $page_count -ge $max_pages ]; then
        echo "  警告: 最大ページ数（$max_pages）に到達しました。一部のアイテムが取得されていない可能性があります。" >&2
    fi
    
    total_items=$(echo "$all_items" | jq 'length')
    echo "  合計 $total_items 件のアイテムを $page_count ページから取得しました" >&2
    echo "" >&2
    
    # Return the data in the expected format
    echo "$all_items" | jq '{"data": {"organization": {"projectV2": {"items": {"nodes": .}}}}}'
}

# Fetch all project items
RAW_DATA=$(fetch_all_project_items)

# Process results with simpler jq
echo "Processing results..."
RESULTS=$(echo "$RAW_DATA" | jq --arg start "$MONDAY" --arg end "$SUNDAY" '
[.data.organization.projectV2.items.nodes[] | 
  select(.content.labels.nodes != null) |
  select(.content.labels.nodes | any(.name == "QA")) |
  select(.fieldValues.nodes != null) |
  {
    issue: .content.number,
    title: .content.title,
    state: .content.state,
    start_date: ([.fieldValues.nodes[] | select(.field != null and .field.name == "Start date") | .date][0] // null),
    end_date: ([.fieldValues.nodes[] | select(.field != null and .field.name == "End date") | .date][0] // null),
    status: ([.fieldValues.nodes[] | select(.field != null and .field.name == "Status") | .name][0] // "No Status"),
    assignees: [.content.assignees.nodes[].login],
    closed_at: .content.closedAt,
    url: .content.url
  }
] |
map(select(
  (.start_date != null and .end_date != null) and
  ((.start_date >= $start and .start_date <= $end) or (.end_date >= $start and .end_date <= $end) or (.start_date <= $start and .end_date >= $end))
)) |
unique_by(.issue) |
sort_by(.start_date, .issue)')

# Count tasks
TOTAL_COUNT=$(echo "$RESULTS" | jq -r 'length' | tr -d '\n')
COMPLETED_COUNT=$(echo "$RESULTS" | jq -r '[.[] | select(.state == "CLOSED")] | length' | tr -d '\n')
IN_PROGRESS_COUNT=$(echo "$RESULTS" | jq -r '[.[] | select(.state == "OPEN")] | length' | tr -d '\n')

# Summary
echo -e "${YELLOW}[サマリー]${NC}"
echo "- 合計タスク数: ${TOTAL_COUNT}件"
echo "- 完了済み: ${COMPLETED_COUNT}件"
echo "- 進行中: ${IN_PROGRESS_COUNT}件"
echo ""

# Function to display tasks
display_tasks() {
    local state="$1"
    local color="$2"
    local title="$3"
    
    local count=$(echo "$RESULTS" | jq -r "[.[] | select(.state == \"$state\")] | length" | tr -d '\n')
    
    if [ "$count" -gt 0 ]; then
        echo -e "${color}$title (${count}件)${NC}"
        echo "$RESULTS" | jq -r ".[] | select(.state == \"$state\") | 
          \"- [#\(.issue)] \(.title)\\n  担当: \(if (.assignees | length) > 0 then (.assignees | join(\", \")) else \"未アサイン\" end)\\n  期間: \(if .start_date then .start_date else \"未設定\" end) 〜 \(if .end_date then .end_date else \"未設定\" end)\\n  ステータス: \(.status)\(if .closed_at then \"\\n  完了日: \" + (.closed_at | split(\"T\")[0]) else \"\" end)\\n  URL: \(.url)\\n\""
    fi
}

# Display completed tasks
display_tasks "CLOSED" "$GREEN" "[完了済み] 完了済みタスク"

# Display in-progress tasks  
display_tasks "OPEN" "$YELLOW" "[進行中] 進行中タスク"

# Assignee summary
echo -e "${BLUE}[担当者別サマリー]${NC}"
echo "$RESULTS" | jq -r '
  group_by(if (.assignees | length) > 0 then .assignees[0] else "未アサイン" end) | 
  map({
    assignee: (if (.[0].assignees | length) > 0 then .[0].assignees[0] else "未アサイン" end),
    total: length,
    completed: ([.[] | select(.state == "CLOSED")] | length),
    in_progress: ([.[] | select(.state == "OPEN")] | length)
  }) | 
  .[] | 
  "- \(.assignee): \(.total)件（完了\(.completed)件、進行中\(.in_progress)件）"'

echo ""
echo -e "${BLUE}======================================${NC}"

# Additional weekly issue information
echo ""
echo -e "${BLUE}[プロジェクトボード外のQA関連issue（日付情報なし）]${NC}"
echo "以下のQAタスクはプロジェクトボードに含まれていないため、日付フィルタリングができませんが、QAラベルが付いています："
gh issue list --label "QA" --state open --json number,title,state,updatedAt,assignees,url --limit 50 2>/dev/null | \
  jq --arg start "$MONDAY" --arg end "$SUNDAY" '
  # プロジェクトボードで表示済みのIssue番号を除外
  map(select([18211,18246,18367,18375] | index(.number) | not)) | 
  sort_by(.number) | reverse | .[0:10]' | \
  jq -r '.[] | 
  "- [#\(.number)] \(.title) (\(.state))\n  担当: \(if (.assignees | length) > 0 then [.assignees[].login] | join(", ") else "未アサイン" end)\n  URL: \(.url)\n"' || echo "エラー: Issue一覧を取得できませんでした"

echo ""
echo -e "${BLUE}[今週作成されたQA関連issue]${NC}"
gh issue list --label "QA" --state all --json number,title,state,createdAt,url --limit 100 2>/dev/null | \
  jq -r --arg start "$MONDAY" --arg end "$SUNDAY" '.[] | 
  select(.createdAt >= ($start + "T00:00:00Z") and .createdAt <= ($end + "T23:59:59Z")) | 
  "- [#\(.number)] \(.title) (\(.state))\n  URL: \(.url)"' || echo "エラー: Issue一覧を取得できませんでした"

echo ""
echo -e "${BLUE}[今週完了したQA関連issue]${NC}"
gh issue list --label "QA" --state closed --json number,title,closedAt,url --limit 100 2>/dev/null | \
  jq -r --arg start "$MONDAY" --arg end "$SUNDAY" '.[] | 
  select(.closedAt >= ($start + "T00:00:00Z") and .closedAt <= ($end + "T23:59:59Z")) | 
  "- [#\(.number)] \(.title)\n  URL: \(.url)"' || echo "エラー: Issue一覧を取得できませんでした"

echo ""
echo "レポート生成完了: $(date)"