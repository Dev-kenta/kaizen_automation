#!/bin/bash

# セキュリティチェック自動化スクリプト
# Usage: ./security_check.sh [CSVファイルパス] [オプション]
# Example: ./security_check.sh urls.csv --cookie1 "cookie値" --cookie2 "cookie値"

set -e

# カラーコード定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# デフォルト設定
DEFAULT_CSV="urls.csv"
TEMP_DIR=""
REPORT_DIR="security_reports"
LOG_FILE=""

# コマンドライン引数で指定されたCookie
ARG_COOKIE1=""
ARG_COOKIE2=""
ARG_COOKIE3=""
ARG_COOKIE4=""
ARG_COOKIE5=""

# 使い方表示関数
show_usage() {
    cat << EOF
使い方: $0 [CSVファイルパス] [オプション]

オプション:
  --cookie1 "値"    Cookie1を指定（必須）
  --cookie2 "値"    Cookie2を指定
  --cookie3 "値"    Cookie3を指定
  --cookie4 "値"    Cookie4を指定
  --cookie5 "値"    Cookie5を指定
  -h, --help        ヘルプを表示

CSVフォーマット:
  url
  https://example.com/page1
  https://example.com/page2

  ※ CSVファイルにはURL列のみを記載してください
  ※ Cookieは全て引数で指定します

例:
  # Cookie1とCookie2を引数で指定
  $0 urls.csv --cookie1 "pscd=xxx; beta=yyy" --cookie2 "pscd=aaa; beta=bbb"

  # Cookie1のみ指定
  $0 urls.csv --cookie1 "session_token=xxxxx"

  # デフォルトCSVファイルを使用
  $0 --cookie1 "session_token=xxxxx"

注意:
  - Cookieは引数で指定してください（CSV列には含めません）
  - Cookieは必ずダブルクォートで囲んでください
  - ログは security_reports/ ディレクトリに保存されます
EOF
}

# クリーンアップ関数
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        echo -e "${BLUE}一時ファイルをクリーンアップしています...${NC}"
        rm -rf "$TEMP_DIR"
    fi
}

# エラー時のクリーンアップ
trap cleanup EXIT

# ログ出力関数（コンソールとファイルの両方に出力）
log() {
    if [ -n "$LOG_FILE" ]; then
        # カラーコードを除去してログファイルに出力
        echo -e "$@" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"
    fi
    # コンソールには通常通り出力
    echo -e "$@"
}

# 前提条件チェック関数
check_prerequisites() {
    log "${BLUE}=== 前提条件チェック ===${NC}"

    if ! command -v curl &> /dev/null; then
        log "${RED}エラー: curlコマンドが見つかりません${NC}"
        log "curlをインストールしてください:"
        log "  macOS: brew install curl"
        log "  Ubuntu: sudo apt-get install curl"
        exit 1
    fi
    log "${GREEN}✓${NC} curl: $(curl --version | head -1)"

    if ! command -v diff &> /dev/null; then
        log "${RED}エラー: diffコマンドが見つかりません${NC}"
        exit 1
    fi
    log "${GREEN}✓${NC} diff: available"

    log ""
}

# URLにアクセスしてレスポンスを取得する関数
fetch_url() {
    local url="$1"
    local cookie="$2"
    local output_file="$3"
    local status_file="$4"

    # set -eを一時的に無効化してcurlのエラーを処理
    set +e

    if [ -z "$cookie" ]; then
        # Cookieなし
        /usr/bin/curl -s -L -w "%{http_code}" --max-time 30 -o "$output_file" "$url" > "$status_file" 2>&1 < /dev/null
    else
        # Cookie付き
        /usr/bin/curl -s -L -w "%{http_code}" --max-time 30 -H "Cookie: $cookie" -o "$output_file" "$url" > "$status_file" 2>&1 < /dev/null
    fi

    # set -eを再度有効化
    set -e
}

# セキュリティチェック関数
check_security() {
    local url_id="$1"
    local no_cookie_file="$2"
    local no_cookie_status="$3"
    local cookie_files=("${@:4}")

    local status="PASS"
    local messages=()

    # チェック1: 認証なしアクセス検知
    if [ "$no_cookie_status" -eq 200 ]; then
        status="ERROR"
        messages+=("✗ 認証なしアクセス防御: NG（Cookieなしで200 OKを返しています）")
        messages+=("  セキュリティリスク: このURLは認証なしでアクセス可能です")
    else
        messages+=("✓ 認証なしアクセス防御: OK（Cookieなしで${no_cookie_status}を返しています）")
    fi

    # チェック2: Cookieなし vs Cookie1 の差分チェック
    if [ -f "$no_cookie_file" ] && [ ${#cookie_files[@]} -gt 0 ] && [ -f "${cookie_files[0]}" ]; then
        if diff -q "$no_cookie_file" "${cookie_files[0]}" > /dev/null 2>&1; then
            if [ "$status" != "ERROR" ]; then
                status="WARNING"
            fi
            messages+=("⚠ レスポンス差分: WARNING（Cookieの有無でレスポンスが同一）")
            messages+=("  Cookie認証が機能していない可能性があります")
        else
            messages+=("✓ レスポンス差分: OK（Cookieの有無でレスポンスが異なります）")
        fi
    fi

    # チェック3: Cookie間の差分チェック
    if [ ${#cookie_files[@]} -gt 1 ]; then
        local all_same=true
        for ((i=0; i<${#cookie_files[@]}-1; i++)); do
            if [ -f "${cookie_files[$i]}" ] && [ -f "${cookie_files[$i+1]}" ]; then
                if ! diff -q "${cookie_files[$i]}" "${cookie_files[$i+1]}" > /dev/null 2>&1; then
                    all_same=false
                    break
                fi
            fi
        done

        if [ "$all_same" = true ]; then
            if [ "$status" = "PASS" ]; then
                status="WARNING"
            fi
            messages+=("⚠ Cookie間差分: WARNING（全てのCookieで同じレスポンス）")
            messages+=("  異なるユーザーで同じ内容が表示されている可能性があります")
        else
            messages+=("✓ Cookie間差分: OK（Cookie間で異なるレスポンス）")
        fi
    fi

    # 結果を返す
    echo "$status"
    printf '%s\n' "${messages[@]}"
}

# レポート生成関数
generate_report() {
    local csv_file="$1"
    local report_file="$2"
    local timestamp="$3"
    local url_count="$4"
    shift 4
    local results=("$@")

    # レポートヘッダー
    {
        echo "# セキュリティチェックレポート"
        echo ""
        echo "生成日時: $timestamp"
        echo "対象CSV: $csv_file"
        echo "チェックURL数: ${url_count}件"
        echo ""
        echo "---"
        echo ""
        echo "## サマリー"
        echo ""
    } > "$report_file"

    # サマリー集計
    local pass_count=0
    local warning_count=0
    local error_count=0

    for result in "${results[@]}"; do
        if [[ "$result" == *"STATUS:PASS"* ]]; then
            ((pass_count++))
        elif [[ "$result" == *"STATUS:WARNING"* ]]; then
            ((warning_count++))
        elif [[ "$result" == *"STATUS:ERROR"* ]]; then
            ((error_count++))
        fi
    done

    cat >> "$report_file" << EOF
| ステータス | 件数 |
|----------|------|
| ✓ PASS   | ${pass_count}件  |
| ⚠ WARNING | ${warning_count}件  |
| ✗ ERROR   | ${error_count}件  |

---

## 詳細結果

EOF

    # 詳細結果を追記
    for result in "${results[@]}"; do
        echo "$result" >> "$report_file"
        echo "" >> "$report_file"
    done

    # 推奨アクション
    cat >> "$report_file" << EOF

---

## 推奨アクション

EOF

    if [ $error_count -gt 0 ]; then
        echo "1. **ERROR状態のURL（${error_count}件）を優先的に修正してください**" >> "$report_file"
        echo "   - 認証なしアクセスが可能なURLがあります" >> "$report_file"
        echo "" >> "$report_file"
    fi

    if [ $warning_count -gt 0 ]; then
        echo "2. **WARNING状態のURL（${warning_count}件）を確認してください**" >> "$report_file"
        echo "   - Cookie認証が正しく機能していない可能性があります" >> "$report_file"
        echo "" >> "$report_file"
    fi

    if [ $pass_count -eq $url_count ]; then
        echo "すべてのURLで正常に認証が機能しています。" >> "$report_file"
        echo "" >> "$report_file"
    fi

    echo "---" >> "$report_file"
    echo "" >> "$report_file"
    echo "ログファイル: $LOG_FILE" >> "$report_file"
    echo "生データ保存先: $TEMP_DIR" >> "$report_file"
}

# 引数解析
parse_arguments() {
    CSV_FILE=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            --cookie1)
                ARG_COOKIE1="$2"
                shift 2
                ;;
            --cookie2)
                ARG_COOKIE2="$2"
                shift 2
                ;;
            --cookie3)
                ARG_COOKIE3="$2"
                shift 2
                ;;
            --cookie4)
                ARG_COOKIE4="$2"
                shift 2
                ;;
            --cookie5)
                ARG_COOKIE5="$2"
                shift 2
                ;;
            *)
                if [ -z "$CSV_FILE" ]; then
                    CSV_FILE="$1"
                else
                    echo "エラー: 不明な引数: $1"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # CSVファイルが指定されていない場合はデフォルトを使用
    if [ -z "$CSV_FILE" ]; then
        CSV_FILE="$DEFAULT_CSV"
    fi
}

# メイン処理
main() {
    # 引数解析
    parse_arguments "$@"

    # タイムスタンプ生成
    TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
    TIMESTAMP_READABLE=$(date "+%Y-%m-%d %H:%M:%S")

    # レポートディレクトリとログファイルの作成
    mkdir -p "$REPORT_DIR"
    LOG_FILE="$REPORT_DIR/security_check_${TIMESTAMP}.log"
    REPORT_FILE="$REPORT_DIR/security_check_${TIMESTAMP}.md"

    # ログファイルに開始情報を記録
    {
        echo "=================================="
        echo "セキュリティチェック 実行ログ"
        echo "=================================="
        echo "実行開始時刻: $TIMESTAMP_READABLE"
        echo "実行コマンド: $0 $*"
        echo "CSVファイル: $CSV_FILE"
        echo ""
        echo "引数で指定されたCookie:"
        [ -n "$ARG_COOKIE1" ] && echo "  Cookie1: [指定あり]" || echo "  Cookie1: [CSVから使用]"
        [ -n "$ARG_COOKIE2" ] && echo "  Cookie2: [指定あり]" || echo "  Cookie2: [CSVから使用]"
        [ -n "$ARG_COOKIE3" ] && echo "  Cookie3: [指定あり]" || echo "  Cookie3: [CSVから使用]"
        [ -n "$ARG_COOKIE4" ] && echo "  Cookie4: [指定あり]" || echo "  Cookie4: [CSVから使用]"
        [ -n "$ARG_COOKIE5" ] && echo "  Cookie5: [指定あり]" || echo "  Cookie5: [CSVから使用]"
        echo ""
        echo "=================================="
        echo ""
    } > "$LOG_FILE"

    log "${BLUE}======================================${NC}"
    log "${BLUE}セキュリティチェック自動化スクリプト${NC}"
    log "${BLUE}======================================${NC}"
    log ""
    log "ログファイル: $LOG_FILE"
    log ""

    # 前提条件チェック
    check_prerequisites

    # CSVファイルの確認
    if [ ! -f "$CSV_FILE" ]; then
        log "${RED}エラー: CSVファイルが見つかりません: $CSV_FILE${NC}"
        log ""
        log "使い方:"
        log "  $0 [CSVファイルパス] [オプション]"
        log ""
        log "詳細は -h オプションを参照してください"
        exit 1
    fi

    log "${GREEN}✓${NC} CSVファイル: $CSV_FILE"
    log ""

    # 一時ディレクトリの作成
    TEMP_DIR="/tmp/security_check_$$"
    mkdir -p "$TEMP_DIR"

    log "${BLUE}=== CSVファイル解析 ===${NC}"

    # CSV解析とURL処理
    local url_id=0
    local results=()
    local skip_header=true

    while IFS= read -r url <&3 || [[ -n "$url" ]]; do
        # ヘッダー行をスキップ
        if [ "$skip_header" = true ]; then
            skip_header=false
            continue
        fi

        # 空行をスキップ
        if [ -z "$url" ]; then
            continue
        fi

        # ダブルクォートとCR/LF文字を除去
        url=$(echo "$url" | sed 's/^"//;s/"$//;s/\r$//')

        # Cookieは引数から取得（CSVファイルには含まれない）
        cookie1="$ARG_COOKIE1"
        cookie2="$ARG_COOKIE2"
        cookie3="$ARG_COOKIE3"
        cookie4="$ARG_COOKIE4"
        cookie5="$ARG_COOKIE5"

        ((url_id++))

        log "${YELLOW}[URL #$url_id] チェック中: $url${NC}"

        # Step 1: Cookieなしでアクセス
        log "  Step 1: Cookieなしでアクセス中..."
        no_cookie_file="$TEMP_DIR/url_${url_id}_no_cookie.html"
        no_cookie_status_file="$TEMP_DIR/url_${url_id}_no_cookie.status"
        fetch_url "$url" "" "$no_cookie_file" "$no_cookie_status_file"
        no_cookie_status=$(cat "$no_cookie_status_file")
        no_cookie_size=$(wc -c < "$no_cookie_file" | tr -d ' ')
        log "    HTTPステータス: $no_cookie_status, サイズ: ${no_cookie_size} bytes"

        # Cookie付きアクセス
        cookie_files=()
        cookie_statuses=()
        cookie_sizes=()
        local cookie_num=0

        for cookie in "$cookie1" "$cookie2" "$cookie3" "$cookie4" "$cookie5"; do
            if [ -n "$cookie" ]; then
                ((cookie_num++))
                log "  Step $((cookie_num+1)): Cookie${cookie_num}でアクセス中..."
                cookie_file="$TEMP_DIR/url_${url_id}_cookie${cookie_num}.html"
                cookie_status_file="$TEMP_DIR/url_${url_id}_cookie${cookie_num}.status"
                fetch_url "$url" "$cookie" "$cookie_file" "$cookie_status_file"
                cookie_status=$(cat "$cookie_status_file")
                cookie_size=$(wc -c < "$cookie_file" | tr -d ' ')
                log "    HTTPステータス: $cookie_status, サイズ: ${cookie_size} bytes"

                cookie_files+=("$cookie_file")
                cookie_statuses+=("$cookie_status")
                cookie_sizes+=("$cookie_size")
            fi
        done

        # セキュリティチェック実行
        log "  セキュリティチェック実行中..."
        check_result=$(check_security "$url_id" "$no_cookie_file" "$no_cookie_status" "${cookie_files[@]}")
        check_status=$(echo "$check_result" | head -1)
        check_messages=$(echo "$check_result" | tail -n +2)

        # 結果の表示
        if [ "$check_status" = "ERROR" ]; then
            log "  ${RED}結果: ✗ ERROR${NC}"
        elif [ "$check_status" = "WARNING" ]; then
            log "  ${YELLOW}結果: ⚠ WARNING${NC}"
        else
            log "  ${GREEN}結果: ✓ PASS${NC}"
        fi
        echo "$check_messages" | sed 's/^/    /' | while IFS= read -r line; do log "$line"; done
        log ""

        # レポート用のデータを構築
        result_detail="### URL #${url_id}: $url

**ステータス**: "

        if [ "$check_status" = "ERROR" ]; then
            result_detail+="✗ ERROR"
        elif [ "$check_status" = "WARNING" ]; then
            result_detail+="⚠ WARNING"
        else
            result_detail+="✓ PASS"
        fi

        result_detail+="

#### アクセス結果

| アクセス方式 | HTTPステータス | レスポンスサイズ | 備考 |
|------------|--------------|----------------|-----|
| Cookieなし | $no_cookie_status | ${no_cookie_size} bytes | "

        if [ "$no_cookie_status" -eq 200 ]; then
            result_detail+="⚠ 認証なしでアクセス可能"
        else
            result_detail+="認証エラー（正常）"
        fi

        result_detail+=" |
"

        for ((i=0; i<${#cookie_files[@]}; i++)); do
            result_detail+="| Cookie$((i+1)) | ${cookie_statuses[$i]} | ${cookie_sizes[$i]} bytes | アクセス成功 |
"
        done

        result_detail+="
#### セキュリティチェック結果

$check_messages

STATUS:$check_status"

        results+=("$result_detail")

    done 3< "$CSV_FILE"

    # レポート生成
    log "${BLUE}=== レポート生成 ===${NC}"
    generate_report "$CSV_FILE" "$REPORT_FILE" "$TIMESTAMP_READABLE" "$url_id" "${results[@]}"

    log "${GREEN}✓${NC} レポート生成完了: $REPORT_FILE"
    log ""

    # サマリー表示
    log "${BLUE}======================================${NC}"
    log "${BLUE}処理完了${NC}"
    log "${BLUE}======================================${NC}"
    log ""
    log "実行終了時刻: $(date '+%Y-%m-%d %H:%M:%S')"
    log "チェック済みURL数: $url_id件"
    log "レポートファイル: $REPORT_FILE"
    log "ログファイル: $LOG_FILE"
    log ""
    log "${YELLOW}レポートを確認してください:${NC}"
    log "  cat $REPORT_FILE"
    log ""
}

# メイン処理実行
main "$@"
