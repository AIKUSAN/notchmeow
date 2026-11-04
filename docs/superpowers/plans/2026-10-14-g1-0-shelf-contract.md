# G1-0 Shelf Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give both apps what sub-project G1 (shelf and send) needs from the shared contract before the app plans run: the three pure rules of the shelf, written once in a Python reference and pinned by two JSON fixtures under `tests/fixtures/shelf/`: `zoneAt` (which half of the open island a pointer is in: Ask or Shelf), `shelfClean` (how `shelf.json` is read: ids, names, links, sizes, duplicates, the 30-item cap, newest first) and `shelfAdd` (what a drop on the Shelf half does: added, duplicate, full or invalid for each file, and nothing already shelved is ever removed). The apps use none of it yet: those are the G1-mac and G1-tauri plans.

**Architecture:** This contract has the shape of the AI contract (`tests/fixtures/ai/`), not the cat contract, because the spec says so (G1-0: `shelf-cases.json`, `zone-cases.json`, `reference.py`): there is no new JavaScript and no change to `cat-core.js`, `gen-cat-fixtures.mjs` or any existing fixture. `reference.py` (Python standard library) holds the three rules as plainly as possible and is the tie-breaker. `build_cases.py` writes the two JSON files with every expected answer typed out by hand and none computed by the reference, so the fixtures and the reference check each other; `--check` fails on drift. `scripts/test-shelf-contract.sh` runs both, and CI runs that script. `docs/SHELF-CONTRACT.md` is the document the app plans cite. There is no prototype panel: nothing in G1-0 is visible. The owner's checkpoint is a plain-language read of the rules and the open questions (Task 4).

**Tech Stack:** Python 3 (standard library only), Bash, JSON. Node 22 only for the regression run of the cat contract.

**Spec:** `docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md`, revision 2, sub-project G, sections "G1. Shelf and send" (Dropping, The shelf view, Storage, Send) for the rules and "G1-0 and G2-0. The contracts" for the files. Read the whole spec before starting. This plan implements only G1-0; G1-mac, G1-tauri and everything of G2 are other plans.

**Base:** branch `g1-0/shelf-contract`, created from `notchmeow/rebrand` at `5f9051c` or later, with this plan file already committed to `notchmeow/rebrand`. This plan touches no app code under `NotchBuddy/` or `windows/`, no `design/prototype/` file and no existing fixture. **It changes no pixel and no behaviour in either app.**

## Global Constraints

Every task's requirements include this section. Values are copied from the spec; the lines marked "(plan decision)" are choices this plan makes where the spec is silent, and are listed again under "Open questions for the owner".

- **Two halves, one centre line (spec "Dropping"):** the open island is split at its centre line into **Ask** (left) and **Shelf** (right); the half is decided by the pointer's position at release by one pure rule, `zoneAt`. The centre line is Ask, the drop that exists today (plan decision). Outside the island there is no half.
- **Shelf limits (spec "The shelf view", "Dropping"):** at most **30** items, newest first; items past 30 are refused with a short note and **nothing old is removed silently**.
- **Reading `shelf.json` (spec "Storage"):** one clean-up rule in the shared contract (hostile files, duplicates, the cap, unknown fields), as for the Cat settings; the rule never raises and cleaning twice equals cleaning once.
- **Item fields (plan decision):** `{id, name, size, folder, copy, link?, addedAt}`. The spec names none. A copy (promised files, browser images) has no `link`; a link item (a secure bookmark on the Mac, a path on Windows/Linux) has one; a folder is only ever a link.
- **Counting (plan decision):** names and links are limited in Unicode **code points** (255 and 8192), so Python, JavaScript and Swift agree; an id must match `[A-Za-z0-9_-]{1,64}` as a **whole** string.
- **Numbers:** `size` and `addedAt` are whole numbers from 0 to 9007199254740991 (the largest integer JavaScript holds exactly), and `5.0` is the same JSON number as `5`. JSON cannot hold `NaN`, `Infinity` or `undefined`: the fixtures use text, `null`, a boolean or a missing key for "not a number", and each port adds its own tests for a non-finite number.
- **Only new files.** `tests/fixtures/cat/` and `tests/fixtures/ai/` stay byte for byte (`node scripts/check-fixtures-additive.mjs 5f9051c` must pass). The cat contract (`bash scripts/test-cat-contract.sh`) must pass unchanged. The only existing files edited are `.github/workflows/build.yml` (one step), `CLAUDE.md` and `ARCHITECT.md` (one bullet each) and the spec (its G1-0 table).
- **Python standard library only; no npm package, no new dependency.** Same style as `tests/fixtures/ai/reference.py` (a `check()` that prints `✓` or `✗` and counts failures, exit status 1 on any failure).
- **No telemetry, no network, nothing outside the repository.** The scripts read and write only `tests/fixtures/shelf/`.
- **Nothing of Coucou's comes back, and the names Coucou and Mochi appear in no new file.** `scripts/check-no-leftovers.sh` must stay green.
- **Commits:** local only, never pushed. End every commit message with `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>` when a Haiku agent wrote it, or `Claude Sonnet 5.5` when an `nm-implementer-deep` did.

## SUBAGENT RULES

Every subagent and the controller follow these; the controller puts them in each brief.

- **Never launch, quit or replace a NotchMeow app or the Tauri app.** The work is files and Python.
- **Install and download nothing.** No `pip install`, no `npm install`, no network.
- **Delete with `trash`, never `rm -rf`,** and give scratch files unique names (the prefix `g10-`, in `${TMPDIR:-/tmp}`).
- **Never run the real `claude` binary, never read tokens, never sign in.**
- **Never write to `~/Library/Logs/NotchMeow/` or to an app's preferences.** Nothing in this plan touches `UserDefaults`.
- **No Coucou or Mochi names.**
- **Commit only in a task's commit step, and never push.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder, the second `g1-0/shelf-contract`. If either is wrong, stop and report.
- **Never edit an existing fixture, `cat-core.js` or `gen-cat-fixtures.mjs`.**
- **Python writes no `__pycache__`** into the repository: import `reference.py` only with `sys.dont_write_bytecode = True` (Task 4 does), and delete nothing with `rm -rf`.
- **Subagents are the `nm-*` agents** (Haiku 5.5 first; Sonnet 5.5 only on a named CLAUDE.md trigger; never Opus or Fable). The table below says which one runs each task.
- **If a command is denied by a permission prompt, stop and report it. Do not look for a workaround.**
- **If a `find` text of a patch step is not found exactly once, stop and report.** Do not edit the anchor.

## Review Focus

The spec says what the rules are. It is silent on these inputs, and each would bite a person (or a port) first, most likely first. Each line names its test.

1. **A hostile or damaged `shelf.json`:** the file is not an object, `items` is text or an object, an id such as `../x`, `a/b`, an empty string or `a` followed by a newline, a name with a path separator or a control character, a link with a NUL, a 300-item file. Expected: an empty shelf or the clean items only, never a throw, nothing on `Object.prototype`, an item whose folder name could escape `shelf/<id>/` never survives. Tests: Task 2 "not a shelf: …", "hostile id …", "hostile name …", "hostile link …", "a hostile file with 45 items…" and the 3000-case fuzz.
2. **The same file dropped twice, a drop with more files than room, a drop on a full shelf:** Expected: the second drop adds nothing and says `duplicate`; a full shelf refuses and removes nothing; a re-drop on a full shelf says `duplicate`, not `full`; of three files with room for two, the first two are added. Tests: Task 3 "a file already on the shelf is a duplicate", "a full shelf refuses and removes nothing", "a full shelf says duplicate…", "room for two of three", "room for one, a duplicate does not use it" and the 1500-drop property test.
3. **The pointer at the centre line, at the edges and outside, with fractional and odd numbers:** Retina pointers have half points and an odd island width has an exact centre. Expected: the centre line is Ask, 0 and the width are inside, a hair outside is `null`, text or `true` is `null`. Tests: Task 1, every row of `zone-cases.json`.
4. **Names with emoji and accents, counted differently by each language:** 255 emoji are 255 code points (510 UTF-16 units in JavaScript, 1020 bytes in UTF-8). Expected: kept; 256 refused. Tests: Task 2 "names count code points, not bytes", "a name of 256 code points is refused".
5. **A shelf written by a newer app, or cleaned twice:** unknown fields and a different `version`. Expected: the unknown fields are dropped and not written back; cleaning a clean shelf changes nothing. Tests: Task 2 "unknown fields go…" and the fuzz's idempotence check.

---

## File Structure

| Path | Responsibility |
|---|---|
| `tests/fixtures/shelf/reference.py` | The contract's tie-breaker: `zone_at`, `shelf_clean` (with `item_clean` and `tidy`), `shelf_add`, the replay of both fixtures and a seeded fuzz. Grown a rule per task. |
| `tests/fixtures/shelf/build_cases.py` | Writes `zone-cases.json` and `shelf-cases.json`; `--check` fails on drift. Grown a rule per task. |
| `tests/fixtures/shelf/zone-cases.json` | 25 rows (generated, about 2 KB). |
| `tests/fixtures/shelf/shelf-cases.json` | The constants, 97 `cleanCases` and 19 `addCases` (generated, about 124 KB: the limit cases are written out in full). |
| `scripts/test-shelf-contract.sh` | Runs the reference and the no-drift check. CI runs it. |
| `.github/workflows/build.yml` | One step after "Cat contract". |
| `docs/SHELF-CONTRACT.md` | The document the app plans cite: the rules, the files, the decisions. |
| `CLAUDE.md`, `ARCHITECT.md` | One bullet each. |
| `docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md` | Its G1-0 table says what the files hold (two rows changed, one added). |

The "prove it bites" steps (Tasks 1 to 3) are one-offs and are never committed. **CI needs no other change:** the Windows tests workflow gets `tests/fixtures/shelf/**` in its path filter in the G1-tauri plan, which is the plan that adds a TypeScript replay.

**Order of tasks:**

1. `zoneAt`: the zone fixture, the reference's skeleton and the test script
2. `shelfClean`: the clean-up of `shelf.json`
3. `shelfAdd`: the Shelf drop
4. Owner checkpoint: the rules and the open questions
5. Docs, CI and the final checks

## Tasks and agents

CLAUDE.md: the lightest model that fits. Every task gives all its code and docs, so all five are transcription: `nm-implementer-light` (Haiku 5.5, medium). Each task is then reviewed by `nm-reviewer` (Haiku 5.5, high); the whole branch by `nm-reviewer-deep` (Sonnet 5.5, high, trigger 4) after Task 5. If a step's expected output differs and the cause is not obvious, hand that task to `nm-implementer-deep` (trigger 2) and say so in the ledger.

| Task | Deliverable | Agent | Review |
|---|---|---|---|
| 1. `zoneAt` | `build_cases.py` (zones), `zone-cases.json` (25 rows), `reference.py` (skeleton and `zone_at`), `test-shelf-contract.sh` | `nm-implementer-light` | `nm-reviewer` |
| 2. `shelfClean` | the clean-up rule, the clean cases, the 3000-case fuzz | `nm-implementer-light` | `nm-reviewer` |
| 3. `shelfAdd` | the add rule, the add cases, the 1500-drop property test | `nm-implementer-light` | `nm-reviewer` |
| 4. Owner checkpoint | a printed table of the rules and the open questions, and a stop | `nm-implementer-light` | the owner |
| 5. Docs, CI, final checks | `SHELF-CONTRACT.md`, the CI step, three pointers, the spec's table, every check | `nm-implementer-light` | `nm-reviewer` |
| After Task 5 | The whole branch: the rules against the spec, hostile inputs, what a port could read two ways | `nm-reviewer-deep` | n/a |

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`).

## Execution

One worktree chat session runs the whole plan: branch `g1-0/shelf-contract`, model **Haiku 5.5 at medium effort** (CLAUDE.md: a plan whose tasks are given in full: contracts, fixtures, docs). It is not trigger 5: there is no platform API, no concurrency and no cross-task interface beyond three function names. Nothing is pushed.

**Before the session starts,** the plan file is committed to `notchmeow/rebrand` (a docs-only commit): the controller does this, with the owner's OK, so the branch the session starts from already holds the plan it runs. **The base is `5f9051c` or later:** `git merge-base --is-ancestor 5f9051c HEAD` must succeed.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up (it carries the owner's advance approval of the brief in step 3):

   > Run `git switch -c g1-0/shelf-contract notchmeow/rebrand`, then `git merge-base --is-ancestor 5f9051c HEAD` and `git ls-files docs/superpowers/plans/2026-10-14-g1-0-shelf-contract.md`: the first must succeed and the second must print the plan's path. If either fails, say so and stop. Read `CLAUDE.md`, `ARCHITECT.md`, `docs/superpowers/plans/2026-10-14-g1-0-shelf-contract.md` and `docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md`. Reply "ready" and stop. Do not start any task. The owner approves in advance the controller brief the main session will send as your next message.

2. **Model.** Once the owner starts the chip, the main session sets that session to Haiku 5.5 at medium effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message.

**Controller brief** (what the main session sends once the model is set):

> Run `docs/superpowers/plans/2026-10-14-g1-0-shelf-contract.md` with `superpowers:subagent-driven-development`, task by task, on branch `g1-0/shelf-contract`. Dispatch each task to the agent the plan's "Tasks and agents" table names (Haiku 5.5 first: `nm-implementer-light`, `nm-implementer`, `nm-reviewer`; Sonnet 5.5 only for a task Haiku failed twice, or the final whole-branch review, and then the CLAUDE.md trigger goes in the ledger), then to `nm-reviewer`; fix what the review finds before the next task. Rules for you and for every subagent (put the plan's SUBAGENT RULES block in every brief):
>
> - **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder, the second `g1-0/shelf-contract`. If either is wrong, stop and report. Commit with `git commit -F <file>`, with the trailer of the model that did the task. **Never push.** Commit once per task, in the task's commit step, with only the files that step names.
> - **Ledger.** Keep a manual ledger at `.superpowers/sdd/2026-10-14-g1-0-shelf-contract/progress.md`: one line per task with its agent, model, commit hash, test lines and review verdict, and any escalation with its trigger. The SDD skill's plugin scripts may be refused by the auto-mode permission check: if so, do not call them; write each task brief with the Write tool just before you dispatch it, and each review's diff with `git diff` to a file under the ledger folder.
> - **Briefs are task-sized.** A brief carries one task: its text, the Global Constraints, the SUBAGENT RULES and the files it names. Never hand a subagent the whole plan.
> - **Reviews** read `git diff notchmeow/rebrand...HEAD` (three dots), narrowed to the task's files.
> - **Every shell block passes `bash -n`** before it is run.
> - **Stop after Task 4:** report the printed rule table and the open questions to the main session and wait for its go (the owner approves the rules at this checkpoint; their answers may change a rule, which is one edit in `reference.py` and `build_cases.py` and a regenerate, made before Task 5 documents it). Then run Task 5 and dispatch `nm-reviewer-deep` over the whole branch.
> - **Servers and processes.** None are needed. Never launch a NotchMeow app. Install and download nothing.
> - **Stop and report on any refusal** (a denied command, a permission prompt) and **on any `find` text that is not found exactly once:** do not look for a workaround.
> - **Ping the main session.** Its name in `ListAgents` is `NotchMeow — fork research & cat design`: call `ListAgents` first and use the name (and the `[ref]` it shows, if it asks for one) as `to` in `SendMessage`. At the owner checkpoint (Task 4), at the end, and whenever you stop (a refusal, a failed check, a question), send your report with `SendMessage` as well as writing it in your own chat, so the main session can double-check the work before anything reaches the owner.
> - **When you are done, report:** the commits; the output of `bash scripts/test-shelf-contract.sh`; the `# tests` line of `bash scripts/test-cat-contract.sh`; the output of `node scripts/check-fixtures-additive.mjs 5f9051c`; and anything you could not settle.

## Interface for the app plans

What the Mac (G1-mac) and Windows/Linux (G1-tauri) plans consume. The names below are the rules' names in this contract; each app ports them natively (Swift: a pure `ShelfRules`-style file with no AppKit; TypeScript: a module in `windows/src/`; Rust: the same clean-up for the file on disk, as `cat_settings.rs` does for the Cat settings) and replays `tests/fixtures/shelf/*.json`. `docs/SHELF-CONTRACT.md` (Task 5) has the full text; this is the summary.

| Rule | Signature | Answer |
|---|---|---|
| `zoneAt(x, width)` | numbers in points | `"ask"`, `"shelf"` or `null` |
| `shelfClean(raw)` | the parsed JSON of `shelf.json`, anything | the list of items, never raises |
| `shelfAdd(items, incoming)` | the shelf, and the items for one drop | `{items, results}`, `results[i]` is `"added"`, `"duplicate"`, `"full"` or `"invalid"` |

- **Item:** `{id, name, size, folder, copy, link?, addedAt}`, keys written in that order, `link` absent when `copy` is true.
- **The constants** (`max` 30, `idPattern`, `nameMax` 255, `linkMax` 8192, `numberMax` 9007199254740991) are in `shelf-cases.json`; an app compares its own with them.
- **What an app adds to the rule:** it resolves a bookmark or checks that a path is absolute and exists (this contract is structural only), it supplies `addedAt` from its clock when it builds `incoming`, it applies the platform's file-name rules (Windows' reserved names, a trailing dot) when it creates the folder of a copy, and it shows the short note when any result is `full`. A JSON number that is `NaN`, `Infinity` or beyond 2^53 is a port-side test (JSON cannot hold one).
- **Strings are counted in code points** (`Array.from(s).length` in JavaScript, `unicodeScalars.count` in Swift, `chars().count()` in Rust). An id is matched against the whole string (`^…$` in JavaScript and Swift is not enough if it lets a trailing newline through: use `\z`, or test the length first).
- **Not in this contract:** the drag itself, the bookmark round trip, the copy's folder, the thumbnails, Send, the badge. They are the app plans'.

---

### Task 1: `zoneAt`: the zone fixture, the reference's skeleton and the test script

**Files:**
- Create: `tests/fixtures/shelf/build_cases.py`, `tests/fixtures/shelf/zone-cases.json` (generated), `tests/fixtures/shelf/reference.py`, `scripts/test-shelf-contract.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `zone_at(x, width)` in `reference.py`; `zone-cases.json` (`version`, `cases[]` of `{name, x?, width?, out}`); the two markers `# @@RULES` and `# @@CHECKS` in `reference.py` and `# @@BUILDERS` in `build_cases.py`, which Tasks 2 and 3 fill; `scripts/test-shelf-contract.sh`.

- [ ] **Step 1: Write the fixture builder and generate the zone cases**

The expected answers are typed here, not computed by the reference.

```bash
mkdir -p tests/fixtures/shelf
cat > tests/fixtures/shelf/build_cases.py <<'EOF'
#!/usr/bin/env python3
"""Writes shelf-cases.json and zone-cases.json (standard library only).

The expected answers are written out here by hand and never computed by reference.py, so the
fixtures and the reference check each other. Run it after an intended change to a rule:
    python3 tests/fixtures/shelf/build_cases.py          # rewrite the two files
    python3 tests/fixtures/shelf/build_cases.py --check  # exit 1 if they drifted from this script
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def zones():
    cases = []

    def z(name, x, width, out):
        c = {"name": name}
        if x is not None:
            c["x"] = x
        if width is not None:
            c["width"] = width
        c["out"] = out
        cases.append(c)

    z("left edge is Ask", 0, 600, "ask")
    z("well inside the left half", 120, 600, "ask")
    z("just left of the centre line", 299.5, 600, "ask")
    z("the centre line is Ask, as today", 300, 600, "ask")
    z("just right of the centre line", 300.5, 600, "shelf")
    z("well inside the right half", 480, 600, "shelf")
    z("right edge is Shelf", 600, 600, "shelf")
    z("just outside on the left", -0.5, 600, None)
    z("far outside on the left", -4000, 600, None)
    z("just outside on the right", 600.5, 600, None)
    z("far outside on the right", 1e9, 600, None)
    z("an odd width has an exact centre", 150.5, 301, "ask")
    z("an odd width, just right of it", 150.75, 301, "shelf")
    z("a narrow island", 10, 20, "ask")
    z("a narrow island, right half", 11, 20, "shelf")
    z("fractional pointer inside", 0.001, 600, "ask")
    z("a zero width has no halves", 0, 0, None)
    z("a negative width has no halves", 5, -600, None)
    z("x is text", "300", 600, None)
    z("width is text", 300, "600", None)
    z("x is null", None, 600, None)
    z("width is missing", 300, None, None)
    z("x is true", True, 600, None)
    z("width is true", 0, True, None)
    z("x is a list", [300], 600, None)
    return {"version": 1, "cases": cases}


# @@BUILDERS
def render(obj):
    """One case per line: easy to read and to diff. Floats like 5.0 stay 5.0."""
    out = []
    for k, v in obj.items():
        if isinstance(v, list):
            out.append('  "%s": [\n    %s\n  ]' % (k, ",\n    ".join(json.dumps(x, ensure_ascii=False) for x in v)))
        else:
            out.append('  "%s": %s' % (k, json.dumps(v, ensure_ascii=False)))
    return "{\n" + ",\n".join(out) + "\n}\n"


FILES = {"zone-cases.json": zones}


def main():
    check = "--check" in sys.argv
    bad = 0
    for name, build in FILES.items():
        text = render(build())
        path = os.path.join(HERE, name)
        if check:
            have = open(path, encoding="utf-8").read() if os.path.exists(path) else None
            if have != text:
                print(f"✗ {name} drifted from build_cases.py")
                bad = 1
            else:
                print(f"✓ {name} matches build_cases.py")
        else:
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
            print(f"wrote {name} ({len(text)} bytes)")
    return bad


if __name__ == "__main__":
    sys.exit(main())
EOF
python3 tests/fixtures/shelf/build_cases.py
python3 -c "import json; d = json.load(open('tests/fixtures/shelf/zone-cases.json')); print(d['version'], len(d['cases']))"
```

Expected: `wrote zone-cases.json (1965 bytes)` and `1 25`.

- [ ] **Step 2: Write the reference with `zone_at` still a stub**

```bash
cat > tests/fixtures/shelf/reference.py <<'EOF'
#!/usr/bin/env python3
"""Reference implementation of NotchMeow's shelf contract (sub-project G1).

Three rules, all pure: zone_at (which half of the open island a pointer is in),
shelf_clean (how shelf.json is read) and shelf_add (what happens when files are
dropped on the Shelf half). Runs every fixture in tests/fixtures/shelf/ against them,
then a few self-checks and a seeded fuzz. Standard library only; exit status 1 if
anything fails. Both apps implement the same rules natively; this file is the
tie-breaker when they disagree.
"""
import json
import os
import random
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FAILURES = 0


def zone_at(x, width):
    """'ask' (left half, the centre line included), 'shelf' (right half) or None (outside the island or not numbers)."""
    return None  # stub: Task 1, step 4 writes the rule


# @@RULES


def load(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return json.load(f)


def check(label, got, expected):
    global FAILURES
    if got == expected:
        print(f"  ✓ {label}")
    else:
        print(f"  ✗ {label}\n    got:      {str(got)[:400]}\n    expected: {str(expected)[:400]}")
        FAILURES += 1


def check_zones():
    print("zone-cases.json")
    z = load("zone-cases.json")
    for c in z["cases"]:
        got = zone_at(c.get("x"), c.get("width"))
        check(c["name"], got, c["out"])


# @@CHECKS


def main():
    check_zones()
    print(f"\n{'FAILED: ' + str(FAILURES) if FAILURES else 'all shelf contract checks passed'}")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
EOF
python3 tests/fixtures/shelf/reference.py > "${TMPDIR:-/tmp}/g10-zone-red.txt"; echo "exit $?"
grep -c '✗' "${TMPDIR:-/tmp}/g10-zone-red.txt"; tail -1 "${TMPDIR:-/tmp}/g10-zone-red.txt"
```

Expected: `exit 1`, a count of `✗` of `12` (the stub answers `null`, which is right for the 13 rows that expect `null` and wrong for the 12 others) and the last line `FAILED: 12`.

- [ ] **Step 3: Write the rule**

```bash
python3 - <<'PY'
# Task 1, step 3: replace the stub by the rule. The find text must be there exactly once.
p = 'tests/fixtures/shelf/reference.py'
s = open(p, encoding='utf-8').read()
was = "    return None  # stub: Task 1, step 4 writes the rule\n"
assert s.count(was) == 1, 'stub not found exactly once'
s = s.replace(was, r'''    for v in (x, width):
        if isinstance(v, bool) or not isinstance(v, (int, float)) or v != v or v in (float("inf"), float("-inf")):
            return None
    if width <= 0 or x < 0 or x > width:
        return None
    return "ask" if x <= width / 2 else "shelf"
''')
open(p, 'w', encoding='utf-8').write(s)
PY
python3 tests/fixtures/shelf/reference.py | tail -3
```

Expected: the heading `zone-cases.json`, 25 `✓` lines, a blank line and `all shelf contract checks passed`.

- [ ] **Step 4: Prove it bites (a one-off, never committed)**

```bash
cd tests/fixtures/shelf
for m in 's/x <= width \/ 2/x < width \/ 2/' 's/x < 0 or x > width/x < 0 or x >= width/' 's/width <= 0 or //'; do
  sed "$m" reference.py > g10-mutant.py
  cmp -s reference.py g10-mutant.py && echo "NOCHANGE: $m"
  python3 g10-mutant.py | tail -1
done
trash g10-mutant.py
cd ../../..
git status --short
```

Expected: no `NOCHANGE` line and three lines `FAILED: 3`, `FAILED: 1` and `FAILED: 1` (every mutation is caught: the centre line, the right edge, a zero width); the status shows only the new `tests/fixtures/shelf/` folder and the script is not there yet.

- [ ] **Step 5: Write the test script and run it**

```bash
cat > scripts/test-shelf-contract.sh <<'EOF'
#!/usr/bin/env bash
# Runs the shelf contract (sub-project G1): the fixtures in tests/fixtures/shelf/ against the Python reference,
# and a no-drift check of the two JSON files against the script that writes them.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/fixtures/shelf/reference.py
python3 tests/fixtures/shelf/build_cases.py --check
EOF
chmod +x scripts/test-shelf-contract.sh
bash -n scripts/test-shelf-contract.sh && bash scripts/test-shelf-contract.sh | tail -4
```

Expected: `all shelf contract checks passed`, `✓ zone-cases.json matches build_cases.py`.

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add tests/fixtures/shelf/build_cases.py tests/fixtures/shelf/zone-cases.json tests/fixtures/shelf/reference.py scripts/test-shelf-contract.sh
cat > "${TMPDIR:-/tmp}/g10-msg1.txt" <<'EOF'
test(shelf): the zone rule, its fixture and the reference's skeleton (G1-0)

zoneAt(x, width): Ask on the left half and on the centre line, Shelf on
the right half, nothing outside the island or for input that is not
numbers. 25 hand-written rows, a Python reference and a test script.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -q -F "${TMPDIR:-/tmp}/g10-msg1.txt" && git log --oneline -1 && git show --stat --format= HEAD
```

Expected: the four files listed.

---

### Task 2: `shelfClean`: the clean-up of `shelf.json`

**Files:**
- Modify: `tests/fixtures/shelf/build_cases.py` (the clean cases above `# @@BUILDERS`), `tests/fixtures/shelf/reference.py` (the rule above `# @@RULES`'s marker, the checks above `# @@CHECKS`, two calls in `main`)
- Create: `tests/fixtures/shelf/shelf-cases.json` (generated)

**Interfaces:**
- Consumes: Task 1's markers, `load`, `check`, `FAILURES`.
- Produces: `item_clean(raw)`, `tidy(items)`, `shelf_clean(raw)`, the constants `SHELF_MAX`, `ID_RE`, `NAME_MAX`, `LINK_MAX`, `NUMBER_MAX`, the helpers `has_control` and `whole`; `shelf-cases.json` with `max`, `idPattern`, `nameMax`, `linkMax`, `numberMax`, `cleanCases` and an empty `addCases`; the markers `# @@ADD-RULE` (reference) and `# @@ADD-CASES` (builder), which Task 3 fills.

- [ ] **Step 1: Write the clean cases**

The helpers `it()` (a clean item) and `dirty()` (a raw item with chosen faults) and the cases are typed here with their expected answers. The fixture also holds the constants, so an app can compare its own.

```bash
python3 - <<'PY'
# Task 2, step 1: the clean cases. Run from the repository root. The find text must be there exactly once.
p = 'tests/fixtures/shelf/build_cases.py'
s = open(p, encoding='utf-8').read()
was = "# @@BUILDERS\n"
assert s.count(was) == 1, 'marker not found exactly once'
s = s.replace(was, r'''MAX = 2**53 - 1


def it(i, name="f.txt", link=None, size=1, folder=False, copy=False, at=1):
    """A clean item, in the order the contract writes its keys."""
    d = {"id": i, "name": name, "size": size, "folder": folder, "copy": copy}
    if not copy:
        d["link"] = link if link is not None else "/p/" + i
    d["addedAt"] = at
    return d


def dirty(i, **kw):
    """A raw item: the clean one plus whatever the case sets (use None to delete a key)."""
    d = it(i)
    for k, v in kw.items():
        if v is None:
            d.pop(k, None)
        else:
            d[k] = v
    return d


def shelf(raw_items):
    return {"version": 1, "items": raw_items}


def shelf_cases():
    clean, add = [], []

    def c(name, raw, out):
        clean.append({"name": name, "raw": raw, "out": out})

    a, b, d = it("a", at=3), it("b", at=2), it("c", at=1)
    c("an empty file", {}, [])
    c("an empty list", shelf([]), [])
    for name, raw in [("null", None), ("a number", 7), ("text", "items"), ("a list", []), ("a bare list of items", [a]),
                      ("items is text", {"items": "x"}), ("items is an object", {"items": {"a": a}}), ("items is null", {"items": None})]:
        c("not a shelf: " + name, raw, [])
    c("one good link", shelf([a]), [a])
    c("three good items stay as they are", shelf([a, b, d]), [a, b, d])
    c("unknown fields go, on the file and on the item", {"version": 9, "extra": 1, "items": [dict(a, bookmark="x", __proto__={"x": 1}, constructor=5)]}, [a])
    c("a copied item carries no link", shelf([dirty("k", copy=True, link="/somewhere")]), [it("k", copy=True)])
    c("a copied item needs no link", shelf([dirty("k", copy=True, link=None)]), [it("k", copy=True)])
    c("a folder is a link", shelf([dirty("f", folder=True)]), [it("f", folder=True)])
    c("a copied folder is refused", shelf([dirty("f", folder=True, copy=True)]), [])
    c("copy and folder count only as the boolean true", shelf([dirty("g", copy="true", folder=1)]), [it("g")])
    # ids
    for bad in ["", "../x", "a/b", "a b", "a.b", "a\n", "\nA", "é", "z" * 65, 7, None, ["a"], {"x": 1}]:
        c("hostile id " + json.dumps(bad), shelf([dirty("x", id=bad)]), [])
    c("an id of 64 characters is fine", shelf([dirty("y" * 64, link="/y")]), [it("y" * 64, link="/y")])
    c("ids may hold letters, digits, dash and underscore", shelf([dirty("Aa_0-9")]), [it("Aa_0-9")])
    c("a missing id", shelf([dirty("x", id=None)]), [])
    # names
    for bad in ["", ".", "..", "a/b", "a\\b", "tab\there", "nul\u0000x", "del\u007fx", "c1\u0085x", "n" * 256, 5, None, ["f"]]:
        c("hostile name " + json.dumps(bad), shelf([dirty("x", name=bad)]), [])
    c("a name of 255 characters is fine", shelf([dirty("x", name="n" * 255)]), [it("x", name="n" * 255)])
    c("names count code points, not bytes", shelf([dirty("x", name="😀" * 255)]), [it("x", name="😀" * 255)])
    c("a name of 256 code points is refused", shelf([dirty("x", name="😀" * 256)]), [])
    c("spaces, dots inside and accents are fine", shelf([dirty("x", name=" Rapport été.2026.pdf ")]), [it("x", name=" Rapport été.2026.pdf ")])
    c("a name that only looks like a dot is a name", shelf([dirty("x", name="...")]), [it("x", name="...")])
    # links
    for bad in ["", "a\u0000b", "a\nb", "a\u007fb", "r" * 8193, 5, None, ["/p"], True]:
        c("hostile link " + json.dumps(bad)[:40], shelf([dirty("x", link=bad)]), [])
    c("a missing link on a link item", shelf([dirty("x", link=None)]), [])
    c("a link of 8192 characters is fine", shelf([dirty("x", link="r" * 8192)]), [it("x", link="r" * 8192)])
    c("a Windows path and a bookmark are only strings", shelf([dirty("w", link="C:\\Users\\Zoé\\a b.pdf"), dirty("m", link="Ym9va21hcmtkYXRh+/==")]),
      [it("w", link="C:\\Users\\Zoé\\a b.pdf"), it("m", link="Ym9va21hcmtkYXRh+/==")])
    # size and addedAt
    for bad in [-1, 1.5, "7", None, True, [3], MAX + 1, 1e300, 2**70]:
        c("size " + json.dumps(bad) + " becomes 0", shelf([dirty("x", size=bad)]), [it("x", size=0)])
    c("size 5.0 is the number 5", shelf([dirty("x", size=5.0)]), [it("x", size=5)])
    c("the largest exact size is kept", shelf([dirty("x", size=MAX)]), [it("x", size=MAX)])
    c("size 0 is fine", shelf([dirty("x", size=0)]), [it("x", size=0)])
    c("a missing size is 0", shelf([dirty("x", size=None)]), [it("x", size=0)])
    for bad in [-1, 0.5, "9", None, True, MAX + 1]:
        c("addedAt " + json.dumps(bad) + " becomes 0", shelf([dirty("x", at=None, addedAt=bad)]), [it("x", at=0)])
    # order
    c("newest first, whatever the file's order", shelf([d, a, b]), [a, b, d])
    c("equal times keep the file's order", shelf([it("p", at=5), it("q", at=5), it("r", at=5)]), [it("p", at=5), it("q", at=5), it("r", at=5)])
    c("items without a time sink to the end, in file order", shelf([dirty("n1", addedAt=None), it("t", at=2), dirty("n2", addedAt="x")]),
      [it("t", at=2), it("n1", at=0), it("n2", at=0)])
    # duplicates
    c("the same id twice: the newer stays", shelf([it("a", link="/old", at=1), it("a", link="/new", at=9)]), [it("a", link="/new", at=9)])
    c("the same id twice at the same time: the first in the file stays", shelf([it("a", link="/one", at=4), it("a", link="/two", at=4)]), [it("a", link="/one", at=4)])
    c("the same file twice under two ids: the newer stays", shelf([it("a", link="/same", at=1), it("b", link="/same", at=2)]), [it("b", link="/same", at=2)])
    c("links compare exactly, case and all", shelf([it("a", link="/Same", at=2), it("b", link="/same", at=1)]), [it("a", link="/Same", at=2), it("b", link="/same", at=1)])
    c("a copy never clashes with a link", shelf([it("a", copy=True, at=2), it("b", link="/a", at=1)]), [it("a", copy=True, at=2), it("b", link="/a", at=1)])
    c("a hostile item does not hide a good duplicate", shelf([dirty("a", name="a/b", at=9), it("a", link="/kept", at=1)]), [it("a", link="/kept", at=1)])
    c("hostile entries between good ones are skipped", shelf([a, None, 5, "x", [], {"id": "q"}, b]), [a, b])
    # the cap
    many = [it("i%02d" % n, at=100 - n) for n in range(45)]
    c("a hostile file with 45 items keeps the 30 newest", shelf(many), many[:30])
    shuffled = many[::-1]
    c("the cap keeps the newest whatever the order", shelf(shuffled), many[:30])
    c("exactly 30 items stay", shelf(many[:30]), many[:30])
    c("a duplicate does not use a place", shelf(many[:29] + [dict(many[0], addedAt=1)]), many[:29])

    # @@ADD-CASES

    return {"version": 1, "max": 30, "idPattern": "[A-Za-z0-9_-]{1,64}", "nameMax": 255, "linkMax": 8192, "numberMax": MAX,
            "cleanCases": clean, "addCases": add}


# @@BUILDERS
''')
was = 'FILES = {"zone-cases.json": zones}'
assert s.count(was) == 1
s = s.replace(was, 'FILES = {"shelf-cases.json": shelf_cases, "zone-cases.json": zones}')
open(p, 'w', encoding='utf-8').write(s)
PY
python3 tests/fixtures/shelf/build_cases.py
python3 -c "import json; d = json.load(open('tests/fixtures/shelf/shelf-cases.json')); print(len(d['cleanCases']), len(d['addCases']))"
```

Expected: `wrote shelf-cases.json (80536 bytes)`, `wrote zone-cases.json (1965 bytes)` and `97 0`.

- [ ] **Step 2: Add the checks to the reference, and see them fail**

```bash
python3 - <<'PY'
# Task 2, step 2: the replay and the fuzz, calling a rule that does not exist yet.
p = 'tests/fixtures/shelf/reference.py'
s = open(p, encoding='utf-8').read()
was = "# @@CHECKS\n\n\n"
assert s.count(was) == 1, 'checks marker not found exactly once'
s = s.replace(was, r'''def check_shelf():
    print("shelf-cases.json")
    s = load("shelf-cases.json")
    check("constants", (s["max"], s["idPattern"], s["nameMax"], s["linkMax"], s["numberMax"]),
          (SHELF_MAX, ID_RE.pattern, NAME_MAX, LINK_MAX, NUMBER_MAX))
    for c in s["cleanCases"]:
        check("clean: " + c["name"], shelf_clean(c["raw"]), c["out"])


def check_properties():
    print("properties")
    rnd = random.Random(7)
    words = ["a", "b", "c", "/x", "..", ".", "", "x" * 300, "n\n", "ok", "é", "😀", "a/b", "a\\b"]

    def junk():
        kind = rnd.randrange(8)
        if kind == 0:
            return rnd.choice([None, True, 7, -1, 2.5, 1e300, "text", [], {}])
        return {"id": rnd.choice(["a1", "b2", "c3", "d4", "../x", "", "a b", "z" * 65, "a\n"]),
                "name": rnd.choice(words), "size": rnd.choice([0, 5, -1, 2.5, "7", None, 2**60]),
                "folder": rnd.choice([True, False, 1, "true"]), "copy": rnd.choice([True, False, 0, None]),
                "link": rnd.choice(["/p", "/q", "", "a\x00b", None, 5, "r" * 9000, "/p"]),
                "addedAt": rnd.choice([1, 2, 3, 3, -1, "x", None, 2.0, 1e30]), "extra": {"__proto__": 1}}

    ok, last = True, None
    for _ in range(3000):
        raw = {"items": [junk() for _ in range(rnd.randrange(0, 40))]}
        try:
            out = shelf_clean(raw)
            again = shelf_clean({"items": out})
        except Exception as e:                     # noqa: BLE001 - the point is that nothing raises
            ok, last = False, repr(e)
            break
        ids = [it["id"] for it in out]
        links = [it["link"] for it in out if "link" in it]
        if (again != out or len(out) > SHELF_MAX or len(set(ids)) != len(ids) or len(set(links)) != len(links)
                or any(a["addedAt"] < b["addedAt"] for a, b in zip(out, out[1:]))):
            ok, last = False, raw
            break
    check("3000 hostile shelves: never raises, clean twice is clean once, no duplicates, newest first, at most 30", ok, True)
    if not ok:
        print("    first failure:", last)


''')
was = "    check_zones()\n"
assert s.count(was) == 1
s = s.replace(was, "    check_zones()\n    check_shelf()\n    check_properties()\n")
open(p, 'w', encoding='utf-8').write(s)
PY
python3 tests/fixtures/shelf/reference.py 2>&1 | tail -2
```

Expected: a traceback ending `NameError: name 'SHELF_MAX' is not defined` (the rule is not written yet).

- [ ] **Step 3: Write the rule**

```bash
python3 - <<'PY'
# Task 2, step 3: the constants, the helpers and the three functions.
p = 'tests/fixtures/shelf/reference.py'
s = open(p, encoding='utf-8').read()
was = "# @@RULES\n\n\n"
assert s.count(was) == 1, 'rules marker not found exactly once'
s = s.replace(was, r'''SHELF_MAX = 30                      # items on the shelf
ID_RE = re.compile(r"[A-Za-z0-9_-]{1,64}")   # matched against the WHOLE string
NAME_MAX = 255                      # code points
LINK_MAX = 8192                     # code points
NUMBER_MAX = 2**53 - 1              # largest size / addedAt (every language holds it exactly)


def has_control(s):
    """True for a C0 control, DEL or a C1 control (U+0000-001F, U+007F-009F)."""
    return any(ord(c) < 0x20 or 0x7F <= ord(c) <= 0x9F for c in s)


def whole(v):
    """A whole number from 0 to NUMBER_MAX (5 and 5.0 are the same JSON number to JavaScript), else 0."""
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return 0
    if isinstance(v, float) and (v != v or v in (float("inf"), float("-inf")) or not v.is_integer()):
        return 0
    n = int(v)
    return n if 0 <= n <= NUMBER_MAX else 0


def item_clean(raw):
    """One stored item to its clean form, or None when it cannot be kept."""
    if not isinstance(raw, dict):
        return None
    i, name = raw.get("id"), raw.get("name")
    if not isinstance(i, str) or not ID_RE.fullmatch(i):
        return None
    if (not isinstance(name, str) or not 1 <= len(name) <= NAME_MAX or has_control(name)
            or "/" in name or "\\" in name or name in (".", "..")):
        return None
    copy, folder = raw.get("copy") is True, raw.get("folder") is True
    if copy and folder:
        return None                 # a folder is only ever a link
    out = {"id": i, "name": name, "size": whole(raw.get("size")), "folder": folder, "copy": copy}
    if not copy:
        link = raw.get("link")
        if not isinstance(link, str) or not 1 <= len(link) <= LINK_MAX or has_control(link):
            return None
        out["link"] = link
    out["addedAt"] = whole(raw.get("addedAt"))
    return out


def tidy(items):
    """Newest first (stable), then the first of each id and of each link, then the first SHELF_MAX."""
    items = sorted(items, key=lambda it: -it["addedAt"])
    seen_id, seen_link, out = set(), set(), []
    for it in items:
        if it["id"] in seen_id or ("link" in it and it["link"] in seen_link):
            continue
        seen_id.add(it["id"])
        if "link" in it:
            seen_link.add(it["link"])
        out.append(it)
    return out[:SHELF_MAX]


def shelf_clean(raw):
    """The parsed content of shelf.json to the list of items the shelf holds. Never raises."""
    if not isinstance(raw, dict) or not isinstance(raw.get("items"), list):
        return []
    return tidy([c for c in (item_clean(r) for r in raw["items"]) if c is not None])


# @@ADD-RULE


''')
open(p, 'w', encoding='utf-8').write(s)
PY
python3 tests/fixtures/shelf/reference.py | grep -v '✓'
```

Expected: the headings `zone-cases.json`, `shelf-cases.json`, `properties` and the last line `all shelf contract checks passed` (no `✗`).

- [ ] **Step 4: Prove it bites (a one-off, never committed)**

```bash
cd tests/fixtures/shelf
for m in 's/ID_RE.fullmatch(i)/ID_RE.match(i)/' 's/^SHELF_MAX = 30 /SHELF_MAX = 31 /' 's/key=lambda it: -it\["addedAt"\]/key=lambda it: 0/' 's/ or ("link" in it and it\["link"\] in seen_link)//' 's/ or "\/" in name or "\\\\" in name//' 's/if copy and folder:/if False:/' 's/return n if 0 <= n <= NUMBER_MAX else 0/return n if 0 <= n else 0/' 's/or has_control(link)//'; do
  sed "$m" reference.py > g10-mutant.py
  cmp -s reference.py g10-mutant.py && echo "NOCHANGE: $m"
  python3 g10-mutant.py | tail -1
done
trash g10-mutant.py
cd ../../..
```

Expected: no `NOCHANGE` line, and eight lines each starting `FAILED:` (here 5, 3, 6, 2, 3, 1, 4 and 3 failures) (a wrong fullmatch, a cap of 31, no sort, no link de-duplication, path separators allowed, a copied folder, a size beyond 2^53, a link with control characters). If a mutation prints `all shelf contract checks passed`, a case is missing: stop and report.

- [ ] **Step 5: Run the whole script**

```bash
bash scripts/test-shelf-contract.sh | tail -4
```

Expected: `all shelf contract checks passed`, `✓ shelf-cases.json matches build_cases.py`, `✓ zone-cases.json matches build_cases.py`.

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add tests/fixtures/shelf/build_cases.py tests/fixtures/shelf/shelf-cases.json tests/fixtures/shelf/reference.py
cat > "${TMPDIR:-/tmp}/g10-msg2.txt" <<'EOF'
test(shelf): shelfClean, how shelf.json is read (G1-0)

Item fields, hostile ids, names and links, sizes, duplicates by id and by
link, newest first and the 30-item cap, with 97 hand-written cases, a
3000-shelf fuzz and eight mutations the cases catch.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -q -F "${TMPDIR:-/tmp}/g10-msg2.txt" && git log --oneline -1 && git show --stat --format= HEAD
```

Expected: the three files listed.

---

### Task 3: `shelfAdd`: the Shelf drop

**Files:**
- Modify: `tests/fixtures/shelf/build_cases.py` (the add cases at `# @@ADD-CASES`), `tests/fixtures/shelf/reference.py` (the rule at `# @@ADD-RULE`, the replay and the property test)
- Modify (regenerated): `tests/fixtures/shelf/shelf-cases.json`

**Interfaces:**
- Consumes: Task 2's `item_clean`, `tidy`, `shelf_clean`, `SHELF_MAX`, the markers.
- Produces: `shelf_add(items, incoming)` returning `{items, results}`; `addCases` in `shelf-cases.json` (19 rows).

- [ ] **Step 1: Write the add cases**

```bash
python3 - <<'PY'
# Task 3, step 1: the add cases. The find text must be there exactly once.
p = 'tests/fixtures/shelf/build_cases.py'
s = open(p, encoding='utf-8').read()
was = "    # @@ADD-CASES\n"
assert s.count(was) == 1, 'marker not found exactly once'
s = s.replace(was, r'''    # ---- adding (the Shelf half of a drop)
    def ad(name, items, incoming, out_items, results):
        add.append({"name": name, "items": items, "incoming": incoming, "out": {"items": out_items, "results": results}})

    base = [it("a", at=30), it("b", at=20)]
    n1, n2, n3 = it("n1", at=300), it("n2", at=300), it("n3", at=300)
    ad("into an empty shelf", [], [n1, n2], [n1, n2], ["added", "added"])
    ad("the new ones go first, in the order given", base, [n1, n2], [n1, n2] + base, ["added", "added"])
    ad("nothing dropped", base, [], base, [])
    ad("incoming is not a list", base, None, base, [])
    ad("a file already on the shelf is a duplicate", base, [it("zz", link="/p/a", at=300)], base, ["duplicate"])
    ad("the same id is a duplicate", base, [it("a", link="/other", at=300)], base, ["duplicate"])
    ad("the same file twice in one drop is added once", base, [n1, it("n9", link="/p/n1", at=300)], [n1] + base, ["added", "duplicate"])
    ad("the same id twice in one drop is added once", base, [n1, dict(n1, link="/p/other")], [n1] + base, ["added", "duplicate"])
    ad("a hostile item is invalid, the rest go on", base, [dirty("bad", name="a/b"), n1, 5, None], [n1] + base, ["invalid", "added", "invalid", "invalid"])
    ad("an item whose link is missing is invalid", base, [dirty("x", link=None)], base, ["invalid"])
    full = [it("i%02d" % n, at=200 - n) for n in range(30)]
    ad("a full shelf refuses and removes nothing", full, [n1], full, ["full"])
    ad("a full shelf says duplicate for a file it already holds", full, [it("zz", link="/p/i00", at=999)], full, ["duplicate"])
    ad("a full shelf, one invalid and one full", full, [dirty("bad", id="../x"), n1], full, ["invalid", "full"])
    almost = full[:28]
    ad("room for two of three", almost, [n1, n2, n3], [n1, n2] + almost, ["added", "added", "full"])
    ad("room for one, a duplicate does not use it", full[:29], [dirty("zz", link="/p/i00"), n1, n2], [n1] + full[:29], ["duplicate", "added", "full"])
    ad("the shelf given is cleaned first", [dict(base[0], bookmark="x"), 5], [n1], [n1, base[0]], ["added"])
    ad("a copied item is added without a link", base, [dirty("cp", copy=True, link="/dropped", addedAt=300)], [it("cp", copy=True, at=300)] + base, ["added"])
    ad("a copied folder is invalid", base, [dirty("cf", copy=True, folder=True)], base, ["invalid"])
    ad("an older item slots in by time", base, [it("old", at=25)], [base[0], it("old", at=25), base[1]], ["added"])
''')
open(p, 'w', encoding='utf-8').write(s)
PY
python3 tests/fixtures/shelf/build_cases.py
python3 -c "import json; d = json.load(open('tests/fixtures/shelf/shelf-cases.json')); print(len(d['cleanCases']), len(d['addCases']))"
```

Expected: `wrote shelf-cases.json (` with a size near 124000 bytes, and `97 19`.

- [ ] **Step 2: Add the replay and the property test, and see them fail**

```bash
python3 - <<'PY'
# Task 3, step 2: the replay of addCases and the 1500-drop property test.
p = 'tests/fixtures/shelf/reference.py'
s = open(p, encoding='utf-8').read()
was = '        check("clean: " + c["name"], shelf_clean(c["raw"]), c["out"])\n'
assert s.count(was) == 1, 'clean loop not found exactly once'
s = s.replace(was, was + r'''    for c in s["addCases"]:
        check("add: " + c["name"], shelf_add(c["items"], c["incoming"]), c["out"])


''')
was = '        print("    first failure:", last)\n'
assert s.count(was) == 1, 'first-failure line not found exactly once'
s = s.replace(was, was + r'''    # Adding never removes anything and never grows the shelf past the cap.
    ok = True
    for _ in range(1500):
        base = shelf_clean({"items": [junk() for _ in range(rnd.randrange(0, 45))]})
        res = shelf_add(base, [junk() for _ in range(rnd.randrange(0, 12))])
        old = {it["id"] for it in base}
        if (len(res["items"]) > SHELF_MAX or not old <= {it["id"] for it in res["items"]}
                or res["results"].count("added") != len(res["items"]) - len(base)):
            ok = False
            break
    check("1500 drops: nothing already shelved is removed, the cap holds, the added count matches", ok, True)


''')
open(p, 'w', encoding='utf-8').write(s)
PY
python3 tests/fixtures/shelf/reference.py 2>&1 | tail -2
```

Expected: a traceback ending `NameError: name 'shelf_add' is not defined`.

- [ ] **Step 3: Write the rule**

```bash
python3 - <<'PY'
p = 'tests/fixtures/shelf/reference.py'
s = open(p, encoding='utf-8').read()
was = "# @@ADD-RULE\n\n\n"
assert s.count(was) == 1, 'add-rule marker not found exactly once'
s = s.replace(was, r'''def shelf_add(items, incoming):
    """Files dropped on the Shelf half. Returns {items, results}; results has one word per incoming item:
    'added', 'duplicate', 'full' or 'invalid'. Nothing already on the shelf is ever removed."""
    current = shelf_clean({"items": items})
    ids = {it["id"] for it in current}
    links = {it["link"] for it in current if "link" in it}
    accepted, results = [], []
    for raw in incoming if isinstance(incoming, list) else []:
        it = item_clean(raw)
        if it is None:
            results.append("invalid")
        elif it["id"] in ids or ("link" in it and it["link"] in links):
            results.append("duplicate")
        elif len(current) + len(accepted) >= SHELF_MAX:
            results.append("full")
        else:
            accepted.append(it)
            ids.add(it["id"])
            if "link" in it:
                links.add(it["link"])
            results.append("added")
    return {"items": tidy(accepted + current), "results": results}


''')
open(p, 'w', encoding='utf-8').write(s)
PY
python3 tests/fixtures/shelf/reference.py | grep -v '✓'
```

Expected: the four headings and `all shelf contract checks passed`.

- [ ] **Step 4: Prove it bites (a one-off, never committed)**

```bash
cd tests/fixtures/shelf
for m in 's/len(current) + len(accepted) >= SHELF_MAX/len(current) >= SHELF_MAX/' 's/elif it\["id"\] in ids or ("link" in it and it\["link"\] in links):/elif it["id"] in ids:/' 's/return {"items": tidy(accepted + current), "results": results}/return {"items": tidy(accepted + current)[:SHELF_MAX - 1], "results": results}/' 's/^            ids.add(it\["id"\])$/            pass/' 's/results.append("invalid")/results.append("duplicate")/'; do
  sed "$m" reference.py > g10-mutant.py
  cmp -s reference.py g10-mutant.py && echo "NOCHANGE: $m"
  python3 g10-mutant.py | tail -1
done
trash g10-mutant.py
cd ../../..
```

Expected: no `NOCHANGE` line and five lines each starting `FAILED:` (a cap that ignores this drop's own additions, no link de-duplication, a shelf that loses its oldest item, a drop that forgets the ids it has added, the wrong word for a hostile item).

- [ ] **Step 5: Run the whole script**

```bash
bash scripts/test-shelf-contract.sh | tail -4
```

Expected: `all shelf contract checks passed` and the two `✓ … matches build_cases.py` lines.

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add tests/fixtures/shelf/build_cases.py tests/fixtures/shelf/shelf-cases.json tests/fixtures/shelf/reference.py
cat > "${TMPDIR:-/tmp}/g10-msg3.txt" <<'EOF'
test(shelf): shelfAdd, a drop on the Shelf half (G1-0)

added, duplicate, full or invalid for each file; a full shelf refuses and
removes nothing; a re-dropped file says duplicate. 19 hand-written cases,
a 1500-drop property test and five mutations the cases catch.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -q -F "${TMPDIR:-/tmp}/g10-msg3.txt" && git log --oneline -1 && git show --stat --format= HEAD
```

Expected: the three files listed.

---

### Task 4: Owner checkpoint: the rules and the open questions

**Files:**
- Create (outside the repository, never committed): `${TMPDIR:-/tmp}/g10-rules.txt`

**Interfaces:**
- Consumes: Tasks 1 to 3. Produces: a printed table of what the rules do on chosen inputs, and a stop.

Nothing in G1-0 is visible, so the owner's look is a plain read: for each rule, what it answers to a handful of inputs that matter, and the choices the spec left open. The numbers are printed by the reference itself, so the table cannot drift from the code.

- [ ] **Step 1: Print the table**

```bash
python3 -I - <<'PY' | tee "${TMPDIR:-/tmp}/g10-rules.txt"
import sys, importlib.util
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('ref', 'tests/fixtures/shelf/reference.py')
r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
print('zoneAt(x, 600): ' + ', '.join(f'{x} -> {r.zone_at(x, 600)}' for x in (-1, 0, 299, 300, 301, 600, 601)))
def it(i, **kw):
    d = {'id': i, 'name': 'report.pdf', 'size': 10, 'folder': False, 'copy': False, 'link': '/f/' + i, 'addedAt': 1}; d.update(kw); return d
def show(title, raw):
    out = r.shelf_clean({'items': raw})
    print(f'shelfClean {title}: kept {[x["id"] for x in out]}')
show('a good item', [it('a')])
show('an id of ../x, a name of a/b, a NUL in a link', [it('../x'), it('b', name='a/b'), it('c', link='a\x00b'), it('d')])
show('a bad size and a bad time keep the item', [it('e', size=-5, addedAt='yesterday')])
show('the same file under two ids (newer stays)', [it('old', link='/same', addedAt=1), it('new', link='/same', addedAt=2)])
show('a copy that is a folder', [it('f', copy=True, folder=True)])
many = [it('i%02d' % n, addedAt=100 - n) for n in range(45)]
print('shelfClean a file of 45 items keeps', len(r.shelf_clean({'items': many})), 'and the newest is', r.shelf_clean({'items': many})[0]['id'])
full = r.shelf_clean({'items': many[:30]})
res = r.shelf_add(full, [it('new1', addedAt=500), it('zz', link='/f/i00', addedAt=500), it('../x')])
print('shelfAdd on a full shelf [new file, a file already there, a hostile id]:', res['results'], 'items', len(res['items']))
res = r.shelf_add(full[:28], [it('n1', addedAt=500), it('n2', addedAt=500), it('n3', addedAt=500)])
print('shelfAdd with room for two of three:', res['results'], 'first two now on the shelf:', [x['id'] for x in res['items'][:3]])
PY
```

Expected: nine lines: `zoneAt(x, 600): -1 -> None, 0 -> ask, 299 -> ask, 300 -> ask, 301 -> shelf, 600 -> shelf, 601 -> None`; `shelfClean a good item: kept ['a']`; the hostile line keeps only `['d']`; the bad size line keeps `['e']`; the same-file line keeps `['new']`; the copied folder keeps `[]`; `a file of 45 items keeps 30 and the newest is i00`; `shelfAdd on a full shelf [...]: ['full', 'duplicate', 'invalid'] items 30`; and `shelfAdd with room for two of three: ['added', 'added', 'full'] first two now on the shelf: ['n1', 'n2', 'i00']`.

- [ ] **Step 2: Stop and report to the main session**

**Stop here and report to the main session:** the printed table (paste it), the commit hashes of Tasks 1 to 3, and the list under "Open questions for the owner" below, with the answer the plan assumed for each. The main session shows the owner. **Task 5 starts only when the main session says go.** If the owner wants another rule (the centre line to the Shelf half, a bad `size` to drop the item, other limits, a different duplicate rule), the change is one edit in `reference.py` and the same in `build_cases.py`, a regenerate (`python3 tests/fixtures/shelf/build_cases.py`) and a re-run of `bash scripts/test-shelf-contract.sh`, made by the main session or by a fix task, as one more commit, before Task 5 documents it.

---

### Task 5: Docs, CI and the final checks

**Files:**
- Create: `docs/SHELF-CONTRACT.md`
- Modify: `.github/workflows/build.yml`, `CLAUDE.md`, `ARCHITECT.md`, `docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md`

**Interfaces:**
- Consumes: Tasks 1 to 4 and the owner's go. Produces: the document the app plans cite, the CI step and the pointers.

- [ ] **Step 1: Write the contract document**

If the owner's notes at the checkpoint changed a rule, change the same words in the text below before running this.

`````bash
cat > docs/SHELF-CONTRACT.md <<'EOF'
# The shelf contract

Sub-project G1 (`docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md`, "G1-0") parks files in the notch. Three rules are the same on both apps and are written once, here and in `tests/fixtures/shelf/`. The macOS app (Swift) and the Windows/Linux app (TypeScript, with a Rust twin for the file on disk) each reimplement them natively and test themselves against the fixtures, the same way both apps test the AI layer (`tests/fixtures/ai/`).

**`tests/fixtures/shelf/reference.py` is the tie-breaker.** It is a small Python program (standard library only) with the three rules written as plainly as possible. The two JSON files are written by `build_cases.py`, with every expected answer typed out by hand and none computed by the reference, so the fixtures and the reference check each other. If an app and a fixture disagree, the app is wrong.

The look, the drag, the bookmark itself and the share sheet are not tested here. This contract is only the arithmetic and the clean-up that both apps must agree on.

## Run it

```
bash scripts/test-shelf-contract.sh                       # the reference against both fixtures, then the no-drift check
python3 tests/fixtures/shelf/build_cases.py               # rewrite the two JSON files after an intended change
python3 tests/fixtures/shelf/build_cases.py --check
```

Python 3, nothing to install. CI runs the script next to the AI contract. Both app plans add their own replay of the two files (`shelf-cases.json`, `zone-cases.json`) to their tests.

## The files

| File | Pins |
|---|---|
| `zone-cases.json` | `cases[]` of `{name, x?, width?, out}`: `zoneAt(x, width)`. A missing key stands for a value JSON cannot hold; the cases with text, `null` or `true` in its place pin the refusal. `out` is `"ask"`, `"shelf"` or `null`. |
| `shelf-cases.json` | The constants (`max`, `idPattern`, `nameMax`, `linkMax`, `numberMax`), `cleanCases[]` of `{name, raw, out}` (`shelfClean`) and `addCases[]` of `{name, items, incoming, out: {items, results}}` (`shelfAdd`). |
| `reference.py` | The three rules, the replay of both files, and a seeded fuzz (3000 hostile shelves, 1500 drops). |
| `build_cases.py` | Writes the two JSON files (`--check` fails on drift). |

## The rules

### `zoneAt(x, width)`: which half the pointer is in

The pointer's horizontal position `x`, measured from the island's left edge, and the island's `width`, both in points. The island is split at its centre line.

| Input | Answer |
|---|---|
| `0 <= x <= width / 2` | `ask` (the centre line itself is Ask: the drop that exists today) |
| `width / 2 < x <= width` | `shelf` |
| `x < 0` or `x > width` | `null`: outside the island, so no half |
| `width <= 0`, or either is not a finite number (text, `null`, a boolean, a list) | `null` |

On the Mac `x` comes from the drag's own location; on Windows and Linux from the last polled cursor position, because the drop event carries paths only. The vertical position is not part of the rule: each app already knows whether the pointer is over the island.

### `shelfClean(raw)`: how `shelf.json` is read

`shelf.json` is `{"version": 1, "items": [ ... ]}`. An app reads the file as plain JSON values, runs this rule and uses only the result. Anything else (not an object, `items` not a list, text, `null`) is an empty shelf. The file's `version` and any unknown field are ignored and not written back.

One stored item is **dropped** unless all of this holds, and otherwise **cleaned** to exactly these fields, in this order:

| Field | Rule |
|---|---|
| `id` | A string matching `[A-Za-z0-9_-]{1,64}` as a **whole** string (a trailing newline does not match). It is also the name of the item's folder under `shelf/`. |
| `name` | A string of 1 to 255 **code points** (not UTF-16 units, bytes or grapheme clusters), with no control character (U+0000 to U+001F and U+007F to U+009F), no `/` or `\`, and not `.` or `..`. |
| `size` | A whole number from 0 to 9007199254740991 (`5` and `5.0` are the same number). Anything else becomes `0`. It is for display only. |
| `folder` | `true` only for the boolean `true`, else `false`. |
| `copy` | `true` only for the boolean `true`, else `false`. A copy lives in `shelf/<id>/<name>`; it has no `link`. A copy that is also a folder is **dropped** (a folder is only ever a link). |
| `link` | Present only when `copy` is `false`, and then required: a string of 1 to 8192 code points with no control character. The Mac stores the base64 of a security-scoped bookmark here, Windows and Linux the path. This rule is structural only; each app checks the rest (a bookmark that resolves, an absolute path). |
| `addedAt` | The time the item was shelved, milliseconds since 1970: a whole number from 0 to 9007199254740991, else `0`. |

Then, on the items that survived:

1. **Newest first:** a stable sort by `addedAt`, largest first (equal times keep the file's order).
2. **Duplicates:** the first of each `id` stays, and the first of each `link` (compared exactly, case and all; a copy has no link so never clashes). Because of step 1, the newer duplicate wins.
3. **Cap:** the first 30. A hostile file with 300 items keeps the 30 newest.

The result is the shelf. Cleaning a clean shelf changes nothing.

### `shelfAdd(items, incoming)`: files dropped on the Shelf half

`items` is the shelf as stored (it is cleaned first). `incoming` is the list of items for the files of one drop, in the order the app wants them shown, each built by the app with `addedAt` set to now. The answer is `{items, results}` with one word per incoming item, in order:

| Word | When (checked in this order) |
|---|---|
| `invalid` | `incoming[i]` is not a list item `shelfClean` would keep (this includes a non-object). |
| `duplicate` | Its `id` or `link` is already on the shelf, or was added earlier in the same drop. A re-dropped file on a full shelf says `duplicate`, not `full`. |
| `full` | The shelf already holds 30, counting what this drop has added. Nothing already on the shelf is ever removed; the app shows a short note when any word is `full`. |
| `added` | Otherwise. |

The new shelf is `shelfClean` of the added items followed by the old ones, so the added ones are first (newest) and everything is in `shelfClean`'s order. If `incoming` is not a list it is empty.

## Decisions and open questions

These are choices the spec did not make. Each has the answer the plan assumed and the fixture pins it; a different answer is one edit in `reference.py` and `build_cases.py` (see the plan's "Open questions for the owner").

- The centre line belongs to **Ask**, the half whose behaviour already ships.
- An item is `{id, name, size, folder, copy, link?, addedAt}`; the spec names no fields.
- A **bad `size` or `addedAt` becomes 0** and the item stays (they are display and order only); a bad `id`, `name` or `link` drops the item (they are file system names and the way back to the original).
- Names and links are limited in **code points**, 255 and 8192, so all three languages count the same.
- A **duplicate** is the same id or the same `link`; the newer one stays. A cleaned file with more than 30 items keeps the 30 newest, but a **drop never evicts**: it refuses the extras (`full`).
- Windows' reserved names (`CON`, `NUL`) and a trailing dot or space in `name` are **not** refused here; the app that creates a copy's folder applies the file-name rules of G2's sanitizer, or its own, when it copies.
EOF
`````

- [ ] **Step 2: Add the CI step, the two pointers and the spec's table**

```bash
python3 - <<'PY'
# Task 5: the docs, the CI step and the spec's table. Run from the repository root. Every anchor must be there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('.github/workflows/build.yml', [(
"""      - name: Cat contract (cat-core.js self-checks, fixtures, determinism)
        run: bash scripts/test-cat-contract.sh
""",
"""      - name: Cat contract (cat-core.js self-checks, fixtures, determinism)
        run: bash scripts/test-cat-contract.sh

      - name: Shelf contract (zone and shelf rules, fixtures, no drift)
        run: bash scripts/test-shelf-contract.sh
""")])

edit('CLAUDE.md', [(
"- `docs/superpowers/specs/` — the NotchMeow design spec",
"- `tests/fixtures/shelf/`, `docs/SHELF-CONTRACT.md` — the shelf contract (sub-project G1-0): `zoneAt` (Ask or Shelf half), `shelfClean` (how `shelf.json` is read: ids, names, links, duplicates, the 30-item cap, newest first) and `shelfAdd` (a drop never evicts). `reference.py` (Python, standard library) decides when an app and a fixture disagree; `build_cases.py` writes the two JSON files; `scripts/test-shelf-contract.sh` runs them. No Swift, TypeScript or JS source holds these rules until the G1 app plans port them.\n"
"- `docs/superpowers/specs/` — the NotchMeow design spec")])

edit('ARCHITECT.md', [(
"   - **Sub-project H on Windows/Linux:**",
"   - **Sub-project G1-0 (the shelf contract):** `tests/fixtures/shelf/` (`zone-cases.json`, `shelf-cases.json`) with a Python `reference.py` that decides, like the AI contract's; `build_cases.py` writes the JSON, `scripts/test-shelf-contract.sh` checks it and CI runs that. Documented in `docs/SHELF-CONTRACT.md`. The G1 Mac and Windows/Linux plans port the rules and replay the fixtures.\n"
"   - **Sub-project H on Windows/Linux:**")])

edit('docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md', [(
"| `shelf-cases.json` | The clean-up of `shelf.json`: unknown fields, hostile ids and paths, duplicates, the 30-item cap, newest first, a refused overflow |",
"| `shelf-cases.json` | The clean-up of `shelf.json` (`shelfClean`: unknown fields, hostile ids, names and links, duplicates, the 30-item cap, newest first) and the Shelf drop (`shelfAdd`: `added`, `duplicate`, `full` or `invalid` for each file; an overflow is refused, nothing old is removed) |"),
(
"| `reference.py` | A Python standard-library reference for both rules |",
"| `reference.py` | A Python standard-library reference for the three rules; it decides when an app and a fixture disagree |\n| `build_cases.py` | Writes the two JSON files with the expected answers typed out by hand (`--check` fails on drift) |")])
PY
git diff --stat
```

Expected: `.github/workflows/build.yml` (3 insertions), `ARCHITECT.md` (1), `CLAUDE.md` (1) and the spec (3 insertions, 2 deletions) changed.

- [ ] **Step 3: Run every check**

```bash
bash -n scripts/test-shelf-contract.sh && bash scripts/test-shelf-contract.sh | tail -4
bash scripts/test-cat-contract.sh 2>&1 | grep -E '^# (tests|pass|fail)|fixture files|identical'
node scripts/check-fixtures-additive.mjs 5f9051c | tail -1
bash scripts/check-no-leftovers.sh | tail -6
grep -n "shelf" .github/workflows/build.yml
git status --short
```

Expected: `all shelf contract checks passed` with the two `matches` lines; `# tests 288`, `# pass 288`, `# fail 0`, `✓ 15 fixture files match cat-core.js`, `✓ two generator runs write identical bytes` (the number of tests is the cat contract's own, unchanged by this plan: if it differs from the number on `notchmeow/rebrand`, say so); `✓ fixtures changed only by addition since 5f9051c`; six `✓` lines of `check-no-leftovers.sh`; the workflow step; and a status of the four modified files and `?? docs/SHELF-CONTRACT.md` (the shelf fixtures and the script were committed by Tasks 1 to 3, and no `__pycache__` folder appears).

- [ ] **Step 4: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add docs/SHELF-CONTRACT.md .github/workflows/build.yml CLAUDE.md ARCHITECT.md docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md
cat > "${TMPDIR:-/tmp}/g10-msg5.txt" <<'EOF'
docs(shelf): the shelf contract document, the CI step and the pointers (G1-0)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -q -F "${TMPDIR:-/tmp}/g10-msg5.txt" && git log --oneline -5 && git show --stat --format= HEAD
```

Expected: five files listed; `git log` shows Tasks 1, 2, 3 and 5 on top of `notchmeow/rebrand`.

**Then the controller dispatches `nm-reviewer-deep` over the whole branch** (`git diff notchmeow/rebrand...HEAD`): the three rules against the spec's text, every hostile input it can think of against `reference.py`, anything a Swift, TypeScript or Rust port could read two ways (code points, whole-string match, `5.0`, stable sort, the order of the checks in `shelf_add`), that no existing fixture or source file moved, and that the plan's open questions are all in `docs/SHELF-CONTRACT.md`. Then it reports to the main session with `SendMessage`.

---

## Open questions for the owner

Each has the answer this plan assumes, so nothing blocks. A different answer is one edit in `reference.py` and `build_cases.py`, a regenerate, and the app plans pick it up.

1. **Where is the centre line?** The spec says "a pointer in a half, the centre line, outside the island" but not which half owns the line. Assumed: **Ask** (the drop that ships today, so a pointer exactly on the line behaves as before).
2. **What is a shelf item?** The spec names no fields. Assumed: `{id, name, size, folder, copy, link?, addedAt}` (see Global Constraints). `link` is a base64 bookmark on the Mac and a path on Windows/Linux, and is absent on a copy.
3. **A bad `size` or `addedAt`:** assumed to become `0` and keep the item (they only show and order); a bad `id`, `name` or `link` **drops** the item (they name a folder under `shelf/` and the way back to the original). The other reading is to drop the item for any bad field.
4. **Limits:** names 255 and links 8192 **code points**; an id of up to 64 of `[A-Za-z0-9_-]`; no control characters, `/` or `\` in a name (so a copy's folder cannot escape), and not `.` or `..`. Windows' reserved names and a trailing dot are left to the app that creates the copy's folder.
5. **Duplicates:** the same `id`, or the same `link` compared exactly (case-sensitive), keep the newer one. A copy never clashes with a link.
6. **Two caps:** reading a file with more than 30 items keeps the **30 newest** (a hostile file must not make a 300-tile shelf), but a drop on a full shelf **never evicts** (the spec's "nothing old is removed silently"): it answers `full`.
7. **The words and their order:** `invalid`, then `duplicate`, then `full`, then `added`. So a re-dropped file on a full shelf says `duplicate` (nothing to refuse), not `full`.
8. **A folder that is a copy** is refused (the spec: folders are accepted as links; Ask and Send refuse them, Show in folder accepts them).
9. **The plan has five tasks, not four:** the spec counts four for G1-0 (fixtures, reference and its test, docs and the CI hook, final checks); the fifth is the owner checkpoint the brief asked for. It can be folded into Task 5 by dropping its stop.
10. **No `cat-core.js`, no prototype panel, no `gen-cat-fixtures` change:** this follows the spec's G1-0 table (JSON plus a Python `reference.py`, as the AI contract does) rather than the H-0 and B-0 shape. If the owner prefers the rules to live in a shared JavaScript module like the cat's, that is a different plan.
11. **The Windows CI path filter** (`tests/fixtures/shelf/**` in `windows-tests.yml`) is added by the G1-tauri plan together with the TypeScript replay.

## The owner's answers (2026-10-14)

The owner approved this plan with every assumed answer above (questions 1–11 as written): the centre line is Ask; the item fields as listed; a bad `size` or `addedAt` becomes `0`, a bad `id`, `name` or `link` drops the item; the limits as listed; duplicates keep the newer; reading keeps the 30 newest, a drop on a full shelf never evicts; the words' order as listed; a folder copy is refused; five tasks; JSON plus `reference.py`; the CI filter in G1-tauri. Task 4 still stops for the owner's look at the printed rules table.

## Self-review notes

- **Spec coverage.** "Dropping": the half decided by one pure rule, `zoneAt` (Task 1). "Full shelf": items past 30 refused, nothing old removed (Task 3). "Storage": the list in `shelf.json` read through one clean-up rule covering hostile files, duplicates, the cap and unknown fields (Task 2); copies live in `shelf/<id>/`, so ids and names are restricted (Task 2). "G1-0": `shelf-cases.json`, `zone-cases.json`, `reference.py` (Tasks 1 to 3), `docs/SHELF-CONTRACT.md` and the CI hook (Task 5). Out of scope, left to the app plans: the shelf view and its entry points, drag out, Ask, Send, the badge, the desktop cat's reaction, the bookmark round trip and the Debug panel.
- **Placeholders.** None: every code step carries its full content, generated into this plan from the files the dry run ran.
- **Type consistency.** The names `zone_at`, `item_clean`, `tidy`, `shelf_clean`, `shelf_add`, `SHELF_MAX`, `ID_RE`, `NAME_MAX`, `LINK_MAX`, `NUMBER_MAX` and the fixture keys `cleanCases`, `addCases`, `cases`, `max`, `idPattern`, `nameMax`, `linkMax`, `numberMax` are the same in the builder, the reference, the document and the interface table; the answers `ask`, `shelf`, `added`, `duplicate`, `full`, `invalid` likewise.
- **Review Focus** lines 1 to 5 each have named tests above.
- **What this plan deliberately does not do:** touch either app; add a TypeScript or Swift port; add a prototype panel; add a Windows CI path.

## Dry run (2026-10-14)

Run before the plan was handed over, in a throwaway clone made with `git clone -q --local --shared --branch notchmeow/rebrand` of the repository at `5f9051c`, on a new branch `g1-0/shelf-contract`. The plan's text was generated from the files the first clone ran, then replayed from its first line to its last by a small script that executes every fenced `bash` block of Tasks 1 to 5 in order (the five-backtick block included) and prints what each printed. All 23 blocks exited 0 and printed the plan's `Expected:` lines. The commit steps ran in the clone, so each task started from its predecessor's commit; nothing was committed or pushed in the main checkout, where the plan file is the only change.

| Task | Result |
|---|---|
| 1 | The stub fails 12 of 25 zone rows; with `zone_at` written, 25 of 25; the three mutations (the centre line, the right edge, a zero width) fail 3, 1 and 1 rows |
| 2 | 97 clean cases (`shelf-cases.json` 80,536 bytes at this point); the checks fail with `NameError` until the rule exists; the eight mutations fail 5, 3, 6, 2, 3, 1, 4 and 3 checks; the 3000-shelf fuzz passes |
| 3 | 19 add cases (`shelf-cases.json` 124,451 bytes); `NameError` until the rule exists; the five mutations fail 2, 5, 5, 2 and 4 checks; the 1500-drop property test passes |
| 4 | The table prints as the plan says |
| 5 | The docs and edits apply; `bash scripts/test-shelf-contract.sh` passes with both no-drift lines; `bash scripts/test-cat-contract.sh`: `# tests 288`, `# pass 288`, `# fail 0`, 15 fixture files, identical bytes; `check-fixtures-additive.mjs 5f9051c`: `✓ fixtures changed only by addition`; `check-no-leftovers.sh` six `✓`; no `__pycache__` in the status |

**What drafting and the dry run changed in the plan:**
- **The shape follows the spec, not the brief.** The brief suggested `cat-core.js`, `gen-cat-fixtures` and a prototype panel; the spec's G1-0 table is two JSON files and a Python `reference.py` (the AI contract's shape). The plan follows the spec (open question 10).
- **The fixtures and the reference check each other.** A first run of the reference against hand-written add cases caught three mistakes in the cases themselves (a drop's new items sorted behind older ones because the test used an old time, and a key named `at` where `addedAt` was meant); that is why `build_cases.py` types every answer and never calls the reference.
- **A mutation that the cases did not catch** (the new items placed last: the stable sort hides it when they are newest) was replaced by one that they do (a drop that forgets the ids it has added), and an add case for the same id twice in one drop was added.
- **No bytecode in the repository.** The Task 4 script imports `reference.py`, which first left a `__pycache__` folder in the status; the script now sets `sys.dont_write_bytecode`.
- **Limits written out in full.** The 8192 and 8193 code point links and the 45-item shelves make `shelf-cases.json` about 124 KB; a repeat shorthand would have asked every port to implement it.

**Not run, by rule:** no NotchMeow app and no Tauri app was launched, and no `xcodebuild`, `cargo` or `npm` command ran (the plan touches no app code). `ListAgents` was not available to the drafting agent, so the main session's `[ref]` is not in the brief: the controller looks it up with `ListAgents` (the plan says so).

