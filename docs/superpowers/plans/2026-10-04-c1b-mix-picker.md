# Mix Picker (C, Stage 1b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the owner pick a version for each of the 15 cat moments on the audition page, lock the picks in as **Your mix**, and build that mix (and the round-two alternatives for any "None of these") through the same pipeline and report as the four sets.

**Architecture:** `recipe.py` gains the pickable-moment list, a loader for `design/sounds/sets/mine.json` (a `SetRecipe` named `mine` whose entries copy the picked entries and carry each set's pitch shift into them) and a loader for `design/sounds/sets/round2.json`. `build_pack.py` gains `--set mine` (refuses while any moment is `none`) and `--round2`, and `--check-recipes` validates both files when they exist; `--all` still builds only the four sets, never `mine` (controller's ruling). `audition.html` gains the pickers, the counter, Play my mix, Lock in and the Alt columns (on rows set to none and on rows already holding a round-two pick: a picked Alt stays visible and changeable, controller's ruling); its summary shows the exact text of `mine.json` in `#mine-json`, so the main session can read it from the page and write the file. Nothing in this stage touches the apps.

**Tech Stack:** Python 3.9 or newer (the macOS system `python3` is 3.9), standard library only, macOS `afconvert` (already C1's only external tool), plain HTML and JavaScript with no external scripts.

**Spec:** `docs/superpowers/specs/2026-10-04-sounds-design.md`: the Decisions table, section 2, "Picking per moment" (approved by the owner, commit `250b8dd`), the "Build" checks of section 6, "Stages" step 1b and "Risks". This plan is Stage 1b. It builds on C1, which has merged: `docs/superpowers/plans/2026-10-04-c1-sound-sets.md` and the code it produced (`tools/sounds/`, the recipe format, the four set recipes, `design/sounds/audition.html` and `tests/test_sound_build.py`), as it stands in `notchmeow/rebrand` at `5cdf7fc`, review-wave fixes included (listed under "C1's fixes this plan keeps" in the File Structure section). Stage 2 (originals, final pack, licence files) and Stage 3 (wiring) keep their own plans; "Interfaces for Stages 2 and 3" at the end says what this plan leaves them.

**Execution.** Run this plan in a git worktree session, on a new branch `c1/mix-picker` cut from `notchmeow/rebrand` at `5cdf7fc` (the merge of `c1/sound-sets`) or later. C1 has merged, so this plan edits C1's real files and imports C1's real test helpers. The session already runs in its own worktree, so its first command only creates the branch there:

```bash
git switch -c c1/mix-picker notchmeow/rebrand
git log --oneline -1
```

The log line must show `5cdf7fc` or a later commit of `notchmeow/rebrand`; if it shows something older, stop and tell the controller. Every command in the tasks runs from the worktree root. The 63 candidate clips are git-ignored, so the worktree does not have them: `build_pack.py` finds them in the main checkout on its own (C1 Task 8), and `NM_SOUND_CANDIDATES` points it there explicitly (read-only: the build only reads the clips and never writes into the main checkout):

```bash
export NM_SOUND_CANDIDATES="/path/to/notchmeow/.claude/sounds/candidates"
```

The built sets are git-ignored too: the page and the checks in Task 3 need `python3 tools/sounds/build_pack.py --all --report` run once in the worktree first (about 15 seconds, it writes under the worktree's `.claude/sounds/build/`).

**The session.** The session that runs this plan uses **Sonnet 5.5 at medium effort** (`ARCHITECT.md`: a plan whose tasks are mostly given in full). A worktree chat session's first turn runs on the app's default model, so the main session starts it in three steps:

1. The chip's prompt only sets up: run the `git switch` above in its worktree and check the log line, read `CLAUDE.md`, `ARCHITECT.md`, this plan and the spec, report "ready" and stop.
2. Once the owner starts the chip, the main session sets that session's model and effort (`set_session_model` to Sonnet 5.5, `set_session_effort` to medium).
3. The main session then sends the controller brief as the next message, so the whole plan runs on the configured model. Before any follow-up turn (a fix round, a question), it checks the session is still on Sonnet 5.5 at medium.

**Agents** (from `CLAUDE.md`): Task 1 hands over complete code and tests, so `nm-implementer-light` can transcribe it; Tasks 2 and 3 integrate and run things (a command line with new modes, a page checked in a browser), so use `nm-implementer`; each task gets an `nm-reviewer`, and the finished branch an `nm-reviewer-deep`. Fix rounds 4 and 5 go to `nm-implementer-deep`. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`. The commit steps below carry the trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`: an implementer running on another model puts that model's name in the trailer instead (for example `Claude Haiku 4.5`). Never push.

**From the page to `mine.json`.** The page cannot write a file, and the owner downloads and pastes nothing. After the owner locks in, the main session reads the exact `mine.json` text from the page and writes the file:

1. The page runs over `file://` or from a local web server rooted at the repo (both work: it only plays `../../.claude/sounds/build/` files). To show it in the app's browser pane, serve the repo root and open `/design/sounds/audition.html`. Serve it through a static server with a deep connection queue (the few lines in Task 3 Step 6, `request_queue_size = 256`): Python's stock `python3 -m http.server` resets connections when the page asks for its 112 WAVs at once, and the page then reports existing files as missing. The page asks once more for a file that fails (controller's ruling, kept: see Task 3), which is a backstop, not a substitute for the deep queue. If the page's notice says files are missing, reload. Picks live in that browser's `localStorage`, so the owner uses the same pane for every round.
2. The owner picks and presses **Lock in**. The summary shows the moments and, under it, `<pre id="mine-json">`.
3. The main session reads `document.getElementById('mine-json').textContent` from the pane (the pane's javascript tool, or `get_page_text`), writes it unchanged to `design/sounds/sets/mine.json`, and runs `python3 tools/sounds/build_pack.py --check-recipes`: that is the same loader the build uses, so a wrong or hand-edited file fails here, not in Stage 2.
4. For any `none`: a Sonnet subagent proposes `design/sounds/sets/round2.json` (spec, "Round two"), `build_pack.py --round2` builds it, the owner reloads the page, picks Alt cells and locks in again; the main session replaces `mine.json` the same way. When no moment is `none`, `build_pack.py --set mine` builds the mix and Stage 2 can start.

**This plan creates no real `mine.json` or `round2.json`**: the tests use temporary files, and the checks in Task 3 keep their scratch copies under `.claude/`. The owner's lock-in and the round-two data step make them later.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec and the brief.

- **Pickable moments (15):** `greet, love, annoyed, dizzy, slap, finish, error, approval, question, proud, wink, sleep, think, search, rate`. The other 13 (the 10 ticks, `yawn`, `work`, `gulp`) are the same in every set, and the page labels them "same in every set". The list is **derived from the recipes** (the slots the set files hold themselves) and pinned in a test against the spec's list.
- **Sets (4) and their pitch:** `studio`, `steff`, `kitten` (+1.5 semitones for the whole set), `bestof` (-1.0). A picked moment carries its set's pitch shift into the entry; a round-two entry keeps its own pitch; made-in-code sources never get a set's shift (as in C1's `build_slot`).
- **`mine.json`:** `{"title": "Your mix", "picks": {moment: value}}` for exactly the 15 moments, each once. A value is a set name, `none`, or `round2:<moment>-<n>`. An unknown name is an error; listing a shared sound is an error; `none` may sit in the file, but `build_pack.py --set mine` refuses (non-zero exit, naming the moments) while any moment is `none`.
- **`round2.json`:** ordinary recipe entries with ids `<moment>-<n>`, n from 1 to 3, only for pickable moments; mood and signature fixed by the slot table; the existing source checks apply (excluded clips, the Department64 rule); an entry may not reuse a set's exact window (same source, start and end) for that moment. `--round2` builds them to `.claude/sounds/build/round2/<moment>-<n>.wav`.
- **Your mix builds** through the same pipeline and checks as the four sets, with its own report section. Every picked file is byte-identical to its source's file, and a test pins that, on generated stand-in WAVs and small temporary recipes (CI has no candidate clips). **`--all` builds the four sets only, never `mine`** (controller's ruling): `mine` is built by `--set mine` alone, and a `mine.json` that is missing, broken or still `none` never affects `--all`.
- **The page:** pickers on the 15 rows, a select dot by each set's Play button plus **None of these**, the chosen cell highlighted; **Use this set for all** per set column; the counter "N of 15 picked" where none counts as an answer; **Play my mix** (all 28 in order, reusing the run-through); **Lock in** (enabled at 15 of 15) freezes the pickers and shows a summary; **Change picks** unlocks; picks persisted in `localStorage` inside try/catch; the exact `mine.json` text in an element with a stable id; Alt 1 to 3 columns only on rows marked none **or already holding a round-two pick** (controller's ruling: a picked Alt stays visible and changeable), when round-two files exist. A file that fails to load is asked for once more after 400 ms before the page calls it missing (controller's ruling, kept). It keeps the existing style, theme switch and no-network rule.
- **Tools:** Python 3 standard library plus macOS `afconvert`. Nothing else, no pip, no network, no downloads. Code must run on Python 3.9 (no `match`, no `X | Y` types at runtime) and on current Python 3. Output is deterministic.
- **Git:** commit `tools/sounds/`, `design/sounds/audition.html`, `tests/test_sound_build.py`. **Never commit WAVs or anything under `.claude/`.** Never create `design/sounds/sets/mine.json` or `round2.json` here. Never push. Stage files by name; never `git add -A`.
- **Repo rules that apply:** new views follow the existing app style (the page keeps C1's, which follows `design/sounds/listen.html`); never restyle what ships; `NotchBuddy/Resources/sounds/` stays untouched.
- **C1's merged fixes stay.** Two files are replaced in full here (`tools/sounds/build_pack.py`, `design/sounds/audition.html`) and the rest are appended to, so every block starts from the file as merged at `5cdf7fc`, and none of C1's review-wave fixes may be lost. They are listed under "C1's fixes this plan keeps" in the File Structure section; the "C1's fixes are still there" steps of Tasks 2 and 3 grep for each one, and C1's own tests (`TestRecipe`, `TestCli`, `TestAuditionPage`) pin them against the replaced files.

## Review Focus

Inputs and conditions the spec implies but never spells out, most likely first. Each has a test in the task named after it.

1. **A moment still `none` slipping into a shipped mix**, with or without `--report`, or half-building before the refusal. Expected: exit 2, the moments named, no folder and no WAV written. Tests: Task 2 `test_set_mine_refuses_while_any_moment_is_none_and_names_them`; Task 1 `test_none_is_allowed_in_the_file_but_the_recipe_refuses_while_any_moment_is_none`.
2. **`mine.json` typed or pasted wrong**: a moment listed twice (`json.load` silently keeps the last), a misspelled moment (which also leaves one missing), a shared sound listed, a bad set name, a round-two pick whose entry does not exist or belongs to another moment. Expected: one error naming every problem, never a mix with a wrong sound. Tests: Task 1 `test_every_moment_exactly_once`, `test_a_typo_names_both_the_unknown_moment_and_the_missing_one`, `test_a_shared_sound_cannot_be_listed`, `test_unknown_picks_are_errors`.
3. **Pitch lost or doubled on the way into the mix**: Kitten +1.5 and Best of -1.0 must travel with the moment, and a made-in-code `search` must not be shifted by a set's pitch. Expected: the picked file is the set's file byte for byte. Tests: Task 1 `test_every_picked_file_is_byte_identical_to_its_sources_file` (all four sets, a round-two pick, a made-in-code pick), `test_a_mix_copies_each_picked_entry_and_carries_its_sets_pitch`, Task 2 `test_set_mine_builds_the_picks_byte_identical_to_the_sets_files_and_reports`.
4. **Stale round-two files**: alternatives an earlier round built and the next `round2.json` no longer lists would show up as Alt columns on the page. A `none` moment with no alternative at all must be reported, not padded. Also a round-two clip that `afconvert` cannot decode (the new clips are the likeliest to be odd). Expected: `--round2` removes only its own `<moment>-<n>.wav` leftovers and says which `none` moments have nothing; an undecodable clip stops the build with exit 2 and the clip named, never a traceback (C1's `788449f`, which the new modes share). Tests: Task 2 `test_round2_removes_alternatives_an_earlier_round_left_behind`, `test_round2_says_which_none_moments_have_no_alternative`, `test_a_round_two_clip_that_cannot_be_decoded_stops_with_exit_2_and_no_traceback`.
5. **The page after a reload or without storage**: picks that name a set or alternative that no longer exists, storage that throws, a locked page whose counter no longer reaches 15, a round-two pick whose file is gone, a picked set with a missing folder in Play my mix, a round-two pick that vanishes from its row the moment it is made, a file the web server drops once on a cold load. Expected: the page never shows a pick it cannot play, never locks below 15 of 15, skips what it cannot play with a note, keeps a picked Alt visible and changeable (controller's ruling) and does not call a file missing after a single failed request (the 400 ms retry, controller's ruling). Tests: Task 3 `test_picks_are_stored_only_inside_try_catch`, `test_alt_cells_stay_on_a_row_that_holds_a_round_two_pick`, `test_a_file_that_fails_to_load_is_asked_for_once_more_after_400_ms`, the headless checks of Task 3 step 6 (stale, garbled and unavailable storage, a locked page that loses a pick, a missing set folder, the Alt cells after picking one, a request that fails once).

## File Structure

`tools/sounds/` stays a flat folder of modules that import each other by bare name.

| File (as merged at `5cdf7fc`) | Change |
|---|---|
| `tools/sounds/recipe.py` (200 lines) | Imports at lines 9-11 get `re`; then appended after `missing_sources` (the last function, ending line 200): `pickable_moments`, `Mix`, `MixPending`, `load_round2`, `round2_recipe`, `read_mix`, `none_moments`, `mix_recipe`, `load_mine`, and the constants `MINE_NAME`, `ROUND2_NAME`, `NONE`, `MIX_TITLE`, `ROUND2_PREFIX`, `ROUND2_MAX`, `ROUND2_ID`. Nothing of C1's is edited. |
| `tools/sounds/report.py` (70 lines) | `measure_set` (lines 32-40) is replaced by `measure_files` (rows named by file, checked against the slot's targets) plus a `measure_set` that calls it; `render_waiting` is appended after `render` (the last function) |
| `tools/sounds/build_pack.py` (118 lines) | Replaced in full, starting from the merged file: new modes `--set mine` and `--round2`, `--check-recipes` also checks `mine.json` and `round2.json` when they exist, `ROUND2_DIR`, `load_extras`, `remove_stale_round2`, the usage note on picking and locking in. `find_candidates` is unchanged; the build loop keeps C1's `788449f` handler. |
| `design/sounds/audition.html` (283 lines) | Replaced in full, starting from the merged page: everything C1's page does, plus the pickers, counter, Play my mix, Lock in, summary and Alt columns; keeps the `38a6b1c` and `9b4ae61` fixes |
| `tests/test_sound_build.py` (1035 lines, 103 tests, last test `test_it_tells_the_owner_how_to_build_when_files_are_missing`) | Appended at the end: `TestMix`, `TestMixBuild` (Task 1), `TestReportFiles`, `TestMixCli` (Task 2), `TestAuditionPicker` (Task 3) |

**Depends on C1.** The code below was written against C1's merged code (`notchmeow/rebrand` at `5cdf7fc`) and replayed on a clean clone of it. It uses: `recipe.SLOTS`, `SET_NAMES`, `SHARED_NAME`, `Entry`, `SetRecipe`, `RecipeError`, `parse_entry`, `load_recipes`, `_read`, `missing_sources`; `pipeline.build_set`, `build_slot`, `read_back`, `SourceError`; `report.check`, `Row`, `render`, `failures`; `build_pack.find_candidates`, `BUILD_DIR`, `main`; `audio_io.AfconvertLoader`; and, from C1's test file, `raw`, `write_json`, `SHARED_SLOTS`, `DictLoader`, `entry`, `burst`, `sine`, `read_bytes`, `ROOT`, the module-level imports (`contextlib`, `io`, `json`, `mock`, `os`, `re`, `shutil`, `subprocess`, `tempfile`, `unittest`, `synth`, `pipeline`, `report`, `build_pack`, `audio_io`) and the page test's data block (`<script type="application/json" id="data">`). All of these exist under these names at `5cdf7fc`. If a later C1 change renames one, adapt the name here and nothing else. The new test code defines none of C1's module-level names (C1 has `m`, `db`, `level`, `power`, `crossings`, `own_files`, `SETS_DIR`, `CANDIDATES`, `SHARED_SLOTS_IN_ORDER`), and C1's single `db` helper stays the only one.

**C1's fixes this plan keeps.** C1's review waves added these fixes; every block of this plan starts from the merged files and keeps them:

| Commit | Fix | Where it lives, and what pins it |
|---|---|---|
| `a5232db` | `_read` returns only JSON objects; `load_set` refuses a `set` that differs from its file name; `_check_source` accepts only a lower-case `synth:` prefix | `recipe.py`, which this plan only appends to. `load_round2` calls `_read` and `parse_entry`, so round two inherits all three; Task 1 `test_round_two_files_get_the_loaders_strictness_too` pins that |
| `788449f` | A clip `afconvert` cannot decode stops the build with exit 2 and the clip named, not a traceback | The `except (pipeline.SourceError, subprocess.CalledProcessError, OSError)` line of the build loop in the new `build_pack.py`; Task 2 `test_a_round_two_clip_that_cannot_be_decoded_stops_with_exit_2_and_no_traceback`, C1's `test_a_silent_window_stops_the_build_with_the_slot_named` |
| `38a6b1c` | The page ignores a stale `play()` rejection, and refreshes the status after a single play | `audition.html`: `if (current !== c) return;` in `playCell`'s catch handler, and `endRun(); setStatus(); playCell(c);` in every cell's click handler (the Alt cells use the same `newCell`); C1's `test_it_plays_the_build_folder_from_file_urls` pins both literals against the replaced page |
| `9b4ae61` | Page and recipe wording, the docstring and the single `db` helper | `audition.html`: the subtitle names the shared sounds exactly as merged ("the ticks, yawn, work and gulp are the same in all four (search is made in code in three sets and a recorded chatter in Best of)") and then says what the picker adds; the recipes, `pipeline.py` and the `db` helper are not touched here |
| `8eb17ce` | `scripts/test-sound-build.sh` and the CI step run the sound tests | Not touched: the new tests run there as they stand, standard library only |

---

### Task 1: The mix loader, the round-two loader and the byte-identical test

`recipe.py` learns what is pickable (the slots the set files hold themselves), how to read `mine.json` (strictly: a key listed twice is an error, every problem is named in one message) and `round2.json`, and how to turn picks into a `SetRecipe` named `mine`. A moment picked from a set copies that set's entry and **carries the set's pitch shift into the entry**, so Your mix needs no pitch of its own (`pitch_st` 0.0) and the pipeline builds it exactly as the set was built. A made-in-code source is not shifted, because `build_slot` does not shift it either. A round-two entry is taken as it is, and goes through C1's `_read` and `parse_entry`, so it inherits their strictness (a file that is not a JSON object, a `set` that is not `round2`, an odd-case `SYNTH:` source). `none` is legal in the file (`read_mix`), but `mix_recipe` and `load_mine` raise `MixPending` while any moment is `none`. The test at the end builds four small sets, round two and the mix on stand-in clips and compares every picked file to its source's file byte for byte.

**Files:**
- Modify: `tools/sounds/recipe.py` (the imports at lines 9-11, then append after line 200)
- Modify: `tests/test_sound_build.py` (append after line 1035, the end of C1's last test)

**Interfaces:**
- Consumes (C1 `recipe`): `SLOTS`, `SET_NAMES`, `Entry`, `SetRecipe`, `RecipeError`, `parse_entry(raw, where, shared=False) -> Entry`, `load_recipes(sets_dir) -> OrderedDict name -> SetRecipe`, `_read(path) -> dict` (as merged: it raises `RecipeError` for broken JSON and for a file that is not a JSON object, so `load_round2` needs no object check of its own; `parse_entry` accepts `synth:` only in lower case and `load_set` makes a file's `set` match its name, both from `a5232db`). Consumes (C1 `pipeline`): `build_set(recipe, loader, out_dir, cache=None)`, `build_slot(entry, loader, set_pitch_st=0.0)`, `read_back(out_dir, slot)`. Consumes (C1 tests): `raw`, `write_json`, `SHARED_SLOTS`, `DictLoader`, `burst`, `read_bytes`, `synth`, `pipeline`.
- Produces (`recipe`): `MINE_NAME = "mine"`, `ROUND2_NAME = "round2"`, `NONE = "none"`, `MIX_TITLE = "Your mix"`, `ROUND2_PREFIX = "round2:"`, `ROUND2_MAX = 3`, `ROUND2_ID` (compiled `^([a-z]+)-([1-3])$`); `Mix(title, picks)` where `picks` is an `OrderedDict` moment to pick in pickable order; `MixPending(RecipeError)` with `.moments`; `pickable_moments(sets) -> [moment]` (SLOTS order); `load_round2(path, sets) -> OrderedDict id -> Entry` (empty when the file is absent); `round2_recipe(round2) -> SetRecipe` (entries keyed by id, so `build_set` writes `<id>.wav`); `read_mix(path, sets, round2) -> Mix`; `none_moments(mix) -> [moment]`; `mix_recipe(mix, sets, round2) -> SetRecipe` named `mine`; `load_mine(path, sets, round2) -> SetRecipe`.
- Produces (tests, for Tasks 2 and 3): `PICKABLE_SPEC`, `SET_PITCH`, `CLIP_FREQ`, `MIX_PICKS`, `write_distinct_sets(directory)`, `distinct_clips() -> DictLoader`, `r2raw(slot, n, source=None, **extra)`, `write_round2(directory, *entries)`, `write_default_round2(directory)`, `write_mine(directory, picks, **top)`.

- [ ] **Step 1: Write the failing tests** (they include Review Focus 1, 2 and 3)

**Append to `tests/test_sound_build.py`**

```python
from collections import OrderedDict  # noqa: E402

# The 15 moments that differ between the sets (spec, "Picking per moment"), in the spec's order.
PICKABLE_SPEC = ["greet", "love", "annoyed", "dizzy", "slap", "finish", "error", "approval", "question",
                 "proud", "wink", "sleep", "think", "search", "rate"]
SET_PITCH = {"studio": 0.0, "steff": 0.0, "kitten": 1.5, "bestof": -1.0}          # the spec's set shifts
CLIP_FREQ = {"studio": 600.0, "steff": 700.0, "kitten": 800.0, "bestof": 900.0, "r2": 1000.0,
             "shared": 500.0}
# One pick per moment, from all four sets and from round two (the alternatives written below).
MIX_PICKS = {"greet": "kitten", "love": "bestof", "annoyed": "kitten", "dizzy": "studio",
             "slap": "round2:slap-1", "finish": "steff", "error": "bestof", "approval": "studio",
             "question": "kitten", "proud": "steff", "wink": "bestof", "sleep": "kitten", "think": "studio",
             "search": "kitten", "rate": "round2:rate-2"}


def write_distinct_sets(directory):
    """Four complete recipe sets whose clips differ, so a picked file can only have come from its set:
    set S reads '<slot>/S.wav'. Kitten shifts greet by a further +1 itself and makes its search in code,
    so the carried pitch meets a recorded entry with its own pitch and a made-in-code one."""
    os.makedirs(directory, exist_ok=True)
    write_json(os.path.join(directory, "_shared.json"), {"set": "_shared", "entries": [
        raw(s, "synth:%s" % s if s in synth.GAPS else "%s/shared.wav" % s) for s in SHARED_SLOTS]})
    own = [s for s in recipe.SLOTS if s not in SHARED_SLOTS]
    for name in recipe.SET_NAMES:
        entries = []
        for slot in own:
            extra = {"pitch_st": 1.0} if (name, slot) == ("kitten", "greet") else {}
            source = "synth:search" if (name, slot) == ("kitten", "search") else "%s/%s.wav" % (slot, name)
            entries.append(raw(slot, source, **extra))
        write_json(os.path.join(directory, name + ".json"), {
            "set": name, "title": name, "pitch_st": SET_PITCH[name], "entries": entries})


_DISTINCT = []


def distinct_clips():
    """A DictLoader with a stand-in clip for every '<slot>/<tag>.wav' (tags: the four sets, r2 for
    round two, shared). One sine burst per tag, so a built file can be traced to the tag it came from.
    Built once and shared by the tests."""
    if not _DISTINCT:
        bursts = {tag: burst(freq, 0.25, lead=0.03, amp=0.2) for tag, freq in CLIP_FREQ.items()}
        _DISTINCT.append(DictLoader({"%s/%s.wav" % (slot, tag): clip
                                     for slot in recipe.SLOTS for tag, clip in bursts.items()}))
    return _DISTINCT[0]


def r2raw(slot, n, source=None, **extra):
    """A raw round-two entry: an ordinary entry plus its id '<slot>-<n>'."""
    item = raw(slot, "%s/r2.wav" % slot if source is None else source, **extra)
    item["id"] = "%s-%d" % (slot, n)
    return item


def write_round2(directory, *entries):
    write_json(os.path.join(directory, "round2.json"), {"set": "round2", "entries": list(entries)})


def write_default_round2(directory):
    """Three alternatives: slap-1, rate-2 and rate-3 (so rate-1 does not exist)."""
    write_round2(directory, r2raw("slap", 1, start=0.0, end=0.2, pitch_st=2.0),
                 r2raw("rate", 2, pitch_st=-1.0), r2raw("rate", 3, start=0.0, end=0.15))


def write_mine(directory, picks, **top):
    doc = {"title": "Your mix", "picks": picks}
    doc.update(top)
    write_json(os.path.join(directory, "mine.json"), doc)


class TestMix(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nm mix ")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.d = os.path.join(self.tmp, "sets")
        write_distinct_sets(self.d)
        write_default_round2(self.d)
        self.sets = recipe.load_recipes(self.d)
        self.round2 = recipe.load_round2(os.path.join(self.d, "round2.json"), self.sets)
        self.mine = os.path.join(self.d, "mine.json")

    def read(self):
        return recipe.read_mix(self.mine, self.sets, self.round2)

    def fail_text(self, picks=None):
        """The message of the RecipeError that reading mine.json raises (after writing `picks`)."""
        if picks is not None:
            write_mine(self.d, picks)
        with self.assertRaises(recipe.RecipeError) as ctx:
            self.read()
        return str(ctx.exception)

    def r2(self, *entries):
        write_round2(self.d, *entries)
        return recipe.load_round2(os.path.join(self.d, "round2.json"), self.sets)

    def r2_fails(self, *entries):
        with self.assertRaises(recipe.RecipeError) as ctx:
            self.r2(*entries)
        return str(ctx.exception)

    # --- what is pickable -------------------------------------------------------------------

    def test_the_pickable_moments_are_the_15_the_set_files_hold(self):
        self.assertEqual(recipe.pickable_moments(self.sets), PICKABLE_SPEC)
        real = recipe.load_recipes(os.path.join(ROOT, "design", "sounds", "sets"))
        self.assertEqual(recipe.pickable_moments(real), PICKABLE_SPEC)
        self.assertTrue(set(SHARED_SLOTS).isdisjoint(PICKABLE_SPEC))
        self.assertEqual(len(PICKABLE_SPEC) + len(SHARED_SLOTS), len(recipe.SLOTS))

    # --- the mix ----------------------------------------------------------------------------

    def test_a_mix_copies_each_picked_entry_and_carries_its_sets_pitch(self):
        write_mine(self.d, dict(MIX_PICKS))
        mine = recipe.load_mine(self.mine, self.sets, self.round2)
        self.assertEqual((mine.name, mine.title, mine.pitch_st), ("mine", "Your mix", 0.0))
        self.assertEqual(list(mine.entries), list(recipe.SLOTS))
        e = mine.entries
        self.assertEqual((e["greet"].pitch_st, e["greet"].source), (2.5, "greet/kitten.wav"))   # +1.0 own, +1.5 set
        self.assertEqual(e["annoyed"].pitch_st, 1.5)          # kitten
        self.assertEqual(e["love"].pitch_st, -1.0)            # bestof
        self.assertEqual(e["dizzy"].pitch_st, 0.0)            # studio
        self.assertEqual((e["search"].pitch_st, e["search"].source), (0.0, "synth:search"))  # made in code: no shift
        self.assertEqual((e["slap"].pitch_st, e["slap"].source), (2.0, "slap/r2.wav"))       # round two keeps its own
        self.assertEqual(e["rate"].pitch_st, -1.0)
        self.assertEqual(e["finish"], self.sets["steff"].entries["finish"])    # steff has no shift: the entry is the set's
        for slot in SHARED_SLOTS:                                              # shared sounds pass through untouched
            self.assertEqual(e[slot], self.sets["studio"].entries[slot])
            self.assertTrue(e[slot].shared)
        self.assertFalse(any(e[m].shared for m in PICKABLE_SPEC))

    def test_use_this_set_for_all_gives_each_real_set_back(self):
        real = recipe.load_recipes(os.path.join(ROOT, "design", "sounds", "sets"))
        for name, s in real.items():
            mix = recipe.Mix("Your mix", OrderedDict((m, name) for m in PICKABLE_SPEC))
            mine = recipe.mix_recipe(mix, real, OrderedDict())
            for slot, src in s.entries.items():
                recorded = not src.shared and not src.source.startswith("synth:")
                self.assertEqual(mine.entries[slot].pitch_st, src.pitch_st + (s.pitch_st if recorded else 0.0), (name, slot))
                self.assertEqual(mine.entries[slot]._replace(pitch_st=0.0), src._replace(pitch_st=0.0), (name, slot))

    def test_the_carried_pitch_must_stay_in_range(self):
        doc = recipe._read(os.path.join(self.d, "kitten.json"))
        doc["pitch_st"] = 11.0
        doc["entries"][0]["pitch_st"] = 5.0                  # greet
        write_json(os.path.join(self.d, "kitten.json"), doc)
        sets = recipe.load_recipes(self.d)
        write_mine(self.d, dict(MIX_PICKS))
        with self.assertRaises(recipe.RecipeError) as ctx:
            recipe.load_mine(self.mine, sets, self.round2)
        self.assertIn("greet", str(ctx.exception))
        self.assertIn("-12..12", str(ctx.exception))

    def test_none_is_allowed_in_the_file_but_the_recipe_refuses_while_any_moment_is_none(self):
        write_mine(self.d, dict(MIX_PICKS, rate="none", search="none"))
        mix = self.read()
        self.assertEqual(recipe.none_moments(mix), ["search", "rate"])
        with self.assertRaises(recipe.MixPending) as ctx:
            recipe.load_mine(self.mine, self.sets, self.round2)
        self.assertEqual(ctx.exception.moments, ["search", "rate"])
        self.assertIn("search, rate", str(ctx.exception))
        self.assertIsInstance(ctx.exception, recipe.RecipeError)
        with self.assertRaises(recipe.MixPending):
            recipe.mix_recipe(mix, self.sets, self.round2)

    # --- the checks on mine.json ------------------------------------------------------------

    def test_every_moment_exactly_once(self):
        picks = dict(MIX_PICKS)
        del picks["wink"]
        self.assertIn("missing moment wink", self.fail_text(picks))
        with open(self.mine, "w", encoding="utf-8") as f:       # json.load would silently keep the last "greet"
            f.write('{"title": "Your mix", "picks": {"greet": "studio", "greet": "kitten"}}')
        self.assertIn("'greet' appears twice", self.fail_text())

    def test_a_typo_names_both_the_unknown_moment_and_the_missing_one(self):
        picks = dict(MIX_PICKS)
        picks["anoyed"] = picks.pop("annoyed")
        text = self.fail_text(picks)
        self.assertIn("unknown moment 'anoyed'", text)
        self.assertIn("missing moment annoyed", text)

    def test_a_shared_sound_cannot_be_listed(self):
        for slot in ("tick", "yawn", "gulp", "work", "approve"):
            self.assertIn("%s is the same in every set" % slot, self.fail_text(dict(MIX_PICKS, **{slot: "studio"})))
        self.assertIn("unknown moment 'purr'", self.fail_text(dict(MIX_PICKS, purr="studio")))

    def test_unknown_picks_are_errors(self):
        for value, part in (("studo", "unknown pick 'studo'"), ("", "unknown pick ''"),
                            ("Studio", "unknown pick 'Studio'"), ("_shared", "unknown pick '_shared'"),
                            (7, "must be text"), (None, "must be text"),
                            ("round2:slap-9", "is not in round2.json"),
                            ("round2:rate-2", "an alternative for rate, not greet")):
            self.assertIn(part, self.fail_text(dict(MIX_PICKS, greet=value)), repr(value))

    def test_the_file_shape_is_checked(self):
        for doc in ([], {"title": "Your mix"}, {"title": "Your mix", "picks": []},
                    {"title": "Your mix", "picks": dict(MIX_PICKS), "note": "x"}):
            write_json(self.mine, doc)
            self.assertIn("must be", self.fail_text(), repr(doc))
        write_json(self.mine, {"title": " ", "picks": dict(MIX_PICKS)})
        self.assertIn("title must be text", self.fail_text())
        with open(self.mine, "w", encoding="utf-8") as f:
            f.write("{ not json")
        self.assertIn("not valid JSON", self.fail_text())

    def test_a_mine_json_without_a_title_is_called_your_mix(self):
        write_json(self.mine, {"picks": dict(MIX_PICKS)})
        self.assertEqual(self.read().title, "Your mix")

    # --- round two --------------------------------------------------------------------------

    def test_round_two_entries_are_ordinary_entries_with_ids(self):
        r = self.r2(r2raw("rate", 1), r2raw("rate", 3, pitch_st=2), r2raw("search", 1, "synth:clink"))
        self.assertEqual(list(r), ["rate-1", "rate-3", "search-1"])
        self.assertEqual((r["rate-3"].slot, r["rate-3"].pitch_st, r["rate-3"].shared), ("rate", 2.0, False))
        self.assertEqual(recipe.round2_recipe(r).entries, r)
        os.remove(os.path.join(self.d, "round2.json"))
        self.assertEqual(recipe.load_round2(os.path.join(self.d, "round2.json"), self.sets), OrderedDict())

    def test_round_two_ids_must_name_a_pickable_moment_and_n_from_1_to_3(self):
        for ident in ("rate-0", "rate-4", "rate", "Rate-1", "rate-01", "rate-1-1", "-1", ""):
            item = r2raw("rate", 1)
            item["id"] = ident
            self.assertIn("must be <moment>-<n>", self.r2_fails(item), ident)
        item = r2raw("rate", 1)
        del item["id"]
        self.assertIn("must be <moment>-<n>", self.r2_fails(item))
        for slot in ("yawn", "tick", "gulp"):                  # shared sounds are not pickable
            item = r2raw(slot, 1)
            self.assertIn("not one of the 15", self.r2_fails(item), slot)
        item = r2raw("rate", 1)
        item["id"] = "purr-1"
        self.assertIn("not one of the 15", self.r2_fails(item))

    def test_a_round_two_id_and_slot_must_agree_and_ids_are_unique(self):
        item = r2raw("rate", 1)
        item["slot"] = "greet"
        item["mood"], item["signature"] = "happy", True
        self.assertIn("slot must be 'rate'", self.r2_fails(item))
        self.assertIn("appears twice", self.r2_fails(r2raw("rate", 1), r2raw("rate", 1, start=0.0, end=0.1)))

    def test_the_existing_source_checks_apply_to_round_two(self):
        self.assertIn("excluded source", self.r2_fails(r2raw("rate", 1, "rate/fs-857748-qubodup.mp3")))
        self.assertIn("excluded source", self.r2_fails(r2raw("rate", 1, "rate/fs-732521-Lukey1028.mp3")))
        self.assertIn("not a Department64", self.r2_fails(r2raw("rate", 1, "rate/fs-211234-Department64.mp3")))
        self.assertIn("mood must be", self.r2_fails(dict(r2raw("rate", 1), mood="happy")))
        self.assertIn("unknown fields", self.r2_fails(dict(r2raw("rate", 1), volume=3)))
        self.assertIn("pitch_st", self.r2_fails(r2raw("rate", 1, pitch_st=40)))
        self.r2(r2raw("rate", 1, "rate/fs-64012-Department64.mp3"))        # a kitten## file is fine

    def test_round_two_files_get_the_loaders_strictness_too(self):
        path = os.path.join(self.d, "round2.json")
        write_json(path, [])                                     # C1's _read: a recipe file is a JSON object
        with self.assertRaises(recipe.RecipeError) as ctx:
            recipe.load_round2(path, self.sets)
        self.assertIn("must be a JSON object", str(ctx.exception))
        write_json(path, {"set": "studio", "entries": []})       # a file that names another set
        with self.assertRaises(recipe.RecipeError) as ctx:
            recipe.load_round2(path, self.sets)
        self.assertIn("set 'round2'", str(ctx.exception))
        self.assertIn("source 'SYNTH:blip' must be", self.r2_fails(r2raw("rate", 1, "SYNTH:blip")))   # odd-case synth:

    def test_a_round_two_entry_may_not_reuse_a_sets_exact_window(self):
        for name in recipe.SET_NAMES:
            text = self.r2_fails(r2raw("rate", 1, "rate/%s.wav" % name))   # same clip, no window: the set's own
            self.assertIn("%s already uses this window" % name, text)
        self.assertIn("already uses", self.r2_fails(r2raw("search", 1, "synth:search")))   # kitten's made-in-code search
        self.r2(r2raw("rate", 1, "rate/studio.wav", start=0.1, end=0.2))   # same clip, another window
        self.r2(r2raw("rate", 1, "rate/studio.wav", start=0.0))            # a different window is enough
        self.r2(r2raw("greet", 1, "rate/studio.wav"))                      # the same clip for another moment is fine


class TestMixBuild(unittest.TestCase):
    """Your mix, built through the same pipeline, is the picked sources' own files, byte for byte."""

    def test_every_picked_file_is_byte_identical_to_its_sources_file(self):
        tmp = tempfile.mkdtemp(prefix="nm mix build ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        d = os.path.join(tmp, "sets")
        write_distinct_sets(d)
        write_default_round2(d)
        write_mine(d, dict(MIX_PICKS))
        sets = recipe.load_recipes(d)
        round2 = recipe.load_round2(os.path.join(d, "round2.json"), sets)
        mine = recipe.load_mine(os.path.join(d, "mine.json"), sets, round2)
        loader, cache = distinct_clips(), {}
        for name, s in sets.items():
            pipeline.build_set(s, loader, os.path.join(tmp, name), cache)
        pipeline.build_set(recipe.round2_recipe(round2), loader, os.path.join(tmp, "round2"), cache)
        pipeline.build_set(mine, loader, os.path.join(tmp, "mine"), {})       # its own cache: nothing is reused

        def read(*parts):
            return read_bytes(os.path.join(tmp, *parts))

        self.assertEqual(sorted(os.listdir(os.path.join(tmp, "mine"))), sorted(s + ".wav" for s in recipe.SLOTS))
        for moment, pick in MIX_PICKS.items():
            source = os.path.join("round2", pick[len(recipe.ROUND2_PREFIX):]) if pick.startswith(recipe.ROUND2_PREFIX) \
                else os.path.join(pick, moment)
            self.assertEqual(read("mine", moment + ".wav"), read(source + ".wav"), (moment, pick))
        for slot in SHARED_SLOTS:
            self.assertEqual(read("mine", slot + ".wav"), read("studio", slot + ".wav"), slot)
        # the comparison can tell the sets apart, and a mix that forgot the set's pitch would not match
        self.assertNotEqual(read("kitten", "greet.wav"), read("studio", "greet.wav"))
        self.assertNotEqual(read("mine", "greet.wav"), read("studio", "greet.wav"))
        forgot = pipeline.build_slot(sets["kitten"].entries["greet"], loader)       # kitten's entry, without the set's +1.5
        self.assertNotEqual(len(forgot.samples), len(pipeline.read_back(os.path.join(tmp, "kitten"), "greet")))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest tests.test_sound_build.TestMix tests.test_sound_build.TestMixBuild`
Expected: FAIL; every test errors with `AttributeError: module 'recipe' has no attribute ...` (`pickable_moments`, `load_round2`, `read_mix`, `Mix`, ...). The rest of the file still imports and runs.

- [ ] **Step 3: Write the implementation**

**Replace in `tools/sounds/recipe.py`**

```python
import json
import os
from collections import OrderedDict, namedtuple
```

with:

```python
import json
import os
import re
from collections import OrderedDict, namedtuple
```

**Append to `tools/sounds/recipe.py`**

```python
# --- Your mix and the round-two alternatives (stage 1b) --------------------------------------------

MINE_NAME = "mine"
ROUND2_NAME = "round2"
NONE = "none"                    # a pick that asks for a second round
MIX_TITLE = "Your mix"
ROUND2_PREFIX = "round2:"        # a pick of an alternative: round2:<moment>-<n>
ROUND2_MAX = 3                   # alternatives per moment: <moment>-1 to <moment>-3
ROUND2_ID = re.compile(r"^([a-z]+)-([1-3])$")

Mix = namedtuple("Mix", "title picks")        # picks: OrderedDict moment -> pick, in pickable order


class MixPending(RecipeError):
    """Your mix still has moments set to none, so it cannot be built for shipping."""

    def __init__(self, moments):
        RecipeError.__init__(
            self, "Your mix is not ready to build, still none: %s. Pick them on design/sounds/audition.html "
                  "(run --round2 first if nothing fits), lock in again and save the new mine.json"
                  % ", ".join(moments))
        self.moments = list(moments)


def pickable_moments(sets):
    """The cat moments that differ between the sets: the slots the set files hold themselves, that is
    everything outside _shared.json, in SLOTS order. `sets` is what load_recipes returns."""
    first = next(iter(sets.values()))
    return [slot for slot, e in first.entries.items() if not e.shared]


def _pairs_once(pairs):
    seen = OrderedDict()
    for key, value in pairs:
        if key in seen:
            raise RecipeError("%r appears twice" % key)
        seen[key] = value
    return seen


def _read_once(path):
    """Like _read, but a repeated key is an error: json.load would silently keep the last one, and a
    moment listed twice must not slip through."""
    with open(path, encoding="utf-8") as f:
        try:
            return json.load(f, object_pairs_hook=_pairs_once)
        except RecipeError as e:
            raise RecipeError("%s: %s (every key exactly once)" % (path, e))
        except ValueError as e:
            raise RecipeError("%s: not valid JSON (%s)" % (path, e))


def load_round2(path, sets):
    """round2.json: alternatives for the moments the owner marked none, as
    {"set": "round2", "entries": [{"id": "rate-1", "slot": "rate", ...an ordinary entry...}]}.
    Returns OrderedDict id -> Entry; empty when the file does not exist. Checked like any recipe
    (mood, signature, excluded sources) and, in addition, an entry may not use a window of a clip that
    one of the four sets already uses for that moment (same source, start and end)."""
    if not os.path.isfile(path):
        return OrderedDict()
    doc = _read(path)          # a broken file, or one that is not a JSON object, is already a RecipeError
    if doc.get("set", ROUND2_NAME) != ROUND2_NAME or not isinstance(doc.get("entries"), list):
        raise RecipeError("%s: must be an object with set 'round2' and a list of 'entries'" % path)
    pickable = pickable_moments(sets)
    out = OrderedDict()
    for item in doc["entries"]:
        if not isinstance(item, dict):
            raise RecipeError("%s: an entry must be an object" % ROUND2_NAME)
        item = dict(item)
        ident = item.pop("id", None)
        found = ROUND2_ID.match(ident) if isinstance(ident, str) else None
        if not found:
            raise RecipeError("%s: id %r must be <moment>-<n> with n from 1 to %d"
                              % (ROUND2_NAME, ident, ROUND2_MAX))
        where, moment = "%s/%s" % (ROUND2_NAME, ident), found.group(1)
        if moment not in pickable:
            raise RecipeError("%s: %s is not one of the 15 pickable moments" % (where, moment))
        if item.get("slot") != moment:
            raise RecipeError("%s: slot must be %r to match the id" % (where, moment))
        if ident in out:
            raise RecipeError("%s: id appears twice" % where)
        e = parse_entry(item, where)
        for name, s in sets.items():
            theirs = s.entries[moment]
            if (e.source, e.start, e.end) == (theirs.source, theirs.start, theirs.end):
                raise RecipeError("%s: %s already uses this window of %s for %s; take another clip or window"
                                  % (where, name, e.source, moment))
        out[ident] = e
    return out


def round2_recipe(round2):
    """The round-two entries as a SetRecipe keyed by id, so build_set writes <id>.wav."""
    return SetRecipe(ROUND2_NAME, "Round two", 0.0, OrderedDict(round2))


def _pick_problem(moment, pick, sets, round2):
    """Why `pick` is wrong for `moment`, or None."""
    if not isinstance(pick, str):
        return "%s: the pick must be text" % moment
    if pick == NONE or pick in sets:
        return None
    if pick.startswith(ROUND2_PREFIX):
        ident = pick[len(ROUND2_PREFIX):]
        if ident not in round2:
            return "%s: %s is not in round2.json" % (moment, pick)
        if round2[ident].slot != moment:
            return "%s: %s is an alternative for %s, not %s" % (moment, pick, round2[ident].slot, moment)
        return None
    return "%s: unknown pick %r (use %s, %s or %s<moment>-<n>)" % (moment, pick, ", ".join(sets), NONE, ROUND2_PREFIX)


def read_mix(path, sets, round2):
    """Read and check mine.json, {"title": "Your mix", "picks": {moment: pick}}: exactly the 15 pickable
    moments, each once; a pick is a set name, none, or round2:<moment>-<n> (an entry of `round2`).
    none is allowed here; mix_recipe is where it stops a build. Every problem is named in one message."""
    doc = _read_once(path)
    if not isinstance(doc, dict) or set(doc) - {"title", "picks"} or not isinstance(doc.get("picks"), dict):
        raise RecipeError('%s: must be {"title": ..., "picks": {moment: pick}} and nothing else' % path)
    title = doc.get("title", MIX_TITLE)
    if not isinstance(title, str) or not title.strip():
        raise RecipeError("%s: title must be text" % path)
    pickable, picks, problems = pickable_moments(sets), doc["picks"], []
    for moment in picks:
        if moment in pickable:
            continue
        problems.append("%s is the same in every set and is not picked" % moment if moment in SLOTS
                        else "unknown moment %r" % moment)
    problems += ["missing moment %s" % m for m in pickable if m not in picks]
    problems += [p for p in (_pick_problem(m, picks[m], sets, round2) for m in pickable if m in picks) if p]
    if problems:
        raise RecipeError("%s: %s" % (path, "; ".join(problems)))
    return Mix(title.strip(), OrderedDict((m, picks[m]) for m in pickable))


def none_moments(mix):
    return [m for m, pick in mix.picks.items() if pick == NONE]


def _picked_entry(moment, pick, sets, round2):
    """The entry Your mix builds for `moment`. A set's entry carries that set's pitch shift with it,
    because Your mix has no pitch of its own: the pipeline adds a set's shift to recorded clips only
    (never to made-in-code sounds), and so does this. A round-two entry keeps its own pitch."""
    if pick.startswith(ROUND2_PREFIX):
        return round2[pick[len(ROUND2_PREFIX):]]
    source = sets[pick]
    entry = source.entries[moment]
    shift = entry.pitch_st if entry.source.startswith("synth:") else entry.pitch_st + source.pitch_st
    if not -12.0 <= shift <= 12.0:
        raise RecipeError("%s: %s's pitch shift %+g plus its set's %+g is outside -12..12 semitones"
                          % (moment, pick, entry.pitch_st, source.pitch_st))
    return entry._replace(pitch_st=shift)


def mix_recipe(mix, sets, round2):
    """Your mix as a SetRecipe named 'mine' (28 entries in SLOTS order, pitch_st 0.0): each picked moment
    copies the picked entry, the 13 shared sounds are the sets' shared entries (the entries of
    _shared.json). Raises MixPending
    while any moment is none."""
    pending = none_moments(mix)
    if pending:
        raise MixPending(pending)
    shared = next(iter(sets.values())).entries
    entries = OrderedDict((slot, _picked_entry(slot, mix.picks[slot], sets, round2) if slot in mix.picks
                           else shared[slot]) for slot in SLOTS)
    return SetRecipe(MINE_NAME, mix.title, 0.0, entries)


def load_mine(path, sets, round2):
    """mine.json as the SetRecipe 'mine'. Raises MixPending while any moment is none."""
    return mix_recipe(read_mix(path, sets, round2), sets, round2)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: `Ran 121 tests`, `OK` (C1's 103 plus 18 new; the byte-identical test builds four sets, round two and the mix on stand-in clips and takes about 9 seconds of the run's roughly 40 (65 on the system Python 3.9); with no candidate clips found one C1 test is skipped, `OK (skipped=1)`)

- [ ] **Step 5: Commit**

```bash
git add tools/sounds/recipe.py tests/test_sound_build.py
git commit -m "feat(sounds): loader for Your mix and the round-two alternatives" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


---

### Task 2: `build_pack.py --set mine` and `--round2`, and the report

`--set mine` loads `mine.json` from the recipes folder and builds it through the same loop as the four sets, with its own report section (`## mine: 28 of 28 pass`). **`--all` builds the four sets only, never `mine`** (controller's ruling): it does not even read `mine.json` or `round2.json`, so a missing, broken or pending `mine.json` cannot affect it, and the build root's `report.md` holds four sections. **It refuses before building anything** while any moment is `none`: exit 2, the moments named on stderr, no folder created. `--round2` builds every entry of `round2.json` to `<build>/round2/<moment>-<n>.wav` with a section of its own, removes the `<moment>-<n>.wav` files an earlier round left behind (nothing else), and says which `none` moments of `mine.json` have no alternative at all. `--check-recipes` also validates `mine.json` and `round2.json` when they exist (and the clips of the round-two entries). A broken `mine.json` stops only `--set mine` and `--check-recipes`: building the four sets (`--set <set>`, `--all`) does not read it. The new modes share C1's build loop, so its handler stays: a window that is empty or silent, a clip `afconvert` cannot decode and an `OSError` all stop the build with exit 2 and the clip named, never a traceback (`788449f`). `--out` is the folder the WAVs go to, as for a set, so Stage 2 can run `--set mine --candidates <originals> --out NotchBuddy/Resources/sounds --report`. The new tests run on stand-in clips (the loader is replaced), so they need no `afconvert` and no candidate clips.

**Files:**
- Modify: `tools/sounds/report.py` (replace `measure_set`, lines 32-40; append `render_waiting` after line 70)
- Modify: `tools/sounds/build_pack.py` (118 lines, replaced in full by the version below)
- Modify: `tests/test_sound_build.py` (append, after Task 1's tests)

**Interfaces:**
- Consumes (Task 1): everything under "Produces (`recipe`)" and the test helpers `write_distinct_sets`, `distinct_clips`, `write_default_round2`, `write_round2`, `r2raw`, `write_mine`, `MIX_PICKS`, `PICKABLE_SPEC`. Consumes (C1): `report.check`, `Row`, `render`, `failures`, `read_back`; `pipeline.build_set`, `SourceError`; `build_pack.find_candidates`; `audio_io.AfconvertLoader`.
- Produces: `report.measure_files(pairs, out_dir) -> [Row]` where `pairs` is `[(file name, Built)]` (the row is named by the file, the slot's targets apply); `report.render_waiting(moments) -> str`; `build_pack.ROUND2_DIR` (`.claude/sounds/build/round2`, the folder the page probes); `build_pack.load_extras(recipes_dir, recipes) -> (round2, mix or None)`; `build_pack.remove_stale_round2(out, keep)`; command line `--set mine`, `--round2` (both take `--candidates`, `--out`, `--recipes`, `--report`). Exit codes as C1: 0 fine, 1 a file missed its targets (`--report`), 2 a recipe, clip (missing or undecodable), source or refusal problem.

- [ ] **Step 1: Write the failing tests** (they include Review Focus 1 and 4)

**Append to `tests/test_sound_build.py`**

```python
class TestReportFiles(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nm report files ")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.built = pipeline.build_slot(entry("rate"), DictLoader({"rate/c.wav": burst(700.0, 0.4, amp=0.2)}))

    def test_rows_are_named_by_file_and_checked_against_the_slots_targets(self):
        audio_io.write_wav16(os.path.join(self.tmp, "rate-2.wav"), self.built.samples)
        rows = report.measure_files([("rate-2", self.built)], self.tmp)
        self.assertEqual((rows[0].slot, rows[0].kind, rows[0].problems), ("rate-2", "cat", []))
        audio_io.write_wav16(os.path.join(self.tmp, "rate.wav"), self.built.samples)       # a set's files are named by slot
        self.assertEqual(report.measure_set([self.built], self.tmp), report.measure_files([("rate", self.built)], self.tmp))

    def test_a_round_two_file_that_misses_its_targets_is_named_by_its_id(self):
        audio_io.write_wav16(os.path.join(self.tmp, "rate-2.wav"), sine(500, 0.5, 0.01))   # about -43 LUFS
        rows = report.measure_files([("rate-2", self.built)], self.tmp)
        self.assertTrue(rows[0].problems)
        self.assertTrue(report.failures({"round2": rows})[0].startswith("round2/rate-2: loudness"))

    def test_the_waiting_note_names_the_moments_or_is_empty(self):
        self.assertEqual(report.render_waiting([]), "")
        self.assertIn("No round-two alternative for: rate, search", report.render_waiting(["rate", "search"]))


class TestMixCli(unittest.TestCase):
    """build_pack.py --set mine, --round2 and --check-recipes on stand-in clips: the decoder is replaced,
    so no afconvert and no candidate clips are needed."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nm mix cli ")                 # a space in every path
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.recipes = os.path.join(self.tmp, "recipe folder")
        write_distinct_sets(self.recipes)
        self.cands = os.path.join(self.tmp, "my candidates")
        loader = distinct_clips()
        for source in loader.clips:       # empty placeholders: the build checks the files exist, the stand-in never reads them
            path = os.path.join(self.cands, *source.split("/"))
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "w").close()
        patch = mock.patch.object(build_pack, "AfconvertLoader", lambda folder: loader)
        patch.start()
        self.addCleanup(patch.stop)

    def run_main(self, *argv, **kw):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = build_pack.main(list(argv) + ["--recipes", self.recipes, "--candidates", kw.get("cands", self.cands)])
        return code, out.getvalue(), err.getvalue()

    def folder(self, *names):
        return os.path.join(self.tmp, *names)

    def files(self, *names):
        return sorted(os.listdir(self.folder(*names)))

    def test_set_mine_refuses_while_any_moment_is_none_and_names_them(self):
        picks = dict.fromkeys(PICKABLE_SPEC, "studio")
        picks.update(rate="none", search="none")
        write_mine(self.recipes, picks)
        for extra in ([], ["--report"]):
            code, out, err = self.run_main("--set", "mine", "--out", self.folder("mine out"), *extra)
            self.assertEqual(code, 2)
            self.assertIn("search, rate", err)
            self.assertNotIn("built", out)
        self.assertFalse(os.path.exists(self.folder("mine out")))

    def test_set_mine_builds_the_picks_byte_identical_to_the_sets_files_and_reports(self):
        write_default_round2(self.recipes)
        picks = dict.fromkeys(PICKABLE_SPEC, "kitten")
        picks.update(slap="round2:slap-1", rate="round2:rate-2")
        write_mine(self.recipes, picks)
        self.assertEqual(self.run_main("--set", "kitten", "--out", self.folder("kitten"))[0], 0)
        self.assertEqual(self.run_main("--round2", "--out", self.folder("round2"))[0], 0)
        code, out, err = self.run_main("--set", "mine", "--out", self.folder("mine"), "--report")
        self.assertEqual(code, 0, err)
        self.assertIn("built mine: 28 files", out)
        self.assertIn("(28 of 28 files meet their targets)", out)
        self.assertEqual(self.files("mine"), sorted([s + ".wav" for s in recipe.SLOTS] + ["report.md"]))
        for slot in recipe.SLOTS:
            pick = picks.get(slot, "")
            source = self.folder("round2", pick[len(recipe.ROUND2_PREFIX):] + ".wav") \
                if pick.startswith(recipe.ROUND2_PREFIX) else self.folder("kitten", slot + ".wav")
            self.assertEqual(read_bytes(self.folder("mine", slot + ".wav")), read_bytes(source), slot)
        with open(self.folder("mine", "report.md"), encoding="utf-8") as f:
            self.assertIn("## mine: 28 of 28 pass", f.read())

    def test_set_mine_without_a_mine_json_says_where_it_comes_from(self):
        code, _, err = self.run_main("--set", "mine", "--out", self.folder("never"))
        self.assertEqual(code, 2)
        self.assertIn("mine.json", err)
        self.assertIn("audition.html", err)
        self.assertFalse(os.path.exists(self.folder("never")))

    def test_all_builds_the_four_sets_only_and_never_mine(self):
        write_default_round2(self.recipes)
        write_mine(self.recipes, dict(MIX_PICKS))                # a complete mine.json and a round2.json are right there
        built = []

        def record(rec, loader, out, cache=None):               # stands in for the 112-file build: only who gets built
            built.append((rec.name, os.path.basename(out)))
            return []

        with mock.patch.object(build_pack.pipeline, "build_set", record):
            code, _, err = self.run_main("--all", "--out", self.folder("all"))
            self.assertEqual(code, 0, err)
            self.assertEqual(built, [(name, name) for name in recipe.SET_NAMES])
            write_json(os.path.join(self.recipes, "mine.json"), [1])     # a broken mine.json is not even read
            code, _, err = self.run_main("--all", "--out", self.folder("all"))
            self.assertEqual(code, 0, err)
            self.assertEqual(len(built), 8)

    def test_a_broken_mine_json_stops_mine_and_the_check_but_not_the_four_sets(self):
        with open(os.path.join(self.recipes, "mine.json"), "w", encoding="utf-8") as f:
            f.write('{"title": "Your mix", "picks": {"greet": "studio", "greet": "kitten"}}')
        for argv in (["--set", "mine", "--out", self.folder("never")], ["--check-recipes"]):
            code, _, err = self.run_main(*argv)
            self.assertEqual(code, 2, argv)
            self.assertIn("recipe error", err)
            self.assertIn("appears twice", err)
        code, _, err = self.run_main("--set", "studio", "--out", self.folder("never"), cands=self.folder("nowhere"))
        self.assertIn("candidates folder not found", err)        # it got past the recipes
        self.assertNotIn("mine.json", err)
        code, _, err = self.run_main("--all", "--out", self.folder("never"), cands=self.folder("nowhere"))
        self.assertIn("candidates folder not found", err)        # --all does not read mine.json either
        self.assertNotIn("mine.json", err)
        self.assertFalse(os.path.exists(self.folder("never")))

    def test_round2_builds_the_alternatives_with_their_own_report_section(self):
        write_default_round2(self.recipes)
        code, out, err = self.run_main("--round2", "--out", self.folder("alts"), "--report")
        self.assertEqual(code, 0, err)
        self.assertEqual(self.files("alts"), ["rate-2.wav", "rate-3.wav", "report.md", "slap-1.wav"])
        self.assertIn("built round2: 3 files", out)
        with open(self.folder("alts", "report.md"), encoding="utf-8") as f:
            text = f.read()
        self.assertIn("## round2: 3 of 3 pass", text)
        self.assertIn("| rate-2 | cat |", text)

    def test_round2_removes_alternatives_an_earlier_round_left_behind(self):
        write_default_round2(self.recipes)
        self.run_main("--round2", "--out", self.folder("alts"))
        for other in ("greet.wav", "notes.txt", "rate-4.wav"):       # not alternatives the page would probe
            open(self.folder("alts", other), "w").close()
        write_round2(self.recipes, r2raw("rate", 2, pitch_st=-1.0))
        code, out, _ = self.run_main("--round2", "--out", self.folder("alts"))
        self.assertEqual(code, 0)
        self.assertEqual(self.files("alts"), ["greet.wav", "notes.txt", "rate-2.wav", "rate-4.wav"])
        self.assertIn("removed stale rate-3.wav", out)
        self.assertIn("removed stale slap-1.wav", out)

    def test_round2_says_which_none_moments_have_no_alternative(self):
        write_round2(self.recipes, r2raw("rate", 1))
        picks = dict.fromkeys(PICKABLE_SPEC, "studio")
        picks.update(rate="none", search="none")
        write_mine(self.recipes, picks)
        code, out, _ = self.run_main("--round2", "--out", self.folder("alts"), "--report")
        self.assertEqual(code, 0)
        self.assertIn("no round-two alternative for: search", out)
        self.assertNotIn("for: rate", out)
        with open(self.folder("alts", "report.md"), encoding="utf-8") as f:
            self.assertIn("No round-two alternative for: search", f.read())

    def test_round2_with_nothing_to_build_is_an_error(self):
        code, _, err = self.run_main("--round2", "--out", self.folder("alts"))
        self.assertEqual(code, 2)
        self.assertIn("round2.json", err)
        write_round2(self.recipes)
        code, _, err = self.run_main("--round2", "--out", self.folder("alts"))
        self.assertEqual(code, 2)
        self.assertFalse(os.path.exists(self.folder("alts")))

    def test_a_round_two_clip_that_cannot_be_decoded_stops_with_exit_2_and_no_traceback(self):
        write_default_round2(self.recipes)
        good = distinct_clips()
        bad = os.path.join(self.cands, "slap", "r2.wav")

        class Undecodable:
            clips = good.clips

            def load(self, source):
                if source == "slap/r2.wav":                      # what AfconvertLoader raises for a clip it cannot read
                    raise subprocess.CalledProcessError(1, ["afconvert", "-f", "WAVE", bad, "decoded.wav"])
                return good.load(source)

        with mock.patch.object(build_pack, "AfconvertLoader", lambda folder: Undecodable()):
            code, out, err = self.run_main("--round2", "--out", self.folder("alts"), "--report")
        self.assertEqual(code, 2)
        self.assertIn("round2:", err)
        self.assertIn("slap/r2.wav", err)
        self.assertNotIn("Traceback", err)
        self.assertNotIn("built round2", out)

    def test_check_recipes_validates_mine_json_and_round2_json_when_they_exist(self):
        code, out, _ = self.run_main("--check-recipes")
        self.assertEqual(code, 0)
        self.assertIn("recipes ok: 4 sets x 28 slots", out)
        self.assertNotIn("mine.json", out)
        self.assertNotIn("round2.json", out)
        write_default_round2(self.recipes)
        write_mine(self.recipes, dict(MIX_PICKS, search="none"))
        code, out, _ = self.run_main("--check-recipes")
        self.assertEqual(code, 0)
        self.assertIn("round2.json ok: 3 alternatives for rate, slap", out)
        self.assertIn("mine.json ok: 15 picks, 1 none (search)", out)
        os.remove(os.path.join(self.cands, "rate", "r2.wav"))
        code, _, err = self.run_main("--check-recipes")
        self.assertEqual(code, 2)
        self.assertIn("missing clip - round2: rate/r2.wav", err)
        write_mine(self.recipes, dict(MIX_PICKS, greet="studo"))
        code, _, err = self.run_main("--check-recipes")
        self.assertEqual(code, 2)
        self.assertIn("unknown pick 'studo'", err)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest tests.test_sound_build.TestReportFiles tests.test_sound_build.TestMixCli`
Expected: FAIL, 13 of the 14 tests. `TestReportFiles` errors with `AttributeError: module 'report' has no attribute 'measure_files'` (or `render_waiting`); the `TestMixCli` tests fail with `SystemExit: 2` (argparse rejects `--set mine` and `--round2`) or with missing output. `test_all_builds_the_four_sets_only_and_never_mine` already passes: C1's `--all` never built anything but the four sets, and the test keeps it that way once `main` is rewritten.

- [ ] **Step 3: Write the implementation**

**Replace in `tools/sounds/report.py`**

```python
def measure_set(built, out_dir):
    """Rows for one built set, measured from the WAV files as written."""
    rows = []
    for b in built:
        info = SLOTS[b.slot]
        m = loudness.measure(read_back(out_dir, b.slot))
        rows.append(Row(b.slot, info.kind, m.lufs, TARGETS[info.kind][0], m.rms_db, m.tp_db,
                        m.seconds, b.limit_db, check(b.slot, m)))
    return rows
```

with:

```python
def measure_files(pairs, out_dir):
    """Rows for built sounds, measured from the WAV files as written. `pairs` is [(file name, Built)]:
    out_dir/<file name>.wav holds the sound and the Built says which slot's targets apply. A set's file
    is named by its slot; a round-two alternative's by its id (rate-1)."""
    rows = []
    for name, b in pairs:
        info = SLOTS[b.slot]
        m = loudness.measure(read_back(out_dir, name))
        rows.append(Row(name, info.kind, m.lufs, TARGETS[info.kind][0], m.rms_db, m.tp_db,
                        m.seconds, b.limit_db, check(b.slot, m)))
    return rows


def measure_set(built, out_dir):
    """Rows for one built set, measured from the WAV files as written."""
    return measure_files([(b.slot, b) for b in built], out_dir)
```

**Append to `tools/sounds/report.py`**

```python
def render_waiting(moments):
    """A closing paragraph for the round-two report: moments still none that have no alternative.
    Nothing is invented for them; they are settled in chat."""
    if not moments:
        return ""
    return ("\nNo round-two alternative for: %s. Nothing in the candidates fits these moments; settle them in "
            "chat (a made-in-code sound, or wait for the real recordings).\n" % ", ".join(moments))
```

**Create `tools/sounds/build_pack.py`**

This replaces C1's file in full, starting from the file as merged at `5cdf7fc`. What changed: the usage text, `ROUND2_DIR`, `load_extras`, `remove_stale_round2`, and `main` (the two new modes, the extra checks, one loop over the jobs). Everything else is C1's, including `find_candidates` and the build loop's `except (pipeline.SourceError, subprocess.CalledProcessError, OSError)` handler from `788449f`; Step 4 greps for it.

```python
#!/usr/bin/env python3
"""Build NotchMeow's sound sets from the recipes in design/sounds/sets/.

  build_pack.py --set studio --candidates DIR --out DIR   one set, 28 WAVs in --out
  build_pack.py --all [--report]                          the four sets (never mine) under .claude/sounds/build
  build_pack.py --check-recipes                           validate the recipes (and the clips, if found)
  build_pack.py --set mine [--report]                     Your mix: 28 WAVs from the owner's picks
  build_pack.py --round2 [--report]                       the round-two alternatives, one WAV each

--report also writes report.md next to the WAVs and exits 1 when any file misses its targets.

Picking and locking in. Build the four sets (--all), open design/sounds/audition.html, pick a version
for each of the 15 cat moments (or "None of these") and Lock in. The page shows the exact text of
design/sounds/sets/mine.json: save it there and run --check-recipes. --set mine builds Your mix with
the same pipeline and report as a set, and refuses (exit 2, naming the moments) while any moment is
none. For the moments left at none, list alternatives in design/sounds/sets/round2.json (ids rate-1 to
rate-3 and so on), run --round2 and reload the page: Alt columns appear on those rows. Pick again and
lock in again.

Needs Python 3 and, for decoding the candidate clips, macOS afconvert. Nothing else.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(os.path.dirname(HERE))

import pipeline  # noqa: E402
import recipe  # noqa: E402
import report  # noqa: E402
from audio_io import AfconvertLoader  # noqa: E402

SETS_DIR = os.path.join(ROOT, "design", "sounds", "sets")
BUILD_DIR = os.path.join(ROOT, ".claude", "sounds", "build")
ROUND2_DIR = os.path.join(BUILD_DIR, recipe.ROUND2_NAME)    # the folder the audition page probes


def find_candidates(explicit=None, root=ROOT):
    """The candidates folder: --candidates, $NM_SOUND_CANDIDATES, <root>/.claude/sounds/candidates,
    then the same folder in the main checkout (a git worktree does not carry the git-ignored clips).
    None when there is none."""
    wanted = [explicit] if explicit else [os.environ.get("NM_SOUND_CANDIDATES"),
                                          os.path.join(root, ".claude", "sounds", "candidates")]
    for path in wanted:
        if path and os.path.isdir(path):
            return os.path.abspath(path)
    if explicit:
        return None
    try:
        common = subprocess.run(["git", "-C", root, "rev-parse", "--path-format=absolute",
                                 "--git-common-dir"], check=True, capture_output=True,
                                text=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    path = os.path.join(os.path.dirname(common), ".claude", "sounds", "candidates")
    return path if os.path.isdir(path) else None


def load_extras(recipes_dir, recipes):
    """round2.json and mine.json from the recipes folder, each only if it exists: (round2, mix or None)."""
    round2 = recipe.load_round2(os.path.join(recipes_dir, recipe.ROUND2_NAME + ".json"), recipes)
    path = os.path.join(recipes_dir, recipe.MINE_NAME + ".json")
    return round2, (recipe.read_mix(path, recipes, round2) if os.path.isfile(path) else None)


def remove_stale_round2(out, keep):
    """Round-two files in `out` that round2.json no longer lists: an earlier round's alternatives, which
    the page would show as Alt columns. Only names of the form <moment>-<n>.wav go; anything else stays."""
    for name in sorted(os.listdir(out)):
        stem, ext = os.path.splitext(name)
        if ext == ".wav" and recipe.ROUND2_ID.match(stem) and stem not in keep:
            os.remove(os.path.join(out, name))
            print("removed stale %s" % name)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    what = ap.add_mutually_exclusive_group(required=True)
    what.add_argument("--set", choices=recipe.SET_NAMES + (recipe.MINE_NAME,))
    what.add_argument("--all", action="store_true")
    what.add_argument("--round2", action="store_true", help="build the round-two alternatives (round2.json)")
    what.add_argument("--check-recipes", action="store_true")
    ap.add_argument("--candidates", help="folder of candidate clips (default: .claude/sounds/candidates)")
    ap.add_argument("--out", help="output folder: the WAVs of --set and --round2, or the build root of --all")
    ap.add_argument("--recipes", default=SETS_DIR, help="folder of set recipes (and mine.json, round2.json)")
    ap.add_argument("--report", action="store_true", help="write report.md and fail if targets are missed")
    args = ap.parse_args(argv)

    wants_extras = args.check_recipes or args.round2 or args.set == recipe.MINE_NAME
    try:
        recipes = recipe.load_recipes(args.recipes)
        round2, mix = load_extras(args.recipes, recipes) if wants_extras else (OrderedDict(), None)
    except (recipe.RecipeError, OSError) as e:
        print("recipe error: %s" % e, file=sys.stderr)
        return 2
    cands = find_candidates(args.candidates)

    if args.check_recipes:
        print("recipes ok: %d sets x %d slots" % (len(recipes), len(recipe.SLOTS)))
        todo = list(recipes.values())
        if round2:
            todo.append(recipe.round2_recipe(round2))
            print("round2.json ok: %d alternatives for %s"
                  % (len(round2), ", ".join(sorted({e.slot for e in round2.values()}))))
        if mix is not None:
            none = recipe.none_moments(mix)
            print("mine.json ok: %d picks, %d none%s"
                  % (len(mix.picks), len(none), (" (%s)" % ", ".join(none)) if none else ""))
        if cands is None:
            print("candidates folder not found: the clip files were not checked")
            return 0
        gone = sorted({"%s: %s" % (r.name, s) for r in todo for s in recipe.missing_sources(r, cands)})
        for line in gone:
            print("missing clip - " + line, file=sys.stderr)
        print("clips ok in %s" % cands if not gone else "%d missing clip(s)" % len(gone))
        return 2 if gone else 0

    # what to build: (name, SetRecipe, output folder). The refusals come before anything is written.
    root_out = os.path.abspath(args.out or BUILD_DIR) if args.all else None
    if args.all:
        jobs = [(n, r, os.path.join(root_out, n)) for n, r in recipes.items()]
    elif args.set == recipe.MINE_NAME:
        if mix is None:
            print("mine: no %s.json in %s; pick on design/sounds/audition.html and lock in first"
                  % (recipe.MINE_NAME, args.recipes), file=sys.stderr)
            return 2
        try:
            mine = recipe.mix_recipe(mix, recipes, round2)
        except recipe.RecipeError as e:           # MixPending names the moments that are still none
            print("mine: %s" % e, file=sys.stderr)
            return 2
        jobs = [(recipe.MINE_NAME, mine, os.path.abspath(args.out or os.path.join(BUILD_DIR, recipe.MINE_NAME)))]
    elif args.round2:
        if not round2:
            print("round2: no alternatives in %s" % os.path.join(args.recipes, recipe.ROUND2_NAME + ".json"),
                  file=sys.stderr)
            return 2
        jobs = [(recipe.ROUND2_NAME, recipe.round2_recipe(round2), os.path.abspath(args.out or ROUND2_DIR))]
    else:
        jobs = [(args.set, recipes[args.set], os.path.abspath(args.out or os.path.join(BUILD_DIR, args.set)))]

    if cands is None:
        print("candidates folder not found; pass --candidates or set NM_SOUND_CANDIDATES", file=sys.stderr)
        return 2
    loader, cache, results = AfconvertLoader(cands), {}, OrderedDict()
    for name, rec, out in jobs:
        gone = recipe.missing_sources(rec, cands)
        if gone:
            print("%s: missing clips in %s: %s" % (name, cands, ", ".join(gone)), file=sys.stderr)
            return 2
        try:
            built = pipeline.build_set(rec, loader, out, cache)
        except (pipeline.SourceError, subprocess.CalledProcessError, OSError) as e:
            print("%s: %s" % (name, e), file=sys.stderr)
            return 2
        print("built %s: %d files in %s" % (name, len(built), out))
        if args.round2:
            remove_stale_round2(out, rec.entries)
        if args.report:
            results[name] = report.measure_files(list(zip(rec.entries, built)), out)
    waiting = []
    if args.round2 and mix is not None:
        waiting = [m for m in recipe.none_moments(mix) if not any(e.slot == m for e in round2.values())]
        if waiting:
            print("no round-two alternative for: %s" % ", ".join(waiting))
    if args.report:
        target = os.path.join(root_out if args.all else jobs[0][2], "report.md")
        with open(target, "w", encoding="utf-8") as f:
            f.write(report.render(results) + report.render_waiting(waiting) + "\n")
        bad = report.failures(results)
        total = sum(len(r) for r in results.values())
        print("report: %s (%d of %d files meet their targets)" % (target, total - len(bad), total))
        for line in bad:
            print("FAIL " + line, file=sys.stderr)
        return 1 if bad else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

The file must stay executable (it was in C1); if the editor dropped the mode, restore it:

```bash
chmod +x tools/sounds/build_pack.py
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: `Ran 135 tests`, `OK` (Task 1's 121 plus 14 new; about 45 seconds in all, about 80 on the system Python 3.9). C1's own CLI and report tests still pass: the four-set modes behave as before.

- [ ] **Step 5: Check that C1's fixes in `build_pack.py` are still there**

`build_pack.py` was replaced in full, so look at exactly what the replacement took out of the merged file:

```bash
git diff -U0 tools/sounds/build_pack.py | grep -E '^-[^-]' | wc -l
git diff -U0 tools/sounds/build_pack.py | grep -c 'CalledProcessError'
grep -n 'except (pipeline.SourceError, subprocess.CalledProcessError, OSError)' tools/sounds/build_pack.py
git diff --summary tools/sounds/build_pack.py
```

Expected: `15`: only the lines `main` replaces (the `--all` usage line, the `--set` choices, the `--out` and `--recipes` help texts, the two lines of the missing-clip comprehension, `chosen`, `root_out`, the loop header and its `out`, `gone` and `build_set` lines, `measure_set`, and the report `target` and `render` lines); `0`, because the `788449f` handler is neither removed nor changed; the handler line with its line number (line 159 of the resulting file); and no output from the last command (the file is still executable, no `mode change`). If the first number is larger, the replacement dropped something of C1's: restore it from `git show HEAD:tools/sounds/build_pack.py`.

- [ ] **Step 6: Commit**

```bash
git add tools/sounds/report.py tools/sounds/build_pack.py tests/test_sound_build.py
git commit -m "feat(sounds): build_pack --set mine and --round2, report rows by file" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


---

### Task 3: The picker on the audition page

`design/sounds/audition.html` is replaced by a version that does everything C1's page did (the 28 rows by four sets, Play buttons with lengths, "Play the whole set" per set, the missing-files notice, the theme switch, no network) and adds the picking. The 15 pickable rows get a **select dot** beside each set's Play button and a **None of these** cell; the chosen cell is highlighted. Each set column gets **Use this set for all**. The 13 shared rows say "same in every set" and have nothing to pick. The sticky bottom bar shows the status, the counter ("12 of 15 picked", none counts), **Play my mix**, **Lock in** (enabled at 15 of 15) and **Change picks**. Lock in freezes every picker and shows a summary that includes the exact text of `mine.json` in `<pre id="mine-json">`; the main session reads that element from the page (the app's browser pane) and writes `design/sounds/sets/mine.json`, so the owner downloads and pastes nothing. Picks survive a reload through `localStorage` (every access inside try/catch; a pick that no longer makes sense is dropped; the page only comes back locked if all 15 are still valid, and it unlocks itself if a pick is lost). One small robustness change to C1's grid: a file that errors is asked for once more after 400 ms before the page calls it missing, because the page asks for 112 files at once and a simple local web server can drop some on a cold load (seen with `python3 -m http.server`, where a first load reported dozens of existing files as missing).

**Ruling (controller): the 400 ms retry stays.** Python's stock `http.server` has a connection queue of 5 and resets connections when 112 WAVs load at once. The owner listens through a deep-queue server (Step 6 has the few lines), so the retry is a backstop for a request that still fails once, not the fix for the stock server, and it must not be removed as redundant. It costs 400 ms before a really missing file is reported, and one extra console error for it.

**The page below is built from C1's merged page** (`5cdf7fc`) and keeps its two review-wave fixes: the `play()` rejection handler starts `if (current !== c) return;` (a stale rejection from a sound that was already replaced must not clear the sound now playing), and every cell's click handler is `endRun(); setStatus(); playCell(c);` (a single play after a run-through refreshes the status line instead of leaving the old "Playing ..." text). The subtitle keeps the merged wording about which sounds are shared. C1's `TestAuditionPage` asserts both literals against this page, so a replacement that drops them fails Step 4.

**Play my mix** reuses C1's run-through: it queues the 28 sounds in slot order, a pick from that set's already-built file (or from the round-two file), a shared sound from the first set whose file exists, and skips with a note any moment that is `none`, unpicked or unplayable.

**The Alt 1 to 3 columns.** The page is static over `file://`: it cannot list a folder, and `fetch` is refused for `file://` pages (the no-network test also forbids it). So it **probes the three file names `round2/<moment>-<n>.wav` (n = 1 to 3)**, which the build fixes: `build_pack.py --round2` writes exactly those names, and a missing file is just an `error` event on an `Audio` element, the same mechanism C1's grid already uses for the four sets. A row probes (and shows an Alt cell for each file that exists) while it is set to None of these **or already holds a round-two pick**, so a picked alternative stays visible and can be changed to another Alt, to a set or back to None of these. (Ruling, controller: accepted. Showing Alt cells only on rows set to none would make them vanish the moment one is picked.) There is nothing to keep in step by hand: build round two, reload the page. The probing is lazy (only those rows), so a page with no `none` row asks for no round-two file and logs nothing. A column header shows only while some row shows a cell in it.

**Files:**
- Modify: `design/sounds/audition.html` (283 lines, replaced in full by the version below)
- Modify: `tests/test_sound_build.py` (append, after Task 2's tests)

**Interfaces:**
- Consumes: `recipe.pickable_moments`, `recipe.MIX_TITLE`, `recipe.NONE`, `recipe.ROUND2_PREFIX`, `recipe.ROUND2_MAX`, `recipe.SET_NAMES`, `build_pack.BUILD_DIR`, `build_pack.ROUND2_DIR`; the files the builds write: `.claude/sounds/build/<set>/<slot>.wav` and `.claude/sounds/build/round2/<moment>-<n>.wav`. Consumes (tests): `PICKABLE_SPEC`, `SHARED_SLOTS`.
- Produces: the page. Stable ids: `counter`, `play-mix`, `lock`, `unlock`, `summary`, `summary-note`, `summary-body`, `mine-json`, `run-<set>`, `all-<set>`. The text of `#mine-json` is `JSON.stringify({title, picks}, null, 2)` plus a newline, with the 15 moments in pickable order: exactly what `recipe.read_mix` reads. Its `localStorage` keys: `notchmeow.audition.picks` (`{"picks": {...}, "locked": bool}`) and C1's `notchmeow.audition.theme`.
- Everything C1's page tests pin stays true: the embedded slot table equals `recipe.SLOTS`, `var BASE` is the build folder, the literal `BASE + set.id + "/" + s.slot + ".wav"`, the two literals of `38a6b1c` (`if (current !== c) return;` and `endRun(); setStatus(); playCell(c);`), no `<script src`, no `http://` or `https://`, no `fetch(`, the rebuild command text and "Play the whole set".

- [ ] **Step 1: Write the failing tests** (they include Review Focus 5)

**Append to `tests/test_sound_build.py`**

```python
class TestAuditionPicker(unittest.TestCase):
    def setUp(self):
        with open(os.path.join(ROOT, "design", "sounds", "audition.html"), encoding="utf-8") as f:
            self.html = f.read()
        self.data = json.loads(re.search(r'<script type="application/json" id="data">(.*?)</script>',
                                         self.html, re.S).group(1))

    def js(self, name):
        """The text of a `var NAME = "...";` line of the page."""
        return re.search(r'var %s = "([^"]*)"' % name, self.html).group(1)

    def test_the_pickable_moments_are_the_specs_fifteen_and_the_recipes(self):
        sets = recipe.load_recipes(os.path.join(ROOT, "design", "sounds", "sets"))
        self.assertEqual(self.data["pickable"], PICKABLE_SPEC)
        self.assertEqual(self.data["pickable"], recipe.pickable_moments(sets))

    def test_the_other_thirteen_rows_are_the_shared_sounds(self):
        rest = [s["slot"] for s in self.data["slots"] if s["slot"] not in self.data["pickable"]]
        self.assertEqual(len(rest), 13)
        self.assertEqual(sorted(rest), sorted(SHARED_SLOTS))
        self.assertIn("same in every set", self.html)

    def test_the_page_speaks_the_loaders_vocabulary(self):
        self.assertEqual(self.js("TITLE"), recipe.MIX_TITLE)
        self.assertEqual(self.js("NONE"), recipe.NONE)
        self.assertEqual(self.js("ROUND2_PREFIX"), recipe.ROUND2_PREFIX)
        self.assertEqual(int(re.search(r"var ALT_COUNT = (\d+);", self.html).group(1)), recipe.ROUND2_MAX)
        self.assertEqual([s["id"] for s in self.data["sets"]], list(recipe.SET_NAMES))

    def test_alternatives_are_probed_in_the_folder_build_pack_writes(self):
        sub = re.search(r'var ROUND2 = BASE \+ "([^"]+)"', self.html).group(1)
        self.assertEqual(os.path.normpath(os.path.join(build_pack.BUILD_DIR, sub)), build_pack.ROUND2_DIR)
        self.assertIn('ROUND2 + slot + "-" + n + ".wav"', self.html)

    def test_the_picker_controls_and_labels_are_there(self):
        for ident in ("counter", "play-mix", "lock", "unlock", "summary", "summary-note", "summary-body", "mine-json"):
            self.assertIn('id="%s"' % ident, self.html, ident)
        for text in ("None of these", "Use this set for all", "Play my mix", "Lock in", "Change picks", '" picked"'):
            self.assertIn(text, self.html, text)

    def test_picks_are_stored_only_inside_try_catch(self):
        lines = [line for line in self.html.splitlines() if "localStorage" in line]
        self.assertGreaterEqual(len(lines), 2)
        for line in lines:
            self.assertIn("try {", line)
            self.assertIn("catch", line)
        self.assertIn("notchmeow.audition.picks", self.html)

    def test_alt_cells_stay_on_a_row_that_holds_a_round_two_pick(self):
        # controller's ruling: a picked Alt stays visible and changeable, so a row asks for its Alt cells
        # while it is none and also while it holds a round2: pick
        self.assertIn("var wantsAlts = v === NONE || isAlt(v);", self.html)
        self.assertIn("var show = wantsAlts && alt.found;", self.html)

    def test_a_file_that_fails_to_load_is_asked_for_once_more_after_400_ms(self):
        # controller's ruling, kept: a simple server can drop a request on a cold load of 112 files
        self.assertIn("if (!c.retried) { c.retried = true; setTimeout(function () { c.audio.src = url; }, 400); return; }",
                      self.html)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest tests.test_sound_build.TestAuditionPicker`
Expected: FAIL, all 8 tests: `KeyError: 'pickable'` and `AttributeError: 'NoneType' object has no attribute 'group'` (the page has no `var TITLE` yet), and assertion failures for the missing ids, labels and the two ruled behaviours.

- [ ] **Step 3: Write the page**

**Create `design/sounds/audition.html`**

This replaces C1's page in full. It keeps C1's colours, type, cards, theme switch, slot table and run-through; the picking is new.

```html
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark light">
<title>NotchMeow sound sets</title>
<!--
  Audition and picking page for the sound sets (sub-project C, stages 1 and 1b). Static: no scripts from
  anywhere, no network. It plays the WAVs that tools/sounds/build_pack.py wrote to .claude/sounds/build/,
  which is not in git, so build them first:  python3 tools/sounds/build_pack.py --all --report
  Works from file://. Colours, type and cards follow design/sounds/listen.html.

  Picking. Choose a version of each of the 15 cat moments (a set, or None of these), then Lock in. The
  summary shows the exact text of design/sounds/sets/mine.json in the element #mine-json: save it there
  (the main session reads it from this page) and run  python3 tools/sounds/build_pack.py --check-recipes.
  A moment left at None of these gets a second round: alternatives are listed in
  design/sounds/sets/round2.json and built with  python3 tools/sounds/build_pack.py --round2  into
  .claude/sounds/build/round2/<moment>-<n>.wav. A static page cannot list a folder, so this one probes
  those three file names for every row that is set to None of these (or already holds a round-two pick)
  and shows an Alt cell for each file that exists. Build round two, reload the page: nothing to keep in
  step by hand. Picks are remembered in this browser only (a convenience; mine.json is the record).

  The slot table and the list of pickable moments in the JSON block below are checked against
  tools/sounds/recipe.py by tests/test_sound_build.py, so they cannot drift from the build.
-->
<style>
:root{--bg:#0f1012;--card:#17181b;--sub:#131417;--line:#2a2c31;--line2:#43464e;--ink:#ececee;--dim:#9a9ca3;--acc:#5EEAD4;--btn:#202227;--warn:#f2c46d;--bar:rgba(23,24,27,.94);color-scheme:dark}
@media (prefers-color-scheme:light){:root:not([data-theme="dark"]){--bg:#f3f3f5;--card:#ffffff;--sub:#f8f8fa;--line:#dcdde2;--line2:#b4b7bf;--ink:#17181b;--dim:#5b5e66;--acc:#0b7f71;--btn:#f0f1f3;--warn:#8a5a00;--bar:rgba(255,255,255,.94);color-scheme:light}}
:root[data-theme="light"]{--bg:#f3f3f5;--card:#ffffff;--sub:#f8f8fa;--line:#dcdde2;--line2:#b4b7bf;--ink:#17181b;--dim:#5b5e66;--acc:#0b7f71;--btn:#f0f1f3;--warn:#8a5a00;--bar:rgba(255,255,255,.94);color-scheme:light}
*{box-sizing:border-box}
[hidden]{display:none!important}
body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;background:var(--sub);border:1px solid var(--line);border-radius:6px;padding:0 5px}
.wrap{max-width:1280px;margin:0 auto;padding:24px 16px 40px}
.top{display:flex;gap:12px;align-items:flex-start;justify-content:space-between}
h1{font-size:22px;font-weight:600;margin:0 0 4px}
h2{font-size:17px;font-weight:600;margin:0 0 6px}
.sub{color:var(--dim);margin:0 0 14px}
button{font:inherit;font-size:12px;color:var(--ink);background:var(--btn);border:1px solid var(--line);border-radius:8px;padding:4px 10px;cursor:pointer;line-height:1.5}
button:hover:not(:disabled){border-color:var(--line2)}
button:disabled{cursor:default;opacity:.5}
button.on{border-color:var(--acc);color:var(--acc)}
button:focus-visible{outline:2px solid var(--acc);outline-offset:2px}
input[type=radio]{accent-color:var(--acc);width:16px;height:16px;margin:0;flex:none;cursor:pointer}
input[type=radio]:disabled{cursor:default}
input[type=radio]:focus-visible{outline:2px solid var(--acc);outline-offset:2px}
.panel{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:16px;margin:0 0 16px}
.panel p{margin:0}.panel p+p{margin-top:6px;color:var(--dim);font-size:13px}
.warn{border-color:var(--warn)}
.scroll{overflow-x:auto;border:1px solid var(--line);border-radius:16px;background:var(--card)}
table{border-collapse:collapse;width:100%}
#grid{min-width:980px}
th,td{padding:8px 12px;border-bottom:1px solid var(--line);vertical-align:top;text-align:left}
thead th{position:sticky;top:0;background:var(--card);z-index:2;border-bottom:1px solid var(--line2)}
tbody tr:last-child td{border-bottom:0}
tbody th{font-weight:400}
th.slot{width:22%}
.set-h{display:flex;flex-direction:column;gap:6px;align-items:flex-start}
.set-h b{font-size:15px;font-weight:600}
.set-h span{color:var(--dim);font-size:12px;font-weight:400}
tr.group th{background:var(--sub);font-size:12px;color:var(--dim);text-transform:uppercase;letter-spacing:.04em}
.name{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-weight:600}
.when{color:var(--dim);font-size:13px}
.chips{display:flex;flex-wrap:wrap;gap:4px;margin-top:4px}
.chip{font-size:11px;color:var(--dim);border:1px solid var(--line);border-radius:999px;padding:0 8px}
.chip.sig{border-color:var(--acc);color:var(--acc)}
.cell{display:flex;flex-wrap:wrap;align-items:center;gap:8px;min-height:30px}
.cell .len{color:var(--dim);font-size:12px}
.cell.missing .len{color:var(--warn)}
.cell.now button{border-color:var(--acc);color:var(--acc);background:var(--sub)}
td.picked{box-shadow:inset 0 0 0 2px var(--acc);background:var(--sub)}
.none-pick{display:flex;align-items:center;gap:8px;min-height:30px;cursor:pointer}
.same{color:var(--dim);font-size:13px;min-height:30px}
.plain{width:auto}
.plain th,.plain td{padding:4px 24px 4px 0}
pre{margin:6px 0 0;padding:12px;background:var(--sub);border:1px solid var(--line);border-radius:10px;font:12px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;overflow-x:auto;user-select:all}
.bar{position:sticky;bottom:0;z-index:5;background:var(--bar);border-top:1px solid var(--line);-webkit-backdrop-filter:blur(8px);backdrop-filter:blur(8px)}
.bar-in{max-width:1280px;margin:0 auto;padding:10px 16px;font-size:13px;color:var(--dim);display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:8px 16px}
.mix-ctl{display:flex;flex-wrap:wrap;align-items:center;gap:8px}
#counter{color:var(--ink);font-weight:600}
</style></head><body>
<div class="wrap">
<div class="top">
<div>
<h1>NotchMeow sound sets</h1>
<p class="sub">Four complete sets of the 28 sounds. They differ only in the cat's voice; the ticks, yawn, work and gulp are the same in all four (search is made in code in three sets and a recorded chatter in Best of). Listen, then pick a version for each cat moment: your picks ship as Your mix.</p>
</div>
<button id="theme" type="button" aria-label="Switch colour theme">Light</button>
</div>

<div class="panel" id="missing" hidden role="alert">
<p><b id="missing-n"></b> sound files are missing. Build the sets, then reload this page:</p>
<p><code>python3 tools/sounds/build_pack.py --all --report</code></p>
</div>

<div class="panel" role="note">
<p>Each cat moment is the cat sound plus a short <b>touch</b> in its mood, and some also get the <b>signature</b> (collar-bell sparkle). Ticks get neither. The per-cat voice (pitch offset) and the chattiness volume are applied in the app at play time, so they are not in these files.</p>
<p>Pick a version for each of the 15 cat moments with the dot beside its Play button, or <b>None of these</b> if nothing fits: it gets a second round, and Alt columns appear on that row once the alternatives are built. <b>Use this set for all</b> fills every row from one set. The other 13 rows are the same in every set, so there is nothing to pick. At 15 of 15, <b>Lock in</b> shows your mix. "Play the whole set" and "Play my mix" run through all the sounds with a short gap. Sounds play from <code>.claude/sounds/build/</code>, which is not in git.</p>
</div>

<div class="panel" id="summary" hidden>
<h2>Your mix is locked in</h2>
<p id="summary-note"></p>
<table class="plain"><tbody id="summary-body"></tbody></table>
<p>The exact text of <code>design/sounds/sets/mine.json</code>:</p>
<pre id="mine-json"></pre>
</div>

<div class="scroll">
<table id="grid">
<thead><tr id="head"><th class="slot" scope="col">Slot</th></tr></thead>
</table>
</div>
</div>

<footer class="bar"><div class="bar-in">
<div id="status" role="status" aria-live="polite">Looking for the built files…</div>
<div class="mix-ctl">
<b id="counter">0 of 15 picked</b>
<button id="play-mix" type="button">Play my mix</button>
<button id="lock" type="button" disabled>Lock in</button>
<button id="unlock" type="button" hidden>Change picks</button>
</div>
</div></footer>

<script type="application/json" id="data">
{"pickable":["greet","love","annoyed","dizzy","slap","finish","error","approval","question","proud","wink","sleep","think","search","rate"],
"sets":[
{"id":"studio","title":"Studio","voice":"BigSoundBank's cat Emi, with MBPL's soft trills"},
{"id":"steff","title":"Steff's cat","voice":"steffcaffrey's cat; gaps from MBPL and Sadiquecat"},
{"id":"kitten","title":"Kitten","voice":"Department64's Oscar (kitten files, Buddha Purr), up 1.5 semitones"},
{"id":"bestof","title":"Best of","voice":"The strongest clip per slot, one shared pitch shift"}],
"slots":[
{"slot":"greet","kind":"cat","mood":"happy","signature":true,"dark":false,"when":"the greeting"},
{"slot":"love","kind":"cat","mood":"happy","signature":true,"dark":false,"when":"love emote, hover on the cat, a file drag starts"},
{"slot":"annoyed","kind":"cat","mood":"upset","signature":false,"dark":false,"when":"poked too often"},
{"slot":"dizzy","kind":"cat","mood":"upset","signature":false,"dark":false,"when":"dizzy after slaps"},
{"slot":"slap","kind":"cat","mood":"calm","signature":false,"dark":false,"when":"poked"},
{"slot":"finish","kind":"cat","mood":"happy","signature":true,"dark":false,"when":"agent finished"},
{"slot":"error","kind":"cat","mood":"upset","signature":true,"dark":true,"when":"agent error"},
{"slot":"approval","kind":"cat","mood":"attention","signature":true,"dark":false,"when":"an agent needs your approval"},
{"slot":"question","kind":"cat","mood":"attention","signature":true,"dark":false,"when":"an agent asks a question"},
{"slot":"proud","kind":"cat","mood":"happy","signature":false,"dark":false,"when":"proud emote"},
{"slot":"wink","kind":"cat","mood":"happy","signature":false,"dark":false,"when":"wink emote"},
{"slot":"yawn","kind":"cat","mood":"calm","signature":false,"dark":false,"when":"yawn emote"},
{"slot":"sleep","kind":"cat","mood":"calm","signature":false,"dark":false,"when":"falling asleep (one soft snore)"},
{"slot":"gulp","kind":"cat","mood":"happy","signature":false,"dark":false,"when":"catching a file"},
{"slot":"think","kind":"cat","mood":"attention","signature":false,"dark":false,"when":"a prompt is sent"},
{"slot":"search","kind":"cat","mood":"attention","signature":false,"dark":false,"when":"searching"},
{"slot":"work","kind":"cat","mood":"calm","signature":false,"dark":false,"when":"working (kneading pats)"},
{"slot":"rate","kind":"cat","mood":"upset","signature":false,"dark":false,"when":"rate-limited"},
{"slot":"approve","kind":"tick","mood":"none","signature":false,"dark":false,"when":"you approved an agent's request"},
{"slot":"peek","kind":"tick","mood":"none","signature":false,"dark":false,"when":"the island peeks"},
{"slot":"open","kind":"tick","mood":"none","signature":false,"dark":false,"when":"the island opens"},
{"slot":"close","kind":"tick","mood":"none","signature":false,"dark":false,"when":"the island closes"},
{"slot":"hover","kind":"tick","mood":"none","signature":false,"dark":false,"when":"hover"},
{"slot":"blip","kind":"tick","mood":"none","signature":false,"dark":false,"when":"small UI blip"},
{"slot":"tick","kind":"tick","mood":"none","signature":false,"dark":false,"when":"ticker tick"},
{"slot":"send","kind":"tick","mood":"none","signature":false,"dark":false,"when":"sending a chat message"},
{"slot":"attach","kind":"tick","mood":"none","signature":false,"dark":false,"when":"attaching a file"},
{"slot":"pop","kind":"tick","mood":"none","signature":false,"dark":false,"when":"popover pop"}]}
</script>

<script>
"use strict";
(function () {
  var BASE = "../../.claude/sounds/build/";
  var ROUND2 = BASE + "round2/";
  var GAP_MS = 450;
  var TITLE = "Your mix";
  var NONE = "none";
  var ROUND2_PREFIX = "round2:";
  var ALT_COUNT = 3;
  var PICKS_KEY = "notchmeow.audition.picks";
  var THEME_KEY = "notchmeow.audition.theme";
  var DATA = JSON.parse(document.getElementById("data").textContent);
  var PICKABLE = DATA.pickable;
  var GROUPS = [["cat", "Cat moments"], ["tick", "Interface ticks"]];
  var cells = {};          // "set/slot" -> cell: the four sets' sounds
  var alts = {};           // "moment-n" -> cell: the round-two alternatives, probed only while a row asks for them
  var rows = {};           // pickable moment -> {noneTd, noneRadio, altTds}
  var sharedTds = [];      // the "same in every set" cells of the 13 shared rows
  var groupHeads = [];
  var altHeads = [];
  var allBtns = [];
  var titleOf = {};
  var current = null;      // the cell playing now
  var run = null;          // the running pass: {btn, label}
  var timer = null;
  var state = { picks: {}, locked: false };
  var statusEl = document.getElementById("status");
  var counterEl = document.getElementById("counter");
  var lockBtn = document.getElementById("lock");
  var unlockBtn = document.getElementById("unlock");
  var mixBtn = document.getElementById("play-mix");
  var summaryEl = document.getElementById("summary");
  DATA.sets.forEach(function (s) { titleOf[s.id] = s.title; });

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }
  function key(set, slot) { return set + "/" + slot; }
  function readStore(k) { try { return window.localStorage.getItem(k); } catch (e) { return null; } }
  function writeStore(k, v) { try { window.localStorage.setItem(k, v); } catch (e) { /* storage unavailable */ } }

  // --- the picks: one value per pickable moment: a set id, "none", or "round2:<moment>-<n>" ---
  function isAlt(v) { return typeof v === "string" && v.indexOf(ROUND2_PREFIX) === 0; }
  function altNumber(moment, v) {
    var head = ROUND2_PREFIX + moment + "-";
    if (!isAlt(v) || v.indexOf(head) !== 0) return 0;
    var n = v.slice(head.length);
    return /^[1-9]$/.test(n) && Number(n) <= ALT_COUNT ? Number(n) : 0;
  }
  function validPick(moment, v) {
    return typeof v === "string" && (v === NONE || titleOf.hasOwnProperty(v) || altNumber(moment, v) > 0);
  }
  function loadState() {
    var saved = null, picks = {};
    try { saved = JSON.parse(readStore(PICKS_KEY)); } catch (e) { saved = null; }
    if (saved && typeof saved === "object" && saved.picks && typeof saved.picks === "object") {
      PICKABLE.forEach(function (m) {
        if (Object.prototype.hasOwnProperty.call(saved.picks, m) && validPick(m, saved.picks[m])) picks[m] = saved.picks[m];
      });
    }
    // a locked page only comes back locked while every moment still has a valid pick
    return { picks: picks, locked: !!(saved && saved.locked) && Object.keys(picks).length === PICKABLE.length };
  }
  function save() { writeStore(PICKS_KEY, JSON.stringify({ picks: state.picks, locked: state.locked })); }
  function change() { save(); render(); }
  function pickLabel(v) {
    if (v === NONE) return "none: gets a second round";
    if (isAlt(v)) return "Alt " + v.slice(v.lastIndexOf("-") + 1) + " (round two)";
    return titleOf[v];
  }
  // the exact text of design/sounds/sets/mine.json
  function mineText() {
    var picks = {};
    PICKABLE.forEach(function (m) { picks[m] = state.picks[m]; });
    return JSON.stringify({ title: TITLE, picks: picks }, null, 2) + "\n";
  }

  // --- playback ---
  function stopNow() {
    if (timer) { clearTimeout(timer); timer = null; }
    if (current) {
      current.audio.pause();
      try { current.audio.currentTime = 0; } catch (e) { /* not seekable yet */ }
      current.box.classList.remove("now");
      current = null;
    }
  }
  function playCell(c, onEnd) {
    stopNow();
    current = c;
    c.box.classList.add("now");
    c.audio.onended = function () {
      c.box.classList.remove("now");
      if (current === c) current = null;
      if (onEnd) onEnd();
    };
    var p = c.audio.play();
    if (p && p.catch) p.catch(function () { if (current !== c) return; c.box.classList.remove("now"); current = null; if (onEnd) onEnd(); });
  }
  function endRun() {
    if (run) {
      run.btn.textContent = run.label;
      run.btn.classList.remove("on");
      run = null;
    }
  }
  // one run-through for a set and for the mix: play the queue in order with a short gap
  function runQueue(btn, label, queue, name) {
    var wasThis = run && run.btn === btn;
    endRun();
    stopNow();
    if (wasThis) { setStatus(); return; }
    var mine = { btn: btn, label: label };
    run = mine;
    btn.textContent = "Stop";
    btn.classList.add("on");
    (function next(i) {
      if (run !== mine) return;
      if (i >= queue.length) { endRun(); setStatus(); return; }
      statusEl.textContent = "Playing " + name + ": " + queue[i].slot + " (" + (i + 1) + " of " + queue.length + ")";
      playCell(queue[i], function () {
        timer = setTimeout(function () { next(i + 1); }, GAP_MS);
      });
    })(0);
  }
  function runSet(set, btn) {
    var queue = [];
    DATA.slots.forEach(function (s) { var c = cells[key(set, s.slot)]; if (c.found) queue.push(c); });
    runQueue(btn, "Play the whole set", queue, set);
  }
  // the 28 sounds in slot order: a pick from its set's (or round two's) file, a shared sound from the
  // first set whose file exists; anything none, unpicked or not playable is skipped and named
  function mixQueue() {
    var queue = [], skipped = [];
    DATA.slots.forEach(function (s) {
      var c = null, v = state.picks[s.slot];
      if (PICKABLE.indexOf(s.slot) >= 0) {
        if (isAlt(v)) c = alts[v.slice(ROUND2_PREFIX.length)];
        else if (v && v !== NONE) c = cells[key(v, s.slot)];
      } else {
        for (var i = 0; i < DATA.sets.length && !(c && c.found); i++) c = cells[key(DATA.sets[i].id, s.slot)];
      }
      if (c && c.found) queue.push(c); else skipped.push(s.slot);
    });
    return { queue: queue, skipped: skipped };
  }

  function setStatus() {
    var total = 0, found = 0, missing = 0;
    Object.keys(cells).forEach(function (k) {
      total++;
      if (cells[k].found) found++;
      if (cells[k].missing) missing++;
    });
    var box = document.getElementById("missing");
    box.hidden = missing === 0;
    document.getElementById("missing-n").textContent = missing + " of " + total;
    statusEl.textContent = found + " of " + total + " files found" +
      (found + missing < total ? ", still looking…" : (missing ? "; run build_pack.py --all for the rest." : "."));
  }

  // --- one cell: an optional select dot, a Play button and the length once the file is known ---
  function newCell(slot, label, radioName, radioValue) {
    var box = el("div", "cell");
    var c = { slot: slot, audio: new Audio(), box: box, td: null, radio: null, found: false, missing: false, started: false, retried: false };
    if (radioName) {
      c.radio = el("input");
      c.radio.type = "radio"; c.radio.name = radioName; c.radio.value = radioValue;
      c.radio.setAttribute("aria-label", "Pick " + label + " for " + slot);
      box.appendChild(c.radio);
    }
    c.btn = el("button", "", "▶ Play"); c.btn.type = "button";
    c.btn.setAttribute("aria-label", "Play " + slot + ", " + label);
    c.btn.addEventListener("click", function () { endRun(); setStatus(); playCell(c); });
    c.len = el("span", "len", "…");
    box.appendChild(c.btn); box.appendChild(c.len);
    c.audio.preload = "metadata";
    return c;
  }
  function startCell(c, url, onChange) {
    if (c.started) return;
    c.started = true;
    c.audio.addEventListener("loadedmetadata", function () {
      c.found = true; c.len.textContent = c.audio.duration.toFixed(2) + " s"; onChange();
    });
    c.audio.addEventListener("error", function () {
      if (c.found) return;
      // 112 files are asked for at once, and a simple local web server can drop some of them on a cold
      // load: look once more before calling a file missing
      if (!c.retried) { c.retried = true; setTimeout(function () { c.audio.src = url; }, 400); return; }
      c.missing = true; c.btn.disabled = true; c.box.classList.add("missing"); c.len.textContent = "missing"; onChange();
    });
    c.audio.src = url;
  }
  function startAlt(slot, n) {
    var c = alts[slot + "-" + n];
    startCell(c, ROUND2 + slot + "-" + n + ".wav", function () {
      // a round-two pick whose file is gone is no pick
      if (c.missing && state.picks[slot] === ROUND2_PREFIX + slot + "-" + n) { delete state.picks[slot]; save(); }
      render();
    });
  }

  // --- drawing the state: dots, highlights, Alt columns, counter, buttons, summary ---
  function render() {
    var count = Object.keys(state.picks).length;
    if (state.locked && count < PICKABLE.length) { state.locked = false; save(); }   // never locked below 15 of 15
    var altShown = [false, false, false];
    PICKABLE.forEach(function (m) {
      var row = rows[m], v = state.picks[m];
      var wantsAlts = v === NONE || isAlt(v);
      DATA.sets.forEach(function (set) {
        var c = cells[key(set.id, m)];
        c.radio.checked = v === set.id;
        c.radio.disabled = state.locked || c.missing;
        c.td.classList.toggle("picked", v === set.id);
      });
      row.noneRadio.checked = v === NONE;
      row.noneRadio.disabled = state.locked;
      row.noneTd.classList.toggle("picked", v === NONE);
      for (var n = 1; n <= ALT_COUNT; n++) {
        var alt = alts[m + "-" + n];
        if (wantsAlts) startAlt(m, n);
        var show = wantsAlts && alt.found;
        alt.box.hidden = !show;
        alt.radio.checked = v === ROUND2_PREFIX + m + "-" + n;
        alt.radio.disabled = state.locked;
        alt.td.classList.toggle("picked", alt.radio.checked);
        if (show) altShown[n - 1] = true;
      }
    });
    altShown.forEach(function (shown, i) {
      altHeads[i].hidden = !shown;
      PICKABLE.forEach(function (m) { rows[m].altTds[i].hidden = !shown; });
    });
    var extra = altShown.filter(Boolean).length;
    sharedTds.forEach(function (td) { td.colSpan = 1 + extra; });
    groupHeads.forEach(function (th) { th.colSpan = DATA.sets.length + 2 + extra; });
    counterEl.textContent = count + " of " + PICKABLE.length + " picked";
    lockBtn.disabled = count < PICKABLE.length;
    lockBtn.hidden = state.locked;
    unlockBtn.hidden = !state.locked;
    allBtns.forEach(function (b) { b.disabled = state.locked; });
    summaryEl.hidden = !state.locked;
    if (state.locked) fillSummary();
  }
  function fillSummary() {
    var body = document.getElementById("summary-body"), nones = [];
    body.textContent = "";
    PICKABLE.forEach(function (m) {
      var tr = el("tr"), th = el("th", "", m);
      th.scope = "row";
      tr.appendChild(th);
      tr.appendChild(el("td", "", pickLabel(state.picks[m])));
      body.appendChild(tr);
      if (state.picks[m] === NONE) nones.push(m);
    });
    document.getElementById("summary-note").textContent = nones.length
      ? nones.length + " moment" + (nones.length === 1 ? "" : "s") + " set to none: " + nones.join(", ") +
        ". They get a second round; then pick and lock in again."
      : "Every moment has a version. This is the mix that ships.";
    document.getElementById("mine-json").textContent = mineText();
  }

  function pickHandler(moment, value) {
    return function () { if (state.locked) return; state.picks[moment] = value; change(); };
  }
  function useForAll(set) {
    if (state.locked) return;
    PICKABLE.forEach(function (m) { state.picks[m] = set; });
    change();
  }

  // --- header: one column per set (run-through, use for all), then None of these and Alt 1 to 3 ---
  var head = document.getElementById("head");
  DATA.sets.forEach(function (s) {
    var th = el("th"); th.scope = "col";
    var box = el("div", "set-h");
    box.appendChild(el("b", "", s.title));
    box.appendChild(el("span", "", s.voice));
    var runBtn = el("button", "", "Play the whole set");
    runBtn.type = "button"; runBtn.id = "run-" + s.id;
    runBtn.addEventListener("click", function () { runSet(s.id, runBtn); });
    var allBtn = el("button", "", "Use this set for all");
    allBtn.type = "button"; allBtn.id = "all-" + s.id;
    allBtn.addEventListener("click", function () { useForAll(s.id); });
    allBtns.push(allBtn);
    box.appendChild(runBtn); box.appendChild(allBtn);
    th.appendChild(box); head.appendChild(th);
  });
  (function () {
    var th = el("th"); th.scope = "col";
    var box = el("div", "set-h");
    box.appendChild(el("b", "", "None of these"));
    box.appendChild(el("span", "", "nothing fits: gets a second round"));
    th.appendChild(box); head.appendChild(th);
    for (var n = 1; n <= ALT_COUNT; n++) {
      var alt = el("th"); alt.scope = "col"; alt.hidden = true;
      var abox = el("div", "set-h");
      abox.appendChild(el("b", "", "Alt " + n));
      abox.appendChild(el("span", "", "round two"));
      alt.appendChild(abox); head.appendChild(alt); altHeads.push(alt);
    }
  })();

  // --- body: a group heading, then one row per slot ---
  function makeAlt(slot, n, tr) {
    var td = el("td", "alt"), c = newCell(slot, "Alt " + n, "pick-" + slot, ROUND2_PREFIX + slot + "-" + n);
    c.td = td; c.box.hidden = true; td.hidden = true;
    c.radio.addEventListener("change", pickHandler(slot, ROUND2_PREFIX + slot + "-" + n));
    alts[slot + "-" + n] = c;
    td.appendChild(c.box); tr.appendChild(td);
    return td;
  }
  var table = document.getElementById("grid");
  GROUPS.forEach(function (g) {
    var tbody = el("tbody");
    var gr = el("tr", "group"), gh = el("th", "", g[1]);
    groupHeads.push(gh); gr.appendChild(gh); tbody.appendChild(gr);
    DATA.slots.filter(function (s) { return s.kind === g[0]; }).forEach(function (s) {
      var pickable = PICKABLE.indexOf(s.slot) >= 0;
      var tr = el("tr");
      var th = el("th"); th.scope = "row";
      th.appendChild(el("div", "name", s.slot));
      th.appendChild(el("div", "when", s.when));
      var chips = el("div", "chips");
      if (s.kind === "tick") {
        chips.appendChild(el("span", "chip", "no layers"));
      } else {
        chips.appendChild(el("span", "chip", "touch: " + s.mood));
        if (s.signature) chips.appendChild(el("span", "chip sig", s.dark ? "signature, dark" : "signature"));
      }
      th.appendChild(chips); tr.appendChild(th);
      DATA.sets.forEach(function (set) {
        var td = el("td");
        var c = newCell(s.slot, set.title, pickable ? "pick-" + s.slot : null, set.id);
        c.td = td;
        cells[key(set.id, s.slot)] = c;
        if (pickable) c.radio.addEventListener("change", pickHandler(s.slot, set.id));
        startCell(c, BASE + set.id + "/" + s.slot + ".wav", function () { setStatus(); render(); });
        td.appendChild(c.box); tr.appendChild(td);
      });
      if (pickable) {
        var noneTd = el("td"), label = el("label", "none-pick"), radio = el("input");
        radio.type = "radio"; radio.name = "pick-" + s.slot; radio.value = NONE;
        radio.setAttribute("aria-label", "None of these for " + s.slot);
        radio.addEventListener("change", pickHandler(s.slot, NONE));
        label.appendChild(radio); label.appendChild(el("span", "", "None of these"));
        noneTd.appendChild(label); tr.appendChild(noneTd);
        var altTds = [];
        for (var n = 1; n <= ALT_COUNT; n++) altTds.push(makeAlt(s.slot, n, tr));
        rows[s.slot] = { noneTd: noneTd, noneRadio: radio, altTds: altTds };
      } else {
        var same = el("td", "same", "same in every set");
        sharedTds.push(same); tr.appendChild(same);
      }
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);
  });

  lockBtn.addEventListener("click", function () {
    if (Object.keys(state.picks).length < PICKABLE.length) return;
    state.locked = true;
    change();
    if (summaryEl.scrollIntoView) summaryEl.scrollIntoView();
  });
  unlockBtn.addEventListener("click", function () { state.locked = false; change(); });
  mixBtn.addEventListener("click", function () {
    var q = mixQueue();
    runQueue(mixBtn, "Play my mix", q.queue,
             "my mix" + (q.skipped.length ? " (no sound yet for " + q.skipped.join(", ") + ")" : ""));
  });

  state = loadState();
  setStatus();
  render();

  // colour theme, remembered in this browser only
  var themeBtn = document.getElementById("theme");
  function applyTheme(t) {
    document.documentElement.setAttribute("data-theme", t);
    themeBtn.textContent = t === "dark" ? "Light" : "Dark";
  }
  var savedTheme = readStore(THEME_KEY);
  if (savedTheme === "dark" || savedTheme === "light") applyTheme(savedTheme);
  else applyTheme(window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark");
  themeBtn.addEventListener("click", function () {
    var next = document.documentElement.getAttribute("data-theme") === "dark" ? "light" : "dark";
    writeStore(THEME_KEY, next); applyTheme(next);
  });
})();
</script>
</body></html>
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s tests -p test_sound_build.py`
Expected: `Ran 143 tests`, `OK` (Task 2's 135 plus 8 new). C1's `TestAuditionPage` tests still pass against the replaced page, the slot-table test and the two literals of the `38a6b1c` fix among them.

Then check C1's fixes in the page one by one (the page was replaced in full):

```bash
grep -c 'if (current !== c) return;' design/sounds/audition.html
grep -c 'endRun(); setStatus(); playCell(c);' design/sounds/audition.html
grep -c 'the ticks, yawn, work and gulp are the same in all four (search is made in code in three sets and a recorded chatter in Best of)' design/sounds/audition.html
```

Expected: `1`, `1` and `1`.

- [ ] **Step 5: Check the command line on the real clips** (the scratch recipes live under `.claude/c1b/`, which is git-ignored; nothing is written to `design/sounds/sets/`)

Build the four sets first, then a complete scratch `mine.json` that mixes all four sets, and compare every picked file with the set's own built file:

```bash
cd "$(git rev-parse --show-toplevel)"
bash scripts/test-sound-build.sh --real
```

Expected: `Ran 143 tests` and `OK` (no skips when the clips are found), `recipes ok: 4 sets x 28 slots`, `clips ok in ...`, four `built <set>: 28 files in ...` lines and `report: ... (112 of 112 files meet their targets)`. Exit code 0.

```bash
cd "$(git rev-parse --show-toplevel)"
rm -rf .claude/c1b && mkdir -p .claude/c1b/sets && cp design/sounds/sets/*.json .claude/c1b/sets/
cat > .claude/c1b/sets/mine.json <<'EOF'
{
  "title": "Your mix",
  "picks": {
    "greet": "studio",
    "love": "steff",
    "annoyed": "kitten",
    "dizzy": "bestof",
    "slap": "studio",
    "finish": "steff",
    "error": "kitten",
    "approval": "bestof",
    "question": "studio",
    "proud": "steff",
    "wink": "kitten",
    "sleep": "bestof",
    "think": "studio",
    "search": "kitten",
    "rate": "steff"
  }
}
EOF
python3 tools/sounds/build_pack.py --check-recipes --recipes .claude/c1b/sets
python3 tools/sounds/build_pack.py --set mine --recipes .claude/c1b/sets --report
python3 - <<'EOF'
import hashlib, json, os
build = ".claude/sounds/build"
picks = json.load(open(".claude/c1b/sets/mine.json"))["picks"]
digest = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()
ok = True
for moment, name in picks.items():
    same = digest("%s/mine/%s.wav" % (build, moment)) == digest("%s/%s/%s.wav" % (build, name, moment))
    ok = ok and same
    print("%-9s %-7s %s" % (moment, name, "identical" if same else "DIFFERENT"))
shared = sorted(f[:-4] for f in os.listdir(build + "/studio") if f[:-4] not in picks)
for slot in shared:
    for name in ("studio", "steff", "kitten", "bestof"):
        ok = ok and digest("%s/mine/%s.wav" % (build, slot)) == digest("%s/%s/%s.wav" % (build, name, slot))
print("%d shared sounds checked against all four sets" % len(shared))
print("ALL OK" if ok else "MISMATCH")
EOF
```

Expected: `recipes ok: 4 sets x 28 slots`, `mine.json ok: 15 picks, 0 none`, `clips ok in ...`, `built mine: 28 files in .../.claude/sounds/build/mine`, `report: ... (28 of 28 files meet their targets)`; then 15 lines ending `identical` (Kitten and Best of picks among them, so the carried pitch is right on the real recipes), `13 shared sounds checked against all four sets` and `ALL OK`.

Then a `none` must refuse, and round two must build next to the page's folder:

```bash
cd "$(git rev-parse --show-toplevel)"
rm -rf .claude/c1b/sets-none && cp -R .claude/c1b/sets .claude/c1b/sets-none
sed -i '' 's/"rate": "steff"/"rate": "none"/; s/"search": "kitten"/"search": "none"/' .claude/c1b/sets-none/mine.json
python3 tools/sounds/build_pack.py --set mine --recipes .claude/c1b/sets-none --out .claude/c1b/none-out --report; echo "exit $?"
ls .claude/c1b/none-out
cat > .claude/c1b/sets-none/round2.json <<'EOF'
{
  "set": "round2",
  "entries": [
    {"id": "rate-1", "slot": "rate", "source": "rate/fs-64011-Department64.mp3", "start": 0.05, "end": 0.5, "effects": [{"type": "thump"}], "mood": "upset", "signature": false, "note": "kitten16, a short grumble, then the tail thump."},
    {"id": "rate-2", "slot": "rate", "source": "rate/fs-730098-Sadiquecat.mp3", "start": 0.2, "end": 0.9, "pitch_st": -1.0, "mood": "upset", "signature": false, "note": "Sadiquecat's meow from 0.2 s, a little lower."}
  ]
}
EOF
python3 tools/sounds/build_pack.py --round2 --recipes .claude/c1b/sets-none --report; echo "exit $?"
ls .claude/sounds/build/round2
grep -A5 "## round2" .claude/sounds/build/round2/report.md
```

Expected: the refusal prints `mine: Your mix is not ready to build, still none: search, rate. Pick them on design/sounds/audition.html ...`, then `exit 2`, and `ls` says `No such file or directory` (nothing was written). The round-two build prints `built round2: 2 files in .../.claude/sounds/build/round2`, `no round-two alternative for: search` (search is still none and has no alternative; rate has two), a `report:` line ending `(2 of 2 files meet their targets)`, `exit 0`; the folder holds `rate-1.wav`, `rate-2.wav` and `report.md`; the report section starts `## round2: 2 of 2 pass` and its rows are named `rate-1` and `rate-2`.

- [ ] **Step 6: Check the page in a headless browser** (Review Focus 5)

The built-in browser pane renders local files as static snapshots, so use `playwright-cli`, as C1 did, in a **named session** (`-s=c1b`) so it never touches another session's browser. Serve the worktree the way the owner will (a static server with a deep connection queue, see "From the page to `mine.json`" above) on a free local port: the checks use 8771, so pick another if it is taken, and never use 8768, which the owner's own preview server may hold. Each `eval` below returns one JSON line to compare with the expected one. The round-two folder from Step 5 (with `rate-1.wav` and `rate-2.wav`) must exist. (The page also works over `file://`, with `{"allowUnrestrictedFileAccess": true}` in the session's `.playwright/cli.config.json`; the checks give the same results, apart from the wording of the console errors.)

Start the server, open the page, then check the first state:

```bash
cd "$(git rev-parse --show-toplevel)"
mkdir -p .claude/c1b .claude/pw
python3 - 8771 "$(pwd)" <<'EOF' > .claude/c1b/server.log 2>&1 &
import functools, http.server, sys

class Server(http.server.ThreadingHTTPServer):
    request_queue_size = 256      # the stock queue is 5: 112 WAVs asked for at once get connection resets
    daemon_threads = True

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/favicon.ico":       # the browser asks once per page; an empty answer keeps the console clean
            self.send_response(204)
            self.end_headers()
        else:
            super().do_GET()

port, root = int(sys.argv[1]), sys.argv[2]
Server(("127.0.0.1", port), functools.partial(Handler, directory=root)).serve_forever()
EOF
echo $! > .claude/c1b/server.pid
sleep 1
cd .claude/pw
playwright-cli -s=c1b open "http://127.0.0.1:8771/design/sounds/audition.html"
playwright-cli -s=c1b console
playwright-cli -s=c1b --raw eval "JSON.stringify({rows: document.querySelectorAll('#grid tbody tr:not(.group)').length, radios: document.querySelectorAll('input[type=radio]').length, play: document.querySelectorAll('td button').length, runs: document.querySelectorAll('[id^=run-]').length, alls: document.querySelectorAll('[id^=all-]').length, status: document.getElementById('status').textContent, counter: document.getElementById('counter').textContent, lockDisabled: document.getElementById('lock').disabled, altHeadsHidden: [...document.querySelectorAll('thead th')].slice(6).map(t => t.hidden), noticeHidden: document.getElementById('missing').hidden})"
```

Expected: `Total messages: 0 (Errors: 0, Warnings: 0)` (no row is none, so no round-two file is probed) and `{"rows":28,"radios":120,"play":157,"runs":4,"alls":4,"status":"112 of 112 files found.","counter":"0 of 15 picked","lockDisabled":true,"altHeadsHidden":[true,true,true],"noticeHidden":true}`.

Picking: Use this set for all, two single picks, then None of these on `rate`, whose Alt cells must appear (only the two files that exist):

```bash
cd "$(git rev-parse --show-toplevel)/.claude/pw"
playwright-cli -s=c1b --raw click "#all-kitten" > /dev/null
playwright-cli -s=c1b --raw eval "JSON.stringify({counter: document.getElementById('counter').textContent, lockDisabled: document.getElementById('lock').disabled, kittenChecked: document.querySelectorAll('input[value=kitten]:checked').length, highlighted: document.querySelectorAll('td.picked').length})"
playwright-cli -s=c1b --raw click "input[name='pick-greet'][value='studio']" > /dev/null
playwright-cli -s=c1b --raw click "input[name='pick-love'][value='bestof']" > /dev/null
playwright-cli -s=c1b --raw click "input[name='pick-rate'][value='none']" > /dev/null
playwright-cli -s=c1b --raw eval "JSON.stringify({counter: document.getElementById('counter').textContent, altHeadsHidden: [...document.querySelectorAll('thead th')].slice(6).map(t => t.hidden), rateAltShown: [1, 2, 3].map(n => { var r = document.querySelector('input[name=pick-rate][value=\"round2:rate-' + n + '\"]'); return !r.closest('.cell').hidden && !r.closest('td').hidden; }), greetAltShown: [1, 2, 3].map(n => { var r = document.querySelector('input[name=pick-greet][value=\"round2:greet-' + n + '\"]'); return !r.closest('.cell').hidden; })})"
playwright-cli -s=c1b console error
```

Expected: `{"counter":"15 of 15 picked","lockDisabled":false,"kittenChecked":15,"highlighted":15}`, then `{"counter":"15 of 15 picked","altHeadsHidden":[false,false,true],"rateAltShown":[true,true,false],"greetAltShown":[false,false,false]}` (none counts as an answer; Alt 1 and Alt 2 exist, Alt 3 does not, and no other row shows an Alt cell), and two console errors, both `Failed to load resource ... 404 (File not found)` for `round2/rate-3.wav`: the browser reporting the probe of a file round two did not build and its one retry (a missing file is asked for twice, 400 ms apart, before the page calls it missing; over `file://` the same two read `ERR_FILE_NOT_FOUND`). This only happens on a row set to none or holding a round-two pick.

Pick an alternative: its Alt cells must stay (controller's ruling), and it must stay changeable. Then set `search` to none, lock in, and check the summary and the text of `mine.json`:

```bash
cd "$(git rev-parse --show-toplevel)/.claude/pw"
playwright-cli -s=c1b --raw click "input[name='pick-rate'][value='round2:rate-2']" > /dev/null
playwright-cli -s=c1b --raw eval "JSON.stringify({picked: document.querySelector('input[name=pick-rate]:checked').value, highlighted: document.querySelector('input[name=pick-rate]:checked').closest('td').classList.contains('picked'), altShown: [1, 2, 3].map(n => !document.querySelector('input[name=pick-rate][value=\"round2:rate-' + n + '\"]').closest('.cell').hidden), altHeadsHidden: [...document.querySelectorAll('thead th')].slice(6).map(t => t.hidden)})"
playwright-cli -s=c1b --raw click "input[name='pick-rate'][value='round2:rate-1']" > /dev/null
playwright-cli -s=c1b --raw eval "document.querySelector('input[name=pick-rate]:checked').value"
playwright-cli -s=c1b --raw click "input[name='pick-rate'][value='round2:rate-2']" > /dev/null
playwright-cli -s=c1b --raw click "input[name='pick-search'][value='none']" > /dev/null
playwright-cli -s=c1b --raw click "#lock" > /dev/null
playwright-cli -s=c1b --raw eval "JSON.stringify({summaryHidden: document.getElementById('summary').hidden, lockHidden: document.getElementById('lock').hidden, unlockHidden: document.getElementById('unlock').hidden, radiosEnabled: document.querySelectorAll('input[type=radio]:not(:disabled)').length, allBtnsEnabled: document.querySelectorAll('[id^=all-]:not(:disabled)').length, note: document.getElementById('summary-note').textContent, firstRows: [...document.querySelectorAll('#summary-body tr')].slice(0, 3).map(r => r.textContent)})"
playwright-cli -s=c1b --raw eval "document.getElementById('mine-json').textContent" | python3 -c "import json, sys; open('../c1b/page-mine.json', 'w').write(json.load(sys.stdin))"
cat ../c1b/page-mine.json
```

Expected: `{"picked":"round2:rate-2","highlighted":true,"altShown":[true,true,false],"altHeadsHidden":[false,false,true]}` (the picked Alt keeps its cells, its dot and its highlight), `"round2:rate-1"` (and it can be changed to another Alt), then `{"summaryHidden":false,"lockHidden":true,"unlockHidden":false,"radiosEnabled":0,"allBtnsEnabled":0,"note":"1 moment set to none: search. They get a second round; then pick and lock in again.","firstRows":["greetStudio","loveBest of","annoyedKitten"]}`, then the JSON text: `{"title": "Your mix", "picks": {...}}` over 15 lines with `greet` studio, `love` bestof, ten moments `kitten`, `search` none and `rate` `round2:rate-2`.

The text must be exactly what the loader reads. Feed it to `--check-recipes` in a copy of the scratch recipes, then complete the mix and build it:

```bash
cd "$(git rev-parse --show-toplevel)"
rm -rf .claude/c1b/page && cp -R .claude/c1b/sets-none .claude/c1b/page && cp .claude/c1b/page-mine.json .claude/c1b/page/mine.json
python3 tools/sounds/build_pack.py --check-recipes --recipes .claude/c1b/page; echo "exit $?"
sed -i '' 's/"search": "none"/"search": "kitten"/' .claude/c1b/page/mine.json
python3 tools/sounds/build_pack.py --set mine --recipes .claude/c1b/page --out .claude/c1b/page-out --report; echo "exit $?"
cmp .claude/c1b/page-out/rate.wav .claude/sounds/build/round2/rate-2.wav && echo "rate is round2/rate-2.wav"
cmp .claude/c1b/page-out/annoyed.wav .claude/sounds/build/kitten/annoyed.wav && echo "annoyed is the Kitten file"
```

Expected: `round2.json ok: 2 alternatives for rate`, `mine.json ok: 15 picks, 1 none (search)`, `clips ok in ...`, `exit 0`; then `built mine: 28 files in ...`, `(28 of 28 files meet their targets)`, `exit 0` and the two `cmp` lines.

Reload (the picks must survive and the page must come back locked), then Change picks:

```bash
cd "$(git rev-parse --show-toplevel)/.claude/pw"
playwright-cli -s=c1b --raw reload > /dev/null
sleep 1
playwright-cli -s=c1b --raw eval "JSON.stringify({counter: document.getElementById('counter').textContent, summaryHidden: document.getElementById('summary').hidden, radiosEnabled: document.querySelectorAll('input[type=radio]:not(:disabled)').length, jsonKeepsNone: document.getElementById('mine-json').textContent.indexOf('\"search\": \"none\"') > 0, altHeadsHidden: [...document.querySelectorAll('thead th')].slice(6).map(t => t.hidden), highlighted: document.querySelectorAll('td.picked').length})"
playwright-cli -s=c1b --raw click "#unlock" > /dev/null
playwright-cli -s=c1b --raw eval "JSON.stringify({summaryHidden: document.getElementById('summary').hidden, lockHidden: document.getElementById('lock').hidden, lockDisabled: document.getElementById('lock').disabled, radiosEnabled: document.querySelectorAll('input[type=radio]:not(:disabled)').length, storedLocked: JSON.parse(window.localStorage.getItem('notchmeow.audition.picks')).locked})"
```

Expected: `{"counter":"15 of 15 picked","summaryHidden":false,"radiosEnabled":0,"jsonKeepsNone":true,"altHeadsHidden":[false,false,true],"highlighted":15}`, then `{"summaryHidden":true,"lockHidden":false,"lockDisabled":false,"radiosEnabled":120,"storedLocked":false}`.

Play my mix. The page cannot play sound here, so replace `play()` with a recorder (it also ends each sound at once; the 450 ms gaps remain, so the run takes about 13 s), then read which files it asked for:

```bash
cd "$(git rev-parse --show-toplevel)/.claude/pw"
playwright-cli -s=c1b --raw eval "(function () { window.__played = []; HTMLMediaElement.prototype.play = function () { var a = this; window.__played.push(a.src.split('/build/')[1]); setTimeout(function () { if (a.onended) a.onended(); }, 0); return Promise.resolve(); }; })()" > /dev/null
playwright-cli -s=c1b --raw click "#play-mix" > /dev/null
sleep 1
playwright-cli -s=c1b --raw eval "document.getElementById('status').textContent + ' | button: ' + document.getElementById('play-mix').textContent"
sleep 14
playwright-cli -s=c1b --raw eval "JSON.stringify({button: document.getElementById('play-mix').textContent, n: window.__played.length, played: window.__played})"
```

Expected: while running `Playing my mix (no sound yet for search): dizzy (4 of 27) | button: Stop`; at the end `{"button":"Play my mix","n":27,"played":[...]}` with the 27 files in slot order: `studio/greet.wav`, `bestof/love.wav`, `kitten/annoyed.wav`, `kitten/dizzy.wav`, `kitten/slap.wav`, `kitten/finish.wav`, `kitten/error.wav`, `kitten/approval.wav`, `kitten/question.wav`, `kitten/proud.wav`, `kitten/wink.wav`, `studio/yawn.wav`, `kitten/sleep.wav`, `studio/gulp.wav`, `kitten/think.wav`, `studio/work.wav`, `round2/rate-2.wav`, then the ten ticks from `studio/` (`approve`, `peek`, `open`, `close`, `hover`, `blip`, `tick`, `send`, `attach`, `pop`). `search` is skipped (none) and named in the status; the shared sounds come from the first set's folder.

Stop in the middle of the run, then the cases that must not break the page (stale, garbled and unavailable storage, a locked page that no longer has 15 valid picks, a missing set folder):

```bash
cd "$(git rev-parse --show-toplevel)/.claude/pw"
playwright-cli -s=c1b --raw click "#play-mix" > /dev/null; sleep 1.2
playwright-cli -s=c1b --raw click "#play-mix" > /dev/null; sleep 1
playwright-cli -s=c1b --raw eval "JSON.stringify({button: document.getElementById('play-mix').textContent, status: document.getElementById('status').textContent})"
playwright-cli -s=c1b --raw eval "window.localStorage.setItem('notchmeow.audition.picks', JSON.stringify({picks: {greet: 'bogus', love: 'studio', rate: 'round2:rate-9', annoyed: 'round2:greet-1', dizzy: 7, constructor: 'studio', slap: 'kitten'}, locked: true}))" > /dev/null
playwright-cli -s=c1b --raw reload > /dev/null; sleep 1
playwright-cli -s=c1b --raw eval "JSON.stringify({counter: document.getElementById('counter').textContent, summaryHidden: document.getElementById('summary').hidden, lockDisabled: document.getElementById('lock').disabled, checked: [...document.querySelectorAll('input[type=radio]:checked')].map(r => r.name + '=' + r.value)})"
playwright-cli -s=c1b --raw eval "window.localStorage.setItem('notchmeow.audition.picks', '{not json')" > /dev/null
playwright-cli -s=c1b --raw reload > /dev/null; sleep 1
playwright-cli -s=c1b --raw eval "JSON.stringify({counter: document.getElementById('counter').textContent, rows: document.querySelectorAll('#grid tbody tr:not(.group)').length})"
playwright-cli -s=c1b --raw eval "(function () { var p = {}; ['greet','love','annoyed','dizzy','slap','finish','error','approval','question','proud','wink','sleep','think','search'].forEach(function (m) { p[m] = 'studio'; }); p.rate = 'round2:rate-3'; window.localStorage.setItem('notchmeow.audition.picks', JSON.stringify({picks: p, locked: true})); })()" > /dev/null
playwright-cli -s=c1b --raw reload > /dev/null; sleep 2
playwright-cli -s=c1b --raw eval "JSON.stringify({counter: document.getElementById('counter').textContent, summaryHidden: document.getElementById('summary').hidden, lockHidden: document.getElementById('lock').hidden, storedLocked: JSON.parse(window.localStorage.getItem('notchmeow.audition.picks')).locked})"
playwright-cli -s=c1b --raw run-code "async page => { await page.addInitScript(() => { Object.defineProperty(window, 'localStorage', { get() { throw new DOMException('blocked', 'SecurityError'); } }); }); await page.reload(); }" > /dev/null
sleep 1
playwright-cli -s=c1b --raw click "#all-bestof" > /dev/null; playwright-cli -s=c1b --raw click "#lock" > /dev/null
playwright-cli -s=c1b --raw eval "JSON.stringify({rows: document.querySelectorAll('#grid tbody tr:not(.group)').length, counter: document.getElementById('counter').textContent, summaryHidden: document.getElementById('summary').hidden})"
playwright-cli -s=c1b console error
```

Expected, in order: `{"button":"Play my mix","status":"112 of 112 files found."}` (Stop ends the run); stale storage `{"counter":"2 of 15 picked","summaryHidden":true,"lockDisabled":true,"checked":["pick-love=studio","pick-slap=kitten"]}` (only the two valid picks survive, and the page is not locked); garbled storage `{"counter":"0 of 15 picked","rows":28}`; a page stored as locked whose round-two file is gone `{"counter":"14 of 15 picked","summaryHidden":true,"lockHidden":false,"storedLocked":false}` (the pick with no file is dropped and the page unlocks: it never stays locked below 15 of 15); with `localStorage` throwing `{"rows":28,"counter":"15 of 15 picked","summaryHidden":false}` (picking and Lock in still work for the session); and `Total messages: 0 (Errors: 0, Warnings: 0)` for the last `console error`.

A request that fails once, which is what a busy server does on a cold load, must not make a file read as missing (controller's ruling: the retry stays). Drop the first request for one file at the network level, reload, and see that the retry fetched it:

```bash
cd "$(git rev-parse --show-toplevel)/.claude/pw"
playwright-cli -s=c1b --raw run-code "async page => { let drops = 0; await page.route('**/build/studio/greet.wav', route => { if (drops++ < 1) route.abort('connectionreset'); else route.continue(); }); await page.reload(); await page.waitForTimeout(2000); }" > /dev/null
playwright-cli -s=c1b --raw eval "JSON.stringify({status: document.getElementById('status').textContent, noticeHidden: document.getElementById('missing').hidden})"
playwright-cli -s=c1b console error
```

Expected: `{"status":"112 of 112 files found.","noticeHidden":true}` and `Total messages: 1 (Errors: 1, Warnings: 0)`, the one `net::ERR_CONNECTION_RESET` for `studio/greet.wav` that the browser logged for the dropped request. Without the retry the same drop reads `111 of 112 files found; run build_pack.py --all for the rest.` and shows the notice.

Finally the missing-folder case, stop the server, and put everything back:

```bash
cd "$(git rev-parse --show-toplevel)"
mv .claude/sounds/build/kitten .claude/sounds/build/kitten.off
cd .claude/pw
playwright-cli -s=c1b --raw reload > /dev/null; sleep 1.5
playwright-cli -s=c1b --raw click "#all-kitten" > /dev/null
playwright-cli -s=c1b --raw eval "JSON.stringify({status: document.getElementById('status').textContent, noticeHidden: document.getElementById('missing').hidden, kittenDotsDisabled: document.querySelectorAll('input[value=kitten]:disabled').length})"
playwright-cli -s=c1b --raw eval "(function () { window.__played = []; HTMLMediaElement.prototype.play = function () { var a = this; window.__played.push(a.src.split('/build/')[1]); setTimeout(function () { if (a.onended) a.onended(); }, 0); return Promise.resolve(); }; })()" > /dev/null
playwright-cli -s=c1b --raw click "#play-mix" > /dev/null; sleep 11
playwright-cli -s=c1b --raw eval "JSON.stringify({n: window.__played.length, first: window.__played.slice(0, 3)})"
playwright-cli -s=c1b close
cd ../.. && mv .claude/sounds/build/kitten.off .claude/sounds/build/kitten
kill "$(cat .claude/c1b/server.pid)" && rm .claude/c1b/server.pid
ls .claude/sounds/build
```

Expected: `{"status":"84 of 112 files found; run build_pack.py --all for the rest.","noticeHidden":false,"kittenDotsDisabled":15}` (the missing-files notice shows and the Kitten dots are disabled); then `{"n":13,"first":["studio/yawn.wav","studio/gulp.wav","studio/work.wav"]}`: all 15 picks are Kitten, whose files are missing, so Play my mix plays only the 13 shared sounds (taken from the Studio folder) and its status names the 15 moments it skipped. The last `ls` lists `bestof kitten mine report.md round2 steff studio`: the Kitten folder is back.

- [ ] **Step 7: Check nothing forbidden is staged or tracked**

```bash
cd "$(git rev-parse --show-toplevel)"
git status --short
git ls-files | grep -E '\.wav$|^\.claude/|design/sounds/sets/(mine|round2)\.json' || echo "no wav, nothing under .claude, no mine.json or round2.json is tracked"
```

Expected: `git status --short` lists only `design/sounds/audition.html` and `tests/test_sound_build.py` (everything from Tasks 1 and 2 is already committed; `.claude/` is ignored), and the second command prints `no wav, nothing under .claude, no mine.json or round2.json is tracked`.

- [ ] **Step 8: Commit**

```bash
git add design/sounds/audition.html tests/test_sound_build.py
git commit -m "design(sounds): pickers, Lock in and Your mix on the audition page" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


---

## Interfaces for Stages 2 and 3

Nothing here builds them; this is what they can rely on.

- **Stage 2 (final pack, licences).** Once `mine.json` has no `none`: `python3 tools/sounds/build_pack.py --set mine --candidates <folder of originals> --out NotchBuddy/Resources/sounds --report` writes Your mix's 28 `<slot>.wav` files and a report (`--out` is the folder the WAVs go to, as for a set). The list of clips to take from Freesound and to credit is `recipe.load_mine(path, sets, round2)`: its entries' `source` fields (skip `synth:` ones), and the shipped `sources.json` / `SOUND-CREDITS.md` come from that list. Only the recipe `source` names change when the originals replace the previews; the picked windows and pitches carry over because the mix is made of copies of the sets' entries. `recipe._check_source` is still where "the build refuses any source without a verified CC0 entry" belongs, and it applies to round-two entries too (they go through `parse_entry`).
- **Stage 3 (wiring, per-cat voice).** No change: the 28 files carry no per-cat pitch, and the file names are the slot names. `recipe.pickable_moments` is the list of moments whose version the owner chose; the other 13 are the same in every set.

## Spec coverage

| Spec item ("Picking per moment" unless noted) | Where |
|---|---|
| What is pickable: the 15 moments, the 13 shared sounds labelled "same in every set" | Task 1 `pickable_moments` and its pin against the spec's list; Task 3 page (`pickable` in the data block, the "same in every set" cells, `test_the_pickable_moments_are_the_specs_fifteen_and_the_recipes`, `test_the_other_thirteen_rows_are_the_shared_sounds`) |
| Select dot per set cell plus None of these, chosen cell highlighted | Task 3 (`input[type=radio]`, `td.picked`, `none-pick` cell) |
| Use this set for all, per set column | Task 3 (`all-<set>` buttons, `useForAll`) |
| Counter "N of 15 picked", none counts | Task 3 (`counter`, `render`) |
| Play my mix: 28 in order from the built set files, shared sounds from any set's folder, reusing the run-through | Task 3 (`mixQueue`, `runQueue`, shared with `runSet`; headless check of the 27-file list) |
| Lock in at 15 of 15, summary, Change picks | Task 3 (`lock`, `unlock`, `fillSummary`; the lock invariant in `render`) |
| Picks in `localStorage` inside try/catch, a convenience only | Task 3 (`readStore`, `writeStore`, `loadState`, `test_picks_are_stored_only_inside_try_catch`, headless storage checks) |
| The main session reads the summary from the page and writes `mine.json` | Task 3 (`#mine-json` holds the exact text; checked against the loader in step 6); "From the page to `mine.json`" above |
| `mine.json` shape; loader copies the entry and carries the set's pitch; round two keeps its own pitch; the 13 shared from `_shared.json` | Task 1 (`read_mix`, `mix_recipe`, `load_mine`; `test_a_mix_copies_each_picked_entry_and_carries_its_sets_pitch`) |
| Checks: all 15 moments, each once; unknown name is an error; a shared sound is an error | Task 1 (`test_every_moment_exactly_once`, `test_a_typo_names_both_...`, `test_a_shared_sound_cannot_be_listed`, `test_unknown_picks_are_errors`) |
| `none` may sit in the file, `--set mine` refuses and names the moments | Task 1 `MixPending`; Task 2 (`test_set_mine_refuses_while_any_moment_is_none_and_names_them`) |
| Build: same pipeline, checks and own report section; every picked file byte-identical to its source's file, pinned by a test | Task 1 (`test_every_picked_file_is_byte_identical_to_its_sources_file`), Task 2 (`--set mine`, `test_set_mine_builds_the_picks_byte_identical_...`), Task 3 step 5 (real clips) |
| Round two: ordinary entries `<moment>-<n>`, mood and signature fixed by the slot table, source checks apply, no reuse of a set's exact window | Task 1 (`load_round2` and its tests) |
| `build_pack.py --round2` to `.claude/sounds/build/round2/`, its own report section; "the round-two report says so" when nothing fits | Task 2 (`--round2`, `ROUND2_DIR`, `render_waiting`, stale files removed) |
| The page adds Alt 1 to 3 columns to those rows only (ruling: rows set to none **and rows already holding a round-two pick**, so a picked Alt stays visible and changeable) | Task 3 (probing `round2/<moment>-<n>.wav`; why: see the Task 3 introduction; `test_alt_cells_stay_on_a_row_that_holds_a_round_two_pick`, the Alt checks of step 6) |
| Rulings on the draft's open questions: the 400 ms retry on a cell that fails a cold load is kept; `--all` does not build `mine` | Task 3 (`startCell`, `test_a_file_that_fails_to_load_is_asked_for_once_more_after_400_ms`, the dropped-request check of step 6); Task 2 (`test_all_builds_the_four_sets_only_and_never_mine`, `test_a_broken_mine_json_stops_mine_and_the_check_but_not_the_four_sets`) |
| C1's merged fixes survive the full-file replacements | "C1's fixes this plan keeps" (File Structure); Task 2 step 5 (`build_pack.py`); Task 3 step 4 (the page); Task 1 `test_round_two_files_get_the_loaders_strictness_too` |
| Section 6, Checks: "Your mix: every picked file is byte-identical to its source's file, and a mix with a moment still none can't build for shipping" | Tasks 1 and 2 as above |
| Stages, step 1b | the whole plan |
| Docs: a note on picking and locking in where C1 documents `build_pack.py` usage | Task 2 (the `build_pack.py` usage text) and Task 3 (the page's header comment) |
