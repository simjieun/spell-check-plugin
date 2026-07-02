#!/usr/bin/env bash
# ponytail: macOS 기본 /bin/bash는 3.2라 mapfile/declare -A(bash 4+)를 지원하지 않음.
# env로 실행해 $PATH의 최신 bash(Homebrew 등)를 사용하도록 함.
set -euo pipefail

# spell-check hook (PreToolUse: Write|Edit)
# 파일이 저장되기 전에 영어 오타를 검사합니다
# 프로젝트에서 허용하는 단어는 루트의 .spell-check-ignore (한 줄에 한 단어)에서 가져옵니다
#
# 실행 모드 세 가지:
#   1) 인자 모드:  check-spelling.sh <파일경로>  — 수동 실행/테스트용, 디스크의 파일을 검사
#   2) PreToolUse hook 모드: stdin JSON에서 저장될 새 내용(tool_input.content / new_string)을
#      꺼내 검사 (디스크의 옛 내용이 아님)
#   3) FileChanged hook 모드: 사용자가 에디터에서 저장하는 등 디스크의 파일이 변경된 뒤 —
#      stdin JSON의 file_path로 디스크 파일을 그대로 검사

FILE="${1:-}"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IGNORE_FILE="${PLUGIN_DIR}/.spell-check-ignore"

# 기본 설정
STRICT_MODE="${SPELL_CHECK_STRICT:-false}"

TMP_DIR=""
trap '[[ -n "$TMP_DIR" ]] && rm -rf "$TMP_DIR"' EXIT

# hook 모드: stdin JSON에서 대상 경로와 저장될 내용을 추출
DISPLAY_PATH=""
if [[ -z "$FILE" ]]; then
  input="$(cat)"
  MODE="$(jq -r '.hook_event_name // "PreToolUse"' <<<"$input")"
  # hook 실행 기록 — 플러그인이 실제로 돌았는지 확인용 (tail -f 로 관찰)
  echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODE] $(jq -r '.file_path // .tool_input.file_path // "(no path)"' <<<"$input")" \
    >> "${SPELL_CHECK_LOG_FILE:-$HOME/.claude/spell-check-plugin.log}"
  if [[ "$MODE" == "FileChanged" ]]; then
    # FileChanged: 파일이 이미 디스크에 있으므로 경로만 꺼내 그대로 검사
    FILE="$(jq -r '.file_path // empty' <<<"$input")"
    [[ -n "$FILE" && -f "$FILE" ]] || exit 0
  else
    DISPLAY_PATH="$(jq -r '.tool_input.file_path // empty' <<<"$input")"
    content="$(jq -r '.tool_input.content // .tool_input.new_string // empty' <<<"$input")"
    [[ -n "$DISPLAY_PATH" && -n "$content" ]] || exit 0
    TMP_DIR="$(mktemp -d)"
    FILE="${TMP_DIR}/$(basename "$DISPLAY_PATH")"
    printf '%s\n' "$content" > "$FILE"
  fi
fi
DISPLAY_PATH="${DISPLAY_PATH:-$FILE}"

# 무시할 파일 패턴
IGNORE_PATTERNS=(
  "**/node_modules/**"
  "**/.git/**"
  "**/dist/**"
  "**/build/**"
  "**/.next/**"
  "**/coverage/**"
  "**/mockData/**"
  "**/*.min.js"
)

# 파일 검사 여부 판단 (실제 저장 경로 기준 — hook 모드의 임시 파일 경로가 아님)
should_check_file() {
  local file="$1"

  # 무시 패턴 확인 (앞에 /를 붙여 상대 경로도 */node_modules/* 패턴에 걸리게 함)
  for pattern in "${IGNORE_PATTERNS[@]}"; do
    if [[ "/$file" == $pattern ]]; then
      return 1
    fi
  done

  # 지원하는 확장자 확인 (바이너리는 여기서 함께 걸러짐)
  case "$file" in
    *.ts|*.tsx|*.js|*.jsx|*.md|*.json) return 0 ;;
    *) return 1 ;;
  esac
}

# 파일에서 영어 단어 추출
extract_english_text() {
  local file="$1"

  case "$file" in
    *.md)
      cat "$file"
      ;;
    *.js|*.jsx|*.ts|*.tsx)
      # 주석 라인만 추출 (// 또는 * 로 시작하는 라인)
      grep -E '^[[:space:]]*(//|\*|/\*)' "$file" | \
        sed -E 's#^[[:space:]]*(//|/\*|\*)[[:space:]]*##'
      ;;
  esac
}

# .spell-check-ignore에서 허용 단어 목록 로드 (# 주석과 빈 줄은 무시)
load_ignore_words() {
  local ignore_file="$1"
  [[ -f "$ignore_file" ]] || return 0

  grep -vE '^[[:space:]]*(#|$)' "$ignore_file" || true
}

# 오타 검사 (기본 패턴)
check_spelling() {
  local file="$1"
  local errors=0

  local ignore_words=()
  mapfile -t ignore_words < <(load_ignore_words "$IGNORE_FILE")

  # 간단한 오타 패턴 (실제로는 Claude가 더 정교하게 감지)
  declare -A common_errors=(
    ["recieve"]="receive"
    ["occured"]="occurred"
    ["seperator"]="separator"
    ["neccessary"]="necessary"
    ["definately"]="definitely"
    ["accomodate"]="accommodate"
    ["untill"]="until"
    ["wich"]="which"
    ["dont"]="don't"
    ["doesnt"]="doesn't"
    ["cant"]="can't"
    ["wont"]="won't"
  )

  local content
  content=$(extract_english_text "$file")

  # 각 오류 패턴 검사
  for error in "${!common_errors[@]}"; do
    correct="${common_errors[$error]}"

    # 단어 경계를 고려한 검사
    if echo "$content" | grep -iw "$error" >/dev/null 2>&1; then
      local line_num
      line_num=$(grep -in "\b$error\b" "$file" | cut -d: -f1 | head -1)

      # ignore 목록 확인 (.spell-check-ignore)
      local should_ignore=false
      for ignore_word in "${ignore_words[@]}"; do
        [[ "${error,,}" == "${ignore_word,,}" ]] && should_ignore=true && break
      done

      if [[ "$should_ignore" == false ]]; then
        echo "  Line $line_num: '$error' → should be '$correct'"
        ((errors++))
      fi
    fi
  done

  return $errors
}

# 메인 실행
main() {
  if ! should_check_file "$DISPLAY_PATH"; then
    exit 0
  fi

  echo "🔍 Checking spelling in: $DISPLAY_PATH"

  local issues error_count=0
  issues="$(check_spelling "$FILE")" || error_count=$?

  if [[ "$error_count" -eq 0 ]]; then
    echo "✅ No spelling errors found"
    exit 0
  fi

  echo "$issues"
  echo "⚠️  Found $error_count potential spelling issues"

  if [[ "$STRICT_MODE" == "true" ]]; then
    # PreToolUse에서 exit 2 = 도구 실행 차단, stderr가 Claude에게 전달됨
    echo "❌ Strict mode: spelling issue(s) in $DISPLAY_PATH - blocking save. Fix and retry:" >&2
    echo "$issues" >&2
    exit 2
  fi

  exit 0
}

main
