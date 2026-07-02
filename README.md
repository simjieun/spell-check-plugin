# spell-check 플러그인

Claude Code에서 소스 코드의 **영어 철자 오류**(식별자, 상수 키, 문자열, 주석)를 자동으로 검사하는 플러그인입니다.

VSCode 확장프로그램을 대체하며, Claude의 언어 모델 능력을 활용해 더 정교한 검사를 제공합니다.

## 기능

### 자동 검사 (Hook)
- **파일 저장 시 자동 실행**: 주석, docstring, 문서에서 오타 감지
- **비침투적**: 저장이 끝난 뒤 검사하므로 절대 저장을 막지 않음 — 오타는 Claude에게 피드백되어 자동 교정
- **빠른 피드백**: 저장 직후 터미널에 결과 표시

### 수동 검사 (Skill)
```bash
/spell-check                    # 현재 파일 검사
/spell-check --dir docs         # 특정 디렉토리 검사
/spell-check --fix              # 대화형 수정 제안
```

### 팀 커스터마이제이션
- `.spell-check-ignore`: 허용할 단어 목록 (회사명, 기술약자, 팀 고유 용어 — 한 줄에 한 단어)
- 프로젝트별 설정 가능

---

## 설치

### 로컬 개발 테스트
```bash
# 플러그인 디렉토리에서
claude --plugin-dir .

# Claude Code 시작 후
/spell-check
```

### 개인 설치 (팀원용, 가장 간단)
Claude Code 안에서:
```
/plugin marketplace add simjieun/spell-check-plugin
/plugin install spell-check@team-tools
```

### 팀 프로젝트에 추가 (프로젝트 단위 자동 적용)
프로젝트 루트의 `.claude/settings.json`에 아래를 추가하면, 팀원이 해당 프로젝트에서 Claude Code를 열 때 자동으로 설치를 제안받습니다:
```json
{
  "extraKnownMarketplaces": {
    "team-tools": {
      "source": {
        "source": "github",
        "repo": "simjieun/spell-check-plugin"
      }
    }
  },
  "enabledPlugins": {
    "spell-check@team-tools": true
  }
}
```

---

## 사용 예시

### 1. 자동 검사 (파일 저장 시)
```
파일을 저장하면 자동으로:

🔍 Checking spelling in: src/api.ts
  Line 12: 'recieve' → should be 'receive'
  Line 45: 'occured' → should be 'occurred'
⚠️  Found 2 potential spelling issues
```

### 2. 수동 검사 & 수정
```
/spell-check --fix

Claude가 제안하는 수정:
✅ src/api.ts
   - Line 12: recieve → receive
   - Line 45: occured → occurred

Apply changes? (y/n): y
```

### 3. 허용 단어 추가
오탐지된 단어는 `.spell-check-ignore`에 한 줄씩 추가하면 다시 잡지 않습니다 (형식은 파일 상단 주석 참고).
목록은 이 repo에서 팀 공통으로 관리하므로, **단어 추가는 이 repo에 PR로 올려주세요** —
각자 설치된 플러그인의 파일을 직접 고치면 본인에게만 반영되고 업데이트 시 덮어써집니다.

---

## 동작 순서도 (Hook 자동 검사)

검사는 항상 **저장이 끝난 뒤** 실행됩니다 — 오타가 있어도 저장을 막지 않습니다.

```mermaid
flowchart TD
    A1[Claude가 파일 저장<br/>PostToolUse: Write·Edit] --> B[check-spelling.sh 실행]
    A2[사용자가 에디터에서 저장<br/>FileChanged] --> B
    B --> F{검사 대상 파일인가?<br/>확장자 ts/js/md/json<br/>+ node_modules 등 제외}
    F -->|아니오| G[exit 0 — 종료]
    F -->|예| H[영어 텍스트 추출<br/>md: 전체<br/>js/ts: 주석 라인만]
    H --> I[.spell-check-ignore<br/>허용 단어 로드]
    I --> J[오타 패턴과 대조<br/>recieve, occured, dont 등<br/>단어 경계 기준]
    J --> K{오타 발견?}
    K -->|없음| L[✅ No spelling errors<br/>exit 0]
    K -->|있음, PostToolUse| M[⚠️ exit 2 — stderr로 Claude에게 전달<br/>저장은 이미 완료, Claude가 스스로 교정]
    K -->|있음, FileChanged| N[⚠️ 경고만 출력 — exit 0]
```

---

## 오류 카테고리

### 즉시 감지 (기본 패턴)
- **철자**: recieve, occured, seperator
- **축약형**: dont, doesnt, wont, cant

### Claude 모델 활용 (더 정교함)
- **식별자 오타**: camelCase/snake_case 분리 인식 (modifedDate → modifiedDate)
- **대소문자 일관성**: ModifiedDate vs modifiedDate 혼용 감지
- **표기 일관성**: dataBase vs database 혼용 감지

---

## 설정

### 플러그인 비활성화
```bash
/plugin disable spell-check@team-tools
```

---

## VSCode 확장과의 차이

| 기능 | VSCode 확장 | spell-check 플러그인 |
|------|-----------|------------------|
| 자동 검사 | UI 표시 | 터미널 출력 + 수정 제안 |
| 문맥 이해 | 패턴 기반 | Claude 모델 활용 |
| 팀 설정 | 전역만 | 프로젝트별 가능 |
| AI 수정 제안 | 없음 | 있음 (대화형) |

---

## 문제 해결

### Hook이 실제로 실행됐는지 확인
hook이 트리거될 때마다 실행 로그가 남습니다:
```bash
tail -f ~/.claude/spell-check-plugin.log
# 2026-07-02 14:30:12 [PostToolUse] src/api.ts
# 2026-07-02 14:31:05 [FileChanged] src/constants.ts
```
경로를 바꾸려면 `SPELL_CHECK_LOG_FILE` 환경 변수를 설정하세요.

### Hook이 실행되지 않음
```bash
# Hook 파일 권한 확인
chmod +x scripts/check-spelling.sh

# 플러그인 재로드
/reload-plugins
```

### 오탐지가 많음
- `.spell-check-ignore`에 단어를 추가하는 PR을 이 repo에 올려주세요

---

## 라이선스

MIT

## 기여

PR 환영합니다! 팀 피드백은 저희 로드맵을 결정합니다.
