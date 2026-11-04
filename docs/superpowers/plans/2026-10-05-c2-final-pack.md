# Final Sound Pack (C, Stage 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Your mix as one WAV per slot in `NotchBuddy/Resources/sounds/` (29 once `c1c-hairball` has added the hairball), rebuilt from the full-quality Freesound originals that the owner downloads, with a machine-readable, re-checked CC0 source list (`design/sounds/sources.json`), a credits file (`docs/SOUND-CREDITS.md`) and the `LICENSE-ASSETS.md` carve-out.

**Architecture:** Three small Python modules join the stage-1 build. `sources.py` holds the source list, the licence gate and the text of the credits and the download list. `align.py` is the rule that says an original still holds the sound a preview window held. `originals.py` pins, aligns and credits the downloaded originals and loads them for the build. `build_pack.py --set mine --originals` builds from them, and it is the only build allowed to write the shipping folder, which holds one WAV per slot and nothing else. A recipe window is decided once, on the preview the owner auditioned, then pinned in `sources.json` and applied to the original, so Your mix keeps its windows. Only the owner downloads anything.

**Tech Stack:** Python 3 (3.9 compatible, standard library only), macOS `afconvert`, `unittest`, Markdown.

**Spec:** `docs/superpowers/specs/2026-10-04-sounds-design.md`: "Stages" step 2, section 5 "Licences and credits", section 6 "Checks" and the "Risks" on previews against originals. It builds on stages 1 and 1b (merged): `tools/sounds/`, `design/sounds/sets/mine.json` (the owner's lock-in, commit `cbc771e`) and `tests/test_sound_build.py`. It differs from the spec in two places, on purpose. Section 5 offers a download through the owner's signed-in Chrome; the owner ruled that out, so only the owner downloads. Section 6's tick tolerance of ±1.5 LU was never in the code, which held ±2.0; Task 1 puts the spec's number in the code.

**Base:** branch `c2/final-pack`, created from `notchmeow/rebrand` **after `c1c-hairball` has merged**, with this plan file already committed there. `c1c-hairball` adds the 29th slot, `hairball`, to `recipe.SLOTS` and `_shared.json`, plus the build's placed-segments and made-in-code layer (spec, "Hairball" and Stage 1c); Stage 2 needs all of it, because the hairball's one recorded clip is on the list of originals and its three windows are checked like any other. The plan touches no Swift, Rust or TypeScript and no recipe: `design/sounds/sets/*.json` stay exactly as they are. (How this was replayed, since `c1c-hairball` was not merged yet: see "Replay record".)

**What this plan takes from `c1c-hairball`,** read from its plan (`docs/superpowers/plans/2026-10-05-c1c-hairball.md`, Tasks 2 and 3) because Stage 2 comes after it. Counts are never hard-coded: they come from `recipe.SLOTS` (29), `sources.file_sources(mine)` (23 clips) and the windows of each entry. The hairball is one entry of `_shared.json` with the source `"placed"`: `segments` is a list of dicts, one per window of a recorded clip (`source`, `start`, `end` in seconds on the clip, and `at`, `level`, `fade_in_ms`, `fade_out_ms`), and `synth_layers` a list of dicts for the made-in-code retch and plop; the entry's own `start` and `end` cut the finished timeline and are not a clip window. All three segments come from `hairball/fs-561726-har2h.mp3` (windows 2.143-2.558, 4.196-4.576 and 7.278-7.658 s). Stage 2 reads that shape in exactly two functions, `sources.clip_uses` (Task 2) and `originals.with_windows` (Task 4), and their tests build their own stand-in entries in that shape; if c1c's merged recipe differs from its plan, **change those two functions and nothing else**, and say so in the report. Task 1, Step 1 checks the base before anything is written.

c1c's plan also lists three things it hands to Stage 2 (its "Overlap with the Stage 2 plan"). This plan meets them without touching a recipe: (1) *the segment sources move from the preview to the original, the windows are re-measured and the tests re-pinned*: every recipe stays on its preview source, the originals are mapped through `sources.json`, the offset between original and preview is measured and applied (Task 4) and each of the three windows is checked on the original (Task 7), so c1c's byte-for-byte test against `B.wav` keeps working on the preview; (2) *`sources.json` and `SOUND-CREDITS.md` need har2h's CC0 entry*: it is one of the 23 clips of the list (Tasks 2, 5, 7 and 8); (3) *the 29 WAVs, and the README lists naming 28*: Task 8 rewrites `NotchBuddy/Resources/sounds/README.md` and fixes the line "The 28 sounds" in `windows/README.md`.

## Execution

One worktree chat session runs the whole plan: branch `c2/final-pack`, model **Sonnet 5.5 at medium effort** (ARCHITECT.md: a plan whose tasks are mostly given in full). Nothing is pushed. The session stops twice for the owner: at Task 6, for the downloads, and at Task 8, for the listen.

**Before the session starts,** the plan file is committed to `notchmeow/rebrand` (a docs-only commit): the controller does this, with the owner's OK, so the branch the session starts from already holds the plan it runs. **The base is `notchmeow/rebrand` after `c1c-hairball` has merged:** the session's branch is made from it as it is then, `git merge-base --is-ancestor cbc771e HEAD` must succeed, and `hairball` must be in `recipe.SLOTS`.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run `git switch -c c2/final-pack notchmeow/rebrand`, then `git merge-base --is-ancestor cbc771e HEAD`, `git ls-files docs/superpowers/plans/2026-10-05-c2-final-pack.md` and `python3 -c "import sys; sys.path.insert(0, 'tools/sounds'); import recipe; assert 'hairball' in recipe.SLOTS, 'c1c-hairball has not merged'"`: the first must succeed, the second must print the plan's path and the third must succeed. If any fails, say so and stop. Read `CLAUDE.md`, `ARCHITECT.md`, `docs/superpowers/plans/2026-10-05-c2-final-pack.md` and `docs/superpowers/specs/2026-10-04-sounds-design.md`. Reply "ready" and stop. Do not start any task.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at medium effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message:

   > Run `docs/superpowers/plans/2026-10-05-c2-final-pack.md` with `superpowers:subagent-driven-development`, task by task, on this branch. Dispatch each task to the agent the plan names for it, then to `nm-reviewer`; fix what the review finds before the next task. Task 6 is yours alone because it talks to the owner: do what it says and stop until the owner says the originals are in the folder. Never download anything, log in anywhere or touch the owner's browser, and never push; commit only as the plan's commit steps say. When Task 8's commits are in, dispatch `nm-reviewer-deep` over the whole branch and fix what it finds, and only then ask the owner to listen (Task 8, Step 7). When you are done, report: the commits, the test counts (`bash scripts/test-sound-build.sh`), the Task 7 table of offsets and window checks, the line `report: ... files meet their targets` of the ship build, `git status` of the shipping folder, and anything you could not settle.

Before any follow-up turn, the main session checks the session is still on its configured model and effort.

**Agents** (from `CLAUDE.md`). Tasks 1 and 2 hand over complete code and tests, so `nm-implementer-light` transcribes them. Tasks 3 and 4 refactor and integrate (a shared trim, a loader, a build mode), so use `nm-implementer`. Task 5's code is small and complete (`nm-implementer-light`); its run of the re-check goes to a **second, fresh** `nm-implementer-light` dispatch, so the check is independent of whoever wrote the tool. Task 6 is the controller. Tasks 7 and 8 run the tools on real files and read what comes back, so use `nm-implementer`. Each task gets an `nm-reviewer`, and the finished branch an `nm-reviewer-deep`. Fix rounds 4 and 5 go to `nm-implementer-deep`. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`. An implementer running on another model puts that model's name in the commit trailer (for example `Claude Haiku 4.5`).

**Paths.** Every command runs from the worktree root. The git-ignored folders are not in a worktree, so the plan reads and writes them in the **main checkout**, which the owner's browser also saves into. Set these once per shell (the build and the tools also find the previews by themselves, but the originals folder is named explicitly):

```bash
export MAIN="/path/to/notchmeow"
export NM_SOUND_CANDIDATES="$MAIN/.claude/sounds/candidates"
export NM_SOUND_ORIGINALS="$MAIN/.claude/sounds/originals"
```

The tests never read those folders (CI has neither), except the optional checks that say so. Never write anything into `$NM_SOUND_CANDIDATES`.

The invisible `<!-- replay ... -->` comments in front of the code blocks are for the script that replayed this plan (see "Replay record"); ignore them. A block without one (the paths above, the owner's message, the listening loop) is not replayable.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec and the owner's brief.

- **Slots and files.** One `<slot>.wav` for every slot in `recipe.SLOTS` (29 once the hairball is in), 48 kHz, 16-bit, mono. Counts come from `recipe.SLOTS`, never from a number in the code. Shipped: exactly those WAVs, plus `README.md`, in `NotchBuddy/Resources/sounds/`, and no `report.md` or anything else.
- **Targets** (spec sections 2 and 6): short-term loudness −20 LUFS for cat moments and −28 for ticks, both ±1.5 LU; true peak −1 dBTP or lower; lengths up to 1.5 s for cat moments, 3 s for sleep, 0.4 s for ticks.
- **Licence.** Every recorded clip is CC0 as read on its own page; "the build refuses any source without a verified CC0 entry"; `sources.json` is machine-readable; `SOUND-CREDITS.md` and `sources.json` must agree; Coucou's sounds, names and designs never come back.
- **Downloads.** No agent downloads a file, logs in, or uses the owner's browser. The owner downloads the Freesound originals. A direct-link file (BigSoundBank) needs the owner's explicit yes first, naming the file, its source and its size. The only network use in this plan is reading the 22 public clip pages with `curl` (Task 5; its reviewer reads three of them again), saving nothing.
- **The checks on a page.** A page that does not say "Creative Commons 0" with the CC0 link, by the maker `sources.json` names, is not recorded. Nobody edits `sources.json` by hand to make a check pass.
- **Tools.** Python 3 standard library plus macOS `afconvert`. The code runs on Python 3.9 (no `match`, no `X | Y` types at runtime). Output is deterministic: rebuilding gives byte-identical WAVs.
- **The app.** Nothing here launches, quits or replaces the installed NotchMeow app, and `~/Library/Logs/NotchMeow/nm.log` must not grow. Stage 2 changes no app code.
- **Git.** Commits are local and never pushed. Stage files by name, never `git add -A`. Never commit anything under `.claude/` (the previews, originals and builds live there). End every commit message with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`, or the model that wrote it.
- **Repo rules that apply.** The code stays MIT; NotchMeow's own mixes and made-in-code sounds stay under `LICENSE-ASSETS.md`; existing views, cat IDs and pill IDs are untouched.

## Review Focus

The spec says what the pack, the list and the gate must do. It is silent on these inputs, and each would bite the owner (or a later maintainer) first, most likely first. Each line names the tests that pin it.

1. **A wrong file in the originals folder:** the preview MP3 saved instead of the WAV, a browser's second copy (`name (1).wav`), a file that afconvert cannot read, or a file swapped after it was pinned. Expected: named and refused, never guessed at, never built. Tests: `test_a_preview_mp3_saved_by_mistake_is_not_a_wave`, `test_find_original_takes_the_pinned_name_else_the_one_file_named_by_the_id` (Task 2); `test_a_right_original_passes_the_check_and_a_wrong_one_is_named`, `test_a_missing_or_doubled_original_is_a_problem_not_a_crash`, `test_the_loader_refuses_a_file_that_is_not_the_pinned_one` (Task 4).
2. **An original that is not the sound its preview window held:** later or earlier by some milliseconds, a longer tail, hiss that would move an automatic trim, another take of the cat, shorter than the window, at another speed, or (the hairball) one of the three windows of a clip bad while the other two are fine, or the placed sound's own cut (`end` 1.48) read as a window of a clip. Expected: shifted back and built identically when it is the same sound; stopped, with the slot named, when it is not. Tests: `TestAlign` (Task 3); `test_align_finds_the_offset_pins_every_window_and_the_build_matches_the_preview_build`, `test_pinning_keeps_the_previews_window_when_the_originals_noise_floor_would_move_it`, `test_another_take_in_the_original_fails_its_window_and_stops_the_build`, `test_originals_in_other_formats_decode_and_align`, `test_a_slot_that_takes_three_windows_of_one_clip_is_aligned_pinned_and_cut_window_by_window` (Task 4); `test_every_window_of_such_a_slot_is_checked_and_named`, `test_a_placed_sounds_own_cut_is_not_a_clip_window_and_a_layers_only_sound_has_no_source` (Task 2).
3. **A clip that would ship without a verified CC0 entry:** missing from `sources.json`, half a licence entry, a CC-BY page, a page showing two licences or none, a different maker. Expected: the build stops before it writes a file and names the clip. Tests: `test_the_build_refuses_a_source_missing_from_sources_json`, `test_the_build_refuses_a_source_without_a_verified_cc0_entry`, `test_half_a_licence_entry_is_a_shape_error` (Task 2); `TestPageCheck` (Task 5); `test_a_source_missing_from_sources_json_stops_the_build` (Task 4).
4. **Anything but the pack in the shipping folder:** a `report.md` from `--report`, a build from the previews, a leftover. Expected: the report goes elsewhere, a preview build is refused before anything is written, a stray file fails the ship build. Tests: `TestShippingFolder` (Task 1), `test_your_mix_ships_every_slots_wav_and_nothing_else_identical_to_the_preview_build` (Task 4), `TestShippingFolderIsThePack` (Task 8).
5. **`mine.json` or a recipe window edited after the originals were pinned:** the owner swaps a pick later, or a window moves. Expected: the build refuses and names the clip, and a test fails when `sources.json` stops matching Your mix; nothing ships that nobody checked. Tests: `test_sources_json_names_exactly_the_recorded_clips_of_your_mix` (Task 2), `test_a_recipe_window_that_moved_after_pinning_is_refused` (Task 4), `test_every_source_is_verified_pinned_and_checked` (Task 8).

---

## File Structure

| Path | Responsibility |
|---|---|
| `tools/sounds/sources.py` (new) | `design/sounds/sources.json`: shape check, the licence gate, `clip_uses` (the recorded windows of an entry), finding a downloaded original, reading a Freesound page, the text of `docs/SOUND-CREDITS.md` and of the download list. No audio. |
| `tools/sounds/align.py` (new) | The window rule: find the offset between an original and its preview, then say whether a window still holds the same sound. Pure DSP on lists of samples. |
| `tools/sounds/originals.py` (new) | The stage-2 command line (`list`, `pin`, `align`, `credits`, `page`), `OriginalsLoader` (decode a pinned original and move it into preview time), `with_windows` and `pinned_recipe` (every window written out). |
| `tools/sounds/build_pack.py` | The shipping folder (`SHIP_DIR`, `report_path`, `ship_problems`, `refuse_shipping_folder`), `find_folder`, and `--set mine --originals`. |
| `tools/sounds/dsp.py`, `tools/sounds/pipeline.py` | The trims also return where they cut (`*_span`, `source_span`), so a window can be pinned. Same output as before. `TARGETS` takes the spec's tick tolerance. |
| `design/sounds/sources.json` (new) | The source list. Written in Task 2, filled in by Tasks 5 and 7. |
| `design/sounds/audition.html` | Two voice strings made true (Studio, Best of). |
| `docs/SOUND-CREDITS.md` (new) | Generated from `sources.json`; every shipped clip with its maker, page, licence, date checked and the SHA-256 of the original. |
| `NotchBuddy/Resources/sounds/` | One WAV per slot (new) and `README.md` (rewritten). |
| `LICENSE-ASSETS.md`, `CLAUDE.md`, `windows/README.md` | The CC0 carve-out; the sounds folder is no longer described as empty; "The 28 sounds" no longer counts them. |
| `scripts/test-sound-build.sh` | Runs every `tests/test_sound_*.py`. |
| `tests/test_sound_build.py` | The tick-tolerance test and two report strings follow the new target. |
| `tests/sound_pack_support.py` (new) | Helpers the stage-2 tests share (`your_mix`, `blanked`, `voice`, `write_original`, ...). |
| `tests/test_sound_pack.py`, `test_sound_sources.py`, `test_sound_align.py`, `test_sound_originals.py`, `test_sound_page.py`, `test_sound_shipped.py` (new) | One file per task, so each task adds a file instead of editing an import block. |

One-off files (the seed script, the pages list, the page-reading blocks) live in `${TMPDIR:-/tmp}` and are never committed.

**Files touched, all of them:** `tools/sounds/{sources,align,originals}.py` (new), `tools/sounds/{build_pack,dsp,pipeline}.py`, `design/sounds/sources.json` (new), `design/sounds/audition.html`, `docs/SOUND-CREDITS.md` (new), the `NotchBuddy/Resources/sounds/*.wav`, one per slot (new), `NotchBuddy/Resources/sounds/README.md`, `LICENSE-ASSETS.md`, `CLAUDE.md`, `windows/README.md` (one sentence), `scripts/test-sound-build.sh`, `tests/test_sound_build.py`, and the seven new files under `tests/`. Not touched: `design/sounds/sets/*.json`, `NotchBuddy/Sources/`, `NotchBuddy/project.yml`, the rest of `windows/`, `.github/workflows/`, `ARCHITECT.md`.

## Overlap with the cat plans and with Stage 3

Grepped from the `**Files:**` blocks of `2026-10-04-a-mac-cats-stages-1-4.md` and `2026-10-04-a-tauri-cats-stages-1-4.md`:

- **`CLAUDE.md` and `windows/README.md` are the shared files.** Both cat plans have a `Modify:` line naming `CLAUDE.md` (line 9669 of the Mac plan, line 5964 of the Tauri plan) and the Tauri plan names `windows/README.md` too. Stage 2 changes one sentence of each: `CLAUDE.md` line 6 (the sounds folder is no longer "empty until the sounds land") and `windows/README.md` line 135 ("The 28 sounds are the macOS app's own files"). The edits sit in different places of the files, so they merge without a conflict in either order; whoever merges second checks `git diff --stat` on both.
- **Nothing else with the cat plans.** The Mac cat plan also modifies `.github/workflows/build.yml`; Stage 2 does not, because that workflow already runs `bash scripts/test-sound-build.sh`, and only the script's test pattern changes. The cat plans create `tests/Cat*.swift`, `scripts/test-cat-*.sh`, `scripts/render-cat*`, `windows/src/cat/*` and `windows/scripts/cat-tests/*`; Stage 2 creates none of those and none of the cat plans touches `tools/sounds/`, `design/sounds/`, `docs/SOUND-CREDITS.md`, `LICENSE-ASSETS.md` or `NotchBuddy/Resources/sounds/`. The Tauri plan only reads `core/sound.ts`.
- **`c1c-hairball`, which lands first.** Its plan is not written yet; from the spec it touches `tools/sounds/recipe.py`, `pipeline.py` and `synth.py` (perhaps `dsp.py` and `build_pack.py` too), `design/sounds/sets/_shared.json`, `design/sounds/audition.html` and `tests/test_sound_build.py`. Stage 2 edits `dsp.py`, `pipeline.py`, `build_pack.py`, `audition.html` and `tests/test_sound_build.py` as well, so the two plans must not run in parallel: Stage 2 starts after c1c has merged. The text Stage 2's edit scripts anchor on (each stops with "not there exactly once" if it moved) is meant to lie outside what c1c changes: `TARGETS`, two voice strings, `dsp.seconds_slice` and the three trims, the line `def _source(` (an insertion before it; `_source` itself is untouched), the `ROUND2_DIR` line, the refusal point in `main` and the report target. If an anchor did move, make the equivalent edit and say so.
- **Stage 3 (wiring, not in this plan)** will edit `NotchBuddy/Sources/App/SoundEngine.swift`, `windows/src/core/sound.ts` and the call sites the cat plans create (`CatEngine+App.swift`'s `onSound`, `windows/src/cat/engine.ts`), and add `tests/fixtures/sound/rules.json`. That is why it waits for A. Stage 2 writes none of those; Stage 3 only needs Stage 2's files, which keep the slot names.

## What lands with the files

Both apps already look for `<slot>.wav` in this folder (`SoundEngine.swift`, `windows/src/core/sound.ts`) and play the slots they already wire, at the fixed volume 0.12, with none of Stage 3's priority, cooldowns, visibility rules, per-cat voice or chattiness. So once Stage 2 is merged, **both apps start playing Your mix on peek, open, close, hover, greet, finish, error, approval, question, rate, approve, send, tick, blip, pop, slap, annoyed and love**, and stay silent on the rest until Stage 3 (neither app's list of sound names has `hairball` yet, so that WAV is bundled and unused). `NotchBuddy/project.yml` bundles the folder as a resource folder in both Mac targets, so the App Store build carries the whole pack (about 1.8 MB). The plan leaves that as it is and says so; the owner decides, in "Open questions" at the end, whether Stage 2 merges alone.

## The originals list as it stands

23 files, all from Freesound (so all need the owner's sign-in), none from BigSoundBank, about 36 MB in all (5 big ones: 18.4 MB, 8.3 MB, 3.9 MB, 1.8 MB, 1.4 MB). Your mix uses 25 recorded slots: the 24 of the stage-1 mix plus the hairball, whose coughs are three windows of one clip, *Cat Coughing* by har2h (the owner added it on 2026-10-05; the spec's "Hairball" paragraph has the choice, and Electron John's cat vomit, 82543, was not picked, so it is not on the list). `kitten13` serves two slots (annoyed, wink) and `kitten12` two (dizzy, slap), so 25 slots come from 23 files. The other 4 slots (yawn, work, blip, attach) are made in code and have no source; the hairball's retch and plop are made in code too and need none (its entry is a "placed" sound: three windows of the clip laid on a timeline with a made-in-code layer). Sizes, types and durations are what each clip's page said on 2026-10-05 (read through the public pages; the licence on every one of the 23 read "Creative Commons 0"); Task 5 re-reads all of it. Save every file, **without renaming it**, into `$NM_SOUND_ORIGINALS`, that is `/path/to/notchmeow/.claude/sounds/originals/` (git-ignored). Freesound names a download `<id>__<user>__<name>.<ext>`; the tools find each file by the number in front.

| # | Clip (page) | Author | Original, as the page states it | Saved as | Slots and windows taken (seconds on the preview) |
|---|---|---|---|---|---|
| 1 | [kitten22.wav](https://freesound.org/people/Department64/sounds/64017/) | Department64 | WAV, 110.9 KB, 0:00.643 | `64017__….wav` | greet 0.00-0.42 |
| 2 | [Cat short purr](https://freesound.org/people/Mafon2/sounds/436542/) | Mafon2 | WAV, 341.8 KB, 0:01.322 | `436542__….wav` | love (auto) |
| 3 | [kitten13.wav](https://freesound.org/people/Department64/sounds/64008/) | Department64 | WAV, 146.5 KB, 0:00.850 | `64008__….wav` | annoyed (auto), wink 0.45-0.80 |
| 4 | [kitten12.wav](https://freesound.org/people/Department64/sounds/64007/) | Department64 | WAV, 115.5 KB, 0:00.670 | `64007__….wav` | dizzy (auto), slap 0.00-0.30 |
| 5 | [catwhirr.wav](https://freesound.org/people/steffcaffrey/sounds/415107/) | steffcaffrey | WAV, 145.5 KB, 0:00.840 | `415107__….wav` | finish (auto) |
| 6 | [Cute Kitten Meow](https://freesound.org/people/Breviceps/sounds/448084/) | Breviceps | WAV, 104.2 KB, 0:00.604 | `448084__….wav` | error (auto) |
| 7 | [kitten10.wav](https://freesound.org/people/Department64/sounds/64005/) | Department64 | WAV, 111.7 KB, 0:00.648 | `64005__….wav` | approval (auto) |
| 8 | [kitten20.wav](https://freesound.org/people/Department64/sounds/64015/) | Department64 | WAV, 151.7 KB, 0:00.880 | `64015__….wav` | question 0.10-0.60 |
| 9 | [cat chirp.wav](https://freesound.org/people/dreamstobecome/sounds/451250/) | dreamstobecome | WAV, 1.4 MB, 0:07.815 | `451250__….wav` | proud 2.50-3.00 |
| 10 | [Cat purr.wav](https://freesound.org/people/Trautwein/sounds/260881/) | Trautwein | WAV, 8.3 MB, 1:00.103 | `260881__….wav` | sleep 4.00-6.80 |
| 11 | [Cat licking her paw](https://freesound.org/people/Sadiquecat/sounds/730097/) | Sadiquecat | WAV, 1.8 MB, 0:13.375 | `730097__….wav` | gulp 0.00-0.90 |
| 12 | [Cat MmRrm noise](https://freesound.org/people/Sadiquecat/sounds/730102/) | Sadiquecat | WAV, 255.9 KB, 0:01.817 | `730102__….wav` | think 0.30-1.20 |
| 13 | [Cat_Hunting.wav](https://freesound.org/people/16H_Panska_Rudenko_Angelika/sounds/499362/) | 16H_Panska_Rudenko_Angelika | WAV, 18.4 MB, 1:06.775 | `499362__….wav` | search 12.85-13.75 |
| 14 | [kitten17.wav](https://freesound.org/people/Department64/sounds/64012/) | Department64 | WAV, 163.8 KB, 0:00.950 | `64012__….wav` | rate (auto) |
| 15 | [Cat Coughing.wav](https://freesound.org/people/har2h/sounds/561726/) | har2h | WAV, 3.9 MB, 0:20.995 | `561726__….wav` | hairball: three windows of the clip, 2.143-2.558, 4.196-4.576 and 7.278-7.658 (c1c's recipe) |
| 16 | [Cardboard_Small Impact_06.wav](https://freesound.org/people/BenDrain/sounds/487999/) | BenDrain | WAV, 132.2 KB, 0:00.416 | `487999__….wav` | approve (auto) |
| 17 | [Sleigh Bell Short 01.wav](https://freesound.org/people/JoshuaPomeroy/sounds/541360/) | JoshuaPomeroy | WAV, 18.5 KB, 0:00.214 | `541360__….wav` | peek (auto) |
| 18 | [open-cardboard-box-compartment.wav](https://freesound.org/people/newagesoup/sounds/364740/) | newagesoup | WAV, 282.0 KB, 0:01.000 | `364740__….wav` | open 0.22-0.62 |
| 19 | [Item placed](https://freesound.org/people/Mafon2/sounds/320847/) | Mafon2 | WAV, 114.9 KB, 0:00.560 | `320847__….wav` | close 0.20-0.56 |
| 20 | [Water Click](https://freesound.org/people/Mafon2/sounds/371274/) | Mafon2 | WAV, 61.4 KB, 0:00.108 | `371274__….wav` | hover (auto) |
| 21 | [Ceramic Click](https://freesound.org/people/Mafon2/sounds/371278/) | Mafon2 | WAV, 86.5 KB, 0:00.153 | `371278__….wav` | tick (auto) |
| 22 | [pouring cat food](https://freesound.org/people/jimmyfisher/sounds/402453/) | jimmyfisher | WAV, 38.6 KB, 0:00.205 | `402453__….wav` | send (auto) |
| 23 | [Mouth pop](https://freesound.org/people/jcallison/sounds/258269/) | jcallison | **Ogg Vorbis (.ogg)**, 9.2 KB, 0:00.323 | `258269__….ogg` | pop (auto) |

"auto" means the recipe gives no window and the build trims the silence and keeps the loudest part that fits; Task 7 pins what that came to on the preview. The `pop` original is an Ogg Vorbis file, not a WAV. `afconvert` on this Mac (macOS 27.0.1) lists Ogg Vorbis among the formats it reads, but that was only checked against an unrelated Ogg file, never against this one; Task 7 finds out, and "Open questions" has the fallback.

Why previews and originals can differ, measured on the 2026-10-05 candidates: the duration each page states for its original matches the decoded preview to within 1 ms for all 23 clips (for example `peek` 0.214 s, `kitten22` 0.643 s), because `afconvert` trims the MP3 encoder's delay and padding, so the offsets should come out at or near zero. The rule of Task 3 does not rely on that.

---

### Task 1: The three notes from the owner's checklist

Stage 1 left three notes for this stage. This task settles them, before anything is shipped:

1. **`--report` writes `report.md` into `--out`.** For a build into `NotchBuddy/Resources/sounds/` that would put an extra file in the folder. Now `build_pack.report_path(out)` sends the report of a build into the shipping folder to `.claude/sounds/build/ship-report.md` and leaves every other build as it was. Beyond that, `ship_problems(folder)` says whether the folder holds one `<slot>.wav` per slot and `README.md` and nothing else, and a build from the preview clips is refused outright when its `--out` is the shipping folder or inside it (a preview build there would ship low-quality clips). Task 4 lets Your mix built from the originals through.
2. **The tick tolerance is ±2.0 LU in the code and ±1.5 in the spec** (section 6: "targets allow ±1.5 LU"; nothing in stage 1 says why ticks got 2.0). The code now follows the spec. Measured on the real previews (stage-1 sets, 140 files): every file, ticks included, sits within 0.1 LU of its target, so ±1.5 costs nothing. If the originals in Task 8 miss a tick by more than 1.5 LU the plan stops and asks; it does not loosen the number.
3. **The audition page's one-line "voice" of each set is not tied to the recipes.** Two were already wrong: Studio's sleep is Trautwein's purr (the owner picked it), which its line did not name, and Best of's line said "one shared pitch shift" without the −1 semitone. `TestAuditionVoice` now ties each line to its recipe: every uploader a set uses is named (Best of mixes a dozen voices on purpose and is exempt), and the pitch a line states (`up 1.5 semitones`) is the recipe's `pitch_st`, or no pitch is stated when it is 0.

**Files:**
- Modify: `tools/sounds/pipeline.py` (`TARGETS` and its comment)
- Modify: `tools/sounds/build_pack.py` (usage text, `SHIP_DIR` and the four functions after `ROUND2_DIR`, the refusal before the candidates check, the report target)
- Modify: `tests/test_sound_build.py` (the tick-tolerance test and two report strings)
- Modify: `design/sounds/audition.html` (two `voice` strings in the data block)
- Modify: `scripts/test-sound-build.sh` (run every `tests/test_sound_*.py`)
- Create: `tests/test_sound_pack.py`

**Interfaces:**
- Consumes: stage 1's (and c1c's) `build_pack.main`, `BUILD_DIR`, `ROOT`, `recipe.SLOTS`, `recipe.MINE_NAME`, `recipe.load_recipes`, `pipeline.TARGETS`, the audition page's `<script type="application/json" id="data">` block, and `test_sound_build.write_recipes` and `ROOT`.
- Produces (`build_pack`): `SHIP_DIR`, `SHIP_KEEPS = ("README.md", ".DS_Store")`, `real(path)`, `in_ship_dir(path) -> bool`, `report_path(out) -> str`, `ship_problems(folder) -> [str]`, `refuse_shipping_folder(jobs, from_originals=False) -> str or None` (`jobs` is the list of `(name, SetRecipe, out)` that `main` builds; Task 4 passes `from_originals`). Produces (`pipeline`): `TARGETS == {"cat": (-20.0, 1.5), "tick": (-28.0, 1.5)}`. Produces (tests): `tests/test_sound_pack.py` with `TestChecklistNotes`, `TestShippingFolder`, `TestShippedPackOnDisk`, `TestAuditionVoice`.

- [ ] **Step 1: Check the base, and note the test count**

The plan runs on `notchmeow/rebrand` after `c1c-hairball` has merged. This prints the slot count, how the hairball's entry is shaped and the number of tests before any change (call it N; each task below adds a known number to it).

<!-- replay -->
```bash
git merge-base --is-ancestor cbc771e HEAD && echo "base ok"
python3 - <<'EOF'
import sys
sys.path.insert(0, "tools/sounds")
import recipe
sets = recipe.load_recipes("design/sounds/sets")
e = next(iter(sets.values())).entries["hairball"]
print(len(recipe.SLOTS), "slots; hairball source:", e.source)
segs = getattr(e, "segments", None)
print("segments:", [(s["source"], s["start"], s["end"]) for s in segs] if segs else "NONE")
print("synth_layers:", [(l["name"], l["at"]) for l in getattr(e, "synth_layers", None) or []])
EOF
bash scripts/test-sound-build.sh 2>&1 | grep -E '^Ran|^OK|FAILED'
```

Expected: `base ok`; `29 slots; hairball source: placed`; `segments:` followed by three `('hairball/fs-561726-har2h.mp3', start, end)` tuples (on c1c's plan: 2.143-2.558, 4.196-4.576 and 7.278-7.658); `synth_layers: [('hairball_retch_plop', 0.93)]`; `Ran N tests`, then `OK`. If `segments` says `NONE` or the source is not `placed`, c1c's merged recipe differs from the plan this one was written against (see "Base"): stop, read c1c's `recipe.py`, and adapt `sources.clip_uses` (Task 2) and `originals.with_windows` (Task 4) when you get there; tell the controller now.

- [ ] **Step 2: Write the failing tests**

<!-- replay -->
```bash
cat > tests/test_sound_pack.py <<'EOF'
"""Tests for the final sound pack (sub-project C, stage 2), part 1: the checklist notes, the shipping folder and the
audition page's voices. Standard library only. Run: bash scripts/test-sound-build.sh
Builds on the helpers of test_sound_build.py (stage 1), which unittest finds in the same folder."""
import contextlib
import io
import json
import os
import re
import shutil
import tempfile
import unittest
from unittest import mock

from test_sound_build import ROOT, write_recipes  # noqa: F401  (also puts tools/sounds on sys.path)

import build_pack  # noqa: E402
import pipeline  # noqa: E402
import recipe  # noqa: E402

SETS_DIR = os.path.join(ROOT, "design", "sounds", "sets")


class TestChecklistNotes(unittest.TestCase):
    """The three notes the owner's checklist left for stage 2."""

    def test_the_loudness_targets_are_the_specs_for_cats_and_ticks(self):
        self.assertEqual(pipeline.TARGETS, {"cat": (-20.0, 1.5), "tick": (-28.0, 1.5)})


class TestShippingFolder(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nm ship test ")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.ship = os.path.join(self.tmp, "NotchBuddy", "Resources", "sounds")
        os.makedirs(self.ship)
        patch = mock.patch.object(build_pack, "SHIP_DIR", self.ship)
        patch.start()
        self.addCleanup(patch.stop)

    def run_main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = build_pack.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def test_a_report_sits_beside_the_wavs_everywhere_but_in_the_shipping_folder(self):
        elsewhere = os.path.join(self.tmp, "build", "mine")
        self.assertEqual(build_pack.report_path(elsewhere), os.path.join(elsewhere, "report.md"))
        self.assertEqual(build_pack.report_path(self.ship),
                         os.path.join(build_pack.BUILD_DIR, "ship-report.md"))
        self.assertEqual(build_pack.report_path(os.path.join(self.ship, "..", "sounds")),
                         os.path.join(build_pack.BUILD_DIR, "ship-report.md"))        # however the path is spelt

    def test_ship_problems_names_what_is_missing_and_what_is_extra(self):
        slots = list(recipe.SLOTS)
        for slot in slots:
            open(os.path.join(self.ship, slot + ".wav"), "wb").close()
        open(os.path.join(self.ship, "README.md"), "w").close()
        open(os.path.join(self.ship, ".DS_Store"), "w").close()           # Finder litter is allowed, git ignores it
        self.assertEqual(build_pack.ship_problems(self.ship), [])
        open(os.path.join(self.ship, "report.md"), "w").close()
        os.remove(os.path.join(self.ship, "gulp.wav"))
        self.assertEqual(build_pack.ship_problems(self.ship), ["missing gulp.wav", "unexpected report.md"])

    def test_a_build_from_previews_may_not_write_into_the_shipping_folder(self):
        recipes = os.path.join(self.tmp, "recipes")
        write_recipes(recipes, lambda s: "synth:blip")
        cands = os.path.join(self.tmp, "cands")
        os.makedirs(cands)
        for argv in (["--set", "studio", "--out", self.ship],
                     ["--set", "studio", "--out", os.path.join(self.ship, "studio")],
                     ["--all", "--out", self.ship]):
            code, _, err = self.run_main(*argv, "--recipes", recipes, "--candidates", cands)
            self.assertEqual(code, 2, argv)
            self.assertIn("Freesound originals", err)
        self.assertEqual(os.listdir(self.ship), [])        # nothing written, not even a folder


class TestShippedPackOnDisk(unittest.TestCase):
    def test_the_shipping_folder_is_empty_or_exactly_one_wav_per_slot(self):
        ship = build_pack.SHIP_DIR
        names = os.listdir(ship)
        if any(n.endswith(".wav") for n in names):
            self.assertEqual(build_pack.ship_problems(ship), [])
        else:
            self.assertEqual([n for n in names if n not in build_pack.SHIP_KEEPS], [])


def uploader(source):
    """Who recorded a clip, from the name the candidates folder gives it (stage 1 naming)."""
    name = os.path.basename(source)
    if name.startswith("bsb-"):
        return "BigSoundBank"
    found = re.match(r"fs-\d+-(.+)\.[a-z0-9]+$", name)
    return found.group(1) if found else None


class TestAuditionVoice(unittest.TestCase):
    """The page's one-line voice of each set must say what the recipe really uses."""

    def setUp(self):
        with open(os.path.join(ROOT, "design", "sounds", "audition.html"), encoding="utf-8") as f:
            html = f.read()
        data = json.loads(re.search(r'<script type="application/json" id="data">(.*?)</script>', html, re.S).group(1))
        self.voice = {s["id"]: s["voice"] for s in data["sets"]}
        self.sets = recipe.load_recipes(SETS_DIR)

    def own_uploaders(self, s):
        return {uploader(e.source) for e in s.entries.values() if not e.shared and not e.source.startswith("synth:")}

    def test_every_uploader_a_set_uses_is_named_in_its_voice(self):
        for name, s in self.sets.items():
            if name == "bestof":            # Best of mixes a dozen voices on purpose; its line says so
                continue
            for who in self.own_uploaders(s):
                self.assertIsNotNone(who, name)
                self.assertIn(who.lower(), self.voice[name].lower(), "%s does not name %s" % (name, who))

    def test_the_pitch_a_voice_states_is_the_recipes(self):
        for name, s in self.sets.items():
            said = re.search(r"\b(up|down) (\d+(?:\.\d+)?) semitones?\b", self.voice[name])
            if s.pitch_st == 0.0:
                self.assertIsNone(said, "%s states a pitch shift its recipe does not have" % name)
                self.assertNotIn("semitone", self.voice[name])
            else:
                self.assertIsNotNone(said, "%s does not state its %+g semitones" % (name, s.pitch_st))
                self.assertEqual(said.group(1), "up" if s.pitch_st > 0 else "down", name)
                self.assertEqual(float(said.group(2)), abs(s.pitch_st), name)

    def test_every_set_has_a_voice_and_nothing_else_does(self):
        self.assertEqual(list(self.voice), list(self.sets))
        self.assertTrue(all(v.strip() for v in self.voice.values()))


if __name__ == "__main__":
    unittest.main()
EOF
```

- [ ] **Step 3: Run them to see them fail**

<!-- replay-fail -->
```bash
python3 -m unittest discover -s tests -p 'test_sound_pack.py' 2>&1 | tail -12
```

Expected: `FAILED (failures=3, errors=4)` out of 8 tests: the targets test, Studio's voice and Best of's pitch fail; the four shipping-folder tests error with `AttributeError: ... does not have the attribute 'SHIP_DIR'`.

- [ ] **Step 4: The tick tolerance, the two voice strings and the test script**

<!-- replay -->
```bash
python3 - <<'EOF'
def edit(path, old, new):
    with open(path, encoding="utf-8") as f:
        s = f.read()
    assert s.count(old) == 1, "%s: the text to replace is not there exactly once:\n%s" % (path, old)
    with open(path, "w", encoding="utf-8") as f:
        f.write(s.replace(old, new))


# 1. the tick tolerance: the spec says +-1.5 LU for both, the code said 2.0 for ticks
edit("tools/sounds/pipeline.py",
     '# short-term LUFS target and tolerance in LU, by kind. Ticks sit 6 to 10 dB under the vocals.\n'
     'TARGETS = {"cat": (-20.0, 1.5), "tick": (-28.0, 2.0)}',
     '# short-term LUFS target and tolerance in LU, by kind (spec section 6: both +-1.5). Ticks sit 8 dB under the vocals.\n'
     'TARGETS = {"cat": (-20.0, 1.5), "tick": (-28.0, 1.5)}')
edit("tests/test_sound_build.py",
     "    def test_vocals_may_be_1_5_lu_off_and_ticks_2_lu(self):",
     "    def test_vocals_and_ticks_may_both_be_1_5_lu_off(self):")
edit("tests/test_sound_build.py",
     '        self.assertEqual(report.check("tick", m(lufs=-29.9, seconds=0.2)), [])\n'
     '        self.assertEqual(report.check("tick", m(lufs=-26.1, seconds=0.2)), [])\n'
     '        self.assertTrue(report.check("tick", m(lufs=-30.1, seconds=0.2)))',
     '        self.assertEqual(report.check("tick", m(lufs=-29.4, seconds=0.2)), [])\n'
     '        self.assertEqual(report.check("tick", m(lufs=-26.6, seconds=0.2)), [])\n'
     '        self.assertTrue(report.check("tick", m(lufs=-29.6, seconds=0.2)))\n'
     '        self.assertTrue(report.check("tick", m(lufs=-26.4, seconds=0.2)))')
edit("tests/test_sound_build.py",
     '        bad = report.Row("tick", "tick", -33.0, -28.0, -30.0, -3.0, 0.2, 0.0, ["loudness -33.0 LUFS is not -28.0 +-2.0"])',
     '        bad = report.Row("tick", "tick", -33.0, -28.0, -30.0, -3.0, 0.2, 0.0, ["loudness -33.0 LUFS is not -28.0 +-1.5"])')
edit("tests/test_sound_build.py",
     '        self.assertEqual(report.failures(results), ["studio/tick: loudness -33.0 LUFS is not -28.0 +-2.0"])',
     '        self.assertEqual(report.failures(results), ["studio/tick: loudness -33.0 LUFS is not -28.0 +-1.5"])')

# 2. the audition page's voices: Studio also uses Trautwein's purr (for sleep), and Best of's shift is -1 semitone
edit("design/sounds/audition.html",
     '"voice":"BigSoundBank\'s cat Emi, with MBPL\'s soft trills"}',
     '"voice":"BigSoundBank\'s cat Emi, with MBPL\'s soft trills and Trautwein\'s purr for sleep"}')
edit("design/sounds/audition.html",
     '"voice":"The strongest clip per slot, one shared pitch shift"}',
     '"voice":"The strongest clip per slot, one shared pitch shift (down 1 semitone)"}')

# 3. the test script runs every tests/test_sound_*.py, not only the stage-1 file
edit("scripts/test-sound-build.sh",
     "# Tests for the sound-set build (tools/sounds/): Python 3 standard library plus macOS afconvert.",
     "# Tests for the sound build (tools/sounds/, stages 1 and 2): Python 3 standard library plus macOS afconvert.")
edit("scripts/test-sound-build.sh",
     "python3 -m unittest discover -s tests -p 'test_sound_build.py'",
     "python3 -m unittest discover -s tests -p 'test_sound_*.py'")
EOF
```

- [ ] **Step 5: The shipping folder in `build_pack.py`**

<!-- replay -->
```bash
python3 - <<'EOF'
def edit(path, old, new):
    with open(path, encoding="utf-8") as f:
        s = f.read()
    assert s.count(old) == 1, "%s: the text to replace is not there exactly once:\n%s" % (path, old)
    with open(path, "w", encoding="utf-8") as f:
        f.write(s.replace(old, new))


P = "tools/sounds/build_pack.py"

# the shipping folder, where a report goes, and who may write into it
edit(P, '''ROUND2_DIR = os.path.join(BUILD_DIR, recipe.ROUND2_NAME)    # the folder the audition page probes
''', '''ROUND2_DIR = os.path.join(BUILD_DIR, recipe.ROUND2_NAME)    # the folder the audition page probes
SHIP_DIR = os.path.join(ROOT, "NotchBuddy", "Resources", "sounds")    # what both apps play: one WAV per slot
SHIP_KEEPS = ("README.md", ".DS_Store")      # the only other things the folder may hold (Finder litter is git-ignored)


def real(path):
    return os.path.realpath(os.path.abspath(path))


def in_ship_dir(path):
    """True when `path` is the shipping folder or inside it."""
    ship = real(SHIP_DIR)
    return os.path.commonpath([real(path), ship]) == ship


def report_path(out):
    """Where report.md goes for a build into `out`: next to the WAVs, except in the shipping folder,
    which holds the WAVs and nothing else, so its report goes under .claude/sounds/build."""
    return os.path.join(BUILD_DIR, "ship-report.md") if in_ship_dir(out) else os.path.join(out, "report.md")


def ship_problems(folder):
    """What is wrong with a shipping folder, as short sentences: it holds one <slot>.wav per slot and
    README.md, and nothing else (no report.md, no leftovers). Empty means it is exactly that."""
    have = set(os.listdir(folder))
    want = {slot + ".wav" for slot in recipe.SLOTS}
    return (["missing %s" % n for n in sorted(want - have)]
            + ["unexpected %s" % n for n in sorted(have - want - set(SHIP_KEEPS))])


def refuse_shipping_folder(jobs, from_originals=False):
    """A message when a build would write into the shipping folder, else None. Only Your mix built
    from the originals may go there (stage 2); a build from the preview clips never ships."""
    for name, _rec, out in jobs:
        if in_ship_dir(out) and not (from_originals and name == recipe.MINE_NAME):
            return ("%s: %s only takes Your mix built from the Freesound originals (stage 2), never a build "
                    "from the preview clips; build into .claude/sounds/build instead" % (name, SHIP_DIR))
    return None
''')

# refuse before anything is written
edit(P, '''    if cands is None:
        print("candidates folder not found; pass --candidates or set NM_SOUND_CANDIDATES", file=sys.stderr)
        return 2
    loader, cache, results''', '''    refusal = refuse_shipping_folder(jobs)
    if refusal:
        print(refusal, file=sys.stderr)
        return 2
    if cands is None:
        print("candidates folder not found; pass --candidates or set NM_SOUND_CANDIDATES", file=sys.stderr)
        return 2
    loader, cache, results''')

# the report goes where report_path says
edit(P, '''        target = os.path.join(root_out if args.all else jobs[0][2], "report.md")
''', '''        target = os.path.join(root_out, "report.md") if args.all else report_path(jobs[0][2])
        os.makedirs(os.path.dirname(target), exist_ok=True)
''')

# the usage text says where the report goes
edit(P, '''--report also writes report.md next to the WAVs and exits 1 when any file misses its targets.
''', '''--report also writes report.md next to the WAVs and exits 1 when any file misses its targets. Into the shipping
folder (NotchBuddy/Resources/sounds, which holds the WAVs and nothing else) it writes
.claude/sounds/build/ship-report.md instead.
''')
EOF
```

- [ ] **Step 6: Run the tests, then the whole script, then a real build**

<!-- replay -->
```bash
python3 -m unittest discover -s tests -p 'test_sound_pack.py' 2>&1 | tail -4
/usr/bin/python3 -m unittest discover -s tests -p 'test_sound_pack.py' 2>&1 | tail -4
bash scripts/test-sound-build.sh 2>&1 | tail -8
python3 tools/sounds/build_pack.py --all --report 2>&1 | tail -2
```

Expected: `Ran 8 tests ... OK` twice (the second run is the system Python 3.9); the script ends with `Ran N+8 tests ... OK`, `recipes ok: 5 sets x 29 slots`, `mine.json ok: 15 picks, 0 none` and `clips ok in ...`; the real build ends with `report: .../.claude/sounds/build/report.md (145 of 145 files meet their targets)` (5 sets of 29 slots). The build writes only under the worktree's git-ignored `.claude/`.

- [ ] **Step 7: Commit**

<!-- replay-commit -->
```bash
git add tools/sounds/pipeline.py tools/sounds/build_pack.py design/sounds/audition.html scripts/test-sound-build.sh tests/test_sound_build.py tests/test_sound_pack.py
git commit -m "feat(sounds): stage 2 notes: ticks +-1.5 LU, a shipping folder that holds only the pack, voices tied to the recipes

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 2: `sources.json`, the licence gate and the credits text

`design/sounds/sources.json` is the machine-readable list of every recorded clip Your mix uses, keyed by the recipe's own source name (`love/fs-64017-Department64.mp3`, the preview clip the recipes were written against). One entry says who made the clip and where its page is, what that page states about the original (`stated`: Type, Duration, File size and the rest of its Sound information, as printed), the licence as read on that page (`licence`, `licence_url`, `checked_on`, `checked_by`), the original the owner downloaded (`original`: file name, bytes, SHA-256), the offset between that original and the preview (`offset_s`) and the window each slot takes (`windows`). Tasks 5 and 7 fill in the fields that are `null` in the seed.

A recipe entry can take **more than one window**: the hairball (plan `c1c-hairball`) lays three windows of one recorded clip over a made-in-code layer. `sources.clip_uses(entry)` is the one function that lists an entry's recorded windows, so everything else (which clips are needed, which windows are pinned, who is credited) counts windows, not slots, and `windows[slot]` in `sources.json` is a list, one item per window the slot takes from that clip.

`sources.py` is the gate. `licence_problems` is the spec's "the build refuses any source without a verified CC0 entry": a source is verified only with licence `CC0-1.0`, the page's CC0 link, a real date and a checker, and half a licence entry is a shape error. `gate` adds that every original is pinned and every window is checked. The build in Task 4 runs `gate` before it writes a file. The same module writes `docs/SOUND-CREDITS.md` from the list, so the two cannot drift, and the text of the download list the owner works from (Task 6).

**Files:**
- Create: `tools/sounds/sources.py`
- Create: `design/sounds/sources.json` (generated by a one-off script, then committed)
- Create: `tests/sound_pack_support.py`, `tests/test_sound_sources.py`

**Interfaces:**
- Consumes: stage 1's `recipe` (`_check_source`, `RecipeError`, `SetRecipe`, `load_recipes`, `load_round2`, `load_mine`), `test_sound_build.entry` and `ROOT`.
- Produces (`sources`): `SOURCES_NAME`, `CC0 = "CC0-1.0"`, `CC0_URLS`, `DATE`, `SourcesError`; `freesound_id(source)`, `freesound_author(source)`, `page_url(source)`; `parse_duration("1:00.103") -> 60.103`, `parse_size("110.9 KB") -> bytes`; `load(path) -> dict` (raises `SourcesError` on a bad shape), `save(path, doc)`, `problems(doc) -> [str]`, `is_verified(entry) -> bool`; `clip_uses(entry) -> [(source, start, end)]` (an ordinary entry has one, a made-in-code one none, the hairball three; the only reader of the hairball's `segments`); `file_sources(rec) -> OrderedDict source -> [slots]`; `slot_windows(rec, slot, source) -> [(start, end)]`; `licence_problems(doc, rec)`, `pin_problems(doc, rec)`, `window_problems(doc, rec)`, `gate(doc, rec)` (each a list of short sentences, empty means go); `find_original(folder, source, entry) -> path`; `type_matches(entry, path) -> bool`; `credits_text(doc, rec) -> str`; `download_list_text(doc, rec, folder) -> str`. Produces (tests): `tests/sound_pack_support.py` with `your_mix()`, `blanked(doc)`, `mini_recipe(*items)`, `blank_doc(rec)`, `verify_all(doc, **fields)` the stand-ins `FakeSegment`, `FakeEntry`, `hairball_like(...)` and `with_hairball(rec)` (an entry that takes three windows of one clip, as the hairball's does) and the constants `SR`, `SETS_DIR`, `SOURCES_JSON`, `ROOT`; Tasks 3 and 4 append to it.

- [ ] **Step 1: Write the shared test helpers and the failing tests**

<!-- replay -->
```bash
cat > tests/sound_pack_support.py <<'EOF'
"""Helpers the stage-2 sound tests share (sub-project C). Standard library only.

Importing test_sound_build puts tools/sounds on sys.path, so the build modules import by bare name here too."""
import copy
import math  # noqa: F401  (used by the helpers later tasks add)
import os
import random  # noqa: F401
import struct  # noqa: F401
import wave  # noqa: F401
from collections import OrderedDict, namedtuple

from test_sound_build import ROOT, entry  # noqa: F401

import dsp  # noqa: E402
import recipe  # noqa: E402
import sources  # noqa: E402

SR = dsp.SR
SETS_DIR = os.path.join(ROOT, "design", "sounds", "sets")
SOURCES_JSON = os.path.join(ROOT, "design", "sounds", "sources.json")


def your_mix():
    sets = recipe.load_recipes(SETS_DIR)
    return recipe.load_mine(os.path.join(SETS_DIR, "mine.json"), sets,
                            recipe.load_round2(os.path.join(SETS_DIR, "round2.json"), sets))


# A stand-in for the hairball's entry, in the shape plan c1c-hairball gives it: the source "placed", `segments` a list
# of dicts (a window of a recorded clip each, with where it is placed and its level and fades) and `synth_layers` a
# list of dicts. The tests of the tools use this, not c1c's own types, so they only depend on the fields `clip_uses`
# documents. `start` and `end` of the entry cut the finished timeline; they are not a clip window.
FakeEntry = namedtuple("FakeEntry", "slot source start end pitch_st segments synth_layers")
HAIRBALL_CLIP = "hairball/fs-1004-Dana.wav"


def hairball_like(slot="hairball", clip=HAIRBALL_CLIP, windows=((0.10, 0.30), (0.50, 0.70), (0.90, 1.10))):
    """An entry that takes several windows of one recorded clip and has a made-in-code layer too."""
    segments = [{"source": clip, "start": a, "end": b, "at": 0.01 + 0.32 * n, "level": 0.2, "fade_in_ms": 5.0, "fade_out_ms": 60.0}
                for n, (a, b) in enumerate(windows)]
    return FakeEntry(slot, "placed", 0.0, 1.48, 0.0, segments, [{"name": "hairball_retch_plop", "seed": 1205, "at": 0.93}])


def with_hairball(rec, entry_=None):
    """`rec` plus a hairball-like entry (a copy of the recipe: the original is not changed)."""
    entries = OrderedDict(rec.entries)
    entries["hairball"] = entry_ or hairball_like()
    return rec._replace(entries=entries)


def blanked(doc):
    """A copy of a sources.json document as the seed had it: every clip named, nothing checked, pinned or measured.
    The tests of the tools use this, so they keep passing after the real file is filled in."""
    out = copy.deepcopy(doc)
    for e in out["sources"].values():
        e.update(licence=None, licence_url=None, checked_on=None, checked_by=None, original=None, offset_s=None,
                 windows=OrderedDict())
    return out


def mini_recipe(*items):
    """A SetRecipe named mine from (slot, source) or (slot, source, {fields}) tuples: enough to test the originals."""
    entries = OrderedDict()
    for slot, source, *fields in items:
        entries[slot] = entry(slot, source, **(fields[0] if fields else {}))
    return recipe.SetRecipe("mine", "Your mix", 0.0, entries)


def blank_doc(rec):
    """A sources.json document for the recorded clips of `rec`, as the seed has it: nothing checked yet."""
    doc = OrderedDict(title="test", sources=OrderedDict())
    for source in sources.file_sources(rec):
        doc["sources"][source] = OrderedDict(
            title="Clip %s" % sources.freesound_id(source), author=sources.freesound_author(source),
            page=sources.page_url(source), stated={"type": "Wave (.wav)", "duration": "0:00.900", "size": "84.4 KB"},
            licence=None, licence_url=None, checked_on=None, checked_by=None, original=None, offset_s=None,
            windows=OrderedDict())
    return doc


def verify_all(doc, **fields):
    for e in doc["sources"].values():
        e.update(licence=sources.CC0, licence_url=sources.CC0_URLS[0], checked_on="2026-10-06", checked_by="a test")
        e.update(fields)
    return doc
EOF
```

<!-- replay -->
```bash
cat > tests/test_sound_sources.py <<'EOF'
"""Tests for sources.json and the licence gate (sub-project C, stage 2, task 2). Standard library only."""
import copy
import os
import shutil
import tempfile
import unittest
from collections import OrderedDict

from sound_pack_support import (HAIRBALL_CLIP, SOURCES_JSON, blank_doc, blanked, hairball_like, mini_recipe, verify_all,
                               with_hairball, your_mix)
from test_sound_build import raw

import recipe  # noqa: E402
import sources  # noqa: E402


class TestSources(unittest.TestCase):
    def setUp(self):
        self.mix = your_mix()
        self.live = sources.load(SOURCES_JSON)
        self.seed = blanked(self.live)

    def test_sources_json_names_exactly_the_recorded_clips_of_your_mix(self):
        self.assertEqual(list(self.live["sources"]), list(sources.file_sources(self.mix)))
        self.assertIn("hairball", sources.file_sources(self.mix)["hairball/fs-561726-har2h.mp3"])      # Cat Coughing, har2h
        made_in_code = [s for s, e in self.mix.entries.items() if not sources.clip_uses(e)]
        self.assertEqual(made_in_code, ["yawn", "work", "blip", "attach"])               # nothing recorded in them

    def test_every_page_and_author_follows_the_source_name(self):
        for source, e in self.live["sources"].items():
            self.assertEqual(e["page"], "https://freesound.org/people/%s/sounds/%s/" % (e["author"], sources.freesound_id(source)))
            self.assertTrue(e["title"].strip())

    def test_a_blank_entry_claims_neither_a_licence_nor_a_download(self):
        for e in self.seed["sources"].values():
            self.assertFalse(sources.is_verified(e))
            self.assertIsNone(e["original"])
            self.assertIsNone(e["offset_s"])
            self.assertEqual(e["windows"], {})

    def test_the_pages_figures_parse(self):
        self.assertEqual(sources.parse_duration("1:00.103"), 60.103)
        self.assertEqual(sources.parse_duration("0:00.643"), 0.643)
        self.assertEqual(sources.parse_size("110.9 KB"), int(round(110.9 * 1024)))
        self.assertEqual(sources.parse_size("1.4 MB"), int(round(1.4 * 1024 * 1024)))
        for bad in ("", "soon", "12", "1.4 mb "):
            with self.assertRaises(sources.SourcesError):
                sources.parse_size(bad)
        for bad in ("", "soon", "0.643", "1:5"):
            with self.assertRaises(sources.SourcesError):
                sources.parse_duration(bad)
        for e in self.live["sources"].values():
            sources.parse_duration(e["stated"]["duration"])
            sources.parse_size(e["stated"]["size"])

    def test_a_verified_licence_needs_cc0_the_link_a_date_and_a_checker(self):
        good = dict(licence="CC0-1.0", licence_url="https://creativecommons.org/publicdomain/zero/1.0/",
                    checked_on="2026-10-06", checked_by="the re-check agent")
        self.assertTrue(sources.is_verified(good))
        for field, bad in (("licence", "CC-BY-4.0"), ("licence", "CC0"), ("licence_url", "https://example.com/cc0"),
                           ("checked_on", "yesterday"), ("checked_on", None), ("checked_by", " "), ("checked_by", None)):
            self.assertFalse(sources.is_verified(dict(good, **{field: bad})), (field, bad))

    def test_half_a_licence_entry_is_a_shape_error(self):
        doc = copy.deepcopy(self.seed)
        first = next(iter(doc["sources"].values()))
        first["licence"] = "CC0-1.0"                       # no link, date or checker
        self.assertTrue(any("licence entry needs" in p for p in sources.problems(doc)))
        verify_all(doc)
        self.assertEqual(sources.problems(doc), [])

    def test_shape_errors_name_the_clip(self):
        doc = copy.deepcopy(self.seed)
        doc["sources"]["love/fs-64017-Department64.mp3"]["page"] = "https://freesound.org/people/Department64/sounds/1/"
        doc["sources"]["annoyed/fs-64008-Department64.mp3"]["original"] = {"file": "x.wav", "bytes": 5, "sha256": "ABC"}
        doc["sources"]["dizzy/fs-64007-Department64.mp3"]["stated"]["size"] = "big"
        said = "; ".join(sources.problems(doc))
        self.assertIn("love/fs-64017-Department64.mp3: page must be", said)
        self.assertIn("annoyed/fs-64008-Department64.mp3: original needs", said)
        self.assertIn("dizzy/fs-64007-Department64.mp3: size 'big'", said)
        tmp = tempfile.mkdtemp(prefix="nm sources ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        path = os.path.join(tmp, "sources.json")
        sources.save(path, doc)
        with self.assertRaises(sources.SourcesError) as ctx:
            sources.load(path)
        self.assertIn("love/fs-64017-Department64.mp3: page must be", str(ctx.exception))

    def test_an_excluded_clip_can_never_be_a_source(self):
        doc = copy.deepcopy(self.seed)
        doc["sources"]["tick/fs-857748-qubodup.mp3"] = copy.deepcopy(next(iter(doc["sources"].values())))
        self.assertTrue(any("excluded source" in p for p in sources.problems(doc)))

    def test_the_build_refuses_a_source_missing_from_sources_json(self):
        doc = verify_all(copy.deepcopy(self.seed))
        self.assertEqual(sources.licence_problems(doc, self.mix), [])
        del doc["sources"]["sleep/fs-260881-Trautwein.mp3"]
        said = sources.licence_problems(doc, self.mix)
        self.assertEqual(len(said), 1)
        self.assertIn("1 clips are not in sources.json: sleep/fs-260881-Trautwein.mp3", said[0])
        self.assertEqual(sources.gate(doc, self.mix)[0], said[0])

    def test_the_build_refuses_a_source_without_a_verified_cc0_entry(self):
        doc = verify_all(copy.deepcopy(self.seed))
        doc["sources"]["pop/fs-258269-jcallison.mp3"]["checked_on"] = None
        doc["sources"]["send/fs-402453-jimmyfisher.mp3"]["licence"] = "CC-BY-4.0"
        said = "; ".join(sources.licence_problems(doc, self.mix))
        self.assertIn("2 clips have no verified CC0 entry", said)
        self.assertIn("pop/fs-258269-jcallison.mp3", said)
        self.assertIn("send/fs-402453-jimmyfisher.mp3", said)

    def test_a_long_list_of_problems_is_shortened(self):
        said = sources.gate(self.seed, self.mix)
        self.assertTrue(all(len(line) < 400 for line in said), said)
        self.assertTrue(any("and %d more" % (len(self.seed["sources"]) - 4) in line for line in said))

    def test_find_original_takes_the_pinned_name_else_the_one_file_named_by_the_id(self):
        tmp = tempfile.mkdtemp(prefix="nm originals ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        source = "love/fs-64017-Department64.mp3"
        e = {"original": None}
        with self.assertRaises(sources.SourcesError) as ctx:
            sources.find_original(tmp, source, e)
        self.assertIn("64017__", str(ctx.exception))
        for name in ("64017__department64__kitten22.wav", "640170__other__x.wav", ".64017__hidden.wav"):
            open(os.path.join(tmp, name), "w").close()
        self.assertEqual(os.path.basename(sources.find_original(tmp, source, e)), "64017__department64__kitten22.wav")
        open(os.path.join(tmp, "64017__department64__kitten22 (1).wav"), "w").close()      # a browser's second copy
        with self.assertRaises(sources.SourcesError) as ctx:
            sources.find_original(tmp, source, e)
        self.assertIn("more than one", str(ctx.exception))
        e = {"original": {"file": "64017__department64__kitten22.wav"}}                       # pinned: no guessing
        self.assertTrue(sources.find_original(tmp, source, e).endswith("kitten22.wav"))
        e = {"original": {"file": "gone.wav"}}
        with self.assertRaises(sources.SourcesError):
            sources.find_original(tmp, source, e)

    def test_a_preview_mp3_saved_by_mistake_is_not_a_wave(self):
        e = {"stated": {"type": "Wave (.wav)"}}
        self.assertTrue(sources.type_matches(e, "/x/64017__a__b.wav"))
        self.assertTrue(sources.type_matches(e, "/x/64017__a__b.WAV"))
        self.assertFalse(sources.type_matches(e, "/x/64017_861714-lq.mp3"))
        self.assertTrue(sources.type_matches({"stated": {"type": "Ogg Vorbis (.ogg)"}}, "/x/258269__a__b.ogg"))
        self.assertFalse(sources.type_matches({"stated": {"type": "Ogg Vorbis (.ogg)"}}, "/x/258269__a__b.wav"))

    def test_the_download_list_gives_every_clip_its_page_and_what_the_page_says(self):
        text = sources.download_list_text(self.seed, self.mix, "/o/originals")
        n = len(self.seed["sources"])
        self.assertIn("%d clips." % n, text)
        self.assertIn("Needs your Freesound sign-in: download these yourself (%d)" % n, text)
        self.assertIn("Direct links, with your OK before anything is downloaded (0)", text)
        self.assertIn("None: Your mix uses no BigSoundBank clip.", text)
        self.assertEqual(text.count("- [ ] **"), n)
        for source, e in self.seed["sources"].items():
            self.assertIn(e["page"], text)
            self.assertIn("`%s__`" % sources.freesound_id(source), text)
        self.assertIn(" by Department64, for dizzy, slap", text)                      # one file, two slots
        self.assertIn("by har2h, for hairball", text)                                  # one file, three windows, one slot
        pop = self.seed["sources"]["pop/fs-258269-jcallison.mp3"]["stated"]
        self.assertIn("the page says: %s, %s, %s" % (pop["type"], pop["duration"], pop["size"]), text)

    def test_a_bigsoundbank_clip_would_go_in_the_direct_link_group_with_its_link(self):
        rec = mini_recipe(("greet", "greet/bsb-s1885.mp3"))
        doc = blank_doc(rec)
        e = doc["sources"]["greet/bsb-s1885.mp3"]
        e.update(author="BigSoundBank", page="https://bigsoundbank.com/growling-cat-1-s1885.html",
                 download={"url": "https://bigsoundbank.com/UPLOAD/wav/1885.wav", "file": "bsb-1885.wav"})
        self.assertEqual(sources.problems(doc), [])
        text = sources.download_list_text(doc, rec, "/o")
        self.assertIn("Needs your Freesound sign-in: download these yourself (0)", text)
        self.assertIn("Direct links, with your OK before anything is downloaded (1)", text)
        self.assertIn("direct link: https://bigsoundbank.com/UPLOAD/wav/1885.wav", text)
        self.assertIn("save it as `bsb-1885.wav`", text)

    def test_credits_list_every_recorded_slot_once_per_clip_and_name_the_made_in_code_ones(self):
        doc = verify_all(copy.deepcopy(self.seed))
        for i, e in enumerate(doc["sources"].values()):
            e["original"] = {"file": "x%d.wav" % i, "bytes": 10 + i, "sha256": ("%02x" % i) * 32}
        text = sources.credits_text(doc, self.mix)
        rows = [l for l in text.splitlines() if l.startswith("| ") and not l.startswith("| Slot") and not l.startswith("|---")]
        want = sum(len(OrderedDict.fromkeys(s for s, _a, _b in sources.clip_uses(e))) for e in self.mix.entries.values())
        self.assertEqual(len(rows), want)
        first = doc["sources"]["love/fs-64017-Department64.mp3"]
        self.assertIn("| greet | %s | Department64 | <https://freesound.org/people/Department64/sounds/64017/> "
                      "| CC0 1.0 | 2026-10-06 | `" % first["title"] + "00" * 32 + "` |", text)
        self.assertIn("Made in code, with no source clip: yawn (yawn), work (work), blip (blip), attach (clink).", text)
        self.assertEqual(text, sources.credits_text(doc, self.mix))                  # same input, same text

    # --- an entry that takes several windows of one clip, and also has a made-in-code layer (the hairball)

    def test_clip_uses_lists_every_recorded_window_of_an_entry_in_order(self):
        plain = recipe.parse_entry(raw("love", "love/fs-1-A.wav", start=0.1, end=0.6), "t")
        self.assertEqual(sources.clip_uses(plain), [("love/fs-1-A.wav", 0.1, 0.6)])
        self.assertEqual(sources.clip_uses(recipe.parse_entry(raw("blip", "synth:blip"), "t")), [])
        self.assertEqual(sources.clip_uses(hairball_like()),
                         [(HAIRBALL_CLIP, 0.10, 0.30), (HAIRBALL_CLIP, 0.50, 0.70), (HAIRBALL_CLIP, 0.90, 1.10)])

    def test_a_placed_sounds_own_cut_is_not_a_clip_window_and_a_layers_only_sound_has_no_source(self):
        cut = hairball_like()
        self.assertEqual((cut.start, cut.end), (0.0, 1.48))                                # the timeline's cut ...
        self.assertNotIn((HAIRBALL_CLIP, 0.0, 1.48), sources.clip_uses(cut))               # ... is never read as a window
        layers_only = cut._replace(segments=[])
        self.assertEqual(sources.clip_uses(layers_only), [])

    def test_a_slot_with_three_windows_of_one_clip_is_one_source_and_one_slot(self):
        rec = with_hairball(mini_recipe(("love", "love/fs-1002-Bob.wav")))
        self.assertEqual(sources.file_sources(rec), OrderedDict([("love/fs-1002-Bob.wav", ["love"]), (HAIRBALL_CLIP, ["hairball"])]))
        self.assertEqual(sources.slot_windows(rec, "hairball", HAIRBALL_CLIP), [(0.10, 0.30), (0.50, 0.70), (0.90, 1.10)])
        text = sources.download_list_text(blank_doc(rec), rec, "/o")
        self.assertEqual(text.count("by Dana, for hairball"), 1)

    def test_every_window_of_such_a_slot_is_checked_and_named(self):
        rec = with_hairball(mini_recipe(("love", "love/fs-1002-Bob.wav")))
        doc = verify_all(blank_doc(rec))
        for e in doc["sources"].values():
            e["original"] = {"file": "x.wav", "bytes": 5, "sha256": "ab" * 32}
            e["offset_s"] = 0.0
        ok = lambda a, b: {"start": a, "end": b, "r": 0.99, "ok": True}
        bob = doc["sources"]["love/fs-1002-Bob.wav"]
        bob["windows"] = {"love": [ok(0.0, 0.5)]}
        dana = doc["sources"][HAIRBALL_CLIP]
        dana["windows"] = {"hairball": [ok(0.10, 0.30), ok(0.50, 0.70)]}                       # one window short
        self.assertEqual(sources.gate(doc, rec), ["3 windows are not pinned and checked: hairball 1 of 3, hairball 2 of 3, hairball 3 of 3"])
        dana["windows"]["hairball"] = [ok(0.10, 0.30), dict(ok(0.50, 0.70), ok=False, r=0.41), ok(0.90, 1.10)]
        self.assertEqual(sources.gate(doc, rec), ["1 windows do not hold the same sound as the preview: hairball 2 of 3 (r=0.41)"])
        dana["windows"]["hairball"] = [ok(0.10, 0.30), ok(0.50, 0.70), ok(0.95, 1.10)]           # a window moved since it was pinned
        self.assertEqual(sources.gate(doc, rec), ["1 windows changed in the recipe since they were pinned: hairball 3 of 3"])
        dana["windows"]["hairball"] = [ok(0.10, 0.30), ok(0.50, 0.70), ok(0.90, 1.10)]
        self.assertEqual(sources.gate(doc, rec), [])

    def test_credits_give_such_a_slot_one_row_and_say_the_made_in_code_part_is_partly_made_in_code(self):
        rec = with_hairball(mini_recipe(("love", "love/fs-1002-Bob.wav"), ("blip", "synth:blip")))
        doc = verify_all(blank_doc(rec))
        for i, e in enumerate(doc["sources"].values()):
            e["original"] = {"file": "x%d.wav" % i, "bytes": 5, "sha256": ("%02x" % (i + 1)) * 32}
        text = sources.credits_text(doc, rec)
        rows = [l.split("|")[1].strip() for l in text.splitlines() if l.startswith("| ") and not l.startswith("| Slot") and not l.startswith("|---")]
        self.assertEqual(rows, ["love", "hairball"])                                           # one row for the three windows
        self.assertIn("Made in code, with no source clip: blip (blip).", text)
        self.assertIn("Partly made in code, the recorded part credited above: hairball.", text)
        layers_only = with_hairball(mini_recipe(("blip", "synth:blip")), hairball_like()._replace(segments=[]))
        self.assertIn("Made in code, with no source clip: blip (blip), hairball (hairball_retch_plop).",
                      sources.credits_text(verify_all(blank_doc(layers_only)), layers_only))

if __name__ == "__main__":
    unittest.main()
EOF
```

- [ ] **Step 2: Run them to see them fail**

<!-- replay-fail -->
```bash
python3 -m unittest discover -s tests -p 'test_sound_sources.py' 2>&1 | tail -6
```

Expected: an `ImportError`/`ModuleNotFoundError` for `sources`, and no tests run.

- [ ] **Step 3: Write `tools/sounds/sources.py`**

<!-- replay -->
```bash
cat > tools/sounds/sources.py <<'EOF'
"""design/sounds/sources.json: where every shipped clip comes from, and what the build may do with it.

One entry per recorded clip of Your mix, keyed by the recipe's source name ('love/fs-64017-Department64.mp3').
An entry says who made the clip and where its page is, the licence as read on that page (when, and by whom),
the original file the owner downloaded (its name, size and SHA-256), the offset between that original and
the preview clip the recipes were written against, and the window each slot takes from it.

The build from the originals refuses a source that is not here, whose licence is not a verified CC0, whose
original is not pinned, or whose windows were not checked (spec section 5: "the build refuses any source
without a verified CC0 entry"). Standard library only; nothing here touches audio.
"""
from __future__ import annotations

import json
import os
import re
from collections import OrderedDict

import recipe

SOURCES_NAME = "sources.json"
CC0 = "CC0-1.0"
CC0_URLS = ("http://creativecommons.org/publicdomain/zero/1.0/", "https://creativecommons.org/publicdomain/zero/1.0/")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
FS_SOURCE = re.compile(r"^[a-z0-9]+/fs-(\d+)-(.+)\.[a-z0-9]+$")
EXTENSIONS = {"wave": (".wav",), "ogg vorbis": (".ogg",), "flac": (".flac",), "aiff": (".aif", ".aiff"),
              "mp3": (".mp3",), "m4a": (".m4a",)}       # the Type a Freesound page states, by extension


class SourcesError(ValueError):
    pass


def freesound_id(source):
    """'love/fs-64017-Department64.mp3' -> '64017'; None for a source that is not a Freesound clip."""
    found = FS_SOURCE.match(source)
    return found.group(1) if found else None


def freesound_author(source):
    found = FS_SOURCE.match(source)
    return found.group(2) if found else None


def page_url(source):
    """The clip's own Freesound page, which the licence re-check reads."""
    fid = freesound_id(source)
    return None if fid is None else "https://freesound.org/people/%s/sounds/%s/" % (freesound_author(source), fid)


def parse_duration(text):
    """'1:00.103' -> 60.103, '0:00.643' -> 0.643 (a Freesound page's Duration)."""
    found = re.match(r"^(\d+):(\d{2}(?:\.\d+)?)$", text.strip())
    if not found:
        raise SourcesError("duration %r is not m:ss.mmm" % text)
    return int(found.group(1)) * 60 + float(found.group(2))


def parse_size(text):
    """'110.9 KB' -> 113562 (bytes; Freesound's KB and MB are 1024-based)."""
    found = re.match(r"^(\d+(?:\.\d+)?)\s*(B|KB|MB|GB)$", text.strip())
    if not found:
        raise SourcesError("size %r is not '<number> KB' or '<number> MB'" % text)
    return int(round(float(found.group(1)) * {"B": 1, "KB": 1024, "MB": 1024 ** 2, "GB": 1024 ** 3}[found.group(2)]))


def load(path):
    """sources.json as a dict, checked for shape (see `problems`). Raises SourcesError."""
    with open(path, encoding="utf-8") as f:
        try:
            doc = json.load(f, object_pairs_hook=OrderedDict)
        except ValueError as e:
            raise SourcesError("%s: not valid JSON (%s)" % (path, e))
    bad = problems(doc)
    if bad:
        raise SourcesError("%s: %s" % (path, "; ".join(bad)))
    return doc


def save(path, doc):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2, ensure_ascii=False)
        f.write("\n")


def is_verified(e):
    """A verified CC0: the licence read on the clip's own page, with the page's CC0 link, the date it was
    read and who read it."""
    return (e.get("licence") == CC0 and e.get("licence_url") in CC0_URLS
            and isinstance(e.get("checked_on"), str) and bool(DATE.match(e["checked_on"]))
            and isinstance(e.get("checked_by"), str) and bool(e["checked_by"].strip()))


def problems(doc):
    """What is wrong with the shape of a sources.json document, as short sentences. Empty means fine.
    Not about completeness: an entry may still wait for its re-check or its download."""
    if not isinstance(doc, dict) or not isinstance(doc.get("sources"), dict):
        return ['must be an object with a "sources" object']
    out = []
    for source, e in doc["sources"].items():
        where = source
        if not isinstance(e, dict):
            out.append("%s: must be an object" % where)
            continue
        try:
            recipe._check_source(source, where)         # an excluded clip is never a source
        except recipe.RecipeError as err:
            out.append(str(err))
            continue
        if source.startswith("synth:"):
            out.append("%s: a made-in-code sound has no source entry" % where)
            continue
        fid = freesound_id(source)
        if fid is not None and e.get("page") != page_url(source):
            out.append("%s: page must be %s" % (where, page_url(source)))
        if fid is None and not str(e.get("page", "")).startswith("https://"):
            out.append("%s: page must be the clip's own https page" % where)
        want_author = freesound_author(source)
        if (e.get("author") != want_author) if want_author else not str(e.get("author", "")).strip():
            out.append("%s: author must be %s" % (where, want_author or "the maker's name"))
        if not isinstance(e.get("title"), str) or not e["title"].strip():
            out.append("%s: title is missing" % where)
        stated = e.get("stated")
        if not isinstance(stated, dict) or not {"type", "duration", "size"} <= set(stated):
            out.append("%s: stated needs type, duration and size as the page shows them" % where)
        else:
            try:
                parse_duration(stated["duration"])
                parse_size(stated["size"])
            except SourcesError as err:
                out.append("%s: %s" % (where, err))
        if any(e.get(k) is not None for k in ("licence", "licence_url", "checked_on", "checked_by")) and not is_verified(e):
            out.append("%s: a licence entry needs licence %s, the page's CC0 link, checked_on (YYYY-MM-DD) and "
                       "checked_by, or all four left null" % (where, CC0))
        orig = e.get("original")
        if orig is not None and not (isinstance(orig, dict) and SHA256.match(str(orig.get("sha256", "")))
                                     and isinstance(orig.get("file"), str) and orig["file"]
                                     and isinstance(orig.get("bytes"), int) and orig["bytes"] > 0):
            out.append("%s: original needs file, bytes and a lower-case sha256" % where)
        if e.get("offset_s") is not None and (isinstance(e["offset_s"], bool)
                                              or not isinstance(e["offset_s"], (int, float))):
            out.append("%s: offset_s must be a number" % where)
        if not isinstance(e.get("windows", {}), dict):
            out.append("%s: windows must be an object" % where)
    return out


def clip_uses(entry):
    """The recorded windows a recipe entry builds from, in order: [(source, start, end)], start and end in seconds on
    the source clip or None. An ordinary entry has one (its source and the window its recipe gives); a made-in-code
    entry has none. The hairball's entry (plan c1c-hairball) is a "placed" sound: its recorded part is
    `entry.segments`, a list of dicts with `source`, `start` and `end` (seconds on the clip) among others, and its
    made-in-code part is `entry.synth_layers`; the entry's own `start` and `end` cut the finished timeline and are not
    a clip window. This function and `originals.with_windows` are the only code that reads that shape: if c1c's
    final recipe names it differently, change those two."""
    segments = getattr(entry, "segments", None) or ()
    if segments:
        return [(seg["source"], seg["start"], seg["end"]) for seg in segments]
    if entry.source.startswith("synth:") or entry.source == "placed":
        return []
    return [(entry.source, entry.start, entry.end)]


def file_sources(rec):
    """OrderedDict source -> [slots that build from it], in slot order, for the recorded clips of a SetRecipe
    (Your mix); a slot is listed once per source however many windows it takes (the hairball takes three of one
    clip). The made-in-code sounds have no source."""
    out = OrderedDict()
    for slot, e in rec.entries.items():
        for source, _start, _end in clip_uses(e):
            if slot not in out.setdefault(source, []):
                out[source].append(slot)
    return out


def slot_windows(rec, slot, source):
    """[(start, end)] the recipe gives for each window `slot` takes from `source`, in order (None for a window the
    build's automatic trim chooses)."""
    return [(a, b) for s, a, b in clip_uses(rec.entries[slot]) if s == source]


def _say(count_sentence, names, limit=4):
    """'3 sources have no verified CC0 entry: a, b, c' (at most `limit` names, then 'and N more'); [] for none."""
    names = list(names)
    if not names:
        return []
    shown = ", ".join(names[:limit]) + (" and %d more" % (len(names) - limit) if len(names) > limit else "")
    return ["%d %s: %s" % (len(names), count_sentence, shown)]


def licence_problems(doc, rec):
    """The recorded clips of `rec` that may not ship: not in sources.json, or without a verified CC0."""
    uses = file_sources(rec)
    absent = [s for s in uses if s not in doc["sources"]]
    unverified = [s for s in uses if s in doc["sources"] and not is_verified(doc["sources"][s])]
    return (_say("clips are not in %s" % SOURCES_NAME, absent)
            + _say("clips have no verified CC0 entry (licence, the page's link, date and checker)", unverified))


def pin_problems(doc, rec):
    return _say("originals are not pinned (file, size and SHA-256)",
                [s for s in file_sources(rec) if not (doc["sources"].get(s) or {}).get("original")])


def window_problems(doc, rec):
    """Each slot's window must be checked against the original (the align step) and must still be the recipe's
    own window when the recipe gives one."""
    no_offset, unchecked, differ, stale = [], [], [], []
    for source, slots in file_sources(rec).items():
        e = doc["sources"].get(source) or {}
        if e.get("offset_s") is None:
            no_offset.append(source)
        for slot in slots:
            want = slot_windows(rec, slot, source)
            got = (e.get("windows") or {}).get(slot) or []
            names = [slot if len(want) == 1 else "%s %d of %d" % (slot, n + 1, len(want)) for n in range(len(want))]
            if len(got) != len(want):
                unchecked += names
                continue
            for name, (start, end), w in zip(names, want, got):
                if w.get("ok") is not True:
                    differ.append("%s (r=%s)" % (name, w.get("r")))
                if start is not None and end is not None and (
                        abs(w["start"] - start) > 1e-6 or abs(w["end"] - end) > 1e-6):
                    stale.append(name)
    return (_say("clips have no measured offset between preview and original", no_offset)
            + _say("windows are not pinned and checked", unchecked)
            + _say("windows do not hold the same sound as the preview", differ)
            + _say("windows changed in the recipe since they were pinned", stale))


def gate(doc, rec):
    """Everything the build from the originals needs before it writes a file. Empty means go."""
    return licence_problems(doc, rec) + pin_problems(doc, rec) + window_problems(doc, rec)


def find_original(folder, source, entry):
    """The downloaded original of a source in `folder`: the pinned file name if there is one, otherwise the
    one file Freesound named '<id>__<user>__<name>.<ext>'. Raises SourcesError when there is none or two."""
    pinned = (entry.get("original") or {}).get("file")
    if pinned:
        path = os.path.join(folder, pinned)
        if not os.path.isfile(path):
            raise SourcesError("%s: %s is not in %s" % (source, pinned, folder))
        return path
    fid = freesound_id(source)
    if fid is None:
        raise SourcesError("%s: no way to name its original; pin it by hand" % source)
    found = sorted(n for n in os.listdir(folder) if n.startswith(fid + "__") and not n.startswith("."))
    if not found:
        raise SourcesError("%s: no file named %s__* in %s" % (source, fid, folder))
    if len(found) > 1:
        raise SourcesError("%s: more than one file for it in %s: %s" % (source, folder, ", ".join(found)))
    return os.path.join(folder, found[0])


def type_matches(entry, path):
    """The file's extension is the Type the page states (a preview MP3 saved by mistake is not a Wave)."""
    said = entry["stated"]["type"].lower()
    ext = os.path.splitext(path)[1].lower()
    for key, exts in EXTENSIONS.items():
        if said.startswith(key):
            return ext in exts
    return True


def _made_by(entry):
    """What makes the made-in-code part of an entry: 'yawn' for synth:yawn, the layer names of a placed sound, or ''."""
    if entry.source.startswith("synth:"):
        return entry.source[6:]
    return ", ".join(layer["name"] for layer in getattr(entry, "synth_layers", None) or ())


def _cell(text):
    return str(text).replace("|", "\\|")


def credits_text(doc, rec):
    """docs/SOUND-CREDITS.md: every shipped clip, written from sources.json so the two cannot disagree."""
    lines = ["# Sound credits", "",
             "NotchMeow's sounds are built from clips released under Creative Commons Zero (CC0 1.0), which asks "
             "for no credit. Each clip is credited anyway, because its maker deserves it (Breviceps asks for it). "
             "The mixes built from them, and the sounds made in code, are NotchMeow's own and stay under "
             "`LICENSE-ASSETS.md`.", "",
             "This file is written from `design/sounds/sources.json` by `python3 tools/sounds/originals.py credits`. "
             "Do not edit it by hand: `tests/test_sound_shipped.py` fails when the two differ.", "",
             "| Slot | Title | Author | Page | Licence | Checked on | SHA-256 of the original |",
             "|---|---|---|---|---|---|---|"]
    for slot, ent in rec.entries.items():
        for source in OrderedDict((s, None) for s, _a, _b in clip_uses(ent)):
            e = doc["sources"][source]
            lines.append("| %s | %s | %s | <%s> | CC0 1.0 | %s | `%s` |" % (
                slot, _cell(e["title"]), _cell(e["author"]), e["page"], e["checked_on"], e["original"]["sha256"]))
    made = [("%s (%s)" % (s, _made_by(ent))) for s, ent in rec.entries.items() if not clip_uses(ent)]
    partly = [s for s, ent in rec.entries.items() if clip_uses(ent) and _made_by(ent)]
    lines += ["", "Made in code, with no source clip: %s." % ", ".join(made)]
    if partly:
        lines += ["", "Partly made in code, the recorded part credited above: %s." % ", ".join(partly)]
    lines.append("")
    return "\n".join(lines)


def download_list_text(doc, rec, folder):
    """The list the owner works from: every original to get, with its page and what the page says about it."""
    uses = file_sources(rec)
    freesound = [s for s in uses if freesound_id(s) is not None]
    direct = [s for s in uses if freesound_id(s) is None]
    lines = ["# Originals to download", "",
             "Save every file into `%s` and leave its name as the site gave it (Freesound names it "
             "`<id>__<user>__<name>.<ext>`). %d clips." % (folder, len(uses)), ""]

    def row(source):
        e = doc["sources"][source]
        st = e["stated"]
        said = ", ".join(str(st[k]) for k in ("type", "duration", "size", "sample_rate", "bit_depth", "channels")
                         if st.get(k))
        name = ("the file name starts with `%s__`" % freesound_id(source) if freesound_id(source)
                else "save it as `%s`" % e.get("download", {}).get("file", "(name it in sources.json)"))
        return ["- [ ] **%s** by %s, for %s" % (_cell(e["title"]), e["author"], ", ".join(uses[source])),
                "  - page: %s" % e["page"],
                "  - the page says: %s" % said,
                "  - %s" % name]

    lines += ["## Needs your Freesound sign-in: download these yourself (%d)" % len(freesound), ""]
    for s in freesound:
        lines += row(s)
    lines += ["", "## Direct links, with your OK before anything is downloaded (%d)" % len(direct), ""]
    for s in direct:
        lines += row(s) + ["  - direct link: %s" % doc["sources"][s].get("download", {}).get("url", "(missing)")]
    if not direct:
        lines += ["None: Your mix uses no BigSoundBank clip."]
    lines.append("")
    return "\n".join(lines)
EOF
```

- [ ] **Step 4: Write the seed of `sources.json`**

The seed script holds what the 23 clip pages said on 2026-10-05 (copied from the pages, then cross-checked against their raw HTML: every figure matched). It is a one-off in `${TMPDIR:-/tmp}`; only its output is committed.

<!-- replay -->
```bash
cat > "${TMPDIR:-/tmp}/c2-make-seed.py" <<'EOF'
"""One-off: writes design/sounds/sources.json, the seed of the source list. Run from the repository root, on a
checkout that has plan c1c-hairball merged (the hairball's recorded clip, Cat Coughing by har2h, is one of the 23).

One entry per recorded clip of Your mix. `stated` holds what each clip's own Freesound page said on 2026-10-05
(Type, Duration, File size and the rest of its Sound information, as printed); nothing is checked, downloaded or
measured yet. Task 5 re-reads the pages, so a figure that is wrong here is corrected there, and said."""
import sys
from collections import OrderedDict

sys.path.insert(0, "tools/sounds")
import recipe  # noqa: E402
import sources  # noqa: E402

sets = recipe.load_recipes("design/sounds/sets")
mine = recipe.load_mine("design/sounds/sets/mine.json", sets, recipe.load_round2("design/sounds/sets/round2.json", sets))


def wav(duration, size, rate, bits, channels):
    return OrderedDict([("type", "Wave (.wav)"), ("duration", duration), ("size", size), ("sample_rate", "%d.0 Hz" % rate),
                        ("bit_depth", "%d bit" % bits), ("channels", channels)])


FACTS = {  # Freesound id: (title as the page shows it, its Sound information)
    "64017": ("kitten22.wav", wav("0:00.643", "110.9 KB", 44100, 16, "Stereo")),
    "436542": ("Cat short purr", wav("0:01.322", "341.8 KB", 44100, 24, "Stereo")),
    "64008": ("kitten13.wav", wav("0:00.850", "146.5 KB", 44100, 16, "Stereo")),
    "64007": ("kitten12.wav", wav("0:00.670", "115.5 KB", 44100, 16, "Stereo")),
    "415107": ("catwhirr.wav", wav("0:00.840", "145.5 KB", 44100, 16, "Stereo")),
    "448084": ("Cute Kitten Meow", wav("0:00.604", "104.2 KB", 44100, 16, "Stereo")),
    "64005": ("kitten10.wav", wav("0:00.648", "111.7 KB", 44100, 16, "Stereo")),
    "64015": ("kitten20.wav", wav("0:00.880", "151.7 KB", 44100, 16, "Stereo")),
    "451250": ("cat chirp.wav", wav("0:07.815", "1.4 MB", 48000, 16, "Stereo")),
    "260881": ("Cat purr.wav", wav("1:00.103", "8.3 MB", 48000, 24, "Mono")),
    "730097": ("Cat licking her paw", wav("0:13.375", "1.8 MB", 48000, 24, "Mono")),
    "730102": ("Cat MmRrm noise", wav("0:01.817", "255.9 KB", 48000, 24, "Mono")),
    "499362": ("Cat_Hunting.wav", wav("1:06.775", "18.4 MB", 48000, 24, "Stereo")),
    "64012": ("kitten17.wav", wav("0:00.950", "163.8 KB", 44100, 16, "Stereo")),
    "487999": ("Cardboard_Small Impact_06.wav", wav("0:00.416", "132.2 KB", 48000, 24, "Stereo")),
    "541360": ("Sleigh Bell Short 01.wav", wav("0:00.214", "18.5 KB", 44100, 16, "Mono")),
    "364740": ("open-cardboard-box-compartment.wav", wav("0:01.000", "282.0 KB", 48000, 24, "Stereo")),
    "320847": ("Item placed", wav("0:00.560", "114.9 KB", 48000, 16, "Stereo")),
    "371274": ("Water Click", wav("0:00.108", "61.4 KB", 96000, 24, "Stereo")),
    "371278": ("Ceramic Click", wav("0:00.153", "86.5 KB", 96000, 24, "Stereo")),
    "402453": ("pouring cat food", wav("0:00.205", "38.6 KB", 48000, 32, "Mono")),
    "561726": ("Cat Coughing.wav", wav("0:20.995", "3.9 MB", 48000, 16, "Stereo")),
    "258269": ("Mouth pop", OrderedDict([("type", "Ogg Vorbis (.ogg)"), ("duration", "0:00.323"), ("size", "9.2 KB"),
                                         ("sample_rate", "44100.0 Hz"), ("bitrate", "232 kbps"), ("channels", "Stereo")])),
}

doc = OrderedDict()
doc["title"] = "NotchMeow sound sources"
doc["note"] = ("One entry per recorded clip of Your mix (design/sounds/sets/mine.json). 'stated' is what the clip's own "
               "page said on stated_read_on; the licence re-check re-reads it. tools/sounds/sources.py says what the "
               "build demands of each entry.")
doc["stated_read_on"] = "2026-10-05"
doc["sources"] = OrderedDict()
for source in sources.file_sources(mine):
    title, stated = FACTS[sources.freesound_id(source)]
    doc["sources"][source] = OrderedDict([
        ("title", title), ("author", sources.freesound_author(source)), ("page", sources.page_url(source)),
        ("stated", stated), ("licence", None), ("licence_url", None), ("checked_on", None), ("checked_by", None),
        ("original", None), ("offset_s", None), ("windows", OrderedDict())])
assert set(FACTS) == {sources.freesound_id(s) for s in doc["sources"]}, "the facts table does not match Your mix"
sources.save("design/sounds/sources.json", doc)
print("wrote design/sounds/sources.json: %d clips" % len(doc["sources"]))
EOF
```

<!-- replay -->
```bash
python3 "${TMPDIR:-/tmp}/c2-make-seed.py"
```

Expected: `wrote design/sounds/sources.json: 23 clips`.

- [ ] **Step 5: Run the tests**

<!-- replay -->
```bash
python3 -m unittest discover -s tests -p 'test_sound_sources.py' 2>&1 | tail -4
bash scripts/test-sound-build.sh 2>&1 | tail -6
```

Expected: `Ran 21 tests ... OK`; the script ends with `Ran N+29 tests ... OK` (the 8 of Task 1 and these 21) followed by the three recipe-check lines.

- [ ] **Step 6: Commit**

<!-- replay-commit -->
```bash
git add tools/sounds/sources.py design/sounds/sources.json tests/sound_pack_support.py tests/test_sound_sources.py
git commit -m "feat(sounds): sources.json and the licence gate: a clip without a verified CC0 entry cannot ship

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 3: The window rule: does an original still hold the sound a window held?

The recipes were written against the preview clips; Stage 2 builds from the originals. Originals and previews can differ in offset, in length, or be a different take altogether, so each recipe window gets a check that it still holds the same sound. **The rule (settled here, in `align.py`):**

1. **Decide the window once, on the preview.** For a recipe entry with a window, that is its `start`..`end`. For an entry with none, it is what the build's automatic trim chooses on the preview (silence dropped, then the loudest part that fits). That span is then written out as an explicit window and pinned (Task 7), so the original is cut exactly where the owner's ears heard the preview, and a quieter or hissier original cannot move an automatic trim.
2. **Find the offset.** Search the original for the preview's window, within ±100 ms: a coarse pass on 1 ms loudness envelopes of the window plus 150 ms either side, then a fine pass on the waveform (low-passed at 3 kHz and cut to 8 kHz, which the MP3 keeps faithfully) in steps of 0.125 ms. The best lag is the clip's `offset_s`; the build moves the original by it, so a recipe window means the same sound it meant on the preview.
3. **Same sound.** After the move, the waveform of the original's window must correlate with the preview's window at **0.80 or better** (a residual of ±1 ms is allowed). Below that the window fails, and the build refuses to ship it.

Calibrated on the 24 real windows of Your mix (preview clips, 2026-10-05): the same window through a gain change, noise at −40 dB or a 5 kHz low-pass (all harsher than the MP3 codec) scores 0.87 or better; 548 pairs of different real clips, each searched for its best offset, score 0.35 at the most, and none passes. A second test, the time a window stays within 30 dB of its peak, was tried and dropped: hiss in the original lifted a quiet fade above the threshold and moved it by 40 ms or more while the waveform still matched at 0.99. The offset is good to 0.125 ms; a one-sample (0.02 ms) difference between how two `afconvert` paths resample is inaudible and is not corrected.

To pin a window the build's trims have to say where they cut. `dsp.py` gains `*_span` twins (`seconds_span`, `trim_silence_span`, `loudest_window_span`, `auto_trim_span`) that return `(a, b)`, and the old functions become one-line uses of them; a test pins that the new spans cut exactly where the old functions did. `pipeline.source_span(entry, clip, shift)` states how `_source` picks an *ordinary* entry's window, which is where the pinned windows come from. `_source` itself is left untouched (c1c-hairball changes the build next to it), and a test pins that the two agree.

**Files:**
- Modify: `tools/sounds/dsp.py` (`seconds_slice`, `trim_silence`, `loudest_window`, `auto_trim` and their new `*_span` twins)
- Modify: `tools/sounds/pipeline.py` (`source_span` added before `_source`; `_source` is not touched)
- Create: `tools/sounds/align.py`
- Modify: `tests/sound_pack_support.py` (append `voice`)
- Create: `tests/test_sound_align.py`

**Interfaces:**
- Consumes: `dsp.lowpass`, `dsp.SR`, `dsp.db_to_lin`, `recipe.SLOTS` (for `source_span`'s window length); the Task 2 support module.
- Produces (`dsp`): `seconds_span(n, start=None, end=None) -> (a, b)`, `trim_silence_span(x)`, `loudest_window_span(x, length)`, `auto_trim_span(x, max_len_s)`, each `(a, b)` in samples; the old functions return `list(x[a:b])` of them. Produces (`pipeline`): `source_span(entry, clip, shift) -> (a, b)` for an ordinary entry. Produces (`align`): `MIN_R = 0.80`, `envelope(x)`, `pearson(a, b)`, `decimate(x)`, `padded(x, a, b)`, `measure_offset(p, o, a, b) -> (offset_samples, r)` where `o[i + offset]` matches `p[i]`, `shift_clip(o, offset) -> list`, `Verdict(r, ok)`, `window_verdict(p, q, a, b) -> Verdict` (`q` already moved into preview time). Produces (tests): `voice(seed, seconds, lead, tail)` in the support module.

- [ ] **Step 1: Write the failing tests**

<!-- replay -->
```bash
cat >> tests/sound_pack_support.py <<'EOF'


def voice(seed, seconds=0.7, lead=0.15, tail=0.15):
    """A made-up meow: a gliding tone with three partials, a little noise and a two-hump envelope, with silence
    either side. The seed picks its pitch and glide, so two seeds are two different takes."""
    rng = random.Random(seed)
    f0, glide = 330.0 + 45.0 * (seed % 7), (60.0 + 13.0 * seed) * (-1) ** seed
    out, phase = [], 0.0
    for i in range(int(seconds * SR)):
        t = i / SR
        phase += 2 * math.pi * (f0 + glide * t + 25.0 * math.sin(2 * math.pi * 5.5 * t)) / SR
        env = math.sin(math.pi * t / seconds) ** 2 * (0.75 + 0.25 * math.sin(2 * math.pi * 3.0 * t + seed))
        out.append(0.4 * env * (math.sin(phase) + 0.5 * math.sin(2 * phase) + 0.25 * math.sin(3 * phase)
                                + 0.05 * (rng.random() - 0.5)))
    return [0.0] * int(lead * SR) + out + [0.0] * int(tail * SR)
EOF
```

<!-- replay -->
```bash
cat > tests/test_sound_align.py <<'EOF'
"""Tests for the window rule: does an original still hold the sound the preview's window held? (sub-project C, stage 2,
task 3). Standard library only."""
import random
import unittest

from sound_pack_support import SR, voice

import align  # noqa: E402
import dsp  # noqa: E402
import pipeline  # noqa: E402
import recipe  # noqa: E402
from test_sound_build import DictLoader, entry  # noqa: E402


class TestSpans(unittest.TestCase):
    """The trims now also say where they cut, so a window can be pinned. They must cut exactly as before."""

    def test_every_span_is_the_slice_the_old_function_returned(self):
        rng = random.Random(3)
        for _ in range(12):
            x = [0.0] * rng.randrange(0, 3000) + voice(rng.randrange(1, 9), rng.uniform(0.05, 0.9)) + [0.0] * rng.randrange(0, 3000)
            a, b = dsp.trim_silence_span(x)
            self.assertEqual(dsp.trim_silence(x), x[a:b])
            for length in (900, 20000, 200000):
                i, j = dsp.loudest_window_span(x, length)
                self.assertEqual(dsp.loudest_window(x, length), x[i:j])
            for max_len in (0.05, 0.4, 1.5):
                a, b = dsp.auto_trim_span(x, max_len)
                self.assertEqual(dsp.auto_trim(x, max_len), x[a:b])
                self.assertLessEqual(b - a, int(max_len * SR))

    def test_a_silent_or_empty_clip_has_a_whole_clip_span_and_no_crash(self):
        self.assertEqual(dsp.trim_silence_span([0.0] * 500), (0, 500))
        self.assertEqual(dsp.trim_silence_span([]), (0, 0))
        self.assertEqual(dsp.auto_trim_span([], 1.5), (0, 0))

    def test_seconds_span_clamps_like_seconds_slice(self):
        self.assertEqual(dsp.seconds_span(1000, None, None), (0, 1000))
        self.assertEqual(dsp.seconds_span(1000, 0.0, 0.01), (0, 480))
        self.assertEqual(dsp.seconds_span(1000, 0.01, 5.0), (480, 1000))
        self.assertEqual(dsp.seconds_span(1000, 5.0, 6.0), (0, 0))               # past the end: empty
        self.assertEqual(dsp.seconds_slice(list(range(1000)), 0.01, 5.0), list(range(480, 1000)))

    def test_the_pipeline_cuts_where_source_span_says(self):
        """`source_span` is a second statement of how `pipeline._source` picks a window (the pinned windows come from
        it), so a test pins that the two agree, for a window, for an automatic trim and for one that a shift shortens."""
        clip = voice(2, 0.5, lead=0.3, tail=0.3)
        long_clip = voice(3, 2.5, lead=0.3, tail=0.3)
        explicit = entry("love", "love/c.wav", start=0.2, end=0.5)
        self.assertEqual(pipeline.source_span(explicit, clip, 0.0), (9600, 24000))
        for e, shift, source in ((entry("love", "love/c.wav"), 0.0, clip), (explicit, 0.0, clip),
                                 (entry("greet", "love/c.wav"), 7.0, long_clip), (entry("greet", "love/c.wav"), 0.0, long_clip)):
            a, b = pipeline.source_span(e, source, shift)
            got = pipeline._source(e, recipe.SLOTS[e.slot], DictLoader({"love/c.wav": source}), shift)
            self.assertEqual(got, list(source[a:b]), (e.slot, e.start, shift))
        a, b = pipeline.source_span(entry("greet", "love/c.wav"), long_clip, 12.0)             # +12 st: room for 3 s
        self.assertLessEqual(b - a, int(3.0 * SR))


class TestAlign(unittest.TestCase):
    def setUp(self):
        self.p = voice(2)                                   # the preview: 1.0 s, the sound from 0.15 s to 0.85 s
        self.a, self.b = int(0.2 * SR), int(0.8 * SR)       # the window a recipe took

    def offset_of(self, original):
        return align.measure_offset(self.p, original, self.a, self.b)

    def verdict_of(self, original):
        off, _ = self.offset_of(original)
        return align.window_verdict(self.p, align.shift_clip(original, off), self.a, self.b)

    def test_pearson_and_envelope(self):
        self.assertAlmostEqual(align.pearson([1, 2, 3, 4], [2, 4, 6, 8]), 1.0)
        self.assertAlmostEqual(align.pearson([1, 2, 3, 4], [8, 6, 4, 2]), -1.0)
        self.assertEqual(align.pearson([1, 1, 1], [1, 2, 3]), 0.0)               # a flat list correlates with nothing
        self.assertEqual(align.pearson([], []), 0.0)
        self.assertEqual(len(align.envelope([0.5] * 4800)), 100)
        self.assertAlmostEqual(align.envelope([0.5] * 96)[0], 0.5)

    def test_shift_clip_moves_the_original_into_preview_time(self):
        o = [1.0, 2.0, 3.0, 4.0]
        self.assertEqual(align.shift_clip(o, 2), [3.0, 4.0])
        self.assertEqual(align.shift_clip(o, -2), [0.0, 0.0, 1.0, 2.0, 3.0, 4.0])
        self.assertEqual(align.shift_clip(o, 0), o)

    def test_the_offset_is_found_whichever_way_the_original_is_shifted(self):
        for ms in (0, 37, -42, 95, -100):
            original = align.shift_clip(self.p, -ms * 48)               # the same sound, `ms` later in the original
            off, r = self.offset_of(original)
            self.assertLessEqual(abs(off - ms * 48), 6, ms)            # within a quarter millisecond
            self.assertGreater(r, 0.99, ms)

    def test_a_shifted_original_holds_the_same_sound_once_shifted_back(self):
        for ms in (0, 25, -30):
            v = self.verdict_of(align.shift_clip(self.p, -ms * 48))
            self.assertTrue(v.ok, (ms, v))
            self.assertGreater(v.r, 0.99)

    def test_a_quieter_noisier_duller_original_still_holds_the_same_sound(self):
        rng = random.Random(1)
        dull = dsp.lowpass([0.3 * v + rng.gauss(0, 0.002) for v in self.p], 7000.0)
        v = self.verdict_of(dull)
        self.assertTrue(v.ok, v)

    def test_another_take_of_the_cat_does_not(self):
        for seed in (3, 4, 5):
            v = self.verdict_of(voice(seed))
            self.assertFalse(v.ok, (seed, v))
            self.assertLess(v.r, 0.5)

    def test_an_original_that_ends_inside_the_window_does_not(self):
        v = self.verdict_of(self.p[:int(0.45 * SR)])                      # 0.35 s of the 0.6 s window is missing
        self.assertFalse(v.ok, v)

    def test_an_original_at_another_speed_does_not(self):
        faster = dsp.pitch_shift(self.p, 1.0)                              # 6 % faster: the window no longer lines up
        self.assertFalse(self.verdict_of(faster).ok)

    def test_hiss_in_the_original_does_not_fail_a_window_that_matches(self):
        rng = random.Random(2)
        hissy = [v + rng.gauss(0, 0.03) for v in self.p]                      # hiss at about -30 dBFS
        v = self.verdict_of(hissy)
        self.assertTrue(v.ok, v)
        self.assertGreater(v.r, 0.97)


if __name__ == "__main__":
    unittest.main()
EOF
```

- [ ] **Step 2: Run them to see them fail**

<!-- replay-fail -->
```bash
python3 -m unittest discover -s tests -p 'test_sound_align.py' 2>&1 | tail -6
```

Expected: `ModuleNotFoundError: No module named 'align'`, and no tests run.

- [ ] **Step 3: The span twins in `dsp.py` and `source_span` in `pipeline.py`**

<!-- replay -->
```bash
python3 - <<'EOF'
def edit(path, old, new):
    with open(path, encoding="utf-8") as f:
        s = f.read()
    assert s.count(old) == 1, "%s: the text to replace is not there exactly once:\n%s" % (path, old)
    with open(path, "w", encoding="utf-8") as f:
        f.write(s.replace(old, new))


D = "tools/sounds/dsp.py"
edit(D, '''def seconds_slice(x, start=None, end=None, sr=SR):
    a = 0 if start is None else max(0, int(round(start * sr)))
    b = len(x) if end is None else min(len(x), int(round(end * sr)))
    return list(x[a:b]) if b > a else []
''', '''def seconds_span(n, start=None, end=None, sr=SR):
    """(a, b) sample indices of the part of an n-sample clip between two times; (0, 0) when it is empty."""
    a = 0 if start is None else max(0, int(round(start * sr)))
    b = n if end is None else min(n, int(round(end * sr)))
    return (a, b) if b > a else (0, 0)


def seconds_slice(x, start=None, end=None, sr=SR):
    a, b = seconds_span(len(x), start, end, sr)
    return list(x[a:b])
''')
edit(D, '''def trim_silence(x, sr=SR, floor_db=-35.0, pad_ms=5.0):
    """Cut leading and trailing frames more than |floor_db| below the loudest 10 ms frame."""
    frame = int(sr * 0.010)
    env = frame_rms(x, frame)
    if not env or max(env) == 0.0:
        return list(x)
    thr = max(env) * db_to_lin(floor_db)
    idx = [i for i, e in enumerate(env) if e >= thr]
    pad = int(sr * pad_ms / 1000.0)
    a = max(0, idx[0] * frame - pad)
    b = min(len(x), (idx[-1] + 1) * frame + pad)
    return list(x[a:b])


def loudest_window(x, length, sr=SR):
    """The `length`-sample window with the most energy, searched in 10 ms steps."""
    if len(x) <= length:
        return list(x)
    cs = [0.0]
    for v in x:
        cs.append(cs[-1] + v * v)
    step = int(sr * 0.010)
    best_i, best_e = 0, -1.0
    for i in range(0, len(x) - length + 1, step):
        e = cs[i + length] - cs[i]
        if e > best_e:
            best_i, best_e = i, e
    return list(x[best_i:best_i + length])


def auto_trim(x, max_len_s, sr=SR):
    """No explicit trim: drop the silence, then keep the loudest window of at most max_len_s."""
    return loudest_window(trim_silence(x, sr), int(max_len_s * sr), sr)
''', '''def trim_silence_span(x, sr=SR, floor_db=-35.0, pad_ms=5.0):
    """(a, b) of the part of x that trim_silence keeps."""
    frame = int(sr * 0.010)
    env = frame_rms(x, frame)
    if not env or max(env) == 0.0:
        return 0, len(x)
    thr = max(env) * db_to_lin(floor_db)
    idx = [i for i, e in enumerate(env) if e >= thr]
    pad = int(sr * pad_ms / 1000.0)
    return max(0, idx[0] * frame - pad), min(len(x), (idx[-1] + 1) * frame + pad)


def trim_silence(x, sr=SR, floor_db=-35.0, pad_ms=5.0):
    """Cut leading and trailing frames more than |floor_db| below the loudest 10 ms frame."""
    a, b = trim_silence_span(x, sr, floor_db, pad_ms)
    return list(x[a:b])


def loudest_window_span(x, length, sr=SR):
    """(a, b) of the `length`-sample window with the most energy, searched in 10 ms steps."""
    if len(x) <= length:
        return 0, len(x)
    cs = [0.0]
    for v in x:
        cs.append(cs[-1] + v * v)
    step = int(sr * 0.010)
    best_i, best_e = 0, -1.0
    for i in range(0, len(x) - length + 1, step):
        e = cs[i + length] - cs[i]
        if e > best_e:
            best_i, best_e = i, e
    return best_i, best_i + length


def loudest_window(x, length, sr=SR):
    a, b = loudest_window_span(x, length, sr)
    return list(x[a:b])


def auto_trim_span(x, max_len_s, sr=SR):
    """(a, b) of the part of x that auto_trim keeps: the silence dropped, then the loudest window of at most
    max_len_s."""
    a, b = trim_silence_span(x, sr)
    i, j = loudest_window_span(x[a:b], int(max_len_s * sr), sr)
    return a + i, a + j


def auto_trim(x, max_len_s, sr=SR):
    """No explicit trim: drop the silence, then keep the loudest window of at most max_len_s."""
    a, b = auto_trim_span(x, max_len_s, sr)
    return list(x[a:b])
''')

# pipeline.py: where an entry's window falls in its clip. _source is left alone; a test pins that the two agree.
edit("tools/sounds/pipeline.py", "def _source(entry, info, loader, shift):", '''def source_span(entry, clip, shift):
    """(a, b) sample indices of the part of `clip` that an ordinary entry builds from: its window, or, with no
    explicit trim, what the automatic trim keeps (silence dropped, then the loudest part that fits after the shift).
    `_source` below cuts the same way; tests/test_sound_align.py pins that the two agree."""
    if entry.start is None and entry.end is None:
        return dsp.auto_trim_span(clip, SLOTS[entry.slot].max_len * 2.0 ** (shift / 12.0))
    return dsp.seconds_span(len(clip), entry.start, entry.end)


def _source(entry, info, loader, shift):''')
EOF
```

- [ ] **Step 4: Write `tools/sounds/align.py`**

<!-- replay -->
```bash
cat > tools/sounds/align.py <<'EOF'
"""Does an original still hold the same sound as the preview clip a window was chosen on?

The recipes were written against the Freesound preview clips (MP3, decoded to 48 kHz mono). Stage 2 builds
from the full-quality originals instead, and an original can differ from its preview in offset (a trimmed
start), in length, or be a different file altogether. The rule, applied to every window of every clip:

  1. Offset. Search the original for the preview's window, within +-100 ms: a coarse pass on 1 ms
     loudness envelopes, then a fine pass on the waveform (low-passed at 3 kHz and cut to 8 kHz, which the
     MP3 keeps faithfully) in steps of 0.125 ms. The best lag is the clip's offset; the build shifts the
     original by it, so every recipe window keeps its meaning.
  2. Same sound. After the shift, the waveform of the original's window must correlate with the preview's
     window at 0.80 or better (a residual of +-1 ms is allowed). A window that runs off the end of a shorter
     original, a different take of the same cat, and a clip at another speed all fall far below that.

Calibrated on the 24 real windows of Your mix (preview clips, 2026-10-05): the same window through a gain
change, noise at -40 dB, or a 5 kHz low-pass (all harsher than the MP3) scores 0.87 or better; 548 pairs of
different real clips, each searched for its best offset, score 0.35 at the most and none passes. (A second
test, the time a window stays within 30 dB of its peak, was tried and dropped: hiss in an original lifts a
quiet fade above the threshold and moves it by 40 ms or more, while the waveform still matches at 0.99.)

Pure Python, standard library only. Samples are 48 kHz mono lists of floats.
"""
from __future__ import annotations

import math
from collections import namedtuple

import dsp
from dsp import SR

HOP = SR // 1000            # 1 ms: the coarse envelope
DECIMATE = 6                # 48 kHz -> 8 kHz for the fine pass
FINE_HZ = 3000.0
MAX_LAG_S = 0.100
MARGIN_S = 0.150            # context around a window when measuring the offset
FINE_SPAN_MS = 3            # the fine pass looks +-3 ms around the coarse lag
MIN_R = 0.80
RESIDUAL_MS = 1

Verdict = namedtuple("Verdict", "r ok")


def envelope(x):
    """RMS of every 1 ms block."""
    return [math.sqrt(sum(v * v for v in x[i:i + HOP]) / HOP) for i in range(0, len(x) - HOP + 1, HOP)]


def pearson(a, b):
    """Correlation of two equal-length lists; 0.0 when either is flat."""
    n = min(len(a), len(b))
    if n < 2:
        return 0.0
    ma, mb = sum(a[:n]) / n, sum(b[:n]) / n
    sab = saa = sbb = 0.0
    for i in range(n):
        da, db = a[i] - ma, b[i] - mb
        sab += da * db
        saa += da * da
        sbb += db * db
    return sab / math.sqrt(saa * sbb) if saa > 0.0 and sbb > 0.0 else 0.0


def decimate(x):
    return dsp.lowpass(dsp.lowpass(x, FINE_HZ), FINE_HZ)[::DECIMATE]


def padded(x, a, b):
    """x[a:b] with zeros where the range runs outside the clip."""
    out = [0.0] * max(0, -a) + list(x[max(a, 0):max(b, 0)])
    return out + [0.0] * (b - a - len(out))


def measure_offset(p, o, a, b):
    """How much later the preview's window p[a:b] sits in the original o: returns (offset in samples, r).
    o[i + offset] matches p[i]. r is the waveform correlation at that offset, 0 to 1."""
    ra, rb = max(0, a - int(MARGIN_S * SR)), min(len(p), b + int(MARGIN_S * SR))
    ra -= ra % HOP
    rb -= (rb - ra) % HOP
    reach = int(MAX_LAG_S * SR)
    pad = reach + FINE_SPAN_MS * HOP                    # a multiple of DECIMATE, so the fine grid lines up
    wide = padded(o, ra - pad, rb + pad)
    pe = envelope(p[ra:rb])
    oe = envelope(wide)
    lead = pad // HOP                                   # envelope blocks before the region starts
    steps = reach // HOP
    best_ms, best_r = 0, -2.0
    for lag in sorted(range(-steps, steps + 1), key=abs):
        r = pearson(pe, oe[lead + lag: lead + lag + len(pe)])
        if r > best_r + 1e-12:
            best_ms, best_r = lag, r
    pd, od = decimate(p[ra:rb]), decimate(wide)
    best_lag, best = 0, -2.0
    span = FINE_SPAN_MS * HOP // DECIMATE
    centre = best_ms * HOP // DECIMATE
    for k in sorted(range(-span, span + 1), key=abs):
        start = pad // DECIMATE + centre + k
        r = pearson(pd, od[start:start + len(pd)])
        if r > best + 1e-12:
            best_lag, best = (centre + k) * DECIMATE, r
    return best_lag, max(best, 0.0)


def shift_clip(o, offset):
    """The original moved into preview time: the result's sample i is o[i + offset]."""
    return list(o[offset:]) if offset >= 0 else [0.0] * -offset + list(o)


def window_verdict(p, q, a, b):
    """Does q[a:b] (the original, already shifted into preview time) hold the same sound as p[a:b]?"""
    pd, qd = decimate(p[a:b]), decimate(padded(q, a, b))
    r = max((pearson(pd[max(0, -k):], qd[max(0, k):]) for k in range(-RESIDUAL_MS * 8, RESIDUAL_MS * 8 + 1)),
            default=0.0)
    return Verdict(round(max(r, 0.0), 4), r >= MIN_R)
EOF
```

- [ ] **Step 5: Run the new tests and every older one**

The refactor must not change a byte of what stage 1 builds, so the whole stage-1 file runs too.

<!-- replay -->
```bash
python3 -m unittest discover -s tests -p 'test_sound_align.py' 2>&1 | tail -4
bash scripts/test-sound-build.sh 2>&1 | tail -6
python3 tools/sounds/build_pack.py --all --report 2>&1 | tail -1
```

Expected: `Ran 13 tests ... OK` for the new file (about 3 s); the script ends with `Ran N+42 tests ... OK`; the real build still says `(145 of 145 files meet their targets)`.

- [ ] **Step 6: Commit**

<!-- replay-commit -->
```bash
git add tools/sounds/dsp.py tools/sounds/pipeline.py tools/sounds/align.py tests/sound_pack_support.py tests/test_sound_align.py
git commit -m "feat(sounds): the window rule: offset between original and preview, and whether a window holds the same sound

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Pinned windows, the originals loader and `build_pack.py --set mine --originals`

This task builds everything that needs the originals except the originals themselves, and proves it on stand-in files, so that Tasks 7 and 8 only have to run it.

- **`originals.py pin`** looks at each downloaded original before it is trusted: the file is found by the number Freesound puts in front of its name (exactly one file; a browser's `(1)` copy is a second file and is refused), its extension must be the Type the page states (a preview MP3 saved by mistake is not a Wave), its size must be within 10 % of the page's, `afconvert` must decode it, and it must last what the page says, to 5 ms. Then it pins the file name, size and SHA-256 in `sources.json`. A file that differs from an earlier pin is a problem and is never overwritten.
- **`originals.py align`** measures each clip's offset against its preview (Task 3), moves the original into preview time, checks every window of every slot and writes `offset_s` (one per clip) and `windows` (per slot, a list: `start`, `end`, `r`, `ok` for each window the slot takes) into `sources.json`. An entry with no recipe window gets the span the build's automatic trim chose on the preview, written out.
- **`OriginalsLoader`** is what `pipeline.build_set` reads clips from in this mode: it checks the file against its pinned SHA-256, decodes it with the stage-1 `decode_clip` and moves it by `offset_s`. **`pinned_recipe`** copies Your mix with every recorded entry's window replaced by its pinned one. A slot that takes several windows of one clip (the hairball) gets several pinned windows, and `with_windows` writes each back into the matching segment, so `pinned_recipe` works for it too. So the build never needs the previews, and a stand-in test can prove that an original equal to its preview builds byte for byte the same WAVs.
- **`build_pack.py --set mine --originals [DIR]`** runs `sources.gate` first (licence, pins, windows) and stops, naming the clips, before it writes a file. It is the only build that may write `NotchBuddy/Resources/sounds/`, and if it does, any file in that folder besides one WAV per slot and `README.md` fails the run.
- **`afconvert` and Ogg.** `decode_clip` is unchanged; whether it reads the `pop` original (Ogg Vorbis) is found out in Task 7.

**Files:**
- Create: `tools/sounds/originals.py`
- Modify: `tools/sounds/build_pack.py` (`find_folder`, imports, the usage text, `--originals` and `--sources`, the gate and the loader, the shipping check)
- Modify: `tests/sound_pack_support.py` (append `write_original`, `quantise`)
- Create: `tests/test_sound_originals.py`

**Interfaces:**
- Consumes: Task 2's `sources` API; Task 3's `align.measure_offset`, `align.shift_clip`, `align.window_verdict` and `pipeline.source_span`; stage 1's `audio_io.decode_clip` and `AfconvertLoader`, `pipeline.build_set` and `SourceError`; Task 1's `SHIP_DIR`, `in_ship_dir`, `ship_problems`, `refuse_shipping_folder`.
- Produces (`originals`): `SOURCES_PATH`, `CREDITS_PATH`, `sha256_file(path)`, `load_mine(recipes_dir) -> SetRecipe`, `OriginalsLoader(folder, doc)` with `load(source)`, `with_windows(entry, windows) -> entry` (the second of the two readers of an entry's shape, with `sources.clip_uses`), `pinned_recipe(rec, doc) -> SetRecipe`, `use_spans(rec, slot, source, preview) -> [(a, b)]`, `check_original(source, entry, folder) -> (problems, path, bytes, seconds)`, `pin(doc, rec, folder) -> [problem]`, `align_all(doc, rec, folder, previews) -> [Row]` (one `Row(slot, source, offset_ms, r, preview_s, original_s, ok)` per window; a slot with several windows is named `hairball 2 of 3`), `render_rows(rows) -> str`, `main(argv)` with the commands `list`, `pin`, `align`, `credits` (Task 5 adds `page`). Produces (`build_pack`): `find_folder(explicit, env, name, root=ROOT)`, the options `--originals [DIR]` and `--sources FILE`. Produces (tests): `write_original(path, ints, rate, channels, width)` and `quantise(x) -> (ints, floats)` in the support module.

- [ ] **Step 1: Write the failing tests**

<!-- replay -->
```bash
cat >> tests/sound_pack_support.py <<'EOF'


def write_original(path, ints, rate=SR, channels=1, width=2):
    """A WAV standing in for a downloaded original: `ints` are 16-bit sample values, written as 16- or 24-bit
    PCM at `rate`, `channels` identical channels."""
    frames = bytearray()
    for v in ints:
        frames += (struct.pack("<h", v) if width == 2 else struct.pack("<i", v << 8)[:3]) * channels
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(width)
        w.setframerate(rate)
        w.writeframes(bytes(frames))


def quantise(x):
    """(16-bit ints, the floats a decoder gives back for them): what an original holds and what a preview shows."""
    ints = [max(-32768, min(32767, int(round(v * 32768)))) for v in x]
    return ints, [i / 32768.0 for i in ints]
EOF
```

<!-- replay -->
```bash
cat > tests/test_sound_originals.py <<'EOF'
"""Tests for building Your mix from the Freesound originals (sub-project C, stage 2, task 4). Standard library plus
macOS afconvert, which the end-to-end tests skip without."""
import contextlib
import copy
import io
import os
import random
import shutil
import tempfile
import unittest
from collections import OrderedDict
from unittest import mock

from sound_pack_support import (HAIRBALL_CLIP, SOURCES_JSON, SR, blank_doc, blanked, hairball_like, mini_recipe, quantise,
                               verify_all, voice, write_original)
from test_sound_build import (HAS_AFCONVERT, MIX_PICKS, DictLoader, read_bytes, write_default_round2, write_distinct_sets,
                              write_mine)

import audio_io  # noqa: E402
import build_pack  # noqa: E402
import dsp  # noqa: E402
import originals  # noqa: E402
import pipeline  # noqa: E402
import recipe  # noqa: E402
import sources  # noqa: E402


@unittest.skipUnless(HAS_AFCONVERT, "needs macOS afconvert")
class TestOriginals(unittest.TestCase):
    ALICE, BOB, CY = "greet/fs-1001-Alice.wav", "love/fs-1002-Bob.wav", "tick/fs-1003-Cy.wav"

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="nm originals test ")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.folder = os.path.join(self.tmp, "originals folder")
        os.makedirs(self.folder)
        self.rec = mini_recipe(("greet", self.ALICE, {"start": 0.2, "end": 0.7}),
                               ("wink", self.ALICE, {"start": 0.3, "end": 0.6}),          # a second window of one clip
                               ("love", self.BOB),                                       # no window: trimmed automatically
                               ("tick", self.CY),
                               ("blip", "synth:blip"))
        takes = {self.ALICE: voice(2, 0.7, 0.2, 0.1), self.BOB: voice(3, 0.5, 0.1, 0.1), self.CY: voice(4, 0.2, 0.02, 0.02)}
        self.ints = {k: quantise(v)[0] for k, v in takes.items()}
        self.previews = {k: quantise(v)[1] for k, v in takes.items()}
        self.doc = blank_doc(self.rec)

    def install(self, lead_ms=0, tail_ms=0, only=None, ints=None, **wav):
        """Write every clip's original into the folder: `lead_ms` of silence in front (the original later than the
        preview; negative cuts the front), `tail_ms` after. Fills in what the pages say."""
        for source, own in (ints or self.ints).items():
            if only and source not in only:
                continue
            body = ([0] * (lead_ms * 48) + own if lead_ms >= 0 else own[-lead_ms * 48:]) + [0] * (tail_ms * 48)
            name = "%s__someone__%s.wav" % (sources.freesound_id(source), os.path.basename(source)[:-4])
            path = os.path.join(self.folder, name)
            write_original(path, body, **wav)
            seconds = audio_io.decode_clip(path)
            e = self.doc["sources"][source]
            e["stated"] = {"type": "Wave (.wav)", "duration": "0:%06.3f" % (len(seconds) / SR),
                           "size": "%.1f KB" % (os.path.getsize(path) / 1024.0)}

    def build(self, rec, loader, name):
        out = os.path.join(self.tmp, name)
        pipeline.build_set(rec, loader, out)
        return {f: read_bytes(os.path.join(out, f)) for f in sorted(os.listdir(out))}

    def test_a_right_original_passes_the_check_and_a_wrong_one_is_named(self):
        self.install()
        source = self.ALICE
        entry_ = self.doc["sources"][source]
        bad, path, size, seconds = originals.check_original(source, entry_, self.folder)
        self.assertEqual(bad, [])
        self.assertAlmostEqual(seconds, 1.0, places=3)
        wrong = dict(entry_, stated={"type": "Ogg Vorbis (.ogg)", "duration": "0:00.500", "size": "9.0 KB"})
        said = " | ".join(originals.check_original(source, wrong, self.folder)[0])
        self.assertIn("is not a Ogg Vorbis (.ogg) file", said)
        self.assertIn("its page says 9.0 KB", said)
        self.assertIn("its page says 0:00.500", said)
        with open(path, "wb") as f:
            f.write(b"this is not audio")
        bad = originals.check_original(source, dict(entry_, stated=dict(entry_["stated"], size="0.0 KB")), self.folder)[0]
        self.assertTrue(any("afconvert cannot read" in b for b in bad), bad)

    def test_a_missing_or_doubled_original_is_a_problem_not_a_crash(self):
        self.install(only=[self.ALICE])
        said = originals.pin(self.doc, self.rec, self.folder)
        self.assertEqual(len(said), 2)                            # Bob and Cy are not there
        self.assertTrue(all("no file named" in s for s in said), said)
        self.assertIsNotNone(self.doc["sources"][self.ALICE]["original"])       # the good one is still pinned
        self.assertIsNone(self.doc["sources"][self.BOB]["original"])

    def test_pin_writes_name_size_and_sha256_and_never_overwrites_a_pin(self):
        self.install()
        self.assertEqual(originals.pin(self.doc, self.rec, self.folder), [])
        for source, e in self.doc["sources"].items():
            path = os.path.join(self.folder, e["original"]["file"])
            self.assertEqual(e["original"]["bytes"], os.path.getsize(path))
            self.assertEqual(e["original"]["sha256"], originals.sha256_file(path))
        before = copy.deepcopy(self.doc)
        self.assertEqual(originals.pin(self.doc, self.rec, self.folder), [])           # pinning twice changes nothing
        self.assertEqual(self.doc, before)
        e = self.doc["sources"][self.CY]
        write_original(os.path.join(self.folder, e["original"]["file"]), self.ints[self.CY][:-480])    # a different file, same name
        e["stated"]["size"] = "%.1f KB" % (os.path.getsize(os.path.join(self.folder, e["original"]["file"])) / 1024.0)
        e["stated"]["duration"] = "0:00.230"
        said = originals.pin(self.doc, self.rec, self.folder)
        self.assertEqual(len(said), 1)
        self.assertIn("differs from the file pinned earlier", said[0])
        self.assertEqual(self.doc["sources"][self.CY]["original"], before["sources"][self.CY]["original"])

    def test_the_loader_refuses_a_file_that_is_not_the_pinned_one(self):
        self.install()
        originals.pin(self.doc, self.rec, self.folder)
        self.doc["sources"][self.ALICE]["offset_s"] = 0.0
        loader = originals.OriginalsLoader(self.folder, self.doc)
        self.assertEqual(len(loader.load(self.ALICE)), len(self.ints[self.ALICE]))
        write_original(os.path.join(self.folder, self.doc["sources"][self.BOB]["original"]["file"]), [1, 2, 3])
        self.doc["sources"][self.BOB]["offset_s"] = 0.0
        with self.assertRaises(pipeline.SourceError) as ctx:
            originals.OriginalsLoader(self.folder, self.doc).load(self.BOB)
        self.assertIn("is not the file pinned", str(ctx.exception))

    def test_the_loader_moves_each_original_into_preview_time(self):
        self.install(lead_ms=30)
        originals.pin(self.doc, self.rec, self.folder)
        self.doc["sources"][self.ALICE]["offset_s"] = 0.03
        moved = originals.OriginalsLoader(self.folder, self.doc).load(self.ALICE)
        self.assertEqual(moved, self.previews[self.ALICE])

    def test_align_finds_the_offset_pins_every_window_and_the_build_matches_the_preview_build(self):
        for lead, tail in ((0, 0), (30, 120), (-20, 0)):      # the same sound, later / with a longer tail / earlier
            self.setUp()
            self.install(lead_ms=lead, tail_ms=tail)
            self.assertEqual(originals.pin(self.doc, self.rec, self.folder), [])
            rows = originals.align_all(self.doc, self.rec, self.folder, DictLoader(self.previews))
            self.assertEqual(len(rows), 4, (lead, tail))                   # one per recorded slot
            self.assertTrue(all(r.ok for r in rows), originals.render_rows(rows))
            for source in (self.ALICE, self.BOB, self.CY):
                self.assertAlmostEqual(self.doc["sources"][source]["offset_s"], lead / 1000.0, places=3)
            windows = self.doc["sources"][self.ALICE]["windows"]
            self.assertEqual([(w["start"], w["end"]) for w in windows["greet"]], [(0.2, 0.7)])
            self.assertEqual([(w["start"], w["end"]) for w in windows["wink"]], [(0.3, 0.6)])
            auto = self.doc["sources"][self.BOB]["windows"]["love"][0]    # an automatic window, now written out
            self.assertTrue(0.0 <= auto["start"] < auto["end"] <= 0.7)
            verify_all(self.doc)
            self.assertEqual(sources.gate(self.doc, self.rec), [])
            from_originals = self.build(originals.pinned_recipe(self.rec, self.doc),
                                        originals.OriginalsLoader(self.folder, self.doc), "from originals")
            from_previews = self.build(self.rec, DictLoader(self.previews), "from previews")
            self.assertEqual(sorted(from_originals), ["blip.wav", "greet.wav", "love.wav", "tick.wav", "wink.wav"])
            self.assertEqual(from_originals, from_previews, (lead, tail))

    def test_pinning_keeps_the_previews_window_when_the_originals_noise_floor_would_move_it(self):
        rng = random.Random(5)
        hissy = {s: [max(-32768, min(32767, v + int(rng.gauss(0, 900)))) for v in ints] for s, ints in self.ints.items()}
        self.install(ints=hissy)                                       # the originals carry hiss at about -31 dBFS
        self.assertEqual(originals.pin(self.doc, self.rec, self.folder), [])
        rows = originals.align_all(self.doc, self.rec, self.folder, DictLoader(self.previews))
        self.assertTrue(all(r.ok for r in rows), originals.render_rows(rows))
        a, b = pipeline.source_span(self.rec.entries["love"], self.previews[self.BOB], 0.0)         # the preview's window
        pinned = self.doc["sources"][self.BOB]["windows"]["love"][0]
        self.assertEqual((pinned["start"], pinned["end"]), (round(a / float(SR), 6), round(b / float(SR), 6)))
        own = audio_io.decode_clip(os.path.join(self.folder, self.doc["sources"][self.BOB]["original"]["file"]))
        self.assertNotEqual(dsp.auto_trim_span(own, 1.5), (a, b))      # trimming the hissy original itself would cut elsewhere

    def test_another_take_in_the_original_fails_its_window_and_stops_the_build(self):
        self.install()
        other = os.path.join(self.folder, "1002__someone__fs-1002-Bob.wav")
        write_original(other, quantise(voice(5, 0.5, 0.1, 0.1))[0])        # Bob's file is a different take of the cat
        e = self.doc["sources"][self.BOB]
        e["stated"]["size"] = "%.1f KB" % (os.path.getsize(other) / 1024.0)
        self.assertEqual(originals.pin(self.doc, self.rec, self.folder), [])      # the page's figures cannot tell
        rows = originals.align_all(self.doc, self.rec, self.folder, DictLoader(self.previews))
        self.assertEqual([r.slot for r in rows if not r.ok], ["love"])
        self.assertFalse(self.doc["sources"][self.BOB]["windows"]["love"][0]["ok"])
        said = sources.gate(verify_all(self.doc), self.rec)
        self.assertEqual(len(said), 1)
        self.assertIn("1 windows do not hold the same sound as the preview: love (r=", said[0])

    def test_a_recipe_window_that_moved_after_pinning_is_refused(self):
        self.install()
        originals.pin(self.doc, self.rec, self.folder)
        originals.align_all(self.doc, self.rec, self.folder, DictLoader(self.previews))
        verify_all(self.doc)
        self.assertEqual(sources.gate(self.doc, self.rec), [])
        moved = mini_recipe(("greet", self.ALICE, {"start": 0.25, "end": 0.7}), ("wink", self.ALICE, {"start": 0.3, "end": 0.6}),
                            ("love", self.BOB), ("tick", self.CY))
        self.assertEqual(sources.gate(self.doc, moved), ["1 windows changed in the recipe since they were pinned: greet"])

    def test_the_pinned_recipe_writes_automatic_windows_out_and_leaves_made_in_code_sounds_alone(self):
        self.install()
        originals.pin(self.doc, self.rec, self.folder)
        originals.align_all(self.doc, self.rec, self.folder, DictLoader(self.previews))
        pinned = originals.pinned_recipe(self.rec, self.doc)
        self.assertEqual(list(pinned.entries), list(self.rec.entries))
        self.assertEqual(pinned.entries["blip"], self.rec.entries["blip"])
        for slot in ("greet", "wink", "love", "tick"):
            self.assertIsNotNone(pinned.entries[slot].start)
            self.assertIsNotNone(pinned.entries[slot].end)
            self.assertEqual(pinned.entries[slot].pitch_st, self.rec.entries[slot].pitch_st)
        self.assertIsNone(self.rec.entries["love"].start)                  # the original recipe is untouched

    def test_a_slot_that_takes_three_windows_of_one_clip_is_aligned_pinned_and_cut_window_by_window(self):
        # the hairball: a placed sound, three windows of one recorded clip plus a made-in-code layer
        gap = [0.0] * 14400
        coughs = [0.0] * 4800 + voice(6, 0.2, 0.05, 0.05) + gap + voice(7, 0.2, 0.05, 0.05) + gap + voice(8, 0.2, 0.05, 0.05) + [0.0] * 4800
        ints, floats = quantise(coughs)
        windows = ((0.08, 0.38), (0.68, 0.98), (1.28, 1.58))
        rec = recipe.SetRecipe("mine", "Your mix", 0.0, OrderedDict(hairball=hairball_like(windows=windows)))      # source "placed"
        doc = blank_doc(rec)
        path = os.path.join(self.folder, "1004__someone__cough.wav")
        write_original(path, [0] * 480 + ints)                                           # the original starts 10 ms later
        doc["sources"][HAIRBALL_CLIP]["stated"] = {"type": "Wave (.wav)", "duration": "0:%06.3f" % ((len(ints) + 480) / float(SR)),
                                                    "size": "%.1f KB" % (os.path.getsize(path) / 1024.0)}
        self.assertEqual(originals.pin(doc, rec, self.folder), [])
        rows = originals.align_all(doc, rec, self.folder, DictLoader({HAIRBALL_CLIP: floats}))
        self.assertEqual([r.slot for r in rows], ["hairball 1 of 3", "hairball 2 of 3", "hairball 3 of 3"])
        self.assertTrue(all(r.ok for r in rows), originals.render_rows(rows))
        clip = doc["sources"][HAIRBALL_CLIP]
        self.assertAlmostEqual(clip["offset_s"], 0.01, places=3)                         # one offset for the clip
        self.assertEqual([(w["start"], w["end"]) for w in clip["windows"]["hairball"]], list(windows))
        verify_all(doc)
        self.assertEqual(sources.gate(doc, rec), [])
        pinned = originals.pinned_recipe(rec, doc)
        self.assertEqual([(s["start"], s["end"]) for s in pinned.entries["hairball"].segments], list(windows))
        self.assertEqual([s["at"] for s in pinned.entries["hairball"].segments], [s["at"] for s in rec.entries["hairball"].segments])
        self.assertEqual(pinned.entries["hairball"].synth_layers, rec.entries["hairball"].synth_layers)   # the made-in-code layer is left alone
        self.assertEqual((pinned.entries["hairball"].source, pinned.entries["hairball"].end), ("placed", 1.48))
        clip["windows"]["hairball"][1]["start"] = 0.70                                   # what is pinned wins over the recipe's 0.68
        self.assertEqual(originals.pinned_recipe(rec, doc).entries["hairball"].segments[1]["start"], 0.70)
        clip["windows"]["hairball"][1]["start"] = 0.68
        self.assertEqual(originals.OriginalsLoader(self.folder, doc).load(HAIRBALL_CLIP), floats)    # moved back into preview time

    def test_originals_in_other_formats_decode_and_align(self):
        # the formats Freesound's pages state: 44.1 kHz stereo 16-bit, 96 kHz stereo 24-bit
        for rate, channels, width in ((44100, 2, 2), (96000, 2, 3)):
            self.setUp()
            body = {s: dsp.pitch_shift(f, 0.0) for s, f in self.previews.items()}
            for source, floats in body.items():
                step = rate / float(SR)
                ints = [int(round(32768 * floats[min(len(floats) - 1, int(i * SR / rate))])) for i in range(int(len(floats) * step))]
                path = os.path.join(self.folder, "%s__x__y.wav" % sources.freesound_id(source))
                write_original(path, [max(-32768, min(32767, v)) for v in ints], rate, channels, width)
                self.doc["sources"][source]["stated"] = {"type": "Wave (.wav)", "duration": "0:%06.3f" % (len(floats) / SR),
                                                         "size": "%.1f KB" % (os.path.getsize(path) / 1024.0)}
            self.assertEqual(originals.pin(self.doc, self.rec, self.folder), [], (rate, channels, width))
            rows = originals.align_all(self.doc, self.rec, self.folder, DictLoader(self.previews))
            self.assertTrue(all(r.ok for r in rows), (rate, originals.render_rows(rows)))
            self.assertTrue(all(abs(r.offset_ms) < 1.0 for r in rows))
            self.assertTrue(all(r.r > 0.95 for r in rows))


class TestBuildFromOriginals(unittest.TestCase):
    def run_main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = build_pack.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def test_a_blank_sources_json_is_not_ready_and_the_build_says_what_is_missing_and_writes_nothing(self):
        tmp = tempfile.mkdtemp(prefix="nm originals cli ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        out, path = os.path.join(tmp, "out"), os.path.join(tmp, "sources.json")
        sources.save(path, blanked(sources.load(SOURCES_JSON)))
        code, stdout, err = self.run_main("--set", "mine", "--originals", tmp, "--sources", path, "--out", out)
        self.assertEqual(code, 2)
        self.assertIn("the originals are not ready", err)
        n = len(sources.load(path)["sources"])
        self.assertIn("%d clips have no verified CC0 entry" % n, err)
        self.assertIn("%d originals are not pinned" % n, err)
        self.assertFalse(os.path.exists(out))

    def test_a_source_missing_from_sources_json_stops_the_build(self):
        tmp = tempfile.mkdtemp(prefix="nm originals cli ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        doc = blanked(sources.load(SOURCES_JSON))
        del doc["sources"]["rate/fs-64012-Department64.mp3"]
        path = os.path.join(tmp, "sources.json")
        sources.save(path, doc)
        code, _, err = self.run_main("--set", "mine", "--originals", tmp, "--sources", path, "--out", os.path.join(tmp, "out"))
        self.assertEqual(code, 2)
        self.assertIn("1 clips are not in sources.json: rate/fs-64012-Department64.mp3", err)

    def test_originals_belong_to_your_mix_only(self):
        for argv in (["--set", "studio", "--originals"], ["--all", "--originals"]):
            code, _, err = self.run_main(*argv)
            self.assertEqual(code, 2, argv)
            self.assertIn("--originals builds Your mix only", err)

    def test_only_a_build_from_originals_may_write_the_shipping_folder(self):
        ship = os.path.join(build_pack.SHIP_DIR)
        mine = (recipe.MINE_NAME, None, ship)
        self.assertIsNone(build_pack.refuse_shipping_folder([mine], True))
        self.assertIn("Freesound originals", build_pack.refuse_shipping_folder([mine], False))
        self.assertIn("Freesound originals", build_pack.refuse_shipping_folder([("studio", None, ship)], True))
        self.assertIsNone(build_pack.refuse_shipping_folder([("studio", None, os.path.join(build_pack.BUILD_DIR, "studio"))], False))


@unittest.skipUnless(HAS_AFCONVERT, "needs macOS afconvert")
class TestShipBuildEndToEnd(unittest.TestCase):
    """The whole path on stand-in clips: recipes, a verified and pinned sources.json, the originals folder, then
    `build_pack.py --set mine --originals --out <shipping folder> --report`."""

    def test_your_mix_ships_every_slots_wav_and_nothing_else_identical_to_the_preview_build(self):
        tmp = tempfile.mkdtemp(prefix="nm ship e2e ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        recipes, folder = os.path.join(tmp, "recipes"), os.path.join(tmp, "originals")
        ship = os.path.join(tmp, "NotchBuddy", "Resources", "sounds")
        os.makedirs(folder)
        os.makedirs(ship)
        open(os.path.join(ship, "README.md"), "w").close()
        write_distinct_sets(recipes)
        write_default_round2(recipes)
        write_mine(recipes, MIX_PICKS)
        sets = recipe.load_recipes(recipes)
        mine = recipe.load_mine(os.path.join(recipes, "mine.json"), sets, recipe.load_round2(os.path.join(recipes, "round2.json"), sets))
        clips = {}
        doc = OrderedDict(title="e2e", sources=OrderedDict())
        for n, source in enumerate(sources.file_sources(mine)):
            ints, floats = quantise(voice(10 + n, 0.25, 0.03, 0.02))
            name = "%s.wav" % source.replace("/", "_")
            path = os.path.join(folder, name)
            write_original(path, [0] * 480 + ints)                         # every original 10 ms later than its preview
            clips[source] = floats
            doc["sources"][source] = OrderedDict(
                title=source, author="tester", page="https://example.org/" + source, licence=sources.CC0,
                licence_url=sources.CC0_URLS[0], checked_on="2026-10-06", checked_by="the test",
                stated={"type": "Wave (.wav)", "duration": "0:00.300", "size": "30 KB"},
                original={"file": name, "bytes": os.path.getsize(path), "sha256": originals.sha256_file(path)},
                offset_s=None, windows=OrderedDict())
        previews = DictLoader(clips)
        self.assertTrue(all(r.ok for r in originals.align_all(doc, mine, folder, previews)))
        sources_path = os.path.join(tmp, "sources.json")
        sources.save(sources_path, doc)
        expected_dir = os.path.join(tmp, "from previews")
        pipeline.build_set(mine, previews, expected_dir)
        with mock.patch.object(build_pack, "SHIP_DIR", ship), mock.patch.object(build_pack, "BUILD_DIR", os.path.join(tmp, "build")):
            out, err = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = build_pack.main(["--set", "mine", "--originals", folder, "--sources", sources_path,
                                        "--recipes", recipes, "--out", ship, "--report"])
            self.assertIn(code, (0, 1), err.getvalue())                    # a stand-in burst may miss a loudness target
            self.assertEqual(build_pack.ship_problems(ship), [])
            self.assertEqual(sorted(os.listdir(ship)), sorted(["README.md"] + [s + ".wav" for s in recipe.SLOTS]))
            self.assertTrue(os.path.isfile(os.path.join(tmp, "build", "ship-report.md")))
            for slot in recipe.SLOTS:
                self.assertEqual(read_bytes(os.path.join(ship, slot + ".wav")), read_bytes(os.path.join(expected_dir, slot + ".wav")), slot)


if __name__ == "__main__":
    unittest.main()
EOF
```

- [ ] **Step 2: Run them to see them fail**

<!-- replay-fail -->
```bash
python3 -m unittest discover -s tests -p 'test_sound_originals.py' 2>&1 | tail -6
```

Expected: `ModuleNotFoundError: No module named 'originals'`, and no tests run.

- [ ] **Step 3: Write `tools/sounds/originals.py`**

<!-- replay -->
```bash
cat > tools/sounds/originals.py <<'EOF'
#!/usr/bin/env python3
"""Stage 2's steps on the Freesound originals: the download list, pinning the downloaded files, aligning
them with the preview clips, and the credits file. build_pack.py builds from the result.

  originals.py list      write the list of originals to download (git-ignored folder) and print it
  originals.py pin       check every downloaded original (type, size, length, decodes) and pin its SHA-256
  originals.py align     measure each original's offset against its preview and check every window
  originals.py credits   write docs/SOUND-CREDITS.md from sources.json

All of them read design/sounds/sources.json (--sources) and Your mix (design/sounds/sets/mine.json).
`pin` and `align` write their results into sources.json. Nothing here downloads anything or asks for a login.
Needs Python 3 and macOS afconvert; the preview clips are only needed by `align`.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import sys
from collections import namedtuple

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(os.path.dirname(HERE))

import align  # noqa: E402
import audio_io  # noqa: E402
import dsp  # noqa: E402
import pipeline  # noqa: E402
import recipe  # noqa: E402
import sources  # noqa: E402
from dsp import SR  # noqa: E402

SOURCES_PATH = os.path.join(ROOT, "design", "sounds", sources.SOURCES_NAME)
CREDITS_PATH = os.path.join(ROOT, "docs", "SOUND-CREDITS.md")
SIZE_TOLERANCE = 0.10          # a downloaded file within 10 % of the size its page states
LENGTH_TOLERANCE_S = 0.005     # and as long as its page says, to 5 ms


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def load_mine(recipes_dir):
    """Your mix as a SetRecipe (one entry per slot), from the recipes folder."""
    sets = recipe.load_recipes(recipes_dir)
    round2 = recipe.load_round2(os.path.join(recipes_dir, recipe.ROUND2_NAME + ".json"), sets)
    return recipe.load_mine(os.path.join(recipes_dir, recipe.MINE_NAME + ".json"), sets, round2)


class OriginalsLoader:
    """Decodes the pinned originals and moves each one into preview time by its measured offset, so a recipe
    window means the same sound it meant on the preview. `load` has the loader interface of pipeline.build_set."""

    def __init__(self, folder, doc):
        self.folder, self.doc, self._clips = str(folder), doc, {}

    def load(self, source):
        if source not in self._clips:
            e = self.doc["sources"][source]
            path = os.path.join(self.folder, e["original"]["file"])
            if not os.path.isfile(path):
                raise pipeline.SourceError("%s: the original %s is not in %s" % (source, e["original"]["file"], self.folder))
            if sha256_file(path) != e["original"]["sha256"]:
                raise pipeline.SourceError("%s: %s is not the file pinned in sources.json (its SHA-256 differs)"
                                           % (source, path))
            self._clips[source] = align.shift_clip(audio_io.decode_clip(path), int(round(e["offset_s"] * SR)))
        return self._clips[source]


def with_windows(entry, windows):
    """`entry` with the window of each of its clip uses (`sources.clip_uses` order) replaced by the matching
    (start, end) of `windows`. Like `clip_uses`, one of the two places that know the shape of an entry."""
    segments = getattr(entry, "segments", None) or ()
    if segments:
        return entry._replace(segments=[dict(seg, start=a, end=b) for seg, (a, b) in zip(segments, windows)])
    return entry._replace(start=windows[0][0], end=windows[0][1])


def pinned_recipe(rec, doc):
    """`rec` with every recorded window written out as the window pinned (and checked) in sources.json, so the
    originals are cut exactly where the previews were. Made-in-code entries are left as they are."""
    entries = type(rec.entries)()
    for slot, e in rec.entries.items():
        taken, pinned = {}, []
        for source, _start, _end in sources.clip_uses(e):
            n = taken[source] = taken.get(source, -1) + 1
            w = doc["sources"][source]["windows"][slot][n]
            pinned.append((w["start"], w["end"]))
        entries[slot] = with_windows(e, pinned) if pinned else e
    return rec._replace(entries=entries)


def check_original(source, entry, folder):
    """Look at a downloaded original: returns (problems, path, bytes, seconds). Nothing is written."""
    try:
        path = sources.find_original(folder, source, entry)
    except sources.SourcesError as e:
        return [str(e)], None, 0, 0.0
    out, size = [], os.path.getsize(path)
    if not sources.type_matches(entry, path):
        out.append("%s is not a %s file" % (os.path.basename(path), entry["stated"]["type"]))
    said = sources.parse_size(entry["stated"]["size"])
    if abs(size - said) > SIZE_TOLERANCE * said:
        out.append("%s is %d bytes, its page says %s" % (os.path.basename(path), size, entry["stated"]["size"]))
    seconds = 0.0
    try:
        seconds = len(audio_io.decode_clip(path)) / float(SR)
    except Exception as e:                      # afconvert refuses it: the message says which file
        out.append("afconvert cannot read %s (%s)" % (os.path.basename(path), str(e).strip()[:120]))
        return out, path, size, seconds
    want = sources.parse_duration(entry["stated"]["duration"])
    if abs(seconds - want) > LENGTH_TOLERANCE_S:
        out.append("%s lasts %.3f s, its page says %s" % (os.path.basename(path), seconds, entry["stated"]["duration"]))
    return out, path, size, seconds


def pin(doc, rec, folder):
    """Check every original of `rec` in `folder` and pin it in `doc` (file, bytes, SHA-256). A file that
    differs from an earlier pin is a problem, never overwritten. Returns the problems."""
    problems = []
    for source in sources.file_sources(rec):
        entry = doc["sources"][source]
        bad, path, size, _ = check_original(source, entry, folder)
        if not bad and path is not None:
            digest = sha256_file(path)
            old = entry.get("original")
            if old and old["sha256"] != digest:
                bad = ["%s differs from the file pinned earlier; if the new one is right, set its original to null "
                       "in sources.json and pin again" % os.path.basename(path)]
            elif not old:
                entry["original"] = {"file": os.path.basename(path), "bytes": size, "sha256": digest}
        problems += ["%s: %s" % (source, b) for b in bad]
    return problems


Row = namedtuple("Row", "slot source offset_ms r preview_s original_s ok")


def use_spans(rec, slot, source, preview):
    """[(a, b)] sample spans of `preview` for each window `slot` takes from `source`: the window the recipe gives,
    or, for an entry with none, the span the build's automatic trim chooses on the preview."""
    entry = rec.entries[slot]
    if getattr(entry, "segments", None):
        return [dsp.seconds_span(len(preview), a, b) for a, b in sources.slot_windows(rec, slot, source)]
    return [pipeline.source_span(entry, preview, entry.pitch_st)]


def align_all(doc, rec, folder, previews):
    """For every recorded clip of `rec`: measure the offset between its pinned original and its preview, shift the
    original into preview time and check every window of every slot (align.py's rule). Writes offset_s and windows
    into `doc` (windows[slot] is a list, one per window the slot takes from the clip); returns one Row per window.
    `previews` is a loader of the preview clips."""
    rows = []
    for source, slots in sources.file_sources(rec).items():
        entry = doc["sources"][source]
        preview = previews.load(source)
        original = audio_io.decode_clip(os.path.join(folder, entry["original"]["file"]))
        spans = {s: use_spans(rec, s, source, preview) for s in slots}
        offset, _ = align.measure_offset(preview, original, *spans[slots[0]][0])
        moved = align.shift_clip(original, offset)
        entry["offset_s"] = round(offset / float(SR), 6)
        entry["windows"] = {}
        for slot in slots:
            entry["windows"][slot] = []
            for n, (a, b) in enumerate(spans[slot]):
                v = align.window_verdict(preview, moved, a, b)
                entry["windows"][slot].append({"start": round(a / float(SR), 6), "end": round(b / float(SR), 6),
                                               "r": v.r, "ok": bool(v.ok)})
                name = slot if len(spans[slot]) == 1 else "%s %d of %d" % (slot, n + 1, len(spans[slot]))
                rows.append(Row(name, source, offset * 1000.0 / SR, v.r,
                                len(preview) / float(SR), len(original) / float(SR), bool(v.ok)))
    return rows


def render_rows(rows):
    lines = ["| slot | source | offset ms | r | preview s | original s | window |", "|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append("| %s | %s | %+.2f | %.3f | %.3f | %.3f | %s |" % (
            r.slot, r.source, r.offset_ms, r.r, r.preview_s, r.original_s, "same sound" if r.ok else "FAILS"))
    return "\n".join(lines)


def _folder(explicit, name, env):
    """A git-ignored folder: the flag, $<env> (taken even before the folder exists, so `list` can name it),
    <repo>/.claude/sounds/<name>, then the same folder in the main checkout."""
    want = explicit or os.environ.get(env)
    if want:
        return os.path.abspath(want)
    import build_pack           # imported here because build_pack imports this module
    return build_pack.find_folder(None, env, name) or os.path.join(build_pack.ROOT, ".claude", "sounds", name)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=("list", "pin", "align", "credits"))
    ap.add_argument("--sources", default=SOURCES_PATH, help="sources.json (default: design/sounds/sources.json)")
    ap.add_argument("--recipes", default=os.path.join(ROOT, "design", "sounds", "sets"))
    ap.add_argument("--originals", help="folder of downloaded originals (default: .claude/sounds/originals)")
    ap.add_argument("--candidates", help="folder of preview clips (align only)")
    ap.add_argument("--credits", default=CREDITS_PATH, help="where `credits` writes (default: docs/SOUND-CREDITS.md)")
    args = ap.parse_args(argv)
    try:
        rec = load_mine(args.recipes)
        doc = sources.load(args.sources)
    except (recipe.RecipeError, sources.SourcesError, OSError) as e:
        print("error: %s" % e, file=sys.stderr)
        return 2
    missing = [s for s in sources.file_sources(rec) if s not in doc["sources"]]
    if missing:
        print("error: not in sources.json: %s" % ", ".join(missing), file=sys.stderr)
        return 2
    folder = _folder(args.originals, "originals", "NM_SOUND_ORIGINALS")

    if args.command == "list":
        text = sources.download_list_text(doc, rec, folder)
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, "DOWNLOAD-LIST.md"), "w", encoding="utf-8") as f:
            f.write(text)
        print(text)
        return 0
    if args.command == "credits":
        bad = sources.licence_problems(doc, rec) + sources.pin_problems(doc, rec)
        if bad:
            print("credits: not ready: %s" % "; ".join(bad), file=sys.stderr)
            return 2
        with open(args.credits, "w", encoding="utf-8") as f:
            f.write(sources.credits_text(doc, rec))
        print("wrote %s" % args.credits)
        return 0
    if not os.path.isdir(folder):
        print("%s: the originals folder %s does not exist yet" % (args.command, folder), file=sys.stderr)
        return 2
    if args.command == "pin":
        bad = pin(doc, rec, folder)
        sources.save(args.sources, doc)
        for line in bad:
            print("PROBLEM " + line, file=sys.stderr)
        print("pinned %d of %d originals" % (sum(1 for s in sources.file_sources(rec) if doc["sources"][s].get("original")),
                                             len(sources.file_sources(rec))))
        return 1 if bad else 0
    not_pinned = sources.pin_problems(doc, rec)
    if not_pinned:
        print("align: pin the originals first: %s" % "; ".join(not_pinned), file=sys.stderr)
        return 2
    import build_pack
    cands = build_pack.find_candidates(args.candidates)
    if cands is None:
        print("align: the preview clips (candidates folder) were not found; pass --candidates", file=sys.stderr)
        return 2
    rows = align_all(doc, rec, folder, audio_io.AfconvertLoader(cands))
    sources.save(args.sources, doc)
    print(render_rows(rows))
    failed = [r for r in rows if not r.ok]
    print("%d of %d windows hold the same sound" % (len(rows) - len(failed), len(rows)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
EOF
```

- [ ] **Step 4: The originals mode in `build_pack.py`**

<!-- replay -->
```bash
python3 - <<'EOF'
def edit(path, old, new):
    with open(path, encoding="utf-8") as f:
        s = f.read()
    assert s.count(old) == 1, "%s: the text to replace is not there exactly once:\n%s" % (path, old)
    with open(path, "w", encoding="utf-8") as f:
        f.write(s.replace(old, new))


P = "tools/sounds/build_pack.py"

# 1. find_candidates becomes a use of find_folder, so the originals folder is found the same way (flag, env, repo, main checkout)
edit(P, '''def find_candidates(explicit=None, root=ROOT):
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
''', '''def find_folder(explicit, env, name, root=ROOT):
    """A git-ignored folder under .claude/sounds: the flag, $<env>, <root>/.claude/sounds/<name>, then the same
    folder in the main checkout (a git worktree does not carry git-ignored files). None when there is none."""
    wanted = [explicit] if explicit else [os.environ.get(env), os.path.join(root, ".claude", "sounds", name)]
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
    path = os.path.join(os.path.dirname(common), ".claude", "sounds", name)
    return path if os.path.isdir(path) else None


def find_candidates(explicit=None, root=ROOT):
    """The candidates folder: --candidates, $NM_SOUND_CANDIDATES, <root>/.claude/sounds/candidates,
    then the same folder in the main checkout. None when there is none."""
    return find_folder(explicit, "NM_SOUND_CANDIDATES", "candidates", root)
''')

# 2. imports
edit(P, '''import pipeline  # noqa: E402
import recipe  # noqa: E402
import report  # noqa: E402
from audio_io import AfconvertLoader  # noqa: E402
''', '''import originals  # noqa: E402
import pipeline  # noqa: E402
import recipe  # noqa: E402
import report  # noqa: E402
import sources  # noqa: E402
from audio_io import AfconvertLoader  # noqa: E402
''')

# 3. the usage text
edit(P, '''  build_pack.py --round2 [--report]                       the round-two alternatives, one WAV each
''', '''  build_pack.py --round2 [--report]                       the round-two alternatives, one WAV each
  build_pack.py --set mine --originals [DIR] [--out D]    Your mix from the pinned Freesound originals (stage 2);
                                                          the only build that may write NotchBuddy/Resources/sounds
''')

# 4. the new options
edit(P, '''    ap.add_argument("--report", action="store_true", help="write report.md and fail if targets are missed")
''', '''    ap.add_argument("--report", action="store_true", help="write report.md and fail if targets are missed")
    ap.add_argument("--originals", nargs="?", const="", metavar="DIR",
                    help="with --set mine: build from the pinned Freesound originals in DIR (default "
                         ".claude/sounds/originals), the only build that may write NotchBuddy/Resources/sounds")
    ap.add_argument("--sources", default=originals.SOURCES_PATH, help="sources.json for --originals")
''')
edit(P, '''    args = ap.parse_args(argv)

    wants_extras''', '''    args = ap.parse_args(argv)
    from_originals = args.originals is not None
    if from_originals and args.set != recipe.MINE_NAME:
        print("--originals builds Your mix only: use --set mine --originals", file=sys.stderr)
        return 2

    wants_extras''')
edit(P, '''    cands = find_candidates(args.candidates)

    if args.check_recipes:''', '''    cands = find_candidates(args.candidates)
    loader = None                                  # set below when Your mix is built from the originals

    if args.check_recipes:''')

# 5. Your mix from the originals: the gate, the pinned windows, the loader
edit(P, '''        jobs = [(recipe.MINE_NAME, mine, os.path.abspath(args.out or os.path.join(BUILD_DIR, recipe.MINE_NAME)))]
''', '''        name = recipe.MINE_NAME + ("-originals" if from_originals else "")
        if from_originals:
            try:
                doc = sources.load(args.sources)
            except (sources.SourcesError, OSError) as e:
                print("mine: %s" % e, file=sys.stderr)
                return 2
            not_ready = sources.gate(doc, mine)        # the licence gate, the pins and the checked windows
            if not_ready:
                print("mine: not built, the originals are not ready:\\n  " + "\\n  ".join(not_ready), file=sys.stderr)
                return 2
            folder = find_folder(args.originals or None, "NM_SOUND_ORIGINALS", "originals")
            if folder is None:
                print("mine: originals folder not found; pass --originals DIR or set NM_SOUND_ORIGINALS", file=sys.stderr)
                return 2
            loader = originals.OriginalsLoader(folder, doc)
            mine = originals.pinned_recipe(mine, doc)
        jobs = [(recipe.MINE_NAME, mine, os.path.abspath(args.out or os.path.join(BUILD_DIR, name)))]
''')

# 6. who may write the shipping folder, and which loader builds
edit(P, '''    refusal = refuse_shipping_folder(jobs)
    if refusal:
        print(refusal, file=sys.stderr)
        return 2
    if cands is None:
        print("candidates folder not found; pass --candidates or set NM_SOUND_CANDIDATES", file=sys.stderr)
        return 2
    loader, cache, results = AfconvertLoader(cands), {}, OrderedDict()
    for name, rec, out in jobs:
        gone = recipe.missing_sources(rec, cands)
''', '''    refusal = refuse_shipping_folder(jobs, from_originals)
    if refusal:
        print(refusal, file=sys.stderr)
        return 2
    if loader is None:
        if cands is None:
            print("candidates folder not found; pass --candidates or set NM_SOUND_CANDIDATES", file=sys.stderr)
            return 2
        loader = AfconvertLoader(cands)
    cache, results = {}, OrderedDict()
    for name, rec, out in jobs:
        gone = [] if from_originals else recipe.missing_sources(rec, cands)
''')

# 7. a shipping folder that holds anything but the pack fails the build
edit(P, '''    waiting = []
    if args.round2 and mix is not None:''', '''    stray = ship_problems(jobs[0][2]) if from_originals and in_ship_dir(jobs[0][2]) else []
    for line in stray:
        print("SHIP " + line, file=sys.stderr)
    waiting = []
    if args.round2 and mix is not None:''')
edit(P, '''        for line in bad:
            print("FAIL " + line, file=sys.stderr)
        return 1 if bad else 0
    return 0
''', '''        for line in bad:
            print("FAIL " + line, file=sys.stderr)
        return 1 if bad or stray else 0
    return 1 if stray else 0
''')
EOF
```

- [ ] **Step 5: Run the new tests, then everything**

<!-- replay -->
```bash
python3 -m unittest discover -s tests -p 'test_sound_originals.py' 2>&1 | tail -4
bash scripts/test-sound-build.sh 2>&1 | tail -6
python3 tools/sounds/build_pack.py --set mine --originals || echo "exit $?"
```

Expected: `Ran 17 tests ... OK` for the new file (about 17 s); the script ends with `Ran N+59 tests ... OK`. The last command is the gate working on the real seed: it prints `mine: not built, the originals are not ready:` followed by four lines (`23 clips have no verified CC0 entry ...`, `23 originals are not pinned ...`, `23 clips have no measured offset ...`, `27 windows are not pinned and checked: ...`) and `exit 2`, and writes nothing.

- [ ] **Step 6: Commit**

<!-- replay-commit -->
```bash
git add tools/sounds/originals.py tools/sounds/build_pack.py tests/sound_pack_support.py tests/test_sound_originals.py
git commit -m "feat(sounds): pin, align and load the originals, and build Your mix from them behind the licence gate

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The licence re-check, on each clip's own page

The spec asks for an independent re-check of the licence on every shipped clip's own page, before the originals. **How it is done here:** a clip's Freesound page is public HTML. `originals.py page SRC` reads that HTML on stdin and takes nobody's word for it: it records a licence only when the page's own tags say the maker `sources.json` names, the licence link is a CC0 link (`creativecommons.org/publicdomain/zero/1.0/`) with the name "Creative Commons 0", there is exactly one Creative Commons link on the page, and the Sound information block shows a Type, a Duration and a File size. Then it writes `licence`, `licence_url`, `checked_on` (today), `checked_by` (the `--by` text), the page's own title and the page's own Sound information into the entry, and reports in `WARN` lines any figure that differs from what the seed had. Anything else prints `NOT RECORDED` and writes nothing. The tool never touches the network: whoever runs the check runs `curl` on the public page and pipes it in.

This task writes the tool (code and tests, `nm-implementer-light`), then a **second, fresh agent** runs it over the 23 pages, which is the independent part: whoever wrote the tool does not run the check.

**Files:**
- Modify: `tools/sounds/sources.py` (`import html`; `STATED_LABELS`, `parse_page`, `check_page`, `record_check`, inserted before `find_original`)
- Modify: `tools/sounds/originals.py` (the `page` command: `import datetime`, `record_page`, the command's arguments and branch, the usage text)
- Create: `tests/test_sound_page.py`
- Modify: `design/sounds/sources.json` (data: the 23 licence entries)

**Interfaces:**
- Consumes: Task 2's `sources.CC0`, `CC0_URLS`, `DATE`, `is_verified`, `parse_duration`, `file_sources`; Task 4's `originals.main`, `load_mine`, `SOURCES_PATH`.
- Produces (`sources`): `STATED_LABELS`, `parse_page(html_text) -> {"title", "author", "licence_name", "licence_url", "stated"}` (a value the page does not show is `None`; `stated` is an ordered dict of the Sound information as printed, no-break spaces read as spaces), `check_page(entry, page) -> [str]` (empty means the page vouches), `record_check(entry, page, by, on) -> [warning]`. Produces (`originals`): `record_page(args, doc, rec) -> exit code` and the command `page SRC --by TEXT [--date YYYY-MM-DD] [--sources FILE]`, HTML on stdin; exit 0 recorded, 1 not recorded, 2 a usage error.

- [ ] **Step 1: Write the failing tests**

<!-- replay -->
```bash
cat > tests/test_sound_page.py <<'EOF'
"""Tests for the licence re-check: reading a clip's own Freesound page (sub-project C, stage 2, task 5). Standard library only."""
import contextlib
import io
import os
import shutil
import sys
import tempfile
import unittest
from unittest import mock

from sound_pack_support import SOURCES_JSON, blanked

import originals  # noqa: E402
import sources  # noqa: E402


PAGE = """<html><head>
<title>Freesound - kitten22.wav by Department64</title>
<meta property="og:title" content="kitten22.wav by Department64" />
<meta property="og:audio:artist" content="Department64" />
<meta property="og:audio:title" content="kitten22.wav" />
</head><body>
<span class="bw-icon-zero"></span> <a title="Go to the full license text" href="%(url)s" target="_blank" class="bw-link--black">%(name)s</a>
<div class="row">
<div class="col-2 text-center text-17">
<p class="text-grey no-margins">Type</p>
<p class="no-margins">Wave (.wav)</p>
</div>
<div class="col-2 text-center text-17">
<p class="text-grey no-margins">Duration</p>
<p class="no-margins">0:00.643</p>
</div>
<div class="col-2 text-center text-17">
<p class="text-grey no-margins">File size</p>
<p class="no-margins">110.9 KB</p>
</div>
<div class="col-2 text-center text-17">
<p class="text-grey no-margins">Sample rate</p>
<p class="no-margins">44100.0 Hz</p>
</div>
<div class="col-2 text-center text-17">
<p class="text-grey no-margins">Bit depth</p>
<p class="no-margins">16 bit</p>
</div>
<div class="col-2 text-center text-17">
<p class="text-grey no-margins">Channels</p>
<p class="no-margins">Stereo</p>
</div>
</div>
</body></html>"""
CC0_PAGE = PAGE % {"url": "http://creativecommons.org/publicdomain/zero/1.0/", "name": "Creative Commons 0"}
BY_PAGE = PAGE % {"url": "https://creativecommons.org/licenses/by/4.0/", "name": "Attribution 4.0"}


class TestPageCheck(unittest.TestCase):
    """The licence re-check reads each clip's own page. The tool reads the page's HTML; it takes nobody's word for it."""
    SOURCE = "love/fs-64017-Department64.mp3"

    def setUp(self):
        self.doc = blanked(sources.load(SOURCES_JSON))
        self.entry = self.doc["sources"][self.SOURCE]

    def test_the_page_is_read_from_its_own_tags(self):
        page = sources.parse_page(CC0_PAGE)
        self.assertEqual({k: v for k, v in page.items() if k != "stated"},
                         {"title": "kitten22.wav", "author": "Department64", "licence_name": "Creative Commons 0",
                          "licence_url": "http://creativecommons.org/publicdomain/zero/1.0/"})
        self.assertEqual(list(page["stated"].items()),
                         [("type", "Wave (.wav)"), ("duration", "0:00.643"), ("size", "110.9 KB"),
                          ("sample_rate", "44100.0 Hz"), ("bit_depth", "16 bit"), ("channels", "Stereo")])
        self.assertEqual(sources.check_page(self.entry, page), [])
        self.assertEqual(sources.parse_page("<html>nothing here</html>"),
                         {"title": None, "author": None, "licence_name": None, "licence_url": None, "stated": {}})

    def test_a_no_break_space_before_the_unit_is_read_as_a_space(self):
        page = sources.parse_page(CC0_PAGE.replace("110.9 KB", "110.9\u00a0KB").replace("0:00.643", "0:00.643 "))
        self.assertEqual((page["stated"]["size"], page["stated"]["duration"]), ("110.9 KB", "0:00.643"))

    def test_the_sound_information_of_an_ogg_page_has_a_bitrate_and_no_bit_depth(self):
        ogg = CC0_PAGE.replace("Wave (.wav)", "Ogg Vorbis (.ogg)").replace(
            '<p class="text-grey no-margins">Bit depth</p>\n<p class="no-margins">16 bit</p>',
            '<p class="text-grey no-margins">Bitrate</p>\n<p class="no-margins">232 kbps</p>')
        stated = sources.parse_page(ogg)["stated"]
        self.assertEqual((stated["type"], stated["bitrate"]), ("Ogg Vorbis (.ogg)", "232 kbps"))
        self.assertNotIn("bit_depth", stated)

    def test_the_seeds_figures_are_the_ones_a_page_prints(self):
        for source, e in self.doc["sources"].items():
            self.assertEqual(e["stated"]["sample_rate"].split(".")[-1], "0 Hz", source)       # '44100.0 Hz', as the page has it

    def test_only_a_plain_cc0_page_by_the_right_maker_vouches_for_a_clip(self):
        said = sources.check_page(self.entry, sources.parse_page(BY_PAGE))
        self.assertEqual(len(said), 2)
        self.assertIn("not 'Creative Commons 0'", said[0])
        self.assertIn("not a CC0 link", said[1])
        other = sources.parse_page(CC0_PAGE.replace('content="Department64"', 'content="Somebody"'))
        self.assertIn("maker is 'Somebody'", sources.check_page(self.entry, other)[0])
        nothing = sources.check_page(self.entry, sources.parse_page("<html></html>"))
        self.assertEqual(len(nothing), 6)                    # maker, licence name, link, and the three figures
        no_figures = sources.check_page(self.entry, sources.parse_page(CC0_PAGE.replace("Duration", "Length")))
        self.assertEqual(no_figures, ["the page shows no duration in its Sound information"])

    def test_a_page_with_two_different_creative_commons_links_is_ambiguous(self):
        both = CC0_PAGE.replace("</body>", '<a href="https://creativecommons.org/licenses/by/4.0/">Attribution 4.0</a></body>')
        page = sources.parse_page(both)
        self.assertIsNone(page["licence_url"])
        self.assertTrue(sources.check_page(self.entry, page))
        twice = CC0_PAGE.replace("</body>", '<a href="http://creativecommons.org/publicdomain/zero/1.0/">CC0 again</a></body>')
        self.assertEqual(sources.check_page(self.entry, sources.parse_page(twice)), [])      # the same link twice is fine

    def test_recording_writes_the_licence_the_reader_the_day_and_the_pages_own_figures(self):
        self.assertEqual(sources.record_check(self.entry, sources.parse_page(CC0_PAGE), "a re-check agent", "2026-10-06"), [])
        self.assertTrue(sources.is_verified(self.entry))
        self.assertEqual((self.entry["checked_by"], self.entry["checked_on"]), ("a re-check agent", "2026-10-06"))
        longer = sources.parse_page(CC0_PAGE.replace("0:00.643", "0:00.700").replace("kitten22.wav by", "x by"))
        warnings = sources.record_check(self.entry, longer, "a re-check agent", "2026-10-07")
        self.assertEqual(warnings, ["duration was '0:00.643', the page says '0:00.700'"])
        self.assertEqual(self.entry["stated"]["duration"], "0:00.700")                   # the page's figure wins, and is reported

    def run_page(self, html, *argv):
        tmp = tempfile.mkdtemp(prefix="nm page ")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        path = os.path.join(tmp, "sources.json")
        sources.save(path, self.doc)
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(sys, "stdin", io.StringIO(html)), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = originals.main(["page", *argv, "--sources", path])
        return code, out.getvalue(), err.getvalue(), sources.load(path)

    def test_the_command_records_a_cc0_page_and_only_that(self):
        code, out, err, saved = self.run_page(CC0_PAGE, self.SOURCE, "--by", "a re-check agent", "--date", "2026-10-06")
        self.assertEqual(code, 0, err)
        self.assertIn("recorded %s: Creative Commons 0 by Department64, read on 2026-10-06" % self.SOURCE, out)
        self.assertTrue(sources.is_verified(saved["sources"][self.SOURCE]))
        self.assertFalse(sources.is_verified(saved["sources"]["love/fs-436542-Mafon2.mp3"]))       # only the one clip
        code, _, err, saved = self.run_page(BY_PAGE, self.SOURCE, "--by", "a re-check agent")
        self.assertEqual(code, 1)
        self.assertIn("NOT RECORDED %s" % self.SOURCE, err)
        self.assertFalse(sources.is_verified(saved["sources"][self.SOURCE]))

    def test_the_command_wants_a_clip_of_your_mix_a_reader_and_a_real_date(self):
        self.assertEqual(self.run_page(CC0_PAGE, "love/fs-1-Nobody.mp3", "--by", "x")[0], 2)
        self.assertEqual(self.run_page(CC0_PAGE, self.SOURCE)[0], 2)
        self.assertEqual(self.run_page(CC0_PAGE, self.SOURCE, "--by", "x", "--date", "6 October")[0], 2)


if __name__ == "__main__":
    unittest.main()
EOF
```

- [ ] **Step 2: Run them to see them fail**

<!-- replay-fail -->
```bash
python3 -m unittest discover -s tests -p 'test_sound_page.py' 2>&1 | tail -6
```

Expected: errors, `module 'sources' has no attribute 'parse_page'`.

- [ ] **Step 3: Add the page functions to `sources.py` and the `page` command to `originals.py`**

The two blocks are written to files first, then inserted at their markers.

<!-- replay -->
```bash
cat > "${TMPDIR:-/tmp}/c2-sources-block.py" <<'EOF'
STATED_LABELS = OrderedDict([("Type", "type"), ("Duration", "duration"), ("File size", "size"), ("Sample rate", "sample_rate"),
                             ("Bit depth", "bit_depth"), ("Bitrate", "bitrate"), ("Channels", "channels")])


def parse_page(text):
    """What a Freesound sound page says, read from its HTML: title and author (its <meta> tags), the licence link and
    its name, and the Sound information block (type, duration, size, sample rate, bit depth or bitrate, channels) as
    printed. A value the page does not show is None (stated: empty). More than one distinct creativecommons.org
    link on the page leaves the licence None: the page is ambiguous."""
    def meta(prop):
        found = re.search(r'<meta\s+property="%s"\s+content="([^"]*)"' % re.escape(prop), text)
        return html.unescape(found.group(1)).strip() if found else None
    links = re.findall(r'<a\s[^>]*href="(https?://creativecommons\.org/[^"]*)"[^>]*>\s*([^<]*?)\s*</a>', text)
    one = links[0] if len({url for url, _ in links}) == 1 else (None, None)
    stated = OrderedDict()
    for label, value in re.findall(r'<p class="text-grey no-margins">\s*([^<]+?)\s*</p>\s*<p class="no-margins">\s*([^<]*?)\s*</p>', text):
        if label in STATED_LABELS and STATED_LABELS[label] not in stated:
            stated[STATED_LABELS[label]] = " ".join(html.unescape(value).split())      # the page puts a no-break space before KB
    return {"title": meta("og:audio:title"), "author": meta("og:audio:artist"),
            "licence_name": one[1] and html.unescape(one[1]), "licence_url": one[0], "stated": stated}


def check_page(entry, page):
    """What stops a page from vouching for its clip: not the maker the entry names, not a plain Creative Commons 0
    licence with the CC0 link, or no Type, Duration and File size to check the download against. Empty means go."""
    out = []
    if page["author"] != entry["author"]:
        out.append("the page's maker is %r, not %r" % (page["author"], entry["author"]))
    if page["licence_name"] != "Creative Commons 0":
        out.append("the page's licence is %r, not 'Creative Commons 0'" % page["licence_name"])
    if page["licence_url"] not in CC0_URLS:
        out.append("the page's licence link is %r, not a CC0 link" % page["licence_url"])
    for key in ("type", "duration", "size"):
        if key not in page["stated"]:
            out.append("the page shows no %s in its Sound information" % key)
    return out


def record_check(entry, page, by, on):
    """Write what the page vouched for into the entry: the licence, its link, who read it and when, the title as the
    page shows it and the page's own Sound information. Returns warnings: what the page says now that differs from
    what the entry had (the caller has run check_page first)."""
    changed = ["%s was %r, the page says %r" % (k, entry["stated"].get(k), v)
               for k, v in page["stated"].items() if entry["stated"].get(k) != v]
    changed += ["%s was %r, the page shows none" % (k, v) for k, v in entry["stated"].items() if k not in page["stated"]]
    entry.update(licence=CC0, licence_url=page["licence_url"], checked_on=on, checked_by=by, stated=OrderedDict(page["stated"]))
    if page["title"]:
        entry["title"] = page["title"]
    return changed


EOF
```

<!-- replay -->
```bash
cat > "${TMPDIR:-/tmp}/c2-record-page.py" <<'EOF'
def record_page(args, doc, rec):
    """`page`: the HTML of one clip's own page on stdin. Records the licence only when the page vouches for it."""
    if args.source not in sources.file_sources(rec):
        print("page: %r is not a recorded clip of Your mix" % args.source, file=sys.stderr)
        return 2
    if not args.by or not args.by.strip():
        print("page: say who read the page with --by", file=sys.stderr)
        return 2
    on = args.date or datetime.date.today().isoformat()
    if not sources.DATE.match(on):
        print("page: --date must be YYYY-MM-DD", file=sys.stderr)
        return 2
    page = sources.parse_page(sys.stdin.read())
    entry = doc["sources"][args.source]
    bad = sources.check_page(entry, page)
    if bad:
        print("NOT RECORDED %s: %s" % (args.source, "; ".join(bad)), file=sys.stderr)
        return 1
    for warning in sources.record_check(entry, page, args.by.strip(), on):
        print("WARN %s: %s" % (args.source, warning), file=sys.stderr)
    sources.save(args.sources, doc)
    print("recorded %s: %s by %s, read on %s" % (args.source, page["licence_name"], page["author"], on))
    return 0


EOF
```

<!-- replay -->
```bash
python3 - <<'EOF'
import os

TMP = os.environ.get("TMPDIR", "/tmp")


def edit(path, old, new):
    with open(path, encoding="utf-8") as f:
        s = f.read()
    assert s.count(old) == 1, "%s: the text to replace is not there exactly once:\n%s" % (path, old)
    with open(path, "w", encoding="utf-8") as f:
        f.write(s.replace(old, new))


def read(name):
    with open(os.path.join(TMP, name), encoding="utf-8") as f:
        return f.read()


S, O = "tools/sounds/sources.py", "tools/sounds/originals.py"

# sources.py: read a page, check it, record it
edit(S, "import json\nimport os\nimport re\n", "import html\nimport json\nimport os\nimport re\n")
edit(S, "def find_original(folder, source, entry):", read("c2-sources-block.py") + "def find_original(folder, source, entry):")

# originals.py: the `page` command
edit(O, '''  originals.py credits   write docs/SOUND-CREDITS.md from sources.json
''', '''  originals.py credits   write docs/SOUND-CREDITS.md from sources.json
  originals.py page SRC  read a clip's own Freesound page (its HTML on stdin) and record its licence for source SRC:
                           curl -sL "<page>" | python3 tools/sounds/originals.py page love/fs-64017-Department64.mp3 --by "..."
                         Only a page that says Creative Commons 0, with the CC0 link and the right maker, is recorded.
''')
edit(O, "import argparse\nimport hashlib\n", "import argparse\nimport datetime\nimport hashlib\n")
edit(O, '''    ap.add_argument("command", choices=("list", "pin", "align", "credits"))''', '''    ap.add_argument("command", choices=("list", "pin", "align", "credits", "page"))
    ap.add_argument("source", nargs="?", help="page: the recipe source name the page on stdin belongs to")
    ap.add_argument("--by", help="page: who read the page, for sources.json (e.g. 'licence re-check agent, Sonnet 5.5')")
    ap.add_argument("--date", help="page: the day it was read, YYYY-MM-DD (default: today)")''')
edit(O, '''    folder = _folder(args.originals, "originals", "NM_SOUND_ORIGINALS")

    if args.command == "list":''', '''    folder = _folder(args.originals, "originals", "NM_SOUND_ORIGINALS")

    if args.command == "page":
        return record_page(args, doc, rec)
    if args.command == "list":''')
edit(O, "def _folder(explicit, name, env):", read("c2-record-page.py") + "def _folder(explicit, name, env):")
EOF
```

- [ ] **Step 4: Run the tests**

<!-- replay -->
```bash
python3 -m unittest discover -s tests -p 'test_sound_page.py' 2>&1 | tail -4
bash scripts/test-sound-build.sh 2>&1 | tail -6
```

Expected: `Ran 9 tests ... OK`; the script ends with `Ran N+68 tests ... OK`.

- [ ] **Step 5: Commit the tool**

<!-- replay-commit -->
```bash
git add tools/sounds/sources.py tools/sounds/originals.py tests/test_sound_page.py
git commit -m "feat(sounds): record a clip's licence only from its own page: CC0 link, the right maker, one licence

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: The re-check, by a second agent**

Dispatch a **fresh** `nm-implementer-light` with this prompt (it must not be the agent that wrote Steps 1 to 5):

> You are the licence re-check for NotchMeow's sound pack. Work in this worktree. For each of the 23 clips in `design/sounds/sources.json`, run the loop below. It reads the clip's own public Freesound page with `curl` (no sign-in, nothing saved) and pipes the HTML to a tool that records the licence only if the page says Creative Commons 0 by the right maker. You do not judge, download any audio, log in, open a browser or edit any file by hand. Use `--by "licence re-check, <your agent name>, <your model>"`. Report every output line of the loop verbatim and the final count. If any line starts with `NOT RECORDED` or `WARN`, report it and stop without changing anything.

The loop (the pages list is written first and sits in `${TMPDIR:-/tmp}`):

<!-- replay -->
```bash
python3 - <<'EOF' > "${TMPDIR:-/tmp}/c2-pages.list"
import json
for source, e in json.load(open("design/sounds/sources.json"))["sources"].items():
    print(source, e["page"])
EOF
wc -l < "${TMPDIR:-/tmp}/c2-pages.list"
while read -r SRC URL; do
  curl -sL -m 30 -A "Mozilla/5.0 (NotchMeow licence check)" "$URL" \
    | python3 tools/sounds/originals.py page "$SRC" --by "licence re-check, a fresh agent"
  sleep 1
done < "${TMPDIR:-/tmp}/c2-pages.list"
python3 - <<'EOF'
import sys
sys.path.insert(0, "tools/sounds")
import sources
doc = sources.load("design/sounds/sources.json")
print(sum(1 for e in doc["sources"].values() if sources.is_verified(e)), "of", len(doc["sources"]), "verified")
EOF
```

Expected: `23`, then 23 lines `recorded <source>: Creative Commons 0 by <maker>, read on <date>` with no `WARN` and no `NOT RECORDED`, then `23 of 23 verified`. (On 2026-10-05 all 23 pages did read "Creative Commons 0" and every figure in the seed matched the page.) The only expected difference is the title of `tick`: its page spells it `Сeramic Сlick` with two Cyrillic letters, and the tool copies the title as the page has it.

If a page says anything else (another licence, two licences, a different maker), nothing is recorded for that clip: the session stops, shows the line to the owner and asks. It does not swap the clip, edit the file or retry with different words.

- [ ] **Step 7: Review the check, then commit the data**

The `nm-reviewer` for this task also opens three of the 23 pages itself (for example `love/fs-436542-Mafon2.mp3`, `hairball/fs-561726-har2h.mp3`, `pop/fs-258269-jcallison.mp3`), reads the licence line with its own eyes (WebFetch or `curl`) and confirms it against `sources.json`. Then:

<!-- replay-commit -->
```bash
git diff --stat design/sounds/sources.json
git add design/sounds/sources.json
git commit -m "data(sounds): licence re-check: the 23 clips are CC0 on their own pages

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 6: The originals list, and the owner's downloads (the session stops here)

This task is the controller's own: it talks to the owner and runs no subagent. **It produces the exact list of originals and then stops.** Nothing in it, or in any later task, downloads a file, logs in, or uses the owner's browser: Freesound only gives an original to a signed-in account, so the owner downloads those 23 files themselves.

**Files:**
- Create (git-ignored, not committed): `$NM_SOUND_ORIGINALS/DOWNLOAD-LIST.md`

**Interfaces:**
- Consumes: `originals.py list`, which writes `sources.download_list_text(doc, rec, folder)` for Your mix and prints it. The list has two groups: **the Freesound clips** (each needs the owner's sign-in; entry per clip: page URL, maker, title, what the page states about the original, the slots it serves, and the number its file name starts with) and **direct links** (a clip whose source is not on Freesound, with its link).
- Produces: the folder `$NM_SOUND_ORIGINALS`, the list file in it, and the owner's message.

- [ ] **Step 1: Create the folder and write the list**

`$NM_SOUND_ORIGINALS` is set in "Paths" at the top; it is the main checkout's `.claude/sounds/originals/`, which git ignores (`.claude/`).

<!-- replay -->
```bash
mkdir -p "$NM_SOUND_ORIGINALS"
python3 tools/sounds/originals.py list | sed -n '1,14p'
ls "$NM_SOUND_ORIGINALS"
```

Expected: the folder holds `DOWNLOAD-LIST.md`. The list begins `# Originals to download`, then `## Needs your Freesound sign-in: download these yourself (23)` with one checkbox entry per clip, and ends with `## Direct links, with your OK before anything is downloaded (0)` and `None: Your mix uses no BigSoundBank clip.`

- [ ] **Step 2: If the direct-link group is not empty, ask before anything**

Today it is empty: Your mix has no BigSoundBank clip (the hairball's is Freesound's too), so there is nothing to ask. If it ever is not (a later change to `mine.json` picked a BigSoundBank clip), do this and nothing else first: tell the owner, in chat, each file's name, the source link the list gives and its size (the page's File size), and ask for a clear yes. Without the yes, download nothing. With it, download only those files, one `curl -fL -o "$NM_SOUND_ORIGINALS/<name>" "<link>"` each, from that link, and say in the reply that you did. Never combine this with the Freesound group, which is never downloaded by an agent.

- [ ] **Step 3: Tell the owner what to do, then stop**

Send the owner this (adjusting nothing but the folder path if it differs), and then **do nothing else until they reply**:

> Your mix is built from 23 clips, and Freesound only hands out the full-quality originals to a signed-in account, so I can't fetch them: please download them yourself. Sign in to Freesound in your own browser, open each page from the list, press Download, and save the file into `/path/to/notchmeow/.claude/sounds/originals/` without renaming it (Freesound names it `<number>__<user>__<name>.<ext>`; if your browser adds a "(1)", delete the extra copy). The list, with a page link and a checkbox for each, is saved in that folder as `DOWNLOAD-LIST.md` and pasted below. 23 files, about 36 MB in all; five are big (Cat_Hunting 18.4 MB, Cat purr 8.3 MB, Cat Coughing 3.9 MB, Cat licking her paw 1.8 MB, cat chirp 1.4 MB). One of them, Mouth pop, is an Ogg Vorbis file rather than a WAV, which is fine: save it as it comes. I will not log in, use your browser, or download anything for you. Tell me "downloaded" when the 23 files are in the folder.

- [ ] **Step 4: When the owner says "downloaded", count and go on**

<!-- replay-after-downloads -->
```bash
ls "$NM_SOUND_ORIGINALS" | grep -v DOWNLOAD-LIST.md | wc -l
```

Expected: `23`. If it is not, say which numbers are missing (compare `ls` against the list's `<id>__` prefixes) and ask the owner; do not go on to Task 7 with fewer.

Nothing from this task is committed.

---

### Task 7: Pin the real originals and check every window

Runs the tools of Task 4 on the 23 files the owner downloaded. It reads the owner's files and the preview clips and writes only `design/sounds/sources.json`. **Whatever this finds is the owner's call:** the task stops and reports on the first problem, and never edits `sources.json` by hand, loosens a number or swaps a clip to get past it.

**Files:**
- Modify: `design/sounds/sources.json` (data: `original`, `offset_s` and `windows` of the 23 clips)

**Interfaces:**
- Consumes: `originals.py pin` and `originals.py align` (Task 4), the folder `$NM_SOUND_ORIGINALS` (Task 6) and the preview clips (`$NM_SOUND_CANDIDATES`).
- Produces: a `sources.json` in which every recorded clip is verified (Task 5), pinned, measured and window-checked, so that `sources.gate(doc, mine) == []`.

- [ ] **Step 1: Pin the originals**

<!-- replay-after-downloads -->
```bash
python3 tools/sounds/originals.py pin
```

Expected: `pinned 23 of 23 originals` and exit 0. Otherwise each problem is printed as `PROBLEM <source>: <what>`, exit 1, and the clips that did pass are still pinned. The likely ones, and what each means:
- `no file named <id>__* in ...` or `more than one file for it`: a file is missing, or the browser saved a second copy. Tell the owner which.
- `... is not a Wave (.wav) file` or `... its page says <size>`: the wrong thing was saved (a preview MP3, or another clip). Tell the owner which clip.
- `afconvert cannot read ...`: expected for **at most one** file, the Ogg Vorbis `pop` original, if this Mac's `afconvert` does not read Ogg after all. Do not work around it. Stop and give the owner the choices from "Open questions" (another pop sound, which is a change to `design/sounds/sets/_shared.json` and needs a new listen, or a small extension of the tools to record a converted copy).

- [ ] **Step 2: Measure the offsets and check the windows**

<!-- replay-after-downloads -->
```bash
python3 tools/sounds/originals.py align
```

Expected: a table with one row per window (27 rows on today's spec: 24 slots with one window each, plus the hairball's three, named `hairball 1 of 3` and so on; each with the offset in ms, the correlation `r`, both lengths in seconds, and `same sound` or `FAILS`) and the last line `27 of 27 windows hold the same sound`, exit 0. The hairball's three windows share their clip's offset, which is measured on the first one: a window that fails while its two neighbours are fine means that window is wrong, not the file, and three failures mean the first window (and so the offset) should be looked at first. About 10 s. Offsets should be at or near zero (`afconvert` trims the MP3 padding; see "The originals list"), and every `r` should be 0.95 or better; an offset of a few milliseconds is fine and is compensated, and `r` between 0.80 and 0.95 is worth saying out loud. A `FAILS` row means that window does not hold the sound the owner auditioned: stop, give the owner the row, and wait. The longest windows are `sleep` (2.8 s of a 60 s clip) and `search` (0.9 s of a 67 s clip).

- [ ] **Step 3: Check the gate is satisfied**

<!-- replay-after-downloads -->
```bash
python3 - <<'EOF'
import sys
sys.path.insert(0, "tools/sounds")
import originals, sources
rec = originals.load_mine("design/sounds/sets")
doc = sources.load("design/sounds/sources.json")
print(sources.gate(doc, rec) or "gate: nothing in the way")
print(len(sources.file_sources(rec)), "clips,", len({s for v in sources.file_sources(rec).values() for s in v}), "recorded slots")
EOF
```

Expected: `gate: nothing in the way` and `23 clips, 25 recorded slots`.

- [ ] **Step 4: Commit**

<!-- replay-commit -->
```bash
git diff --stat design/sounds/sources.json
git add design/sounds/sources.json
git commit -m "data(sounds): pin the 23 originals, measure their offsets and check every window against the previews

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Build the pack, credit it, license it, and let the owner listen

Rebuilds Your mix from the pinned originals into `NotchBuddy/Resources/sounds/`, writes the credits file from `sources.json`, adds the `LICENSE-ASSETS.md` carve-out, and adds the tests that keep the pack, the list and the credits honest from now on. It ends with the owner's listen, which is the stage's real acceptance test (spec, "Risks": the originals may sound slightly different from the auditioned previews).

**Files:**
- Create: `NotchBuddy/Resources/sounds/<slot>.wav` for every slot, 29 once the hairball is in (generated)
- Modify: `NotchBuddy/Resources/sounds/README.md` (rewritten: it said "Empty on purpose")
- Create: `docs/SOUND-CREDITS.md` (generated by `originals.py credits`)
- Modify: `LICENSE-ASSETS.md`, `CLAUDE.md`, `windows/README.md` (the one sentence that counts the sounds)
- Create: `tests/test_sound_shipped.py`

**Interfaces:**
- Consumes: Task 7's `sources.json`, `build_pack.py --set mine --originals`, `originals.py credits`, `sources.gate`, `sources.credits_text`, `build_pack.ship_problems`.
- Produces: the shipped pack and the tests `TestShippedPack` (format, loudness and length targets of the committed files, the gate, the credits against `sources.json`, every recorded slot credited, nothing of Coucou's), `TestShippingFolderIsThePack` (exactly one WAV per slot and `README.md`) and `TestLicenceFiles` (the carve-out, `CLAUDE.md`, the two READMEs). After this task the folder is no longer allowed to be empty: `test_the_shipping_folder_is_exactly_one_wav_per_slot_and_its_readme` fails without them.

- [ ] **Step 1: Write the failing tests**

<!-- replay -->
```bash
cat > tests/test_sound_shipped.py <<'EOF'
"""Tests for the shipped pack and its licence files (sub-project C, stage 2, task 8). Standard library only."""
import os
import re
import unittest
import wave
from collections import OrderedDict

from sound_pack_support import ROOT, SOURCES_JSON, your_mix

import audio_io  # noqa: E402
import build_pack  # noqa: E402
import recipe  # noqa: E402
import sources  # noqa: E402


CREDITS = os.path.join(ROOT, "docs", "SOUND-CREDITS.md")


class TestShippedPack(unittest.TestCase):
    """The pack as committed: one file per slot, their format and loudness, and the paper trail that goes with them."""

    @classmethod
    def setUpClass(cls):
        cls.ship = build_pack.SHIP_DIR
        cls.mix = your_mix()
        cls.doc = sources.load(SOURCES_JSON)

    def test_every_file_is_48_khz_16_bit_mono(self):
        for slot in recipe.SLOTS:
            with wave.open(os.path.join(self.ship, slot + ".wav"), "rb") as w:
                self.assertEqual((w.getframerate(), w.getsampwidth(), w.getnchannels()), (48000, 2, 1), slot)

    def test_every_file_meets_its_loudness_peak_and_length_targets(self):
        import loudness
        import report
        failed = {}
        for slot in recipe.SLOTS:
            samples = audio_io.read_wav(os.path.join(self.ship, slot + ".wav"))[0]
            bad = report.check(slot, loudness.measure(samples))
            if bad:
                failed[slot] = bad
        self.assertEqual(failed, {})

    def test_every_source_is_verified_pinned_and_checked(self):
        self.assertEqual(sources.gate(self.doc, self.mix), [])

    def test_the_credits_file_and_sources_json_agree(self):
        with open(CREDITS, encoding="utf-8") as f:
            self.assertEqual(f.read(), sources.credits_text(self.doc, self.mix))

    def test_every_recorded_slot_is_credited_and_every_credited_slot_ships(self):
        with open(CREDITS, encoding="utf-8") as f:
            rows = [l.split("|")[1].strip() for l in f.read().splitlines()
                    if l.startswith("| ") and not l.startswith("| Slot")]
        recorded = [s for s, e in self.mix.entries.items() for _ in OrderedDict.fromkeys(src for src, _a, _b in sources.clip_uses(e))]
        self.assertEqual(rows, recorded)
        self.assertTrue(all(os.path.isfile(os.path.join(self.ship, s + ".wav")) for s in rows))

    def test_nothing_of_coucous_is_credited_or_sourced(self):
        for path in (CREDITS, SOURCES_JSON):
            with open(path, encoding="utf-8") as f:
                self.assertIsNone(re.search(r"coucou|mochi", f.read(), re.I), path)


class TestShippingFolderIsThePack(unittest.TestCase):
    def test_the_shipping_folder_is_exactly_one_wav_per_slot_and_its_readme(self):
        ship = build_pack.SHIP_DIR
        self.assertEqual(build_pack.ship_problems(ship), [])
        self.assertEqual(sorted(n for n in os.listdir(ship) if n not in build_pack.SHIP_KEEPS),
                         sorted(slot + ".wav" for slot in recipe.SLOTS))
        self.assertTrue(os.path.isfile(os.path.join(ship, "README.md")))


class TestLicenceFiles(unittest.TestCase):
    def test_licence_assets_carves_out_the_cc0_clips_and_keeps_the_mixes_reserved(self):
        with open(os.path.join(ROOT, "LICENSE-ASSETS.md"), encoding="utf-8") as f:
            text = f.read()
        self.assertIn("## The CC0 source clips", text)
        self.assertIn("excluded from the \"all\nrights reserved\"", text)
        self.assertIn("docs/SOUND-CREDITS.md", text)
        self.assertIn("design/sounds/sources.json", text)
        self.assertIn("NotchMeow's own sounds in `NotchBuddy/Resources/sounds/`", text)
        self.assertNotIn("- the sounds in `NotchBuddy/Resources/sounds/`;", text)       # the bare line, without the carve-out

    def test_claude_md_no_longer_says_the_sounds_folder_is_empty(self):
        with open(os.path.join(ROOT, "CLAUDE.md"), encoding="utf-8") as f:
            text = f.read()
        self.assertNotIn("empty until the sounds land", text)
        self.assertIn("docs/SOUND-CREDITS.md", text)
        self.assertIn("Coucou's are reserved and must never be added back", text)

    def test_windows_readme_no_longer_counts_the_sounds(self):
        with open(os.path.join(ROOT, "windows", "README.md"), encoding="utf-8") as f:
            text = f.read()
        self.assertNotIn("The 28 sounds", text)
        self.assertIn("The sounds are the macOS app's own files", text)

    def test_the_shipping_folders_readme_no_longer_says_it_is_empty(self):
        with open(os.path.join(build_pack.SHIP_DIR, "README.md"), encoding="utf-8") as f:
            text = f.read()
        self.assertNotIn("Empty on purpose", text)
        self.assertIn("docs/SOUND-CREDITS.md", text)
        for slot in recipe.SLOTS:
            self.assertIn(slot, text.split("Slots:")[-1].split(), slot)               # the README lists every slot
        self.assertIn("Louis Raillé", text)            # the reminder that Coucou's sounds never come back


if __name__ == "__main__":
    unittest.main()
EOF
```

<!-- replay-fail -->
```bash
python3 -m unittest discover -s tests -p 'test_sound_shipped.py' 2>&1 | tail -6
```

Expected: `FAILED`, with failures and errors from the missing WAVs and credits (the pack does not exist yet); the run itself works.

- [ ] **Step 2: Rehearse the build into the build folder**

Builds Your mix from the originals into `.claude/sounds/build/mine-originals/` first, with a report, so nothing reaches the shipping folder until it is right.

<!-- replay-after-downloads -->
```bash
python3 tools/sounds/build_pack.py --set mine --originals --report
```

Expected: `built mine: 29 files in .../.claude/sounds/build/mine-originals` and `report: .../mine-originals/report.md (29 of 29 files meet their targets)`, exit 0. A `FAIL` line (a file outside its loudness, peak or length target) stops the task: report it to the owner; do not loosen a target and do not edit `pipeline.py` to get past it.

- [ ] **Step 3: Ship it**

<!-- replay-after-downloads -->
```bash
python3 tools/sounds/build_pack.py --set mine --originals --out NotchBuddy/Resources/sounds --report
diff -rq --exclude=report.md --exclude=README.md .claude/sounds/build/mine-originals NotchBuddy/Resources/sounds && echo "the two builds are byte-identical"
ls NotchBuddy/Resources/sounds | wc -l
```

Expected: `built mine: 29 files in .../NotchBuddy/Resources/sounds` and `report: .../.claude/sounds/build/ship-report.md (29 of 29 files meet their targets)` (the report is **not** in the shipping folder); `the two builds are byte-identical` (spec section 6: rebuilding gives byte-identical WAVs); `30` (the 29 WAVs and `README.md`).

- [ ] **Step 4: The README, the credits, the licence carve-out, `CLAUDE.md` and `windows/README.md`**

<!-- replay -->
```bash
cat > NotchBuddy/Resources/sounds/README.md <<'EOF'
# Sounds

NotchMeow's own sounds: 48 kHz, 16-bit, mono WAVs, one per slot and named after it, played at volume 0.12. This folder
holds those files and this README, nothing else (`build_pack.py` and `tests/test_sound_shipped.py` check it).

They are built from CC0 clips, which are credited in `docs/SOUND-CREDITS.md`, by
`python3 tools/sounds/build_pack.py --set mine --originals --out NotchBuddy/Resources/sounds --report`
(see `docs/superpowers/specs/2026-10-04-sounds-design.md`). Don't edit the WAVs by hand: rebuild them.
Coucou's sounds are © Louis Raillé and must never be added back.

Both players skip missing files, so a slot without a WAV is simply silent:
`SoundEngine.swift` (macOS) and `windows/src/core/sound.ts` (Windows, Linux).

Slots:
peek open close hover blip slap annoyed dizzy greet work finish error approval
question approve gulp tick send love pop proud wink yawn attach think search rate sleep hairball
EOF
```

<!-- replay-after-downloads -->
```bash
python3 tools/sounds/originals.py credits
```

Expected: `wrote .../docs/SOUND-CREDITS.md` (it refuses, naming what is missing, if a clip is not verified or not pinned).

<!-- replay -->
```bash
python3 - <<'EOF'
def edit(path, old, new):
    with open(path, encoding="utf-8") as f:
        s = f.read()
    assert s.count(old) == 1, "%s: the text to replace is not there exactly once:\n%s" % (path, old)
    with open(path, "w", encoding="utf-8") as f:
        f.write(s.replace(old, new))


# LICENSE-ASSETS.md: the CC0 clips stay CC0, NotchMeow's own work stays reserved
edit("LICENSE-ASSETS.md", "- the sounds in `NotchBuddy/Resources/sounds/`;\n",
     "- NotchMeow's own sounds in `NotchBuddy/Resources/sounds/`: the mixes, one per slot, and the sounds made in code. The CC0 clips\n"
     "  they are built from are **not** covered by this file, see [The CC0 source clips](#the-cc0-source-clips);\n")
edit("LICENSE-ASSETS.md", "## What you can do\n", """## The CC0 source clips

The recorded clips behind NotchMeow's sounds were released by their makers under Creative Commons Zero
([CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)). They stay CC0, and they are excluded from the "all
rights reserved" above: nothing here takes that back. Each one is listed, with its maker, its page, the date its
licence was checked and the SHA-256 of the original, in [docs/SOUND-CREDITS.md](docs/SOUND-CREDITS.md) and, for the
build, in `design/sounds/sources.json`. Get the originals from those pages and use them as CC0 allows.

What stays reserved is NotchMeow's own work on them: how the clips are cut, pitched, layered, levelled and mixed into
the pack's files, and the sounds made in code.

## What you can do
""")

# windows/README.md: the sounds are no longer counted
edit("windows/README.md", "The 28 sounds are the macOS app's own files;", "The sounds are the macOS app's own files;")

# CLAUDE.md: the sounds folder is no longer empty
edit("CLAUDE.md",
     "`NotchBuddy/Resources/sounds/` — NotchMeow's own WAVs (empty until the sounds land; Coucou's are reserved and must never be added back).",
     "`NotchBuddy/Resources/sounds/` — NotchMeow's own WAVs (one per slot), built from CC0 clips by `tools/sounds/build_pack.py` and credited in `docs/SOUND-CREDITS.md` (Coucou's are reserved and must never be added back).")
EOF
```

- [ ] **Step 5: Run the tests**

<!-- replay-after-downloads -->
```bash
python3 -m unittest discover -s tests -p 'test_sound_shipped.py' 2>&1 | tail -4
bash scripts/test-sound-build.sh 2>&1 | tail -6
git status --short NotchBuddy/Resources/sounds docs LICENSE-ASSETS.md CLAUDE.md
```

Expected: `Ran 11 tests ... OK`; the script ends with `Ran N+79 tests ... OK`; `git status` lists the new `.wav` files (one per slot), the modified `README.md`, the new `docs/SOUND-CREDITS.md` and the three modified files (`LICENSE-ASSETS.md`, `CLAUDE.md`, `windows/README.md`), and nothing else (no `report.md`, nothing under `.claude/`).

- [ ] **Step 6: Commit, in two commits**

<!-- replay-commit -->
```bash
git add NotchBuddy/Resources/sounds/README.md docs/SOUND-CREDITS.md LICENSE-ASSETS.md CLAUDE.md windows/README.md tests/test_sound_shipped.py
git commit -m "docs(sounds): credits for every sound, the CC0 carve-out, and tests that keep the pack and its paper trail honest

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git add NotchBuddy/Resources/sounds/*.wav
git commit -m "feat(sounds): ship Your mix: one WAV per slot, built from the Freesound originals

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Now the task's `nm-reviewer` and the branch's `nm-reviewer-deep` review, and their findings are fixed, **before** the owner is asked to spend time listening.

- [ ] **Step 7: The owner listens (the session stops here)**

Tell the owner the pack is built and ask them to listen through it once, because the sounds are rebuilt from the originals, not the previews they auditioned. The owner runs this in their own terminal (the session runs it only if the owner says yes, since it plays through their speakers). It plays each slot twice, first the preview build the owner picked, then the shipped original, in the spec's order:

```bash
cd "$(git rev-parse --show-toplevel)"
for s in greet love annoyed dizzy slap finish error approval question proud wink yawn sleep gulp think search work rate approve peek open close hover blip tick send attach pop; do
  echo "$s: preview"; afplay "$MAIN/.claude/sounds/build/mine/$s.wav"; sleep 0.3
  echo "$s: original"; afplay "NotchBuddy/Resources/sounds/$s.wav"; sleep 0.9
done
```

Wait for the owner's verdict. If a sound is not right, that is a change to Your mix (`mine.json`, or a clip's window), which is a new pick and a new plan, not a fix here: report which slot and stop. If they sign off, go on.

- [ ] **Step 8: Verify before saying it is done**

<!-- replay-after-downloads -->
```bash
bash scripts/test-sound-build.sh 2>&1 | tail -6
/usr/bin/python3 -m unittest discover -s tests -p 'test_sound_*.py' 2>&1 | tail -4
git status --short
git log --oneline -9
ls -la NotchBuddy/Resources/sounds | head -40
```

Expected: the script passes (`Ran N+79 tests ... OK`, and the same on the system Python 3.9, about 3 minutes); `git status` is empty (everything committed, nothing untracked); the log shows the stage's commits on top of `cbc771e` or later; the folder holds one WAV per slot and `README.md` only. Report the evidence, not the claim. Nothing is pushed.

---

## Interfaces for Stage 3

Nothing here wires anything; this is what Stage 3 can rely on once Stage 2 has merged.

- **The files.** `NotchBuddy/Resources/sounds/<slot>.wav` for every slot in `recipe.SLOTS` (29 with the hairball), named by the slots the apps call (the 28 already in `SoundEngine.swift` and `windows/src/core/sound.ts`, plus `hairball`, which neither app lists yet: Stage 3 adds it), 48 kHz, 16-bit, mono, within the loudness, peak and length targets of the spec. `tests/test_sound_shipped.py` fails if any of that stops being true.
- **No per-cat pitch in the files.** The per-cat voice (`2^(st/12)` playback rate, except for the hairball, which plays at rate 1), the chattiness volume, the priority and cooldown rules and the visibility rules are all play-time and stay Stage 3's.
- **The source list is a build input, not a runtime one.** The apps never read `sources.json`; they only play the WAVs.
- **A new pick means a new Stage 2 run.** If the owner later changes `mine.json` (or c1c's hairball recipe moves a window), `tests/test_sound_sources.py` fails until `sources.json` names exactly the clips of the new mix, and `build_pack.py --originals` refuses until each new clip is re-checked, downloaded, pinned and window-checked (Tasks 5 to 8, for those clips only).

## Spec coverage

| Spec item | Where |
|---|---|
| Stage 2: "Independent licence re-check, then the originals, then rebuild Your mix into `NotchBuddy/Resources/sounds/`" | Task 5 (re-check by a second agent), Tasks 6 and 7 (originals), Task 8 (rebuild and ship) |
| "Add `sources.json`, `SOUND-CREDITS.md` and the `LICENSE-ASSETS.md` carve-out" | `sources.json`: Tasks 2, 5 and 7; `SOUND-CREDITS.md`: the generator in Task 2, the file in Task 8; the carve-out: Task 8 |
| §5: "`sources.json` is the machine-readable source list. The build refuses any source without a verified CC0 entry" | `sources.licence_problems` and `gate` (Task 2), run before `build_pack.py --originals` writes anything (Task 4); `test_the_build_refuses_a_source_missing_from_sources_json`, `..._without_a_verified_cc0_entry` |
| §5: `SOUND-CREDITS.md` lists "slot, title, author, page URL, licence, licence-check date, and the SHA-256 of the original" | `sources.credits_text` (Task 2); `test_credits_list_every_recorded_slot_once_per_clip_and_name_the_made_in_code_ones`; the file in Task 8 |
| §5: "Re-check. Before Stage 2, a second agent re-checks the licence on every shipped clip's own page" | Task 5: the page's own HTML, read by a fresh agent, recorded only if it says CC0 by the right maker |
| §5: "Originals. ... needs a logged-in download ... Agents never log in or handle credentials." | Task 6: the owner downloads; the Chrome-session route of the spec is not used (the owner's ruling). BigSoundBank direct links: the session asks first, naming file, source and size; none are needed today |
| §3 "Hairball" (added 2026-10-05): one recorded clip, *Cat Coughing* (har2h, 561726, CC0), three windows, with the retch and plop made in code | The clip is on the originals list (row 15). `sources.clip_uses` counts the windows of a placed sound, so the three windows are pinned and checked one by one (Tasks 2, 4 and 7) and the credit is one row for the slot, marked partly made in code. The made-in-code part needs no source |
| §6 Build: "Rebuilding a set gives byte-identical WAVs", "All 29 files exist", the lengths, the loudness report | Task 8 Step 3 (`diff -rq` of two builds), `TestShippedPack`, `TestShippingFolderIsThePack` (both take the count from `recipe.SLOTS`) |
| §6 Licences: "`SOUND-CREDITS.md` and `sources.json` must agree" | `test_the_credits_file_and_sources_json_agree` (Task 8) |
| §6 Owner's manual checks: listen through the pack | Task 8 Step 7 |
| Risks: "Preview versus original ... The owner listens once more after the Stage 2 rebuild" | Task 3 (the window rule), Task 7 (the real check), Task 8 Step 7 (the A/B listen) |
| Risks: loudness on short clips, "the targets allow ±1.5 LU" | Task 1: the tick tolerance now matches |
| The owner's checklist: `--report` writes `report.md` into `--out` | Task 1: `report_path`, `ship_problems`, `refuse_shipping_folder` |
| The owner's checklist: the tick tolerance, ±2.0 in the code against ±1.5 in the spec | Task 1: the code takes the spec's number; all 140 real stage-1 files are within 0.1 LU |
| The owner's checklist: the page's "voice" strings are not tied to the recipes | Task 1: `TestAuditionVoice`; two strings corrected |
| Owner's rule: the shipped files are exactly the WAVs | `ship_problems`; the `README.md` is the only other file allowed (see "Open questions") |
| Owner's rule: the originals list, with page URL, author, file name, format, size, where to save | "The originals list as it stands" above, regenerated and saved by Task 6 |
| c1c-hairball's hand-offs to Stage 2 (its "Overlap with the Stage 2 plan"): the segment sources, har2h's CC0 entry, 29 WAVs and the two READMEs | Met as the "Base" section says: offset and windows pinned in `sources.json` (Tasks 4 and 7), the entry in Tasks 2, 5 and 7, `NotchBuddy/Resources/sounds/README.md` and `windows/README.md` in Task 8 |
| Owner's rule: counts from `recipe.SLOTS`, never 28 | Every count in the code and tests is derived (`recipe.SLOTS`, `file_sources`, `clip_uses`); the numbers in this plan's prose are the values on today's spec |
| CLAUDE.md: Coucou's sounds never come back | `test_nothing_of_coucous_is_credited_or_sourced`; the README's reminder |

## Open questions for the owner

1. **`c1c-hairball` has to land first, and Stage 2 reads its recipe shape from its plan, not from merged code.** The hairball's recorded windows come from `entry.segments` (dicts with `source`, `start`, `end`; the entry's source is `"placed"`) in two functions only, `sources.clip_uses` and `originals.with_windows`; Task 1, Step 1 checks the merged recipe and says what to change if c1c ended up different. c1c's three windows (2.143-2.558, 4.196-4.576, 7.278-7.658 s) were measured on the preview MP3; Task 7 measures them again on the original, and c1c's own note that Stage 2 should re-point the segments at the original and re-pin its byte test is met differently here (offset and windows pinned in `sources.json`, recipes and the preview test untouched): say if you would rather the recipe itself moved to the original.
2. **Do the apps start playing these sounds when Stage 2 merges?** Yes, on the 18 slots they already wire, at volume 0.12, without Stage 3's rules (see "What lands with the files"); the hairball stays unused until Stage 3. Merge Stage 2 together with Stage 3, or accept the interim sound? The plan changes no app code either way.
3. **`README.md` in the shipping folder.** The folder holds one WAV per slot and `README.md` (it was already there, saying "Empty on purpose", and Xcode bundles the folder, so it ships inside the Mac app). The plan rewrites it and allows it. Say if the folder must be WAVs only: the README's text would move to `docs/`, and `SHIP_KEEPS` would lose it.
4. **The `pop` original is Ogg Vorbis.** `afconvert` on this Mac lists Ogg Vorbis, and decoded a different local Ogg file when tried, but Task 7 is the first time it meets this one. If it cannot read it, the choices are: you pick another pop sound that has a WAV original (a change to `_shared.json` and a new listen), or I extend the tools to record a converted copy (the `.ogg`'s hash in the credits, the decoded WAV built from), which the plan does not do today.
5. **The tick tolerance.** The plan makes the code ±1.5 LU like the spec (it was ±2.0, with no recorded reason). Confirm, or say the spec should say ±2.0 for ticks instead. Nothing real needs the extra room today.
6. **The window rule's one number.** A window passes at waveform correlation 0.80 or better after the offset is found. It sits between 0.35 (the best different clip scored) and 0.87 (the harshest degradation of the right clip scored). Any real window that fails is shown to you, never loosened by an agent.
7. **Credits spell titles as the pages do.** Mafon2's tick clip is titled with two Cyrillic letters on its page (`Сeramic Сlick`), and the credits copy it as is.
8. **About 1.8 MB of WAV binaries go into git history**, plus a 36 MB download you make once (18.4 MB of it is one 67-second recording of which the build uses 0.9 s).
9. **Owner's decision (2026-10-08): HQ previews.** There are no WAV originals (the owner has no Freesound account). The 23 HQ previews (the MP3, variable bitrate, Freesound serves publicly for each clip, saved with the owner's OK) in `.claude/sounds/hq-previews/` are the audio source. `sources.json` gets an `hq_preview` field beside `original` (file, bytes, SHA-256, format, decoded sample rate and length; never presented as the original's figures); the loader prefers an original if one is present, otherwise builds from the pinned HQ preview. The credits and the `LICENSE-ASSETS.md` carve-out say "HQ preview" for these clips (the CC0 licence belongs to the sound and was verified on each clip's page). Tasks 6-8 run on the HQ previews, and Open question 4 (Ogg) is moot.
10. **Owner's approval of the sound (2026-10-08).** The owner listened to all 29 slots, the stage-1 pick and then the shipped file for each, and said "Sounds good". The pack is approved as built (Task 8, Step 7). The owner chose to merge as soon as the pack is approved, accepting that both apps play Your mix on the 18 slots they already wire until Stage 3 (answers Open question 2).

## Replay record

`c1c-hairball` had not merged when this plan was written, so the plan was replayed on a **stand-in for it**: a fresh clone of `notchmeow/rebrand` at `479c41a` (the tip when the final replay started) plus a throwaway patch (not part of this plan, and cruder than c1c: the real build, levels, fades and retch are c1c's) that adds the 29th slot and a shared `hairball` entry in the shape c1c's plan gives it (its actual JSON: source `placed`, three `segments` dicts of `hairball/fs-561726-har2h.mp3`, one `synth_layers` dict, `end` 1.48), a crude pipeline for such an entry, and the stage-1 test edits that going from 28 to 29 slots needs. Then every block tagged in this plan, Tasks 1 to 8, was extracted and run in order. Differences from the real run: `git commit` was replaced by `git diff --cached --stat`; the 23 downloads were replaced by stand-in originals (each preview clip converted by `afconvert` to the format its page states, 44.1, 48 or 96 kHz, 16, 24 or 32 bit, mono or stereo, then rewritten without `afconvert`'s filler chunk; `pop` as a WAV, since there is no Ogg encoder here; every stand-in's stated size edited to its own, because a real original carries metadata chunks a stand-in lacks, all in the clone only); Task 5's re-check ran against the real pages. Results, with the real previews and the real recipes:

- Every one of the 54 tagged blocks ended as expected: the six red steps failed for the stated reason, the others passed.
- `bash scripts/test-sound-build.sh`: 147 tests at the start (the stage-1 tests, adjusted to 29 slots by the stand-in), then 155, 176, 189, 206, 215 and finally **226 pass** after Tasks 1 to 5 and 8; the same set passes on the system Python 3.9.6.
- `build_pack.py --all --report`: 145 of 145 files meet their targets (5 sets of 29 slots) with ticks at ±1.5 LU.
- Task 5: all 23 clip pages, the hairball's included, read "Creative Commons 0" by the right maker; every figure in the seed matched the page's own HTML, with no `WARN`.
- Task 7 on the stand-ins: `pinned 23 of 23 originals`; `27 of 27 windows hold the same sound` (24 slots with one window each and the hairball's three), offsets 0.00 ms, `r` between 0.99 and 1.00; the gate then says `23 clips, 25 recorded slots` and `nothing in the way`.
- Task 8 on the stand-ins: the rehearsal and the ship build each report `29 of 29 files meet their targets`, the two builds are byte-identical, the shipping folder holds 30 entries (29 WAVs and `README.md`), the report is in `.claude/sounds/build/ship-report.md`, and the credits file has one row for the hairball, marked partly made in code. The shipped files against a preview build of Your mix: loudness identical to 0.1 LU, full-band correlation 0.987 or better after a four-sample lag search (the stand-ins went through a 44.1 or 96 kHz format and back, so 9 of 29 are byte-identical and the rest differ only by that resampling).
- Mutation checks on the tests: 26 deliberate breaks (a sign flip in the offset, a licence gate that skips the licence, a ship refusal that is off, a loader that skips the hash, an unpinned window, a type check that always passes, a second creative commons link taken as the first, and for the multi-window seam: `clip_uses` blind to segments or reading the entry's own cut as a window, `with_windows` ignoring segments, only the first of a slot's windows checked, aligned or stale-checked, a credit row per window) each made at least one test fail; one that survived (a harmless rewrite of a pin) changed nothing observable, and one test that let a seam break through was strengthened.
- Nothing was committed, downloaded, logged in to or pushed; the installed app was not launched; `nm.log` was not touched; the clones were moved to the Trash.
