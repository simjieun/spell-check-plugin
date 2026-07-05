#!/usr/bin/env bash
# ponytail: macOS 기본 /bin/bash는 3.2라 mapfile/declare -A(bash 4+)를 지원하지 않음.
# env로 실행해 $PATH의 최신 bash(Homebrew 등)를 사용하도록 함.
set -euo pipefail

# spell-check hook — 저장을 막지 않고 사후에 알려줍니다
# 프로젝트에서 허용하는 단어는 루트의 .spell-check-ignore (한 줄에 한 단어)에서 가져옵니다
#
# 실행 모드 세 가지:
#   1) 인자 모드:  check-spelling.sh <파일경로>  — 수동 실행/테스트용, 디스크의 파일을 검사
#   2) PostToolUse hook 모드: Claude가 Write/Edit로 저장한 직후 — 저장은 이미 완료됐으므로
#      stdin JSON의 tool_input.file_path로 디스크의 파일 "전체"를 검사하고, 오타가 있으면
#      exit 2 + stderr로 Claude에게 피드백 (차단 아님, Claude가 다음 수정에서 교정)
#   3) FileChanged hook 모드: 사용자가 에디터에서 저장하는 등 디스크의 파일이 변경된 뒤 —
#      stdin JSON의 file_path로 디스크 파일을 검사, 경고만 출력

FILE="${1:-}"
MODE="manual"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IGNORE_FILE="${PLUGIN_DIR}/.spell-check-ignore"

# hook 모드: stdin JSON에서 대상 경로만 추출 — 두 모드 모두 저장이 이미 끝난 뒤 실행되므로
# 디스크의 실제 파일 전체를 검사 (Edit의 new_string 조각이 아님, 라인 번호도 실제 파일 기준)
if [[ -z "$FILE" ]]; then
  input="$(cat)"
  MODE="$(jq -r '.hook_event_name // "PostToolUse"' <<<"$input")"
  # hook 실행 기록 — 플러그인이 실제로 돌았는지 확인용 (tail -f 로 관찰)
  echo "$(date '+%Y-%m-%d %H:%M:%S') [$MODE] $(jq -r '.file_path // .tool_input.file_path // "(no path)"' <<<"$input")" \
    >> "${SPELL_CHECK_LOG_FILE:-$HOME/.claude/spell-check-plugin.log}"
  FILE="$(jq -r '.file_path // .tool_input.file_path // empty' <<<"$input")"
  [[ -n "$FILE" && -f "$FILE" ]] || exit 0
fi
DISPLAY_PATH="$FILE"

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

  # 토큰화: camelCase/PascalCase 경계와 snake_case의 _ 에 공백을 삽입해
  # 식별자 내부 단어(getSeperator → get Seperator)도 단어 경계 grep에 걸리게 함.
  # 공백만 삽입하므로 라인 번호는 원본과 동일하게 유지됨.
  local tokenized
  tokenized="$(sed -E 's/([a-z0-9])([A-Z])/\1 \2/g; s/([A-Z])([A-Z][a-z])/\1 \2/g; s/_/ /g' "$file")"

  # 각 오류 패턴 검사 (파일 전체 소스 대상, 단어 경계 기준)
  for error in "${!common_errors[@]}"; do
    correct="${common_errors[$error]}"

    local line_num
    line_num=$(grep -inw "$error" <<<"$tokenized" | cut -d: -f1 | head -1)
    [[ -n "$line_num" ]] || continue

    # ignore 목록 확인 (.spell-check-ignore)
    local should_ignore=false
    for ignore_word in "${ignore_words[@]}"; do
      [[ "${error,,}" == "${ignore_word,,}" ]] && should_ignore=true && break
    done

    if [[ "$should_ignore" == false ]]; then
      echo "  Line $line_num: '$error' → should be '$correct'"
      ((errors++))
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

  if [[ "$MODE" == "PostToolUse" ]]; then
    # PostToolUse에서 exit 2 = 저장은 이미 완료된 상태에서 stderr만 Claude에게 전달됨
    # → Claude가 오타를 인지하고 다음 수정에서 스스로 교정
    echo "⚠️ spelling issue(s) in $DISPLAY_PATH (already saved - not blocking). Consider fixing:" >&2
    echo "$issues" >&2
    exit 2
  fi

  exit 0
}

main
