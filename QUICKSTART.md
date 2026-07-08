# 🚀 시작하기

## 5분 안에 테스트하기

### Step 1: 플러그인 디렉토리 준비 (이미 생성됨)
```bash
cd spell-check-plugin
ls -la
# 확인 항목:
# - .claude-plugin/plugin.json ✅
# - skills/spell-check/SKILL.md ✅
# - hooks/hooks.json ✅
# - scripts/check-spelling.sh ✅
```

### Step 2: Hook 실행 권한 설정
```bash
chmod +x scripts/check-spelling.sh
```

### Step 3: 플러그인 검증
```bash
claude plugin validate .
```

### Step 4: Claude Code 시작 (테스트 모드)
```bash
# 플러그인 디렉토리를 지정하여 시작
claude --plugin-dir .
```

### Step 5: 스킬 테스트
```bash
# Claude 터미널에서 수동 호출:
/spell-check

# 또는 현재 파일 검사:
/spell-check --file README.md
```

---

## 실제 동작 흐름

### 시나리오: 개발자가 파일 저장

```
1️⃣ 개발자: src/api.ts 파일 저장
   └─ "// recieve the message from user"

2️⃣ 저장 완료 직후 Hook 자동 실행 (PostToolUse: Write|Edit)
   ├─ scripts/check-spelling.sh 실행 — 저장은 막지 않음
   ├─ "recieve" 패턴 감지
   └─ 터미널 출력:
      ⚠️  Found 1 potential spelling issue
      Line 5: 'recieve' → should be 'receive'

3️⃣ 개발자: /spell-check --fix 실행
   ├─ Claude가 더 정교한 검사
   ├─ 대소문자·표기 일관성도 함께 검사
   └─ 터미널 출력:
      🟢 Line 5: recieve → receive
      💡 Consider: "receive the message from the user"

4️⃣ 개발자: y (수정 승인)
   └─ 파일 자동 수정 후 저장
```

---

## 문제 해결

| 문제 | 해결 |
|------|------|
| Hook이 안 실행됨 | `chmod +x scripts/check-spelling.sh` |
| 플러그인 로드 안 됨 | `claude plugin validate` 후 오류 수정 |
| false positive 많음 | `.spell-check-ignore`에 단어 추가 |
| 성능 느림 | 대파일은 `/spell-check --file` 수동 호출 |

팀 배포 방법은 README.md의 "설치"와 DEPLOYMENT.md를 참고하세요.
