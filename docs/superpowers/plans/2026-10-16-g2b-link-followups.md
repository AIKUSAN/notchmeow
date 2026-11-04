# G2b: Link follow-ups on Windows and Linux (and the Mac's twin): Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the two items G2-tauri parked, which the owner asked to have fixed before the public release (2026-10-16), and give the Mac the same guarantee where it has the same gap. (1) On Windows a declined, cancelled or failed incoming file is removed through the handle the sink holds, never by its path, so no other file of the same name can be removed. (2) When the mDNS daemon dies on its own, the machine list is emptied and the daemon is made again, with a bounded back-off, so the list and the advert recover without the user toggling Visible. The Mac's browser and listener get the same restart rule; the Mac's partial-file removal needs nothing (see "The Mac, checked").

**Architecture:** Two small pure rules, tested everywhere, and a thin platform part each. Files: `link/files.rs` keeps its Linux behaviour byte for byte; on Windows the file is created with `DELETE` access and without `FILE_SHARE_DELETE`, marked for deletion through the handle right after the mark of the web is written, and `finish` takes the mark off last (`arm` and `clear` are the pure sequence, `doom` is the one call to `SetFileInformationByHandle`). mDNS: `link/restart.rs` is the pure rule (a state machine fed with events and a millisecond clock: 1 s, 5 s, 30 s, then every minute, a minute of life starts it over, nothing when nothing is wanted); `link/mdns.rs` watches every daemon it makes on the daemon's monitor channel (a thread asleep in `recv()`), empties the list when it ends, and makes the daemon, the advert and the search again after the rule's wait (a `Condvar` wait that cancelling wakes: no polling). The Mac gets `LinkRestart.swift` (the same table, one `Task.sleep` for a whole wait) wired to `LinkListener`'s failure and `LinkBrowser`'s failure.

**Tech Stack:** Rust (the existing crate; the `windows` crate already in `Cargo.lock` gains one of its own features, `Win32_Storage_FileSystem`, which needs no download), Node 22 (`node --test`, the source pins), Swift 6 (the Mac's twin, one test program, one script).

**Spec:** `docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md` (G2, "Risks"), `docs/LINK-CONTRACT.md` (**unchanged**: both fixes are app-level resilience, no wire byte and no fixture changes) and the parked items in `.claude/archive/sdd/g2-tauri-link/progress.md` (Task 7: "Windows discard identity check"; Task 12: N1 and N4, "mdns daemon death"). The format is `docs/superpowers/plans/2026-10-16-g2-tauri-link.md`'s.

**Base:** a new branch `g2b/link-followups` in a git worktree, from `notchmeow/rebrand` at **`0466d5a2` or later** (G2-tauri is merged: `git merge-base --is-ancestor ca0a8807 HEAD`). The Setup block checks every find text of this plan against the tree.

## Global Constraints

Every task's requirements include this section.

- **No new crate, no new download (CLAUDE.md: "No third-party dependencies unless truly unavoidable").** `Cargo.toml` gains one line: the feature `Win32_Storage_FileSystem` on the `windows` crate that is already a direct dependency and already in `Cargo.lock` (0.61.3; the feature is `["Win32_Storage"]`, nothing else). `cargo tree --offline --locked` resolves it and `Cargo.lock` does not change (Task 1, Step 3 proves it). If either fails, **stop and tell the owner**: that would be a download.
- **Linux behaviour does not change.** `files.rs` keeps `O_EXCL`, `O_NOFOLLOW`, `0600` until complete, the device and inode check before a removal by path, and the clean-quit `remove_partials`. Every Windows change is behind `#[cfg(windows)]`; the code that is common (`arm`, `clear`) is only used on Windows and is tested on every platform.
- **The wire and the contract do not change.** No frame, no fixture, no `docs/LINK-CONTRACT.md` edit.
- **Nothing until Visible is on, and 0 % CPU hidden (CLAUDE.md).** The mDNS daemon, its watch thread and any restart wait exist only while an advert or a search is wanted; `release` cancels the wish and the wait; there is no interval, no polling loop and no thread sleep (`rust-wiring.test.mjs` pins it). The restart waits are one-shot: a `Condvar` wait on the Rust side, one `Task.sleep` on the Mac.
- **The restart table is the same on both apps:** waits of **1 s, 5 s, 30 s**, then **every 60 s** while the thing is wanted; a daemon, listener or browser that stayed up **60 s** starts the table over; no wait is shorter than 1 s. A pin in `rust-wiring.test.mjs` reads the Mac's numbers.
- **Mac at least what Windows/Linux gets (CLAUDE.md).** Task 4 gives the Mac the restart; the Mac's removal of a partial file already checks the file's identity (see "The Mac, checked").
- **A Windows-only change is never claimed as passed from this Mac.** Everything under `#[cfg(windows)]` is read here, compiled and run by CI (`windows-tests.yml`, `cargo test --workspace` on `windows-latest`) and by the owner's check (Task 6). Base `0466d5a2` is itself a fix for a Windows compile error, so this is a real risk, not a formality.
- **The Mac cannot be verified against a real failure** (a failed `NWListener` or `NWBrowser` cannot be forced from outside): the rule and the wiring are tested and pinned, the failure itself is not.
- Never push; commit once per task, only in the worktree; never launch, quit or replace the NotchMeow in `/Applications`; never start the Tauri app; never build or pull the Docker image.

## Review Focus

The input classes and failure modes the tasks' tests do not fully exercise, most likely first, each with the test that pins it.

1. **The mark of the web on a held file (Windows).** The `Zone.Identifier` stream is opened by path while the sink holds the main file without `FILE_SHARE_DELETE`. The stream open asks for write access only and shares delete, so it should pass; no Linux test can show it. Pinned by the Windows-only test `a_marked_file_carries_the_mark_of_the_web_when_finished_and_takes_it_along_when_discarded` (CI) and the owner's check 2. **If CI or the owner shows `Mark` failing, stop and report; do not loosen the sharing without the controller.**
2. **A file that cannot be kept fails closed.** `finish` keeps the file only if the mark for deletion comes off; if not it stays marked and closing the handle removes it. Pinned by `a_file_is_kept_only_if_the_mark_for_deletion_comes_off`.
3. **A daemon that dies over and over never becomes a fast loop.** The table is 1 s, 5 s, 30 s, 60 s, 60 s... for a daemon that dies young, and no wait is under 1 s. Pinned by `a_daemon_that_dies_at_once_again_and_again_never_gets_a_fast_loop`, `no_wait_is_shorter_than_a_second_or_longer_than_a_minute` and the Mac's twins.
4. **Nothing is made again when nothing is wanted** (Visible off, nobody on Devices or the shelf): `a_restart_wait_that_runs_out_with_nothing_wanted_makes_nothing`, `a_restart_wait_that_is_cancelled_ends_its_thread_at_once`, the wiring pins, and on the Mac the pins on `setWanted(false)`.
5. **Our own shutdowns are not deaths.** A daemon we replaced or released closes its channel too; `died` ignores it by the daemon's number. Pinned by `a_death_nobody_can_attribute_to_the_daemon_we_hold_is_ignored`, the wiring pin on the check, and the by-hand test `a_daemon_that_dies_is_made_again_and_stops_when_nothing_is_wanted`.
6. **The empty list is delivered outside the lock** (the service's callback may call back into `Mdns`): read by the reviewer; the wiring keeps the delivery after the `{ ... }` block that holds `shared.inner`.

## File Structure

| File | Change |
|---|---|
| `windows/src-tauri/src/link/files.rs` | Windows: held handle, `doom`, `arm`/`clear`; no removal by path on Windows; tests |
| `windows/src-tauri/Cargo.toml` | the feature `Win32_Storage_FileSystem` on `windows` |
| `windows/src-tauri/src/link/restart.rs` | **new**: the pure restart rule and its tests |
| `windows/src-tauri/src/link/mod.rs` | `pub mod restart;` |
| `windows/src-tauri/src/link/mdns.rs` | watch thread, wish (`search`), restart wait, `died`, `restart`, `start_search`; tests |
| `windows/scripts/link-tests/rust-wiring.test.mjs` | the pins (and the Mac's table) |
| `NotchBuddy/Sources/App/LinkRestart.swift` | **new**: `LinkRestarter`, `LinkRestartWait` |
| `NotchBuddy/Sources/App/LinkNetwork.swift`, `LinkService.swift` | `isRunning`, `onFailed`, the relaunches |
| `tests/LinkRestartTests.swift`, `scripts/test-link-restart.sh`, `scripts/test-link-wiring.sh`, `.github/workflows/build.yml` | **new** test program and script, the pins, the CI step |
| `windows/README.md`, `CLAUDE.md` | the two known limits become true, the restart is described |

## The Mac, checked

- **Partial files: fine.** `LinkFiles.swift` closes the descriptor, then removes the file only if `stat` still reports the device and inode the sink created (`removePartial`); a file that took the name is left alone. Only the microseconds between that `stat` and `unlink` remain (Linux has the same). The Windows hole was that nothing checked at all.
- **Browse and listen: the same gap.** `LinkBrowser` clears a failed `NWBrowser` and says nothing, and `LinkService` holds a dead wrapper that `startBrowser()` never replaces until Devices is closed and opened again; `LinkListener` drops a failed `NWListener` and the service retries only when Devices opens. Task 4 closes both with the rule of Task 2.

## Tasks and agents

CLAUDE.md: Haiku 5.5 first, Sonnet 5.5 only on a named trigger. The code is given in full in every task and its tests prove it. **Tasks 1 and 3 are `nm-implementer-deep` (Sonnet 5.5, high): trigger 1**, platform APIs and concurrency the task must get right (Windows file sharing and `SetFileInformationByHandle` that no container can compile; threads, a `Condvar` and lock order around a daemon). If a Haiku task's expected output differs and the cause is not obvious, or it fails twice, hand it to `nm-implementer-deep` (trigger 2) and say so in the ledger. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; the deep ones also `superpowers:systematic-debugging`; reviewers load `ponytail:ponytail-review`. Ponytail never cuts what this plan asks for, nor tests, security or privacy rules.

| # | Task | Agent, model, effort | Review |
|---|---|---|---|
| 0 | Worktree, find-text pre-flight and baseline | the session | none |
| 1 | Windows: the received file is held without `FILE_SHARE_DELETE` and deleted through its handle | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `nm-reviewer` |
| 2 | The pure restart rule (`restart.rs`) | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 3 | `mdns.rs`: watch the daemon, empty the list, make it again | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `nm-reviewer` |
| 4 | The Mac: the same rule for `LinkListener` and `LinkBrowser` | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 5 | Docs and the whole-tree checks | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| After 5 | The whole branch | `nm-reviewer-deep`, Sonnet 5.5, high (trigger 4) | none |
| 6 | **Checkpoint:** the owner's real-machine checks | the executing session and the owner | none |

## Execution

One worktree chat session runs the whole plan: branch `g2b/link-followups`, model **Sonnet 5.5 at high effort** (trigger 5, and trigger 1 for Tasks 1 and 3). Nothing is pushed. It touches `files.rs`, `mdns.rs`, `LinkService.swift` and `LinkNetwork.swift` and nothing the other open plans edit. The session never starts the Tauri app or the Mac app from `/Applications`.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model:

1. **Setup and stop.** The chip's prompt only sets up (it carries the owner's advance approval of the brief in step 3):

   > Run `git switch -c g2b/link-followups notchmeow/rebrand`, then the Setup block of `docs/superpowers/plans/2026-10-16-g2b-link-followups.md`: only its checks (the `merge-base --is-ancestor` line, the find-text pre-flight, the baseline). Read `CLAUDE.md`, `ARCHITECT.md`, `windows/README.md`, that plan, and `windows/src-tauri/src/link/files.rs` and `mdns.rs`. If a check fails, say so and stop. Reply "ready" and stop. Do not start Task 1. The owner approves in advance the controller brief the main session will send as your next message.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message.

**Controller brief** (what the main session sends once the model is set):

> Run `docs/superpowers/plans/2026-10-16-g2b-link-followups.md` with `superpowers:subagent-driven-development`, task by task, on branch `g2b/link-followups`. You are the controller: Sonnet 5.5 at high effort (CLAUDE.md triggers 1 and 5). Dispatch each task to the agent the plan's table names: `nm-implementer` (Haiku 5.5, high) for Task 4, `nm-implementer-light` for Tasks 2 and 5, `nm-implementer-deep` for Tasks 1 and 3 and for a task Haiku failed twice (then the trigger goes in the ledger); then `nm-reviewer` after every task, fixing what the review finds before the next one; and `nm-reviewer-deep` once over the whole branch at the end. Never Opus or Fable. Rules for you and for every subagent (put these in every brief):
>
> - **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder (under `.claude/worktrees/`), the second `g2b/link-followups`. If either is wrong, stop and report. Commit with `git commit -F -`, the message on stdin, ending with the `Co-Authored-By` line of the model that did the task. Once per task. **Never push.**
> - **Ledger.** Keep `.superpowers/sdd/2026-10-16-g2b-link-followups/progress.md`: the base commit (`git merge-base HEAD notchmeow/rebrand`), then one line per task with its agent, model, commit hash, test lines and review verdict, and any escalation with its trigger.
> - **Briefs are task-sized**: one task's text, the Global Constraints and these rules. Never the whole plan.
> - **Edits are exact.** An edit script's find text must occur exactly once in the file. **If it does not, stop and report**: never "fix" the find text or type a block from memory.
> - **Reviews** read `git diff "$(git merge-base HEAD notchmeow/rebrand)"...HEAD` (three dots), narrowed to the task's files.
> - **Every shell block passes `bash -n` before it is run.**
> - **Rust** only through `windows/scripts/cargo-linux.sh`, always with `--offline` and `--target-dir /repo/windows/target/g2b`. Never build or pull the Docker image: if `docker image inspect notchmeow-linux-dev` fails or the daemon is down, say so; the Rust steps are owed and the others go on. **No step downloads.** If cargo tries to (a "Downloading" line, a failure to resolve), stop and report: that is a decision for the owner.
> - **The apps.** Never launch, quit, replace or open the NotchMeow in `/Applications`, and never start the Tauri app. The Mac build in Task 5 is `xcodebuild` into a derived-data folder of your own.
> - **Servers and processes.** Stop a process only by the PID you saved.
> - **Stop and report on any refusal**, a denied command or a permission prompt: no workaround.
> - **Ping the main session** (`NotchMeow — fork research & cat design`, with `SendMessage`) at the end (Task 6) and whenever you stop (a refusal, a failed check, a find text that does not occur once, a Windows-only doubt, a question), so the main session can double-check before anything reaches the owner.
>
> Report: the commits; `cargo test --offline --workspace` and `cargo check --offline --all-targets` (counts and warnings); `npm run check:link`; `bash scripts/test-link-restart.sh`, `test-link-wiring.sh`, `test-link-network.sh`, `test-link-files.sh`, `test-link-service.sh`; the `xcodebuild` Debug result; the by-hand `--ignored` mDNS tests; and what is owed to CI and to the owner.

## Setup (the controller, once)

- [ ] **Step 1: Branch and base**

```bash
git status                                    # must be clean
git switch -c g2b/link-followups notchmeow/rebrand
git merge-base --is-ancestor ca0a8807 HEAD && echo "G2-tauri is merged (ca0a8807)"
git log --oneline -3
git rev-parse --show-toplevel; git branch --show-current
cp -cR "$MAIN_CHECKOUT/windows/node_modules" windows/node_modules      # MAIN_CHECKOUT: the main checkout that has node_modules
mkdir -p .claude/checkpoints/g2b .superpowers/sdd/2026-10-16-g2b-link-followups
(cd windows && node --version)                # 22.6 or newer
```

Expected: the `... is merged` line and a clean `git status --short`. The plan adds no npm package.

- [ ] **Step 2: Every find text of this plan, against the tree**

This reads the plan itself: the find text of every edit call in the scripts below, counted in the file that call names. All counts must be `1`.

```bash
python3 - <<'PY'
import pathlib, re
plan = pathlib.Path("docs/superpowers/plans/2026-10-16-g2b-link-followups.md").read_text(encoding="utf-8")
pat = re.compile(r"""edit\("([^"]+)", r'''(.*?)''', r'''""", re.S)
bad = 0; n = 0
for path, find in pat.findall(plan):
    n += 1
    c = pathlib.Path(path).read_text(encoding="utf-8").count(find)
    print(c, path.split("/")[-1], "|", find[:56].replace("\n", "\\n"))
    bad += c != 1
print(n, "find texts,", bad, "not exactly once")
raise SystemExit(1 if bad or n != 38 else 0)
PY
```

Expected: `38 find texts, 0 not exactly once`. Anything else: the tree moved; stop and report which line.

- [ ] **Step 3: Baseline, into the ledger**

```bash
CL=windows/scripts/cargo-linux.sh
TD="--target-dir /repo/windows/target/g2b"
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && echo "image ok" || echo "image missing or the daemon is down: the Rust steps are owed"
$CL test --offline $TD --workspace 2>&1 | grep -E "^test result"
(cd windows && npm run check:link 2>&1 | grep -E "^ℹ (tests|pass|fail)")
for s in test-link-restart test-link-wiring test-link-network test-link-service test-link-files test-link-session; do [ -f scripts/$s.sh ] && bash scripts/$s.sh 2>&1 | tail -1; done
```

Expected: `test result: ok.` with `0 failed` (write the passed and ignored counts into the ledger: Task 5 compares), `ℹ fail 0`, and `All tests passed.` for each script that exists (`test-link-restart.sh` does not exist yet).

---

## How to run this plan

**Blocks.** A code step is **Create `path`** (the file's exact content, in the fenced block under it, written with your file tool from the repository root), a `python` block whose `edit` helper replaces text that must occur exactly once in the file it names, or a plain command. Run each block from the repository root, as it is. Never type a block from memory and never "improve" one.

**The edit helper**, written once here; every edit script below begins with it, unchanged:

```python
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")
```

**Rust commands.** From the repository root, once per shell:

```bash
CL=windows/scripts/cargo-linux.sh
TD="--target-dir /repo/windows/target/g2b"
$CL test --offline $TD -p notchmeow link::restart      # a module: the first run compiles Tauri, minutes
$CL check --offline $TD -p notchmeow --all-targets
```

The container is Linux: the Linux Rust is compiled and tested; the Windows-only Rust is read, not compiled.

**Red first, and what stands in for it.** Each Rust file carries its own tests, so a task creates the file whole and runs it; the red evidence is the **"prove it bites"** step of each task: it changes one line, runs the tests, sees them fail, and puts the line back (never committed). The helper (written once, refuses a change whose find text does not occur exactly once, and always puts the file back):

```bash
mkdir -p .claude/checkpoints/g2b
cat > .claude/checkpoints/g2b/mut.py <<'EOF'
import sys, subprocess, pathlib, os
# usage: mut.py rust <file> <find> <replace> <cargo test filter>
#        mut.py node <file> <find> <replace> <test files...>      (run from windows/)
#        mut.py swift <file> <find> <replace> <script>
kind, path, old, new, rest = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:]
p = pathlib.Path(path); s = p.read_text(encoding="utf-8")
assert s.count(old) == 1, (path, old[:60], s.count(old))
try:
    p.write_text(s.replace(old, new), encoding="utf-8")
    if kind == "node":
        out = subprocess.run(["node", "--experimental-strip-types", "--test"] + rest, capture_output=True, text=True).stdout
        line = [l for l in out.splitlines() if l.startswith("# pass") or l.startswith("# fail")]
    elif kind == "swift":
        out = subprocess.run(["bash", rest[0]], capture_output=True, text=True)
        line = [l for l in (out.stdout + out.stderr).splitlines() if "✗" in l][:2] or ["(all pass)"]
    else:
        out = subprocess.run(["windows/scripts/cargo-linux.sh", "test", "--offline", "--target-dir", "/repo/windows/target/g2b", "-p", "notchmeow", rest[0]], capture_output=True, text=True)
        line = [l for l in (out.stdout + out.stderr).splitlines() if l.startswith("test result") and "passed" in l and not l.startswith("test result: ok. 0 passed")]
    print(os.path.basename(path), "|", new[:50].replace("\n", " "), "|", " ".join(line))
finally:
    p.write_text(s, encoding="utf-8")        # a fresh modification time, so that cargo notices
EOF
echo "helper written"
```

---

## Tasks

### Task 1: Windows: the received file is held without `FILE_SHARE_DELETE` and deleted through its handle

**Files:**
- Modify: `windows/src-tauri/Cargo.toml` (one feature), `windows/src-tauri/src/link/files.rs`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `pub(crate) enum Armed { Ready, Failed { err: SinkError, doomed: bool } }`, `pub(crate) fn arm(marked: bool, doom: impl FnMut(bool) -> bool) -> Armed`, `pub(crate) fn clear(doom: impl FnMut(bool) -> bool) -> Result<(), SinkError>`; Windows-only `fn doom(file: &File, on: bool) -> bool`. `Sink`'s public API is unchanged.

**How it works.** On Windows `create_exclusive` opens with `GENERIC_WRITE | DELETE` and share mode `READ | WRITE` (no `FILE_SHARE_DELETE`), so while the sink holds the file nobody can rename, replace or delete it: the path means this file. `open()` writes the mark of the web first (that stream is opened by path, which a file already waiting for deletion refuses), then `arm` marks the file for deletion through the handle. `finish()` flushes, then `clear` takes the mark off as the very last step. So a discard, a dropped sink, a failed `finish`, a crash and `kill -9` all end with Windows removing the file when the handle closes, and `remove_made` and `remove_partials` remove nothing by path on Windows. The only path removal left on Windows is in `open()` when Windows refuses the mark for deletion itself, for a file made a moment before.

- [ ] **Step 1: Apply the edits**

```python
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")

edit("windows/src-tauri/Cargo.toml", r'''  "Storage_Streams",
  "Win32_Foundation",
''', r'''  "Storage_Streams",
  # `SetFileInformationByHandle` (the received file is marked for deletion through its own handle, link/files.rs). A feature of the `windows` crate that is already in Cargo.lock: no new crate.
  "Win32_Storage_FileSystem",
  "Win32_Foundation",
''')

edit("windows/src-tauri/src/link/files.rs", r'''// (it is discarded and the transfer fails). Linux has no standard mark.
''', r'''// (it is discarded and the transfer fails). Linux has no standard mark.
//
// **A discard never goes by a path on Windows (G2b).** The file is created with DELETE access and without `FILE_SHARE_DELETE`, so while this sink holds it nobody else can rename it, replace it or
// delete it, and the name means this file. Once the mark of the web is written (that stream is opened by path, which a file that is already waiting for deletion refuses) the file is marked for
// deletion through the handle (`doom`, `SetFileInformationByHandle`); `finish` takes that mark off, as its last step, and a file whose mark cannot be taken off stays marked and goes when the
// handle closes (the download fails closed). So `discard`, a dropped sink, a failed `finish`, a crash and `kill -9` all end the same way: the last handle closes and Windows removes the file.
// The pure rules of that sequence (`arm`, `clear`) are tested on every platform; the two calls that touch Windows (`create_exclusive`'s access and sharing, `doom`) are Windows-only and are
// compiled and run by CI (windows-tests.yml) and by the owner's check. Linux keeps its device and inode check.
''')

edit("windows/src-tauri/src/link/files.rs", r'''pub const MARK_BY_HAND: bool = cfg!(windows);
''', r'''pub const MARK_BY_HAND: bool = cfg!(windows);

/// What `arm` found: the file is ready to be handed out, or the open must fail with `err`. `doomed` says whether the file is marked for deletion (closing the handle removes it) or whether
/// the caller must remove it by its path as a last resort.
#[cfg_attr(not(windows), allow(dead_code))]
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum Armed {
    Ready,
    Failed { err: SinkError, doomed: bool },
}

/// Windows, right after the file was created and the mark of the web written (`marked` is whether that worked): marks the file for deletion through `doom` (`doom(true)`), so that from now on a
/// partial file cannot outlive its handle. The mark is asked for even when the file could not be marked, so that such a file is removed by the handle too.
#[cfg_attr(not(windows), allow(dead_code))]
pub(crate) fn arm(marked: bool, mut doom: impl FnMut(bool) -> bool) -> Armed {
    let doomed = doom(true);
    if !marked {
        return Armed::Failed { err: SinkError::Mark, doomed };
    }
    if !doomed {
        return Armed::Failed { err: SinkError::Io, doomed: false };
    }
    Armed::Ready
}

/// Windows, the transfer is complete: takes the mark for deletion off. A file whose mark cannot be taken off is not kept: the caller closes the handle and Windows removes it.
#[cfg_attr(not(windows), allow(dead_code))]
pub(crate) fn clear(mut doom: impl FnMut(bool) -> bool) -> Result<(), SinkError> {
    if doom(false) {
        Ok(())
    } else {
        Err(SinkError::Io)
    }
}
''')

edit("windows/src-tauri/src/link/files.rs", r'''        let _ = std::fs::remove_file(p);
        false
''', r'''        // Windows: the sink's handle is marked for deletion and nobody else may delete the file, so the file goes when the process ends and closes it; a removal by path would be refused anyway.
        #[cfg(not(windows))]
        let _ = std::fs::remove_file(p);
        false
''')

edit("windows/src-tauri/src/link/files.rs", r'''                    self.file = Some(file);
                    self.path = Some(target.clone());
                    partials().push(target.clone());
                    // A file that cannot be marked is not handed out; it goes, partial or not.
                    if self.mark && !mark_as_downloaded(&target) {
                        self.discard();
                        return Err(SinkError::Mark);
                    }
                    return Ok(target);
''', r'''                    self.path = Some(target.clone());
                    partials().push(target.clone());
                    #[cfg(windows)]
                    {
                        // The mark of the web first (its stream is opened by path), then the mark for deletion through the handle. A file that cannot be marked is not handed out; it goes, partial or not.
                        let marked = !self.mark || mark_as_downloaded(&target);
                        if let Armed::Failed { err, doomed } = arm(marked, |on| doom(&file, on)) {
                            drop(file);
                            unlist(&target);
                            self.path = None;
                            if !doomed {
                                // Windows refused the mark for deletion: the one removal by path that is left, for a file that was made a moment ago.
                                let _ = std::fs::remove_file(&target);
                            }
                            return Err(err);
                        }
                    }
                    self.file = Some(file);
                    #[cfg(not(windows))]
                    {
                        // A file that cannot be marked is not handed out; it goes, partial or not.
                        if self.mark && !mark_as_downloaded(&target) {
                            self.discard();
                            return Err(SinkError::Mark);
                        }
                    }
                    return Ok(target);
''')

edit("windows/src-tauri/src/link/files.rs", r'''        let done = (|| {
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                file.set_permissions(std::fs::Permissions::from_mode(0o644))?; // on the open descriptor: the very file being closed becomes ordinary
            }
            file.sync_all()
        })();
''', r'''        let done = (|| -> std::io::Result<()> {
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                file.set_permissions(std::fs::Permissions::from_mode(0o644))?; // on the open descriptor: the very file being closed becomes ordinary
            }
            file.sync_all()?;
            #[cfg(windows)]
            {
                // Kept only if the mark for deletion comes off; if not it stays marked and closing the handle removes it.
                clear(|on| doom(&file, on)).map_err(|_| std::io::Error::other("the file could not be kept"))?;
            }
            Ok(())
        })();
''')

edit("windows/src-tauri/src/link/files.rs", r'''        let _ = std::fs::remove_file(path);
    }
}

/// A sink released before `finish`''', r'''        #[cfg(unix)]
        let _ = std::fs::remove_file(path);
        // Windows: nothing is removed by `path`. The held handle is marked for deletion, so closing it (which the caller has just done, or does now) removes the file; a path could by now be another file's.
        #[cfg(windows)]
        let _ = path;
    }
}

/// A sink released before `finish`''')

edit("windows/src-tauri/src/link/files.rs", r'''fn create_exclusive(path: &Path) -> std::io::Result<File> {
    let mut o = OpenOptions::new();
    o.write(true).create_new(true);
''', r'''fn create_exclusive(path: &Path) -> std::io::Result<File> {
    let mut o = OpenOptions::new();
    o.write(true).create_new(true);
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt;
        // GENERIC_WRITE | DELETE, shared for reading and writing only: no FILE_SHARE_DELETE, so no other program can rename, replace or delete the file while it is held (see the header).
        o.access_mode(0x4000_0000 | 0x0001_0000).share_mode(0x1 | 0x2);
    }
''')

edit("windows/src-tauri/src/link/files.rs", r'''#[cfg(windows)]
fn stream_path(file: &Path) -> PathBuf {''', r'''/// Windows: marks the open file for deletion when its last handle closes (`on`), or takes the mark off again. Done through the handle the sink holds, never through a path. False when Windows refused.
#[cfg(windows)]
fn doom(file: &File, on: bool) -> bool {
    use std::os::windows::io::AsRawHandle;
    use windows::Win32::Foundation::HANDLE;
    use windows::Win32::Storage::FileSystem::{FileDispositionInfo, SetFileInformationByHandle, FILE_DISPOSITION_INFO};
    let info = FILE_DISPOSITION_INFO { DeleteFile: on };
    // SAFETY: the handle stays open while `file` is borrowed, and `info` is a live FILE_DISPOSITION_INFO of exactly the size passed.
    unsafe { SetFileInformationByHandle(HANDLE(file.as_raw_handle()), FileDispositionInfo, std::ptr::from_ref(&info).cast(), std::mem::size_of::<FILE_DISPOSITION_INFO>() as u32).is_ok() }
}

#[cfg(windows)]
fn stream_path(file: &Path) -> PathBuf {''')

edit("windows/src-tauri/src/link/files.rs", r'''        // A deleted file that is still open cannot be read (on Windows `exists` can still be true), so `read` is the check.
        assert!(std::fs::read(&partial_path).is_err(), "the partial file is gone");
''', r'''        // A deleted file that is still open cannot be read, so `read` is the check. On Windows nothing is removed by path (the sink's handle is marked for deletion): the file goes when the sink does.
        #[cfg(not(windows))]
        assert!(std::fs::read(&partial_path).is_err(), "the partial file is gone");
''')

edit("windows/src-tauri/src/link/files.rs", r'''    #[test]
    fn a_relative_folder_is_not_a_place_to_receive_into() {''', r'''    #[test]
    fn a_file_is_marked_for_deletion_after_its_mark_of_the_web_and_every_failure_ends_in_a_deletion() {
        let calls = std::cell::RefCell::new(Vec::new());
        assert_eq!(
            arm(true, |on| {
                calls.borrow_mut().push(on);
                true
            }),
            Armed::Ready
        );
        assert_eq!(*calls.borrow(), [true], "marked for deletion once");
        assert_eq!(arm(false, |_| true), Armed::Failed { err: SinkError::Mark, doomed: true }, "no mark of the web: not handed out, and it goes with its handle");
        assert_eq!(arm(true, |_| false), Armed::Failed { err: SinkError::Io, doomed: false }, "Windows refused the mark: the caller removes the new file");
        assert_eq!(arm(false, |_| false), Armed::Failed { err: SinkError::Mark, doomed: false });
    }

    #[test]
    fn a_file_is_kept_only_if_the_mark_for_deletion_comes_off() {
        assert_eq!(
            clear(|on| {
                assert!(!on, "clearing asks for no deletion");
                true
            }),
            Ok(())
        );
        assert_eq!(clear(|_| false), Err(SinkError::Io), "it stays marked, so closing the handle removes it: the download fails closed");
    }

    // The next three run on Windows only (CI and the owner): they need the real handle.
    #[cfg(windows)]
    #[test]
    fn a_file_in_progress_cannot_be_deleted_renamed_or_replaced_by_anybody_else() {
        let dir = temp("held");
        let mut s = Sink::new(dir.clone(), "a.bin", false);
        let path = s.open().unwrap();
        s.write(&[1, 2, 3]).unwrap();
        assert!(std::fs::remove_file(&path).is_err(), "no delete by path while the sink holds it");
        assert!(std::fs::rename(&path, dir.join("moved.bin")).is_err(), "no rename");
        s.discard();
        assert!(names(&dir).is_empty(), "and the discard removed it through the handle");
    }

    #[cfg(windows)]
    #[test]
    fn a_marked_file_carries_the_mark_of_the_web_when_finished_and_takes_it_along_when_discarded() {
        let dir = temp("zone");
        let mut s = Sink::new(dir.clone(), "a.txt", true);
        let path = s.open().unwrap();
        s.write(b"hi").unwrap();
        let done = s.finish().unwrap();
        assert_eq!(std::fs::read(&done).unwrap(), b"hi");
        assert!(std::fs::read_to_string(stream_path(&path)).unwrap().contains("ZoneId=3"), "the mark of the web");
        drop(s);
        assert!(done.exists(), "a finished download stays");
        let mut d = Sink::new(dir.clone(), "b.txt", true);
        d.open().unwrap();
        d.write(b"x").unwrap();
        d.discard();
        assert_eq!(names(&dir), vec!["a.txt"], "the discarded one is gone, stream and all");
    }

    #[cfg(windows)]
    #[test]
    fn another_file_that_takes_the_name_after_a_completed_download_is_never_touched_by_a_later_discard() {
        let dir = temp("later");
        let mut s = Sink::new(dir.clone(), "a.bin", false);
        let path = s.open().unwrap();
        s.finish().unwrap();
        std::fs::remove_file(&path).unwrap();
        std::fs::write(&path, "somebody else's").unwrap();
        s.discard();
        drop(s);
        assert_eq!(std::fs::read(&path).unwrap(), b"somebody else's");
    }

    #[test]
    fn a_relative_folder_is_not_a_place_to_receive_into() {''')

```

- [ ] **Step 2: The tests, on Linux**

Run: `$CL test --offline $TD -p notchmeow link::files` and `$CL check --offline $TD -p notchmeow --all-targets`
Expected: `test result: ok. 16 passed` (two new: `a_file_is_marked_for_deletion_after_its_mark_of_the_web_and_every_failure_ends_in_a_deletion`, `a_file_is_kept_only_if_the_mark_for_deletion_comes_off`) and a `check` with no warning (the `cfg_attr(not(windows), allow(dead_code))` on `Armed`, `arm` and `clear` is what keeps Linux quiet).

- [ ] **Step 3: No new crate**

```bash
$CL tree --offline --locked $TD --target x86_64-pc-windows-msvc -p notchmeow -e features -i windows@0.61.3 | grep -c 'feature "Win32_Storage_FileSystem"'
git diff --stat -- windows/Cargo.lock
```

Expected: a count of `2` or more, and no `Cargo.lock` line. **If `cargo tree` fails, or `Cargo.lock` changed, stop: tell the owner (a download would be needed).**

- [ ] **Step 4: Prove it bites**

```bash
python3 .claude/checkpoints/g2b/mut.py rust windows/src-tauri/src/link/files.rs 'let doomed = doom(true);' 'let doomed = false;' link::files
python3 .claude/checkpoints/g2b/mut.py rust windows/src-tauri/src/link/files.rs '    if doom(false) {' '    if true {' link::files
```

Expected: each prints `test result: FAILED. 15 passed; 1 failed`.

- [ ] **Step 5: Read the Windows-only code, then list what CI must compile and run**

Nothing here compiles on Linux. The implementer reads each of these against the `windows` 0.61.3 source in the registry (`SetFileInformationByHandle(hfile: HANDLE, FILE_INFO_BY_HANDLE_CLASS, *const c_void, u32) -> Result<()>`, `FILE_DISPOSITION_INFO { DeleteFile: bool }`, `HANDLE(pub *mut c_void)`): `doom`; the Windows branch of `create_exclusive`; the `#[cfg(windows)]` block in `open()`; the Windows block in `finish()`; the Windows-only tests (`a_file_in_progress_cannot_be_deleted_renamed_or_replaced_by_anybody_else`, `a_marked_file_carries_the_mark_of_the_web_when_finished_and_takes_it_along_when_discarded`, `another_file_that_takes_the_name_after_a_completed_download_is_never_touched_by_a_later_discard`). Write in the ledger: **owed to CI (`windows-tests.yml`) and to Task 6**, with the one doubt that matters (Review Focus 1).

- [ ] **Step 6: Commit**

```bash
git add windows/src-tauri/Cargo.toml windows/src-tauri/src/link/files.rs
git commit -F - <<'MSG'
fix(link): a Windows download is held without FILE_SHARE_DELETE and deleted through its handle (G2b)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

(The `Co-Authored-By` line is the model that did the task: Sonnet 5.5 for this one.)

---

### Task 2: The pure restart rule

**Files:**
- Create: `windows/src-tauri/src/link/restart.rs`
- Modify: `windows/src-tauri/src/link/mod.rs`

**Interfaces:**
- Consumes: nothing.
- Produces: `pub const DELAYS_MS: [u64; 3]`, `STEADY_MS`, `STABLE_MS`; `pub struct Restarter` with `new()`, `set_wanted(&mut self, bool)`, `started(&mut self, now_ms: u64)`, `died(&mut self, now_ms: u64) -> Option<u64>`, `failed_restart(&mut self) -> Option<u64>`. Task 3 uses all of them; Task 4 ports them to Swift.

- [ ] **Step 1: Create the rule and its tests, and register the module**

**Create `windows/src-tauri/src/link/restart.rs`:**

```rust
// When the machine-list daemon dies, when it comes back (sub-project G2b). `mdns-sd` runs its daemon on a thread of its own; if that thread ends (a socket error, a network that went away for
// good) the daemon is gone for good too, and the machine list would stay stale and this machine unannounced until the user toggled Visible. `mdns.rs` notices the end and asks this rule how long
// to wait before it makes the daemon again. The rule is pure: it is fed with what happened and a clock (milliseconds, any origin) and answers with a wait, or with nothing.
//
// The wait grows (1 s, 5 s, 30 s, then every minute for as long as the daemon is wanted), so that a machine whose network is down is tried a few times quickly and then costs one attempt a
// minute, and a daemon that dies at once, over and over, never gets a fast retry loop. A daemon that stayed up for a minute counts as healthy: its next death starts the table again. Nothing is
// ever asked for while the daemon is not wanted (Visible off and nobody looking at Devices or the shelf: `mdns.rs` says so with `set_wanted(false)`).
//
// The Mac twin is `LinkRestart.swift` (the same table; `scripts/link-tests/rust-wiring.test.mjs` reads its numbers).

/// The first three waits.
pub const DELAYS_MS: [u64; 3] = [1_000, 5_000, 30_000];
/// Every wait after those.
pub const STEADY_MS: u64 = 60_000;
/// A daemon that ran this long before it died starts the table again.
pub const STABLE_MS: u64 = 60_000;

#[derive(Debug, Default, Clone)]
pub struct Restarter {
    wanted: bool,
    failures: usize,
    up_since: Option<u64>,
}

impl Restarter {
    pub fn new() -> Restarter {
        Restarter::default()
    }

    /// Whether anything needs the daemon (an advert, a search). Turning it off forgets the table and the daemon's age.
    pub fn set_wanted(&mut self, wanted: bool) {
        self.wanted = wanted;
        if !wanted {
            self.failures = 0;
            self.up_since = None;
        }
    }

    /// A daemon is up (the first one or a restart).
    pub fn started(&mut self, now_ms: u64) {
        self.up_since = Some(now_ms);
    }

    /// The daemon died. The wait before making another, in milliseconds, or None when nothing needs one.
    pub fn died(&mut self, now_ms: u64) -> Option<u64> {
        if let Some(since) = self.up_since.take() {
            if now_ms.saturating_sub(since) >= STABLE_MS {
                self.failures = 0;
            }
        }
        self.next()
    }

    /// A restart could not make a daemon at all: the next wait.
    pub fn failed_restart(&mut self) -> Option<u64> {
        self.up_since = None;
        self.next()
    }

    fn next(&mut self) -> Option<u64> {
        if !self.wanted {
            return None;
        }
        let wait = DELAYS_MS.get(self.failures).copied().unwrap_or(STEADY_MS);
        self.failures = self.failures.saturating_add(1);
        Some(wait)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wanted() -> Restarter {
        let mut r = Restarter::new();
        r.set_wanted(true);
        r
    }

    #[test]
    fn nothing_is_scheduled_for_a_daemon_nobody_wants() {
        let mut r = Restarter::new();
        assert_eq!(r.died(0), None, "never wanted");
        assert_eq!(r.failed_restart(), None);
        let mut r = wanted();
        r.set_wanted(false);
        assert_eq!(r.died(10), None, "no longer wanted");
        assert_eq!(r.failed_restart(), None);
    }

    #[test]
    fn the_waits_are_one_second_five_thirty_and_then_every_minute() {
        let mut r = wanted();
        r.started(0);
        assert_eq!(r.died(100), Some(1_000));
        let rest: Vec<u64> = (0..6).map(|_| r.failed_restart().unwrap()).collect();
        assert_eq!(rest, [5_000, 30_000, 60_000, 60_000, 60_000, 60_000]);
    }

    #[test]
    fn a_daemon_that_dies_at_once_again_and_again_never_gets_a_fast_loop() {
        let mut r = wanted();
        let mut t = 0;
        let mut waits = Vec::new();
        for _ in 0..6 {
            r.started(t);
            let w = r.died(t + 10).unwrap();
            waits.push(w);
            t += 10 + w;
        }
        assert_eq!(waits, [1_000, 5_000, 30_000, 60_000, 60_000, 60_000]);
    }

    #[test]
    fn a_daemon_that_stayed_up_a_minute_starts_the_table_again() {
        let mut r = wanted();
        r.started(0);
        assert_eq!(r.died(10), Some(1_000));
        assert_eq!(r.failed_restart(), Some(5_000));
        r.started(200_000);
        assert_eq!(r.died(259_999), Some(30_000), "59.999 s is not a minute");
        r.started(300_000);
        assert_eq!(r.died(360_000), Some(1_000), "a minute is");
        r.started(400_000);
        assert_eq!(r.died(1_400_000), Some(1_000), "and so is a long life");
    }

    #[test]
    fn turning_the_wish_off_forgets_the_table() {
        let mut r = wanted();
        r.started(0);
        r.died(10);
        r.failed_restart();
        r.set_wanted(false);
        r.set_wanted(true);
        assert_eq!(r.died(20), Some(1_000));
    }

    #[test]
    fn no_wait_is_shorter_than_a_second_or_longer_than_a_minute() {
        let mut r = wanted();
        for _ in 0..200 {
            let w = r.failed_restart().unwrap();
            assert!((1_000..=60_000).contains(&w), "{w}");
        }
    }
}
```

```python
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")

edit("windows/src-tauri/src/link/mod.rs", r'''pub mod mdns;
''', r'''pub mod mdns;
pub mod restart;
''')

```

- [ ] **Step 2: Run**

Run: `$CL test --offline $TD -p notchmeow link::restart`
Expected: `test result: ok. 6 passed`.

- [ ] **Step 3: Prove it bites**

```bash
python3 .claude/checkpoints/g2b/mut.py rust windows/src-tauri/src/link/restart.rs '[u64; 3] = [1_000, 5_000, 30_000]' '[u64; 3] = [1_000, 5_000, 31_000]' link::restart
python3 .claude/checkpoints/g2b/mut.py rust windows/src-tauri/src/link/restart.rs 'now_ms.saturating_sub(since) >= STABLE_MS' 'now_ms.saturating_sub(since) > STABLE_MS' link::restart
```

Expected: `FAILED. 3 passed; 3 failed` and `FAILED. 5 passed; 1 failed`.

- [ ] **Step 4: Commit**

```bash
git add windows/src-tauri/src/link/restart.rs windows/src-tauri/src/link/mod.rs
git commit -F - <<'MSG'
feat(link): the pure restart rule for a dead mDNS daemon (G2b)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

---

### Task 3: `mdns.rs`: watch the daemon, empty the list, make it again

**Files:**
- Modify: `windows/src-tauri/src/link/mdns.rs`, `windows/scripts/link-tests/rust-wiring.test.mjs`

**Interfaces:**
- Consumes: `restart::Restarter` (Task 2), `mdns_sd` 0.11.5's `ServiceDaemon::monitor() -> Result<Receiver<DaemonEvent>>` (the channel closes when the daemon's thread ends; read in the registry source, nothing assumed).
- Produces: the `Discovery` trait and `Mdns`'s public API are unchanged, so `service.rs` needs no edit. Inside: `Shared { inner, wake, born }`, `Inner.search` (the wish: own id and callback), `Inner.epoch`, `Inner.restarter`, `Inner.wait`; `Mdns::{daemon, run, release, start_search, died, arm, restart}`.

**How it works.** `daemon()` gives every daemon it makes a number (`epoch`) and a watch thread asleep on `monitor()`; the thread ends when the channel closes and calls `died(epoch)`. A search thread whose channel ends by itself calls `died` too. `died` ignores a number that is not the current daemon's (ours, replaced or released) and a death already seen; otherwise it drops the handle, asks the rule for a wait (only if an advert or a search is wanted), arms it, and, outside the lock, hands the callback an **empty list** (the machines are no longer known to be there) and closes the dead search. `arm` starts a thread asleep on a `Condvar` for at most the wait; cancelling (`release`, a new daemon, a new arm) bumps the number and wakes it, and it ends. On expiry `restart` makes the daemon (which registers the advert again) and starts the search again from `Inner.search`; if that fails the rule gives the next wait. `release` (nothing announced, nothing searched) shuts the daemon, takes the wish away and cancels the wait.

- [ ] **Step 1: Apply the edits**

```python
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")

edit("windows/src-tauri/src/link/mdns.rs", r'''// `scripts/link-tests/wiring.test.mjs` pins that `ServiceDaemon::new` is called only here, in `daemon()`.
''', r'''// `scripts/link-tests/wiring.test.mjs` pins that `ServiceDaemon::new` is called only here, in `daemon()`.
//
// **A daemon that dies is made again (G2b).** `mdns-sd` runs the daemon on its own thread; if that thread ends, the machine list would go stale and this machine would stop being announced. Every
// daemon made here has a watch thread asleep in `recv()` on the daemon's monitor channel, which closes when the daemon's thread ends (a search's own channel closing says the same). The watch
// asks `restart.rs` for a wait (1 s, 5 s, 30 s, then every minute), empties the list on screen, and a one-shot wait (a `Condvar`, no polling) makes the daemon, announces again what was announced
// and searches again with what `browse` was given. Nothing is done when nothing is announced or searched: `release` cancels the wait and the wish.
''')

edit("windows/src-tauri/src/link/mdns.rs", r'''use std::sync::{Arc, Mutex, MutexGuard};
use std::thread::ThreadId;
''', r'''use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread::ThreadId;
use std::time::{Duration, Instant};
''')

edit("windows/src-tauri/src/link/mdns.rs", r'''use super::frames::{parse_txt, Advert, OwnId, Txt};
''', r'''use super::frames::{parse_txt, Advert, OwnId, Txt};
use super::restart::Restarter;
''')

edit("windows/src-tauri/src/link/mdns.rs", r'''#[derive(Default)]
struct Inner {
    daemon: Option<ServiceDaemon>,
    /// What this machine announces, while it does: the full name (to unregister) and the record (to announce it again on a fresh daemon).
    advertised: Option<(String, ServiceInfo)>,
    /// While a search runs: the gate its waiting thread hands results through.
    browsing: Option<Arc<Gate>>,
}

#[derive(Default)]
pub struct Mdns {
    inner: Arc<Mutex<Inner>>,
}
''', r'''#[derive(Default)]
struct Inner {
    daemon: Option<ServiceDaemon>,
    /// What this machine announces, while it does: the full name (to unregister) and the record (to announce it again on a fresh daemon).
    advertised: Option<(String, ServiceInfo)>,
    /// While a search runs: the gate its waiting thread hands results through.
    browsing: Option<Arc<Gate>>,
    /// What `browse` was given while a search is wanted: this machine's id and the callback, so that a daemon made again can search again. `stop_browsing` takes it away.
    search: Option<(String, OnResults)>,
    /// The number of the daemon in `daemon`. A death reported by an older daemon (one we replaced or shut down) is not a death.
    epoch: u64,
    /// The rule that decides how long to wait before a daemon is made again.
    restarter: Restarter,
    /// The number of the restart wait that is allowed to run; a wait that finds another number was cancelled.
    wait: u64,
}

/// The state, the signal that wakes a restart wait early (to cancel it) and the clock the restart rule is fed with.
struct Shared {
    inner: Mutex<Inner>,
    wake: Condvar,
    born: Instant,
}

impl Shared {
    fn now_ms(&self) -> u64 {
        self.born.elapsed().as_millis() as u64
    }
}

pub struct Mdns {
    shared: Arc<Shared>,
}

impl Default for Mdns {
    fn default() -> Mdns {
        Mdns { shared: Arc::new(Shared { inner: Mutex::new(Inner::default()), wake: Condvar::new(), born: Instant::now() }) }
    }
}
''')

edit("windows/src-tauri/src/link/mdns.rs", r'''impl Mdns {
    pub fn new() -> Mdns {
        Mdns::default()
    }

    /// The daemon, made on first use. IPv6 is switched off: the advert and the listener are IPv4, and a daemon that cannot be switched is not used. `fresh` drops the daemon there is (one that
    /// died on its own) and makes another, which announces again what this machine announced.
    fn daemon(inner: &mut Inner, fresh: bool) -> Option<ServiceDaemon> {
        if fresh {
            if let Some(old) = inner.daemon.take() {
                let _ = old.shutdown();
            }
        }
        if let Some(d) = &inner.daemon {
            return Some(d.clone());
        }
        let d = ServiceDaemon::new().ok()?;
        let d = ipv4_only(d.clone(), d.disable_interface(IfKind::IPv6).is_ok(), |d| {
            let _ = d.shutdown();
        })?;
        if let Some((_, info)) = &inner.advertised {
            let _ = d.register(info.clone());
        }
        inner.daemon = Some(d.clone());
        Some(d)
    }

    /// Runs `op` on the daemon. If it fails (a daemon that died on its own), the daemon is dropped and `op` is tried once more on a fresh one; `None` when that fails too.
    fn run<T>(inner: &mut Inner, op: impl Fn(&ServiceDaemon) -> mdns_sd::Result<T>) -> Option<T> {
        let d = Mdns::daemon(inner, false)?;
        if let Ok(v) = op(&d) {
            return Some(v);
        }
        op(&Mdns::daemon(inner, true)?).ok()
    }

    /// The daemon is shut down when nothing is announced and nobody is searching.
    fn release(inner: &mut Inner) {
        if inner.advertised.is_none() && inner.browsing.is_none() {
            if let Some(d) = inner.daemon.take() {
                let _ = d.shutdown();
            }
        }
    }
}

impl Discovery for Mdns {
    fn advertise(&self, id: &str, name: &str, port: u16) -> Result<(), String> {
        let info = service(id, name, port, "")?.enable_addr_auto();
        let full = info.get_fullname().to_string();
        let mut inner = lock(&self.inner);
        if let (Some(d), Some((old, _))) = (inner.daemon.clone(), inner.advertised.take()) {
            let _ = d.unregister(&old);
        }
        match Mdns::run(&mut inner, |d| d.register(info.clone())) {
            Some(()) => {
                inner.advertised = Some((full, info));
                Ok(())
            }
            None => {
                Mdns::release(&mut inner);
                Err(CANNOT_ANNOUNCE.to_string())
            }
        }
    }

    fn stop_advertising(&self) {
        let mut inner = lock(&self.inner);
        if let (Some(d), Some((full, _))) = (inner.daemon.clone(), inner.advertised.take()) {
            let _ = d.unregister(&full);
        }
        Mdns::release(&mut inner);
    }

    fn browse(&self, own_id: &str, on_results: OnResults) -> Result<(), String> {
        let mut inner = lock(&self.inner);
        if inner.browsing.is_some() {
            return Ok(());
        }
        let Some(receiver) = Mdns::run(&mut inner, |d| d.browse(SERVICE_TYPE)) else {
            Mdns::release(&mut inner);
            return Err(CANNOT_SEARCH.to_string());
        };
        let gate = Arc::new(Gate::new());
        inner.browsing = Some(gate.clone());
        let (own, shared) = (own_id.to_string(), self.inner.clone());
        // One thread that waits on the daemon's channel (it sleeps in `recv`, nothing polls) and ends when the search is stopped or the daemon is shut down.
        std::thread::spawn(move || {
            if run_search(receiver.iter(), &own, &gate, &on_results) {
                // The search ended by itself (the daemon is gone, replaced or released): it is over, and the daemon is released if nothing else needs it.
                let mut inner = lock(&shared);
                if inner.browsing.as_ref().is_some_and(|g| Arc::ptr_eq(g, &gate)) {
                    inner.browsing = None;
                    Mdns::release(&mut inner);
                }
            }
        });
        Ok(())
    }

    fn stop_browsing(&self) {
        let gate = {
            let mut inner = lock(&self.inner);
            let gate = inner.browsing.take();
            if let Some(g) = &gate {
                g.shut();
                if let Some(d) = &inner.daemon {
                    let _ = d.stop_browse(SERVICE_TYPE);
                }
            }
            Mdns::release(&mut inner);
            gate
        };
        // Outside the lock of `Inner`: a result being handed up may be in the service's callback, which can call into `Mdns`.
        if let Some(g) = gate {
            g.wait_idle();
        }
    }
}
''', r'''impl Mdns {
    pub fn new() -> Mdns {
        Mdns::default()
    }

    /// The daemon, made on first use. IPv6 is switched off: the advert and the listener are IPv4, and a daemon that cannot be switched is not used. A daemon that cannot be watched cannot be repaired
    /// and is not used either. `fresh` drops the daemon there is (one that died on its own) and the search that ran on it, and makes another, which announces again what this machine announced.
    fn daemon(shared: &Arc<Shared>, inner: &mut Inner, fresh: bool) -> Option<ServiceDaemon> {
        if fresh {
            if let Some(old) = inner.daemon.take() {
                let _ = old.shutdown();
            }
            if let Some(dead) = inner.browsing.take() {
                dead.shut();
            }
        }
        if let Some(d) = &inner.daemon {
            return Some(d.clone());
        }
        let d = ServiceDaemon::new().ok()?;
        let d = ipv4_only(d.clone(), d.disable_interface(IfKind::IPv6).is_ok(), |d| {
            let _ = d.shutdown();
        })?;
        let Ok(events) = d.monitor() else {
            let _ = d.shutdown();
            return None;
        };
        if let Some((_, info)) = &inner.advertised {
            let _ = d.register(info.clone());
        }
        inner.epoch += 1;
        inner.daemon = Some(d.clone());
        inner.restarter.started(shared.now_ms());
        Mdns::arm(shared, inner, None); // a restart that was waiting is not needed any more
        let (watch, epoch) = (shared.clone(), inner.epoch);
        // Asleep in `recv` (nothing polls): the channel closes when the daemon's thread ends, whoever ended it (`died` tells our own shutdowns from the rest).
        std::thread::spawn(move || {
            for _ in events.iter() {}
            Mdns::died(&watch, epoch);
        });
        Some(d)
    }

    /// Runs `op` on the daemon. If it fails (a daemon that died on its own), the daemon is dropped and `op` is tried once more on a fresh one; `None` when that fails too.
    fn run<T>(shared: &Arc<Shared>, inner: &mut Inner, op: impl Fn(&ServiceDaemon) -> mdns_sd::Result<T>) -> Option<T> {
        let d = Mdns::daemon(shared, inner, false)?;
        if let Ok(v) = op(&d) {
            return Some(v);
        }
        op(&Mdns::daemon(shared, inner, true)?).ok()
    }

    /// Nothing announced and nothing searched: the daemon is shut down, the wish is taken away and a restart that was waiting is cancelled.
    fn release(shared: &Arc<Shared>, inner: &mut Inner) {
        if inner.advertised.is_none() && inner.search.is_none() {
            if let Some(d) = inner.daemon.take() {
                let _ = d.shutdown();
            }
            inner.restarter.set_wanted(false);
            Mdns::arm(shared, inner, None);
        }
    }

    /// Starts the search `inner.search` describes on the daemon (made if need be). True when it runs.
    fn start_search(shared: &Arc<Shared>, inner: &mut Inner) -> bool {
        let Some((own, on_results)) = inner.search.clone() else { return false };
        let Some(receiver) = Mdns::run(shared, inner, |d| d.browse(SERVICE_TYPE)) else { return false };
        let gate = Arc::new(Gate::new());
        inner.browsing = Some(gate.clone());
        let (watch, epoch) = (shared.clone(), inner.epoch);
        // One thread that waits on the daemon's channel (it sleeps in `recv`, nothing polls) and ends when the search is stopped or the daemon is gone.
        std::thread::spawn(move || {
            if run_search(receiver.iter(), &own, &gate, &on_results) {
                // The search ended by itself: the daemon is gone (or was replaced, which `died` sees by its number).
                Mdns::died(&watch, epoch);
            }
        });
        true
    }

    /// The daemon of number `epoch` ended. Ignored if we ended it ourselves (it was replaced or released) or if this death was already seen. Otherwise the dead handle is dropped, the list on screen
    /// (now stale) is emptied, and, if an advert or a search is wanted, a restart is scheduled by the rule.
    fn died(shared: &Arc<Shared>, epoch: u64) {
        let (stale, clear) = {
            let mut inner = lock(&shared.inner);
            if inner.epoch != epoch || inner.daemon.is_none() {
                return;
            }
            if let Some(d) = inner.daemon.take() {
                let _ = d.shutdown();
            }
            let wanted = inner.advertised.is_some() || inner.search.is_some();
            inner.restarter.set_wanted(wanted);
            let wait = inner.restarter.died(shared.now_ms());
            Mdns::arm(shared, &mut inner, wait);
            (inner.browsing.take(), inner.search.as_ref().map(|(_, on)| on.clone()))
        };
        // Outside the lock (the callback may call into `Mdns`): the machines that were listed are no longer known to be there.
        if let Some(gate) = stale {
            if let Some(on) = clear {
                gate.deliver(|| on(Vec::new()));
            }
            gate.shut();
        }
    }

    /// Cancels the restart wait that is pending (if any) and, with `Some(ms)`, starts a new one: a thread asleep on the `Condvar` for at most `ms`, which makes the daemon again when the time is up and
    /// does nothing if it was cancelled meanwhile. No timer, no polling: the thread ends the moment it is cancelled.
    fn arm(shared: &Arc<Shared>, inner: &mut Inner, wait_ms: Option<u64>) {
        inner.wait += 1;
        shared.wake.notify_all();
        let Some(ms) = wait_ms else { return };
        let (number, shared) = (inner.wait, shared.clone());
        std::thread::spawn(move || {
            let begun = Instant::now();
            let mut inner = lock(&shared.inner);
            loop {
                if inner.wait != number {
                    return;
                }
                let left = Duration::from_millis(ms).saturating_sub(begun.elapsed());
                if left.is_zero() {
                    break;
                }
                inner = shared.wake.wait_timeout(inner, left).unwrap_or_else(|e| e.into_inner()).0;
            }
            Mdns::restart(&shared, &mut inner);
        });
    }

    /// The wait is over: if an advert or a search is still wanted, makes the daemon (which announces again) and starts the search again; if that fails, the rule gives the next wait.
    fn restart(shared: &Arc<Shared>, inner: &mut Inner) {
        if inner.advertised.is_none() && inner.search.is_none() {
            inner.restarter.set_wanted(false);
            return;
        }
        let up = Mdns::daemon(shared, inner, false).is_some() && (inner.search.is_none() || inner.browsing.is_some() || Mdns::start_search(shared, inner));
        if !up {
            let wait = inner.restarter.failed_restart();
            Mdns::arm(shared, inner, wait);
        }
    }
}

impl Discovery for Mdns {
    fn advertise(&self, id: &str, name: &str, port: u16) -> Result<(), String> {
        let info = service(id, name, port, "")?.enable_addr_auto();
        let full = info.get_fullname().to_string();
        let mut inner = lock(&self.shared.inner);
        if let (Some(d), Some((old, _))) = (inner.daemon.clone(), inner.advertised.take()) {
            let _ = d.unregister(&old);
        }
        match Mdns::run(&self.shared, &mut inner, |d| d.register(info.clone())) {
            Some(()) => {
                inner.advertised = Some((full, info));
                // A fresh daemon (the old one had died) has no search yet: start the one that is wanted.
                if inner.search.is_some() && inner.browsing.is_none() {
                    let _ = Mdns::start_search(&self.shared, &mut inner);
                }
                Ok(())
            }
            None => {
                Mdns::release(&self.shared, &mut inner);
                Err(CANNOT_ANNOUNCE.to_string())
            }
        }
    }

    fn stop_advertising(&self) {
        let mut inner = lock(&self.shared.inner);
        if let (Some(d), Some((full, _))) = (inner.daemon.clone(), inner.advertised.take()) {
            let _ = d.unregister(&full);
        }
        Mdns::release(&self.shared, &mut inner);
    }

    fn browse(&self, own_id: &str, on_results: OnResults) -> Result<(), String> {
        let mut inner = lock(&self.shared.inner);
        if inner.search.is_some() {
            return Ok(());
        }
        inner.search = Some((own_id.to_string(), on_results));
        if Mdns::start_search(&self.shared, &mut inner) {
            return Ok(());
        }
        inner.search = None;
        Mdns::release(&self.shared, &mut inner);
        Err(CANNOT_SEARCH.to_string())
    }

    fn stop_browsing(&self) {
        let gate = {
            let mut inner = lock(&self.shared.inner);
            inner.search = None;
            let gate = inner.browsing.take();
            if let Some(g) = &gate {
                g.shut();
                if let Some(d) = &inner.daemon {
                    let _ = d.stop_browse(SERVICE_TYPE);
                }
            }
            Mdns::release(&self.shared, &mut inner);
            gate
        };
        // Outside the lock of `Inner`: a result being handed up may be in the service's callback, which can call into `Mdns`.
        if let Some(g) = gate {
            g.wait_idle();
        }
    }
}
''')

edit("windows/src-tauri/src/link/mdns.rs", r'''    #[test]
    fn nothing_is_made_until_something_is_announced_or_searched() {
        let m = Mdns::new();
        assert!(m.inner.lock().unwrap().daemon.is_none(), "a new Mdns holds no daemon");
        m.stop_advertising();
        m.stop_browsing();
        assert!(m.inner.lock().unwrap().daemon.is_none(), "stopping what never started makes nothing");
    }
''', r'''    #[test]
    fn nothing_is_made_until_something_is_announced_or_searched() {
        let m = Mdns::new();
        assert!(m.shared.inner.lock().unwrap().daemon.is_none(), "a new Mdns holds no daemon");
        m.stop_advertising();
        m.stop_browsing();
        assert!(m.shared.inner.lock().unwrap().daemon.is_none(), "stopping what never started makes nothing");
    }

    /// Waits (a test may poll) until the state is held by `Mdns` alone, i.e. until every thread that borrowed it has ended.
    fn threads_ended(m: &Mdns) -> bool {
        let end = Instant::now() + Duration::from_secs(10);
        while Arc::strong_count(&m.shared) > 1 && Instant::now() < end {
            std::thread::sleep(Duration::from_millis(10));
        }
        Arc::strong_count(&m.shared) == 1
    }

    #[test]
    fn a_restart_wait_that_is_cancelled_ends_its_thread_at_once() {
        let m = Mdns::new();
        {
            let mut inner = lock(&m.shared.inner);
            Mdns::arm(&m.shared, &mut inner, Some(600_000));
            assert_eq!(Arc::strong_count(&m.shared), 2, "the wait holds the state");
            Mdns::arm(&m.shared, &mut inner, None);
        }
        assert!(threads_ended(&m), "a cancelled wait ends without waiting its ten minutes");
    }

    #[test]
    fn a_restart_wait_that_runs_out_with_nothing_wanted_makes_nothing() {
        let m = Mdns::new();
        Mdns::arm(&m.shared, &mut lock(&m.shared.inner), Some(20));
        assert!(threads_ended(&m), "the wait ran out and ended");
        let inner = lock(&m.shared.inner);
        assert!(inner.daemon.is_none() && inner.browsing.is_none(), "no daemon, no socket: nothing was wanted");
    }

    #[test]
    fn a_death_nobody_can_attribute_to_the_daemon_we_hold_is_ignored() {
        let m = Mdns::new();
        Mdns::died(&m.shared, 0); // no daemon at all: our own shutdown, or a death already seen
        Mdns::died(&m.shared, 7);
        let inner = lock(&m.shared.inner);
        assert_eq!(inner.wait, 0, "no restart was scheduled");
        assert_eq!(Arc::strong_count(&m.shared), 1);
    }

    // The next two open a real mDNS daemon (multicast sockets), which no other test does: run them by hand, `cargo test -p notchmeow link::mdns -- --ignored`.
    #[test]
    #[ignore = "opens a real mDNS daemon"]
    fn a_daemon_that_ends_closes_the_channel_the_watch_thread_sleeps_in() {
        let d = ServiceDaemon::new().unwrap();
        let events = d.monitor().unwrap();
        d.shutdown().unwrap();
        let (done, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            for _ in events.iter() {}
            let _ = done.send(());
        });
        rx.recv_timeout(Duration::from_secs(10)).expect("the monitor channel closes when the daemon's thread ends");
    }

    #[test]
    #[ignore = "opens a real mDNS daemon"]
    fn a_daemon_that_dies_is_made_again_and_stops_when_nothing_is_wanted() {
        let m = Mdns::new();
        m.advertise(ID, "Desk PC", 4242).unwrap();
        let (epoch, daemon) = {
            let inner = lock(&m.shared.inner);
            (inner.epoch, inner.daemon.clone().expect("a daemon"))
        };
        let _ = daemon.shutdown(); // the daemon ends by itself, as far as `Mdns` can tell: its slot still holds it
        let end = Instant::now() + Duration::from_secs(15);
        loop {
            {
                let inner = lock(&m.shared.inner);
                if inner.epoch > epoch && inner.daemon.is_some() {
                    break;
                }
            }
            assert!(Instant::now() < end, "no new daemon within 15 s (the first wait is one second)");
            std::thread::sleep(Duration::from_millis(100));
        }
        m.stop_advertising();
        let inner = lock(&m.shared.inner);
        assert!(inner.daemon.is_none(), "nothing wanted, nothing kept");
    }
''')

edit("windows/scripts/link-tests/rust-wiring.test.mjs", r'''  assert.deepEqual(where(/std::thread::spawn/), ["mdns.rs"], "the one thread is the browser's, asleep in recv()");
''', r'''  assert.deepEqual(where(/std::thread::spawn/), ["mdns.rs"], "the threads are the daemon's watch, the browser's and a restart wait's, all of them asleep");
''')

edit("windows/scripts/link-tests/rust-wiring.test.mjs", r'''test("nothing listens before Visible: the listener starts in one place''', r'''test("a dead mDNS daemon is made again by a bounded rule, only while something is announced or searched, and without polling (G2b)", () => {
  const m = prod("src/link/mdns.rs");
  const r = prod("src/link/restart.rs");
  assert.equal((m.match(/std::thread::spawn/g) ?? []).length, 3, "the daemon's watch, the browser's, a restart wait's");
  assert.equal((m.match(/\.monitor\(\)/g) ?? []).length, 1, "every daemon is watched, in daemon()");
  assert.equal((m.match(/wake\.wait_timeout\(/g) ?? []).length, 1, "the one wait is a Condvar wait that cancelling wakes");
  assert.doesNotMatch(m, /thread::sleep|recv_timeout|try_recv|interval\(|loop \{\s*std::thread/, "nothing polls");
  assert.match(m, /restarter\.died\(shared\.now_ms\(\)\)/, "a death asks the rule");
  assert.match(m, /fn restart\(shared: &Arc<Shared>, inner: &mut Inner\) \{\s*if inner\.advertised\.is_none\(\) && inner\.search\.is_none\(\) \{\s*inner\.restarter\.set_wanted\(false\);\s*return;/, "nothing is made again when nothing is wanted");
  assert.match(m, /fn release\(shared: &Arc<Shared>, inner: &mut Inner\) \{\s*if inner\.advertised\.is_none\(\) && inner\.search\.is_none\(\) \{[^}]*\}\s*inner\.restarter\.set_wanted\(false\);\s*Mdns::arm\(shared, inner, None\);/, "releasing cancels the wish and the wait");
  assert.match(m, /if inner\.epoch != epoch \|\| inner\.daemon\.is_none\(\) \{\s*return;/, "a daemon we replaced or released is not a death");
  const table = (re, text) => text.match(re)?.[1].replaceAll("_", "").split(",").map((s) => Number(s.trim()));
  assert.deepEqual(table(/DELAYS_MS: \[u64; 3\] = \[([^\]]+)\]/, r), [1000, 5000, 30000]);
  assert.match(r, /STEADY_MS: u64 = 60_000/);
  assert.match(r, /STABLE_MS: u64 = 60_000/);
  const swift = fs.readFileSync(new URL("../../../NotchBuddy/Sources/App/LinkRestart.swift", import.meta.url), "utf8");
  assert.deepEqual(table(/static let delaysMs = \[([^\]]+)\]/, swift), [1000, 5000, 30000], "the Mac's table is this one");
  assert.match(swift, /static let steadyMs = 60_000/);
  assert.match(swift, /static let stableMs = 60_000/);
});

test("nothing listens before Visible: the listener starts in one place''')

```

- [ ] **Step 2: The tests**

Run: `$CL test --offline $TD -p notchmeow link::mdns` and `$CL check --offline $TD -p notchmeow --all-targets`
Expected: `test result: ok. 15 passed; 0 failed; 2 ignored` (three new tests: `a_restart_wait_that_is_cancelled_ends_its_thread_at_once`, `a_restart_wait_that_runs_out_with_nothing_wanted_makes_nothing`, `a_death_nobody_can_attribute_to_the_daemon_we_hold_is_ignored`; the two ignored open a real daemon) and a `check` with no warning. Then `cd windows && npm run check:link`: `ℹ fail 0`.

- [ ] **Step 3: The two by-hand tests (a real daemon, in the container)**

Run: `$CL test --offline $TD -p notchmeow link::mdns -- --ignored`
Expected: `test result: ok. 2 passed`. They open a real `mdns-sd` daemon (multicast sockets, on the container's network only; no packet leaves it that the daemon would not send anyway): the first shows the monitor channel closes when the daemon ends, the second that a daemon that ends is replaced within the first wait (1 s) and that `stop_advertising` then leaves no daemon. If the container refuses the sockets, report that and go on: the Windows and Linux runs of CI do not run them, and the owner runs them in Task 6.

- [ ] **Step 4: Prove it bites**

```bash
python3 .claude/checkpoints/g2b/mut.py rust windows/src-tauri/src/link/mdns.rs '        inner.wait += 1;
' '' link::mdns
(cd windows && python3 ../.claude/checkpoints/g2b/mut.py node src-tauri/src/link/mdns.rs 'if inner.epoch != epoch || inner.daemon.is_none() {' 'if inner.daemon.is_none() {' scripts/link-tests/rust-wiring.test.mjs)
(cd windows && python3 ../.claude/checkpoints/g2b/mut.py node src-tauri/src/link/restart.rs '[u64; 3] = [1_000, 5_000, 30_000]' '[u64; 3] = [1_000, 5_000, 30_001]' scripts/link-tests/rust-wiring.test.mjs)
```

Expected: `FAILED. 14 passed; 1 failed` (the cancelled wait never ends: it takes ten seconds to say so), then `# fail 1` twice.

- [ ] **Step 5: Commit**

```bash
git add windows/src-tauri/src/link/mdns.rs windows/scripts/link-tests/rust-wiring.test.mjs
git commit -F - <<'MSG'
fix(link): a dead mDNS daemon is noticed, the list emptied and the daemon made again (G2b)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

(Sonnet 5.5 for this one. The wiring test reads `LinkRestart.swift`, so it passes only once Task 4 exists: run it again after Task 4; until then it fails on the Mac-table assertion, which is expected and noted in the ledger.)

---

### Task 4: The Mac: the same rule for `LinkListener` and `LinkBrowser`

**Files:**
- Create: `NotchBuddy/Sources/App/LinkRestart.swift`, `tests/LinkRestartTests.swift`, `scripts/test-link-restart.sh`
- Modify: `NotchBuddy/Sources/App/LinkNetwork.swift`, `NotchBuddy/Sources/App/LinkService.swift`, `scripts/test-link-wiring.sh`, `.github/workflows/build.yml`

**Interfaces:**
- Consumes: nothing from the Rust tasks except the table (pinned by `rust-wiring.test.mjs`).
- Produces: `struct LinkRestarter` (`setWanted(_:)`, `started(nowMs:)`, `died(nowMs:) -> Int?`, `failedRestart() -> Int?`), `@MainActor final class LinkRestartWait` (`arm(ms:_:)`, `cancel()`); `LinkListener.isRunning`; `LinkBrowser.init(ownId:onResults:onFailed:)`.

**How it works.** A listener that failed drops itself (now *before* it reports, so the service sees it is gone); `listenerState` calls `listenerLost()` only when `isRunning` is false (a listener that is merely waiting for the network recovers by itself and is still held). `listenerLost` asks the rule and arms the wait; `relaunchListener()` calls the idempotent `startListening()` (now returns `Bool`) and, if even that fails, asks the rule for the next wait. The browser tells the service when it failed **on its own** (`clearIfCurrent`: not when `stop()` ended it); `browserLost()` empties the list and arms the wait; `relaunchBrowser()` calls `start()` again. Visible off (`stopListening`) and the end of browsing (`stopBrowser`) take the wish away and cancel the wait. Both ask for a restart only while `settings.visible` (and, for the browser, `browsers > 0`).

- [ ] **Step 1: Create the rule, its test program and its script**

**Create `NotchBuddy/Sources/App/LinkRestart.swift`:**

```swift
import Foundation

// A listener or a browser that failed comes back by itself (sub-project G2b), slowly, and only while it is wanted. The rule is pure: it is fed with what happened and a clock in milliseconds and
// answers with a wait, or with nothing. The wait grows (1 s, 5 s, 30 s, then every minute for as long as the thing is wanted), so that a Mac whose network is down is tried a few times quickly and
// then costs one attempt a minute, and a thing that fails at once, over and over, never gets a fast loop. One that stayed up for a minute counts as healthy: its next failure starts the table
// again. Nothing is asked for while it is not wanted (Visible off, or nobody looking at Devices or the shelf: the service says so with `setWanted(false)`).
//
// The Rust twin is `link/restart.rs`: the same table (`scripts/link-tests/rust-wiring.test.mjs` reads this file's numbers). Run the tests through scripts/test-link-restart.sh.

struct LinkRestarter: Equatable {
    /// The first three waits.
    static let delaysMs = [1_000, 5_000, 30_000]
    /// Every wait after those.
    static let steadyMs = 60_000
    /// A thing that ran this long before it failed starts the table again.
    static let stableMs = 60_000

    private var wanted = false
    private var failures = 0
    private var upSince: Int?

    /// Whether anything needs it. Turning it off forgets the table and the age.
    mutating func setWanted(_ on: Bool) {
        wanted = on
        if !on { failures = 0; upSince = nil }
    }

    /// It is up (the first time or a restart).
    mutating func started(nowMs: Int) { upSince = nowMs }

    /// It failed. The wait before trying again, in milliseconds, or nil when nothing needs one.
    mutating func died(nowMs: Int) -> Int? {
        if let since = upSince, nowMs - since >= Self.stableMs { failures = 0 }
        upSince = nil
        return next()
    }

    /// A restart could not even start: the next wait.
    mutating func failedRestart() -> Int? {
        upSince = nil
        return next()
    }

    private mutating func next() -> Int? {
        guard wanted else { return nil }
        let wait = failures < Self.delaysMs.count ? Self.delaysMs[failures] : Self.steadyMs
        failures += 1
        return wait
    }
}

/// One pending restart: arming it cancels the one before, cancelling it ends the wait at once. One sleep for the whole wait, nothing polls.
@MainActor
final class LinkRestartWait {
    private var task: Task<Void, Never>?

    func arm(ms: Int, _ fire: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(ms))
            if !Task.isCancelled { fire() }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
```

**Create `tests/LinkRestartTests.swift`:**

```swift
import Foundation

// The restart table of a listener or a browser that failed (LinkRestarter, sub-project G2b) and its one-shot wait. The same cases as link/restart.rs. Run it through scripts/test-link-restart.sh.

@main
enum LinkRestartTests {
    static func wanted() -> LinkRestarter {
        var r = LinkRestarter()
        r.setWanted(true)
        return r
    }

    @MainActor static func main() async {
        CT.section("nothing is scheduled for a thing nobody wants")
        var r = LinkRestarter()
        CT.check("never wanted", [r.died(nowMs: 0), r.failedRestart()], [nil, nil])
        r = wanted()
        r.setWanted(false)
        CT.check("no longer wanted", [r.died(nowMs: 10), r.failedRestart()], [nil, nil])

        CT.section("the waits are 1 s, 5 s, 30 s, then every minute")
        r = wanted()
        r.started(nowMs: 0)
        var waits = [r.died(nowMs: 100)]
        for _ in 0..<6 { waits.append(r.failedRestart()) }
        CT.check("the table", waits, [1_000, 5_000, 30_000, 60_000, 60_000, 60_000, 60_000])

        CT.section("a thing that fails at once again and again never gets a fast loop")
        r = wanted()
        var t = 0
        var seen: [Int?] = []
        for _ in 0..<6 {
            r.started(nowMs: t)
            let w = r.died(nowMs: t + 10)
            seen.append(w)
            t += 10 + (w ?? 0)
        }
        CT.check("the table again", seen, [1_000, 5_000, 30_000, 60_000, 60_000, 60_000])

        CT.section("a minute of life starts the table again")
        r = wanted()
        r.started(nowMs: 0)
        CT.check("first failure, then a failed restart", [r.died(nowMs: 10), r.failedRestart()], [1_000, 5_000])
        r.started(nowMs: 200_000)
        CT.check("59.999 s is not a minute", r.died(nowMs: 259_999), 30_000)
        r.started(nowMs: 300_000)
        CT.check("a minute is", r.died(nowMs: 360_000), 1_000)
        r.started(nowMs: 400_000)
        CT.check("and so is a long life", r.died(nowMs: 1_400_000), 1_000)

        CT.section("turning the wish off forgets the table")
        r = wanted()
        r.started(nowMs: 0); _ = r.died(nowMs: 10); _ = r.failedRestart()
        r.setWanted(false); r.setWanted(true)
        CT.check("back to one second", r.died(nowMs: 20), 1_000)

        CT.section("no wait is shorter than a second or longer than a minute")
        r = wanted()
        var ok = true
        for _ in 0..<200 { if let w = r.failedRestart(), !(1_000...60_000).contains(w) { ok = false } }
        CT.checkTrue("200 waits in a row", ok)

        CT.section("the one-shot wait")
        let wait = LinkRestartWait()
        var fired = 0
        wait.arm(ms: 30) { fired += 1 }
        try? await Task.sleep(for: .milliseconds(300))
        CT.check("it fires once", fired, 1)
        wait.arm(ms: 60_000) { fired += 1 }
        wait.cancel()
        wait.arm(ms: 30) { fired += 10 }
        wait.arm(ms: 30) { fired += 100 }
        try? await Task.sleep(for: .milliseconds(300))
        CT.check("a cancelled wait does not fire, and arming again replaces the one before", fired, 101)
        CT.finish()
    }
}
```

**Create `scripts/test-link-restart.sh`:**

```bash
#!/usr/bin/env bash
# The restart table of a listener or a browser that failed (LinkRestarter) and its one-shot wait (LinkRestartWait), sub-project G2b. Foundation only: no network, no Keychain, no real clock but the
# short waits of the last section.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-link-restart.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/LinkRestart.swift \
    tests/CatTestSupport.swift tests/LinkRestartTests.swift \
    -o "$TEST_DIR/link-restart-tests"
"$TEST_DIR/link-restart-tests"
```

```bash
chmod +x scripts/test-link-restart.sh
bash -n scripts/test-link-restart.sh && bash scripts/test-link-restart.sh | tail -3
```

Expected: `All tests passed.`

- [ ] **Step 2: Apply the wiring edits, the pins and the CI step**

```python
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")

edit("NotchBuddy/Sources/App/LinkNetwork.swift", r'''            case .failed: self.onState(nil, true); self.drop(l)   // a dead listener is not kept: the next start makes a new one
''', r'''            case .failed: self.drop(l); self.onState(nil, true)   // a dead listener is not kept, and is already gone when the report is made: the service starts a new one after a wait (LinkRestart.swift)
''')

edit("NotchBuddy/Sources/App/LinkNetwork.swift", r'''        let l: NWListener? = lock.withLock { let x = listener; listener = nil; return x }
        l?.cancel()
    }
''', r'''        let l: NWListener? = lock.withLock { let x = listener; listener = nil; return x }
        l?.cancel()
    }

    /// True while a socket is held: false before the first start, after `stop()` and after a failure dropped it.
    var isRunning: Bool { lock.withLock { listener != nil } }
''')

edit("NotchBuddy/Sources/App/LinkNetwork.swift", r'''    private let onResults: @Sendable ([Found]) -> Void

    init(ownId: String, onResults: @escaping @Sendable ([Found]) -> Void) {
        self.ownId = ownId
        self.onResults = onResults
    }
''', r'''    private let onResults: @Sendable ([Found]) -> Void
    private let onFailed: @Sendable () -> Void

    /// `onFailed` is called when the browser failed on its own (not when `stop()` ended it): the list is stale and `start()` browses again.
    init(ownId: String, onResults: @escaping @Sendable ([Found]) -> Void, onFailed: @escaping @Sendable () -> Void) {
        self.ownId = ownId
        self.onResults = onResults
        self.onFailed = onFailed
    }
''')

edit("NotchBuddy/Sources/App/LinkNetwork.swift", r'''            // A failed browser is cancelled and cleared, so the next start() browses again. The browser has no failure hook to report to, so nothing else is said.
            b.stateUpdateHandler = { [weak self, weak b] state in
                guard case .failed = state, let b else { return }
                b.cancel()
                self?.lock.withLock { if self?.browser === b { self?.browser = nil } }
''', r'''            // A failed browser is cancelled and cleared, so the next start() browses again, and the service is told (unless `stop()` ended it first) so that it starts it again after a wait.
            b.stateUpdateHandler = { [weak self, weak b] state in
                guard case .failed = state, let b else { return }
                b.cancel()
                if self?.clearIfCurrent(b) == true { self?.onFailed() }
''')

edit("NotchBuddy/Sources/App/LinkNetwork.swift", r'''        let b: NWBrowser? = lock.withLock { let x = browser; browser = nil; return x }
        b?.cancel()
    }
''', r'''        let b: NWBrowser? = lock.withLock { let x = browser; browser = nil; return x }
        b?.cancel()
    }

    /// Clears `b` if it is still the browser; true when it was (a `stop()` may have taken it already).
    private func clearIfCurrent(_ b: NWBrowser) -> Bool {
        lock.withLock { if browser === b { browser = nil; return true }; return false }
    }
''')

edit("NotchBuddy/Sources/App/LinkService.swift", r'''    private var browser: LinkBrowser?
    private var browsers = 0
''', r'''    private var browser: LinkBrowser?
    private var browsers = 0
    /// A listener or a browser that failed comes back after a wait (LinkRestart.swift), while the Mac is visible and, for the browser, somebody is looking.
    private var listenerRestarter = LinkRestarter()
    private let listenerWait = LinkRestartWait()
    private var browserRestarter = LinkRestarter()
    private let browserWait = LinkRestartWait()
''')

edit("NotchBuddy/Sources/App/LinkService.swift", r'''    private func startListening() {
        guard let me = identity() else { return }
''', r'''    @discardableResult
    private func startListening() -> Bool {
        guard let me = identity() else { return false }
''')

edit("NotchBuddy/Sources/App/LinkService.swift", r'''            if fresh { listener = l; listenerToken = token; listenerFine(); appendAppLog("link.log", "listening") }
        } catch { problem = "This Mac could not start listening."; listening = false }
    }
''', r'''            if fresh { listener = l; listenerToken = token; listenerFine(); appendAppLog("link.log", "listening") }
            return true
        } catch { problem = "This Mac could not start listening."; listening = false; return false }
    }
''')

edit("NotchBuddy/Sources/App/LinkService.swift", r'''        gate.stop()
        listener?.stop(); listener = nil; listenerToken = nil
        listening = false
        sendQueueCancelled = true
''', r'''        gate.stop()
        listenerRestarter.setWanted(false); listenerWait.cancel()
        listener?.stop(); listener = nil; listenerToken = nil
        listening = false
        sendQueueCancelled = true
''')

edit("NotchBuddy/Sources/App/LinkService.swift", r'''        if failed { listening = false; problem = "This Mac can't listen right now. Check System Settings, Privacy & Security, Local Network." }
        else if port != nil { listening = true; listenerFine(); recordPort(port) }
    }
''', r'''        if failed {
            listening = false; problem = "This Mac can't listen right now. Check System Settings, Privacy & Security, Local Network."
            if !(listener?.isRunning ?? false) { listenerLost() }   // it dropped itself (a listener that is only waiting for the network is still held, and comes back by itself)
        } else if port != nil { listening = true; listenerFine(); recordPort(port) }
    }

    /// The listener failed and dropped itself. It comes back after a wait that grows (1 s, 5 s, 30 s, then every minute) while the Mac is visible; Visible off ends it.
    private func listenerLost() {
        guard settings.visible else { return }
        listenerRestarter.setWanted(true)
        guard let ms = listenerRestarter.died(nowMs: Self.nowMs()) else { return }
        listenerWait.arm(ms: ms) { [weak self] in self?.relaunchListener() }
    }

    private func relaunchListener() {
        guard settings.visible else { return }
        if startListening() { listenerRestarter.started(nowMs: Self.nowMs()) }
        else if let ms = listenerRestarter.failedRestart() { listenerWait.arm(ms: ms) { [weak self] in self?.relaunchListener() } }
    }
''')

edit("NotchBuddy/Sources/App/LinkService.swift", r'''        let b = LinkBrowser(ownId: id) { [weak self] results in Task { @MainActor in self?.browsed(results) } }
        browser = b
        b.start()
    }

    private func stopBrowser() {
        browser?.stop(); browser = nil
        seen = [:]
    }
''', r'''        let b = LinkBrowser(ownId: id, onResults: { [weak self] results in Task { @MainActor in self?.browsed(results) } },
                            onFailed: { [weak self] in Task { @MainActor in self?.browserLost() } })
        browser = b
        b.start()
    }

    private func stopBrowser() {
        browserRestarter.setWanted(false); browserWait.cancel()
        browser?.stop(); browser = nil
        seen = [:]
    }

    /// The browser failed: the list on screen is stale, so it is emptied, and the browser starts again after a wait that grows (1 s, 5 s, 30 s, then every minute) while somebody is looking.
    private func browserLost() {
        guard browser != nil, browsers > 0, settings.visible else { return }
        seen = [:]
        refreshRows()
        browserRestarter.setWanted(true)
        guard let ms = browserRestarter.died(nowMs: Self.nowMs()) else { return }
        browserWait.arm(ms: ms) { [weak self] in self?.relaunchBrowser() }
    }

    private func relaunchBrowser() {
        guard let b = browser, browsers > 0, settings.visible else { return }
        b.start()   // idempotent: the failed browser was cleared, so this browses again; if it fails again `browserLost` is called again
        browserRestarter.started(nowMs: Self.nowMs())
    }
''')

edit("scripts/test-link-wiring.sh", r'''devicesOpened(); comments excluded" 5 $APP/LinkService.swift''', r'''devicesOpened() and the relaunch after a failure; comments excluded" 6 $APP/LinkService.swift''')

edit("scripts/test-link-wiring.sh", r'''exists only while its phase lasts)" 6 "${LINK[@]}" -- ''', r'''exists only while its phase lasts; and the one-shot wait before a failed listener or browser is started again, in LinkRestart.swift)" 7 "${LINK[@]}" -- ''')

edit("scripts/test-link-wiring.sh", r'''echo "a connection holds nothing until it has earned it"
''', r'''echo "a failed listener or browser comes back, slowly, and only while it is wanted"
pin "the wait table is in one place, and the Rust twin reads it (1 s, 5 s, 30 s, then every minute)" 1 $APP/LinkRestart.swift -- 'static let delaysMs = \[1_000, 5_000, 30_000\]'
pin "the one sleep of a restart is in LinkRestart.swift and is a single wait (no loop around it)" 1 $APP/LinkRestart.swift -- 'Task\.sleep'
pin "a restart is armed in three places: the listener's loss, its relaunch that could not start, and the browser's loss" 3 $APP/LinkService.swift -- 'Wait\.arm\(ms: ms\)'
pin "Visible off ends the listener's restart, and the end of browsing the browser's (the wish goes and the wait is cancelled)" 2 $APP/LinkService.swift -- 'Restarter\.setWanted\(false\)'
pin "a restart is wanted only while the Mac is visible (the listener's loss, its relaunch, the browser's loss and its relaunch each check it: four lines, and the one that was already there)" 5 $APP/LinkService.swift -- 'settings\.visible else \{ return \}'
pin "a browser that failed is told to the service only when it failed on its own, not when stop() ended it" 1 $APP/LinkNetwork.swift -- 'if self\?\.clearIfCurrent\(b\) == true \{ self\?\.onFailed\(\) \}'

echo "a connection holds nothing until it has earned it"
''')

edit(".github/workflows/build.yml", r'''      - name: Link island card rules (one card at a time, the click settle time)
        run: bash scripts/test-link-service.sh
''', r'''      - name: Link island card rules (one card at a time, the click settle time)
        run: bash scripts/test-link-service.sh

      - name: Link restarts (a failed listener or browser comes back after a bounded wait)
        run: bash scripts/test-link-restart.sh
''')

```

- [ ] **Step 3: Check**

```bash
bash scripts/test-link-wiring.sh 2>&1 | tail -3
for s in test-link-restart test-link-network test-link-service test-link-files test-link-session; do bash scripts/$s.sh 2>&1 | tail -1; done
(cd windows && node --experimental-strip-types --test scripts/link-tests/*.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)")
```

Expected: no `✗` and `0 failed` for the wiring script, `All tests passed.` five times, and the node run with `# fail 0` (it reads `LinkRestart.swift` now).

- [ ] **Step 4: Prove it bites**

```bash
python3 .claude/checkpoints/g2b/mut.py swift NotchBuddy/Sources/App/LinkRestart.swift 'static let delaysMs = [1_000, 5_000, 30_000]' 'static let delaysMs = [1_000, 5_000, 31_000]' scripts/test-link-restart.sh
python3 .claude/checkpoints/g2b/mut.py swift NotchBuddy/Sources/App/LinkService.swift '        listenerRestarter.setWanted(false); listenerWait.cancel()
' '' scripts/test-link-wiring.sh
python3 .claude/checkpoints/g2b/mut.py swift NotchBuddy/Sources/App/LinkNetwork.swift 'if self?.clearIfCurrent(b) == true { self?.onFailed() }' 'self?.onFailed()' scripts/test-link-wiring.sh
```

Expected: each prints at least one `✗` line.

- [ ] **Step 5: Build the app (Debug), without launching it**

```bash
(cd NotchBuddy && xcodegen >/dev/null && xcodebuild -scheme NotchBuddy -configuration Debug build CODE_SIGNING_ALLOWED=NO -derivedDataPath "$TMPDIR/g2b-dd" 2>&1 | grep -E "error:|warning: .*Link(Restart|Service|Network)|BUILD (SUCCEEDED|FAILED)")
```

Expected: `** BUILD SUCCEEDED **` and no warning or error from the three Link files (Swift 6 strict concurrency is on). Delete `$TMPDIR/g2b-dd` with `trash` afterwards. **Never open the built app.**

- [ ] **Step 6: Commit**

```bash
git add NotchBuddy/Sources/App/LinkRestart.swift NotchBuddy/Sources/App/LinkNetwork.swift NotchBuddy/Sources/App/LinkService.swift tests/LinkRestartTests.swift scripts/test-link-restart.sh scripts/test-link-wiring.sh .github/workflows/build.yml
git commit -F - <<'MSG'
fix(link): a failed listener or browser on the Mac comes back after a bounded wait (G2b)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

---

### Task 5: Docs and the whole-tree checks

**Files:**
- Modify: `windows/README.md`, `CLAUDE.md`

**Interfaces:** none.

- [ ] **Step 1: Apply the edits**

The two "Known limit" bullets of the link in `windows/README.md` (the Windows removal by path; the clean quit) are replaced by what is now true, plus the restart; `CLAUDE.md` gets one sentence in the Mac G2 paragraph and one in the Windows/Linux G2 paragraph.

```python
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")

edit("windows/README.md", r'''- Known limit: when a Windows transfer does not finish, its partial file is removed by the path it was created under, without checking that the file there is still that one (Linux checks the device and inode first). If another file takes the name during the transfer, that file can be removed.
- Known limit: a clean quit in the middle of a receive removes the partial file (`link::files::remove_partials`, from the exit hook), but `kill -9`, a crash and a power loss can still leave a partial file in `Downloads/NotchMeow`. On a clean quit that partial file is removed by its path, without the device and inode check a normal discard makes on Linux, so a file the user moved away or one that another file replaced under the same name can be removed on quit.
''', r'''- A received file on Windows is held open while it is written, with delete access and without the right to share deleting, so nobody can rename, replace or delete it meanwhile; it is marked for deletion through that handle as soon as its mark of the web is written, and the mark comes off only when the transfer is complete. A transfer that does not finish (declined, cancelled, failed), a clean quit, a crash and `kill -9` therefore all end with Windows removing the file when the handle closes, and no file is ever removed by its path. Known limit: while the file is being written no other program can open it either (an antivirus scan waits for the end), and a drive that does not support streams refuses the file. Linux removes a partial file by its path after checking the device and inode of the file it made (a window of microseconds is left between the check and the removal); on a clean quit the exit hook removes it (`link::files::remove_partials`), and `kill -9`, a crash and a power loss can still leave a partial file in `Downloads/NotchMeow` there.
- If the mDNS daemon ends on its own, the machine list is emptied and the daemon is made again after 1 s, then 5 s, 30 s and every minute for as long as this machine is visible (or Devices or the shelf is searching), announcing the machine again and searching again; a minute of life starts the table over (`link/restart.rs`, `link/mdns.rs`). Nothing is made again while Visible is off and nobody is searching. A restart that keeps failing shows an empty list and no message.
''')

edit("CLAUDE.md", r'''`scripts/check-link-render-private.sh` pins that no picture and no link source reads this Mac's name or user (LinkService's init default is the one place).
''', r'''`scripts/check-link-render-private.sh` pins that no picture and no link source reads this Mac's name or user (LinkService's init default is the one place). A listener or a browser that failed on its own comes back after a bounded wait (1 s, 5 s, 30 s, then every minute, only while the Mac is visible and, for the browser, somebody is looking): `LinkRestart.swift` holds the table (`LinkRestarter`, one `LinkRestartWait`), `scripts/test-link-restart.sh` tests it, and `rust-wiring.test.mjs` pins that it is the Rust twin's table (G2b).
''')

edit("CLAUDE.md", r'''`windows/scripts/test-link-peers.sh` runs two real `link_peer` processes. New crates `snow` and `mdns-sd` were approved by the owner on 2026-10-14.
''', r'''`windows/scripts/test-link-peers.sh` runs two real `link_peer` processes. New crates `snow` and `mdns-sd` were approved by the owner on 2026-10-14. G2b: a received file on Windows is held without `FILE_SHARE_DELETE` and marked for deletion through its own handle, so a discard never removes a file by its path (`link/files.rs`: the pure `arm`/`clear` are tested everywhere, `doom` and the open's access are Windows-only and owed to CI), and a dead mDNS daemon is made again after 1 s, 5 s, 30 s, then every minute while something is announced or searched (`link/restart.rs` the pure rule, `link/mdns.rs` the wiring pinned by `rust-wiring.test.mjs`).
''')

```

- [ ] **Step 2: The whole tree**

```bash
$CL test --offline $TD --workspace 2>&1 | grep -E "^test result"
$CL check --offline $TD -p notchmeow --all-targets 2>&1 | grep -cE "^warning"
(cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:link 2>&1 | grep -E "^ℹ (tests|pass|fail)"; npm run check:cat 2>&1 | grep -E "^ℹ (pass|fail)")
bash scripts/test-link-contract.sh 2>&1 | tail -1
node --test tests/cat/additive.test.mjs 2>&1 | grep -E "^# (pass|fail)"
```

Expected: workspace `0 failed` with the passed count the baseline's plus eleven (`restart` 6, `files` 2, `mdns` 3) and `2 ignored`; `0` warnings; `tsc exit 0`; `ℹ fail 0` twice; the contract script's last line unchanged from the baseline (`5 fixtures parse with JSON.parse`); `# fail 0`.

- [ ] **Step 3: Commit**

```bash
git add windows/README.md CLAUDE.md
git commit -F - <<'MSG'
docs(link): the two parked limits are fixed, the restart is described (G2b)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
```

---

## After Task 5: the whole-branch review

`nm-reviewer-deep` (Sonnet 5.5, high; trigger 4). Brief: the merge-base diff of the branch, this plan's Global Constraints and Review Focus, `windows/src-tauri/src/link/files.rs`, `mdns.rs`, `LinkService.swift`, `LinkNetwork.swift`. Ask, with file and line for each finding: (1) Windows: that every path by which a partial file can end (discard, drop, failed `finish`, failed `open`, quit, crash) ends in the handle closing while the file is marked for deletion, and that no removal by path remains except the one in `open()` after Windows refused the mark; that the sequence "create, mark of the web by path, mark for deletion, write, flush, clear" has no step that needs a share right the open lacks (read the `windows` crate and the Win32 documentation, not memory); that nothing in `service.rs` or `transfer.rs` reads, renames or opens a partial file by its path while the sink holds it (an `Err` there would now be a sharing violation); (2) `mdns.rs`: the lock order (the lock of `Shared.inner`, then nothing else; the gate's locks are taken outside it), that no callback runs under it, that the watch thread cannot report a death for a daemon we shut down, that `arm` cannot leave a thread behind after `release`, and that nothing runs while Visible is off; (3) the Mac: that `listenerLost` cannot fire for a listener that is only waiting, that a restart cannot start a second listener or browser, and that stale timers cannot restart anything after Visible turns off (the generation is not involved: a relaunch re-checks `settings.visible`); (4) that no wire byte, no fixture and no shipped view changed (`git diff` of `docs/LINK-CONTRACT.md`, `tests/fixtures/`, `views/*.ts`, `style.css`). Findings go to the controller, who fixes by `nm-implementer-deep` and has the fix re-reviewed.

---

### Task 6: Checkpoint: the owner's real-machine checks

No code and no commit. The executing session stops here and reports to the main session (with `SendMessage`) the commits, every test line, the review's findings and what was fixed, and **what is owed**: the Windows-only Rust (never compiled or run on the Mac), the by-hand mDNS tests if the container refused them, and the Mac's real failures (not forceable). No agent launches the real app.

Build with `cd windows && npm install && npm run tauri dev` (or a tester build) on a Windows PC and, for the Mac lines, the Mac's Debug or tester build of the same period. The Mac or a second PC is the sender.

1. **Windows CI is green.** Before the owner looks at anything: `windows-tests.yml` (`windows-latest`) compiles `doom` and the Windows branches and runs the three Windows-only tests of `files.rs`. A red there is a finding for Task 1.
2. **A download that finishes still carries the mark of the web.** Send a file (1 MB, then 200 MB) from the Mac and Accept. When it is complete: `Get-Content -Path .\file -Stream Zone.Identifier` prints `ZoneId=3` (Review Focus 1: the stream is written by path on a held file), the file opens, Explorer warns on a `.exe`.
3. **Decline, cancel and fail while another app tries to touch the file.** Send a 200 MB file and Accept; while it receives, in PowerShell in `Downloads\NotchMeow\` try `Rename-Item`, `Remove-Item` and `Move-Item` on the partial file, and try to make a new file with the same name: each must be refused ("in use by another process" or "access denied"), and nothing may replace it. Then: (a) **Cancel** on the island: the partial file is gone; (b) send again and **turn the sender's Wi-Fi off**: the receiver ends and the file is gone; (c) send again and end NotchMeow with `Stop-Process -Force` in the middle: **the partial file is gone** (it used to stay); (d) a declined offer leaves no file. After each, a file of the same name that you create by hand is never removed by a later transfer.
4. **A file in progress cannot be read by other programs (new, accepted by design).** While receiving, opening the partial in Notepad is refused (it is waiting for deletion until it is complete); an antivirus scans it once it is complete. Tell the owner if that bites in daily use.
5. **The list recovers on Windows.** With Visible on and Devices open, the Mac listed: (a) turn Wi-Fi off and on: the list empties and refills; (b) put the PC to sleep and wake it: the same; (c) add a firewall rule that blocks UDP 5353 inbound and outbound for NotchMeow, wait a minute, remove it: the list refills without touching Visible. These exercise the network, which `mdns-sd` mostly handles itself; a dead daemon cannot be forced from outside, so also run **`cd windows/src-tauri && cargo test -p notchmeow link::mdns -- --ignored`** on the PC: both tests pass (a real daemon on Windows ends, is noticed and is made again).
6. **Nothing when hidden.** Visible off and the island hidden: Task Manager shows no extra thread or socket from the link (`Get-NetUDPEndpoint -OwningProcess <pid>` lists no 5353); switch Visible on, then off: the 5353 sockets go with it and stay gone, and nothing starts again a minute later.
7. **The Mac.** With Devices open and Visible on, turn the Mac's Wi-Fi off and on: the list refills and Devices shows no stale machine. Visible off and on, and closing and opening Devices, behave as before; Activity Monitor shows nothing busy while the island is hidden. (A failed `NWListener` or `NWBrowser` cannot be forced; the rule, the wiring and the build are what is checked.)

Write the answers in the report: each line passes, fails, or needs a change. **A line that fails is a finding, not a flake.** Fixes are made by `nm-implementer-deep` (a failure of unknown cause is trigger 2) with a regression test where a test can see it, re-reviewed by `nm-reviewer`; the whole-branch review is repeated only if a fix touched `files.rs` or `mdns.rs`. The owner merges; **nothing is pushed by the plan**.

---

## Questions for the owner

None blocks the plan; each has the default it is built on.

1. **Partial files are unreadable by others while they are received (Windows).** The price of "nobody can rename, replace or delete it" and "gone even after `kill -9`" is that an antivirus or Explorer cannot open the partial file until it is complete. Default: accepted (a partial file is useless to them anyway).
2. **The Mac is included (Task 4).** The Mac has the same restart gap (not the partial-file one). Default: fixed here, because the Mac gets at least what Windows gets. The alternative is to drop Task 4; nothing else depends on it except the Mac-table pin in `rust-wiring.test.mjs`, which would then be removed.
3. **A first announce that fails is not retried by itself.** The user's click gets the existing sentence ("This computer could not be announced on the network."); only a daemon that ran and then died is restarted. Default: as written.
4. **A restart that keeps failing is silent.** The list stays empty and the retries go on every minute; there is no new line in Settings → Devices (that is a snapshot change and a page change, out of this plan's size). Default: as written.

**Stops for the owner:** none known. A download (a "Downloading" line, or a changed `Cargo.lock`) would be one; so would a failure of the mark of the web on a held file (Review Focus 1), whose fix would loosen the sharing and so change the guarantee.

## Dry run

Before this plan was handed over it was run in a throwaway `git clone --local --shared` of `0466d5a2` (nothing was committed or pushed, no file of the repository was edited, the Tauri app and the app in `/Applications` were never launched, the Docker image was neither built nor pulled):

- **The plan's own blocks were executed.** A script extracted every `python` edit block and every "Create" block from this file and ran them in a second clone: 38 edits and 4 new files, and `diff -r` against the tree that was tested shows no difference. The 38 find texts occur exactly once at the base, and each again at its turn (the Setup pre-flight prints the same). All 20 `bash` blocks pass `bash -n`.
- **Rust, in the image `cargo-linux.sh` uses, offline.** `link::` 232 passed, 2 ignored; the whole workspace 559 passed, 0 failed, 2 ignored (eleven more than before: `restart` 6, `files` 2, `mdns` 3); `cargo check --all-targets` with no warning. `cargo-linux.sh test --offline` works as the plan writes it (the script does not forward `CARGO_NET_OFFLINE`, so the plan passes `--offline`); the same tests were also run with `--network none`. `cargo tree --offline --locked --target x86_64-pc-windows-msvc -e features -i windows@0.61.3` shows `Win32_Storage_FileSystem` and `Cargo.lock` is unchanged: **no download, no new crate**.
- **A real daemon.** The two `--ignored` tests pass in the container (1 s): a `mdns-sd` 0.11.5 daemon that ends closes its monitor channel, and `Mdns` makes a new daemon (a higher number) within the first wait and leaves none after `stop_advertising`. That is the assumption the whole of Task 3 rests on, shown on the real crate.
- **"Prove it bites".** Five Rust mutations fail the tests they should (`restart` table and stability, `arm`, `clear`, the missing cancel), three node mutations fail `rust-wiring.test.mjs` (the epoch check, the Rust table, the Mac table), three Swift mutations fail `test-link-restart.sh` and `test-link-wiring.sh`.
- **Page and Mac.** `node --test scripts/link-tests/*.test.mjs`: 45 passed. `test-link-restart.sh` passes; `test-link-wiring.sh`, `test-link-network.sh`, `test-link-service.sh`, `test-link-files.sh` and `test-link-session.sh` pass. **`xcodegen` and `xcodebuild` Debug: `BUILD SUCCEEDED`, no warning from `LinkRestart.swift`, `LinkService.swift` or `LinkNetwork.swift`** (the app was built into a scratch folder and never opened). The first draft of the Mac pins was wrong twice (a comment that said `Task.sleep`, and a `settings.visible else { return }` that already existed once): the run found both and they are fixed in the text above.
- **Not run, and why it matters.** (a) **Every `#[cfg(windows)]` line**: `doom`, the open's access and sharing, the Windows blocks of `open()` and `finish()`, and the three Windows-only tests. The `windows` crate cannot even be type-checked on Linux (its futures crate needs Windows), so the signatures (`SetFileInformationByHandle`, `FILE_DISPOSITION_INFO { DeleteFile: bool }`, `FileDispositionInfo`, `HANDLE(*mut c_void)`) were read in the 0.61.3 source, not compiled. CI (`windows-tests.yml`) and Task 6 are the first run; base `0466d5a2` is a Windows compile fix, so expect that one may go red once. (b) That the `Zone.Identifier` stream can be written on a file held without `FILE_SHARE_DELETE` (Review Focus 1): argued from the access and share rules, not seen. (c) A real daemon death or a failed `NWListener`/`NWBrowser` on the owner's machines. (d) Whether the first `cargo build --release -q -p notchmeow-hook` of `cargo-linux.sh`, which has no `--offline`, would download on a cold volume: it did not on this one.

## Owner's answers (2026-10-16)

The owner asked for these two items to be fixed before the public release (G2-tauri's parked Windows removal by path, and the mDNS daemon death). The Mac task (Task 4) is an addition of this plan, for the owner to confirm or drop (question 2). The plan runs after nothing else is open on `files.rs`, `mdns.rs`, `LinkService.swift` or `LinkNetwork.swift`.


**Main session, 2026-10-16 (the owner: "finish the whole thing for release date").** The four questions take their defaults: partial files locked while received (1), Task 4 kept because the Mac gets at least what Windows gets (2), and 3 and 4 as written. The owner can still override any of them at Task 6.

**The Windows code is now type-checked here.** `windows/scripts/cargo-windows-check.sh` (added with this plan) runs `cargo check --offline --workspace --all-targets --target x86_64-pc-windows-gnu` in the same container, with two check-only stand-ins for the MinGW compiler and `windres`. It found and `0466d5a2` fixed two Windows compile errors. **Every task that touches `#[cfg(windows)]` code runs it before its commit and reports its last line** (`Finished ...` with no `error`), with `--target-dir /repo/windows/target/win-g2b` so it never shares a build with another session. It is a type check only: linking and running stay owed to CI and to Task 6. The controller adds its result to the report.
