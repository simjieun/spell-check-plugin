// check-spelling.sh 테스트 (프레임워크 없음 — node tests/check-spelling.test.js 로 실행)
const assert = require('assert');
const { spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = path.join(__dirname, '..');
const script = path.join(root, 'scripts', 'check-spelling.sh');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'spell-check-test-'));
process.on('exit', () => fs.rmSync(tmp, { recursive: true, force: true }));

// 인자 모드: check-spelling.sh <파일경로>
// (cspell이 없으면 스크립트가 최초 1회 자동 설치하므로 첫 실행은 느릴 수 있음)
function runFile(file, env = {}) {
  return spawnSync(script, [file], {
    env: { ...process.env, ...env },
    encoding: 'utf8',
  });
}

// hook 모드: stdin으로 PostToolUse JSON 전달 (저장은 이미 완료 → 디스크 파일을 검사)
const hookLog = path.join(tmp, 'hook.log');
function runHook(toolInput, env = {}) {
  return spawnSync(script, [], {
    env: { ...process.env, SPELL_CHECK_LOG_FILE: hookLog, ...env },
    input: JSON.stringify({ tool_name: 'Write', tool_input: toolInput }),
    encoding: 'utf8',
  });
}

function writeTmp(name, content) {
  const file = path.join(tmp, name);
  fs.writeFileSync(file, content);
  return file;
}

// 1. 알려진 오타는 감지되어야 한다 (비 strict: 경고만 하고 exit 0)
let r = runFile(writeTmp('bad.js', '// recieve the message\n'));
assert.equal(r.status, 0, r.stderr);
assert.match(r.stdout, /should be 'receive'/);
assert.match(r.stdout, /Found 1 potential spelling issues/);

// 2. .spell-check-ignore에 등록된 단어("dont")는 오탐지되지 않아야 한다
r = runFile(writeTmp('ignored.js', '// dont forget to check this\n'));
assert.equal(r.status, 0, r.stderr);
assert.match(r.stdout, /No spelling errors found/);

// 3. PostToolUse 모드(Write): 오타 발견 시 exit 2 + stderr로 Claude에게 피드백 (저장 차단 아님)
r = runHook({ file_path: writeTmp('hook-bad.js', '// recieve the data\n') });
assert.equal(r.status, 2, `expected exit 2, got ${r.status}`);
assert.match(r.stderr, /not blocking/);
assert.match(r.stdout, /should be 'receive'/);

// 4. PostToolUse 모드: 오타가 없으면 조용히 통과해야 한다
r = runHook({ file_path: writeTmp('hook-clean.js', '// receive the data\n') });
assert.equal(r.status, 0, r.stderr);

// 5. 수동(인자) 모드는 오타가 있어도 exit 0 — 경고만 출력
r = runFile(writeTmp('manual.js', '// occured yesterday\n'));
assert.equal(r.status, 0, r.stderr);
assert.match(r.stdout, /should be 'occurred'/);

// 6. PostToolUse 모드(Edit): 수정 조각(new_string)이 아니라 디스크의 파일 "전체"를 검사해야 한다
//    — 수정된 부분은 깨끗해도 파일 다른 곳(3번째 줄)의 기존 오타를 잡고, 라인 번호도 실제 파일 기준
const editedFile = writeTmp('hook-edit.js', '// clean line\n// also clean\n// occured yesterday\n');
r = runHook({ file_path: editedFile, new_string: '// clean line' });
assert.equal(r.status, 2, `expected exit 2, got ${r.status}`);
assert.match(r.stdout, /Line 3: 'occured' → should be 'occurred'/);

// 7. hook 모드: file_path가 없거나 디스크에 없는 파일이면 조용히 통과해야 한다
r = runHook({});
assert.equal(r.status, 0, r.stderr);
assert.equal(r.stdout, '');
r = runHook({ file_path: path.join(tmp, 'does-not-exist.js') });
assert.equal(r.status, 0, r.stderr);
assert.equal(r.stdout, '');

// 8. 지원하지 않는 확장자(.py)는 검사하지 않아야 한다
r = runHook({ file_path: writeTmp('main.py', '# recieve the data\n') });
assert.equal(r.status, 0, r.stderr);
assert.equal(r.stdout, '');

// 9. 무시 패턴 경로(node_modules)는 검사하지 않아야 한다
fs.mkdirSync(path.join(tmp, 'node_modules', 'pkg'), { recursive: true });
r = runHook({ file_path: writeTmp(path.join('node_modules', 'pkg', 'index.js'), '// recieve the data\n') });
assert.equal(r.status, 0, r.stderr);
assert.equal(r.stdout, '');

// 10. js 파일은 전체 소스를 검사한다 — 코드(문자열 리터럴)의 오타도 잡아야 한다
r = runFile(writeTmp('code-only.js', 'const msg = "recieve the data";\n'));
assert.equal(r.status, 0, r.stderr);
assert.match(r.stdout, /should be 'receive'/);

// 10-1. 식별자 내부 오타도 camelCase/snake_case 분리로 잡아야 한다
r = runFile(writeTmp('identifier.js', 'function getSeperator() {}\nconst dont_flag = 1;\n'));
assert.equal(r.status, 0, r.stderr);
assert.match(r.stdout, /should be 'Separator'/);
// dont는 .spell-check-ignore에 등록되어 있어 snake_case 분리 후에도 오탐하지 않아야 한다
assert.doesNotMatch(r.stdout, /'dont'/);

// 10-2. 사전 기반 검사 — 알려진 오타 목록에 없는 임의의 오타(discoint)도 잡아야 한다
r = runFile(writeTmp('unknown-word.tsx', "const el = cx('discoint_price');\n"));
assert.equal(r.status, 0, r.stderr);
assert.match(r.stdout, /'discoint'/);

// 11. FileChanged hook 모드: 사용자가 에디터에서 저장한 디스크 파일을 검사해야 한다
r = spawnSync(script, [], {
  env: { ...process.env, SPELL_CHECK_LOG_FILE: hookLog },
  input: JSON.stringify({ hook_event_name: 'FileChanged', file_path: writeTmp('changed.js', '// recieve the message\n') }),
  encoding: 'utf8',
});
assert.equal(r.status, 0, r.stderr);
assert.match(r.stdout, /should be 'receive'/);

// 12. hook 모드는 실행 로그를 남겨야 한다 (모드와 파일 경로 포함)
const logContent = fs.readFileSync(hookLog, 'utf8');
assert.match(logContent, /\[PostToolUse\] .*hook-bad\.js/);
assert.match(logContent, /\[FileChanged\] .*changed\.js/);

// 12-1. 고유 오타가 256개여도 통과로 오판하지 않아야 한다
//       (오타 개수를 함수 반환 코드로 전달하는데 bash 반환 코드는 256에서 0으로 래핑됨)
const manyWords = [];
const alpha = 'abcdefghijklmnopqrstuvwxyz';
outer: for (const x of alpha) for (const y of alpha) { manyWords.push(`zq${x}${y}vex`); if (manyWords.length === 256) break outer; }
r = runFile(writeTmp('many-typos.md', manyWords.join(' ') + '\n'));
assert.equal(r.status, 0, r.stderr);
assert.match(r.stdout, /Found \d+ potential spelling issues/);
assert.doesNotMatch(r.stdout, /No spelling errors found/);

// 13. --warm (SessionStart hook): 검사 없이 cspell만 확보하고 조용히 종료해야 한다
r = spawnSync(script, ['--warm'], { env: { ...process.env, SPELL_CHECK_LOG_FILE: hookLog }, encoding: 'utf8' });
assert.equal(r.status, 0, r.stderr);
assert.equal(r.stdout, '');
assert.ok(fs.existsSync(path.join(root, 'node_modules', '.bin', 'cspell')), 'cspell not installed by --warm');

console.log('all check-spelling tests passed');
