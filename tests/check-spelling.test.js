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
function runFile(file, env = {}) {
  return spawnSync(script, [file], {
    env: { ...process.env, ...env },
    encoding: 'utf8',
  });
}

// hook 모드: stdin으로 PreToolUse JSON 전달
function runHook(toolInput, env = {}) {
  return spawnSync(script, [], {
    env: { ...process.env, ...env },
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

// 3. strict 모드: 오타 발견 시 exit 2로 저장 차단, stderr로 Claude에게 전달
r = runFile(writeTmp('strict.js', '// occured yesterday\n'), { SPELL_CHECK_STRICT: 'true' });
assert.equal(r.status, 2, `expected exit 2, got ${r.status}`);
assert.match(r.stderr, /blocking save/);

// 4. strict 모드라도 오타가 없으면 통과해야 한다
r = runFile(writeTmp('clean.js', '// receive the message\n'), { SPELL_CHECK_STRICT: 'true' });
assert.equal(r.status, 0, r.stderr);

// 5. hook 모드(Write): stdin JSON의 content(저장될 새 내용)에서 오타를 감지해야 한다
r = runHook({ file_path: 'src/api.js', content: '// recieve the data' });
assert.equal(r.status, 0, r.stderr);
assert.match(r.stdout, /should be 'receive'/);

// 6. hook 모드(Edit): content 대신 new_string이 와도 검사해야 한다
r = runHook({ file_path: 'src/api.js', new_string: '// occured yesterday' });
assert.equal(r.status, 0, r.stderr);
assert.match(r.stdout, /should be 'occurred'/);

// 7. hook 모드: content가 없는 JSON(다른 도구 등)은 조용히 통과해야 한다
r = runHook({ file_path: 'src/api.js' });
assert.equal(r.status, 0, r.stderr);
assert.equal(r.stdout, '');

// 8. 지원하지 않는 확장자(.py)는 검사하지 않아야 한다
r = runHook({ file_path: 'src/main.py', content: '# recieve the data' });
assert.equal(r.status, 0, r.stderr);
assert.equal(r.stdout, '');

// 9. 무시 패턴 경로(node_modules)는 검사하지 않아야 한다
r = runHook({ file_path: 'node_modules/pkg/index.js', content: '// recieve the data' });
assert.equal(r.status, 0, r.stderr);
assert.equal(r.stdout, '');

// 10. js 파일은 주석만 검사한다 — 코드(문자열 리터럴)의 오타는 무시해야 한다
r = runFile(writeTmp('code-only.js', 'const msg = "recieve the data";\n'));
assert.equal(r.status, 0, r.stderr);
assert.match(r.stdout, /No spelling errors found/);

console.log('all check-spelling tests passed');
