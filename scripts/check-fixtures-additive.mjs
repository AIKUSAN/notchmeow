#!/usr/bin/env node
// Proves the cat, sidekick and link fixtures changed only by addition since a base ref (default HEAD).
//   node scripts/check-fixtures-additive.mjs [BASE_REF]
// A fixture file may be added, and a file may gain new keys or new cases. Every line the base version had must still be
// there, byte for byte and in the same order (a trailing comma may come or go, because a key appended last gains one).
// Apps read these files, so once they do, change them like this. Not part of the test runners, and not in CI: CI checks out one commit.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DIRS = ['tests/fixtures/cat', 'tests/fixtures/sidekick', 'tests/fixtures/link'];
// F1-0 merged the sidekick contract at this commit. A base that predates it has no sidekick fixtures, so that directory is skipped there.
const F1_0 = '8df679a';
// G2-0b merged the link contract's three connection rules at this commit, and in doing so reworded one frame case (the busy decline), so a base that predates it fails on that line and not on a
// real change. The link directory is skipped for such a base.
const G2_0B = 'd2b23670';
const noComma = line => line.replace(/,$/, '');

/** Whether the link fixtures are compared against a base: only when the base has G2-0b. `isAncestor(commit)` says whether `commit` is in the base's history. */
export function linkDirApplies(isAncestor) { return isAncestor(G2_0B); }

/** Compares one file's old and new text. `problems` is empty when the new text only adds to the old; `added` lists new top-level keys. */
export function checkAdditive(oldText, newText) {
  const problems = [];
  let now;
  try { now = JSON.parse(newText); } catch { return { problems: ['the new version is not valid JSON'], added: [] }; }
  const was = oldText.split('\n').map(noComma), next = newText.split('\n').map(noComma);
  let j = 0;
  for (const [i, line] of was.entries()) {
    while (j < next.length && next[j] !== line) j++;
    if (j === next.length) { problems.push(`old line ${i + 1} is gone or changed: ${line.trim().slice(0, 90)}`); break; }
    j++;
  }
  return { problems, added: Object.keys(now).filter(k => !(k in JSON.parse(oldText))) };
}

function main(ref = 'HEAD') {
  const git = (...args) => execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', maxBuffer: 1 << 26 });
  const predatesF1 = () => { try { git('merge-base', '--is-ancestor', ref, F1_0); return true; } catch { return false; } };
  let failed = false;
  const hasG2_0b = () => { try { git('merge-base', '--is-ancestor', G2_0B, ref); return true; } catch { return false; } };
  for (const dir of DIRS) {
    if (dir.endsWith('/link') && !linkDirApplies(hasG2_0b)) { console.log(`  - ${dir}/ at ${ref} predates G2-0b (${G2_0B}); skipped`); continue; }
    let names;
    try { names = git('ls-tree', '--name-only', ref, `${dir}/`).split('\n').filter(f => f.endsWith('.json')); } catch { console.error(`cannot read ${dir}/ at ${ref}`); process.exit(2); }
    if (!names.length) {
      if (predatesF1()) { console.log(`  - ${dir}/ is not in ${ref}, which predates F1-0 (${F1_0}); skipped`); continue; }
      console.error(`cannot read ${dir}/ at ${ref}`); process.exit(2);
    }
    let dirFailed = false;
    for (const file of names) {
      const name = path.basename(file), now = path.join(ROOT, file);
      if (!fs.existsSync(now)) { dirFailed = true; console.log(`  ✗ ${name} was removed`); continue; }
      const text = fs.readFileSync(now, 'utf8'), old = git('show', `${ref}:${file}`), { problems, added } = checkAdditive(old, text);
      if (problems.length) { dirFailed = true; console.log(`  ✗ ${name}`); problems.forEach(p => console.log(`      ${p}`)); }
      else console.log(`  ✓ ${name}: ${old.split('\n').length - 1} old lines unchanged${text === old ? '' : `, ${text.split('\n').length - old.split('\n').length} lines added${added.length ? ` (new keys: ${added.join(', ')})` : ''}`}`);
    }
    for (const f of fs.readdirSync(path.join(ROOT, dir)).filter(f => f.endsWith('.json') && !names.includes(`${dir}/${f}`))) console.log(`  + ${f} is new`);
    if (dirFailed) { failed = true; console.log(`✗ ${dir}: changed by more than addition since ${ref}`); }
    else console.log(`✓ ${dir}: changed only by addition since ${ref}`);
  }
  if (failed) { console.log(`Fixtures changed by more than addition since ${ref}.`); process.exit(1); }
  console.log(`✓ fixtures changed only by addition since ${ref}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(fs.realpathSync(process.argv[1])).href) main(process.argv[2]);
