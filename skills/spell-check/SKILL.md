---
name: spell-check
description: Check English spelling in code identifiers, constant keys, string literals, and comments
disable-model-invocation: false
when-to-use: When reviewing source code for English spelling errors in variable names, constant keys, string values, and comments
allowed-tools: [Read, Bash, Write]
---

# /spell-check Skill

## Purpose
소스 코드 안의 영어 철자 오류를 찾아서 보고하고 수정을 제안합니다.
문장 단위 문법 검사가 아니라 **코드 특화** 검사입니다.

## 검사 대상

1. **식별자**: 변수명, 함수명, 상수명 (예: `modifedDate` → `modifiedDate`)
2. **상수 키/값**: `SORT_TYPE.MobilePriceAsc` 같은 키와 `'PriceAsc'` 같은 값 문자열
3. **문자열 리터럴**: 사용자 노출 메시지, API 파라미터 값
4. **주석**: `//`, `#`, `/* */` 안의 영어 단어

## 오류 카테고리

- **철자 오류**: `recieve` → `receive`, `occured` → `occurred`
- **대소문자 일관성**: 같은 파일 안에서 `ModifiedDate` vs `modifiedDate`, `LPG` vs `lpg` 혼용
- **복합어 표기 일관성**: `dataBase` vs `database`, `fileName` vs `filename` 혼용

## 검사 제외

- **한글**: 한글 키·값·주석·UI 문자열은 검사하지 않음 (예: `믿고:`, `// 정렬조건`, `title="엔카진단 차량 확인 방법"`)
- **외부 패키지 심볼**: import한 함수/컴포넌트/props 이름은 패키지 API이므로 수정 대상이 아님 (예: `@encarpkg/design`의 `useUniversalCloser`)
- **로깅/분석 필드명**: `screenname` 같은 지표 시스템 필드는 서버 스펙이므로 오타처럼 보여도 보고만 하고 수정 전 확인 요청
- **기술 약어**: `LPG`, `CNG`, `LNG`, `API`, `URL` 등 (`.spell-check-ignore` 목록으로 관리)
- **의도된 축약**: 널리 쓰이는 관례 (`src`, `params`, `impl` 등)

## Usage Examples

```bash
# 현재 파일 검사
/spell-check

# 특정 파일 검사
/spell-check --file src/constants.ts

# 디렉토리 검사
/spell-check --dir ./src --recursive

# 자동 수정 (interactive)
/spell-check --fix
```

## Output Format

**Issues Found:**
```
File: src/constants.ts
  Line 12 (Constant key):
    ❌ "MobileModifedDate" → should be "MobileModifiedDate"
    📍 Context: "MobileModifedDate: '최근 업데이트순',"

  Line 45 (Comment):
    ❌ "// recieve the message" → "// receive the message"

  Line 67 (Consistency):
    ⚠️ "PriceASC" vs "PriceAsc" — 같은 파일에서 표기 혼용
```

**Suggestions:**
```
✅ Ready to fix:
  - Replace 12 issues automatically? (y/n)
  - Review each change before applying? (y/R)
```

## 주의사항

⚠️ **식별자 수정은 참조까지 함께**: 상수 키나 변수명을 고칠 때는 해당 심볼을 참조하는
모든 위치를 함께 수정해야 합니다. 문자열 값(예: API 파라미터 `'PriceAsc'`)은
서버 스펙일 수 있으므로 오타처럼 보여도 수정 전에 확인을 요청합니다.

## Team Integration

이 스킬은:
- 파일 저장 직후 `PostToolUse`(Write|Edit)·`FileChanged` hook으로 자동 검사 — 저장을 막지 않음 (hooks/hooks.json 참고)
- `/spell-check --fix` 로 인터랙티브 수정 가능
- 팀 표준 단어 리스트 (.spell-check-ignore) 지원

## Implementation Notes

- **언어 모델 활용**: Claude가 문맥을 이해하면서 오류 감지 (camelCase/snake_case 분리 인식)
- **오탐지 방지**: 프로젝트별 ignore 목록 설정 가능
- **성능**: 대규모 파일은 자동으로 청크로 나눔
