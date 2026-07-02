#!/usr/bin/env bash
set -euo pipefail

# 사용법: add-ignore-word.sh <단어> [단어 ...]
# .spell-check-ignore에 허용 단어를 추가합니다
# - 이미 있는 단어(대소문자 무시)는 건너뜁니다
# - 영문자/숫자/하이픈/언더스코어만 허용 (예: myterm, -webkit-line-clamp)

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IGNORE_FILE="${SPELL_CHECK_IGNORE_FILE:-${PLUGIN_DIR}/.spell-check-ignore}"

if [[ $# -eq 0 ]]; then
  echo "Usage: $(basename "$0") <word> [word ...]" >&2
  exit 1
fi

for word in "$@"; do
  if [[ ! "$word" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "⏭️  skipped '$word' (영문자·숫자·하이픈·언더스코어만 가능)" >&2
    continue
  fi
  if [[ -f "$IGNORE_FILE" ]] && grep -qix -- "$word" "$IGNORE_FILE"; then
    echo "already in list: $word"
  else
    printf '%s\n' "$word" >> "$IGNORE_FILE"
    echo "✅ added: $word"
  fi
done
