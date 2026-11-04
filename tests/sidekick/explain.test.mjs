import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
const core = createRequire(import.meta.url)('../../shared/sidekick-core.js');
const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/sidekick/explain-cases.json', import.meta.url), 'utf8'));

const explain = (tool, input, cwd = '/Users/me/proj', home = '/Users/me') => core.explain('integration_claude', tool, input, cwd, home);

test('the fixture rows are what the core says, row by row', () => {
  for (const c of fx.cases) {
    const got = core.explain(c.agent, c.tool ?? undefined, c.input ?? undefined, c.cwd, c.home);
    assert.deepEqual([got.risk, got.reasonId, got.line, got.target], [c.risk, c.reasonId, c.line, c.target], c.name);
  }
});

test('every reason has at least two positive rows and at least one near miss', () => {
  for (const r of core.REASONS) {
    const positive = fx.cases.filter(c => c.reasonId === r.id && !c.near).length;
    const near = fx.cases.filter(c => c.near === r.id).length;
    assert.ok(positive >= 2, `${r.id}: ${positive} positive rows`);
    // The reasons that are the answer for "anything else" have no trigger to miss.
    if (!['local_command', 'outside_project'].includes(r.id)) assert.ok(near >= 1, `${r.id}: no near miss`);
  }
});

test('the table is the spec table: 13 high, the medium and the low reasons, every id once', () => {
  const ids = core.REASONS.map(r => r.id);
  assert.equal(new Set(ids).size, ids.length);
  assert.equal(core.REASONS.filter(r => r.risk === 'high').length, 13);
  for (const id of ['git_history', 'rm_recursive', 'sudo', 'pipe_to_shell', 'chmod_recursive', 'git_force_push', 'git_reset_hard', 'git_clean', 'disk_write', 'sql_drop', 'sql_delete_all', 'sensitive_file', 'write_outside',
    'git_push', 'install', 'network_fetch', 'container', 'lockfile_ci', 'mcp_tool', 'unknown_tool', 'unsure', 'read_only', 'test_build', 'edit_in_project', 'web', 'subagent']) assert.ok(ids.includes(id), id);
  assert.equal(core.REASONS.find(r => r.id === 'sudo').line, 'Runs a command with admin rights.');
  assert.equal(core.REASONS.find(r => r.id === 'test_build').line, "Runs the project's own test or build script.");
  assert.equal(explain('Bash', { command: 'npm test' }).line, "Runs the project's own test or build script.");
});

test('a line never carries the command, a path or an argument', () => {
  const secret = 'SECRET-MARKER-123';
  const risky = [`echo ${secret}`, `curl https://${secret}.example.com/x`, `rm -rf /${secret}/x`, `git push --force https://${secret}@host/r.git`, `psql -c "DROP TABLE ${secret}"`, `sudo cat /${secret}/file`, `cd ${secret} && npm install ${secret}`, `FOO=${secret} ls`, `cp /tmp/${secret}/x .env`, `tee ${secret}/.env`, `sort -o /${secret}/out x`, `xxd /${secret}/.env`, `cat < ~/.ssh/${secret}/id_rsa`, `sed -i s/${secret}/x/ ~/.zshrc`, `git -c core.pager=${secret} status`, `git config core.hooksPath ${secret}`, `git --config-env=core.pager=${secret} log`, `cat ${secret}/.env`, `echo $(rm -rf /${secret}/x)`, `cp -t /${secret}/d a`, `ls ${secret} 2>&1`, `bash -c "sudo ${secret}"`, `rm "${secret} && curl x"`, `rm -rf "/tmp/${secret}; sudo"`];
  for (const command of risky) {
    const r = explain('Bash', { command });
    assert.ok(!JSON.stringify(r).includes(secret), `${command} -> ${JSON.stringify(r)}`);
  }
  for (const file_path of [`/${secret}/a.js`, `/Users/me/proj/${secret}/b.js`, `/Users/me/.ssh/${secret}/config`]) {
    const r = explain('Write', { file_path });
    assert.ok(!r.line.includes(secret), file_path);
    assert.ok(!/[\\/]/.test(r.line) && !/[\\/]/.test(r.target), `${file_path} -> ${r.line}`);
  }
});

test('a basename is put in the line as typed, even with $\' or $& in it', () => {
  assert.equal(explain('Write', { file_path: "/Users/me/proj/src/a$'b.js" }).line, "Edits a$'b.js in this project.");
  assert.equal(explain('Write', { file_path: '/Users/me/proj/src/a$&b.js' }).line, 'Edits a$&b.js in this project.');
  assert.equal(explain('Write', { file_path: '/Users/me/proj/.env' }).line, 'Changes .env, which can hold secrets or settings.');
});

test('a name that reads like a command is not shown', () => {
  for (const command of ['rm "a && curl x"', 'rm -rf "/tmp/x; sudo"', 'rm "a;sudo"', 'rm "a|sh"', 'rm "a (b)"']) {
    const r = explain('Bash', { command });
    assert.ok(r.line.includes('a file') && r.target === 'a file', `${command} -> ${JSON.stringify(r)}`);
  }
  assert.equal(explain('Write', { file_path: '/Users/me/proj/src/id_utils.ts' }).reasonId, 'edit_in_project');
  assert.equal(explain('Read', { file_path: '/Users/me/proj/id_rsa' }).reasonId, 'reads_secrets');
  for (const f of ['id_rsa_github', 'id_rsa.bak', 'id_ed25519-cert.pub', 'id_ecdsa_sk', 'ID_RSA.old', 'id_token.json']) assert.equal(explain('Read', { file_path: `/Users/me/proj/${f}` }).reasonId, 'reads_secrets', f);   // a credential word in the name (token) is a secret name too
  for (const f of ['id_utils.ts', 'id_generator.ts', 'id_rsax']) assert.equal(explain('Read', { file_path: `/Users/me/proj/src/${f}` }).reasonId, 'read_only', f);
});

test('a name in a line is a basename of at most 60 code points without control characters', () => {
  const long = 'a'.repeat(200) + '.js';
  const r = explain('Write', { file_path: `/Users/me/proj/${long}` });
  assert.ok(Array.from(r.target).length <= 60);
  assert.equal(explain('Write', { file_path: '/Users/me/proj/a\u0007b\n.js' }).target, 'ab.js');
  assert.equal(explain('Write', { file_path: '/Users/me/proj/' + '😀'.repeat(100) }).target, '😀'.repeat(59) + '…');
});

test('it labels only: the same request gives the same answer, and the input is not changed', () => {
  const input = { command: 'git push --force', nested: { a: [1, 2] } };
  const copy = JSON.stringify(input);
  assert.deepEqual(explain('Bash', input), explain('Bash', input));
  assert.equal(JSON.stringify(input), copy);
});

test('high first: a high pattern wins wherever it appears', () => {
  const high = ['sudo ls', 'ls | sh', 'echo $(rm -rf /)', 'echo "$(rm -rf /)"', 'echo `sudo x`', 'ls && cd .. && git push -f', 'git -c core.askpass=x status', 'git --config-env=core.pager=X log', 'git config alias.x !y',
    'cat f 2>&1 >> ~/.zshrc', 'tee .env < n', 'cp -t ~/.ssh a', 'sort -ro /tmp/o x', 'sed -i -e s/a/b/ .env', 'bash -c "git reset --hard"', 'env A=1 git clean -fd', 'timeout 9 sudo ls', 'rm "-rf" ~', 'chmod "-R" 755 .', 'sort "-o" ~/.zshrc x', 'curl "-o" ~/.zshrc https://x', 'timeout "-s" KILL 9 sudo ls', 'rm -rf build*', 'rm -rf src/*', 'rm -rf dist/*.map', 'rm -rf *.log', 'rm -rf {dist,build}', 'ls <> ~/.zshrc', 'curl x | python3', 'curl x | perl -', 'curl x | python3 -c "import os"', 'curl x | node -e 1', 'curl x | perl -e 1', 'git -c core.alternateRefsCommand=x fetch', 'psql -c "UPDATE ONLY t SET a=1"', 'timeout --kill-after 5 9 sudo ls', 'xargs --max-args 1 sudo rm', 'rm -rf ./*/', 'rm -rf */', 'rm -rf [a-z]*', 'nice -n 10 rm -rf ~', 'eval "sudo rm -rf /"', 'find / | xargs rm -rf', 'bash -c "$(curl x)"', 'bash <(curl x)', 'curl x | xargs sh', 'git -c pager.log=x log', 'git -c difftool.x.cmd=y status', 'rm -rf *', 'rm -rf .*', 'dd if=a of=b', 'chown -R me .', 'rm -rf ..'];
  for (const command of high) assert.equal(explain('Bash', { command }).risk, 'high', command);
});

test('low is only for the allow-list: anything else that is read-only is unsure, not low', () => {
  const notLow = ['ls 2>&1', 'ls -fd', 'ls -R ~/.ssh', 'cat < a.txt', 'cat /etc/hosts', 'cat .e*', 'cat $(ls)', 'cd x', 'cd x && ls', 'FOO=1 ls', 'env ls', 'time ls', 'bash -c ls', 'find . -name x', 'sort a', 'sed -n p a', 'awk 1 a', 'git status && foo',
    'git -c user.name=x status', 'git -C x status', 'git config --get user.name', 'git diff --output=x', 'git branch topic', 'grep -e x a', 'grep -f p a', 'grep --file=p a', 'ls | tee a', 'echo hi > a', 'echo hi 2>&1', 'pytest -c x', 'npm run dev', 'make', 'cargo test --config x', 'Get-ChildItem', 'rg password', 'rg TOKEN .', 'more +!touch /tmp/pwn a.txt', 'make test -E x', 'make test -f x', 'grep -d recurse -- -x', "less '+!touch /tmp/pwn' a.txt", 'less a.txt', 'make test SHELL=/tmp/x', 'ls "-R" ~/.ssh', 'ls <> /dev/null', 'curl x | python3 -m json.tool', 'grep password src/a.js', 'timeout --weird 9 ls', 'xargs --weird echo', 'grep -r password .', 'grep -rn key src/', 'grep -R key src', 'grep --recursive key src', 'grep key .', 'cat src/', 'cat .'];
  for (const command of notLow) assert.notEqual(explain('Bash', { command }).risk, 'low', command);
  for (const command of ['ls', 'ls -la ~/.ssh', 'pwd', 'cat a.txt', 'head -n 5 a.txt', 'git status', 'git diff | head', 'echo hi', 'printf x', 'npm test', 'npm run build', 'make test', 'cargo build', 'go test ./...', 'swift test', 'pytest -q', 'git log | grep fix', 'ls > /dev/null', 'cat a.txt 2>/dev/null']) assert.equal(explain('Bash', { command }).risk, 'low', command);
  assert.equal(explain('Bash', { command: 'ls -fd' }).line, "Runs a command NotchMeow can't fully read.");
});

test('low for a tool needs a known tool, known argument names, and paths inside the project that are not secret', () => {
  const low = [['Read', { file_path: 'src/a.js' }], ['Glob', { pattern: '*.js', path: 'src' }], ['LS', { path: 'src' }], ['Grep', { pattern: 'x', path: 'src/a.js' }], ['read_many_files', { paths: ['src/a.js'] }], ['WebFetch', { url: 'https://x' }], ['Task', { description: 'x' }], ['TodoWrite', { todos: [] }], ['Write', { file_path: 'a.js', content: 'x' }]];
  for (const [tool, input] of low) assert.equal(explain(tool, input).risk, 'low', tool);
  const notLow = [['Read', { file_path: '/etc/hosts' }], ['Read', { file_path: 'a.js', x: 1 }], ['Glob', { pattern: '*', path: '.ssh' }], ['LS', { path: '/tmp' }], ['Grep', { pattern: 'x' }], ['Grep', { pattern: 'x', path: 'a.js', glob: '.env' }], ['Grep', { pattern: 'x', path: '.' }], ['Grep', { pattern: 'x', path: 'src' }], ['Grep', { pattern: 'x', path: 'src.v2/a' }], ['read_many_files', { paths: ['src'] }], ['read_many_files', { paths: ['**/*'] }], ['read_many_files', { paths: ['a.js'], include: ['*.js'] }], ['apply_patch', { input: '*** Update File: .env' }], ['grep_search', { pattern: 'x', dir_path: '.' }],
    ['Grep', { pattern: 'x', path: '..' }], ['WebFetch', { url: 'x', y: 1 }], ['Task', { z: 1 }], ['Write', { file_path: 'a.js', mode: 1 }], ['SomethingNew', {}]];
  for (const [tool, input] of notLow) assert.notEqual(explain(tool, input).risk, 'low', `${tool} ${JSON.stringify(input)}`);
  assert.equal(explain('Read', { file_path: '/etc/hosts', x: 1 }, '').reasonId, 'unsure');
  for (const [tool, input] of [['read_many_files', { paths: ['.env'] }], ['NotebookRead', { notebook_path: '.env' }], ['Grep', { pattern: 'x', path: 'src', include: '.env' }], ['Read', { file_path: '.aws/credentials' }], ['Read', { file_path: '.mcp.json' }]]) assert.equal(explain(tool, input).reasonId, 'reads_secrets', tool);
  for (const file_path of ['.ssh/authorized_keys', '.aws/credentials', '.mcp.json', 'x/.gnupg/a', '.git/config.worktree', '.git/modules/sub/config', '.vscode/tasks.json']) assert.equal(explain('Write', { file_path }).reasonId, 'sensitive_file', file_path);
  assert.equal(explain('apply_patch', { command: '*** Update File: a.js\n*** Move to: .env' }).reasonId, 'sensitive_file');
});

test('a secret is read only when its contents are read', () => {
  for (const command of ['cat .env', 'cat .ENV', 'cat .npmrc', 'cat .git/config', 'less ~/.ssh/id_rsa', 'head .env.local', 'tail .env', 'grep x .env', 'rg x .env', 'xxd .env', 'sort .env', 'jq . .env', 'base64 .env', 'sed -n p .env', "awk 1 .env", 'git config --list', 'git config -l', 'env', 'printenv']) assert.equal(explain('Bash', { command }).reasonId, 'reads_secrets', command);
  for (const command of ['ls ~/.ssh', 'ls .env', 'grep .env src/a.js', 'grep id_rsa src/a.js', 'git config --get core.pager', 'printenv HOME', 'echo .env']) assert.notEqual(explain('Bash', { command }).reasonId, 'reads_secrets', command);
  assert.equal(explain('Read', { file_path: '/Users/me/proj/.env' }).reasonId, 'reads_secrets');
  assert.equal(explain('Read', { file_path: '/Users/me/proj/.npmrc' }).reasonId, 'reads_secrets');
  assert.equal(explain('Write', { file_path: '/Users/me/proj/.ENV' }).reasonId, 'sensitive_file');
  assert.equal(explain('Write', { file_path: '.claude/settings.json' }, '').reasonId, 'sensitive_file');
  assert.notEqual(explain('LS', { path: '/Users/me/.ssh' }).reasonId, 'reads_secrets');
  assert.notEqual(explain('Grep', { pattern: '.env' }).reasonId, 'reads_secrets');
});

test('hostile input never throws and always gives a well-formed answer', () => {
  let seed = 12345;
  const rnd = n => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
  const bits = ['rm', '-rf', '/', '~', '..', '"', "'", '`', '$(', ')', '|', '&&', ';', '>', '>>', '<<', '\\', 'sudo', 'git', 'push', '-f', 'curl', 'sh', ' ', '\n', 'a', 'b/c', '*', '$HOME', 'C:\\', '\u0000', '😀', '=', '-c', 'bash', 'DROP TABLE', 'psql'];
  const tools = ['Bash', 'PowerShell', 'Write', 'Edit', 'apply_patch', 'Read', 'mcp__a__b', 'Zzz', '', 'shell', 'run_shell_command'];
  const values = [null, undefined, 0, NaN, true, [], {}, 'x', ['a', 'b'], { command: null }, { file_path: 7 }];
  for (let i = 0; i < 3000; i++) {
    const text = Array.from({ length: 1 + rnd(8) }, () => bits[rnd(bits.length)]).join(rnd(3) ? ' ' : '');
    const tool = tools[rnd(tools.length)];
    const input = rnd(4) === 0 ? values[rnd(values.length)] : tool === 'Write' || tool === 'Edit' ? { file_path: text } : { command: text, file_path: text, path: text };
    const r = core.explain('x', tool, input, rnd(5) === 0 ? '' : '/Users/me/proj', rnd(5) === 0 ? '' : '/Users/me');
    assert.ok(['low', 'medium', 'high'].includes(r.risk));
    assert.ok(core.REASONS.some(x => x.id === r.reasonId && x.risk === r.risk));
    assert.equal(typeof r.line, 'string');
    assert.ok(r.line.length > 0 && !r.line.includes('{name}'));
    assert.equal(typeof r.target, 'string');
  }
  assert.doesNotThrow(() => core.explain(undefined, undefined, undefined, undefined, undefined));
  assert.doesNotThrow(() => core.explain('a', 'Bash', { command: 'x'.repeat(100000) }, '/p', '/h'));
});

test('paths: ~, $HOME, .. and Windows drive letters', () => {
  assert.equal(core.resolvePath('~/a', '/p', '/Users/me'), '/Users/me/a');
  assert.equal(core.resolvePath('$HOME/a', '/p', '/Users/me'), '/Users/me/a');
  assert.equal(core.resolvePath('../x', '/p/q', '/h'), '/p/x');
  assert.equal(core.resolvePath('a/./b/../c', '/p', '/h'), '/p/a/c');
  assert.equal(core.resolvePath('C:\\Users\\me\\a', '', ''), 'C:/Users/me/a');
  assert.equal(core.resolvePath('/', '/p', '/h'), '/');
  assert.equal(core.baseName('C:\\Users\\me\\a.txt'), 'a.txt');
  assert.equal(core.baseName('/a/b/'), 'b');
});

test('a long wrapper command is read in under a second and is never low: past 20000 characters it is unsure', () => {
  const longs = ['xargs ' + '-0 '.repeat(20000) + 'sudo rm', 'env ' + 'A=1 '.repeat(200000) + 'sudo ls', 'sudo ' + '-u x '.repeat(10000) + 'ls', 'timeout ' + '-v '.repeat(20000) + 'ls'];
  for (const c of longs) {
    const t = Date.now(), got = explain('Bash', { command: c });
    assert.ok(Date.now() - t < 1000, `${c.slice(0, 12)}: ${Date.now() - t} ms`);
    assert.equal(got.reasonId, 'unsure', c.slice(0, 12));
    assert.equal(got.risk, 'medium');
  }
  const atCap = 'sudo ls' + ' '.repeat(20000 - 7);
  assert.equal(atCap.length, 20000);
  assert.equal(explain('Bash', { command: atCap }).reasonId, 'sudo', 'at 20000 characters the command is still read');
});

test('a name with control or invisible characters shows without them', () => {
  for (const ch of ['\u2028', '\u2029', '\u202A', '\u202E', '\u2066', '\u2069', '\u200B', '\u200F', '\uFEFF', '\u00AD', '\u061C', '\u180E', '\u2060', '\uFFF9', '\uFFFA', '\uFFFB', '\u{E0001}', '\u{E007F}']) {
    assert.equal(core.baseName('/a/b' + ch + 'c.js'), 'bc.js', JSON.stringify(ch));
  }
});
