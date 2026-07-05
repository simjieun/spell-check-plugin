#!/usr/bin/env bash
# ponytail: macOS 기본 /bin/bash는 3.2라 declare -A, ${var,,} (bash 4+)를 지원하지 않음.
# env로 실행해 $PATH의 최신 bash(Homebrew 등)를 사용하도록 함.
set -euo pipefail

# spell-check hook — 저장을 막지 않고 사후에 알려줍니다
# 프로젝트에서 허용하는 단어는 루트의 .spell-check-ignore (한 줄에 한 단어)에서 가져옵니다
#
# 검사 엔진: cspell — 전체 영어 사전 기반, discoint 같은 임의의 오타도 사전에 없는
# 단어로 감지. camelCase/snake_case 분리 내장, 한글은 건너뜀. 전역 cspell이 없으면
# npm으로 플러그인 디렉토리에 최초 1회 자동 설치 (전역 오염 없음, Node 18+ 필요).
# cspell 확보 실패(npm 없음 등) 시에는 검사를 건너뜀 — 저장을 막지 않는 도구이므로.
#
# 실행 모드 네 가지:
#   1) 인자 모드:  check-spelling.sh <파일경로>  — 수동 실행/테스트용, 디스크의 파일을 검사
#   2) PostToolUse hook 모드: Claude가 Write/Edit로 저장한 직후 — 저장은 이미 완료됐으므로
#      stdin JSON의 tool_input.file_path로 디스크의 파일 "전체"를 검사하고, 오타가 있으면
#      exit 2 + stderr로 Claude에게 피드백 (차단 아님, Claude가 다음 수정에서 교정)
#   3) FileChanged hook 모드: 사용자가 에디터에서 저장하는 등 디스크의 파일이 변경된 뒤 —
#      stdin JSON의 file_path로 디스크 파일을 검사, 경고만 출력
#   4) --warm (SessionStart hook): 검사 없이 cspell만 미리 설치 — 첫 저장 검사가 느려지지 않게 함

FILE="${1:-}"
MODE="manual"
[[ "$FILE" == "--warm" ]] && { MODE="warm"; FILE=""; }
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IGNORE_FILE="${PLUGIN_DIR}/.spell-check-ignore"

# hook 모드: stdin JSON에서 대상 경로만 추출 — 두 모드 모두 저장이 이미 끝난 뒤 실행되므로
# 디스크의 실제 파일 전체를 검사 (Edit의 new_string 조각이 아님, 라인 번호도 실제 파일 기준)
if [[ -z "$FILE" && "$MODE" != "warm" ]]; then
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

# cspell 확보: 전역 → 플러그인 지역 설치본 → 없으면 최초 1회 자동 설치
# 성공 시 CSPELL에 실행 경로를 담고 0 반환, 실패 시 1 (호출부가 검사를 건너뜀)
CSPELL="$PLUGIN_DIR/node_modules/.bin/cspell"
ensure_cspell() {
  command -v cspell >/dev/null 2>&1 && { CSPELL="cspell"; return 0; }
  [[ -x "$CSPELL" ]] && return 0
  command -v npm >/dev/null 2>&1 || return 1
  # ponytail: 동시 저장으로 npm install이 겹치면 한쪽이 실패할 수 있음 — 그 회차만
  # 검사를 건너뛰고 다음 검사부터 설치본을 쓰므로 lock 없이 둠
  echo "$(date '+%Y-%m-%d %H:%M:%S') [install] cspell@8 → $PLUGIN_DIR" \
    >> "${SPELL_CHECK_LOG_FILE:-$HOME/.claude/spell-check-plugin.log}"
  npm install --prefix "$PLUGIN_DIR" --no-save cspell@8 >/dev/null 2>&1 || return 1
  [[ -x "$CSPELL" ]]
}

# 오타 검사 (전체 영어 사전 기반, 사전에 없는 단어를 전부 감지)
check_spelling() {
  local file="$1"
  local errors=0

  local ignore_words
  ignore_words="$(load_ignore_words "$IGNORE_FILE")"

  declare -A seen=()
  local line lnum word fix
  while IFS= read -r line; do
    # cspell 출력 형식: path:LINE:COL - Unknown word (WORD) fix: (FIX)
    lnum="$(cut -d: -f2 <<<"$line")"
    word="$(sed -E 's/.*Unknown word \(([^)]*)\).*/\1/' <<<"$line")"
    fix="$(sed -nE 's/.* fix: \(([^)]*)\).*/\1/p' <<<"$line")"

    # .spell-check-ignore의 허용 단어와 같은 단어의 중복 보고는 제외
    grep -qixF "$word" <<<"$ignore_words" && continue
    [[ -n "${seen[${word,,}]:-}" ]] && continue
    seen[${word,,}]=1

    if [[ -n "$fix" ]]; then
      echo "  Line $lnum: '$word' → should be '$fix'"
    else
      echo "  Line $lnum: '$word' → unknown word (오타가 아니면 .spell-check-ignore에 추가)"
    fi
    ((errors++))
  # cspell은 cwd 밖의 파일을 검사에서 제외하므로 파일이 있는 디렉토리에서 실행
  # (파일 근처에 프로젝트 자체 cspell 설정이 있으면 함께 적용됨)
  done < <(cd "$(dirname "$file")" && "$CSPELL" lint --no-progress --no-summary "$(basename "$file")" 2>/dev/null || true)

  # bash 반환 코드는 최대 255 — 오타가 정확히 256개면 0으로 래핑되어 통과로 오판하므로 클램프
  return $(( errors > 255 ? 255 : errors ))
}

# 메인 실행
main() {
  # SessionStart(--warm): 검사 없이 cspell만 미리 확보하고 종료
  # (실패해도 조용히 — 검사 시점에 ensure_cspell이 재시도함)
  if [[ "$MODE" == "warm" ]]; then
    ensure_cspell || true
    exit 0
  fi

  if ! should_check_file "$DISPLAY_PATH"; then
    exit 0
  fi

  if ! ensure_cspell; then
    echo "⚠️ cspell을 확보하지 못해 검사를 건너뜁니다 (npm 필요)"
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
