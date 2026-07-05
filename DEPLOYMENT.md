# 팀 배포 체크리스트

## 1. 플러그인 검증 ✅
- [ ] **plugin.json과 marketplace.json의 version 범프** — 버전이 그대로면 팀원이 업데이트해도 설치된 캐시가 갱신되지 않음
- [ ] `claude plugin validate` 통과
- [ ] 모든 파일 경로 확인 (.claude-plugin/ 안에 plugin.json만)
- [ ] hooks/hooks.json 문법 확인
- [ ] scripts/*.sh 실행 권한 설정

```bash
chmod +x scripts/*.sh
claude plugin validate
```

## 2. 팀 표준 단어 정의 ✅
- [ ] `.spell-check-ignore` 단어 목록 검토 (팀 허용 단어가 이미 채워져 있음 — 형식은 파일 상단 주석 참고)

## 3. Hook 테스트 ✅
- [ ] 파일 저장 시 Hook 실행 확인
- [ ] 오류 감지 및 보고 확인
- [ ] false positive 최소화

```bash
# 테스트 파일 생성
echo "// This is a recieve operation" > test.js

# 저장하면 Hook이 오타 감지
```

## 4. 팀 가이드 작성 ✅
README에 추가:
- 무시 목록 관리 방법
- 커스텀 패턴 추가 방법
- 문제 보고 절차

## 5. 배포 ✅
- [ ] GitHub에 푸시
- [ ] `claude plugin tag --push` — 공식 규칙(`spell-check--v{version}`)으로 릴리스 태깅.
      다른 플러그인이 이 플러그인을 버전 제약(`dependencies`)으로 참조할 수 있게 됨
- [ ] 팀 메일링으로 설치 가이드 발송
- [ ] 팀원들이 설치 후 피드백

```bash
# 팀원들을 위한 설치 명령어 (검사 엔진 cspell은 최초 실행 시 자동 설치됨)
/plugin marketplace add simjieun/spell-check-plugin
/plugin install spell-check@team-tools
```

## 6. 모니터링 ✅
- [ ] 첫 주: false positive 수집
- [ ] `.spell-check-ignore` 업데이트
- [ ] Hook 성능 모니터링
- [ ] v1.1.0 업데이트로 개선사항 반영

---

## 문제 발생 시

### Hook이 느림
```bash
# 대용량 파일 제외
# scripts/check-spelling.sh의 should_check_file 확장자/IGNORE_PATTERNS 수정
```

### 자주 나는 오탐지
```bash
# .spell-check-ignore에 단어 추가
echo "TechTerm" >> .spell-check-ignore

# 또는 scripts/check-spelling.sh 패턴 수정
```

### 팀원들이 Hook 비활성화하고 싶어함
```bash
/plugin disable spell-check@team-tools
```

---

## 성공 지표
- ✅ 팀의 60% 이상 설치
- ✅ 월 평균 10개 이상 오타 감지
- ✅ False positive < 10%
- ✅ 팀 피드백 기반 업데이트 2회 이상
