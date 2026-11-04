/**
 * The agent sidekick's rules, written once and shared (sub-project F1, docs/SIDEKICK-CONTRACT.md).
 *
 * Pure: no clock, no network, no files, no randomness. Every rule takes the time it needs as an argument. Both apps port these rules and replay
 * tests/fixtures/sidekick/*.json, which scripts/gen-sidekick-fixtures.mjs writes from this file. If an app and a fixture disagree, this file decides.
 *
 * The sidekick labels and remembers. It never blocks, allows or denies anything, and it keeps no prompt, no assistant text, no command, no full
 * path and no file content: lines carry basenames and counts only.
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.SidekickCore = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
'use strict';
const api = { VERSION: 1 };

// ── Helpers ──────────────────────────────────────────────────────────────────
const MIN = 60000;
const isObj = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const isStr = x => typeof x === 'string';
const isNum = x => typeof x === 'number' && Number.isFinite(x);
/** The last component of a path, `/` or `\` alike, without control and invisible characters (bidi overrides, zero-width marks, line separators), at most 60 code points. Lines carry nothing else of a path. */
const baseName = p => {
  const s = String(p).replace(/[\\/]+$/, '');
  const i = Math.max(s.lastIndexOf('/'), s.lastIndexOf('\\'));
  const cps = Array.from((i >= 0 ? s.slice(i + 1) : s).replace(/[\u0000-\u001f\u007f-\u009f\u00AD\u061C\u180E\u200B-\u200F\u202A-\u202E\u2028\u2029\u2060\u2066-\u2069\uFEFF\uFFF9-\uFFFB\u{E0000}-\u{E007F}]/gu, ''));
  return cps.length > 60 ? cps.slice(0, 59).join('') + '…' : cps.join('');
};

// ── Task 1: explain, the risk rules ─────────────────────────────────────────

/** Every reason, in the order that breaks a tie between two of the same risk (the earlier one wins). `{name}` is a basename, never a path or a command. */
const REASONS = [
  ['git_history', 'high', "Deletes this project's git history."],   // first of the high ones: a delete inside .git is this, not a recursive delete of a name
  ['rm_recursive', 'high', 'Deletes {name} and everything inside it.'],
  ['sudo', 'high', 'Runs a command with admin rights.'],
  ['pipe_to_shell', 'high', 'Downloads a script and runs it at once.'],
  ['chmod_recursive', 'high', 'Changes permissions on {name} and everything inside it.'],
  ['git_force_push', 'high', 'Overwrites the remote branch history.'],
  ['git_reset_hard', 'high', 'Throws away local changes.'],
  ['git_clean', 'high', "Deletes files git doesn't track."],
  ['disk_write', 'high', 'Writes straight to a disk.'],
  ['sql_drop', 'high', 'Deletes a database table or database.'],
  ['sql_delete_all', 'high', 'Changes every row in a table.'],
  ['sensitive_file', 'high', 'Changes {name}, which can hold secrets or settings.'],
  ['write_outside', 'high', 'Changes {name}, outside this project.'],
  ['git_push', 'medium', 'Sends commits to a remote.'],
  ['install', 'medium', 'Installs software.'],
  ['network_fetch', 'medium', 'Talks to another computer.'],
  ['container', 'medium', 'Controls containers.'],
  ['lockfile_ci', 'medium', 'Changes {name}, which affects every build.'],
  ['reads_secrets', 'medium', 'Reads {name}, which can hold secrets.'],
  ['mcp_tool', 'medium', 'Uses a tool from an add-on.'],
  ['unknown_tool', 'medium', 'Uses a tool NotchMeow doesn’t know.'],
  ['unsure', 'medium', "Runs a command NotchMeow can't fully read."],
  ['outside_project', 'medium', 'Touches {name}, outside this project.'],
  ['rm_in_project', 'medium', 'Deletes {name} in this project.'],
  ['read_only', 'low', 'Only reads files.'],
  ['test_build', 'low', "Runs the project's own test or build script."],
  ['edit_in_project', 'low', 'Edits {name} in this project.'],
  ['web', 'low', 'Reads a web page.'],
  ['subagent', 'low', 'Starts a helper agent.'],
  ['local_command', 'low', 'Does a simple local step.'],
];
const REASON = Object.fromEntries(REASONS.map(([id, risk, line], order) => [id, { id, risk, line, order }]));
const RISK_RANK = { low: 0, medium: 1, high: 2 };
api.REASONS = REASONS.map(([id, risk, line]) => ({ id, risk, line }));

// ── Paths ────────────────────────────────────────────────────────────────────
/** `p` against `cwd`: `~` and `$HOME` become `home`, `.` and `..` fold away, `\` is `/`. A relative path with no `cwd` stays relative. */
function resolvePath(p, cwd, home) {
  let s = String(p).replace(/\\/g, '/');
  if (home) s = s.replace(/^(~|\$HOME|\$\{HOME\})(?=\/|$)/, String(home).replace(/\\/g, '/').replace(/\/+$/, ''));
  if (!/^(\/|[A-Za-z]:\/|~)/.test(s)) s = (cwd ? String(cwd).replace(/\\/g, '/').replace(/\/+$/, '') : '.') + '/' + s;
  const m = /^((?:[A-Za-z]:)?\/|~\/?)?([\s\S]*)$/.exec(s);
  const root = m[1] || '', out = [];
  for (const seg of m[2].split('/')) {
    if (seg === '' || seg === '.') continue;
    if (seg === '..') { if (out.length && out[out.length - 1] !== '..') out.pop(); else if (!root) out.push('..'); } else out.push(seg);
  }
  const r = root + out.join('/');
  return r.length > 1 && r.endsWith('/') && !/^[A-Za-z]:\/$/.test(r) ? r.slice(0, -1) : (r || '.');
}
const isAbs = r => /^(\/|[A-Za-z]:\/|~)/.test(r);
const lc = r => (/^[A-Za-z]:\//.test(r) ? r.toLowerCase() : r);
const under = (r, root) => { const a = lc(r), b = lc(root); return a === b || a.startsWith(b.endsWith('/') ? b : b + '/'); };
/** 'inside', 'outside' or 'unknown' (an absolute path when the project folder is not known). */
function where(p, cwd, home) {
  const r = resolvePath(p, cwd, home);
  if (!cwd) return isAbs(r) ? 'unknown' : r.startsWith('..') ? 'outside' : 'inside';
  return under(r, resolvePath(cwd, '', home)) ? 'inside' : 'outside';
}
const isHomeFolder = (r, home) => (home && lc(r) === lc(resolvePath(home, '', ''))) || /^(\/(Users|home)\/[^/]+|[A-Za-z]:\/Users\/[^/]+)$/i.test(r) || r === '~';

// ── What a file path means ───────────────────────────────────────────────────
const SHELL_RC = new Set(['.bashrc', '.bash_profile', '.bash_login', '.bash_logout', '.profile', '.zshrc', '.zshenv', '.zprofile', '.zlogin', '.zlogout', 'config.fish']);
const LOCKFILES = new Set(['package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'bun.lockb', 'Cargo.lock', 'Gemfile.lock', 'poetry.lock', 'Pipfile.lock', 'composer.lock', 'go.sum', 'Podfile.lock', 'Package.resolved', '.gitlab-ci.yml', 'Jenkinsfile', 'azure-pipelines.yml']);
const SECRET_NAMES = new Set(['.npmrc', '.netrc', '.pypirc', '.mcp.json', '.pgpass', '.yarnrc.yml', '.gitmodules', 'kubeconfig']);
/** Names that start with one of these are secret: terraform.tfstate.backup is the state's backup. */
const SECRET_STEMS = ['terraform.tfstate'];
/** Source, doc and style extensions: a credential word in such a name (token.ts, tokenizer.ts, password_reset.md, tokens.css) is a plain name, not a secret. */
const SOURCE_EXT = /\.(ts|tsx|js|jsx|mjs|cjs|py|rs|go|swift|kt|java|rb|md|txt|css|scss|less|html)$/;   // not config or data formats (yml, yaml, toml, sh): they carry secret values
function sensitivePath(r, home) {
  const b = baseName(r).toLowerCase();   // macOS and Windows ignore case: `.ENV` is `.env`
  // A basename that holds a credential word is a secret name (credentials.json, secrets.yml, token.json, .vault-token, .htpasswd); `.env` may be a suffix (prod.env).
  // A source, doc or style file is not, unless its name is exactly `credentials` or `secrets` (any extension).
  const stem = b.split('.')[0];
  const keyword = /credential|secret|token|passw/.test(b) && !(SOURCE_EXT.test(b) && stem !== 'credentials' && stem !== 'secrets');
  if (b.startsWith('.env') || b.endsWith('.env') || SECRET_NAMES.has(b) || SECRET_STEMS.some(s => b.startsWith(s)) || keyword || /\.(pem|key|p12|pfx|keystore|jks|p8|tfvars)$/.test(b) || /^id_(rsa|dsa|ecdsa|ed25519)(_sk)?([._-].*)?$/.test(b) || SHELL_RC.has(b)) return true;
  // git's and the editors' files that run or hold settings; the agents' hooks and commands, and the git hooks folder, run code
  if (/(^|\/)(\.git\/(?!objects\/|refs\/|logs\/)|\.husky(\/|$)|\.githooks(\/|$)|\.claude\/(hooks|commands)(\/|$)|\.(vscode|cursor)\/(tasks|mcp|launch|settings)\.json$)/i.test(r) || /(^|\/)\.claude\/settings[^/]*\.json$/i.test(r)) return true;
  // The folders of keys and logins, in the home folder or in any other: ssh, aws, gnupg, kubernetes, docker, and the GitHub CLI's config
  // A folder named secrets, at any depth, holds secrets like .ssh does
  return /(^|\/)\.(ssh|aws|gnupg|kube|docker)(\/|$)/i.test(r) || /(^|\/)\.config\/gh(\/|$)/i.test(r) || /(^|\/)secrets(\/|$)/i.test(r);
}
const lockOrCi = r => LOCKFILES.has(baseName(r)) || /(^|\/)\.github\/workflows\//.test(r) || /(^|\/)\.circleci\//.test(r);

/** The candidate for writing to one path: `{reason, target}`. */
function writeCandidate(p, cwd, home) {
  const r = resolvePath(p, cwd, home), w = where(p, cwd, home);
  if (sensitivePath(r, home)) return { reason: 'sensitive_file', target: baseName(r) };
  if (w === 'outside') return { reason: 'write_outside', target: baseName(r) };
  if (w === 'unknown') return { reason: 'unsure', target: '' };
  if (lockOrCi(r)) return { reason: 'lockfile_ci', target: baseName(r) };
  return { reason: 'edit_in_project', target: baseName(r) };
}

// ── Shell commands ───────────────────────────────────────────────────────────
/**
 * Splits a command at `&&`, `||`, `;`, `|`, `&`, newlines, `(` and `)`, respecting quotes. Each part is `{args, redirs, op}`: the words (`{text, quoted}`), the redirects
 * (`{out, dup, rw, target}`; the target of `2>&1` is `&1` and `dup` is true) and the operator that follows. `ps` (PowerShell) reads `\` as a path separator, not an escape.
 * `opaque` says some of the text can't be followed as words: `$(…)`, backticks, `<(…)`, a subshell, a here-document or an open quote.
 */
function splitShell(cmd, ps) {
  const s = String(cmd), parts = [];
  let toks = [], cur = '', has = false, quoted = false, q = '', opaque = false;
  const push = () => { if (has) toks.push({ text: cur, quoted }); cur = ''; has = false; quoted = false; };
  const end = op => {
    push();
    const args = [], redirs = [];
    for (let k = 0; k < toks.length; k++) {
      if (toks[k].redir) { const t = toks[k + 1]; if (t) redirs.push({ out: toks[k].out, dup: !!toks[k].dup, rw: !!toks[k].rw, target: t.text }); k++; } else args.push(toks[k]);
    }
    parts.push({ args, redirs, op });
    toks = [];
  };
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (q === "'") { if (c === "'") q = ''; else cur += c; continue; }
    if (q === '"') {
      if (c === '"') q = '';
      else if (c === '\\' && !ps && i + 1 < s.length && '$`"\\\n'.includes(s[i + 1])) cur += s[++i];
      else { if (c === '`' || (c === '$' && s[i + 1] === '(')) opaque = true; cur += c; }
      continue;
    }
    if (c === "'" || c === '"') { q = c; has = true; quoted = true; continue; }
    if (c === '\\') { if (ps) { cur += c; has = true; } else if (i + 1 < s.length) { cur += s[++i]; has = true; } continue; }
    if (c === '`' || c === '(' || c === ')') { opaque = true; end(c); continue; }
    if ((c === '$' || c === '<' || c === '>') && s[i + 1] === '(') { opaque = true; if (c !== '$') { push(); toks.push({ text: c + '(', quoted: false }); } continue; }
    if (c === '<' && s[i + 1] === '<') opaque = true;   // a here-document or here-string: its body is not a command we follow
    if (c === ' ' || c === '\t' || c === '\r') { push(); continue; }
    if (c === '\n') { end('\n'); continue; }
    if (c === ';') { end(';'); continue; }
    if (c === '&' && s[i + 1] === '&') { end('&&'); i++; continue; }
    if (c === '|' && s[i + 1] === '|') { end('||'); i++; continue; }
    if (c === '|') { if (s[i + 1] === '&') i++; end('|'); continue; }
    if (c === '&' && s[i + 1] === '>') continue;   // `&>` and `&>>`: the `>` that follows is the redirect
    if (c === '&') { end('&'); continue; }
    if (c === '>' || c === '<') {
      if (!/^\d*$/.test(cur) || quoted) push(); else { cur = ''; has = false; }   // `2>` names a stream, not an argument
      let op = c; while (s[i + 1] === c) op += s[++i];
      if (c === '>' && s[i + 1] === '|') i++;
      const dup = c === '>' && s[i + 1] === '&' ? /^(\d+|-)/.exec(s.slice(i + 2)) : null;   // `>&2` copies a stream; `>&file` writes a file
      if (c === '>' && s[i + 1] === '&') i++;
      const rw = c === '<' && s[i + 1] === '>';   // `<>` opens the file for reading and writing
      if (rw) i++;
      toks.push({ text: op, quoted: false, redir: true, out: c === '>' || rw, dup: !!dup, rw });
      if (dup) { toks.push({ text: '&' + dup[0], quoted: false }); i += dup[0].length; }
      continue;
    }
    cur += c; has = true;
  }
  if (q) opaque = true;
  end('');
  return { parts: parts.filter(p => p.args.length || p.redirs.length), opaque };
}

const own = () => Object.create(null);   // a table keyed by what a command line says: no `constructor` or `__proto__` to find
const SHELLS = new Set(['sh', 'bash', 'zsh', 'dash', 'fish', 'ksh', 'csh', 'tcsh', 'ash']);
const WRITE_CMDS = new Set(['cp', 'mv', 'ln', 'touch', 'mkdir', 'install', 'tee']);
const WRITE_FLAGS = new Set(['sensitive_file', 'write_outside', 'unsure', 'lockfile_ci']);
/** The flag that names an output file: [short letter, long name]. */
const OUT_FLAG = Object.assign(own(), { sort: ['o', '--output'], curl: ['o', '--output'], wget: ['O', '--output-document'] });
/** Commands that read the contents of the files they are given. For the ones in PROG_FIRST the first operand is a pattern or a program, not a file. */
const READERS = new Set(['cat', 'tac', 'less', 'more', 'head', 'tail', 'grep', 'egrep', 'fgrep', 'rg', 'ag', 'xxd', 'od', 'hexdump', 'strings', 'sort', 'uniq', 'cut', 'nl', 'wc', 'jq', 'base64', 'sed', 'awk']);
const PROG_FIRST = new Set(['grep', 'egrep', 'fgrep', 'rg', 'ag', 'sed', 'awk', 'jq']);
const GIT_READS = new Set(['diff', 'show', 'log', 'blame', 'grep', 'cat-file']);
/** Git keys that run a program: `git -c` or `--config-env` with one of them, or `git config` writing one, is never a plain step. */
const EXEC_KEY = /^(core\.(askpass|sshcommand|hookspath|pager|fsmonitor|editor|gitproxy|alternaterefscommand)|uploadpack\.packobjectshook|submodule\..+\.update|tar\..+\.command|sequence\.editor|filter\..+|diff\.(.+\.)?(external|textconv|command)|merge\..+\.driver|gpg\.(.+\.)?program|credential\..*helper|includeif?\..+|alias\..+|pager\..+|(difftool|mergetool)\..+\.cmd|interactive\.difffilter)$/i;
const GIT_NET = new Set(['fetch', 'pull', 'clone']);
const INSTALL_SUBS = new Set(['install', 'i', 'add', 'ci', 'update', 'upgrade', 'remove', 'uninstall', 'link', 'sync', 'require', 'reinstall']);
const NET_CMDS = new Set(['curl', 'wget', 'ssh', 'scp', 'sftp', 'rsync', 'nc', 'ncat', 'ftp', 'telnet']);
const CONTAINER_CMDS = new Set(['docker', 'podman', 'kubectl', 'helm', 'docker-compose', 'minikube']);
const SQL_CLIS = new Set(['psql', 'mysql', 'mariadb', 'sqlite3', 'sqlcmd', 'mongosh']);
const plain = args => args.filter(a => !/^-/.test(a.text));   // the shell strips quotes, so "-R" is the flag -R

// The allow-list (spec rule: only plain, fully-read forms are low; everything else a command can be is `unsure`).
// A form is low only with no redirect except to /dev/null, no `-c`/`-e`/`-f`/`-o` style flag (a flag must be in the lists below), no substitution, and only low parts in a chain or pipe.
/** command -> [what its operands may be, the reason]: 'none', 'text' (anything), 'any' (a listing: any path), 'file' (inside the project and not a secret). */
const PLAIN = Object.assign(own(), { pwd: ['none', 'read_only'], ls: ['any', 'read_only'], echo: ['text', 'local_command'], printf: ['text', 'local_command'] });
for (const c of ['cat', 'head', 'tail', 'wc', 'file', 'stat', 'du', 'df']) PLAIN[c] = ['file', 'read_only'];
PLAIN.grep = ['none', 'read_only'];   // after its pattern grep may name no file: it reads stdin (a file could be .env, a folder could hold it)
const PLAIN_GIT = Object.assign(own(), { status: 'file', diff: 'file', log: 'file', show: 'file', 'rev-parse': 'file', branch: 'none' });
/** The project's own test and build commands, as the words that start a plain form. */
const PLAIN_TESTS = ['npm test', 'npm run test', 'npm run build', 'npm run lint', 'make test', 'make build', 'cargo test', 'cargo build', 'go test', 'go build', 'swift build', 'swift test', 'pytest'];
const SAFE_SHORT = /^-[AaBbdEFGHhIiJjkLlmNnqRrSsTvwXx0-9]+$/;
const SAFE_LONG = /^--(stat|shortstat|numstat|name-only|name-status|oneline|graph|decorate|cached|staged|short|porcelain|branch|no-color|color|all|almost-all|human-readable|show-current|list|abbrev-ref|show-toplevel|verify|summary|workspace|release|all-targets|lib|bins|tests|no-fail-fast|nocapture|quiet|verbose|locked|frozen|offline|silent|if-present)$/;

/** The basename of a secrets file that `w` names (`rev:path` counts its path), or null. */
function secretName(w, cwd, home) {
  for (const x of [w.slice(w.lastIndexOf(':') + 1), w]) { const r = resolvePath(x, cwd, home); if (x && sensitivePath(r, home)) return baseName(r); }   // `rev:path` names its path first: HEAD:.env is .env
  return null;
}
/** The values of a flag: `-o FILE`, `-oFILE`, `-ro FILE` (a clustered flag takes the next word), `--output FILE`, `--output=FILE`. */
function flagValues(rest, short, long) {
  const v = [];
  rest.forEach((a, i) => {
    const t = a.text;
    if (!t.startsWith('-')) return;
    if (t.startsWith('--')) { if (t === long) { if (rest[i + 1]) v.push(rest[i + 1].text); } else if (t.startsWith(long + '=')) v.push(t.slice(long.length + 1)); return; }
    const k = t.indexOf(short, 1);
    if (k > 0) { const x = k + 1 < t.length ? t.slice(k + 1) : rest[i + 1] ? rest[i + 1].text : ''; if (x) v.push(x); }
  });
  return v;
}
/** The plain words of a command that name files: the pattern or program of grep, sed, awk and jq is not one, unless -e, --expression, --regexp or -f / --file gives it. */
function fileWords(name, rest) {
  const pl = plain(rest).map(a => a.text);
  if (!PROG_FIRST.has(name)) return pl;
  const given = [...flagValues(rest, 'e', '--expression'), ...flagValues(rest, 'e', '--regexp')];
  given.forEach(g => { const k = pl.indexOf(g); if (k >= 0) pl.splice(k, 1); });
  return given.length || flagValues(rest, 'f', '--file').length ? pl : pl.slice(1);
}

/** What each wrapper's options are: `val` take the next word as their value, `bool` take none. Any other option leaves the command word unknown. */
const WRAP = Object.assign(own(), {
  timeout: { val: ['-s', '-k', '--signal', '--kill-after'], bool: ['-v', '--foreground', '--preserve-status', '--verbose'] },
  nice: { val: ['-n', '--adjustment'], bool: [] },
  ionice: { val: ['-c', '-n', '-p', '-P', '-u', '--class', '--classdata', '--pid', '--pgid', '--uid'], bool: ['-t', '--ignore'] },
  stdbuf: { val: ['-i', '-o', '-e', '--input', '--output', '--error'], bool: [] },
  xargs: { val: ['-I', '-n', '-P', '-L', '-s', '-d', '-E', '-a', '-R', '-S', '--max-args', '--max-procs', '--max-lines', '--max-chars', '--delimiter', '--arg-file'], bool: ['-0', '-r', '-t', '-p', '-x', '-o', '--null', '--no-run-if-empty', '--verbose', '--interactive', '--exit', '--open-tty'] },
});
/**
 * Takes the options of a wrapper off the front of `a` (what is left starts at the command it runs). An option that is not in the wrapper's lists, or a long one with a
 * separate value we don't know, leaves the command word unknown: then everything before the first `sudo`, `doas` or `rm` is dropped, and with none of them nothing is left (unsure).
 */
function skipWrapper(a, w) {
  for (;;) {
    const f = a[0] && /^-./.test(a[0].text) ? a[0].text : null;
    if (f === null) return;
    a.shift();
    if (f === '--') return;
    if (w.val.includes(f)) a.shift();
    else if (f.includes('=') || w.bool.includes(f) || /^-\d+$/.test(f) || (!f.startsWith('--') && f.length > 2 && w.val.includes(f.slice(0, 2)))) continue;   // --signal=KILL, -n10, -I{}
    else { const k = a.findIndex(x => /^(sudo|doas|rm)$/.test(baseName(x.text))); a.splice(0, k < 0 ? a.length : k); return; }
  }
}
/** Looks through the words that only prefix a command: `VAR=1`, `env`, `time`, `command`, `nohup`, `sudo` and `doas` (which is remembered). */
function skipPrefix(args) {
  const a = args.slice();
  let sudo = false;
  for (;;) {
    const t = a[0] && a[0].text, b = t && baseName(t);
    if (!t) break;
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(t) && !a[0].quoted) { a.shift(); continue; }
    if (b === 'sudo' || b === 'doas') { sudo = true; a.shift(); while (a[0] && /^-/.test(a[0].text)) { const f = a.shift().text; if (/^-[ugCpD]$/.test(f)) a.shift(); } continue; }
    if (b === 'env') { a.shift(); while (a[0] && (/^-/.test(a[0].text) || /^[A-Za-z_][A-Za-z0-9_]*=/.test(a[0].text))) a.shift(); continue; }
    if (['time', 'command', 'nohup', 'builtin', 'exec'].includes(b)) { a.shift(); continue; }
    if (WRAP[b] && b !== 'xargs') {   // timeout 9, nice -n 10, ionice -c 3, stdbuf -o L: options (some with a value), then the real command
      a.shift();
      skipWrapper(a, WRAP[b]);
      if (b === 'timeout' && a[0] && /^[0-9.]+[smhd]?$/.test(a[0].text)) a.shift();   // its duration
      continue;
    }
    break;
  }
  return { sudo, args: a };
}

/** The reason id (low) when one part of a command is on the allow-list, else null. The command word is read as typed: `/tmp/x/ls` and `FOO=1 ls` are not `ls`. */
function plainReason(part, cwd, home) {
  if (part.redirs.some(r => r.dup || r.rw || r.target !== '/dev/null')) return null;
  const c = part.args[0];
  if (!c) return null;
  const words = part.args.slice(1);
  let rule, reason = 'read_only', args = words;
  if (PLAIN[c.text]) [rule, reason] = PLAIN[c.text];
  else if (c.text === 'git' && words[0] && !words[0].quoted && PLAIN_GIT[words[0].text]) { rule = PLAIN_GIT[words[0].text]; args = words.slice(1); }
  else {
    const p = PLAIN_TESTS.find(x => [c, ...words].map(a => a.text).join(' ').concat(' ').startsWith(x + ' '));
    if (p !== undefined) { rule = 'file'; reason = 'test_build'; args = words.slice(p.split(' ').length - 1); if (c.text === 'make' && args.length) return null; }   // make test takes no flag and no operand
  }
  if (!rule) return null;
  const ops = [];
  let flags = '';
  for (const a of args) {
    if (!a.text.startsWith('-')) { ops.push(a.text); continue; }
    if (a.text === '--') continue;
    if (!(rule === 'text' ? /^-[neE]+$/ : SAFE_SHORT).test(a.text) && !SAFE_LONG.test(a.text)) return null;
    flags += a.text;
  }
  if (PROG_FIRST.has(c.text)) ops.shift();
  if (c.text === 'grep' && /-[A-Za-z]*[rRd]/.test(flags)) return null;   // -r, -R and -d recurse reach every file under the folder
  const isFile = o => !/[$*?[{=]/.test(o) && !o.endsWith('/') && where(o, cwd, home) === 'inside' && lc(resolvePath(o, cwd, home)) !== lc(resolvePath(cwd || '.', '', home)) && secretName(o, cwd, home) === null;   // not a folder
  const ok = rule === 'none' ? !ops.length : rule === 'file' ? ops.every(isFile) : rule === 'any' ? !(/R/.test(flags) && ops.some(o => secretName(o, cwd, home) !== null)) : true;
  return ok ? reason : null;
}

/** The candidates of one command line, `[{reason, target}]`; never empty. High patterns are found in every part and wherever the text hides them, then the allow-list gives low, and any part neither knows is `unsure`. */
function shellCandidates(cmd, cwd, home, depth, ps) {
  const found = [];
  const add = (reason, target = '') => found.push({ reason, target });
  const writeTo = p => { const c = writeCandidate(p, cwd, home); if (WRITE_FLAGS.has(c.reason)) found.push(c); };
  const name = p => baseName(resolvePath(p, cwd, home));
  const outsideOf = paths => paths.find(p => where(p, cwd, home) !== 'inside');
  const command = (args, part, piped) => {
    const cmdName = baseName(args[0].text), rest = args.slice(1), pl = plain(rest).map(a => a.text);
    if (piped && (SHELLS.has(cmdName) || (/^(python[0-9.]*|node|deno|bun|ruby|perl|php|lua|Rscript|(pwsh|powershell)(\.exe)?)$/.test(cmdName) && !(rest[0] && rest[0].text === '-m' && rest.length > 1)))) add('pipe_to_shell');   // a shell, or an interpreter (its script comes from stdin or from -c / -e), unless it only runs a module (python3 -m json.tool)
    // A script fetched and run at once: `bash -c "$(curl …)"`, `bash <(curl …)`, `source <(wget …)`.
    if ((SHELLS.has(cmdName) || cmdName === 'source' || cmdName === '.') && /\b(curl|wget)\b/.test(cmd) && rest.some(a => a.text === '<(' || /\$\(|`/.test(a.text))) add('pipe_to_shell');
    if (SHELLS.has(cmdName)) {
      const ci = rest.findIndex(a => /^-[A-Za-z]*c$/.test(a.text));
      add('unsure');
      if (ci >= 0 && rest[ci + 1] && depth < 2) found.push(...shellCandidates(rest[ci + 1].text, cwd, home, depth + 1, ps));
      return;
    }
    if (cmdName === 'eval') {   // eval reads its words again as a command line
      add('unsure');
      if (depth < 2) found.push(...shellCandidates(rest.map(a => a.text).join(' '), cwd, home, depth + 1, ps));
      return;
    }
    if (cmdName === 'xargs') {   // the words after its options are the command it runs on what it is fed
      const x = rest.slice();
      skipWrapper(x, WRAP.xargs);
      const inner = skipPrefix(x);
      add('unsure');
      if (inner.sudo) add('sudo');
      if (inner.args.length) command(inner.args, part, true);
      return;
    }
    if (cmdName === 'rm' || cmdName.toLowerCase() === 'remove-item') {
      // Deleting .git or anything inside it (the history, the config, the objects): high, recursive or not
      if (pl.some(t => /(^|\/)\.git(\/|$)/i.test(resolvePath(t, cwd, home)))) { add('git_history'); return; }
      const rec = rest.some(a => (/^-[A-Za-z]*[rR][A-Za-z]*$/.test(a.text) || a.text === '--recursive' || /^-recurse$/i.test(a.text)));
      const all = t => /[*?[{]/.test(t);   // a glob under a recursive delete may match a whole folder: high, inside the project too (the owner's decision)
      const bad = pl.find(t => { const r = resolvePath(t, cwd, home); return all(t) || t === '{}' || r === '/' || /^[A-Za-z]:\/$/.test(r) || isHomeFolder(r, home) || r.includes('$') || where(t, cwd, home) !== 'inside' || (cwd && lc(r) === lc(resolvePath(cwd, '', home))); });
      const sec = pl.map(t => secretName(t, cwd, home)).find(n => n !== null);
      if (rec && !pl.length) add('rm_recursive');   // what to delete comes from somewhere else (xargs): never assume it is small
      else if (rec && bad !== undefined) { const rb = resolvePath(bad, cwd, home); add('rm_recursive', isHomeFolder(rb, home) ? '~' : /^([A-Za-z]:)?\/$/.test(rb) ? rb : name(all(bad) && where(bad, cwd, home) === 'inside' ? '.' : bad)); }
      else if (sec !== undefined) add('sensitive_file', sec);
      else if (!rec && outsideOf(pl) !== undefined) add('outside_project', name(outsideOf(pl)));
      else add('rm_in_project', pl.length ? name(pl[0]) : '');
      return;
    }
    if (cmdName === 'chmod' || cmdName === 'chown' || cmdName === 'chgrp') {
      const paths = pl.slice(1);
      if (rest.some(a => (/^-[A-Za-z]*R[A-Za-z]*$/.test(a.text) || a.text === '--recursive'))) add('chmod_recursive', name(paths[paths.length - 1] || '.') || '/');
      else if (outsideOf(paths) !== undefined) add('outside_project', name(outsideOf(paths)));
      return;
    }
    if (cmdName === 'dd' || cmdName.startsWith('mkfs') || cmdName === 'fdisk' || (cmdName === 'diskutil' && /^(erase|partition|zero|secure)/i.test(pl[0] || ''))) { add('disk_write'); return; }
    if (cmdName === 'git') {
      const g = rest.slice();
      while (g[0] && /^-/.test(g[0].text)) {
        const f = g.shift().text;
        if ((f === '-c' || f === '--config-env') && g[0]) { if (EXEC_KEY.test(g.shift().text.split('=')[0])) add('sensitive_file', 'config'); }
        else if (f.startsWith('--config-env=')) { if (EXEC_KEY.test(f.slice(13).split('=')[0])) add('sensitive_file', 'config'); }
        else if (f === '-C') g.shift();
      }
      const sub = g[0] ? g[0].text : '', fl = g.slice(1).map(a => a.text), vals = fl.filter(t => !/^-/.test(t));
      if (sub === 'config') {
        if (vals.length > 1 && vals.some(v => EXEC_KEY.test(v)) && !fl.some(f => /^--get/.test(f))) add('sensitive_file', 'config');
        else if (fl.includes('--list') || fl.includes('-l')) add('reads_secrets', 'config');
      } else if (sub === 'push') add(fl.some(f => /^--force(-with-lease|-if-includes)?(=|$)/.test(f) || /^-[A-Za-z]*f[A-Za-z]*$/.test(f) || /^\+/.test(f)) ? 'git_force_push' : 'git_push');
      else if (sub === 'reset') { if (fl.includes('--hard')) add('git_reset_hard'); }
      else if (sub === 'clean') { if (fl.some(f => f === '--force' || /^-[A-Za-z]*f/.test(f))) add('git_clean'); }
      else if (GIT_NET.has(sub)) add('network_fetch');
      if (GIT_READS.has(sub)) { const n = vals.map(v => secretName(v, cwd, home)).find(x => x !== null); if (n !== undefined) add('reads_secrets', n); }
      return;
    }
    if (OUT_FLAG[cmdName]) flagValues(rest, ...OUT_FLAG[cmdName]).forEach(writeTo);
    if (NET_CMDS.has(cmdName)) { add('network_fetch'); return; }
    if (CONTAINER_CMDS.has(cmdName)) { add('container'); return; }
    if (SQL_CLIS.has(cmdName)) {   // the whole text, so `echo "DROP TABLE x" | psql` is read too
      for (const st of String(cmd).split(';')) {
        if (/\bDROP\s+(TABLE|DATABASE|SCHEMA|INDEX|VIEW)\b/i.test(st) || /\.(drop|dropDatabase)\s*\(/.test(st)) { add('sql_drop'); return; }
        if (((/\bDELETE\s+FROM\b/i.test(st) || /\bUPDATE[^;]*?\bSET\b/i.test(st) || /\bTRUNCATE\b/i.test(st)) && !/\bWHERE\b/i.test(st)) || /deleteMany\(\s*\{\s*\}\s*\)/.test(st)) { add('sql_delete_all'); return; }
      }
      return;
    }
    if (['npm', 'pnpm', 'yarn', 'bun'].includes(cmdName)) { if (INSTALL_SUBS.has(pl[0] || '')) add('install'); return; }
    if (['pip', 'pip3', 'pipx', 'uv', 'brew', 'gem', 'apt', 'apt-get', 'composer', 'poetry', 'conda', 'port'].includes(cmdName)) { if (pl.some(x => INSTALL_SUBS.has(x))) add('install'); return; }
    if (cmdName === 'cargo' || cmdName === 'go') { if (['install', 'add', 'get'].includes(pl[0])) add('install'); return; }
    if (WRITE_CMDS.has(cmdName)) {
      // The destinations: every argument of touch, mkdir, tee and install -d; the target of -t / --target-directory; else the last one of cp, mv, ln and install.
      // The other arguments of cp, mv, ln and install are read sources, so only an outside one is named.
      const tv = flagValues(rest, 't', '--target-directory');
      if (['touch', 'mkdir', 'tee'].includes(cmdName) || (cmdName === 'install' && rest.some(a => a.text === '-d'))) pl.forEach(writeTo);
      else if (tv.length) tv.forEach(writeTo);
      else { if (pl.length) writeTo(pl[pl.length - 1]); for (const s of pl.slice(0, -1)) if (where(s, cwd, home) !== 'inside') add('outside_project', name(s)); }
      return;
    }
    if (cmdName === 'sed' && rest.some(a => /^(-[A-Za-z]*i|--in-place)/.test(a.text))) fileWords('sed', rest).forEach(writeTo);
    if (READERS.has(cmdName)) {
      const n = [...fileWords(cmdName, rest), ...part.redirs.filter(r => !r.out).map(r => r.target)].map(w => secretName(w, cwd, home)).find(x => x !== null);
      if (n !== undefined) add('reads_secrets', n);
    }
  };

  const { parts, opaque } = splitShell(cmd, ps);
  const lists = [parts];
  if (opaque) { add('unsure'); lists.push(splitShell(String(cmd).replace(/["'`]/g, ' '), ps).parts); }   // quotes can hide a substitution: read the text again without them
  for (const list of lists) list.forEach((part, idx) => {
    const low = plainReason(part, cwd, home);
    if (low) { add(low); return; }
    const start = found.length, raw = part.args;
    if (raw.length === 1 && ['env', 'printenv'].includes(baseName(raw[0].text))) { add('reads_secrets', 'environment'); return; }   // with no argument they print every variable
    const { sudo, args } = skipPrefix(raw);
    if (sudo) add('sudo');
    for (const r of part.redirs) {
      if (!r.out || r.dup || /^\/dev\/(null|stdout|stderr|tty|zero)$/.test(r.target)) continue;
      if (/^\/dev\//.test(r.target)) add('disk_write'); else writeTo(r.target);
    }
    if (args.length) command(args, part, idx > 0 && list[idx - 1].op === '|');
    if (found.length === start) add('unsure');
  });
  if (!found.length) add('unsure');
  return found;
}

const SHELL_TOOLS = new Set(['Bash', 'PowerShell', 'run_shell_command', 'shell', 'local_shell', 'exec_command']);
const READ_TOOLS = new Set(['Read', 'Glob', 'Grep', 'LS', 'NotebookRead', 'read_file', 'read_many_files', 'list_directory', 'search_file_content', 'grep_search', 'glob', 'grep_files']);
/** The arguments each known tool takes. LOW needs a known tool, only these argument names, and paths inside the project that are not secret; the rest is `unsure` (an unknown tool is `unknown_tool`). */
const TOOL_ARGS = Object.assign(own(), {
  Read: 'file_path offset limit pages', Glob: 'pattern path', Grep: 'pattern path output_mode -i -n -A -B -C context multiline head_limit offset include', LS: 'path ignore', NotebookRead: 'notebook_path cell_id',
  Write: 'file_path content', Edit: 'file_path old_string new_string replace_all', MultiEdit: 'file_path edits', NotebookEdit: 'notebook_path new_source cell_id cell_type edit_mode',
  read_file: 'file_path absolute_path path offset limit', read_many_files: 'paths include exclude recursive useDefaultExcludes respect_git_ignore respect_gemini_ignore',
  list_directory: 'dir_path path ignore file_filtering_options respect_git_ignore respect_gemini_ignore', search_file_content: 'pattern dir_path path include', grep_search: 'pattern dir_path path include',
  glob: 'pattern dir_path path case_sensitive respect_git_ignore respect_gemini_ignore', grep_files: 'pattern include path limit',
  write_file: 'file_path content', replace: 'file_path old_string new_string instruction expected_replacements', edit_file: 'file_path old_string new_string', apply_patch: 'command',
  WebFetch: 'url prompt', WebSearch: 'query allowed_domains blocked_domains', web_fetch: 'url prompt', google_web_search: 'query', web_search: 'query',
  Task: 'description prompt subagent_type model run_in_background resume', Agent: 'description prompt subagent_type model run_in_background resume',
  TodoWrite: 'todos', write_todos: 'todos', ExitPlanMode: 'plan', AskUserQuestion: 'questions', Skill: 'skill args',
});
const SEARCH_TOOLS = new Set(['Grep', 'search_file_content', 'grep_search', 'grep_files']);
/** The read tools that read file contents; a listing or a glob reads names only. */
const CONTENT_TOOLS = new Set(['Read', 'Grep', 'NotebookRead', 'read_file', 'read_many_files', 'search_file_content', 'grep_search', 'grep_files']);
const WEB_TOOLS = new Set(['WebFetch', 'WebSearch', 'web_fetch', 'google_web_search', 'web_search']);
const WRITE_TOOLS = new Set(['Write', 'Edit', 'MultiEdit', 'NotebookEdit', 'write_file', 'replace', 'edit_file']);
const QUIET_TOOLS = new Set(['TodoWrite', 'ExitPlanMode', 'AskUserQuestion', 'write_todos', 'Skill']);
api.WRITE_TOOLS = [...WRITE_TOOLS, 'apply_patch'];

/** The command of a shell tool's input: a string, or an array like `["bash","-lc","ls"]` (Codex). */
function commandOf(input) {
  const c = input.command;
  if (isStr(c)) return c;
  if (Array.isArray(c) && c.every(isStr)) return c.length >= 3 && SHELLS.has(baseName(c[0])) && /^-[A-Za-z]*c$/.test(c[1]) ? c[2] : c.join(' ');
  return null;
}
/** The files a tool writes, from its input: `file_path`, `path`, `notebook_path`, or the `*** Update File:` lines of a Codex patch. */
function pathsOf(tool, input) {
  if (tool === 'apply_patch') {
    const t = isStr(input.command) ? input.command : isStr(input.patch) ? input.patch : '';
    return [...t.matchAll(/^\*\*\* (?:Add|Update|Delete) File: (.+)$|^\*\*\* Move to: (.+)$/gm)].map(m => (m[1] || m[2]).trim());
  }
  const p = [input.file_path, input.absolute_path, input.path, input.notebook_path, input.target_file].find(isStr);
  return p ? [p] : [];
}

/**
 * Says in plain words how risky one permission request is. Labels only: it never allows, denies or blocks. `agent` is the pill ID (reserved: every agent is read the
 * same way today). Returns `{risk, reasonId, line, target}`; the line is a fixed template with a basename in it and never holds a command, a path or an argument.
 * It never throws: anything it can't read is `medium` with the reason `unsure`.
 */
function explain(agent, tool, toolInput, cwd, home) {
  const finish = (reason, target) => {
    let name = target === '~' || /^([A-Za-z]:)?\/$/.test(target) ? target : target ? baseName(target) : '';
    if (/\s|[;|<>()]|(?<!\$)&/.test(name)) name = 'a file';   // a name that reads like a command is not shown
    const r = REASON[reason];
    return { risk: r.risk, reasonId: r.id, line: r.line.replace('{name}', () => name || 'a file'), target: r.line.includes('{name}') ? name : '' };
  };
  try {
    const t = isStr(tool) ? tool : '', input = isObj(toolInput) ? toolInput : {}, dir = isStr(cwd) ? cwd : '', h = isStr(home) ? home : '';
    let cands = null;
    // ponytail: a command over 20000 characters is unsure, not read: the wrapper skips shift their word list one word at a time (800 KB takes 7 s). Upgrade: index-based skips.
    if (SHELL_TOOLS.has(t)) { const c = commandOf(input); cands = c === null ? null : c.length > 20000 ? [{ reason: 'unsure', target: '' }] : shellCandidates(c, dir, h, 0, t === 'PowerShell'); }
    else if (t === 'apply_patch' || WRITE_TOOLS.has(t)) { const ps = pathsOf(t, input); cands = ps.length ? ps.map(p => writeCandidate(p, dir, h)) : null; }
    else if (READ_TOOLS.has(t)) {
      // Every field that names a file or a folder counts. A search of a folder, or of nothing (the whole project), may reach a secret: unsure.
      const asList = v => (isStr(v) ? [v] : Array.isArray(v) ? v.filter(isStr) : []);
      const named = ['file_path', 'absolute_path', 'path', 'dir_path', 'paths', 'notebook_path', 'target_file'].flatMap(k => asList(input[k]));
      const sec = CONTENT_TOOLS.has(t) ? [...named, ...asList(input.include)].find(p => sensitivePath(resolvePath(p, dir, h), h)) : undefined;
      const dirs = [...asList(input.path), ...asList(input.dir_path), ...asList(input.paths)];
      const notFile = p => p.endsWith('/') || !/\.(ts|tsx|js|jsx|mjs|json|md|txt|py|swift|rs|go|css|html|yml|yaml|toml)$/i.test(baseName(p)) || lc(resolvePath(p, dir, h)) === lc(resolvePath(dir || '.', '', h));   // a single file only with a known extension
      const wide = (SEARCH_TOOLS.has(t) && (!dirs.length || dirs.some(notFile))) || (t === 'read_many_files' && asList(input.paths).some(notFile));
      // Low needs every path inside the project and not secret (a listing of a secrets folder is not low either).
      const off = [...asList(input.paths), ...asList(input.include)].some(p => /[*?[{]/.test(p)) || named.some(p => where(p, dir, h) !== 'inside' || sensitivePath(resolvePath(p, dir, h), h) || (!dir && p === '.'));
      const noPath = ['Read', 'NotebookRead', 'LS', 'read_file', 'read_many_files', 'list_directory'].includes(t) && !named.some(p => p !== '');   // a content tool with no path to read (no text, or an empty one) is unsure, never low
      cands = [noPath ? { reason: 'unsure', target: '' } : sec !== undefined ? { reason: 'reads_secrets', target: baseName(resolvePath(sec, dir, h)) } : wide || off ? { reason: 'unsure', target: '' } : { reason: 'read_only', target: '' }];
    }
    else if (WEB_TOOLS.has(t)) cands = [{ reason: 'web', target: '' }];
    else if (t === 'Task' || t === 'Agent') cands = [{ reason: 'subagent', target: '' }];
    else if (QUIET_TOOLS.has(t)) cands = [{ reason: 'local_command', target: '' }];
    else if (t.startsWith('mcp__')) cands = [{ reason: 'mcp_tool', target: '' }];
    else if (t) cands = [{ reason: 'unknown_tool', target: '' }];
    if (cands && !SHELL_TOOLS.has(t) && TOOL_ARGS[t] && !Object.keys(input).every(k => TOOL_ARGS[t].split(' ').includes(k))) cands.push({ reason: 'unsure', target: '' });   // an argument nobody knows: never low
    if (!cands || !cands.length) return finish('unsure', '');
    const rank = c => RISK_RANK[REASON[c.reason].risk] * 100 - REASON[c.reason].order;
    const best = cands.reduce((a, b) => (rank(b) > rank(a) ? b : a));
    return finish(best.reason, best.target);
  } catch (e) { return finish('unsure', ''); }
}
api.explain = explain;
api.baseName = baseName;
api.resolvePath = resolvePath;

// ── Task 2: the ledger, and the adapter that feeds it ───────────────────────

const hasOwnKey = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
const AGENT_NAMES = { integration_claude: 'Claude Code', agent_cursor: 'Cursor', agent_codex: 'Codex', agent_gemini: 'Gemini CLI', agent_antigravity: 'Antigravity' };
/** The name of an agent for a person: Claude Code for `integration_claude`, `agent_<tag>` is the tag with a capital, and any other ID is "An agent". */
function agentName(agentId) {
  if (!isStr(agentId)) return 'An agent';
  if (hasOwnKey(AGENT_NAMES, agentId)) return AGENT_NAMES[agentId];
  const tag = agentId.startsWith('agent_') ? agentId.slice(6) : '';
  return tag ? tag[0].toUpperCase() + tag.slice(1) : 'An agent';
}
api.agentName = agentName;

// ── The command key ──────────────────────────────────────────────────────────
/** Canonical JSON: keys sorted (by UTF-16 code unit; the fixtures use ASCII keys), no spaces. A number is written by JSON.stringify, so the fixtures use whole numbers. */
const canon = v => (Array.isArray(v) ? '[' + v.map(canon).join(',') + ']' : isObj(v) ? '{' + Object.keys(v).sort().map(k => JSON.stringify(k) + ':' + canon(v[k])).join(',') + '}' : (JSON.stringify(v) ?? 'null'));
/** FNV-1a, 32 bits, over the UTF-8 bytes of a string (valid Unicode), as 8 lower-case hex digits. */
function fnv1a(s) {
  let h = 0x811c9dc5;
  for (const b of new TextEncoder().encode(s)) { h ^= b; h = Math.imul(h, 0x01000193) >>> 0; }
  return h.toString(16).padStart(8, '0');
}
/** What "the same step" means: the tool name and a hash of its input, whitespace in a command folded. Only the hash is ever stored. */
function commandKey(tool, input) {
  let v = input;
  if (isObj(input) && isStr(input.command)) v = { ...input, command: input.command.trim().replace(/\s+/g, ' ') };
  return `${isStr(tool) ? tool : ''}#${fnv1a(canon(v === undefined ? null : v))}`;
}
api.fnv1a = fnv1a;
api.commandKey = commandKey;

// ── eventFrom: a hook payload becomes a normalised event ─────────────────────
const CURSOR_BUNDLE = 'com.todesktop.230313mzl4w4u92';
/** Both the names the relays send and the agents' own (the Mac relay renames BeforeTool to PreToolUse and so on; the Windows one may not). */
const EVENT_KIND = {
  SessionStart: 'sessionStart', startup: 'sessionStart',
  UserPromptSubmit: 'prompt', BeforeAgent: 'prompt', PreInvocation: 'prompt',
  PreToolUse: 'preTool', BeforeTool: 'preTool',
  PostToolUse: 'tool', AfterTool: 'tool',
  PostToolUseFailure: 'failure',
  PermissionRequest: 'approvalAsked',
  Stop: 'stop', AfterAgent: 'stop', PostInvocation: 'stop', Interrupt: 'stop',
  StopFailure: 'stopFailure',
  SubagentStart: 'subagentStart', SubagentStop: 'subagentStop',
  SessionEnd: 'sessionEnd', exit: 'sessionEnd',
  Notification: 'notification',
};
/** Which pill a payload belongs to: a valid `nm_agent` (not "claude"), Codex in the GitHub build, Cursor by its bundle ID, else Claude Code. */
function agentIdOf(payload, opts) {
  const tag = isStr(payload.nm_agent) ? payload.nm_agent : '';
  if (tag === 'codex' && !(opts && opts.codex === false)) return 'agent_codex';
  if (tag !== 'claude' && /^[a-z0-9-]{1,24}$/.test(tag)) return 'agent_' + tag;
  if (isStr(payload.bundle_id) && payload.bundle_id.toLowerCase() === CURSOR_BUNDLE) return 'agent_cursor';
  return 'integration_claude';
}
/** The first 128 code points of a name or an id: a 1 MB session id is kept as 128 code points, so the ledger's size does not depend on what an agent sends. */
const cap128 = s => { const cps = Array.from(s); return cps.length > 128 ? cps.slice(0, 128).join('') : s; };
/**
 * Turns a hook payload into the event the ledger takes, or null for an event it does not know. `now` is the time the app received it (ms). `opts.codex` is false in
 * the App Store build. The event holds a basename, a command key and counts, never the prompt, the assistant's text, a command or a path.
 */
function eventFrom(payload, now, opts) {
  if (!isObj(payload) || !isNum(now)) return null;
  const name = isStr(payload.hook_event_name) ? payload.hook_event_name : '';
  if (!hasOwnKey(EVENT_KIND, name)) return null;
  let kind = EVENT_KIND[name];
  const tool = isStr(payload.tool_name) ? cap128(payload.tool_name) : '';
  const input = isObj(payload.tool_input) ? payload.tool_input : {};
  if (tool === 'AskUserQuestion' && (kind === 'preTool' || kind === 'approvalAsked')) kind = 'question';
  const sessionId = cap128([payload.session_id, payload.conversation_id].find(x => isStr(x) && x) || 'unknown');
  const cwd = isStr(payload.cwd) ? payload.cwd : '';
  const ev = { at: now, agentId: agentIdOf(payload, opts), sessionId, kind, name, tool, target: '', file: '', key: '', ok: kind !== 'failure' && kind !== 'stopFailure', project: cwd ? baseName(cwd) : '', subagentId: '' };
  if (kind === 'tool' || kind === 'failure' || kind === 'approvalAsked' || kind === 'preTool' || kind === 'question') {
    const files = pathsOf(tool, input);
    try { ev.key = commandKey(tool, input); } catch (e) { ev.key = `${tool}#too-deep`; }   // a 20,000-deep input overflows canon's recursion; the key is then the tool and a fixed marker
    ev.target = files.length ? baseName(files[0]) : ev.key;
    ev.file = files.length ? baseName(files[0]) : '';   // the name the recap may show: never the command key
  }
  if (kind === 'subagentStart' || kind === 'subagentStop') ev.subagentId = isStr(payload.agent_id) ? cap128(payload.agent_id) : '';
  return ev;
}
api.eventFrom = eventFrom;
/** The event for the user's click on an approval card: the app makes it (it is not a hook). */
api.approvalAnsweredEvent = (agentId, sessionId, now) => ({ at: now, agentId, sessionId, kind: 'approvalAnswered', name: '', tool: '', target: '', file: '', key: '', ok: true, project: '', subagentId: '' });

// ── The ledger ───────────────────────────────────────────────────────────────
const RING_MAX = 40, SESSIONS_MAX = 8, ENDED_KEEP_MS = 30 * MIN, SILENT_KEEP_MS = 12 * 60 * MIN, SUBAGENTS_MAX = 20;
const SEARCH_SET = new Set(['WebSearch', 'WebFetch', 'Grep', 'Glob', 'google_web_search', 'web_fetch', 'grep_search', 'search_file_content', 'glob', 'web_search', 'grep_files']);
/** The state a tool puts an agent in: a search tool is searching, any other is working (the cat's rule, design/prototype/cat-core.js). */
const toolState = t => (SEARCH_SET.has(t) ? 'searching' : 'working');
api.RING_MAX = RING_MAX; api.SESSIONS_MAX = SESSIONS_MAX;

api.emptyLedger = () => ({ sessions: [] });
const newSession = (ev, key) => ({ key, agentId: ev.agentId, sessionId: ev.sessionId, startedAt: ev.at, lastEventAt: ev.at, endedAt: null, state: 'idle', last: 'sessionStart', project: '', ring: [], pendingApprovalAt: null, pendingKey: null, subagents: {}, nudgedAt: null });
const copy = s => JSON.parse(JSON.stringify(s));
const isDone = s => s.endedAt !== null || s.state === 'finished' || s.state === 'error';

/** The sessions of a ledger that are objects: anything else in the list is nothing (a malformed ledger never throws). */
const sessionsOf = ledger => (isObj(ledger) && Array.isArray(ledger.sessions) ? ledger.sessions.filter(isObj) : []);
/** A session's ring: its entries that are objects, or none when the ring is not a list. */
const ringOf = s => (Array.isArray(s.ring) ? s.ring.filter(isObj) : []);

/** Drops the sessions that are over: 30 minutes after SessionEnd, 12 hours after the last event of one that never ended. */
function ledgerPrune(ledger, now) {
  const sessions = sessionsOf(ledger).filter(s => (s.endedAt !== null ? now - s.endedAt <= ENDED_KEEP_MS : now - s.lastEventAt <= SILENT_KEEP_MS));
  return { sessions };
}
api.ledgerPrune = ledgerPrune;

function applyEvent(s, ev) {
  s.lastEventAt = Math.max(s.lastEventAt, ev.at);
  if (ev.project) s.project = ev.project;
  if (ev.kind === 'notification') return;   // only the time of the last event moves: a finished session stays finished
  if (s.endedAt !== null && ev.kind !== 'sessionEnd') { s.endedAt = null; }
  if (!Array.isArray(s.ring)) s.ring = [];   // a ring that is not a list is an empty one
  if (!isObj(s.subagents)) s.subagents = {};
  const ring = (kind, o = {}) => { s.ring.push({ at: ev.at, kind, tool: ev.tool, target: ev.target, file: ev.file, key: ev.key, ok: true, ...o }); if (s.ring.length > RING_MAX) s.ring.splice(0, s.ring.length - RING_MAX); };
  const clearPending = () => { s.pendingApprovalAt = null; s.pendingKey = null; };
  switch (ev.kind) {
    case 'sessionStart': s.state = 'idle'; clearPending(); break;
    case 'prompt': s.state = 'thinking'; clearPending(); break;
    case 'preTool': s.state = toolState(ev.tool); break;
    case 'question': s.state = 'question'; break;
    case 'tool': case 'failure':
      ring(ev.kind, { ok: ev.kind === 'tool' });
      if (s.pendingKey !== null && ev.key === s.pendingKey) clearPending();
      if (s.pendingKey === null) s.state = 'thinking';   // while another request still waits, the cat stays on it
      break;
    case 'approvalAsked': ring('approvalAsked'); s.pendingApprovalAt = ev.at; s.pendingKey = ev.key; s.state = 'approval'; break;
    case 'approvalAnswered': ring('approvalAnswered', { tool: '', target: '' }); clearPending(); if (s.state === 'approval') s.state = 'working'; break;
    case 'stop': ring('stop', { tool: '', target: '' }); s.state = 'finished'; clearPending(); s.subagents = {}; break;
    case 'stopFailure': ring('stopFailure', { tool: '', target: '', ok: false }); s.state = 'error'; clearPending(); s.subagents = {}; break;
    case 'subagentStart': {
      ring('subagentStart', { tool: '', target: '' });
      if (ev.subagentId && ev.subagentId !== '__proto__') { s.subagents[ev.subagentId] = ev.at; const ids = Object.keys(s.subagents); if (ids.length > SUBAGENTS_MAX) delete s.subagents[ids.sort((a, b) => s.subagents[a] - s.subagents[b])[0]]; }
      break;
    }
    case 'subagentStop': ring('subagentStop', { tool: '', target: '' }); delete s.subagents[ev.subagentId]; break;
    case 'sessionEnd': s.endedAt = ev.at; s.state = 'finished'; clearPending(); s.subagents = {}; break;
  }
  s.last = ev.kind;
}

/**
 * The ledger after one event. Pure: the ledger it is given is not changed. The key of a session is `agentId|sessionId`. At most 8 sessions are kept (a finished one goes
 * first, the oldest first), each ring keeps its last 40 entries, and the ledger holds no prompt, no text of the assistant, no command, no full path and no file content.
 */
function ledgerApply(ledger, ev) {
  const base = ledger && Array.isArray(ledger.sessions) ? ledger : { sessions: [] };
  if (!isObj(ev) || !isStr(ev.agentId) || !isStr(ev.sessionId) || !isStr(ev.kind) || !isNum(ev.at)) return base;
  const key = `${ev.agentId}|${ev.sessionId}`;
  const sessions = ledgerPrune(base, ev.at).sessions;
  const i = sessions.findIndex(s => s.key === key);
  if (i < 0 && (ev.kind === 'sessionEnd' || ev.kind === 'notification')) return { sessions };   // a pruned or unknown session is not brought back
  const s = i >= 0 ? copy(sessions[i]) : newSession(ev, key);
  applyEvent(s, ev);
  if (i >= 0) sessions[i] = s; else sessions.push(s);
  while (sessions.length > SESSIONS_MAX) {
    const victims = sessions.map((x, j) => ({ x, j })).filter(v => v.x.key !== key);
    const pool = victims.filter(v => isDone(v.x));
    const pick = (pool.length ? pool : victims).reduce((a, b) => (b.x.lastEventAt < a.x.lastEventAt ? b : a));
    sessions.splice(pick.j, 1);
  }
  return { sessions };
}
api.ledgerApply = ledgerApply;
/** The sessions of a ledger that have not ended, as the status answer and the recap's "still working" see them. */
api.liveSessions = ledger => sessionsOf(ledger).filter(s => s.endedAt === null);
api.aliveSubagents = s => Object.keys(isObj(s && s.subagents) ? s.subagents : {}).length;

// ── Task 3: stuckStep, the nudges ───────────────────────────────────────────

/** The thresholds of the four rules, in ms. `GIVE_UP_MS` is when the app stops waiting on a request, per platform (the Mac at 115 s, Windows and Linux at 110 s). */
const STUCK = { LOOP_CALLS: 8, LOOP_SAME: 4, WINDOW_MS: 10 * MIN, ERRORS: 3, WAIT_MS: 60000, SILENT_MS: 5 * MIN, SILENT_PRE_MS: 15 * MIN, KITTEN_MS: 10 * MIN, GIVE_UP_MS: { mac: 115000, windows: 110000, linux: 110000 } };
api.STUCK = STUCK;
/** The kinds in the order they are tried when two fire together; they are the kinds of dismissal too. */
const NUDGE_KINDS = ['stuck.loop', 'stuck.errors', 'stuck.waiting', 'stuck.silent'];
const ACTIVE_STATES = new Set(['thinking', 'working', 'searching']);
const WRITE_SET = new Set(api.WRITE_TOOLS);
const isCall = r => r.kind === 'tool' || r.kind === 'failure';

/** The same tool and key four times in the last eight calls, within ten minutes, with no successful edit or write after the first of them. */
function loopFires(s, now) {
  if (!ACTIVE_STATES.has(s.state) || now - s.lastEventAt > STUCK.WINDOW_MS) return false;
  const ring = ringOf(s), calls = ring.filter(isCall).slice(-STUCK.LOOP_CALLS);
  if (calls.length < STUCK.LOOP_SAME) return false;
  const newest = calls[calls.length - 1], inWindow = calls.filter(r => newest.at - r.at <= STUCK.WINDOW_MS);
  // The step is its tool and its command key (the whole input): a Grep with another pattern, a Read of another file or chunk is another step.
  const groups = new Map();
  for (const r of inWindow) if (r.tool) { const k = `${r.tool}\u0000${r.key}`; groups.set(k, [...(groups.get(k) || []), r]); }
  for (const members of groups.values()) {
    if (members.length < STUCK.LOOP_SAME) continue;
    const after = ring.slice(ring.indexOf(members[0]) + 1);
    if (!after.some(r => r.kind === 'tool' && r.ok && WRITE_SET.has(r.tool))) return true;
  }
  return false;
}
/** Three failures in a row, within ten minutes, with no success between. Claude Code only: the other agents send no failure event. */
function errorsFires(s, now) {
  if (s.agentId !== 'integration_claude' || !ACTIVE_STATES.has(s.state)) return false;
  const calls = ringOf(s).filter(isCall), last = calls.slice(-STUCK.ERRORS);
  return last.length === STUCK.ERRORS && last.every(r => r.kind === 'failure') && last[STUCK.ERRORS - 1].at - last[0].at <= STUCK.WINDOW_MS && now - last[STUCK.ERRORS - 1].at <= STUCK.WINDOW_MS;
}
const waitingDue = s => (s.state === 'approval' && s.pendingApprovalAt !== null ? s.pendingApprovalAt + STUCK.WAIT_MS : null);
/** When the quiet rule is due: 5 minutes after a finished step, a prompt or a subagent's stop, 15 after a step that began and never ended; never while a kitten is under 10 minutes old. */
function silentDue(s) {
  if (!ACTIVE_STATES.has(s.state)) return null;
  const gap = s.last === 'preTool' ? STUCK.SILENT_PRE_MS : ['tool', 'failure', 'prompt', 'subagentStop'].includes(s.last) ? STUCK.SILENT_MS : null;
  if (gap === null) return null;
  const kittens = Object.values(isObj(s.subagents) ? s.subagents : {});
  return Math.max(s.lastEventAt + gap, kittens.length ? Math.max(...kittens) + STUCK.KITTEN_MS : 0);
}

// While the card is on screen no waiting timer is asked for (nextAt leaves it out); the caller calls stuckStep again when the card hides.
/**
 * At most one nudge, and when the next one could fall due. `ctx` is `{ratelimit, away, cardShown, muted}` (all false or empty when absent): the cat already shows the rate limit, a nudge that falls
 * due while the user is away is dropped (the recap covers it), and the waiting nudge is for a request whose card is not on screen. Each session is nudged once (`nudgedAt`).
 * `muted` is the nudge kinds the user muted: they are skipped when the nudge is chosen (a muted loop must not hide a quiet session) and a muted waiting or quiet deadline is left out of `nextAt`.
 * Anything in it that is not one of the four kinds, or a `muted` that is not an array, is ignored.
 * Returns `{nudge: {kind, reasonId, key, agentId} | null, nextAt: ms | null}`; `nextAt` is the earliest future deadline of the waiting and quiet rules, for the one-shot timer.
 */
function stuckStep(ledger, now, ctx) {
  const c = isObj(ctx) ? ctx : {}, out = { nudge: null, nextAt: null };
  if (!isNum(now) || !isObj(ledger) || !Array.isArray(ledger.sessions) || c.ratelimit === true || c.away === true) return out;
  const off = k => Array.isArray(c.muted) && c.muted.includes(NUDGE_KINDS[k]);
  let best = null;
  for (const s of sessionsOf(ledger)) {
    if (s.endedAt !== null || s.nudgedAt !== null) continue;
    const wd = waitingDue(s), sd = silentDue(s);
    const fired = [!off(0) && loopFires(s, now) ? 0 : -1, !off(1) && errorsFires(s, now) ? 1 : -1, !off(2) && wd !== null && now >= wd && c.cardShown !== true ? 2 : -1, !off(3) && sd !== null && now >= sd ? 3 : -1].find(k => k >= 0);
    if (fired !== undefined && (best === null || fired < best.rank)) best = { rank: fired, s };
    for (const due of [c.cardShown === true || off(2) ? null : wd, off(3) ? null : sd]) if (due !== null && due > now && (out.nextAt === null || due < out.nextAt)) out.nextAt = due;
  }
  if (best) out.nudge = { kind: NUDGE_KINDS[best.rank], reasonId: NUDGE_KINDS[best.rank].slice(6), key: best.s.key, agentId: best.s.agentId };
  return out;
}
api.stuckStep = stuckStep;
api.NUDGE_KINDS = NUDGE_KINDS;
/** The ledger with that session marked as nudged: it gets no second nudge. */
api.markNudged = (ledger, key, now) => ({ sessions: sessionsOf(ledger).map(s => (s.key === key ? { ...copy(s), nudgedAt: now } : s)) });
/** The words of a nudge: a fixed template with the agent's name and a whole number of minutes. `ctx.platform` ('mac', 'windows' or 'linux'; else the Mac) sets when the app gave up on the request, and the waiting line switches to the terminal line once then. */
function nudgeText(nudge, ledger, now, ctx) {
  const s = sessionsOf(ledger).find(x => x.key === (nudge && nudge.key));
  const agent = agentName(nudge && nudge.agentId);
  switch (nudge && nudge.kind) {
    case 'stuck.loop': return `${agent} has run the same step ${STUCK.LOOP_SAME} times.`;
    case 'stuck.errors': return `${agent} hit ${STUCK.ERRORS} errors in a row.`;
    case 'stuck.waiting': {
      const plat = isObj(ctx) && hasOwnKey(STUCK.GIVE_UP_MS, ctx.platform) ? ctx.platform : 'mac';
      return s && s.pendingApprovalAt !== null && now - s.pendingApprovalAt >= STUCK.GIVE_UP_MS[plat] ? `${agent} is waiting for your OK in the terminal.` : `${agent} is still waiting for your OK.`;
    }
    case 'stuck.silent': return `${agent} has been quiet for ${s ? Math.floor((now - s.lastEventAt) / MIN) : 0} minutes.`;
    default: return '';
  }
}
api.nudgeText = nudgeText;

// ── Task 4: recapOf, statusOf and matchStatusQuestion ───────────────────────

const RECAP = { MIN_AWAY_MS: 2 * MIN, MAX_LINES: 3, MAX_FILES: 3, STATUS_FINISHED_MS: 10 * MIN };
api.RECAP = RECAP;
const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

/** How a session stands now: finished, waiting (for an OK), question, error, quiet (active, with nothing heard for 5 minutes) or working. */
function endOf(s, now) {
  if (s.state === 'approval' && s.pendingApprovalAt !== null) return 'waiting';
  if (s.state === 'question') return 'question';
  if (s.state === 'error') return 'error';
  if (s.state === 'finished') return 'finished';
  return ACTIVE_STATES.has(s.state) && now - s.lastEventAt >= STUCK.SILENT_MS ? 'quiet' : 'working';
}
/** What one agent did since `since` (ms; 0 for everything the ledger holds), over all its sessions: counts, up to three file names, and how it stands. */
function factsOf(sessions, since, now) {
  const entries = sessions.flatMap(s => ringOf(s).filter(r => r.at >= since));
  const files = [];
  for (const r of entries) if (r.kind === 'tool' && r.ok && WRITE_SET.has(r.tool) && r.file && !files.includes(r.file)) files.push(r.file);
  const rep = sessions.reduce((a, b) => (b.lastEventAt > a.lastEventAt ? b : a));
  const end = endOf(rep, now);
  return {
    agent: agentName(rep.agentId), agentId: rep.agentId, project: rep.project,
    steps: entries.filter(isCall).length, stepsAtLeast: sessions.some(s => ringOf(s).length >= RING_MAX && ringOf(s)[0].at >= since),
    files: files.slice(0, RECAP.MAX_FILES), more: Math.max(0, files.length - RECAP.MAX_FILES),
    errors: entries.filter(r => r.kind === 'failure').length, approvals: entries.filter(r => r.kind === 'approvalAsked').length,
    end, quietMinutes: end === 'quiet' ? Math.floor((now - rep.lastEventAt) / MIN) : 0, lastEventAt: rep.lastEventAt,
  };
}
const nameList = f => (f.more ? `${f.files.join(', ')} and ${f.more} more` : f.files.length > 1 ? `${f.files.slice(0, -1).join(', ')} and ${f.files[f.files.length - 1]}` : f.files[0] || '');
const TAIL = { finished: 'finished', waiting: 'is waiting for your OK', error: 'stopped on an error', question: 'is waiting for your answer', working: 'is still working' };
/** The rest of a line after the subject: what it ran, in brackets what went wrong or was asked, the files it edited, and how it stands. */
function lineBody(f, has) {
  const subject = f.project ? `${f.agent} in ${f.project}` : f.agent;
  const tail = f.end === 'quiet' ? `has been quiet for ${plural(f.quietMinutes, 'minute', 'minutes')}` : TAIL[f.end];
  if (f.steps === 0 && f.approvals === 0) return `${subject} ${tail}.`;
  const did = f.steps > 0 ? `${has}${f.stepsAtLeast ? `${RING_MAX} or more steps` : plural(f.steps, 'step', 'steps')}` : `asked for ${plural(f.approvals, 'approval', 'approvals')}`;
  const counts = [f.errors ? plural(f.errors, 'error', 'errors') : '', f.steps > 0 && f.approvals ? `${plural(f.approvals, 'approval', 'approvals')} asked` : ''].filter(Boolean);
  const edited = f.files.length ? `, edited ${nameList(f)}` : '';
  return `${subject} ${did}${counts.length ? ` (${counts.join(', ')})` : ''}${edited}${edited ? ',' : ''} and ${tail}.`;
}
/** Groups sessions by agent, the agent that spoke last first, and writes at most three lines, then "+N more". */
function linesOf(groups, prefix, has, now, since) {
  const facts = groups.map(g => factsOf(g, since, now)).sort((a, b) => b.lastEventAt - a.lastEventAt || (a.agentId < b.agentId ? -1 : 1));
  const lines = facts.slice(0, RECAP.MAX_LINES).map(f => prefix + lineBody(f, has));
  if (facts.length > RECAP.MAX_LINES) lines.push(`+${facts.length - RECAP.MAX_LINES} more`);
  return { lines, facts: facts.map(({ lastEventAt, ...rest }) => rest) };
}
const byAgent = sessions => { const m = new Map(); for (const s of sessions) m.set(s.agentId, [...(m.get(s.agentId) || []), s]); return [...m.values()]; };

/**
 * What happened while the user was away: `{lines, facts}`, or null when the away time was under two minutes or no agent did anything in it (a recap is never "nothing
 * happened"). `snapshot` is `{awaySince, now, sessions}`. It looks only at ring entries at or after `awaySince`.
 */
function recapOf(snapshot) {
  if (!isObj(snapshot) || !isNum(snapshot.awaySince) || !isNum(snapshot.now) || !Array.isArray(snapshot.sessions)) return null;
  const { awaySince, now } = snapshot;
  if (now - awaySince < RECAP.MIN_AWAY_MS) return null;
  const groups = byAgent(snapshot.sessions.filter(isObj)).map(g => g.filter(s => ringOf(s).some(r => r.at >= awaySince))).filter(g => g.length);
  if (!groups.length) return null;
  return linesOf(groups, 'While you were away, ', 'ran ', now, awaySince);
}
api.recapOf = recapOf;

/** The answer to "What's Claude doing?": the same templates over everything the ledger holds, for the live sessions (a finished one for 10 minutes), or for one agent. */
function statusOf(snapshot, agent) {
  const none = { lines: [isStr(agent) && agent ? `${agentName(agent)} is not running right now.` : 'No agent is running right now.'], facts: [] };
  if (!isObj(snapshot) || !isNum(snapshot.now) || !Array.isArray(snapshot.sessions)) return none;
  const live = snapshot.sessions.filter(isObj).filter(s => s.endedAt === null && (s.state !== 'finished' || snapshot.now - s.lastEventAt <= RECAP.STATUS_FINISHED_MS) && (!isStr(agent) || !agent || s.agentId === agent));
  if (!live.length) return none;
  return linesOf(byAgent(live), '', 'has run ', snapshot.now, 0);
}
api.statusOf = statusOf;

const STATUS_AGENTS = { claude: 'integration_claude', 'claude code': 'integration_claude', codex: 'agent_codex', gemini: 'agent_gemini', 'gemini cli': 'agent_gemini', antigravity: 'agent_antigravity', cursor: 'agent_cursor' };
const STATUS_ALL = new Set(['the agents', 'my agents', 'the agent', 'my agent', 'everyone', 'everybody']);
/**
 * Is this message the status question? It must be the whole message: a short text that, lower-cased and stripped of punctuation, is "what's claude doing", "what is codex
 * doing", "what are the agents doing" or "status" (with an optional agent name and an optional "right now"). Anything longer or different is a normal chat message.
 * Returns `{matched, agentId}`; `agentId` is null for "all of them".
 */
function matchStatusQuestion(text) {
  const no = { matched: false, agentId: null };
  if (!isStr(text) || text.length > 80) return no;
  const t = text.toLowerCase().replace(/[‘’ʼ']/g, '').replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim().replace(/ (right )?now$/, '');
  if (t === 'status' || t === 'agent status' || t === 'agents status') return { matched: true, agentId: null };
  let m = /^(?:whats|what is) (.+?) doing$/.exec(t) || /^what (?:are|is) (.+?) doing$/.exec(t);
  if (m) {
    if (hasOwnKey(STATUS_AGENTS, m[1])) return { matched: true, agentId: STATUS_AGENTS[m[1]] };
    if (STATUS_ALL.has(m[1])) return { matched: true, agentId: null };
    return no;
  }
  m = /^(.+) status$/.exec(t);
  if (m && hasOwnKey(STATUS_AGENTS, m[1])) return { matched: true, agentId: STATUS_AGENTS[m[1]] };
  return no;
}
api.matchStatusQuestion = matchStatusQuestion;

// ── Task 5: dismissal memory and the stored settings ────────────────────────

/** The five kinds a note can be, in their frozen order. Each is dismissed and muted on its own. */
const DISMISS_KINDS = ['recap', 'stuck.loop', 'stuck.errors', 'stuck.waiting', 'stuck.silent'];
const MUTE_AT = 2;
api.DISMISS_KINDS = DISMISS_KINDS;
api.MUTE_AT = MUTE_AT;
/** A stored count: a whole number from 1 to 2 stays, anything else (text, a fraction, a negative, null) is 0. */
const cleanCount = v => (Number.isInteger(v) && v > 0 ? Math.min(MUTE_AT, v) : 0);
/** The dismissals as they are kept: every kind once, in order, each a count from 0 to 2. Unknown kinds go. */
const cleanDismissals = raw => Object.fromEntries(DISMISS_KINDS.map(k => [k, cleanCount(isObj(raw) && hasOwnKey(raw, k) ? raw[k] : 0)]));
api.cleanDismissals = cleanDismissals;
/** One more dismissal of a kind (a click on Not now, OK or ×). A kind that is not one of the five changes nothing. Returns the new state. */
api.dismiss = (state, kind) => { const s = cleanDismissals(state); if (DISMISS_KINDS.includes(kind)) s[kind] = Math.min(MUTE_AT, s[kind] + 1); return s; };
/** A kind is muted once it has been dismissed twice. A muted kind never shows. The risk badge and the permission line are not a kind, so they are never muted. */
api.muted = (state, kind) => DISMISS_KINDS.includes(kind) && cleanDismissals(state)[kind] >= MUTE_AT;
/** Unmute in Settings: that kind goes back to 0. */
api.unmute = (state, kind) => { const s = cleanDismissals(state); if (DISMISS_KINDS.includes(kind)) s[kind] = 0; return s; };
/** A kind's switch turned off in Settings: that kind is muted at once, the same as two dismissals. A kind that is not one of the five changes nothing. */
api.mute = (state, kind) => { const s = cleanDismissals(state); if (DISMISS_KINDS.includes(kind)) s[kind] = MUTE_AT; return s; };

/**
 * The Sidekick settings as they are kept (UserDefaults `sidekick.on`, `sidekick.local`, `sidekick.dismissals` on the Mac; one `sidekick` object in settings.json on
 * Windows and Linux): `on` and `local` are booleans that are on unless they are `false`, `dismissals` is cleaned as above. Anything else is dropped. Cleaning twice is cleaning once.
 */
api.cleanSidekickSettings = raw => {
  const o = isObj(raw) ? raw : {};
  return { on: o.on !== false, local: o.local !== false, dismissals: cleanDismissals(o.dismissals) };
};

// ── Task 6: presenceStep and shouldShow ─────────────────────────────────────

const PRESENCE_ORDER = ['lock', 'sleep', 'display', 'idle'];
const PRESENCE_SIGNALS = { lock: ['lock', true], unlock: ['lock', false], sleep: ['sleep', true], wake: ['sleep', false], displayOff: ['display', true], displayOn: ['display', false] };
/** 300 s without input is away; a sample under 3 s is back. The samples in between change nothing. */
const IDLE = { AWAY_S: 300, BACK_S: 3 };
api.IDLE = IDLE;
api.presenceInit = () => ({ reasons: [], awaySince: null, wasAway: false });

/**
 * Whether the user is away, from the signals the OS gives. `state` is `{reasons, awaySince, wasAway}`: the reasons that hold now (lock, sleep, display, idle), when the
 * away began, and whether the user was away before this signal. `signal` is `{type}` with `type` one of lock, unlock, sleep, wake, displayOff, displayOn, or
 * `{type: 'idle', seconds}`. The user is away while any reason holds, and back when the last one lets go. Returns `{state, back}` where `back` is false or
 * `{back: true, awaySince, awayMs}`. It never throws; a signal it does not know changes nothing.
 */
function presenceStep(state, signal, now) {
  const reasons = new Set(isObj(state) && Array.isArray(state.reasons) ? state.reasons.filter(r => PRESENCE_ORDER.includes(r)) : []);
  let since = isObj(state) && isNum(state.awaySince) ? state.awaySince : null;
  const was = reasons.size > 0;
  const keep = () => ({ state: { reasons: PRESENCE_ORDER.filter(r => reasons.has(r)), awaySince: reasons.size ? since : null, wasAway: was }, back: false });
  if (!isNum(now) || !isObj(signal) || !isStr(signal.type)) return keep();
  let began = now;
  if (hasOwnKey(PRESENCE_SIGNALS, signal.type)) { const [r, on] = PRESENCE_SIGNALS[signal.type]; if (on) reasons.add(r); else reasons.delete(r); }
  else if (signal.type === 'idle' && isNum(signal.seconds)) {
    if (signal.seconds >= IDLE.AWAY_S) { reasons.add('idle'); began = now - signal.seconds * 1000; }
    else if (signal.seconds >= 0 && signal.seconds < IDLE.BACK_S) reasons.delete('idle');
  } else return keep();
  const is = reasons.size > 0;
  if (is) since = !was || since === null ? began : signal.type === 'idle' && reasons.has('idle') ? Math.min(since, began) : since;
  if (was && !is) return { state: { reasons: [], awaySince: null, wasAway: true }, back: { back: true, awaySince: since === null ? now : since, awayMs: now - (since === null ? now : since) } };
  return { state: { reasons: PRESENCE_ORDER.filter(r => reasons.has(r)), awaySince: is ? since : null, wasAway: was }, back: false };
}
api.presenceStep = presenceStep;

/** How long a refused note is kept, waiting for the gate to open: 30 s for a nudge, 2 minutes for a recap; and the gap after a note was shown. */
api.HOLD_MS = { nudge: 30000, recap: 2 * MIN };
api.NOTE_GAP_MS = 60000;

/**
 * Whether a note (a recap or a nudge) may show now. Returns `{show, reason, replace}`: `reason` is 'ok' or the first thing that says no, in this order: off (the switch),
 * kind (not one of the five), muted, away (a recap waits for the return, and so does a nudge), ratelimit (a stuck nudge while the agent is rate-limited), card (an approval or a question is in front; for the waiting nudge the rule is the
 * reverse: its own card must not be on screen), typing, busy (another note is visible, unless it is a nudge nobody has seen and this is the recap, which replaces it),
 * recent (a note showed in the last 60 s; the recap goes first), nudged (the session has had its nudge), recapGiven (this away period has had its recap).
 * The input is `{on, kind, dismissals, away, ratelimit, card, ownCard, inputFocused, visible: {kind, seen} | null, lastShownAt, now, nudged, recapGiven}`.
 */
api.shouldShow = input => {
  const i = isObj(input) ? input : {}, kind = i.kind, no = (reason) => ({ show: false, reason, replace: false });
  if (i.on === false) return no('off');
  if (!DISMISS_KINDS.includes(kind)) return no('kind');
  if (api.muted(i.dismissals, kind)) return no('muted');
  const recap = kind === 'recap';
  if (i.away === true) return no('away');
  if (!recap && i.ratelimit === true) return no('ratelimit');
  if (kind === 'stuck.waiting' ? i.ownCard === true : i.card === 'approval' || i.card === 'question') return no('card');
  if (i.inputFocused === true) return no('typing');
  let replace = false;
  if (isObj(i.visible)) { if (recap && isStr(i.visible.kind) && i.visible.kind !== 'recap' && i.visible.seen !== true) replace = true; else return no('busy'); }
  if (!recap && isNum(i.lastShownAt) && isNum(i.now) && i.now - i.lastShownAt < api.NOTE_GAP_MS) return no('recent');
  if (!recap && i.nudged === true) return no('nudged');
  if (recap && i.recapGiven === true) return no('recapGiven');
  return { show: true, reason: 'ok', replace };
};

// ── Task 7: acceptNicerLine, the sanity check of the local voice ────────────

/** A line break of any kind: CR, LF, and the Unicode line and paragraph separators. */
const LINE_BREAK = new RegExp('[\\r\\n' + String.fromCharCode(0x2028, 0x2029) + ']');

/**
 * Whether a sentence from a local model may replace the template. It must be one line of at most 200 characters, with no URL, no `/` or `\`, no backtick and no
 * markdown, use only numbers that are in the facts (their values, the digits in their names, the length of their lists, and 40 when the count is "40 or more"), and name an agent of the facts.
 * `facts` is the `facts` of a recap or a status (a list of facts, or one fact). The template is always right and always shown first; this only guards the swap.
 */
const acceptLine = (line, facts) => {
  if (!isStr(line)) return false;
  const t = line.trim(), list = Array.isArray(facts) ? facts.filter(isObj) : isObj(facts) ? [facts] : [];
  if (!t || Array.from(t).length > 200 || !list.length) return false;
  if (LINE_BREAK.test(t) || /:\/\/|\bwww\./i.test(t) || /[\/\\`]/.test(t) || /[*_#\[\]<>|~]/.test(t) || /^[-+]\s/.test(t)) return false;
  const allowed = new Set();
  const walk = v => {
    if (isNum(v)) allowed.add(String(Math.abs(Math.trunc(v))));
    else if (isStr(v)) (v.match(/\d+/g) || []).forEach(d => allowed.add(d.replace(/^0+(?=\d)/, '')));
    else if (Array.isArray(v)) { allowed.add(String(v.length)); v.forEach(walk); }
    else if (isObj(v)) Object.values(v).forEach(walk);
  };
  list.forEach(f => { walk(f); if (Array.isArray(f.files) && isNum(f.more)) allowed.add(String(f.files.length + f.more)); if (f.stepsAtLeast === true) allowed.add(String(RING_MAX)); });
  if ((t.match(/\d+/g) || []).some(d => !allowed.has(d.replace(/^0+(?=\d)/, '')))) return false;
  const lower = t.toLowerCase();
  return list.some(f => isStr(f.agent) && f.agent !== '' && lower.includes(f.agent.toLowerCase()));
};
/** A cyclic or very deep fact overflows the walk above: that is a refusal, never a throw. */
api.acceptNicerLine = (line, facts) => { try { return acceptLine(line, facts); } catch (e) { return false; } };

return api;
});
