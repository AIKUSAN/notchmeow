# G2-0 Link Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give both apps what sub-project G2 ("between your machines") needs from the shared contract before the app plans run: the rules two NotchMeow machines must agree on to pair and to send each other a file, written once in a Python reference and pinned by JSON fixtures under `tests/fixtures/link/`. They are the Noise handshakes' test vectors (`Noise_XX_25519_ChaChaPoly_SHA256` for pairing and `Noise_KK_25519_ChaChaPoly_SHA256` for a transfer, with damaged-message cases), the pairing in order (a commitment, two nonces and a reveal, the code from both nonces and both keys, the two machines that run it, and the clocks around it), the wire layout (records, the first record, the hello, the six frames, the advert's TXT record), what the receiver and the sender do with each frame, and the file-name sanitizer. It also adds the additive `transferOffer` flag to the desktop cat's alert rule in `design/prototype/cat-core.js`. The apps use none of it yet: those are the G2-mac and G2-tauri plans.

**Architecture:** This contract has the shape of the shelf contract (`tests/fixtures/shelf/`): `reference.py` (Python standard library only) holds every rule as plainly as possible and is the tie-breaker, and `build_cases.py` writes the JSON files with every expected answer typed out by hand (the Noise vectors and the pairing codes are the exception: they are pasted once from the reference and frozen, and the Noise vectors were also checked with an independent implementation on CryptoKit), so the fixtures and the reference check each other; `--check` fails on drift. The reference carries its own X25519, ChaCha20 and Poly1305 (checked against the RFC 7748 and RFC 8439 test vectors) so it can replay the Noise vectors without a package. `scripts/test-link-contract.sh` runs both and CI runs that script. The `transferOffer` flag follows the cat contract's way (the rule in `cat-core.js`, the fixture written by `scripts/gen-cat-fixtures.mjs`, additive only). `docs/LINK-CONTRACT.md` is the document the app plans cite. Nothing in G2-0 is visible; the owner answered the open questions on 2026-10-14 (the last sections of this plan), and the printed rule table in Task 9 is for the record.

**Tech Stack:** Python 3.9 or newer (standard library only), Bash, JSON; Node 22 for `cat-core.js` and its generator; `swiftc` once, for a scratch cross-check that is never committed.

**Spec:** `docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md`, revision 2026-10-14, sections "G2. Between your machines" (Discovery, Pairing, Transfer, Safety rules), "G1-0 and G2-0. The contracts", "Checks", "Rounds", "Plans and order" and "Risks". Read the whole spec before starting. This plan implements only G2-0; G2-mac, G2-tauri and everything of G1 are other plans.

**Base:** branch `g2-0/link-contract`, created from `notchmeow/rebrand` at `d6704bd` or later, with this plan file already committed to `notchmeow/rebrand`. This plan touches no app code under `NotchBuddy/` or `windows/`. **It changes no pixel and no behaviour in either app.** The one existing source file it edits is `design/prototype/cat-core.js` (one flag, additive), with its generator and the fixture the generator writes.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec; the lines marked "(plan decision)" are choices this plan makes where the spec is silent, and are answered under "The owner's answers (2026-10-14)".

- **Protocols (spec "Pairing", "Transfer"):** pairing runs **Noise_XX_25519_ChaChaPoly_SHA256** and exchanges long-term static keys; a transfer opens a **Noise_KK_25519_ChaChaPoly_SHA256** session with the stored keys. Only paired static keys open sessions. Every frame is authenticated, and a tampered, replayed or out-of-order frame aborts the transfer.
- **Pairing code (spec "Pairing", and the owner's decision of 2026-10-14):** both screens show the same **6-digit** code and the user clicks **They match** on both. The code is made so that a man in the middle gets **one guess per pairing attempt** (about 1 in 10^6) and cannot grind it offline: a **commit-then-reveal** step (the short-authenticated-string pattern of Vaudenay, ZRTP and Bluetooth's numeric comparison). The initiator sends a commitment to a fresh nonce and its static key before it sees the responder's nonce, the responder answers with a nonce, the initiator reveals, and the code is a hash of both nonces and both static keys. At most **one pairing attempt every 30 seconds**, and the pairing window closes after **2 minutes**. 6 digits only: no 8-digit value.
- **Offer (spec "Transfer"):** the sender's offer carries name, size and type, with no content. The receiver shows Accept and Decline; if unanswered for **2 minutes** the offer is declined automatically. Nothing accepts it except a click. On accept, encrypted chunks stream; either side may cancel. A name collision becomes `name (1).ext`, and so on.
- **Safety rules (spec "Safety rules"):** file names are sanitized: no path separators, `..`, control characters or reserved Windows names (`CON`, `NUL` and so on); they are length-limited; the received byte count must equal the offer. Limits: **4 GB per transfer**, **one active transfer per peer**, no automatic resume, transfers end when the app quits.
- **Fixtures (spec "G2-0"):** `noise-vectors.json`, `pairing-cases.json`, `frames.json`, `filename-cases.json` and a Python `reference.py` that uses the standard library only. The `transferOffer` flag is an additive change to `desktopAlert` in `cat-core.js`, with `desktop-cases.json` regenerated by `node scripts/gen-cat-fixtures.mjs`.
- **Secrets (spec "Rules that apply", `CLAUDE.md`):** the static private key and the peers' keys live in the Keychain or Credential Manager, never on disk or in git. The keys in the fixtures are plain byte patterns made for tests, are marked as such, and are never used as real keys.
- **Strictness (plan decision):** a decoder is strict: UTF-8 without surrogates, overlong forms or code points over U+10FFFF; no byte left over after a frame; a record length of 0 is an error. Byte limits are in UTF-8 bytes, never in characters.
- **Only additive on the cat side.** `tests/fixtures/cat/` changes only by addition: `desktop-cases.json` gains new keys (`offerNote`, `offerCases`) and new trip rows at the end, and **`alertCases`, `note` and `catchNote` stay as they are** so the Mac and Windows replays that run today keep passing (`node scripts/check-fixtures-additive.mjs HEAD` proves it before the commit, and `node scripts/check-fixtures-additive.mjs notchmeow/rebrand` after). The other existing files edited are `docs/CAT-CONTRACT.md` (one section and a table row), `.github/workflows/build.yml` (one step), `CLAUDE.md` and `ARCHITECT.md` (one bullet each) and the spec (its G2-0 table).
- **Python standard library only; no npm package, no new dependency.** Same style as `tests/fixtures/shelf/reference.py` (a `check()` that prints a tick or a cross and counts failures, exit status 1 on any failure).
- **No telemetry, no network, nothing outside the repository.** The scripts read and write only `tests/fixtures/link/` (and print to the terminal). No Python bytecode is written into the repository (`python3 -B`).
- **Nothing of Coucou's comes back, and the names Coucou and Mochi appear in no new file.** `scripts/check-no-leftovers.sh` must stay green.
- **Commits:** local only, never pushed. End every commit message with `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>` when a Haiku agent wrote it, or `Claude Sonnet 5.5` when an `nm-implementer-deep` did.

## SUBAGENT RULES

Every subagent and the controller follow these; the controller puts them in each brief.

- **Never launch, quit or replace a NotchMeow app or the Tauri app.** The work is files, Python and Node. The one Swift program (Task 2, step 5) is a scratch command-line tool that reads a JSON file and prints; it opens no socket and no window.
- **Install and download nothing.** No `pip install`, no `npm install`, no network, no package from anywhere. The Noise vectors are generated, not fetched.
- **Delete with `trash`, never `rm -rf`,** and give scratch files unique names (the prefix `g20-`, in `${TMPDIR:-/tmp}`).
- **Never run the real `claude` binary, never read tokens, never sign in, never read the real `~/.claude`, `~/.gemini` or `~/.codex`.**
- **Never write to `~/Library/Logs/NotchMeow/` or to an app's preferences, and never touch the Keychain.** Nothing in this plan opens a socket or touches `UserDefaults`.
- **No Coucou or Mochi names.**
- **Commit only in a task's commit step, and never push.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder, the second `g2-0/link-contract`. If either is wrong, stop and report.
- **Never edit an existing fixture by hand.** `tests/fixtures/cat/desktop-cases.json` changes only by running `node scripts/gen-cat-fixtures.mjs` (Task 7).
- **Python writes no `__pycache__`** into the repository: run every script with `python3 -B`, and `scripts/test-link-contract.sh` does.
- **Subagents are the `nm-*` agents** (Haiku 5.5 first; Sonnet 5.5 only on a named CLAUDE.md trigger; never Opus or Fable). The table below says which one runs each task.
- **If a command is denied by a permission prompt, stop and report it. Do not look for a workaround.**
- **If a `find` text of an edit step is not found exactly once, stop and report.** Do not edit the anchor. **If a check fails where the plan says it passes, stop and report:** a typed answer and the reference disagree, and which one is right is a design question (it may be a crypto question).

## Review Focus

The spec says what the rules are. It is silent on these inputs, and each would bite a person (or a port) first, most likely first. Each line names its test.

1. **A hostile file name from a paired peer:** `../../etc/passwd`, `/etc/passwd`, `C:\Windows\x`, a NUL, a right-to-left override that makes `invoice[RLO]fdp.exe` read as `invoiceexe.pdf`, a zero-width space, a full-width solidus that folds to `/`, `CON`, `NUL.tar.gz`, `file.txt:Zone.Identifier`, `name.txt.` and `name.txt `, 300 characters, the same name typed decomposed. Expected: a path, a control or an invisible character is refused; platform differences are rewritten; what is kept is NFC, at most 200 bytes, and can be created on both systems. Tests: Task 4, every row of `filename-cases.json` and the 6000-name fuzz.
2. **A paired peer that misbehaves** (a bug or a stolen key): a second offer while one waits, a size over 4 GiB, a chunk sent twice, a chunk skipped, a chunk that runs past the offer, `done` one byte early, a chunk before the user clicked Accept, frames for another transfer id, a malformed frame (a name that is not UTF-8, a type with a control character, a length that lies). Expected: declined as busy or too large, or the connection closed, and nothing saved as complete. Tests: Task 5 `rejects[]` and the 8000-frame fuzz, Task 6 `receiver[]`, `trips[]` and the 3000-script fuzz.
3. **A damaged, replayed, lost, cut or forged Noise message:** a flipped bit anywhere (the commitment in the first message included), a message one byte short, the same transport message twice, a message that never arrives, a zero-point public key, another prologue, another static key for the peer. Expected: the conversation stops at the message the fixture names, a zero key is refused as a zero key, and a refused message does not move the counter. Tests: Task 2 `rejectCases[]`, the size-limit checks and the 24-session property test.
4. **A man in the middle at the pairing, and a misbehaving pairing peer:** a reveal that does not match the commitment (a wrong nonce, or the right nonce under another static key), a reveal before any commitment, the same commitment sent again, a second attempt within 30 seconds, a reveal or an answer after the 2 minutes, an answer that is not exactly "yes", one side saying yes and the other no, an attacker who chooses its own nonce and key for each side. Expected: each refusal has its own cause (`because`), nothing is stored unless both users said yes, and the attacker's codes on the two screens agree about once in a million. Tests: Task 3 (the code, the commitment, the clock edges, the spread and the aimed-nonce check) and Task 4 (every row of the two machines, the 400 simulated pairings and attacks, the 6000-script fuzz).
5. **Names that differ only below what the eye sees:** the same name composed and decomposed, `A.TXT` against `a.txt`, four-byte emoji against the byte limit, a long extension, a dot file, 9999 numbered copies. Expected: they collide when the volume would collide them, the number is the smallest free, the result stays under the limit, and 10000 collisions give up. Tests: Task 4 `uniqueCases[]` and the length rows.

---

## File Structure

| Path | Responsibility |
|---|---|
| `tests/fixtures/link/reference.py` | The contract's tie-breaker: the primitives (X25519, ChaCha20-Poly1305), the Noise handshakes and `noise_run`, `commit_of`, `pairing_code` and the clocks, `pair_responder_step` and `pair_initiator_step`, `sanitize_name` and `unique_name`, the records, the first record, the hello, the advert, the six frames, `receiver_step`, `sender_step`, `plan_chunks`, the replay of every fixture and seeded fuzzes. Grown a rule per task. |
| `tests/fixtures/link/build_cases.py` | Writes the five JSON files; `--check` fails on drift. Grown a builder per task. |
| `tests/fixtures/link/noise-vectors.json` | 4 vectors and 20 damaged-message cases (generated, about 12 KB). |
| `tests/fixtures/link/pairing-cases.json` | 5 commitments, 7 codes, 6 invalid inputs, the xx-link pairing, 29 clock rows, and the two machines: 33 responder rows, 18 initiator rows and 4 trips (generated, about 45 KB). |
| `tests/fixtures/link/filename-cases.json` | 107 name rows and 13 collision rows (generated, about 21 KB). |
| `tests/fixtures/link/frames.json` | 21 frames, 37 rejects, 3 limits, 17 hello, 16 advert, 11 first-record and 13 record rows (generated, about 23 KB). |
| `tests/fixtures/link/flow-cases.json` | 49 receiver, 15 sender, 7 trip and 7 chunk-plan rows (generated, about 28 KB). |
| `scripts/test-link-contract.sh` | Runs the reference and the no-drift check. CI runs it. |
| `design/prototype/cat-core.js`, `scripts/gen-cat-fixtures.mjs`, `tests/fixtures/cat/desktop-cases.json`, `tests/cat/desktop-offer.test.mjs` | The `transferOffer` flag, its generator rows, the regenerated fixture and its Node test (Task 7). |
| `docs/LINK-CONTRACT.md` | The document the app plans cite: the wire layout, the rules, the files, the decisions. |
| `docs/CAT-CONTRACT.md`, `.github/workflows/build.yml`, `CLAUDE.md`, `ARCHITECT.md`, `docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md` | A section and a row, one step, one bullet each, and the spec's G2-0 table. |

The "prove it bites" steps and the CryptoKit cross-check are one-offs and are never committed. **CI needs no other change:** the Windows tests workflow gets `tests/fixtures/link/**` in its path filter in the G2-tauri plan, which is the plan that adds a TypeScript or Rust replay.

**Order of tasks:**

1. The skeleton, the test script and the primitives (X25519, ChaCha20-Poly1305 against the RFC vectors)
2. Noise: the vectors and the damaged-message cases
3. The pairing code: the commitment, the nonces and the clocks
4. The pairing in order: the two machines (commit, nonce, reveal, confirm)
5. File names: the sanitizer and the collision rule
6. Wire shapes: records, first record, hello, advert and the six frames
7. Flow: what each side does with each frame
8. The `transferOffer` flag in `cat-core.js`
9. Docs, CI and the final checks

## Tasks and agents

CLAUDE.md: the lightest model that fits. Every task gives all its code and docs, so all nine are transcription: `nm-implementer-light` (Haiku 5.5, medium). Each task is then reviewed by `nm-reviewer` (Haiku 5.5, high). The whole branch gets `nm-reviewer-deep` (Sonnet 5.5, high; trigger 4: it includes the **security pass** the spec asks for on the Noise vectors, the frame parser, the file-name sanitizer and the pairing's commit-then-reveal step) after Task 9. If a step's expected output differs and the cause is not obvious, hand that task to `nm-implementer-deep` (trigger 2) and say so in the ledger.

| Task | Deliverable | Agent | Review |
|---|---|---|---|
| 1. Skeleton and primitives | `reference.py` (skeleton, primitives, RFC checks), `build_cases.py` (skeleton), `test-link-contract.sh` | `nm-implementer-light` | `nm-reviewer` |
| 2. Noise | the handshake code, `noise_run`, `noise-vectors.json` (4 vectors, 20 reject cases), the CryptoKit cross-check | `nm-implementer-light` | `nm-reviewer` |
| 3. Pairing code | `pairing-cases.json` (commitments, codes, clocks), `commit_of`, `pairing_code`, the three clock rules | `nm-implementer-light` | `nm-reviewer` |
| 4. Pairing machines | the initiator's and the responder's machines, their rows and trips in `pairing-cases.json`, the 400-pairing simulation and the 6000-script fuzz | `nm-implementer-light` | `nm-reviewer` |
| 5. File names | `filename-cases.json`, `sanitize_name`, `unique_name`, the 6000-name fuzz | `nm-implementer-light` | `nm-reviewer` |
| 6. Wire shapes | `frames.json`, the records, the first record, hello (with its nonce), advert and frames, the 8000-frame fuzz, the tie to the `xx-link` vector | `nm-implementer-light` | `nm-reviewer` |
| 7. Flow | `flow-cases.json`, `receiver_step`, `sender_step`, `plan_chunks`, the 3000-script fuzz | `nm-implementer-light` | `nm-reviewer` |
| 8. `transferOffer` | the flag, the generator rows, the regenerated `desktop-cases.json`, a Node test | `nm-implementer-light` | `nm-reviewer` |
| 9. Docs, CI, final checks | `LINK-CONTRACT.md`, the CI step, three pointers, the spec's table, every check | `nm-implementer-light` | `nm-reviewer` |
| After Task 9 | The whole branch: the rules against the spec, the security pass, what a port could read two ways | `nm-reviewer-deep` | n/a |

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review` and the security skills it needs).

## Execution

One worktree chat session runs the whole plan: branch `g2-0/link-contract`, model **Haiku 5.5 at medium effort** (CLAUDE.md: a plan whose tasks are given in full: contracts, fixtures, docs). It is not trigger 5: there is no platform API and no concurrency. Nothing is pushed. The plan puts crypto test data in the repository, so the deep review at the end is not optional.

**Before the session starts,** the plan file is committed to `notchmeow/rebrand` (a docs-only commit): the controller does this, with the owner's OK. **The base is `d6704bd` or later:** `git merge-base --is-ancestor d6704bd HEAD` must succeed. **G2-0 starts now, before G1-tauri** (the owner's decision of 2026-10-14; the spec had it after G1 ships): it touches none of G1's files, so the two can run side by side.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up (it carries the owner's advance approval of the brief in step 3):

   > Run `git switch -c g2-0/link-contract notchmeow/rebrand`, then `git merge-base --is-ancestor d6704bd HEAD` and `git ls-files docs/superpowers/plans/2026-10-14-g2-0-link-contract.md`: the first must succeed and the second must print the plan's path. If either fails, say so and stop. Read `CLAUDE.md`, `ARCHITECT.md`, `docs/superpowers/plans/2026-10-14-g2-0-link-contract.md` and `docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md`. Reply "ready" and stop. Do not start any task. The owner approves in advance the controller brief the main session will send as your next message.

2. **Model.** Once the owner starts the chip, the main session sets that session to Haiku 5.5 at medium effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message.

**Controller brief** (what the main session sends once the model is set):

> Run `docs/superpowers/plans/2026-10-14-g2-0-link-contract.md` with `superpowers:subagent-driven-development`, task by task, on branch `g2-0/link-contract`. Dispatch each task to the agent the plan's "Tasks and agents" table names (Haiku 5.5 first: `nm-implementer-light`, `nm-implementer`, `nm-reviewer`; Sonnet 5.5 only for a task Haiku failed twice, or the final whole-branch review, and then the CLAUDE.md trigger goes in the ledger), then to `nm-reviewer`; fix what the review finds before the next task. Rules for you and for every subagent (put the plan's SUBAGENT RULES block in every brief):
>
> - **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder, the second `g2-0/link-contract`. If either is wrong, stop and report. Commit with `git commit -F <file>`, with the trailer of the model that did the task. **Never push.** Commit once per task, in the task's commit step, with only the files that step names.
> - **Ledger.** Keep a manual ledger at `.superpowers/sdd/2026-10-14-g2-0-link-contract/progress.md`: one line per task with its agent, model, commit hash, test lines and review verdict, and any escalation with its trigger. The SDD skill's plugin scripts may be refused by the auto-mode permission check: if so, do not call them; write each task brief with the Write tool just before you dispatch it, and each review's diff with `git diff` to a file under the ledger folder.
> - **Briefs are task-sized.** A brief carries one task: its text, the Global Constraints, the SUBAGENT RULES and the files it names. Never hand a subagent the whole plan.
> - **Reviews** read `git diff notchmeow/rebrand...HEAD` (three dots), narrowed to the task's files.
> - **Every shell block passes `bash -n`** before it is run.
> - **No stop for the owner.** The owner answered the open questions on 2026-10-14 ("The owner's answers" at the end of this plan); Task 9 prints the rule table for the record. If a printed line differs from an answer, stop and report. A change to a rule is one edit in `reference.py` and `build_cases.py` and a regenerate; the Noise vectors (including the `xx-link` payloads) and the pairing codes are frozen literals that are regenerated from the reference and pasted again, and the CryptoKit cross-check is run again.
> - **Servers and processes.** None are needed. Never launch a NotchMeow app. Install and download nothing.
> - **Stop and report on any refusal** (a denied command, a permission prompt) and **on any `find` text that is not found exactly once:** do not look for a workaround.
> - **Ping the main session.** Call `ListAgents` first and use the main session's name (and the `[ref]` it shows, if it asks for one) as `to` in `SendMessage`. At the end of every task, at the end of the plan, and whenever you stop (a refusal, a failed check, a question), send your report with `SendMessage` as well as writing it in your own chat, so the main session can double-check the work before anything reaches the owner.
> - **When you are done, report:** the commits; the output of `bash scripts/test-link-contract.sh | tail -5`; the `# tests` line of `bash scripts/test-cat-contract.sh`; the output of `node scripts/check-fixtures-additive.mjs 1627851 | tail -1` and of `node scripts/check-fixtures-additive.mjs notchmeow/rebrand | tail -1`; the CryptoKit cross-check's four ticks (Task 2); and anything you could not settle.

## Interface for the app plans

What the Mac (G2-mac) and Windows/Linux (G2-tauri) plans consume. The names below are the rules' names in this contract; each app ports them natively (Swift: pure files with no AppKit, the Noise layer on CryptoKit; Rust: a module with no Tauri types on `snow`, so the cross-app test can run it as a small binary; TypeScript for anything the page needs) and replays `tests/fixtures/link/*.json`. `docs/LINK-CONTRACT.md` (Task 9) has the full text; this is the summary.

| Rule | Signature | Answer |
|---|---|---|
| Noise handshakes | `Handshake(pattern, initiator, prologue, s, rs?, e?)`, `write(payload)`, `read(msg)`, `finish()` | messages; the handshake hash and the two cipher states; `NoiseError` on any refusal |
| `noise_run(vector, mutation?)` | a vector of `noise-vectors.json` | `("ok", ciphertexts, hash)` or `("fail", index)` |
| `commit_of(nonce, static_pub)` | two 32-byte values | the 32-byte commitment |
| `pairing_code(nonce_i, nonce_r, static_i, static_r)` | four 32-byte values | the six digits as text, leading zeros kept |
| `pair_responder_step(state, event)`, `pair_initiator_step(state, event)` | a state dict and one event | `{state, send, notify, because}` |
| `pairing_attempt_allowed(last, now)`, `pairing_window_open(start, now)`, `offer_expired(offered, now)` | whole milliseconds | booleans |
| `sanitize_name(raw)` | any JSON value | `("ok", name)` or `("reject", "not-text" \| "invisible" \| "separator" \| "empty")` |
| `unique_name(name, taken)` | names already in the folder | the name to use, or `None` |
| `encode_record(payload)`, `split_records(buf)` | bytes | a record; the whole records and the rest |
| `encode_preamble`, `decode_preamble`, `encode_hello(device_id, nonce, name)`, `decode_hello`, `parse_txt` | bytes or a dict | the decoded dict or a `FrameError(code)` |
| `encode_frame(frame)`, `decode_frame(bytes)` | a dict with a `type`; bytes | bytes; a dict or a `FrameError(code)` |
| `receiver_step(state, event)`, `sender_step(state, event)` | a state dict and one event | `{state, send, notify, abort}` |
| `plan_chunks(size, chunk_size=32768)` | whole bytes | `[(offset, length)]` |

- **The constants** (`noiseMax`, `tag`, `chunkMax`, `chunkSize`, `rawNameMax`, `kindMax`, `deviceNameMax`, `sizeMax`, the type numbers and decline reasons, the code's digits and label, the clocks, the name limits) are in the fixtures; an app compares its own with them.
- **What an app adds to the rules:** the sockets and their timeouts; discovery; the Keychain and Credential Manager items; looking up the stored key of the peer named in the first record; the random ephemeral keys (the fixtures inject theirs); writing the file to `Downloads/NotchMeow/`, quarantine and mark-of-the-web; the cards; the monotonic clock; feeding `transferOffer` to the desktop cat.
- **Strings are UTF-8 bytes where a byte limit is named**, and a strict decoder must be used (Swift's `String(decoding:as:)` repairs bad bytes and is wrong here). Names are compared in NFC.
- **Not in this contract:** the cross-app test (it needs both apps), discovery, the Send menu, the Debug fake peer.

---

### Task 1: The skeleton, the test script and the primitives

**Files:**
- Create: `tests/fixtures/link/reference.py`, `tests/fixtures/link/build_cases.py`, `scripts/test-link-contract.sh`
- Create (outside the repository, never committed): `${TMPDIR:-/tmp}/g20-insert.py`, `${TMPDIR:-/tmp}/g20-mutate.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `reference.py` with three markers (`# @@RULES`, `# @@CHECKS`, `    # @@CALLS`) that later tasks fill, and the functions `x25519(k, u)`, `x25519_pub(priv)`, `aead_encrypt(key, nonce12, aad, plaintext)` and `aead_decrypt(key, nonce12, aad, boxed)` (raises `ValueError`), plus `load(name)` and `check(label, got, expected)`; `build_cases.py` with two markers (`# @@BUILDERS`, `    # @@FILES`); `scripts/test-link-contract.sh`; and two scratch helpers: `g20-insert.py FILE MARKER TEXTFILE` (puts the text just above the line that holds the marker) and `g20-mutate.py LIST.json` (runs the reference once per listed change and counts the failing checks).

The primitives are written out in the reference so that it needs no package. They are checked here against the published test vectors of RFC 7748 (X25519) and RFC 8439 (ChaCha20, Poly1305 and the AEAD), so everything built on them in the next tasks stands on checked ground.

- [ ] **Step 1: Create the scratch helpers, the skeleton, the builder skeleton and the test script**

```bash
mkdir -p tests/fixtures/link
cat > "${TMPDIR:-/tmp}/g20-insert.py" <<'EOF'
"""Scratch helper of the G2-0 plan (never committed): g20-insert.py FILE MARKER TEXTFILE puts TEXTFILE just above the one line that holds MARKER."""
import sys

path, marker, textfile = sys.argv[1:]
s = open(path, encoding="utf-8").read()
assert s.count(marker) == 1, (path, marker, s.count(marker))
open(path, "w", encoding="utf-8", newline="\n").write(s.replace(marker, open(textfile, encoding="utf-8").read() + marker))
EOF
cat > "${TMPDIR:-/tmp}/g20-mutate.py" <<'EOF'
"""Scratch helper of the G2-0 plan (never committed): g20-mutate.py LIST.json runs tests/fixtures/link/reference.py once for each [label, find, replace] in the
JSON list, with that one text replaced, and prints how many checks fail (and whether the run then stopped with an error, which also counts as caught). A change that fails no check and ends cleanly is a hole in the tests."""
import json, os, subprocess, sys

src = open("tests/fixtures/link/reference.py", encoding="utf-8").read()
src = src.replace("HERE = os.path.dirname(os.path.abspath(__file__))", "HERE = %r" % os.path.abspath("tests/fixtures/link"))
tmp = os.path.join(os.environ.get("TMPDIR", "/tmp"), "g20-mutant.py")
for label, find, repl in json.load(open(sys.argv[1], encoding="utf-8")):
    if src.count(find) != 1:
        print("NOT FOUND EXACTLY ONCE:", label, repr(find))
        sys.exit(1)
    open(tmp, "w", encoding="utf-8").write(src.replace(find, repl))
    run = subprocess.run([sys.executable, "-B", tmp], capture_output=True, text=True)
    print("%3d failing%s  %s" % (run.stdout.count("\u2717"), " and then an error" if "Traceback" in run.stderr else "", label))
EOF
cat > tests/fixtures/link/reference.py <<'EOF'
#!/usr/bin/env python3
"""Reference implementation of NotchMeow's link contract (sub-project G2).

The rules both apps must agree on when two machines pair and send each other files: the two Noise
handshakes (Noise_XX_25519_ChaChaPoly_SHA256 to pair, Noise_KK_25519_ChaChaPoly_SHA256 to transfer),
the pairing code, the frames, the receiver's and the sender's rules, and the file-name sanitizer.
Runs every fixture in tests/fixtures/link/ against them, then a few self-checks and seeded fuzzes.
Standard library only: the X25519, ChaCha20 and Poly1305 below are written out so that the reference
needs no package, and they are checked against the RFC 7748 and RFC 8439 test vectors. Exit status 1
if anything fails. Both apps implement the same rules natively; this file is the tie-breaker when they
disagree. It is a reference, not production code: it is not constant-time and no app may use it.
"""
import hashlib
import hmac
import json
import os
import random
import struct
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
FAILURES = 0


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


def check_primitives():
    print("primitives (RFC 7748 and RFC 8439 test vectors)")
    h = bytes.fromhex
    check("RFC 7748 5.2: X25519 of the first test vector",
          x25519(h("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4"),
                 h("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c")).hex(),
          "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552")
    alice = h("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
    bob = h("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
    check("RFC 7748 6.1: Alice's public key", x25519_pub(alice).hex(), "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")
    check("RFC 7748 6.1: Bob's public key", x25519_pub(bob).hex(), "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f")
    check("RFC 7748 6.1: the shared secret, both ways", (x25519(alice, x25519_pub(bob)) == x25519(bob, x25519_pub(alice)), x25519(alice, x25519_pub(bob)).hex()),
          (True, "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"))
    check("RFC 8439 2.3.2: a ChaCha20 block", chacha20_block(bytes(range(32)), 1, h("000000090000004a00000000")).hex()[:32], "10f1e7e4d13b5915500fdd1fa32071c4")
    check("RFC 8439 2.5.2: a Poly1305 tag",
          poly1305(h("85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b"), b"Cryptographic Forum Research Group").hex(),
          "a8061dc1305136c6c22b8baf0c0127a9")
    key, nonce, aad = bytes(range(0x80, 0xA0)), h("070000004041424344454647"), h("50515253c0c1c2c3c4c5c6c7")
    pt = b"Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
    boxed = aead_encrypt(key, nonce, aad, pt)
    check("RFC 8439 2.8.2: the AEAD's ciphertext starts and its tag ends as published", (boxed[:16].hex(), boxed[-16:].hex()),
          ("d31a8d34648e60db7b86afbc53ef7ec2", "1ae10b594f09e26a7e902ecbd0600691"))
    check("RFC 8439 2.8.2: it opens again, and a flipped bit does not", (aead_decrypt(key, nonce, aad, boxed) == pt, _opens(key, nonce, aad, boxed[:5] + bytes([boxed[5] ^ 1]) + boxed[6:])),
          (True, False))


def _opens(key, nonce, aad, boxed):
    try:
        aead_decrypt(key, nonce, aad, boxed)
        return True
    except ValueError:
        return False


# @@CHECKS


def main():
    check_primitives()
    # @@CALLS
    print(f"\n{'FAILED: ' + str(FAILURES) if FAILURES else 'all link contract checks passed'}")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
EOF
cat > tests/fixtures/link/build_cases.py <<'EOF'
#!/usr/bin/env python3
"""Writes the JSON fixtures of the link contract (standard library only).

The expected answers are written out here by hand (or, for the Noise vectors and the pairing codes,
pasted once from the reference and then frozen) and never computed by reference.py, so the fixtures and
the reference check each other. Run it after an intended change to a rule:
    python3 tests/fixtures/link/build_cases.py          # rewrite the fixtures
    python3 tests/fixtures/link/build_cases.py --check  # exit 1 if they drifted from this script
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MISSING = object()  # a key that is absent from the JSON; None is written as null


# @@BUILDERS


def render(obj, pretty):
    """Lists one case per line (easy to read and to diff); pretty: the whole file indented, for the Noise vectors. Non-ASCII is escaped, so an invisible character shows as an escape."""
    if pretty:
        return json.dumps(obj, indent=1) + "\n"
    out = []
    for k, v in obj.items():
        if isinstance(v, list):
            out.append('  "%s": [\n    %s\n  ]' % (k, ",\n    ".join(json.dumps(x) for x in v)))
        else:
            out.append('  "%s": %s' % (k, json.dumps(v)))
    return "{\n" + ",\n".join(out) + "\n}\n"


FILES = {  # file name: (builder, pretty)
    # @@FILES
}


def main():
    check = "--check" in sys.argv
    bad = 0
    for name, (build, pretty) in FILES.items():
        text = render(build(), pretty)
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
cat > scripts/test-link-contract.sh <<'EOF'
#!/usr/bin/env bash
# Runs the link contract (sub-project G2): the fixtures in tests/fixtures/link/ against the Python reference,
# and a no-drift check of the JSON files against the script that writes them.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B tests/fixtures/link/reference.py
python3 -B tests/fixtures/link/build_cases.py --check
EOF
bash -n scripts/test-link-contract.sh && echo "script syntax ok"
```

- [ ] **Step 2: Run it to see it fail**

```bash
python3 -B tests/fixtures/link/reference.py 2>&1 | tail -3
```

Expected: a Python traceback ending `NameError: name 'x25519' is not defined` (the checks exist and the primitives do not yet).

- [ ] **Step 3: Add the primitives**

```bash
cat > "${TMPDIR:-/tmp}/g20-t1-prims.py" <<'EOF'
# ---- the primitives (RFC 7748 X25519, RFC 8439 ChaCha20-Poly1305) ----------------------------------
P25519 = 2**255 - 19
M32 = 0xFFFFFFFF
BASE_POINT = bytes([9]) + bytes(31)


def x25519(k, u):
    """X25519(k, u) of RFC 7748: the 32-byte shared value of private key k and public key u."""
    kl = bytearray(k)
    kl[0] &= 248
    kl[31] &= 127
    kl[31] |= 64
    kn = int.from_bytes(kl, "little")
    x1 = int.from_bytes(u, "little") & ((1 << 255) - 1)
    x2, z2, x3, z3, swap = 1, 0, x1, 1, 0
    for t in range(254, -1, -1):
        kt = (kn >> t) & 1
        swap ^= kt
        if swap:
            x2, x3, z2, z3 = x3, x2, z3, z2
        swap = kt
        a = (x2 + z2) % P25519
        aa = a * a % P25519
        b = (x2 - z2) % P25519
        bb = b * b % P25519
        e = (aa - bb) % P25519
        c = (x3 + z3) % P25519
        d = (x3 - z3) % P25519
        da = d * a % P25519
        cb = c * b % P25519
        x3 = (da + cb) ** 2 % P25519
        z3 = x1 * (da - cb) ** 2 % P25519
        x2 = aa * bb % P25519
        z2 = e * (aa + 121665 * e) % P25519
    if swap:
        x2, x3, z2, z3 = x3, x2, z3, z2
    return (x2 * pow(z2, P25519 - 2, P25519) % P25519).to_bytes(32, "little")


def x25519_pub(priv):
    return x25519(priv, BASE_POINT)


def _quarter(s, a, b, c, d):
    s[a] = (s[a] + s[b]) & M32
    s[d] ^= s[a]
    s[d] = ((s[d] << 16) | (s[d] >> 16)) & M32
    s[c] = (s[c] + s[d]) & M32
    s[b] ^= s[c]
    s[b] = ((s[b] << 12) | (s[b] >> 20)) & M32
    s[a] = (s[a] + s[b]) & M32
    s[d] ^= s[a]
    s[d] = ((s[d] << 8) | (s[d] >> 24)) & M32
    s[c] = (s[c] + s[d]) & M32
    s[b] ^= s[c]
    s[b] = ((s[b] << 7) | (s[b] >> 25)) & M32


def chacha20_block(key, counter, nonce):
    st = [0x61707865, 0x3320646E, 0x79622D32, 0x6B206574] + list(struct.unpack("<8I", key)) + [counter] + list(struct.unpack("<3I", nonce))
    w = st[:]
    for _ in range(10):
        _quarter(w, 0, 4, 8, 12)
        _quarter(w, 1, 5, 9, 13)
        _quarter(w, 2, 6, 10, 14)
        _quarter(w, 3, 7, 11, 15)
        _quarter(w, 0, 5, 10, 15)
        _quarter(w, 1, 6, 11, 12)
        _quarter(w, 2, 7, 8, 13)
        _quarter(w, 3, 4, 9, 14)
    return struct.pack("<16I", *[(w[i] + st[i]) & M32 for i in range(16)])


def chacha20_xor(key, counter, nonce, data):
    out = bytearray()
    for i in range(0, len(data), 64):
        ks = chacha20_block(key, counter + i // 64, nonce)
        out += bytes(a ^ b for a, b in zip(data[i:i + 64], ks))
    return bytes(out)


def poly1305(key, msg):
    r = int.from_bytes(key[:16], "little") & 0x0FFFFFFC0FFFFFFC0FFFFFFC0FFFFFFF
    s = int.from_bytes(key[16:], "little")
    acc, p = 0, (1 << 130) - 5
    for i in range(0, len(msg), 16):
        acc = (acc + int.from_bytes(msg[i:i + 16] + b"\x01", "little")) * r % p
    return ((acc + s) & ((1 << 128) - 1)).to_bytes(16, "little")


def _pad16(b):
    return bytes(-len(b) % 16)


def _aead_mac(key, nonce, aad, ct):
    otk = chacha20_block(key, 0, nonce)[:32]
    return poly1305(otk, aad + _pad16(aad) + ct + _pad16(ct) + struct.pack("<QQ", len(aad), len(ct)))


def aead_encrypt(key, nonce, aad, pt):
    """ChaCha20-Poly1305 (RFC 8439): ciphertext followed by the 16-byte tag."""
    ct = chacha20_xor(key, 1, nonce, pt)
    return ct + _aead_mac(key, nonce, aad, ct)


def aead_decrypt(key, nonce, aad, boxed):
    if len(boxed) < 16:
        raise ValueError("short")
    ct, tag = boxed[:-16], boxed[-16:]
    if not hmac.compare_digest(_aead_mac(key, nonce, aad, ct), tag):
        raise ValueError("tag")
    return chacha20_xor(key, 1, nonce, ct)
EOF
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "# @@RULES" "${TMPDIR:-/tmp}/g20-t1-prims.py"
```

- [ ] **Step 4: Run it to see it pass**

```bash
bash scripts/test-link-contract.sh
```

Expected: `primitives (RFC 7748 and RFC 8439 test vectors)`, eight lines starting with a tick (the first X25519 vector, both public keys and the shared secret, the ChaCha20 block, the Poly1305 tag, the AEAD's published ciphertext start and tag, and that it opens and refuses a flipped bit), and `all link contract checks passed`. The second command in the script prints nothing: no JSON file is written yet.

- [ ] **Step 5: Prove it bites (a one-off, never committed)**

```bash
cat > "${TMPDIR:-/tmp}/g20-m1.json" <<'EOF'
[
 ["ChaCha20 rotates by 15 where it should rotate by 16", "s[d] = ((s[d] << 16) | (s[d] >> 16)) & M32", "s[d] = ((s[d] << 15) | (s[d] >> 17)) & M32"],
 ["Poly1305 does not clamp r", "& 0x0FFFFFFC0FFFFFFC0FFFFFFC0FFFFFFF", "& 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"],
 ["X25519 uses 121666 for 121665", "z2 = e * (aa + 121665 * e) % P25519", "z2 = e * (aa + 121666 * e) % P25519"],
 ["the AEAD does not look at its tag", "if not hmac.compare_digest(_aead_mac(key, nonce, aad, ct), tag):", "if False:"]
]
EOF
python3 -B "${TMPDIR:-/tmp}/g20-mutate.py" "${TMPDIR:-/tmp}/g20-m1.json"
```

Expected: every change fails at least one check or ends in an error, and the numbers are these:

```text
  2 failing  ChaCha20 rotates by 15 where it should rotate by 16
  2 failing  Poly1305 does not clamp r
  4 failing  X25519 uses 121666 for 121665
  1 failing  the AEAD does not look at its tag
```


- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add tests/fixtures/link/reference.py tests/fixtures/link/build_cases.py scripts/test-link-contract.sh
cat > "${TMPDIR:-/tmp}/g20-msg1.txt" <<'EOF'
test(link): the link contract's skeleton, test script and RFC-checked primitives (G2-0)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -q -F "${TMPDIR:-/tmp}/g20-msg1.txt" && git log --oneline -2 && git show --stat --format= HEAD
```

Expected: three files listed.

---

### Task 2: Noise: the vectors and the damaged-message cases

**Files:**
- Modify: `tests/fixtures/link/build_cases.py` (a builder and its `FILES` entry), `tests/fixtures/link/reference.py` (the rules, the replay and its call)
- Create: `tests/fixtures/link/noise-vectors.json` (written by the builder)
- Create (outside the repository, never committed): `${TMPDIR:-/tmp}/g20-xcheck.swift`

**Interfaces:**
- Consumes: Task 1's `x25519`, `x25519_pub`, `aead_encrypt`, `aead_decrypt`, `load`, `check` and the markers.
- Produces: `PROTOCOL_VERSION` (1), `PROLOGUE` (`b"notchmeow-link/1"`), `NOISE_MAX` (65535), `TAG` (16), `NoiseError`, `hkdf2(ck, ikm)`, `CipherState` (`encrypt(ad, pt)`, `decrypt(ad, ct)`, `.k`, `.n`), `Symmetric`, `PATTERNS` (`"XX"`, `"KK"`), `protocol_name(pattern)`, `Handshake(pattern, initiator, prologue, s, rs=None, e=None)` with `write(payload=b"")`, `read(msg)`, `my_turn()`, `done()`, `finish()` giving `(handshake_hash, (send_cipher, receive_cipher))`, and `noise_run(vector, mutation=None)` giving `("ok", ciphertexts_hex, hash_hex)` or `("fail", message_index)`; the fixture `noise-vectors.json` with `version`, `note`, `prologue`, `vectors[]` (`id`, `name`, `source`, `protocol_name`, `init_prologue`, `init_static`, `init_ephemeral`, `init_remote_static` (KK only), `resp_prologue`, `resp_static`, `resp_ephemeral`, `resp_remote_static` (KK only), `handshake_hash`, `messages[]` of `{payload, ciphertext}`) and `rejectCases[]` (`name`, `vector`, `kind`, the kind's own fields, `failsAt`, and `because` for the two zero-point cases).

**The patterns** (Noise revision 34; `->` is initiator to responder):

```text
XX (pairing):   -> e          <- e, ee, s, es          -> s, se
KK (transfer):  -> s  <- s (both known before the first message)   then   -> e, es, ss      <- e, ee, se
```

A message is its tokens' bytes and then the payload. Messages alternate, the initiator first, and so do the transport messages after the handshake. The vectors' keys are plain byte patterns (`0x11` repeated and so on): test keys, never real ones. **Where the vectors come from:** the spec asks for the published vectors, and the drafting of this plan had no network, so the vectors are generated by the reference (written from the Noise specification, with the primitives checked against the RFCs), frozen into `build_cases.py`, in the format of the published cacophony and `snow` vectors, and cross-checked in step 5 with a second implementation written on CryptoKit. The published vectors can be added later as more entries of `vectors` (`source`: `published`) without changing any code (the owner's answer 1). The `xx-link` vector carries a real pairing: its first message holds the initiator's commitment, its second and third the two hellos with the nonces (layout in Task 6), so that Task 6 can tie the vector to the pairing code.

- [ ] **Step 1: Add the vectors and the damaged-message cases to the builder, and write the fixture**

```bash
cat > "${TMPDIR:-/tmp}/g20-t2-build.py" <<'EOF'
def noise_vectors():
    """The Noise vectors: pasted once from the reference (with keys that are plain byte patterns), cross-checked with CryptoKit, and frozen here."""
    vectors = [
            {
                "id": "xx-link",
                "name": "XX with the link prologue, a commitment, two hellos with their nonces and four transport messages",
                "source": "generated",
                "protocol_name": "Noise_XX_25519_ChaChaPoly_SHA256",
                "init_prologue": "6e6f7463686d656f772d6c696e6b2f31",
                "init_static": "1111111111111111111111111111111111111111111111111111111111111111",
                "init_ephemeral": "2222222222222222222222222222222222222222222222222222222222222222",
                "resp_prologue": "6e6f7463686d656f772d6c696e6b2f31",
                "resp_static": "3333333333333333333333333333333333333333333333333333333333333333",
                "resp_ephemeral": "4444444444444444444444444444444444444444444444444444444444444444",
                "handshake_hash": "341c19cef1caadcb78d7583edb441fc368bdd9898be3882c1947cd792261a0b8",
                "messages": [
                    {
                        "payload": "2d9a045c7dff54d2f01937d89c0368f3cf4405c05aa95509487d1d85291222a0",
                        "ciphertext": "0faa684ed28867b97f4a6a2dee5df8ce974e76b7018e3f22a1c4cf2678570f202d9a045c7dff54d2f01937d89c0368f3cf4405c05aa95509487d1d85291222a0"
                    },
                    {
                        "payload": "01b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b10a53747564696f204d6163",
                        "ciphertext": "ff2ee45601ec1b67310c7790404585ae697331eee1c1f8cf2419731c1fff3e6b5cda1c2d8029877d73fad62823946ccd0c5da35c129100f43d33a59cf19ea8fc1239fa0de91ca151cc1c1091a1d97365fc2080a06e24a0646a518d620aad6f50cdd1fefbcd0924be407ba42981a6083981cbd98f806ece9d90907bd064b526da14544a0dcc01b88d26b4280c1e91ff8c35fbd340ef8744b14f87a5ed"
                    },
                    {
                        "payload": "01a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1164c6f72656e7ae2809973204d6163426f6f6b20416972",
                        "ciphertext": "f4e4988e97bdcbf0f799d02dd2242624bda72d200e97e322c4f723213896a31e510abc5f30bd406f89f329311de93daefaacf16ffc2f8cac359b5d6e09c3da268f47bf8ab9f19e6e1c04332f75a84856897cdb761f431c14078167debf397674d5a04f2f327c1a6456292e1974edc8d4a16695ce2794f3ccb6680870650ff62d19b5e310212defbd"
                    },
                    {
                        "payload": "",
                        "ciphertext": "7d22cd25844b12db5ad4038aa7bbaaea"
                    },
                    {
                        "payload": "6e6f7463686d656f77",
                        "ciphertext": "4929ccc3e916b4f8335ae4053d9f642f970460babf2d7c2f4a"
                    },
                    {
                        "payload": "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f60616263",
                        "ciphertext": "0c31f02a30ca78d907f0921309ccc813e7c34d24eaa55c3fcfe00b0e0d6282f17a334e59f71c60218425fdd575550f3b45593160f265d701f552a5571cfa8d52df431801f0dc1ce69f20bf843a9fb18c8b6e5679b11072a44cc43042a84d0452e98f1c311dff26600930797e5a49d2d9cdc8abc6"
                    },
                    {
                        "payload": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
                        "ciphertext": "743ae703840f50025e3f74db5722cd3fc6b010463d8e1a2d13a5bc0dbdbdd42654bb3c5e065710d0a7751671b5ed309aec"
                    }
                ]
            },
            {
                "id": "xx-empty",
                "name": "XX with an empty prologue and empty payloads",
                "source": "generated",
                "protocol_name": "Noise_XX_25519_ChaChaPoly_SHA256",
                "init_prologue": "",
                "init_static": "0101010101010101010101010101010101010101010101010101010101010101",
                "init_ephemeral": "0202020202020202020202020202020202020202020202020202020202020202",
                "resp_prologue": "",
                "resp_static": "0303030303030303030303030303030303030303030303030303030303030303",
                "resp_ephemeral": "0404040404040404040404040404040404040404040404040404040404040404",
                "handshake_hash": "21acd1864c5e1ad3a31a5878ece019767878774200e5cadca6199731b2cf009b",
                "messages": [
                    {
                        "payload": "",
                        "ciphertext": "ce8d3ad1ccb633ec7b70c17814a5c76ecd029685050d344745ba05870e587d59"
                    },
                    {
                        "payload": "",
                        "ciphertext": "ac01b2209e86354fb853237b5de0f4fab13c7fcbf433a61c019369617fecf10bb719b14d19eaf5ca91c89748c5ce8668e6864f05ee2367682b3e0c2fd086f0b4f64162733f3fe548251c518fe8c03cce5fc0bcf3f8dea9b003f930ab273300e0"
                    },
                    {
                        "payload": "",
                        "ciphertext": "539a5cf3ae8a0a9134b32bfa775a1522db3558a1351ed4101989b8b88aa6a6f020da6d184283343a1d38fad23b3af58bc614f9b447f9aeb2a583c37b06bc4265"
                    },
                    {
                        "payload": "",
                        "ciphertext": "dee08d4fdeb182971f361ce87d782231"
                    },
                    {
                        "payload": "",
                        "ciphertext": "53231e10e978b5f74fb13e6b407c7c55"
                    },
                    {
                        "payload": "78",
                        "ciphertext": "a45b0c2d950faf9d96554a945645c3a566"
                    },
                    {
                        "payload": "",
                        "ciphertext": "a522f2484848db3857d90226afa01077"
                    }
                ]
            },
            {
                "id": "kk-link",
                "name": "KK with the link prologue and five transport messages",
                "source": "generated",
                "protocol_name": "Noise_KK_25519_ChaChaPoly_SHA256",
                "init_prologue": "6e6f7463686d656f772d6c696e6b2f31",
                "init_static": "5555555555555555555555555555555555555555555555555555555555555555",
                "init_ephemeral": "6666666666666666666666666666666666666666666666666666666666666666",
                "init_remote_static": "1cf579aba45a10ba1d1ef06d91fca2aa9ed0a1150515653155405d0b18cb9a67",
                "resp_prologue": "6e6f7463686d656f772d6c696e6b2f31",
                "resp_static": "7777777777777777777777777777777777777777777777777777777777777777",
                "resp_ephemeral": "8888888888888888888888888888888888888888888888888888888888888888",
                "resp_remote_static": "38ab664bd86f77d7e66bdd9ae0792913a94fd8b33a1260027e4b46c1f4884c67",
                "handshake_hash": "e0a44e29f4dbbcb45ec7d43bb61df80a99866163a508c623677aa0a832e77637",
                "messages": [
                    {
                        "payload": "",
                        "ciphertext": "219e4d800da968d2a5fcb009c784f4746c7138edb9ee4844b739e830b05cf424f644bdd9ac7fdc94322a0e4cc55ec904"
                    },
                    {
                        "payload": "",
                        "ciphertext": "30d3c865a48fceb3d6118577cf2e5f228d6ff69866264757785b253cb7a4806ab81c01883b4690bb8a5bcc39ab680394"
                    },
                    {
                        "payload": "6f66666572",
                        "ciphertext": "f4e9efe22fbfd63b48aa20d57058608e7b2500cd9d"
                    },
                    {
                        "payload": "616363657074",
                        "ciphertext": "71cdeb478c8a786f907d47e080f87150592cb7c96fdc"
                    },
                    {
                        "payload": "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7",
                        "ciphertext": "afb896d42c92a6042ec5962365edaebff963073551d898cd0ed1908c3eb8502091de4294df4ef31bbb3d48b4e4de78acef481e4e1f39943de24427decea114aede0eaa5bff917ac5e1611880581159abfe0915efe7297d8780f5eb944552831acb401a922493688b610a7733cc8ecd5ee340457709719e0b4d31d43c74fdbee18bdfcc6cd3769ace1e1453e2d028d76de1496800d5919dbe821bd48aa4a6536f1e6b6ca363a59cd7f03d0bfa18204d40e6444bd0b94e7cf1840d2c249d228deb87d74b10d20a3d9164e60e6aab6d7a58a4da68c65d3d90f5"
                    },
                    {
                        "payload": "",
                        "ciphertext": "4cdc64f814c85b9e976298155fb754ca"
                    },
                    {
                        "payload": "646f6e65",
                        "ciphertext": "a9b7b87c3fa791f62c9914d5380cdc3750d07c93"
                    }
                ]
            },
            {
                "id": "kk-empty",
                "name": "KK with an empty prologue and empty payloads",
                "source": "generated",
                "protocol_name": "Noise_KK_25519_ChaChaPoly_SHA256",
                "init_prologue": "",
                "init_static": "0505050505050505050505050505050505050505050505050505050505050505",
                "init_ephemeral": "0606060606060606060606060606060606060606060606060606060606060606",
                "init_remote_static": "13be4feaeaf204c7fd3358fc9c00721881d174278128227ec674f37f7fe97b6d",
                "resp_prologue": "",
                "resp_static": "0707070707070707070707070707070707070707070707070707070707070707",
                "resp_ephemeral": "0808080808080808080808080808080808080808080808080808080808080808",
                "resp_remote_static": "50a61409b1ddd0325e9b16b700e719e9772c07000b1bd7786e907c653d20495d",
                "handshake_hash": "cd0cb6c55bc49047e3ac8dc35653f2631aaf7cd2bcb66094c5489ce529893be1",
                "messages": [
                    {
                        "payload": "",
                        "ciphertext": "f5b2d6e60f9477e310c2982daaa6c9136c108a1777c5947e448fa37d68174557710cd6754ad99ee323ac1a1408d8a293"
                    },
                    {
                        "payload": "",
                        "ciphertext": "31d4ab6aceec961137917037936e60716fac573afe94d9da84a8020448dfc1124b3eca92daf7135fa8aa45696abd4318"
                    },
                    {
                        "payload": "",
                        "ciphertext": "1bfa39ea261f6dd93180b68ec07492b3"
                    },
                    {
                        "payload": "",
                        "ciphertext": "a873107e477aa47cd1b96409751d7240"
                    },
                    {
                        "payload": "79",
                        "ciphertext": "eff99e4efa192f4c45eb376602923fcff8"
                    }
                ]
            }
        ]
    reject = []

    def bad(name, vector, failsAt, kind, **more):
        reject.append({"name": name, "vector": vector, "kind": kind, **more, "failsAt": failsAt})

    # XX: message 0 is the initiator's ephemeral key, 1 the responder's reply with its static key, 2 the initiator's static key, 3 and on are transport messages.
    bad("xx: a flipped bit in the initiator's ephemeral key spoils the reply, which the initiator then cannot open", "xx-link", 1, "flip", message=0, offset=0)
    bad("xx: a flipped bit in the commitment, the payload of the first message, spoils the reply", "xx-link", 1, "flip", message=0, offset=40)
    bad("xx: a flipped bit in the responder's encrypted static key", "xx-link", 1, "flip", message=1, offset=40)
    bad("xx: a flipped bit in the last byte of the reply, which is its tag", "xx-link", 1, "flip", message=1, offset=155)
    bad("xx: a flipped bit in the initiator's encrypted static key", "xx-link", 2, "flip", message=2, offset=0)
    bad("xx: the reply one byte short", "xx-link", 1, "truncate", message=1, by=1)
    bad("xx: the first message cut to 31 bytes, too short to hold a key", "xx-link", 0, "truncate", message=0, by=33)
    bad("xx: a flipped bit in the first transport message", "xx-link", 3, "flip", message=3, offset=0)
    bad("xx: the first transport message delivered twice", "xx-link", 3, "replay", message=3)
    bad("xx: a transport message arrives without the one before it", "xx-link", 5, "skip", message=5)
    bad("xx: an ephemeral key that is the zero point (a low-order point)", "xx-link", 1, "low-order", message=0, because="low-order point")
    bad("xx: the initiator has another prologue (another protocol version)", "xx-link", 1, "prologue", prologue=b"notchmeow-link/2".hex())
    # KK: message 0 is the initiator's ephemeral key, 1 the reply, 2 and on are transport messages.
    bad("kk: a flipped bit in the initiator's ephemeral key", "kk-link", 0, "flip", message=0, offset=0)
    bad("kk: a flipped bit in the last byte of the reply", "kk-link", 1, "flip", message=1, offset=47)
    bad("kk: the responder holds another key for the initiator", "kk-link", 0, "static", respRemoteStatic=bytes([9] * 32).hex())
    bad("kk: the first transport message delivered twice", "kk-link", 2, "replay", message=2)
    bad("kk: a transport message arrives without the one before it", "kk-link", 4, "skip", message=4)
    bad("kk: an ephemeral key that is the zero point", "kk-link", 0, "low-order", message=0, because="low-order point")
    bad("kk: the initiator has another prologue", "kk-link", 0, "prologue", prologue=b"notchmeow-link/2".hex())
    bad("kk: a flipped bit in a transport message", "kk-link", 3, "flip", message=3, offset=5)
    note = ("Noise_XX_25519_ChaChaPoly_SHA256 pairs two machines and Noise_KK_25519_ChaChaPoly_SHA256 carries a transfer. Each vector is in the format of the published "
            "cacophony / snow vectors: the keys, the messages alternate initiator first (transport messages too), and handshake_hash is the hash after the last handshake message. "
            "source says where a vector came from. rejectCases damage what is delivered: see noise_run in reference.py for the kinds. failsAt is the index of the message at which a side must refuse. because (the zero-point cases only) is the reference's own reason: a port checks that the zero key is refused as such.")
    return {"version": 1, "note": note, "prologue": '6e6f7463686d656f772d6c696e6b2f31', "vectors": vectors, "rejectCases": reject}
EOF
cat > "${TMPDIR:-/tmp}/g20-t2-files.txt" <<'EOF'
    "noise-vectors.json": (noise_vectors, True),
EOF
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/build_cases.py "# @@BUILDERS" "${TMPDIR:-/tmp}/g20-t2-build.py"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/build_cases.py "    # @@FILES" "${TMPDIR:-/tmp}/g20-t2-files.txt"
python3 -B tests/fixtures/link/build_cases.py
```

Expected: `wrote noise-vectors.json (12735 bytes)`.

- [ ] **Step 2: Add the replay, and run it to see it fail**

```bash
cat > "${TMPDIR:-/tmp}/g20-t2-checks.py" <<'EOF'
def _refused(fn, *args):
    try:
        fn(*args)
        return False
    except NoiseError:
        return True


def check_noise():
    print("noise-vectors.json")
    f = load("noise-vectors.json")
    check("the prologue is the one the rules name", f["prologue"], PROLOGUE.hex())
    vectors = {v["id"]: v for v in f["vectors"]}
    check("four vectors: both patterns, the link prologue and an empty one", sorted(vectors), ["kk-empty", "kk-link", "xx-empty", "xx-link"])
    for v in f["vectors"]:
        got = noise_run(v)
        check(f"{v['id']}: every message is the one the vector gives, and the handshake hash too", got,
              ("ok", [m["ciphertext"] for m in v["messages"]], v["handshake_hash"]))
        if v["protocol_name"] == protocol_name("KK"):
            check(f"{v['id']}: the remote static keys it names are the ones the private keys make",
                  (v["init_remote_static"], v["resp_remote_static"]),
                  (x25519_pub(bytes.fromhex(v["resp_static"])).hex(), x25519_pub(bytes.fromhex(v["init_static"])).hex()))
    for c in f["rejectCases"]:
        mutation = {k: val for k, val in c.items() if k not in ("name", "vector", "failsAt", "because")}
        got = noise_run(vectors[c["vector"]], mutation)
        check(c["name"], got[:2], ("fail", c["failsAt"]))
        if "because" in c:                       # the zero point must be refused as such, not only because the two sides' keys then disagree
            check(c["name"] + ": refused as " + c["because"], got[2:], (c["because"],))
    # The size limit: 65535 bytes in a Noise message, 65519 of data in a transport message; a refused message does not move the counter.
    a = Handshake("KK", True, PROLOGUE, bytes([1]) * 32, rs=x25519_pub(bytes([2]) * 32))
    b = Handshake("KK", False, PROLOGUE, bytes([2]) * 32, rs=x25519_pub(bytes([1]) * 32))
    b.read(a.write())
    a.read(b.write())
    (_, (a_send, _a_recv)), (_, (_b_send, b_recv)) = a.finish(), b.finish()
    big = a_send.encrypt(b"", bytes(NOISE_MAX - TAG))
    check("a transport message of 65535 bytes (65519 of data and the tag) opens", (len(big), len(b_recv.decrypt(b"", big))), (NOISE_MAX, NOISE_MAX - TAG))
    nxt = a_send.encrypt(b"", b"next")
    hurt = bytes([nxt[0] ^ 1]) + nxt[1:]
    check("a damaged message is refused and the counter does not move, so the genuine next one still opens",
          (_refused(b_recv.decrypt, b"", hurt), b_recv.n, b_recv.decrypt(b"", nxt), b_recv.n), (True, 1, b"next", 2))
    start = Handshake("XX", True, b"", bytes([1]) * 32, e=bytes([2]) * 32)
    check("a handshake message of 65535 bytes is written, one of 65536 is refused",
          (len(start.write(bytes(NOISE_MAX - 32))), _refused(Handshake("XX", True, b"", bytes([1]) * 32, e=bytes([2]) * 32).write, bytes(NOISE_MAX - 31))), (NOISE_MAX, True))
    # A seeded property test: random keys, prologues and payloads, both patterns.
    rnd = random.Random(20261014)
    ok = True
    for n in range(24):
        pattern = ("XX", "KK")[n % 2]
        isk, rsk = rnd.randbytes(32), rnd.randbytes(32)
        pro = rnd.randbytes(rnd.randrange(0, 20))
        i = Handshake(pattern, True, pro, isk, rs=x25519_pub(rsk) if pattern == "KK" else None)
        r = Handshake(pattern, False, pro, rsk, rs=x25519_pub(isk) if pattern == "KK" else None)
        while not i.done():
            w, rd = (i, r) if i.my_turn() else (r, i)
            p = rnd.randbytes(rnd.randrange(0, 80))
            ok &= rd.read(w.write(p)) == p
        (hi, (i_send, i_recv)), (hr, (r_send, r_recv)) = i.finish(), r.finish()
        ok &= hi == hr and len(hi) == 32
        p = rnd.randbytes(rnd.randrange(1, 300))
        c = i_send.encrypt(b"", p)
        j = rnd.randrange(len(c))
        ok &= _refused(r_recv.decrypt, b"", c[:j] + bytes([c[j] ^ (1 << rnd.randrange(8))]) + c[j + 1:])
        ok &= r_recv.decrypt(b"", c) == p
        ok &= i_recv.decrypt(b"", r_send.encrypt(b"", p)) == p
    check("24 random sessions, both patterns: the hashes agree, both directions open, any damaged bit is refused", ok, True)
EOF
printf '    check_noise()\n' > "${TMPDIR:-/tmp}/g20-t2-calls.txt"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "# @@CHECKS" "${TMPDIR:-/tmp}/g20-t2-checks.py"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "    # @@CALLS" "${TMPDIR:-/tmp}/g20-t2-calls.txt"
python3 -B tests/fixtures/link/reference.py 2>&1 | tail -3
```

Expected: after the primitives' eight ticks, a traceback ending `NameError: name 'PROLOGUE' is not defined`.

- [ ] **Step 3: Add the Noise rules**

```bash
cat > "${TMPDIR:-/tmp}/g20-t2-rules.py" <<'EOF'
# ---- Noise (Task 2): the Noise Protocol Framework, revision 34, for exactly the two patterns the link uses ----------
PROTOCOL_VERSION = 1
PROLOGUE = b"notchmeow-link/1"          # bound into both handshakes, so a version mismatch fails them
NOISE_MAX = 65535                        # the most bytes of one Noise message, tag included
TAG = 16


class NoiseError(Exception):
    pass


def hkdf2(ck, ikm):
    temp = hmac.new(ck, ikm, hashlib.sha256).digest()
    out1 = hmac.new(temp, b"\x01", hashlib.sha256).digest()
    out2 = hmac.new(temp, out1 + b"\x02", hashlib.sha256).digest()
    return out1, out2


class CipherState:
    def __init__(self, k=None):
        self.k, self.n = k, 0

    def _nonce(self):
        return bytes(4) + self.n.to_bytes(8, "little")     # 32 zero bits, then the counter, little-endian

    def encrypt(self, ad, pt):
        if self.k is None:
            return pt
        if self.n >= 2**64 - 1:
            raise NoiseError("nonce exhausted")
        out = aead_encrypt(self.k, self._nonce(), ad, pt)
        self.n += 1
        return out

    def decrypt(self, ad, ct):
        if self.k is None:
            return ct
        if self.n >= 2**64 - 1:
            raise NoiseError("nonce exhausted")
        try:
            out = aead_decrypt(self.k, self._nonce(), ad, ct)
        except ValueError:
            raise NoiseError("decrypt")
        self.n += 1                                         # only after a good tag: a refused message does not move the counter
        return out


class Symmetric:
    def __init__(self, name):
        nb = name.encode("ascii")
        self.h = nb + bytes(32 - len(nb)) if len(nb) <= 32 else hashlib.sha256(nb).digest()
        self.ck, self.cs = self.h, CipherState()

    def mix_hash(self, data):
        self.h = hashlib.sha256(self.h + data).digest()

    def mix_key(self, ikm):
        self.ck, k = hkdf2(self.ck, ikm)
        self.cs = CipherState(k)

    def encrypt_and_hash(self, pt):
        ct = self.cs.encrypt(self.h, pt)
        self.mix_hash(ct)
        return ct

    def decrypt_and_hash(self, ct):
        pt = self.cs.decrypt(self.h, ct)
        self.mix_hash(ct)
        return pt

    def split(self):
        k1, k2 = hkdf2(self.ck, b"")
        return CipherState(k1), CipherState(k2)


# Tokens: e, s send a public key; ee, es, se, ss mix in a DH. In "es" the first letter is the initiator's key and the second the responder's.
PATTERNS = {
    "XX": {"pre": [], "msgs": [["e"], ["e", "ee", "s", "es"], ["s", "se"]]},
    "KK": {"pre": ["i", "r"], "msgs": [["e", "es", "ss"], ["e", "ee", "se"]]},
}


def protocol_name(pattern):
    return "Noise_%s_25519_ChaChaPoly_SHA256" % pattern


class Handshake:
    """One side of a handshake. `s` is the static private key, `rs` the remote static public key (KK needs it before the first message),
    `e` the ephemeral private key: the fixtures inject it, an app leaves it None and gets a random one."""

    def __init__(self, pattern, initiator, prologue, s, rs=None, e=None):
        self.pat, self.initiator, self.s, self.rs, self.e = PATTERNS[pattern], initiator, s, rs, e
        self.s_pub, self.re, self.i = x25519_pub(s), None, 0
        self.sym = Symmetric(protocol_name(pattern))
        self.sym.mix_hash(prologue)
        for who in self.pat["pre"]:                          # the pre-messages "-> s" then "<- s"
            mine = (who == "i") == initiator
            if not mine and rs is None:
                raise NoiseError("the pattern needs the remote static key")
            self.sym.mix_hash(self.s_pub if mine else rs)

    def my_turn(self):
        return self.i < len(self.pat["msgs"]) and (self.i % 2 == 0) == self.initiator

    def done(self):
        return self.i == len(self.pat["msgs"])

    def _dh(self, tok):
        mine, theirs = (tok[0], tok[1]) if self.initiator else (tok[1], tok[0])
        out = x25519(self.e if mine == "e" else self.s, self.re if theirs == "e" else self.rs)
        if out == bytes(32):                                  # a low-order point: refuse (RFC 7748 section 6.1)
            raise NoiseError("low-order point")
        self.sym.mix_key(out)

    def write(self, payload=b""):
        if not self.my_turn():
            raise NoiseError("not my turn")
        buf = b""
        for tok in self.pat["msgs"][self.i]:
            if tok == "e":
                if self.e is None:
                    self.e = os.urandom(32)
                buf += x25519_pub(self.e)
                self.sym.mix_hash(x25519_pub(self.e))
            elif tok == "s":
                buf += self.sym.encrypt_and_hash(self.s_pub)
            else:
                self._dh(tok)
        buf += self.sym.encrypt_and_hash(payload)
        if len(buf) > NOISE_MAX:
            raise NoiseError("message too long")
        self.i += 1
        return buf

    def read(self, msg):
        if self.done() or self.my_turn():
            raise NoiseError("not my turn")
        if len(msg) > NOISE_MAX:
            raise NoiseError("message too long")
        pos = 0
        for tok in self.pat["msgs"][self.i]:
            if tok == "e":
                if len(msg) - pos < 32:
                    raise NoiseError("short")
                self.re = msg[pos:pos + 32]
                pos += 32
                self.sym.mix_hash(self.re)
            elif tok == "s":
                n = 32 + (TAG if self.sym.cs.k is not None else 0)
                if len(msg) - pos < n:
                    raise NoiseError("short")
                self.rs = self.sym.decrypt_and_hash(msg[pos:pos + n])
                pos += n
            else:
                self._dh(tok)
        payload = self.sym.decrypt_and_hash(msg[pos:])
        self.i += 1
        return payload

    def finish(self):
        """After the last message: the handshake hash, and (send, receive) cipher states for this side."""
        if not self.done():
            raise NoiseError("not finished")
        c1, c2 = self.sym.split()
        return self.sym.h, ((c1, c2) if self.initiator else (c2, c1))


def noise_run(v, mutation=None):
    """Plays a fixture vector's whole conversation, both sides, in this process. Returns ("ok", ciphertexts as hex, handshake hash as hex)
    or ("fail", the index of the message at which a side refused, the reference's own reason). A mutation damages what is delivered, never what is sent:
    {"kind": "flip", "message": i, "offset": o}   one bit of byte o of message i
    {"kind": "truncate", "message": i, "by": n}   the last n bytes of message i
    {"kind": "low-order", "message": 0}           message 0's ephemeral key becomes 32 zero bytes
    {"kind": "replay", "message": i}              message i arrives twice
    {"kind": "skip", "message": i}                message i-2 (the sender's previous one) is lost, then message i arrives
    {"kind": "prologue", "prologue": hex}         the initiator was started with another prologue
    {"kind": "static", "respRemoteStatic": hex}   the responder holds another key for the initiator (KK)"""
    m = mutation or {}
    kind = m.get("kind")
    pattern = v["protocol_name"].split("_")[1]
    isk, rsk = bytes.fromhex(v["init_static"]), bytes.fromhex(v["resp_static"])
    kk = pattern == "KK"
    i = Handshake(pattern, True, bytes.fromhex(m["prologue"] if kind == "prologue" else v["init_prologue"]), isk,
                  rs=x25519_pub(rsk) if kk else None, e=bytes.fromhex(v["init_ephemeral"]))
    r = Handshake(pattern, False, bytes.fromhex(v["resp_prologue"]), rsk,
                  rs=(bytes.fromhex(m["respRemoteStatic"]) if kind == "static" else x25519_pub(isk)) if kk else None, e=bytes.fromhex(v["resp_ephemeral"]))
    nhs, sent, h = len(PATTERNS[pattern]["msgs"]), [], None
    i_send = i_recv = r_send = r_recv = None
    for n, msg in enumerate(v["messages"]):
        payload = bytes.fromhex(msg["payload"])
        to_resp = n % 2 == 0                                   # messages alternate, the initiator first, transport messages included
        try:
            if n < nhs:
                c = (i if to_resp else r).write(payload)
            else:
                c = (i_send if to_resp else r_send).encrypt(b"", payload)
        except NoiseError as e:
            return ("fail", n, str(e))
        sent.append(c.hex())
        delivered = [c]
        if m.get("message") == n:
            if kind == "flip":
                delivered = [c[:m["offset"]] + bytes([c[m["offset"]] ^ 1]) + c[m["offset"] + 1:]]
            elif kind == "truncate":
                delivered = [c[:len(c) - m["by"]]]
            elif kind == "low-order":
                delivered = [bytes(32) + c[32:]]
            elif kind == "replay":
                delivered = [c, c]
        if kind == "skip" and m["message"] - 2 == n:
            delivered = []                                     # sent, never arrived
        for d in delivered:
            try:
                got = (r if to_resp else i).read(d) if n < nhs else (r_recv if to_resp else i_recv).decrypt(b"", d)
            except NoiseError as e:
                return ("fail", n, str(e))
            if d == c and got != payload:                      # a damaged message may legitimately open to another payload (message 0 is not encrypted)
                return ("fail", n, "payload")
        if n == nhs - 1:
            (hi, (i_send, i_recv)), (hr, (r_send, r_recv)) = i.finish(), r.finish()
            if hi != hr:
                return ("fail", n, "hash")
            h = hi
    return ("ok", sent, h.hex())
EOF
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "# @@RULES" "${TMPDIR:-/tmp}/g20-t2-rules.py"
```

- [ ] **Step 4: Run it to see it pass**

```bash
bash scripts/test-link-contract.sh | grep -v "✓"
bash scripts/test-link-contract.sh | grep -c "✓"
```

Expected: the first command prints `primitives (RFC 7748 and RFC 8439 test vectors)`, `noise-vectors.json`, an empty line and `all link contract checks passed` (every line with a tick is filtered out); the second prints `43`. The four vectors replay message for message and the handshake hashes agree; the 19 damaged-message cases stop where `failsAt` says; a message of 65535 bytes opens; a refused message does not move the counter.

- [ ] **Step 5: Cross-check the vectors with an independent implementation (CryptoKit)**

The reference was written by one hand from the Noise specification, so a mistake it makes in reading the specification would be in the fixtures too. This scratch program re-derives every handshake and transport message of the four vectors with Apple's CryptoKit (X25519, ChaChaPoly, SHA-256 and HMAC from the system, the Noise state machine written again) and compares them to the fixture. It is never committed: G2-mac writes the real one.

```bash
cat > "${TMPDIR:-/tmp}/g20-xcheck.swift" <<'EOF'
import Foundation
import CryptoKit

func hex(_ s: String) -> Data { var d = Data(); var i = s.startIndex; while i < s.endIndex { let j = s.index(i, offsetBy: 2); d.append(UInt8(s[i..<j], radix: 16)!); i = j }; return d }
func hx(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
func hmac(_ k: Data, _ m: Data) -> Data { Data(HMAC<SHA256>.authenticationCode(for: m, using: SymmetricKey(data: k))) }
func hkdf(_ ck: Data, _ ikm: Data) -> (Data, Data) { let t = hmac(ck, ikm); let o1 = hmac(t, Data([1])); let o2 = hmac(t, o1 + Data([2])); return (o1, o2) }
struct CS { var k: Data?; var n: UInt64 = 0
  func nonce() -> ChaChaPoly.Nonce { var d = Data(count: 4); var n = self.n.littleEndian; d.append(Data(bytes: &n, count: 8)); return try! ChaChaPoly.Nonce(data: d) }
  mutating func enc(_ ad: Data, _ pt: Data) -> Data { guard let k = k else { return pt }; let b = try! ChaChaPoly.seal(pt, using: SymmetricKey(data: k), nonce: nonce(), authenticating: ad); n += 1; return b.ciphertext + b.tag }
  mutating func dec(_ ad: Data, _ ct: Data) -> Data { guard let k = k else { return ct }; let box = try! ChaChaPoly.SealedBox(nonce: nonce(), ciphertext: ct.dropLast(16), tag: ct.suffix(16)); n += 1; return try! ChaChaPoly.open(box, using: SymmetricKey(data: k), authenticating: ad) }
}
struct SS { var h: Data; var ck: Data; var cs = CS(k: nil)
  init(_ name: String) { var b = Data(name.utf8); if b.count <= 32 { b.append(Data(count: 32 - b.count)); h = b } else { h = Data(SHA256.hash(data: b)) }; ck = h }
  mutating func mixHash(_ d: Data) { h = Data(SHA256.hash(data: h + d)) }
  mutating func mixKey(_ d: Data) { let (a, b) = hkdf(ck, d); ck = a; cs = CS(k: b) }
  mutating func encHash(_ p: Data) -> Data { let c = cs.enc(h, p); mixHash(c); return c }
  mutating func decHash(_ c: Data) -> Data { let p = cs.dec(h, c); mixHash(c); return p }
}
func dh(_ priv: Data, _ pub: Data) -> Data { let k = try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: priv); let p = try! Curve25519.KeyAgreement.PublicKey(rawRepresentation: pub); return try! k.sharedSecretFromKeyAgreement(with: p).withUnsafeBytes { Data($0) } }
func pub(_ priv: Data) -> Data { try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: priv).publicKey.rawRepresentation }

struct HS {
  var ss: SS; let initiator: Bool; let s: Data; var rs: Data?; let e: Data; var re: Data?; let msgs: [[String]]
  init(pattern: String, initiator: Bool, prologue: Data, s: Data, rs: Data?, e: Data) {
    ss = SS("Noise_\(pattern)_25519_ChaChaPoly_SHA256"); self.initiator = initiator; self.s = s; self.rs = rs; self.e = e
    msgs = pattern == "XX" ? [["e"], ["e","ee","s","es"], ["s","se"]] : [["e","es","ss"], ["e","ee","se"]]
    ss.mixHash(prologue)
    if pattern == "KK" { let ip = initiator ? pub(s) : rs!; let rp = initiator ? rs! : pub(s); ss.mixHash(ip); ss.mixHash(rp) }
  }
  mutating func doDH(_ t: String) {
    let a = String(t.first!), b = String(t.last!)
    let (mine, theirs) = initiator ? (a, b) : (b, a)
    let priv = mine == "e" ? e : s; let p = theirs == "e" ? re! : rs!
    ss.mixKey(dh(priv, p))
  }
  mutating func write(_ i: Int, _ payload: Data) -> Data {
    var buf = Data()
    for t in msgs[i] { if t == "e" { buf += pub(e); ss.mixHash(pub(e)) } else if t == "s" { buf += ss.encHash(pub(s)) } else { doDH(t) } }
    return buf + ss.encHash(payload)
  }
  mutating func read(_ i: Int, _ m: Data) -> Data {
    var pos = 0
    for t in msgs[i] {
      if t == "e" { re = m.subdata(in: pos..<pos+32); pos += 32; ss.mixHash(re!) }
      else if t == "s" { let n = 32 + (ss.cs.k != nil ? 16 : 0); rs = ss.decHash(m.subdata(in: pos..<pos+n)); pos += n }
      else { doDH(t) }
    }
    return ss.decHash(m.subdata(in: pos..<m.count))
  }
}
let vectors = (try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any])["vectors"] as! [[String: Any]]
var bad = 0
for v in vectors {
  let name = v["name"] as! String
  let pattern = (v["protocol_name"] as! String).split(separator: "_")[1].description
  let pro = hex(v["init_prologue"] as! String)
  var i = HS(pattern: pattern, initiator: true, prologue: pro, s: hex(v["init_static"] as! String), rs: (v["init_remote_static"] as? String).map(hex), e: hex(v["init_ephemeral"] as! String))
  var r = HS(pattern: pattern, initiator: false, prologue: pro, s: hex(v["resp_static"] as! String), rs: (v["resp_remote_static"] as? String).map(hex), e: hex(v["resp_ephemeral"] as! String))
  let msgs = v["messages"] as! [[String: String]]
  let nhs = pattern == "XX" ? 3 : 2
  var ok = true
  for n in 0..<nhs {
    let pl = hex(msgs[n]["payload"]!), want = hex(msgs[n]["ciphertext"]!)
    let c = n % 2 == 0 ? i.write(n, pl) : r.write(n, pl)
    let back = n % 2 == 0 ? r.read(n, c) : i.read(n, c)
    if c != want || back != pl { ok = false; print("  mismatch at handshake message \(n)") }
  }
  if hx(i.ss.h) != v["handshake_hash"] as! String || i.ss.h != r.ss.h { ok = false; print("  handshake hash differs") }
  let (k1, k2) = hkdf(i.ss.ck, Data())
  var ci = CS(k: k1), cr = CS(k: k2)   // ci: initiator->responder, cr: responder->initiator
  for n in nhs..<msgs.count {
    let pl = hex(msgs[n]["payload"]!), want = hex(msgs[n]["ciphertext"]!)
    let c = (n % 2 == 0) ? ci.enc(Data(), pl) : cr.enc(Data(), pl)
    if c != want { ok = false; print("  mismatch at transport message \(n)") }
  }
  print(ok ? "✓" : "✗", name); if !ok { bad += 1 }
}
exit(bad == 0 ? 0 : 1)
EOF
swiftc -O "${TMPDIR:-/tmp}/g20-xcheck.swift" -o "${TMPDIR:-/tmp}/g20-xcheck" && "${TMPDIR:-/tmp}/g20-xcheck" tests/fixtures/link/noise-vectors.json
```

Expected: four lines, each starting with a tick, one per vector. **A cross (or a "mismatch" line) means the reference and CryptoKit disagree: stop and report, do not edit either side to make them agree.** If `swiftc` is not available, say so in the ledger and ask the main session to run this step on the Mac: it is the only independent check of the vectors until G2-tauri replays them with `snow`.

- [ ] **Step 6: Prove it bites (a one-off, never committed)**

```bash
cat > "${TMPDIR:-/tmp}/g20-m2.json" <<'EOF'
[
 ["the nonce counter is big-endian", "return bytes(4) + self.n.to_bytes(8, \"little\")", "return bytes(4) + self.n.to_bytes(8, \"big\")"],
 ["a zero DH output is accepted", "if out == bytes(32):", "if False:"],
 ["the protocol name is always hashed", "self.h = nb + bytes(32 - len(nb)) if len(nb) <= 32 else hashlib.sha256(nb).digest()", "self.h = hashlib.sha256(nb).digest()"],
 ["the prologue is not mixed in", "self.sym.mix_hash(prologue)", "pass"],
 ["HKDF's second output uses the wrong counter", "out2 = hmac.new(temp, out1 + b\"\\x02\", hashlib.sha256).digest()", "out2 = hmac.new(temp, out1 + b\"\\x03\", hashlib.sha256).digest()"],
 ["the KK pre-messages are mixed in the wrong order", "\"KK\": {\"pre\": [\"i\", \"r\"],", "\"KK\": {\"pre\": [\"r\", \"i\"],"],
 ["both sides use the same cipher state", "return self.sym.h, ((c1, c2) if self.initiator else (c2, c1))", "return self.sym.h, (c1, c2)"],
 ["the counter moves before the tag is checked", "        try:\n            out = aead_decrypt(self.k, self._nonce(), ad, ct)\n        except ValueError:\n            raise NoiseError(\"decrypt\")\n        self.n += 1", "        self.n += 1\n        try:\n            out = aead_decrypt(self.k, self._nonce(), ad, ct)\n        except ValueError:\n            raise NoiseError(\"decrypt\")"]
]
EOF
python3 -B "${TMPDIR:-/tmp}/g20-mutate.py" "${TMPDIR:-/tmp}/g20-m2.json"
```

Expected: every change fails at least one check or ends in an error, and the numbers are these:

```text
  4 failing  the nonce counter is big-endian
  2 failing  a zero DH output is accepted
  4 failing  the protocol name is always hashed
  6 failing  the prologue is not mixed in
  4 failing  HKDF's second output uses the wrong counter
  2 failing  the KK pre-messages are mixed in the wrong order
  7 failing and then an error  both sides use the same cipher state
 12 failing and then an error  the counter moves before the tag is checked
```


- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
bash scripts/test-link-contract.sh | tail -3
git add tests/fixtures/link/reference.py tests/fixtures/link/build_cases.py tests/fixtures/link/noise-vectors.json
cat > "${TMPDIR:-/tmp}/g20-msg2.txt" <<'EOF'
test(link): Noise XX and KK vectors, damaged-message cases and the reference handshake (G2-0)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -q -F "${TMPDIR:-/tmp}/g20-msg2.txt" && git log --oneline -3 && git show --stat --format= HEAD
```

Expected: the test run ends with `all link contract checks passed` and `✓ noise-vectors.json matches build_cases.py`; three files are committed.

---

### Task 3: The pairing code: the commitment, the nonces and the clocks

**Files:**
- Modify: `tests/fixtures/link/build_cases.py`, `tests/fixtures/link/reference.py`
- Create: `tests/fixtures/link/pairing-cases.json` (written by the builder)

**Interfaces:**
- Consumes: Task 1's `load`, `check`, the markers; Task 2's `x25519_pub` and the `xx-link` vector (the builder pastes its commitment, keys and code as literals).
- Produces: `CODE_DIGITS` (6), `COMMIT_LABEL` (`b"notchmeow-link pairing commit v1"`), `CODE_LABEL` (`b"notchmeow-link pairing code v1"`), `PAIR_GAP_MS` (30000), `PAIR_WINDOW_MS` (120000), `OFFER_TIMEOUT_MS` (120000), `commit_of(nonce, static_pub)` (32 bytes; raises `ValueError` unless both are 32 bytes), `pairing_code(nonce_i, nonce_r, static_i, static_r)` (the six digits as text; raises `ValueError` unless all four are 32 bytes), `pairing_attempt_allowed(last_ms, now_ms)`, `pairing_window_open(start_ms, now_ms)`, `offer_expired(offered_ms, now_ms)`; the fixture `pairing-cases.json`: `digits`, `commitLabel`, `codeLabel`, `gapMs`, `windowMs`, `offerTimeoutMs`, `commits[]` (`name`, `nonce`, `static`, `commit`), `codes[]` (`name`, `nonceI`, `nonceR`, `staticI`, `staticR`, `code`), `invalid[]`, `session` (the pairing inside the `xx-link` vector), `gapCases[]`, `windowCases[]`, `offerCases[]`. Task 4 adds the machines to the same file.

**The owner's decision (2026-10-14): a commit-then-reveal step, not 8 digits.** A 6-digit code made from the handshake alone can be ground offline by a man in the middle (about 10^6 tries). The construction here is the short-authenticated-string pattern of Vaudenay (CRYPTO 2005), of ZRTP's hash commitment (RFC 6189) and of Bluetooth's numeric comparison (Core Specification, Vol 3, Part H, 2.3.5.6.2, `f4` and `g2`): the initiator commits to a fresh nonce **before** it has seen the responder's, the responder answers with a nonce of its own, the initiator then reveals, and the code is a hash of both nonces and both static public keys. Every choice a man in the middle makes (its keys, its nonce, towards each side) is made before the honest nonce is known, so the code on each screen is unpredictable to it and it gets **one guess per attempt**, 1 in 10^6, and an attempt is allowed once every 30 seconds.

- `commit_of(nonce, static)` is `SHA-256(label + static + nonce)`, sent in the clear as the payload of the first Noise message. It binds the initiator's static key: a commitment cannot be moved to another key.
- `pairing_code(...)` is `SHA-256(label + static_i + static_r + nonce_i + nonce_r)`, the first 8 bytes as a big-endian number, modulo 10^6, with leading zeros. **The handshake hash is not an input, on purpose:** the last sender's payload (its name, a free text) is in that hash and can still be varied after it has seen the other side's nonce, which lets a man in the middle grind the code offline again. The two static keys are enough, because Noise `XX` authenticates them: a substituted key gives a different code on the two screens.
- The six-digit length is the spec's; the 8-digit value is gone from the contract.

The values in the fixture were pasted from the reference. One commitment and one code were also worked out with `openssl dgst -sha256` when the plan was drafted, and it agrees.

- [ ] **Step 1: Add the builder and write the fixture**

```bash
cat > "${TMPDIR:-/tmp}/g20-t3-build.py" <<'EOF'
def pairing_cases():
    """The commitments and the codes are pasted once from the reference and frozen here; one commitment and one code were also worked out with `openssl dgst -sha256`, which agrees."""
    N, M, SI, SR = "a1" * 32, "b1" * 32, "c1" * 32, "c2" * 32     # the initiator's nonce, the responder's nonce, their static keys: plain patterns made for tests
    commits = [
        {"name": "a nonce and a key", "nonce": N, "static": SI, "commit": "4b8c8215defb279e6d2b65dc0653202357f9da0b3a0e4c661cec2a05f1a00c5d"},
        {"name": "the same nonce under another key: another commitment", "nonce": N, "static": SR, "commit": "63cdd5031f2d4bdd441b126924ba504fac75a6232f81ad2870b49ab0cfc02934"},
        {"name": "all zeros", "nonce": "00" * 32, "static": "00" * 32, "commit": "8d8b1a74a8c0b374e1cecd4579d33ed784470385b72a280f893c75b2ee274a2b"},
        {"name": "all ones", "nonce": "ff" * 32, "static": "ff" * 32, "commit": "e696a5dc70a722bfd46d12c64d1ee4787888862e22bcdd8ada9ef66d96c6d124"},
        {"name": "a counting nonce", "nonce": bytes(range(32)).hex(), "static": SI, "commit": "66507b3e4a69a747a2a52b3cedd4feabb6fd66836adc7d97cae47b24da3f5850"},
    ]
    codes = [
        {"name": "a pairing", "nonceI": N, "nonceR": M, "staticI": SI, "staticR": SR, "code": "479411"},
        {"name": "the two nonces swapped", "nonceI": M, "nonceR": N, "staticI": SI, "staticR": SR, "code": "080624"},
        {"name": "the two static keys swapped", "nonceI": N, "nonceR": M, "staticI": SR, "staticR": SI, "code": "585340"},
        {"name": "all zeros", "nonceI": "00" * 32, "nonceR": "00" * 32, "staticI": "00" * 32, "staticR": "00" * 32, "code": "608564"},
        {"name": "all ones", "nonceI": "ff" * 32, "nonceR": "ff" * 32, "staticI": "ff" * 32, "staticR": "ff" * 32, "code": "848961"},
        {"name": "a counting initiator nonce", "nonceI": bytes(range(32)).hex(), "nonceR": M, "staticI": SI, "staticR": SR, "code": "803937"},
        {"name": "a code that starts with three zeros keeps them", "nonceI": "165b6120ed15c5315aa509306b30f1984630df0155dd087af96ef93660272454", "nonceR": M, "staticI": SI, "staticR": SR, "code": "000973"},
    ]
    bad = [("a nonce of 31 bytes", "a1" * 31), ("a nonce of 33 bytes", "a1" * 33), ("an empty nonce", ""), ("a nonce that is text", "zz"), ("no nonce", None)]
    invalid = [{"name": n, "field": "nonceI", "value": v} for n, v in bad] + [{"name": "a static key of 31 bytes", "field": "staticR", "value": "c2" * 31}]
    # The pairing of the xx-link vector in noise-vectors.json: its first message carries the commitment, its second and third the two hellos with the nonces.
    session = {"vector": "xx-link", "nonceI": N, "nonceR": M, "staticI": "7b4e909bbe7ffe44c465a220037d608ee35897d31ef972f07f74892cb0f73f13",
               "staticR": "7b0d47d93427f8311160781c7c733fd89f88970aef490d8aa0ee19a4cb8a1b14", "commit": "2d9a045c7dff54d2f01937d89c0368f3cf4405c05aa95509487d1d85291222a0", "code": "283272"}
    gaps = []

    def gap(name, last, now, out):
        gaps.append({"name": name, "last": last, "now": now, "out": out})

    gap("the first attempt", None, 0, True)
    gap("the first attempt, at any time", None, 987654321, True)
    gap("29.999 seconds after the last", 1000, 30999, False)
    gap("exactly 30 seconds after the last", 1000, 31000, True)
    gap("a minute after the last", 1000, 61000, True)
    gap("at the same instant", 1000, 1000, False)
    gap("the clock went back", 31000, 1000, False)
    gap("now is negative", 1000, -1, False)
    gap("last is negative", -5, 100000, False)
    gap("now is text", 1000, "31000", False)
    gap("last is text", "1000", 31000, False)
    gap("now is true", 1000, True, False)
    gap("now is null", 1000, None, False)
    windows = []

    def window(name, start, now, out):
        windows.append({"name": name, "start": start, "now": now, "out": out})

    window("the moment it opens", 5000, 5000, True)
    window("one millisecond before 2 minutes", 5000, 124999, True)
    window("exactly 2 minutes", 5000, 125000, False)
    window("long after", 5000, 900000, False)
    window("the clock went back", 5000, 4999, False)
    window("the start is text", "5000", 6000, False)
    window("the start is null", None, 6000, False)
    window("now is negative", 0, -1, False)
    offers = []

    def offer(name, offered, now, out):
        offers.append({"name": name, "offered": offered, "now": now, "out": out})

    offer("just offered", 5000, 5000, False)
    offer("one millisecond before 2 minutes", 5000, 124999, False)
    offer("exactly 2 minutes: expired", 5000, 125000, True)
    offer("long after", 5000, 900000, True)
    offer("the clock went back: expired", 5000, 4999, True)
    offer("the offer time is text: expired", "5000", 6000, True)
    offer("the offer time is null: expired", None, 6000, True)
    offer("now is negative: expired", 0, -1, True)
    out = {"version": 1, "digits": 6, "commitLabel": "notchmeow-link pairing commit v1", "codeLabel": "notchmeow-link pairing code v1", "gapMs": 30000, "windowMs": 120000, "offerTimeoutMs": 120000,
           "commits": commits, "codes": codes, "invalid": invalid, "session": session, "gapCases": gaps, "windowCases": windows, "offerCases": offers}
    # @@PAIRING-KEYS
    return out
EOF
cat > "${TMPDIR:-/tmp}/g20-t3-files.txt" <<'EOF'
    "pairing-cases.json": (pairing_cases, False),
EOF
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/build_cases.py "# @@BUILDERS" "${TMPDIR:-/tmp}/g20-t3-build.py"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/build_cases.py "    # @@FILES" "${TMPDIR:-/tmp}/g20-t3-files.txt"
python3 -B tests/fixtures/link/build_cases.py
```

Expected: `wrote noise-vectors.json (12735 bytes)` and `wrote pairing-cases.json (7656 bytes)`.

- [ ] **Step 2: Add the replay, and run it to see it fail**

```bash
cat > "${TMPDIR:-/tmp}/g20-t3-checks.py" <<'EOF'
def check_pairing():
    print("pairing-cases.json: the commitment, the code and the clocks")
    f = load("pairing-cases.json")
    check("the constants are the ones the rules name", (f["digits"], f["commitLabel"].encode(), f["codeLabel"].encode(), f["gapMs"], f["windowMs"], f["offerTimeoutMs"]),
          (CODE_DIGITS, COMMIT_LABEL, CODE_LABEL, PAIR_GAP_MS, PAIR_WINDOW_MS, OFFER_TIMEOUT_MS))
    for c in f["commits"]:
        check("commitment: " + c["name"], commit_of(bytes.fromhex(c["nonce"]), bytes.fromhex(c["static"])).hex(), c["commit"])
    for c in f["codes"]:
        check("code: " + c["name"], pairing_code(*[bytes.fromhex(c[k]) for k in ("nonceI", "nonceR", "staticI", "staticR")]), c["code"])
    for c in f["invalid"]:
        args = {"nonceI": bytes(32), "nonceR": bytes(32), "staticI": bytes(32), "staticR": bytes(32)}
        v = c["value"]
        try:
            args[c["field"]] = bytes.fromhex(v) if isinstance(v, str) else v
        except ValueError:
            args[c["field"]] = v                              # text that is not hex stays text
        try:
            pairing_code(*args.values())
            got = "a code"
        except ValueError:
            got = "refused"
        check("code: " + c["name"] + ": no code", got, "refused")
    for c in f["gapCases"]:
        check("a pairing attempt: " + c["name"], pairing_attempt_allowed(c["last"], c["now"]), c["out"])
    for c in f["windowCases"]:
        check("the pairing window: " + c["name"], pairing_window_open(c["start"], c["now"]), c["out"])
    for c in f["offerCases"]:
        check("an offer's 2 minutes: " + c["name"], offer_expired(c["offered"], c["now"]), c["out"])
    # Properties. Every input matters, the code is spread evenly, and a commitment says nothing about the nonce it hides.
    rnd = random.Random(20261014)
    ok = True
    for _ in range(300):
        a = [rnd.randbytes(32) for _ in range(4)]
        base = pairing_code(*a)
        for i in range(4):
            b = list(a)
            b[i] = bytes([b[i][0] ^ 1]) + b[i][1:]
            ok &= pairing_code(*b) != base
        ok &= commit_of(a[0], a[2]) != commit_of(a[1], a[2]) and commit_of(a[0], a[2]) != commit_of(a[0], a[3])
    check("300 random pairings: changing any one of the two nonces and the two keys changes the code, and the commitment depends on both of its inputs", ok, True)
    codes = [pairing_code(hashlib.sha256(b"n %d" % n).digest(), b"\xb1" * 32, b"\xc1" * 32, b"\xc2" * 32) for n in range(20000)]
    check("every code is exactly 6 digits, leading zeros kept", all(len(c) == 6 and c.isdigit() for c in codes), True)
    worst = max(sum((n - 2000) ** 2 / 2000 for n in (sum(1 for c in codes if c[p] == str(d)) for d in range(10))) for p in range(6))
    check("each digit position is spread evenly (chi-square over 10 values under 35 for every position)", worst < 35, True)
    check("a leading zero appears about one time in ten", 1700 < sum(1 for c in codes if c[0] == "0") < 2300, True)
    # What a man in the middle can do once the commitment is out: every choice it makes (its keys, its nonce) comes before the honest nonce, so over honest nonces
    # its fixed choices give a code that is as spread as any other: it cannot aim.
    fixed = [b"\xee" * 32, b"\xc1" * 32, b"\xc3" * 32]
    aimed = [pairing_code(hashlib.sha256(b"honest %d" % n).digest(), fixed[0], fixed[1], fixed[2]) for n in range(3000)]
    check("a man in the middle's fixed choices give a different code for almost every honest nonce (3000 nonces, over 2980 different codes)", len(set(aimed)) > 2980, True)
    print("  i with the commitment a man in the middle has one guess per attempt: 1 in 10**6 for 6 digits, and an attempt is allowed every 30 seconds")
EOF
printf '    check_pairing()\n' > "${TMPDIR:-/tmp}/g20-t3-calls.txt"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "# @@CHECKS" "${TMPDIR:-/tmp}/g20-t3-checks.py"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "    # @@CALLS" "${TMPDIR:-/tmp}/g20-t3-calls.txt"
python3 -B tests/fixtures/link/reference.py 2>&1 | tail -3
```

Expected: a traceback ending `NameError: name 'CODE_DIGITS' is not defined`.

- [ ] **Step 3: Add the rules**

```bash
cat > "${TMPDIR:-/tmp}/g20-t3-rules.py" <<'EOF'
# ---- the pairing code: a commitment, two nonces and the two static keys (Task 3) ------------------------------------
# The construction is the short-authenticated-string pattern of Vaudenay (CRYPTO 2005), ZRTP (RFC 6189, the hash commitment) and Bluetooth's numeric
# comparison (Core Specification, Vol 3, Part H, 2.3.5.6.2: f4 and g2): one side commits to its nonce before it has seen the other's, the other side
# answers with a nonce of its own, the first side then reveals, and the short code is a hash of both nonces and both public keys. A man in the middle
# has to choose its keys and its nonce for each side before the honest side's nonce is known, so it gets one guess at the code per attempt.
CODE_DIGITS = 6                                   # the spec's 6; the commitment is what keeps it safe
COMMIT_LABEL = b"notchmeow-link pairing commit v1"
CODE_LABEL = b"notchmeow-link pairing code v1"
PAIR_GAP_MS = 30_000                              # at most one pairing attempt every 30 seconds
PAIR_WINDOW_MS = 120_000                          # the pairing window closes after 2 minutes
OFFER_TIMEOUT_MS = 120_000                        # an offer nobody answers is declined after 2 minutes


def _bytes32(*values):
    return all(isinstance(v, (bytes, bytearray)) and len(v) == 32 for v in values)


def commit_of(nonce, static_pub):
    """The initiator's commitment, sent in the clear as the payload of the first Noise message: SHA-256 over the label, its static public key and its
    fresh 32-byte nonce. Binding the key means a commitment cannot be moved to another key; the nonce stays secret until the reveal."""
    if not _bytes32(nonce, static_pub):
        raise ValueError("commit_of needs a 32-byte nonce and a 32-byte static public key")
    return hashlib.sha256(COMMIT_LABEL + bytes(static_pub) + bytes(nonce)).digest()


def pairing_code(nonce_i, nonce_r, static_i, static_r):
    """The six digits both screens show: SHA-256 over the label, the initiator's static key, the responder's static key, the initiator's nonce and the
    responder's nonce (always in that order); the first 8 bytes as a big-endian number; modulo 10**6; written with leading zeros.
    The handshake hash is deliberately not an input: the last sender's payload (its name, say) is in it and is free to vary after that sender has seen
    the other's nonce, which would let a man in the middle grind the code offline. The static keys are enough: the handshake authenticates them."""
    if not _bytes32(nonce_i, nonce_r, static_i, static_r):
        raise ValueError("pairing_code needs two 32-byte nonces and two 32-byte static public keys")
    d = hashlib.sha256(CODE_LABEL + bytes(static_i) + bytes(static_r) + bytes(nonce_i) + bytes(nonce_r)).digest()
    return str(int.from_bytes(d[:8], "big") % 10**CODE_DIGITS).zfill(CODE_DIGITS)


def _ms(v):
    return isinstance(v, int) and not isinstance(v, bool) and v >= 0


def pairing_attempt_allowed(last_ms, now_ms):
    """last_ms is None for the first attempt. Allowed when PAIR_GAP_MS have passed; a clock that went back, or a value that is not whole milliseconds, refuses."""
    if not _ms(now_ms) or not (last_ms is None or _ms(last_ms)):
        return False
    return last_ms is None or now_ms - last_ms >= PAIR_GAP_MS


def pairing_window_open(start_ms, now_ms):
    return _ms(start_ms) and _ms(now_ms) and 0 <= now_ms - start_ms < PAIR_WINDOW_MS


def offer_expired(offered_ms, now_ms):
    """Expired at exactly OFFER_TIMEOUT_MS. A clock that went back, or a bad value, counts as expired: declining is the safe side."""
    if not _ms(offered_ms) or not _ms(now_ms):
        return True
    return not 0 <= now_ms - offered_ms < OFFER_TIMEOUT_MS
EOF
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "# @@RULES" "${TMPDIR:-/tmp}/g20-t3-rules.py"
```

- [ ] **Step 4: Run it to see it pass**

```bash
bash scripts/test-link-contract.sh | grep -v "✓"
bash scripts/test-link-contract.sh | grep -c "✓"
```

Expected: the headings, the line `  i with the commitment a man in the middle has one guess per attempt: 1 in 10**6 for 6 digits, and an attempt is allowed every 30 seconds` (information, not a check) and `all link contract checks passed`; the second prints `97`.

- [ ] **Step 5: Prove it bites (a one-off, never committed)**

```bash
cat > "${TMPDIR:-/tmp}/g20-m3.json" <<'EOF'
[
 ["the commitment label changes", "COMMIT_LABEL = b\"notchmeow-link pairing commit v1\"", "COMMIT_LABEL = b\"notchmeow-link pairing commit v2\""],
 ["the commitment forgets the static key", "COMMIT_LABEL + bytes(static_pub) + bytes(nonce)", "COMMIT_LABEL + bytes(nonce)"],
 ["the code label changes", "CODE_LABEL = b\"notchmeow-link pairing code v1\"", "CODE_LABEL = b\"notchmeow-link pairing code v2\""],
 ["the code ignores the responder's nonce", "bytes(static_r) + bytes(nonce_i) + bytes(nonce_r))", "bytes(static_r) + bytes(nonce_i))"],
 ["the code ignores the initiator's static key", "CODE_LABEL + bytes(static_i) + bytes(static_r)", "CODE_LABEL + bytes(static_r)"],
 ["the two nonces are in the other order", "bytes(nonce_i) + bytes(nonce_r))", "bytes(nonce_r) + bytes(nonce_i))"],
 ["the leading zeros are lost", ".zfill(CODE_DIGITS)", ""],
 ["the modulus is one digit too big", "% 10**CODE_DIGITS", "% 10**(CODE_DIGITS + 1)"],
 ["thirty seconds exactly is still too soon", "now_ms - last_ms >= PAIR_GAP_MS", "now_ms - last_ms > PAIR_GAP_MS"],
 ["a clock that went back grants an attempt", "return last_ms is None or now_ms - last_ms >= PAIR_GAP_MS", "return last_ms is None or abs(now_ms - last_ms) >= PAIR_GAP_MS"],
 ["the window is still open at exactly 2 minutes", "0 <= now_ms - start_ms < PAIR_WINDOW_MS", "0 <= now_ms - start_ms <= PAIR_WINDOW_MS"],
 ["an offer is still alive at exactly 2 minutes", "return not 0 <= now_ms - offered_ms < OFFER_TIMEOUT_MS", "return not 0 <= now_ms - offered_ms <= OFFER_TIMEOUT_MS"],
 ["a key of the wrong length is accepted", "    if not _bytes32(nonce_i, nonce_r, static_i, static_r):", "    if False:"]
]
EOF
python3 -B "${TMPDIR:-/tmp}/g20-mutate.py" "${TMPDIR:-/tmp}/g20-m3.json"
```

Expected: every change fails at least one check or ends in an error, and the numbers are these:

```text
  6 failing  the commitment label changes
  6 failing  the commitment forgets the static key
  8 failing  the code label changes
  8 failing  the code ignores the responder's nonce
  8 failing  the code ignores the initiator's static key
  5 failing  the two nonces are in the other order
  3 failing and then an error  the leading zeros are lost
  9 failing  the modulus is one digit too big
  1 failing  thirty seconds exactly is still too soon
  1 failing  a clock that went back grants an attempt
  1 failing  the window is still open at exactly 2 minutes
  1 failing  an offer is still alive at exactly 2 minutes
  3 failing and then an error  a key of the wrong length is accepted
```


- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
bash scripts/test-link-contract.sh | tail -3
git add tests/fixtures/link/reference.py tests/fixtures/link/build_cases.py tests/fixtures/link/pairing-cases.json
cat > "${TMPDIR:-/tmp}/g20-msg3.txt" <<'EOF'
test(link): the pairing commitment, the code from two nonces and two keys, and the pairing clocks (G2-0)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -q -F "${TMPDIR:-/tmp}/g20-msg3.txt" && git log --oneline -4 && git show --stat --format= HEAD
```

Expected: three files committed; the test run ends with `all link contract checks passed` and the no-drift lines.

---

### Task 4: The pairing in order: the two machines

**Files:**
- Modify: `tests/fixtures/link/build_cases.py` (a builder, and one line in `pairing_cases()` above its marker), `tests/fixtures/link/reference.py`
- Modify (regenerated): `tests/fixtures/link/pairing-cases.json`

**Interfaces:**
- Consumes: Task 3's `commit_of`, `pairing_code`, `pairing_attempt_allowed`, `pairing_window_open`, the `# @@PAIRING-KEYS` marker inside `pairing_cases()`.
- Produces: `pair_responder_step(state, event)` and `pair_initiator_step(state, event)`, each giving `{state, send, notify, because}`; in `pairing-cases.json` the new keys `machineNote`, `responder[]` and `initiator[]` of `{name, state, event, out}` and `machineTrips[]` of `{name, side, from, events, out}`. **States.** Responder: `{s: "idle", seen: [{commit, at}], last}`, `{s: "committed", commit, start, nonce, seen, last}`, `{s: "coded", start, code, mine, theirs, seen, last}` (`seen` is the list of commitments the app keeps across connections, `last` the time of the last attempt or `None`). Initiator: `{s: "idle", last}`, `{s: "started", nonce, static, start, last}`, `{s: "coded", start, code, mine, theirs, last}`. **Events.** Responder: `{commit, nonce, now}` (the first message arrived; `nonce` is the app's fresh one), `{reveal: {nonce, static, own}, now}` (the third message was opened), `{user, now}`, `{peer, now}`. Initiator: `{start: {nonce, static}, now}`, `{nonce, peerStatic, now}`, `{user, now}`, `{peer, now}`. **Answers.** `send` holds `{nonce}`, `{commit}`, `{reveal}` or `{pair: "yes"|"no"}`; `notify` is `nonce-sent`, `commit-sent`, `show-code`, `store` or `discard`; **`because`** names every refusal, and a port tests the cause: `commit-length`, `commit-replayed`, `attempt-too-soon`, `no-commit`, `reveal-late`, `reveal-length`, `reveal-mismatch`, `unexpected`, `start-length`, `nonce-repeated`, `nonce-length`, `window-closed`, `said-no`.

The order on the wire (the full text is in `docs/LINK-CONTRACT.md`): the initiator's first Noise message carries the commitment as its payload; the responder's second carries its hello with its nonce; the initiator's third carries its hello with the revealed nonce; both then show the code; each user answers; a `pair-yes` or `pair-no` tells the other side; **a key is stored only when both said yes**, and the window of 2 minutes covers all of it. The cases include the five the owner named: a wrong reveal (`reveal-mismatch`), a reveal before the commitment (`no-commit`), a replayed commitment (`commit-replayed`), a reveal under a key other than the committed one (`reveal-mismatch`: a wrong nonce and a wrong key look the same, on purpose, because a commitment cannot tell them apart) and a reveal after the window (`reveal-late`).

- [ ] **Step 1: Add the builder, hook it into the fixture and write it**

```bash
cat > "${TMPDIR:-/tmp}/g20-t4-build.py" <<'EOF'
def pairing_machine_cases():
    """The two pairing machines, row by row. N and M are the initiator's and the responder's nonces, SI and SR their static keys, C the commitment of N under SI
    (the values of pairing-cases.json); 479411 is the code of the four."""
    N, M, SI, SR = "a1" * 32, "b1" * 32, "c1" * 32, "c2" * 32
    C = "4b8c8215defb279e6d2b65dc0653202357f9da0b3a0e4c661cec2a05f1a00c5d"
    D = "63cdd5031f2d4bdd441b126924ba504fac75a6232f81ad2870b49ab0cfc02934"      # another commitment
    CODE = "479411"
    rows, irows, trips = [], [], []

    def out(state, send=(), notify=None, because=None):
        return {"state": state, "send": list(send), "notify": notify, "because": because}

    def ridle(seen=(), last=None):
        return {"s": "idle", "seen": list(seen), "last": last}

    def committed(start=1000, seen=None, last=None, commit=C):
        return {"s": "committed", "commit": commit, "start": start, "nonce": M, "seen": [{"commit": commit, "at": start}] if seen is None else seen, "last": start if last is None else last}

    def coded(mine=None, theirs=None, start=1000, seen=None, last=None):
        return {"s": "coded", "start": start, "code": CODE, "mine": mine, "theirs": theirs, "seen": [{"commit": C, "at": start}] if seen is None else seen, "last": start if last is None else last}

    def reveal(nonce=N, static=SI, own=SR, now=2000):
        return {"reveal": {"nonce": nonce, "static": static, "own": own}, "now": now}

    def r(name, state, event, want):
        rows.append({"name": name, "state": state, "event": event, "out": want})

    yes_sent, no_sent = [{"pair": "yes"}], [{"pair": "no"}]
    # The responder: the first message arrives with the commitment.
    r("a commitment starts a pairing: the responder's nonce goes out", ridle(), {"commit": C, "nonce": M, "now": 1000}, out(committed(), [{"nonce": M}], "nonce-sent"))
    r("a commitment of 31 bytes", ridle(), {"commit": C[:-2], "nonce": M, "now": 1000}, out(ridle(), because="commit-length"))
    r("a nonce of 31 bytes from the app", ridle(), {"commit": C, "nonce": M[:-2], "now": 1000}, out(ridle(), because="commit-length"))
    r("a commitment in capitals is not a commitment", ridle(), {"commit": C.upper(), "nonce": M, "now": 1000}, out(ridle(), because="commit-length"))
    r("the same commitment again a minute later: replayed", ridle([{"commit": C, "at": 1000}], 1000), {"commit": C, "nonce": M, "now": 61000},
      out(ridle([{"commit": C, "at": 1000}], 1000), because="commit-replayed"))
    r("the same commitment again after 10 seconds is named a replay, not too soon", ridle([{"commit": C, "at": 1000}], 1000), {"commit": C, "nonce": M, "now": 11000},
      out(ridle([{"commit": C, "at": 1000}], 1000), because="commit-replayed"))
    r("the same commitment after the window has closed is a new attempt, and the old entry goes", ridle([{"commit": C, "at": 1000}], 1000), {"commit": C, "nonce": M, "now": 121000},
      out(committed(121000), [{"nonce": M}], "nonce-sent"))
    r("another commitment 19 seconds after the last attempt: too soon", ridle([{"commit": C, "at": 1000}], 1000), {"commit": D, "nonce": M, "now": 20000},
      out(ridle([{"commit": C, "at": 1000}], 1000), because="attempt-too-soon"))
    r("another commitment exactly 30 seconds after", ridle([{"commit": C, "at": 1000}], 1000), {"commit": D, "nonce": M, "now": 31000},
      out(committed(31000, [{"commit": C, "at": 1000}, {"commit": D, "at": 31000}], commit=D), [{"nonce": M}], "nonce-sent"))
    r("a commitment during a pairing", committed(), {"commit": D, "nonce": M, "now": 40000}, out(ridle([{"commit": C, "at": 1000}], 1000), because="unexpected"))
    # The third message: the reveal.
    r("a reveal with no commitment before it", ridle(), reveal(), out(ridle(), because="no-commit"))
    r("the reveal matches: the code is shown", committed(), reveal(), out(coded(), notify="show-code"))
    r("the reveal one millisecond before the window closes", committed(), reveal(now=120999), out(coded(), notify="show-code"))
    r("the reveal exactly when the window closes: too late", committed(), reveal(now=121000), out(ridle([{"commit": C, "at": 1000}], 1000), because="reveal-late"))
    r("a reveal long after the window", committed(), reveal(now=900000), out(ridle([{"commit": C, "at": 1000}], 1000), because="reveal-late"))
    r("a reveal of another nonce than the one committed", committed(), reveal(nonce=M), out(ridle([{"commit": C, "at": 1000}], 1000), because="reveal-mismatch"))
    r("a reveal under another static key than the one committed", committed(), reveal(static=SR), out(ridle([{"commit": C, "at": 1000}], 1000), because="reveal-mismatch"))
    r("a reveal that is the commitment itself", committed(), reveal(nonce=C), out(ridle([{"commit": C, "at": 1000}], 1000), because="reveal-mismatch"))
    r("a reveal with a nonce of 31 bytes", committed(), reveal(nonce=N[:-2]), out(ridle([{"commit": C, "at": 1000}], 1000), because="reveal-length"))
    r("a reveal with no key of its own", committed(), {"reveal": {"nonce": N, "static": SI}, "now": 2000}, out(ridle([{"commit": C, "at": 1000}], 1000), because="reveal-length"))
    r("a second reveal once the code is shown", coded(), reveal(), out(ridle([{"commit": C, "at": 1000}], 1000), because="unexpected"))
    # The answers.
    r("the user says they match", coded(), {"user": "yes", "now": 3000}, out(coded(mine="yes"), yes_sent))
    r("the user says they match after the other side did: the key is stored", coded(theirs="yes"), {"user": "yes", "now": 3000}, out(ridle([{"commit": C, "at": 1000}], 1000), yes_sent, "store"))
    r("the other side says they match after the user did: the key is stored", coded(mine="yes"), {"peer": "yes", "now": 3000}, out(ridle([{"commit": C, "at": 1000}], 1000), [], "store"))
    r("the other side says they match first", coded(), {"peer": "yes", "now": 3000}, out(coded(theirs="yes")))
    r("the user says they do not match", coded(), {"user": "no", "now": 3000}, out(ridle([{"commit": C, "at": 1000}], 1000), no_sent, "discard", "said-no"))
    r("the user says no after the other side said yes: nothing is stored", coded(theirs="yes"), {"user": "no", "now": 3000}, out(ridle([{"commit": C, "at": 1000}], 1000), no_sent, "discard", "said-no"))
    r("the other side says no", coded(mine="yes"), {"peer": "no", "now": 3000}, out(ridle([{"commit": C, "at": 1000}], 1000), [], "discard", "said-no"))
    r("an answer that is not exactly yes is a no", coded(), {"user": "YES", "now": 3000}, out(ridle([{"commit": C, "at": 1000}], 1000), no_sent, "discard", "said-no"))
    r("an answer of true is a no", coded(), {"peer": True, "now": 3000}, out(ridle([{"commit": C, "at": 1000}], 1000), [], "discard", "said-no"))
    r("an answer when the window has closed", coded(mine="yes"), {"peer": "yes", "now": 121000}, out(ridle([{"commit": C, "at": 1000}], 1000), [], "discard", "window-closed"))
    r("a click before there is a code is ignored", committed(), {"user": "yes", "now": 3000}, out(committed()))
    r("an event the machine does not know is ignored", committed(), {"surprise": True}, out(committed()))

    def iidle(last=None):
        return {"s": "idle", "last": last}

    def started(start=1000):
        return {"s": "started", "nonce": N, "static": SI, "start": start, "last": start}

    def icoded(mine=None, theirs=None, start=1000):
        return {"s": "coded", "start": start, "code": CODE, "mine": mine, "theirs": theirs, "last": start}

    def second(nonce=M, peer=SR, now=2000):
        return {"nonce": nonce, "peerStatic": peer, "now": now}

    def i(name, state, event, want):
        irows.append({"name": name, "state": state, "event": event, "out": want})

    # The initiator.
    i("the user starts a pairing: the commitment goes out", iidle(), {"start": {"nonce": N, "static": SI}, "now": 1000}, out(started(), [{"commit": C}], "commit-sent"))
    i("a start 19 seconds after the last attempt: too soon", iidle(1000), {"start": {"nonce": N, "static": SI}, "now": 20000}, out(iidle(1000), because="attempt-too-soon"))
    i("a start exactly 30 seconds after", iidle(1000), {"start": {"nonce": N, "static": SI}, "now": 31000}, out({"s": "started", "nonce": N, "static": SI, "start": 31000, "last": 31000}, [{"commit": C}], "commit-sent"))
    i("a start with a nonce of 31 bytes", iidle(), {"start": {"nonce": N[:-2], "static": SI}, "now": 1000}, out(iidle(), because="start-length"))
    i("a start during a pairing", started(), {"start": {"nonce": N, "static": SI}, "now": 5000}, out(iidle(1000), because="unexpected"))
    i("the other side's nonce before any commitment of ours", iidle(), second(), out(iidle(), because="no-commit"))
    i("the other side's nonce: the reveal goes out and the code is shown", started(), second(), out(icoded(), [{"reveal": N}], "show-code"))
    i("the other side's nonce one millisecond before the window closes", started(), second(now=120999), out(icoded(), [{"reveal": N}], "show-code"))
    i("the other side's nonce exactly when the window closes: nothing is revealed", started(), second(now=121000), out(iidle(1000), because="reveal-late"))
    i("a second nonce once the code is shown", icoded(), second(), out(iidle(1000), because="nonce-repeated"))
    i("a nonce of 31 bytes", started(), second(nonce=M[:-2]), out(iidle(1000), because="nonce-length"))
    i("no static key from the other side", started(), {"nonce": M, "now": 2000}, out(iidle(1000), because="nonce-length"))
    i("the user says they match", icoded(), {"user": "yes", "now": 3000}, out(icoded(mine="yes"), yes_sent))
    i("both say they match: the key is stored", icoded(theirs="yes"), {"user": "yes", "now": 3000}, out(iidle(1000), yes_sent, "store"))
    i("the other side says no", icoded(mine="yes"), {"peer": "no", "now": 3000}, out(iidle(1000), [], "discard", "said-no"))
    i("the user says no", icoded(), {"user": "no", "now": 3000}, out(iidle(1000), no_sent, "discard", "said-no"))
    i("an answer when the window has closed", icoded(), {"user": "yes", "now": 121000}, out(iidle(1000), [], "discard", "window-closed"))
    i("a click before there is a code is ignored", started(), {"user": "yes", "now": 3000}, out(started()))

    def trip(name, side, start, events, outs):
        trips.append({"name": name, "side": side, "from": start, "events": events, "out": outs})

    trip("the responder's whole pairing, both users agreeing", "responder", ridle(),
         [{"commit": C, "nonce": M, "now": 1000}, reveal(), {"user": "yes", "now": 5000}, {"peer": "yes", "now": 6000}],
         [out(committed(), [{"nonce": M}], "nonce-sent"), out(coded(), notify="show-code"), out(coded(mine="yes"), yes_sent), out(ridle([{"commit": C, "at": 1000}], 1000), [], "store")])
    trip("the responder, where the initiator reveals a different nonce than it committed", "responder", ridle(),
         [{"commit": C, "nonce": M, "now": 1000}, reveal(nonce=M), {"user": "yes", "now": 5000}],
         [out(committed(), [{"nonce": M}], "nonce-sent"), out(ridle([{"commit": C, "at": 1000}], 1000), because="reveal-mismatch"), out(ridle([{"commit": C, "at": 1000}], 1000))])
    trip("the responder, where the other user says the codes differ", "responder", ridle(),
         [{"commit": C, "nonce": M, "now": 1000}, reveal(), {"peer": "no", "now": 5000}, {"user": "yes", "now": 6000}],
         [out(committed(), [{"nonce": M}], "nonce-sent"), out(coded(), notify="show-code"), out(ridle([{"commit": C, "at": 1000}], 1000), [], "discard", "said-no"), out(ridle([{"commit": C, "at": 1000}], 1000))])
    trip("the initiator's whole pairing, both users agreeing", "initiator", iidle(),
         [{"start": {"nonce": N, "static": SI}, "now": 1000}, second(), {"peer": "yes", "now": 4000}, {"user": "yes", "now": 5000}],
         [out(started(), [{"commit": C}], "commit-sent"), out(icoded(), [{"reveal": N}], "show-code"), out(icoded(theirs="yes")), out(iidle(1000), yes_sent, "store")])
    return {"machineNote": "responder and initiator: pair_responder_step and pair_initiator_step of reference.py, one event at a time ({state, event} -> out). machineTrips: the same over a script, starting from `from`, the state of one result being the state of the next event. "
                                  "because is the cause of a refusal and is what a port tests; a wrong nonce and a wrong static key give the same cause (reveal-mismatch) on purpose, because the commitment cannot tell them apart.",
            "responder": rows, "initiator": irows, "machineTrips": trips}
EOF
cat > "${TMPDIR:-/tmp}/g20-t4-keys.txt" <<'EOF'
    out.update(pairing_machine_cases())
EOF
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/build_cases.py "# @@BUILDERS" "${TMPDIR:-/tmp}/g20-t4-build.py"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/build_cases.py "    # @@PAIRING-KEYS" "${TMPDIR:-/tmp}/g20-t4-keys.txt"
python3 -B tests/fixtures/link/build_cases.py
```

Expected: `wrote noise-vectors.json (12735 bytes)` and `wrote pairing-cases.json (45183 bytes)`.

- [ ] **Step 2: Add the replay, and run it to see it fail**

```bash
cat > "${TMPDIR:-/tmp}/g20-t4-checks.py" <<'EOF'
def check_pairing_machines():
    print("pairing-cases.json: the two machines")
    f = load("pairing-cases.json")
    for c in f["responder"]:
        check("responder: " + c["name"], pair_responder_step(c["state"], c["event"]), c["out"])
    for c in f["initiator"]:
        check("initiator: " + c["name"], pair_initiator_step(c["state"], c["event"]), c["out"])
    for c in f["machineTrips"]:
        step = pair_responder_step if c["side"] == "responder" else pair_initiator_step
        state, got = c["from"], []
        for ev in c["events"]:
            res = step(state, ev)
            got.append(res)
            state = res["state"]
        check("trip: " + c["name"], got, c["out"])
    # Two machines talking to each other, with the nonces and keys drawn from a seeded generator: both reach the same code, both store only when both say yes, and a man in
    # the middle who passes the first message on but chooses its own nonce and key for the other side gets different codes on the two screens (1 in 10**6 would match).
    rnd = random.Random(20261014)
    agree, stored_ok, mitm_equal = True, True, 0
    for _ in range(400):
        ni, nr, si, sr = (rnd.randbytes(32).hex() for _ in range(4))
        ini = pair_initiator_step({"s": "idle", "last": None}, {"start": {"nonce": ni, "static": si}, "now": 1000})
        res = pair_responder_step({"s": "idle", "seen": [], "last": None}, {"commit": ini["send"][0]["commit"], "nonce": nr, "now": 1000})
        i2 = pair_initiator_step(ini["state"], {"nonce": res["send"][0]["nonce"], "peerStatic": sr, "now": 2000})
        r2 = pair_responder_step(res["state"], {"reveal": {"nonce": i2["send"][0]["reveal"], "static": si, "own": sr}, "now": 2000})
        agree &= i2["state"]["code"] == r2["state"]["code"]
        a, b = rnd.choice(["yes", "no"]), rnd.choice(["yes", "no"])
        si_, ri_ = i2["state"], r2["state"]
        ri = pair_responder_step(ri_, {"user": a, "now": 3000})
        ii = pair_initiator_step(si_, {"user": b, "now": 3000})
        ri = pair_responder_step(ri["state"], {"peer": b, "now": 3500}) if ri["state"]["s"] == "coded" else ri
        ii = pair_initiator_step(ii["state"], {"peer": a, "now": 3500}) if ii["state"]["s"] == "coded" else ii
        stored_ok &= (ri["notify"] == "store" and ii["notify"] == "store") == (a == "yes" and b == "yes")
        # the man in the middle: its own nonce and key towards the initiator, so the initiator's code is computed from them
        mn, ms = rnd.randbytes(32).hex(), rnd.randbytes(32).hex()
        mitm = pair_initiator_step(ini["state"], {"nonce": mn, "peerStatic": ms, "now": 2000})
        mitm_equal += mitm["state"]["code"] == r2["state"]["code"]
    check("400 pairings: both machines compute the same code, and a key is stored exactly when both users say yes", (agree, stored_ok), (True, True))
    check("400 attempts by a man in the middle with its own nonce and key: the codes on the two screens almost never agree (at most 2 of 400, 1 in 10**6 each)", mitm_equal <= 2, True)
    # Random event scripts: nothing raises, a key is stored only after both users said yes, and a code is shown only after a good reveal.
    ok, last = True, None
    for _ in range(3000):
        for step, st in ((pair_responder_step, {"s": "idle", "seen": [], "last": None}), (pair_initiator_step, {"s": "idle", "last": None})):
            said = {"user": False, "peer": False}
            for _ in range(rnd.randrange(1, 14)):
                n, m, c = rnd.choice(["a1" * 32, "b1" * 32]), rnd.choice(["a1" * 32, "b1" * 32, "ab"]), rnd.choice(["4b8c8215defb279e6d2b65dc0653202357f9da0b3a0e4c661cec2a05f1a00c5d", "00" * 32])
                ev = rnd.choice([{"commit": c, "nonce": m, "now": rnd.choice([0, 1000, 31000, 130000])}, {"reveal": {"nonce": n, "static": "c1" * 32, "own": "c2" * 32}, "now": rnd.choice([1000, 125000])},
                                 {"start": {"nonce": n, "static": "c1" * 32}, "now": rnd.choice([0, 1000, 31000])}, {"nonce": m, "peerStatic": "c2" * 32, "now": rnd.choice([1000, 125000])},
                                 {"user": rnd.choice(["yes", "no", 1]), "now": rnd.choice([2000, 125000])}, {"peer": rnd.choice(["yes", "no", None]), "now": rnd.choice([2000, 125000])}, {}])
                before = st
                res = step(st, ev)
                st = res["state"]
                for who in ("user", "peer"):
                    if who in ev and before["s"] == "coded" and ev[who] == "yes" and res["because"] is None:
                        said[who] = True
                if res["notify"] == "store" and not (said["user"] and said["peer"]):
                    ok, last = False, (before, ev, res)
                if res["notify"] == "show-code" and before["s"] not in ("committed", "started"):
                    ok, last = False, (before, ev, res)
                if res["because"] is not None and st["s"] != "idle":
                    ok, last = False, (before, ev, res)
                if res["notify"] in ("store", "discard"):
                    said = {"user": False, "peer": False}
    check("6000 random event scripts: nothing raises, a key is stored only after both said yes, a code is shown only after a good reveal, a refusal ends in idle", (ok, last), (True, None))
EOF
printf '    check_pairing_machines()\n' > "${TMPDIR:-/tmp}/g20-t4-calls.txt"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "# @@CHECKS" "${TMPDIR:-/tmp}/g20-t4-checks.py"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "    # @@CALLS" "${TMPDIR:-/tmp}/g20-t4-calls.txt"
python3 -B tests/fixtures/link/reference.py 2>&1 | tail -3
```

Expected: a traceback ending `NameError: name 'pair_responder_step' is not defined`.

- [ ] **Step 3: Add the rules**

```bash
cat > "${TMPDIR:-/tmp}/g20-t4-rules.py" <<'EOF'
# ---- the pairing in order: the two machines of commit, nonce, reveal and confirm (Task 4) ---------------------------------
# The initiator (the machine whose user started the pairing) sends commit_of(nonce, static) as the payload of the first Noise message; the responder answers
# with its own nonce in the payload of the second; the initiator reveals its nonce in the payload of the third; both then compute pairing_code and show it.
# Each user answers "They match" (yes) or no; a pair-yes or pair-no frame tells the other side; a key is stored only when both said yes.
# Events carry the clock ("now", whole milliseconds on a monotonic clock) and the random values an app would draw ("nonce"); the machines draw nothing.
def _hex32(v):
    return isinstance(v, str) and len(v) == 64 and all(c in "0123456789abcdef" for c in v)


def _pout(state, send=(), notify=None, because=None):
    return {"state": state, "send": list(send), "notify": notify, "because": because}


def _answer(state, ev, idle):
    """The part both machines share: a click, or the other side's pair-yes or pair-no, after the code is shown. Anything but exactly "yes" is a no."""
    if state["s"] != "coded":
        return _pout(state)                                          # an answer before there is a code is ignored
    if not pairing_window_open(state["start"], ev.get("now")):
        return _pout(idle, notify="discard", because="window-closed")
    who, ans = ("mine", ev["user"]) if "user" in ev else ("theirs", ev["peer"])
    if ans != "yes":
        return _pout(idle, [{"pair": "no"}] if who == "mine" else [], "discard", because="said-no")
    new = {**state, who: "yes"}
    send = [{"pair": "yes"}] if who == "mine" else []
    if new["mine"] == "yes" and new["theirs"] == "yes":
        return _pout(idle, send, "store")
    return _pout(new, send)


def pair_responder_step(state, ev):
    """The machine of the machine that is asked to pair. state: {"s": "idle", seen, last} | {"s": "committed", commit, start, nonce, seen, last} |
    {"s": "coded", start, code, mine, theirs, seen, last}; seen is the list of {commit, at} the app keeps across connections, last the time of the last attempt (or None).
    ev: {"commit": hex, "nonce": hex, "now"} (the first message arrived; nonce is the app's fresh one) | {"reveal": {"nonce", "static", "own"}, "now"} (the third message was
    opened: the initiator's nonce and static key, and this machine's own static key) | {"user": "yes"|"no", "now"} | {"peer": "yes"|"no", "now"}.
    Returns {state, send, notify, because}: send holds {"nonce": hex} or {"pair": "yes"|"no"}; notify is nonce-sent, show-code, store or discard;
    because names the refusal (the connection is then closed and the state is idle again): commit-length, commit-replayed, attempt-too-soon, no-commit,
    reveal-late, reveal-length, reveal-mismatch, unexpected, window-closed, said-no."""
    keep = {"seen": state["seen"], "last": state["last"]}
    idle = {"s": "idle", **keep}
    now = ev.get("now")
    if "commit" in ev:
        if state["s"] != "idle":
            return _pout(idle, because="unexpected")
        if not _hex32(ev["commit"]) or not _hex32(ev.get("nonce")):
            return _pout(idle, because="commit-length")
        if any(e["commit"] == ev["commit"] and pairing_window_open(e["at"], now) for e in state["seen"]):
            return _pout(idle, because="commit-replayed")              # checked before the gap, so a replay is named as one
        if not pairing_attempt_allowed(state["last"], now):
            return _pout(idle, because="attempt-too-soon")
        seen = [e for e in state["seen"] if pairing_window_open(e["at"], now)] + [{"commit": ev["commit"], "at": now}]
        return _pout({"s": "committed", "commit": ev["commit"], "start": now, "nonce": ev["nonce"], "seen": seen, "last": now}, [{"nonce": ev["nonce"]}], "nonce-sent")
    if "reveal" in ev:
        r = ev["reveal"]
        if state["s"] == "idle":
            return _pout(idle, because="no-commit")                    # a reveal with no commitment before it
        if state["s"] != "committed":
            return _pout(idle, because="unexpected")
        if not pairing_window_open(state["start"], now):
            return _pout(idle, because="reveal-late")
        if not (_hex32(r.get("nonce")) and _hex32(r.get("static")) and _hex32(r.get("own"))):
            return _pout(idle, because="reveal-length")
        if commit_of(bytes.fromhex(r["nonce"]), bytes.fromhex(r["static"])).hex() != state["commit"]:
            return _pout(idle, because="reveal-mismatch")              # a wrong nonce and a wrong key look the same, on purpose
        code = pairing_code(bytes.fromhex(r["nonce"]), bytes.fromhex(state["nonce"]), bytes.fromhex(r["static"]), bytes.fromhex(r["own"]))
        return _pout({"s": "coded", "start": state["start"], "code": code, "mine": None, "theirs": None, **keep}, [], "show-code")
    if "user" in ev or "peer" in ev:
        return _answer(state, ev, idle)
    return _pout(state)


def pair_initiator_step(state, ev):
    """The machine of the machine whose user started the pairing. state: {"s": "idle", last} | {"s": "started", nonce, static, start, last} |
    {"s": "coded", start, code, mine, theirs, last}.
    ev: {"start": {"nonce", "static"}, "now"} (the user chose Pair a machine; the app's fresh nonce and its static public key) | {"nonce": hex, "peerStatic": hex, "now"}
    (the second message was opened: the responder's nonce and static key) | {"user": ...} | {"peer": ...}.
    send holds {"commit": hex}, {"reveal": hex} or {"pair": ...}; notify is commit-sent, show-code, store or discard; because is one of attempt-too-soon,
    start-length, no-commit, nonce-repeated, nonce-length, reveal-late, unexpected, window-closed, said-no."""
    keep = {"last": state["last"]}
    idle = {"s": "idle", **keep}
    now = ev.get("now")
    if "start" in ev:
        if state["s"] != "idle":
            return _pout(idle, because="unexpected")
        if not (_hex32(ev["start"].get("nonce")) and _hex32(ev["start"].get("static"))):
            return _pout(idle, because="start-length")
        if not pairing_attempt_allowed(state["last"], now):
            return _pout(idle, because="attempt-too-soon")
        n, s = ev["start"]["nonce"], ev["start"]["static"]
        return _pout({"s": "started", "nonce": n, "static": s, "start": now, "last": now}, [{"commit": commit_of(bytes.fromhex(n), bytes.fromhex(s)).hex()}], "commit-sent")
    if "nonce" in ev:
        if state["s"] == "idle":
            return _pout(idle, because="no-commit")                    # the other side's nonce with no commitment of ours before it
        if state["s"] != "started":
            return _pout(idle, because="nonce-repeated")
        if not pairing_window_open(state["start"], now):
            return _pout(idle, because="reveal-late")
        if not (_hex32(ev["nonce"]) and _hex32(ev.get("peerStatic"))):
            return _pout(idle, because="nonce-length")
        code = pairing_code(bytes.fromhex(state["nonce"]), bytes.fromhex(ev["nonce"]), bytes.fromhex(state["static"]), bytes.fromhex(ev["peerStatic"]))
        return _pout({"s": "coded", "start": state["start"], "code": code, "mine": None, "theirs": None, **keep}, [{"reveal": state["nonce"]}], "show-code")
    if "user" in ev or "peer" in ev:
        return _answer(state, ev, idle)
    return _pout(state)
EOF
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "# @@RULES" "${TMPDIR:-/tmp}/g20-t4-rules.py"
```

- [ ] **Step 4: Run it to see it pass**

```bash
bash scripts/test-link-contract.sh | grep -v "✓"
bash scripts/test-link-contract.sh | grep -c "✓"
```

Expected: the headings (`pairing-cases.json: the two machines` now among them), the information line, `all link contract checks passed`; and `155`. The 400 simulated pairings give equal codes on both screens and store exactly when both say yes; 400 attempts by a man in the middle with its own nonce and key produce a matching code at most twice; 6000 random event scripts never raise.

- [ ] **Step 5: Prove it bites (a one-off, never committed)**

```bash
cat > "${TMPDIR:-/tmp}/g20-m4.json" <<'EOF'
[
 ["the reveal is not checked against the commitment", "        if commit_of(bytes.fromhex(r[\"nonce\"]), bytes.fromhex(r[\"static\"])).hex() != state[\"commit\"]:", "        if False:"],
 ["a replayed commitment is not noticed", "        if any(e[\"commit\"] == ev[\"commit\"] and pairing_window_open(e[\"at\"], now) for e in state[\"seen\"]):", "        if False:"],
 ["a second attempt is not held back", "        if not pairing_attempt_allowed(state[\"last\"], now):\n            return _pout(idle, because=\"attempt-too-soon\")\n        seen =", "        seen ="],
 ["a reveal with no commitment before it is looked at", "        if state[\"s\"] == \"idle\":\n            return _pout(idle, because=\"no-commit\")                    # a reveal with no commitment before it\n", ""],
 ["a late reveal is accepted", "        if state[\"s\"] != \"committed\":\n            return _pout(idle, because=\"unexpected\")\n        if not pairing_window_open(state[\"start\"], now):\n            return _pout(idle, because=\"reveal-late\")\n", "        if state[\"s\"] != \"committed\":\n            return _pout(idle, because=\"unexpected\")\n"],
 ["the responder's code uses the initiator's nonce twice", "bytes.fromhex(r[\"nonce\"]), bytes.fromhex(state[\"nonce\"]), bytes.fromhex(r[\"static\"])", "bytes.fromhex(r[\"nonce\"]), bytes.fromhex(r[\"nonce\"]), bytes.fromhex(r[\"static\"])"],
 ["an answer that is not exactly yes counts as yes", "    if ans != \"yes\":", "    if ans == \"no\":"],
 ["one yes is enough to store", "    if new[\"mine\"] == \"yes\" and new[\"theirs\"] == \"yes\":", "    if new[\"mine\"] == \"yes\" or new[\"theirs\"] == \"yes\":"],
 ["an answer after the window is taken", "    if not pairing_window_open(state[\"start\"], ev.get(\"now\")):\n        return _pout(idle, notify=\"discard\", because=\"window-closed\")\n", ""],
 ["the initiator accepts a second nonce", "        if state[\"s\"] != \"started\":\n            return _pout(idle, because=\"nonce-repeated\")\n", ""],
 ["the initiator reveals after the window", "        if not pairing_window_open(state[\"start\"], now):\n            return _pout(idle, because=\"reveal-late\")\n        if not (_hex32(ev[\"nonce\"])", "        if not (_hex32(ev[\"nonce\"])"]
]
EOF
python3 -B "${TMPDIR:-/tmp}/g20-mutate.py" "${TMPDIR:-/tmp}/g20-m4.json"
```

Expected: every change fails at least one check or ends in an error, and the numbers are these:

```text
  4 failing  the reveal is not checked against the commitment
  2 failing  a replayed commitment is not noticed
  1 failing  a second attempt is not held back
  1 failing  a reveal with no commitment before it is looked at
  2 failing  a late reveal is accepted
  5 failing  the responder's code uses the initiator's nonce twice
  3 failing  an answer that is not exactly yes counts as yes
  6 failing  one yes is enough to store
  2 failing  an answer after the window is taken
  0 failing and then an error  the initiator accepts a second nonce
  1 failing  the initiator reveals after the window
```


- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
bash scripts/test-link-contract.sh | tail -3
git add tests/fixtures/link/reference.py tests/fixtures/link/build_cases.py tests/fixtures/link/pairing-cases.json
cat > "${TMPDIR:-/tmp}/g20-msg4.txt" <<'EOF'
test(link): the pairing in order: commit, nonce, reveal, confirm, with the cause of every refusal (G2-0)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -q -F "${TMPDIR:-/tmp}/g20-msg4.txt" && git log --oneline -5 && git show --stat --format= HEAD
```

Expected: three files committed.

---

### Task 5: File names: the sanitizer and the collision rule

**Files:**
- Modify: `tests/fixtures/link/build_cases.py`, `tests/fixtures/link/reference.py`
- Create: `tests/fixtures/link/filename-cases.json` (written by the builder)

**Interfaces:**
- Consumes: Task 1's `load`, `check`, the markers (`unicodedata` and `random` are imported by the skeleton).
- Produces: `NAME_BYTES_MAX` (200), `EXT_BYTES_MAX` (16), `COLLISION_MAX` (9999), `BAD_CATEGORIES`, `WIN_ILLEGAL`, `RESERVED`, `_space`, `_trim` (used again by later checks), `sanitize_name(raw)` giving `("ok", name)` or `("reject", "not-text" | "invisible" | "separator" | "empty")`, `unique_name(name, taken)` giving a name or `None`; the fixture `filename-cases.json`: `version`, `bytesMax`, `extBytesMax`, `collisionMax`, `note`, `cases[]` (`name`, `raw`, `out`: `{ok: name}` or `{reject: reason}`), `uniqueCases[]` (`name`, `wanted`, `taken`, `takenNumbered?`, `out`).

The spec says only that names are sanitized ("no path separators, `..`, control characters or reserved Windows names ... length-limited"). The rule here is a split: **reject** what a real sender never sends (a path, a control or invisible character, nothing left), **rewrite** what is a platform difference (Windows-illegal punctuation, trailing dots and spaces, device names, length, normalization). The checks run on the NFC form and on the NFKC form, so a full-width solidus is caught as the `/` it folds to; the kept name is NFC. The order of the checks is: not text, invisible, separator, empty. The category tables come from the language's Unicode data; the cases use only long-assigned characters. These choices are the owner's answers 8 and 9.

- [ ] **Step 1: Add the builder and write the fixture**

```bash
cat > "${TMPDIR:-/tmp}/g20-t5-build.py" <<'EOF'
def filename_cases():
    cases, unique = [], []

    def ok(name, raw, out):
        cases.append({"name": name, "raw": raw, "out": {"ok": out}})

    def no(name, raw, reason):
        cases.append({"name": name, "raw": raw, "out": {"reject": reason}})

    # Names that are fine stay as they are.
    ok("a plain name", "report.pdf", "report.pdf")
    ok("accents, already composed", "r\u00e9sum\u00e9.docx", "r\u00e9sum\u00e9.docx")
    ok("Japanese", "\u65e5\u672c\u8a9e\u306e\u30d5\u30a1\u30a4\u30eb.txt", "\u65e5\u672c\u8a9e\u306e\u30d5\u30a1\u30a4\u30eb.txt")
    ok("an emoji", "\U0001F408.png", "\U0001F408.png")
    ok("a curly apostrophe and spaces inside", "Sam\u2019s  notes v2.txt", "Sam\u2019s  notes v2.txt")
    ok("a dot file", ".bashrc", ".bashrc")
    ok("no extension", "Makefile", "Makefile")
    ok("several dots", "archive.v1.2.3.tar.gz", "archive.v1.2.3.tar.gz")
    ok("two dots inside the name", "a..b", "a..b")
    ok("two dots at the start, then letters: a name, not a way up", "..hidden", "..hidden")
    ok("a dash and a tilde at the start", "-rf~", "-rf~")
    ok("percent signs are not decoded", "%2e%2e%2fetc", "%2e%2e%2fetc")
    ok("shell characters are only characters", "$HOME `id` 100%.txt", "$HOME `id` 100%.txt")
    ok("DIVISION SLASH U+2215 is not a separator (the Finder shows it for /)", "a\u2215b.txt", "a\u2215b.txt")
    ok("COM0, COM10 and CONSOLE are not device names", "COM0", "COM0")
    ok("COM10", "COM10.txt", "COM10.txt")
    ok("CONSOLE", "CONSOLE.txt", "CONSOLE.txt")
    ok("a device name as the extension is only an extension", "a.CON", "a.CON")
    ok("a dot file called .con has an empty stem", ".con", ".con")
    # Path traversal and absolute paths: rejected, never cut down to a last part.
    no("up and out", "../etc/passwd", "separator")
    no("up and out, Windows style", "..\\..\\Windows\\win.ini", "separator")
    no("up in the middle", "a/../../b", "separator")
    no("an absolute path", "/etc/passwd", "separator")
    no("a Windows drive path", "C:\\Windows\\System32\\cmd.exe", "separator")
    no("a UNC path", "\\\\server\\share\\f.txt", "separator")
    no("the home folder", "~/.ssh/authorized_keys", "separator")
    no("dot slash", "./x", "separator")
    no("a folder name with a slash at the end", "dir/", "separator")
    no("a lone backslash", "a\\b", "separator")
    no("a full-width solidus U+FF0F becomes / under NFKC", "\uff0fetc\uff0fpasswd", "separator")
    no("a full-width reverse solidus U+FF3C becomes \\ under NFKC", "a\uff3cb", "separator")
    no("full-width dots, a slash and dots", "\uff0e\uff0e\uff0fx", "separator")
    # Nothing left once trimmed.
    no("an empty name", "", "empty")
    no("one dot", ".", "empty")
    no("two dots", "..", "empty")
    no("three dots", "...", "empty")
    no("dots and spaces", ". . ", "empty")
    no("spaces only", "   ", "empty")
    no("an ideographic space only", "\u3000", "empty")
    no("a no-break space only", "\u00a0", "empty")
    no("full-width dots become .. under NFKC", "\uff0e\uff0e", "empty")
    # Controls, format characters and separators.
    no("a NUL in the middle", "a\x00b.txt", "invisible")
    no("only a NUL", "\x00", "invisible")
    no("a newline", "line\nbreak.txt", "invisible")
    no("a tab", "tab\there", "invisible")
    no("an escape", "esc\x1b[31m.txt", "invisible")
    no("DEL", "a\x7fb", "invisible")
    no("a C1 control, NEL", "a\x85b", "invisible")
    no("a line separator U+2028", "a\u2028b", "invisible")
    no("a paragraph separator U+2029", "a\u2029b", "invisible")
    no("a right-to-left override: invoice[RLO]fdp.exe reads invoiceexe.pdf", "invoice\u202efdp.exe", "invisible")
    no("a left-to-right override", "\u202dx.txt", "invisible")
    no("an isolate, U+2066 and U+2069", "\u2066x\u2069.txt", "invisible")
    no("a left-to-right mark", "a\u200eb", "invisible")
    no("an Arabic letter mark", "\u061cx.txt", "invisible")
    no("a zero-width space", "a\u200bb.txt", "invisible")
    no("a byte order mark at the start", "\ufeffname.txt", "invisible")
    no("a word joiner", "a\u2060b", "invisible")
    no("a zero-width joiner (an emoji family is refused too: the cost of one simple rule)", "a\u200db", "invisible")
    no("a soft hyphen", "a\u00adb", "invisible")
    no("a tag character", "a\U000e0041b", "invisible")
    # Trailing dots and spaces, and spaces at the start.
    ok("a dot at the end goes", "file.txt.", "file.txt")
    ok("a space at the end goes", "file.txt ", "file.txt")
    ok("dots and spaces at the end go", "file.txt . .", "file.txt")
    ok("a space inside stays", "file. txt", "file. txt")
    ok("an ideographic space at the end goes", "trail\u3000", "trail")
    ok("spaces at the start go", "  lead.txt", "lead.txt")
    ok("a dot at the start stays", " .hidden", ".hidden")
    # Windows device names get a _ in front.
    ok("CON", "CON", "_CON")
    ok("con with an extension, any case", "con.txt", "_con.txt")
    ok("Con.tar.gz", "Con.tar.gz", "_Con.tar.gz")
    ok("PRN", "PRN", "_PRN")
    ok("AUX with a dot after a space", "aux .", "_aux")
    ok("NUL.tar.gz", "NUL.tar.gz", "_NUL.tar.gz")
    ok("COM1", "COM1", "_COM1")
    ok("com9.log", "com9.log", "_com9.log")
    ok("lpt9 with a dot at the end", "lpt9.", "_lpt9")
    ok("a space before the dot", "CON .txt", "_CON .txt")
    ok("a superscript digit: COM\u00b9", "COM\u00b9.txt", "_COM\u00b9.txt")
    ok("CONIN$", "CONIN$", "_CONIN$")
    ok("CONOUT$ with an extension", "CONOUT$.log", "_CONOUT$.log")
    ok("full-width letters become CON under NFKC", "\uff23\uff2f\uff2e.txt", "_\uff23\uff2f\uff2e.txt")
    # Characters Windows does not allow, and the alternate data stream.
    ok("a colon", "a:b.txt", "a_b.txt")
    ok("a question mark", "what?.txt", "what_.txt")
    ok("angle brackets", "a<b>c.txt", "a_b_c.txt")
    ok("a quote, a pipe and a star", 'a"b|c*.txt', "a_b_c_.txt")
    ok("an alternate data stream", "file.txt:Zone.Identifier", "file.txt_Zone.Identifier")
    ok("a drive letter without a slash", "C:foo", "C_foo")
    # Normalization: the kept name is NFC, and nothing is folded to NFKC.
    ok("e and a combining acute become one letter", "re\u0301sume\u0301.docx", "r\u00e9sum\u00e9.docx")
    ok("Hangul jamo become a syllable", "\u1100\u1161.txt", "\uac00.txt")
    ok("the angstrom sign becomes the letter", "\u212b.txt", "\u00c5.txt")
    ok("a ligature stays a ligature (NFC, not NFKC)", "\ufb01le.txt", "\ufb01le.txt")
    # Length: 200 bytes of UTF-8, cut at a code point, with the extension kept.
    ok("200 bytes stay", "a" * 200, "a" * 200)
    ok("201 bytes are cut", "a" * 201, "a" * 200)
    ok("a long name keeps its extension", "a" * 300 + ".txt", "a" * 196 + ".txt")
    ok("cats: 70 four-byte emoji are cut to 49 and keep .png", "\U0001F408" * 70 + ".png", "\U0001F408" * 49 + ".png")
    ok("Japanese: 70 three-byte letters are cut to 65 and keep .txt", "\u65e5" * 70 + ".txt", "\u65e5" * 65 + ".txt")
    ok("200 bytes of two-byte letters stay", "\u00e9" * 100, "\u00e9" * 100)
    ok("201 bytes of two-byte letters are cut to 100", "\u00e9" * 100 + "a", "\u00e9" * 100)
    ok("a long extension is not an extension", "a" * 100 + "." + "b" * 150, "a" * 100 + "." + "b" * 99)
    ok("a cut that ends on spaces drops them", "a" * 199 + " " + "b" * 10, "a" * 199)
    ok("a letter with 300 combining marks is cut between marks", "a" + "\u0301" * 300, "\u00e1" + "\u0301" * 99)
    # Not text.
    no("null", None, "not-text")
    no("a number", 5, "not-text")
    no("true", True, "not-text")
    no("a list", ["a"], "not-text")
    no("an object", {"a": 1}, "not-text")

    def free(name, wanted, taken, out, **more):
        unique.append({"name": name, "wanted": wanted, "taken": taken, **more, "out": out})

    free("nothing taken", "a.txt", [], "a.txt")
    free("another name taken", "a.txt", ["b.txt"], "a.txt")
    free("the name is taken", "a.txt", ["a.txt"], "a (1).txt")
    free("1 is taken too", "a.txt", ["a.txt", "a (1).txt"], "a (2).txt")
    free("the smallest free number", "a.txt", ["a.txt", "a (2).txt"], "a (1).txt")
    free("case does not matter", "a.txt", ["A.TXT"], "a (1).txt")
    free("a name that was typed decomposed is the same name", "\u00e9.txt", ["e\u0301.txt"], "\u00e9 (1).txt")
    free("no extension", "notes", ["notes"], "notes (1)")
    free("a dot file", ".bashrc", [".bashrc"], ".bashrc (1)")
    free("only the last extension is kept apart", "a.tar.gz", ["a.tar.gz"], "a.tar (1).gz")
    free("a long extension is not an extension", "a.verylongextensionname", ["a.verylongextensionname"], "a.verylongextensionname (1)")
    free("9999 numbers taken: give up", "a.txt", ["a.txt"], None, takenNumbered={"stem": "a", "ext": ".txt", "from": 1, "to": 9999})
    free("9998 numbers taken: the last one is free", "a.txt", ["a.txt"], "a (9999).txt", takenNumbered={"stem": "a", "ext": ".txt", "from": 1, "to": 9998})
    return {"version": 1, "bytesMax": 200, "extBytesMax": 16, "collisionMax": 9999,
            "note": "cases: raw is the name as sent, out is {ok: the saved name} or {reject: reason}. uniqueCases: taken is the names already in the folder, takenNumbered adds 'stem (n)ext' for n from..to; out is the name to use, or null.",
            "cases": cases, "uniqueCases": unique}
EOF
cat > "${TMPDIR:-/tmp}/g20-t5-files.txt" <<'EOF'
    "filename-cases.json": (filename_cases, False),
EOF
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/build_cases.py "# @@BUILDERS" "${TMPDIR:-/tmp}/g20-t5-build.py"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/build_cases.py "    # @@FILES" "${TMPDIR:-/tmp}/g20-t5-files.txt"
python3 -B tests/fixtures/link/build_cases.py
```

Expected: three `wrote` lines; the last is `wrote filename-cases.json (20927 bytes)`.

- [ ] **Step 2: Add the replay and the fuzz, and run it to see it fail**

```bash
cat > "${TMPDIR:-/tmp}/g20-t5-checks.py" <<'EOF'
def check_filenames():
    print("filename-cases.json")
    f = load("filename-cases.json")
    check("the constants are the ones the rules name", (f["bytesMax"], f["extBytesMax"], f["collisionMax"]), (NAME_BYTES_MAX, EXT_BYTES_MAX, COLLISION_MAX))
    for c in f["cases"]:
        kind, value = sanitize_name(c["raw"])
        check(c["name"], {"ok": value} if kind == "ok" else {"reject": value}, c["out"])
    for c in f["uniqueCases"]:
        taken = list(c["taken"])
        if "takenNumbered" in c:
            t = c["takenNumbered"]
            taken += ["%s (%d)%s" % (t["stem"], n, t["ext"]) for n in range(t["from"], t["to"] + 1)]
        check("a name collision: " + c["name"], unique_name(c["wanted"], taken), c["out"])
    # A seeded fuzz over a hostile alphabet: whatever comes out is a safe name, cleaning it again changes nothing, and a free name is made.
    rnd = random.Random(20261014)
    alphabet = list("ab.. /\\:*?\"<>|~%$") + ["\x00", "\x1f", "\x7f", "\x85", "\u200b", "\u200d", "\u202e", "\u2066", "\ufeff", "\u2028", "\u00a0", "\u3000",
                                              "\uff0e", "\uff0f", "\uff3c", "e\u0301", "\u00e9", "\U0001F408", "\u65e5", "CON", "nul", "COM1", "\u00b9", "\ufb01"]
    bad = None
    for _ in range(6000):
        raw = "".join(rnd.choice(alphabet) for _ in range(rnd.randrange(0, 40))) + rnd.choice(["", ".txt", ".", " ", ".tar.gz"])
        kind, name = sanitize_name(raw)
        if kind != "ok":
            if name not in ("invisible", "separator", "empty"):
                bad = (raw, name)
                break
            continue
        nfkc = unicodedata.normalize("NFKC", name)
        stem = name.split(".", 1)[0].rstrip(" ").upper()
        if (not name or len(name.encode("utf-8")) > NAME_BYTES_MAX or name != unicodedata.normalize("NFC", name)
                or any(ch in "/\\" for ch in name + nfkc) or any(ch in WIN_ILLEGAL for ch in name)
                or any(unicodedata.category(ch) in BAD_CATEGORIES for ch in name)
                or name[-1] in ". " or _space(name[0]) or not _trim(nfkc) or stem in RESERVED or sanitize_name(name) != ("ok", name)
                or len(unique_name(name, [name]).encode("utf-8")) > NAME_BYTES_MAX + 7 or sanitize_name(unique_name(name, [name]))[0] != "ok"):
            bad = (raw, name)
            break
    check("6000 hostile names: what is accepted is NFC, short, free of separators, controls, Windows-illegal characters, trailing dots and device names, and cleaning it again changes nothing", bad, None)
EOF
printf '    check_filenames()\n' > "${TMPDIR:-/tmp}/g20-t5-calls.txt"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "# @@CHECKS" "${TMPDIR:-/tmp}/g20-t5-checks.py"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "    # @@CALLS" "${TMPDIR:-/tmp}/g20-t5-calls.txt"
python3 -B tests/fixtures/link/reference.py 2>&1 | tail -3
```

Expected: a traceback ending `NameError: name 'NAME_BYTES_MAX' is not defined`.

- [ ] **Step 3: Add the rules**

```bash
cat > "${TMPDIR:-/tmp}/g20-t5-rules.py" <<'EOF'
# ---- received file names (Task 5) -----------------------------------------------------------------------------------
NAME_BYTES_MAX = 200                              # UTF-8 bytes of a saved name: room under Windows' 260-character paths, and for " (9999)"
EXT_BYTES_MAX = 16                                # the part after the last dot counts as an extension only up to this long
COLLISION_MAX = 9999
BAD_CATEGORIES = {"Cc", "Cf", "Cs", "Zl", "Zp"}   # controls (NUL, C0, DEL, C1), format characters (bidi controls, zero-width, BOM, soft hyphen), lone surrogates, line and paragraph separators
WIN_ILLEGAL = '<>:"|?*'
RESERVED = ({"CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"} | {"COM%d" % n for n in range(1, 10)} | {"LPT%d" % n for n in range(1, 10)}
            | {"COM\u00b9", "COM\u00b2", "COM\u00b3", "LPT\u00b9", "LPT\u00b2", "LPT\u00b3"})
_ASCII_UPPER = {c: c - 32 for c in range(ord("a"), ord("z") + 1)}


def _space(ch):
    return ch == " " or unicodedata.category(ch) == "Zs"


def _trim(s):
    """Spaces off the start; spaces and dots off the end."""
    start = 0
    while start < len(s) and _space(s[start]):
        start += 1
    s = s[start:]
    while s and (s[-1] == "." or _space(s[-1])):
        s = s[:-1]
    return s


def _reserved(s):
    return s.split(".", 1)[0].rstrip(" ").translate(_ASCII_UPPER) in RESERVED


def _split_ext(name):
    i = name.rfind(".")
    if i > 0 and len(name[i:].encode("utf-8")) <= EXT_BYTES_MAX:
        return name[:i], name[i:]
    return name, ""


def sanitize_name(raw):
    """The name a received file is saved under: ("ok", name) or ("reject", reason).
    Rejected, because a real sender never sends them: not text (not-text), a control, format, surrogate or line-separator character (invisible),
    a / or \\ (separator), and a name that is nothing once spaces and dots are trimmed (empty). The checks run on the NFC form and on the NFKC form,
    so a full-width solidus or full-width dots are caught too; the name that is kept is the NFC form.
    Rewritten, because they are platform differences and not attacks: < > : " | ? * become _, spaces at the start and spaces and dots at the end go,
    a Windows device name (CON, NUL, COM1, ... as the part before the first dot) gets a _ in front, and a name over NAME_BYTES_MAX bytes is cut
    at a code point, keeping an extension of up to EXT_BYTES_MAX bytes."""
    if not isinstance(raw, str):
        return ("reject", "not-text")
    nfc, nfkc = unicodedata.normalize("NFC", raw), unicodedata.normalize("NFKC", raw)
    if any(unicodedata.category(ch) in BAD_CATEGORIES for form in (nfc, nfkc) for ch in form):
        return ("reject", "invisible")
    if any(ch in "/\\" for form in (nfc, nfkc) for ch in form):
        return ("reject", "separator")
    if not _trim(nfc) or not _trim(nfkc):
        return ("reject", "empty")
    name = _trim("".join("_" if ch in WIN_ILLEGAL else ch for ch in nfc))
    probe = _trim("".join("_" if ch in WIN_ILLEGAL else ch for ch in nfkc))
    if not name:
        return ("reject", "empty")
    if _reserved(name) or _reserved(probe):
        name = "_" + name
    if len(name.encode("utf-8")) > NAME_BYTES_MAX:
        stem, ext = _split_ext(name)
        room, out = NAME_BYTES_MAX - len(ext.encode("utf-8")), ""
        for ch in stem:
            if len((out + ch).encode("utf-8")) > room:
                break
            out += ch
        name = _trim(out) + ext
    return ("ok", name)


def _key(name):
    return unicodedata.normalize("NFC", name).casefold()


def unique_name(name, taken):
    """name itself when no taken name equals it, else "stem (n)ext" for the smallest n from 1 that is free; None after COLLISION_MAX tries.
    Names are compared in NFC and case-insensitively, because the Mac's and Windows' usual volumes do."""
    used = {_key(t) for t in taken}
    if _key(name) not in used:
        return name
    stem, ext = _split_ext(name)
    for n in range(1, COLLISION_MAX + 1):
        cand = "%s (%d)%s" % (stem, n, ext)
        if _key(cand) not in used:
            return cand
    return None
EOF
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "# @@RULES" "${TMPDIR:-/tmp}/g20-t5-rules.py"
```

- [ ] **Step 4: Run it to see it pass**

```bash
bash scripts/test-link-contract.sh | grep -v "✓"
bash scripts/test-link-contract.sh | grep -c "✓"
```

Expected: the headings (`filename-cases.json` now among them), the information line, `all link contract checks passed`; and `278`.

- [ ] **Step 5: Prove it bites (a one-off, never committed)**

```bash
cat > "${TMPDIR:-/tmp}/g20-m5.json" <<'EOF'
[
 ["the NFKC form is not looked at", "nfc, nfkc = unicodedata.normalize(\"NFC\", raw), unicodedata.normalize(\"NFKC\", raw)", "nfc = unicodedata.normalize(\"NFC\", raw)\n    nfkc = nfc"],
 ["format characters (bidi, zero-width) are allowed", "BAD_CATEGORIES = {\"Cc\", \"Cf\", \"Cs\", \"Zl\", \"Zp\"}", "BAD_CATEGORIES = {\"Cc\", \"Cs\", \"Zl\", \"Zp\"}"],
 ["a backslash is allowed", "if any(ch in \"/\\\\\" for form in (nfc, nfkc) for ch in form):", "if any(ch in \"/\" for form in (nfc, nfkc) for ch in form):"],
 ["CONIN$ is not a device name", "{\"CON\", \"PRN\", \"AUX\", \"NUL\", \"CONIN$\", \"CONOUT$\"}", "{\"CON\", \"PRN\", \"AUX\", \"NUL\", \"CONOUT$\"}"],
 ["the length limit is 255 bytes", "NAME_BYTES_MAX = 200 ", "NAME_BYTES_MAX = 255 "],
 ["trailing dots stay", "while s and (s[-1] == \".\" or _space(s[-1])):", "while s and _space(s[-1]):"],
 ["a colon stays (an NTFS stream)", "WIN_ILLEGAL = '<>:\"|?*'", "WIN_ILLEGAL = '<>\"|?*'"],
 ["the kept name is NFKC", "name = _trim(\"\".join(\"_\" if ch in WIN_ILLEGAL else ch for ch in nfc))", "name = _trim(\"\".join(\"_\" if ch in WIN_ILLEGAL else ch for ch in nfkc))"],
 ["names are compared with case", "return unicodedata.normalize(\"NFC\", name).casefold()", "return unicodedata.normalize(\"NFC\", name)"],
 ["no extension is ever kept apart", "if i > 0 and len(name[i:].encode(\"utf-8\")) <= EXT_BYTES_MAX:", "if False:"]
]
EOF
python3 -B "${TMPDIR:-/tmp}/g20-mutate.py" "${TMPDIR:-/tmp}/g20-m5.json"
```

Expected: every change fails at least one check or ends in an error, and the numbers are these:

```text
  6 failing  the NFKC form is not looked at
 11 failing  format characters (bidi, zero-width) are allowed
  6 failing  a backslash is allowed
  1 failing  CONIN$ is not a device name
  9 failing  the length limit is 255 bytes
 10 failing  trailing dots stay
  3 failing  a colon stays (an NTFS stream)
  3 failing  the kept name is NFKC
  1 failing  names are compared with case
 11 failing  no extension is ever kept apart
```


- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
bash scripts/test-link-contract.sh | tail -3
git add tests/fixtures/link/reference.py tests/fixtures/link/build_cases.py tests/fixtures/link/filename-cases.json
cat > "${TMPDIR:-/tmp}/g20-msg5.txt" <<'EOF'
test(link): the received file-name sanitizer and the collision rule (G2-0)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -q -F "${TMPDIR:-/tmp}/g20-msg5.txt" && git log --oneline -5 && git show --stat --format= HEAD
```

Expected: three files committed.

---

### Task 6: Wire shapes: records, first record, hello, advert and the six frames

**Files:**
- Modify: `tests/fixtures/link/build_cases.py`, `tests/fixtures/link/reference.py`
- Create: `tests/fixtures/link/frames.json` (written by the builder)

**Interfaces:**
- Consumes: Task 2's `PROTOCOL_VERSION`, `NOISE_MAX`, `TAG`, `x25519_pub` and the `xx-link` vector; Task 3's `commit_of`, `pairing_code` and the `session` of `pairing-cases.json`; Task 5's `BAD_CATEGORIES`; Task 1's `load`, `check`, the markers.
- Produces: `MODE_PAIR` (1), `MODE_TRANSFER` (2), `ID_LEN` (16), `T_OFFER` to `T_CANCEL` (1 to 6), `T_PAIR_YES` (0x21), `T_PAIR_NO` (0x22), `TYPE_NAMES`, `CHUNK_MAX` (65494), `CHUNK_SIZE` (32768), `RAW_NAME_MAX` (1020), `KIND_MAX` (127), `DEVICE_NAME_MAX` (63), `SIZE_MAX` (4294967296), `DECLINE_USER` (0), `DECLINE_TIMEOUT` (1), `DECLINE_BUSY` (2), `DECLINE_TOO_LARGE` (3), `DECLINE_BAD_OFFER` (4), `FrameError(code)` with `.code`, `encode_record(payload)`, `split_records(buf)`, `encode_preamble(mode, device_id)`, `decode_preamble(b)`, `encode_hello(device_id, nonce, name)` (version, device id, a 32-byte nonce, name length, name), `decode_hello(b)` (giving `{id, nonce, name}`), `parse_txt(dict)`, `encode_frame(frame_dict)`, `decode_frame(bytes)`; the fixture `frames.json`: the constants (`noiseMax`, `tag`, `idLen`, `protocolVersion`, `chunkMax`, `chunkSize`, `rawNameMax`, `kindMax`, `deviceNameMax`, `sizeMax`, `types`, `declineReasons`) and `frames[]`, `rejects[]`, `limits[]`, `hello[]`, `txt[]`, `preamble[]`, `records[]`, `recordEncode[]`. Frame dicts: `{type: "offer", id, size, name, kind}`, `{type: "accept"|"done"|"cancel", id}`, `{type: "decline", id, reason}`, `{type: "chunk", id, offset, data}`, with `id` and `data` as lower-case hex, and `{type: "pair-yes"}` and `{type: "pair-no"}` (the type byte alone, no id: the pairing answers). Error codes: `empty`, `unknown-type`, `truncated`, `trailing`, `reason`, `chunk-empty`, `chunk-long`, `name-length`, `utf8`, `kind`, `id`, `length`, `version`, `mode`, `device-id`, `name-chars`, `not-a-record`, `record-empty`, `record-length`.

The layout is this contract's own design (the spec says only "length-prefixed frame encoding"): the full text is in `docs/LINK-CONTRACT.md`, "On the wire", which Task 9 writes. In short: every Noise message travels in a **record** (`u16` length, 1 to 65535); the first record of a connection is an 18-byte preamble (version, mode, device id); pairing's first message carries the initiator's commitment and its messages 2 and 3 a hello (version, device id, nonce, name) each; a transfer's transport messages each carry one frame (a type byte, a 16-byte transfer id, the body), numbers big-endian, and the transport messages after a pairing carry the one-byte `pair-yes` and `pair-no`. The frame hex in the fixture is written out part by part in `build_cases.py` by hand, not by the encoder.

- [ ] **Step 1: Add the builder and write the fixture**

```bash
cat > "${TMPDIR:-/tmp}/g20-t6-build.py" <<'EOF'
ID = "a1" * 16          # a transfer id, as hex
DEV = "b1" * 16         # a device id, as hex


def hx(text):
    return text.encode("utf-8").hex()


def frames_cases():
    ok, bad, hello, txt, pre, rec, recenc, limits = [], [], [], [], [], [], [], []

    def good(name, frame, hexstr):
        ok.append({"name": name, "frame": frame, "hex": hexstr})

    def no(name, hexstr, error):
        bad.append({"name": name, "hex": hexstr, "error": error})

    # The six frames: a type byte, the 16-byte id, the body; numbers big-endian. Written by hand from the layout in docs/LINK-CONTRACT.md.
    good("an offer", {"type": "offer", "id": ID, "size": 1048576, "name": "report.pdf", "kind": "application/pdf"},
         "01" + ID + "0000000000100000" + "000a" + hx("report.pdf") + "0f" + hx("application/pdf"))
    good("an offer of an empty file with no type", {"type": "offer", "id": ID, "size": 0, "name": "a.txt", "kind": ""}, "01" + ID + "0000000000000000" + "0005" + hx("a.txt") + "00")
    good("an offer with an emoji name", {"type": "offer", "id": ID, "size": 7, "name": "\U0001F408.png", "kind": "image/png"},
         "01" + ID + "0000000000000007" + "0008" + hx("\U0001F408.png") + "09" + hx("image/png"))
    good("an offer whose name holds a NUL (a good frame: the sanitizer refuses the name later)", {"type": "offer", "id": ID, "size": 1, "name": "a\x00b", "kind": ""},
         "01" + ID + "0000000000000001" + "0003" + "610062" + "00")
    good("an offer of the largest size a u64 holds (the receiver declines it as too large)", {"type": "offer", "id": ID, "size": 18446744073709551615, "name": "x", "kind": ""},
         "01" + ID + "ffffffffffffffff" + "0001" + "78" + "00")
    good("an offer of 4 GiB and one byte", {"type": "offer", "id": ID, "size": 4294967297, "name": "x", "kind": ""}, "01" + ID + "0000000100000001" + "0001" + "78" + "00")
    good("an offer with a name of 1020 bytes", {"type": "offer", "id": ID, "size": 1, "name": "a" * 1020, "kind": ""}, "01" + ID + "0000000000000001" + "03fc" + "61" * 1020 + "00")
    good("an offer with a type of 127 bytes", {"type": "offer", "id": ID, "size": 1, "name": "x", "kind": "k" * 127}, "01" + ID + "0000000000000001" + "0001" + "78" + "7f" + "6b" * 127)
    good("an accept", {"type": "accept", "id": ID}, "02" + ID)
    for reason, label in enumerate(["the user declined", "nobody answered in 2 minutes", "busy: one transfer per peer", "too large", "the offer was not acceptable"]):
        good("a decline: " + label, {"type": "decline", "id": ID, "reason": reason}, "03" + ID + "%02x" % reason)
    good("a chunk at the start", {"type": "chunk", "id": ID, "offset": 0, "data": hx("hello")}, "04" + ID + "0000000000000000" + hx("hello"))
    good("a chunk at 32768", {"type": "chunk", "id": ID, "offset": 32768, "data": "ab"}, "04" + ID + "0000000000008000" + "ab")
    good("a chunk at the largest offset a u64 holds (the receiver refuses it as out of order)", {"type": "chunk", "id": ID, "offset": 18446744073709551615, "data": "00"},
         "04" + ID + "ffffffffffffffff" + "00")
    good("a done", {"type": "done", "id": ID}, "05" + ID)
    good("a cancel", {"type": "cancel", "id": ID}, "06" + ID)
    good("a pairing answer: they match", {"type": "pair-yes"}, "21")
    good("a pairing answer: they do not match", {"type": "pair-no"}, "22")

    no("no bytes", "", "empty")
    no("type 0", "00" + ID, "unknown-type")
    no("type 7", "07" + ID, "unknown-type")
    no("type 255", "ff" + ID, "unknown-type")
    no("only a type byte", "02", "truncated")
    no("a pair-yes with a byte too many", "2100", "trailing")
    no("a pair-no with a transfer id after it", "22" + ID, "trailing")
    no("type 0x20, just below the pairing answers", "20", "unknown-type")
    no("type 0x23, just above the pairing answers", "23", "unknown-type")
    no("an accept with 15 bytes of id", "02" + "a1" * 15, "truncated")
    no("an accept with a byte too many", "02" + ID + "00", "trailing")
    no("a done with a byte too many", "05" + ID + "00", "trailing")
    no("a cancel with a byte too many", "06" + ID + "00", "trailing")
    no("a decline with no reason", "03" + ID, "truncated")
    no("a decline with reason 5", "03" + ID + "05", "reason")
    no("a decline with reason 255", "03" + ID + "ff", "reason")
    no("a decline with a byte too many", "03" + ID + "0000", "trailing")
    no("a chunk with a short offset", "04" + ID + "00000000000000", "truncated")
    no("a chunk with an offset and no data", "04" + ID + "0000000000000000", "chunk-empty")
    no("an offer with no size", "01" + ID, "truncated")
    no("an offer with 9 bytes after the id", "01" + ID + "000000000000000000", "truncated")
    no("an offer with a name length of 0", "01" + ID + "0000000000000001" + "0000" + "00", "name-length")
    no("an offer with a name length of 1021", "01" + ID + "0000000000000001" + "03fd" + "61" * 1021 + "00", "name-length")
    no("an offer with a name length of 65535", "01" + ID + "0000000000000001" + "ffff", "name-length")
    no("an offer whose name stops short", "01" + ID + "0000000000000001" + "0005" + "616263", "truncated")
    no("an offer with no type length", "01" + ID + "0000000000000001" + "0001" + "78", "truncated")
    no("an offer whose type stops short", "01" + ID + "0000000000000001" + "0001" + "78" + "05" + "616263", "truncated")
    no("an offer with a byte after the type", "01" + ID + "0000000000000001" + "0001" + "78" + "00" + "00", "trailing")
    no("an offer with a type of 128 bytes", "01" + ID + "0000000000000001" + "0001" + "78" + "80" + "6b" * 128, "kind")
    no("an offer with a DEL in the type", "01" + ID + "0000000000000001" + "0001" + "78" + "01" + "7f", "kind")
    no("an offer with a control character in the type", "01" + ID + "0000000000000001" + "0001" + "78" + "01" + "1f", "kind")
    no("an offer with a non-ASCII type", "01" + ID + "0000000000000001" + "0001" + "78" + "02" + "c3a9", "kind")
    no("a name that is not UTF-8: a lone continuation start", "01" + ID + "0000000000000001" + "0002" + "c328" + "00", "utf8")
    no("a name with a UTF-16 surrogate encoded in UTF-8", "01" + ID + "0000000000000001" + "0003" + "eda080" + "00", "utf8")
    no("a name with an overlong slash", "01" + ID + "0000000000000001" + "0002" + "c0af" + "00", "utf8")
    no("a name beyond U+10FFFF", "01" + ID + "0000000000000001" + "0004" + "f4908080" + "00", "utf8")
    no("a name that stops in the middle of a character", "01" + ID + "0000000000000001" + "0002" + "e282" + "00", "utf8")

    # Limits that need long inputs: the reference and the apps build the frame from the recipe. 65494 is the most data in a chunk, so that the frame and the tag fill 65535 bytes.
    for n, out in ((1, "ok"), (65494, "ok"), (65495, "chunk-long")):
        limits.append({"name": "a chunk of %d bytes of data" % n, "id": ID, "offset": 0, "fill": "ab", "count": n, "out": out})

    def h(name, hexstr, out):
        hello.append({"name": name, "hex": hexstr, "out": out})

    def lenhex(text):
        return "%02x" % len(text.encode("utf-8"))

    air = "Sam\u2019s MacBook Air"
    NONCE = "b1" * 32
    h("a hello", "01" + DEV + NONCE + "0a" + hx("Studio Mac"), {"id": DEV, "nonce": NONCE, "name": "Studio Mac"})
    h("a hello with a curly apostrophe", "01" + DEV + NONCE + lenhex(air) + hx(air), {"id": DEV, "nonce": NONCE, "name": air})
    h("a name of 63 bytes", "01" + DEV + NONCE + "3f" + "6e" * 63, {"id": DEV, "nonce": NONCE, "name": "n" * 63})
    h("a name of 64 bytes", "01" + DEV + NONCE + "40" + "6e" * 64, {"error": "name-length"})
    h("an empty name", "01" + DEV + NONCE + "00", {"error": "name-length"})
    h("a hello with no name length", "01" + DEV + NONCE, {"error": "truncated"})
    h("a hello with a nonce of 31 bytes", "01" + DEV + "b1" * 31, {"error": "truncated"})
    h("a name that stops short", "01" + DEV + NONCE + "05" + "616263", {"error": "truncated"})
    h("a byte after the name", "01" + DEV + NONCE + "01" + "6161", {"error": "trailing"})
    h("version 2", "02" + DEV + NONCE + "01" + "61", {"error": "version"})
    h("an all-zero device id", "01" + "00" * 16 + NONCE + "01" + "61", {"error": "device-id"})
    h("a name that is not UTF-8", "01" + DEV + NONCE + "02" + "c328", {"error": "utf8"})
    h("a newline in the name", "01" + DEV + NONCE + "03" + hx("a\nb"), {"error": "name-chars"})
    h("a right-to-left override in the name", "01" + DEV + NONCE + lenhex("a\u202eb") + hx("a\u202eb"), {"error": "name-chars"})
    h("a zero-width space in the name", "01" + DEV + NONCE + lenhex("a\u200bb") + hx("a\u200bb"), {"error": "name-chars"})
    h("a space at the start of the name", "01" + DEV + NONCE + "03" + hx(" ab"), {"error": "name-chars"})
    h("a space at the end of the name", "01" + DEV + NONCE + "03" + hx("ab "), {"error": "name-chars"})

    def t(name, record, out):
        txt.append({"name": name, "txt": record, "out": out})

    good_txt = {"id": "0123456789abcdef0123456789abcdef", "name": "Studio Mac", "v": "1"}
    t("an advert", good_txt, {"id": "0123456789abcdef0123456789abcdef", "name": "Studio Mac"})
    t("other keys are ignored", {**good_txt, "extra": "x", "path": "/etc"}, {"id": "0123456789abcdef0123456789abcdef", "name": "Studio Mac"})
    t("version 2", {**good_txt, "v": "2"}, {"error": "version"})
    t("the version is a number, not text", {**good_txt, "v": 1}, {"error": "version"})
    t("no version", {"id": good_txt["id"], "name": "Studio Mac"}, {"error": "version"})
    t("upper-case hex in the id", {**good_txt, "id": "0123456789ABCDEF0123456789ABCDEF"}, {"error": "device-id"})
    t("an id of 31 digits", {**good_txt, "id": "0123456789abcdef0123456789abcde"}, {"error": "device-id"})
    t("an id that is not hex", {**good_txt, "id": "z123456789abcdef0123456789abcdef"}, {"error": "device-id"})
    t("an all-zero id", {**good_txt, "id": "0" * 32}, {"error": "device-id"})
    t("no id", {"name": "Studio Mac", "v": "1"}, {"error": "device-id"})
    t("no name", {"id": good_txt["id"], "v": "1"}, {"error": "name-length"})
    t("a name of 64 bytes", {**good_txt, "name": "n" * 64}, {"error": "name-length"})
    t("a name with a bidi override", {**good_txt, "name": "a\u202eb"}, {"error": "name-chars"})
    t("a name with a newline", {**good_txt, "name": "a\nb"}, {"error": "name-chars"})
    t("a list is not a record", ["id"], {"error": "not-a-record"})
    t("null is not a record", None, {"error": "not-a-record"})

    def p(name, hexstr, out):
        pre.append({"name": name, "hex": hexstr, "out": out})

    p("a pairing", "0101" + "00" * 16, {"mode": "pair", "id": "00" * 16})
    p("a transfer", "0102" + DEV, {"mode": "transfer", "id": DEV})
    p("version 2", "0201" + "00" * 16, {"error": "version"})
    p("version 0", "0001" + "00" * 16, {"error": "version"})
    p("mode 0", "0100" + DEV, {"error": "mode"})
    p("mode 3", "0103" + DEV, {"error": "mode"})
    p("a pairing that names a device", "0101" + DEV, {"error": "device-id"})
    p("a transfer with no device", "0102" + "00" * 16, {"error": "device-id"})
    p("17 bytes", "0101" + "00" * 15, {"error": "length"})
    p("19 bytes", "0101" + "00" * 17, {"error": "length"})
    p("no bytes", "", {"error": "length"})

    def r(name, stream, out):
        rec.append({"name": name, "hex": stream, "out": out})

    r("nothing yet", "", {"records": [], "rest": ""})
    r("one record", "0003aabbcc", {"records": ["aabbcc"], "rest": ""})
    r("two records in one read", "0001aa0002bbcc", {"records": ["aa", "bbcc"], "rest": ""})
    r("half a length", "00", {"records": [], "rest": "00"})
    r("a length and part of the body", "0005aabb", {"records": [], "rest": "0005aabb"})
    r("a record and the start of the next", "0001aa0003aa", {"records": ["aa"], "rest": "0003aa"})
    r("a record and half a length", "0001aa00", {"records": ["aa"], "rest": "00"})
    r("the largest length, and nothing yet", "ffff", {"records": [], "rest": "ffff"})
    r("a length of 0", "0000", {"error": "record-empty"})
    r("a length of 0 after a good record", "0001aa0000", {"error": "record-empty"})
    for payload, out in (("aa", {"hex": "0001aa"}), ("aabbcc", {"hex": "0003aabbcc"}), ("", {"error": "record-length"})):
        recenc.append({"name": "a record of %d byte(s)" % (len(payload) // 2), "payload": payload, "out": out})
    return {"version": 1,
            "note": "frames: the six frames, decoded and encoded (hex is the plaintext of one transport message). rejects: bytes that must not decode, with the error. limits: a chunk of count bytes of fill. "
                    "hello, txt, preamble, records and recordEncode: the other wire shapes. Strings in hex are bytes; names must be decoded as strict UTF-8 (a decoder that repairs bad bytes is wrong).",
            "noiseMax": 65535, "tag": 16, "idLen": 16, "protocolVersion": 1, "chunkMax": 65494, "chunkSize": 32768, "rawNameMax": 1020, "kindMax": 127, "deviceNameMax": 63, "sizeMax": 4294967296,
            "types": {"offer": 1, "accept": 2, "decline": 3, "chunk": 4, "done": 5, "cancel": 6, "pairYes": 33, "pairNo": 34}, "declineReasons": {"user": 0, "timeout": 1, "busy": 2, "tooLarge": 3, "badOffer": 4},
            "frames": ok, "rejects": bad, "limits": limits, "hello": hello, "txt": txt, "preamble": pre, "records": rec, "recordEncode": recenc}
EOF
cat > "${TMPDIR:-/tmp}/g20-t6-files.txt" <<'EOF'
    "frames.json": (frames_cases, False),
EOF
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/build_cases.py "# @@BUILDERS" "${TMPDIR:-/tmp}/g20-t6-build.py"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/build_cases.py "    # @@FILES" "${TMPDIR:-/tmp}/g20-t6-files.txt"
python3 -B tests/fixtures/link/build_cases.py
```

Expected: four `wrote` lines; the last is `wrote frames.json (24618 bytes)`.

- [ ] **Step 2: Add the replay and the fuzz, and run it to see it fail**

```bash
cat > "${TMPDIR:-/tmp}/g20-t6-checks.py" <<'EOF'
def _err(fn, *args):
    try:
        return fn(*args)
    except FrameError as e:
        return {"error": e.code}


def check_frames():
    print("frames.json")
    f = load("frames.json")
    check("the constants are the ones the rules name", (f["noiseMax"], f["tag"], f["idLen"], f["protocolVersion"], f["chunkMax"], f["chunkSize"], f["rawNameMax"], f["kindMax"], f["deviceNameMax"], f["sizeMax"]),
          (NOISE_MAX, TAG, ID_LEN, PROTOCOL_VERSION, CHUNK_MAX, CHUNK_SIZE, RAW_NAME_MAX, KIND_MAX, DEVICE_NAME_MAX, SIZE_MAX))
    check("the type numbers and decline reasons", (f["types"], f["declineReasons"]),
          ({"offer": T_OFFER, "accept": T_ACCEPT, "decline": T_DECLINE, "chunk": T_CHUNK, "done": T_DONE, "cancel": T_CANCEL, "pairYes": T_PAIR_YES, "pairNo": T_PAIR_NO},
           {"user": DECLINE_USER, "timeout": DECLINE_TIMEOUT, "busy": DECLINE_BUSY, "tooLarge": DECLINE_TOO_LARGE, "badOffer": DECLINE_BAD_OFFER}))
    check("a chunk frame at its largest plus the tag fills one Noise message exactly", 1 + ID_LEN + 8 + CHUNK_MAX + TAG, NOISE_MAX)
    for c in f["frames"]:
        check(c["name"] + ": encode", encode_frame(c["frame"]).hex(), c["hex"])
        check(c["name"] + ": decode", decode_frame(bytes.fromhex(c["hex"])), c["frame"])
    for c in f["rejects"]:
        check(c["name"], _err(decode_frame, bytes.fromhex(c["hex"])), {"error": c["error"]})
    for c in f["limits"]:
        frame = bytes([T_CHUNK]) + bytes.fromhex(c["id"]) + struct.pack(">Q", c["offset"]) + bytes.fromhex(c["fill"]) * c["count"]
        got = _err(decode_frame, frame)
        check(c["name"], "ok" if "type" in got else got["error"], c["out"])
    for c in f["hello"]:
        got = _err(decode_hello, bytes.fromhex(c["hex"]))
        check("hello: " + c["name"], got, c["out"])
        if "error" not in c["out"]:
            check("hello: " + c["name"] + ", encoded again", encode_hello(bytes.fromhex(c["out"]["id"]), bytes.fromhex(c["out"]["nonce"]), c["out"]["name"]).hex(), c["hex"])
    for c in f["txt"]:
        check("advert: " + c["name"], _err(parse_txt, c["txt"]), c["out"])
    for c in f["preamble"]:
        got = _err(decode_preamble, bytes.fromhex(c["hex"]))
        check("first record: " + c["name"], got, c["out"])
        if "error" not in c["out"]:
            check("first record: " + c["name"] + ", encoded again", encode_preamble(MODE_PAIR if got["mode"] == "pair" else MODE_TRANSFER, bytes.fromhex(got["id"])).hex(), c["hex"])
    for c in f["records"]:
        got = _err(split_records, bytes.fromhex(c["hex"]))
        check("records: " + c["name"], got if isinstance(got, dict) else {"records": [r.hex() for r in got[0]], "rest": got[1].hex()}, c["out"])
    for c in f["recordEncode"]:
        got = _err(encode_record, bytes.fromhex(c["payload"]))
        check("record: " + c["name"], {"hex": got.hex()} if isinstance(got, bytes) else got, c["out"])
    # The pairing of the xx-link Noise vector: its first message carries the commitment, its second and third the hellos with the nonces, and the code follows from them.
    p = load("pairing-cases.json")["session"]
    vec = {v["id"]: v for v in load("noise-vectors.json")["vectors"]}[p["vector"]]
    first, second, third = (bytes.fromhex(m["payload"]) for m in vec["messages"][:3])
    hr, hi = decode_hello(second), decode_hello(third)
    check("the xx-link vector's first payload is the initiator's commitment, and its hellos carry the nonces the pairing case names",
          (first.hex(), hi["nonce"], hr["nonce"]), (p["commit"], p["nonceI"], p["nonceR"]))
    check("the commitment is that of the initiator's nonce and of the static key its private key makes", commit_of(bytes.fromhex(hi["nonce"]), x25519_pub(bytes.fromhex(vec["init_static"]))).hex(), p["commit"])
    check("the code of that pairing is the one the case names, from the two nonces and the two static keys",
          pairing_code(bytes.fromhex(hi["nonce"]), bytes.fromhex(hr["nonce"]), x25519_pub(bytes.fromhex(vec["init_static"])), x25519_pub(bytes.fromhex(vec["resp_static"]))), p["code"])
    check("a record of 65535 bytes is made, one of 65536 is not", (len(encode_record(bytes(NOISE_MAX))), _err(encode_record, bytes(NOISE_MAX + 1))), (NOISE_MAX + 2, {"error": "record-length"}))
    # A seeded fuzz: damage valid frames in every way; the decoder raises only FrameError, and what it accepts encodes back to the same bytes.
    rnd = random.Random(20261014)
    seeds = [bytes.fromhex(c["hex"]) for c in f["frames"] if len(c["hex"]) < 400]
    ok, last = True, None
    for _ in range(8000):
        b = bytearray(rnd.choice(seeds))
        for _ in range(rnd.randrange(0, 4)):
            op = rnd.randrange(4)
            if op == 0 and b:
                b[rnd.randrange(len(b))] = rnd.randrange(256)
            elif op == 1 and b:
                del b[rnd.randrange(len(b)):]
            elif op == 2:
                b += bytes(rnd.randrange(256) for _ in range(rnd.randrange(1, 4)))
            elif b:
                b.insert(rnd.randrange(len(b)), rnd.randrange(256))
        try:
            got = decode_frame(bytes(b))
            if encode_frame(got) != bytes(b):
                ok, last = False, bytes(b).hex()
                break
        except FrameError:
            pass
        except Exception as e:                       # noqa: BLE001 - the point is that nothing else is raised
            ok, last = False, (bytes(b).hex(), repr(e))
            break
    check("8000 damaged frames: only FrameError is raised, and every accepted frame encodes back to the same bytes", (ok, last), (True, None))
EOF
printf '    check_frames()\n' > "${TMPDIR:-/tmp}/g20-t6-calls.txt"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "# @@CHECKS" "${TMPDIR:-/tmp}/g20-t6-checks.py"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "    # @@CALLS" "${TMPDIR:-/tmp}/g20-t6-calls.txt"
python3 -B tests/fixtures/link/reference.py 2>&1 | tail -3
```

Expected: a traceback ending `NameError: name 'ID_LEN' is not defined`.

- [ ] **Step 3: Add the rules**

```bash
cat > "${TMPDIR:-/tmp}/g20-t6-rules.py" <<'EOF'
# ---- records, the first record, hello, the advert and the six frames (Task 6) ----------------------------------------
MODE_PAIR, MODE_TRANSFER = 1, 2
ID_LEN = 16
T_OFFER, T_ACCEPT, T_DECLINE, T_CHUNK, T_DONE, T_CANCEL = 1, 2, 3, 4, 5, 6
T_PAIR_YES, T_PAIR_NO = 0x21, 0x22                  # the two pairing answers: a type byte and nothing else
TYPE_NAMES = {T_OFFER: "offer", T_ACCEPT: "accept", T_DECLINE: "decline", T_CHUNK: "chunk", T_DONE: "done", T_CANCEL: "cancel", T_PAIR_YES: "pair-yes", T_PAIR_NO: "pair-no"}
CHUNK_MAX = NOISE_MAX - TAG - 1 - ID_LEN - 8     # 65494: the data in one chunk frame, so that the frame plus the tag fills one Noise message
CHUNK_SIZE = 32768                               # what a sender cuts a file into
RAW_NAME_MAX = 1020                              # bytes of a name on the wire: 255 code points of up to 4 bytes (the sanitizer cuts it to 200)
KIND_MAX = 127                                   # bytes of the file type, printable ASCII, advisory
DEVICE_NAME_MAX = 63                             # bytes of a device name
SIZE_MAX = 4 * 2**30                             # 4 GiB per transfer
DECLINE_USER, DECLINE_TIMEOUT, DECLINE_BUSY, DECLINE_TOO_LARGE, DECLINE_BAD_OFFER = 0, 1, 2, 3, 4


class FrameError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


def encode_record(payload):
    """A record is a u16 big-endian length (1 to 65535) and that many bytes. Every Noise message, handshake or transport, travels in one."""
    if not 1 <= len(payload) <= NOISE_MAX:
        raise FrameError("record-length")
    return struct.pack(">H", len(payload)) + payload


def split_records(buf):
    """(records, rest): the whole records at the start of buf, and the bytes of a record that has not arrived completely. A length of 0 is an error."""
    out, pos = [], 0
    while len(buf) - pos >= 2:
        n = struct.unpack_from(">H", buf, pos)[0]
        if n == 0:
            raise FrameError("record-empty")
        if len(buf) - pos - 2 < n:
            break
        out.append(bytes(buf[pos + 2:pos + 2 + n]))
        pos += 2 + n
    return out, bytes(buf[pos:])


def encode_preamble(mode, device_id):
    """The first record of a connection, in the clear: version, mode (1 pair, 2 transfer), and the sender's device id (16 zero bytes when pairing)."""
    return bytes([PROTOCOL_VERSION, mode]) + device_id


def decode_preamble(b):
    if len(b) != 2 + ID_LEN:
        raise FrameError("length")
    if b[0] != PROTOCOL_VERSION:
        raise FrameError("version")
    if b[1] not in (MODE_PAIR, MODE_TRANSFER):
        raise FrameError("mode")
    if (b[1] == MODE_PAIR) != (b[2:] == bytes(ID_LEN)):
        raise FrameError("device-id")
    return {"mode": "pair" if b[1] == MODE_PAIR else "transfer", "id": b[2:].hex()}


def _device_name(raw):
    """A device name is shown on the pairing card: 1 to 63 bytes of strict UTF-8, no control, format or separator characters, no space at either end."""
    if not 1 <= len(raw) <= DEVICE_NAME_MAX:
        raise FrameError("name-length")
    try:
        s = raw.decode("utf-8")
    except UnicodeDecodeError:
        raise FrameError("utf8")
    if any(unicodedata.category(ch) in BAD_CATEGORIES for ch in s) or s != s.strip():
        raise FrameError("name-chars")
    return s


def encode_hello(device_id, nonce, name):
    """The payload of the second and third pairing messages: version, device id, a 32-byte nonce, name length and name. It is encrypted, so the name on the card is the
    authenticated one. The nonce is the sender's half of the pairing code: the initiator's is its reveal, and it must match the commitment sent in the first message."""
    nb = name.encode("utf-8")
    return bytes([PROTOCOL_VERSION]) + device_id + nonce + bytes([len(nb)]) + nb


def decode_hello(b):
    if len(b) < 2 + ID_LEN + 32:
        raise FrameError("truncated")
    if b[0] != PROTOCOL_VERSION:
        raise FrameError("version")
    if b[1:1 + ID_LEN] == bytes(ID_LEN):
        raise FrameError("device-id")
    nonce, n, body = b[1 + ID_LEN:1 + ID_LEN + 32], b[1 + ID_LEN + 32], b[2 + ID_LEN + 32:]
    if len(body) < n:
        raise FrameError("truncated")
    if len(body) > n:
        raise FrameError("trailing")
    return {"id": b[1:1 + ID_LEN].hex(), "nonce": nonce.hex(), "name": _device_name(body)}


def parse_txt(txt):
    """An advert's TXT record, as a dict of text: {id, name} or a rejection. Anyone on the network can send one, so it is checked like a name on a card.
    v must be the text "1", id 32 lower-case hex digits that are not all zero. Other keys are ignored."""
    if not isinstance(txt, dict):
        raise FrameError("not-a-record")
    v, i, n = txt.get("v"), txt.get("id"), txt.get("name")
    if v != str(PROTOCOL_VERSION):
        raise FrameError("version")
    if not (isinstance(i, str) and len(i) == 2 * ID_LEN and all(c in "0123456789abcdef" for c in i)) or i == "0" * (2 * ID_LEN):
        raise FrameError("device-id")
    if not isinstance(n, str):
        raise FrameError("name-length")
    return {"id": i, "name": _device_name(n.encode("utf-8"))}


def encode_frame(f):
    """A frame is the plaintext of one Noise transport message: a type byte, the 16-byte transfer id, then the body (numbers big-endian); the two pairing answers, `pair-yes` and `pair-no`, are the type byte alone."""
    t = f["type"]
    if t == "pair-yes":
        return bytes([T_PAIR_YES])
    if t == "pair-no":
        return bytes([T_PAIR_NO])
    i = bytes.fromhex(f["id"])
    if len(i) != ID_LEN:
        raise FrameError("id")
    if t == "offer":
        nb, kb = f["name"].encode("utf-8"), f["kind"].encode("ascii")
        return bytes([T_OFFER]) + i + struct.pack(">QH", f["size"], len(nb)) + nb + bytes([len(kb)]) + kb
    if t == "accept":
        return bytes([T_ACCEPT]) + i
    if t == "decline":
        return bytes([T_DECLINE]) + i + bytes([f["reason"]])
    if t == "chunk":
        return bytes([T_CHUNK]) + i + struct.pack(">Q", f["offset"]) + bytes.fromhex(f["data"])
    if t == "done":
        return bytes([T_DONE]) + i
    if t == "cancel":
        return bytes([T_CANCEL]) + i
    raise FrameError("unknown-type")


def decode_frame(b):
    """The frame as a dict, or a FrameError whose code says why. Strict: nothing after the end, UTF-8 without surrogates or overlongs, ASCII for the type."""
    if len(b) == 0:
        raise FrameError("empty")
    t, body = b[0], b[1:]
    if t not in TYPE_NAMES:
        raise FrameError("unknown-type")
    if t in (T_PAIR_YES, T_PAIR_NO):
        if body:
            raise FrameError("trailing")
        return {"type": TYPE_NAMES[t]}
    if len(body) < ID_LEN:
        raise FrameError("truncated")
    f, rest = {"type": TYPE_NAMES[t], "id": body[:ID_LEN].hex()}, body[ID_LEN:]
    if t in (T_ACCEPT, T_DONE, T_CANCEL):
        if rest:
            raise FrameError("trailing")
    elif t == T_DECLINE:
        if len(rest) < 1:
            raise FrameError("truncated")
        if len(rest) > 1:
            raise FrameError("trailing")
        if rest[0] > DECLINE_BAD_OFFER:
            raise FrameError("reason")
        f["reason"] = rest[0]
    elif t == T_CHUNK:
        if len(rest) < 8:
            raise FrameError("truncated")
        data = rest[8:]
        if not data:
            raise FrameError("chunk-empty")
        if len(data) > CHUNK_MAX:
            raise FrameError("chunk-long")
        f["offset"], f["data"] = struct.unpack(">Q", rest[:8])[0], data.hex()
    else:
        if len(rest) < 10:
            raise FrameError("truncated")
        size, n = struct.unpack(">QH", rest[:10])
        if not 1 <= n <= RAW_NAME_MAX:
            raise FrameError("name-length")
        if len(rest) < 10 + n + 1:
            raise FrameError("truncated")
        nb, k, kb = rest[10:10 + n], rest[10 + n], rest[11 + n:]
        if len(kb) < k:
            raise FrameError("truncated")
        if len(kb) > k:
            raise FrameError("trailing")
        if k > KIND_MAX or any(not 0x20 <= c <= 0x7E for c in kb):
            raise FrameError("kind")
        try:
            name = nb.decode("utf-8")
        except UnicodeDecodeError:
            raise FrameError("utf8")
        f.update(size=size, name=name, kind=kb.decode("ascii"))
    return f
EOF
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "# @@RULES" "${TMPDIR:-/tmp}/g20-t6-rules.py"
```

- [ ] **Step 4: Run it to see it pass**

```bash
bash scripts/test-link-contract.sh | grep -v "✓"
bash scripts/test-link-contract.sh | grep -c "✓"
```

Expected: the headings (`frames.json` now among them), the information line, `all link contract checks passed`; and `431`.

- [ ] **Step 5: Prove it bites (a one-off, never committed)**

```bash
cat > "${TMPDIR:-/tmp}/g20-m6.json" <<'EOF'
[
 ["a chunk may carry one byte too many (the limit is off by one)", "CHUNK_MAX = NOISE_MAX - TAG - 1 - ID_LEN - 8 ", "CHUNK_MAX = NOISE_MAX - TAG - 1 - ID_LEN - 7 "],
 ["a name that is not UTF-8 is repaired", "name = nb.decode(\"utf-8\")", "name = nb.decode(\"utf-8\", \"replace\")"],
 ["bytes after an accept are tolerated", "    if t in (T_ACCEPT, T_DONE, T_CANCEL):\n        if rest:\n            raise FrameError(\"trailing\")", "    if t in (T_ACCEPT, T_DONE, T_CANCEL):\n        pass"],
 ["a type may be 255 bytes", "KIND_MAX = 127 ", "KIND_MAX = 255 "],
 ["a record of length 0 is skipped", "        if n == 0:\n            raise FrameError(\"record-empty\")\n", ""],
 ["a decline reason of 5 is accepted", "if rest[0] > DECLINE_BAD_OFFER:", "if rest[0] > 5:"],
 ["a pairing may name a device", "if (b[1] == MODE_PAIR) != (b[2:] == bytes(ID_LEN)):", "if False:"],
 ["an advert with an upper-case id is accepted", "all(c in \"0123456789abcdef\" for c in i)", "all(c in \"0123456789abcdefABCDEF\" for c in i)"],
 ["a device name may start with a space", "or s != s.strip():", ":"],
 ["a hello with a zero device id is accepted", "    if b[1:1 + ID_LEN] == bytes(ID_LEN):\n        raise FrameError(\"device-id\")\n    nonce, n, body", "    nonce, n, body"]
]
EOF
python3 -B "${TMPDIR:-/tmp}/g20-mutate.py" "${TMPDIR:-/tmp}/g20-m6.json"
```

Expected: every change fails at least one check or ends in an error, and the numbers are these:

```text
  3 failing  a chunk may carry one byte too many (the limit is off by one)
  6 failing  a name that is not UTF-8 is repaired
  4 failing  bytes after an accept are tolerated
  2 failing  a type may be 255 bytes
  2 failing  a record of length 0 is skipped
  1 failing  a decline reason of 5 is accepted
  2 failing  a pairing may name a device
  1 failing  an advert with an upper-case id is accepted
  2 failing  a device name may start with a space
  1 failing  a hello with a zero device id is accepted
```


- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
bash scripts/test-link-contract.sh | tail -3
git add tests/fixtures/link/reference.py tests/fixtures/link/build_cases.py tests/fixtures/link/frames.json
cat > "${TMPDIR:-/tmp}/g20-msg6.txt" <<'EOF'
test(link): records, the first record, hello, the advert and the six frames (G2-0)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -q -F "${TMPDIR:-/tmp}/g20-msg6.txt" && git log --oneline -6 && git show --stat --format= HEAD
```

Expected: three files committed.

---

### Task 7: Flow: what each side does with each frame

**Files:**
- Modify: `tests/fixtures/link/build_cases.py`, `tests/fixtures/link/reference.py`
- Create: `tests/fixtures/link/flow-cases.json` (written by the builder)

**Interfaces:**
- Consumes: Task 5's `sanitize_name`; Task 6's `SIZE_MAX`, `CHUNK_SIZE`, `DECLINE_*`; Task 1's `load`, `check`, the markers.
- Produces: `IDLE`, `ABORTS` (`unexpected`, `id`, `order`, `overflow`, `short`), `receiver_step(state, event)`, `sender_step(state, event)`, `plan_chunks(size, chunk_size=32768)`; the fixture `flow-cases.json`: `version`, `chunkSize`, `sizeMax`, `aborts`, `note`, `receiver[]` and `sender[]` of `{name, state, event, out}`, `trips[]` of `{name, side, from, events, out}` and `chunkPlans[]` of `{name, size, chunkSize, out}`. States: `{s: "idle"}`, `{s: "offered", id, size, name}`, `{s: "receiving", id, size, got}` (receiver) and `{s: "offered", id}`, `{s: "sending", id}` (sender). Events: `{frame}`, `{user: "accept"|"decline"|"cancel"}`, `{timeout: true}`. Answer: `{state, send[], notify, abort}`.

This file is a sixth fixture file: the spec lists five for G2-0 and puts the frame encoding in `frames.json`. The receiver's and the sender's rules (the spec's "a tampered, replayed or out-of-order frame aborts the transfer", "one active transfer per peer", "the received byte count must equal the offer") are a different kind of thing from bytes, so they get their own file (the owner's answer 13). The shown name is the sanitized one, so the card and the saved file cannot disagree.

- [ ] **Step 1: Add the builder and write the fixture**

```bash
cat > "${TMPDIR:-/tmp}/g20-t7-build.py" <<'EOF'
ID1 = "01" * 16
ID2 = "02" * 16


def flow_cases():
    rcv, snd, trips, plans = [], [], [], []
    IDLE = {"s": "idle"}

    def offered(i=ID1, size=10, name="a.txt"):
        return {"s": "offered", "id": i, "size": size, "name": name}

    def receiving(got, size=10, i=ID1):
        return {"s": "receiving", "id": i, "size": size, "got": got}

    def offer(i=ID1, size=10, name="a.txt"):
        return {"frame": {"type": "offer", "id": i, "size": size, "name": name, "kind": ""}}

    def chunk(offset, n, i=ID1):
        return {"frame": {"type": "chunk", "id": i, "offset": offset, "data": "ab" * n}}

    def frame(t, i=ID1, **more):
        return {"frame": {"type": t, "id": i, **more}}

    def out(state, send=(), notify=None, abort=None):
        return {"state": state, "send": list(send), "notify": notify, "abort": abort}

    def decline(i, reason):
        return {"type": "decline", "id": i, "reason": reason}

    def r(name, state, event, want):
        rcv.append({"name": name, "state": state, "event": event, "out": want})

    # Offers. The name that is shown is the one that is saved; a size over 4 GiB or a bad name is declined without bothering the user.
    r("an offer: the card is shown", IDLE, offer(), out(offered(), notify="offer"))
    r("the card shows the sanitized name", IDLE, offer(name="a:b.txt"), out(offered(name="a_b.txt"), notify="offer"))
    r("an empty file is offered", IDLE, offer(size=0), out(offered(size=0), notify="offer"))
    r("exactly 4 GiB is offered", IDLE, offer(size=4294967296), out(offered(size=4294967296), notify="offer"))
    r("4 GiB and a byte is declined as too large", IDLE, offer(size=4294967297), out(IDLE, [decline(ID1, 3)]))
    r("a name with a path is declined as a bad offer", IDLE, offer(name="../x"), out(IDLE, [decline(ID1, 4)]))
    r("a name with a NUL is declined as a bad offer", IDLE, offer(name="a\x00b"), out(IDLE, [decline(ID1, 4)]))
    r("a second offer while one waits is declined as busy", offered(), offer(i=ID2), out(offered(), [decline(ID2, 2)]))
    r("a second offer during a transfer is declined as busy", receiving(4), offer(i=ID2), out(receiving(4), [decline(ID2, 2)]))
    r("the same offer again during a transfer is declined as busy", receiving(4), offer(), out(receiving(4), [decline(ID1, 2)]))
    # The user.
    r("accept: the transfer starts and an accept goes out", offered(), {"user": "accept"}, out(receiving(0), [{"type": "accept", "id": ID1}]))
    r("decline: back to idle with a decline", offered(), {"user": "decline"}, out(IDLE, [decline(ID1, 0)]))
    r("nobody answers: declined as timed out", offered(), {"timeout": True}, out(IDLE, [decline(ID1, 1)], notify="expired"))
    r("a click on accept with nothing offered does nothing", IDLE, {"user": "accept"}, out(IDLE))
    r("a timeout with nothing offered does nothing", IDLE, {"timeout": True}, out(IDLE))
    r("a timeout during a transfer does nothing", receiving(3), {"timeout": True}, out(receiving(3)))
    r("cancel by the user during a transfer", receiving(3), {"user": "cancel"}, out(IDLE, [{"type": "cancel", "id": ID1}], notify="cancelled"))
    r("a click on accept during a transfer does nothing", receiving(3), {"user": "accept"}, out(receiving(3)))
    # The sender's frames.
    r("the sender withdraws an offer", offered(), frame("cancel"), out(IDLE, notify="withdrawn"))
    r("a cancel for another transfer is ignored", offered(), frame("cancel", ID2), out(offered()))
    r("a cancel with nothing going on is ignored", IDLE, frame("cancel"), out(IDLE))
    r("the sender cancels during a transfer", receiving(5), frame("cancel"), out(IDLE, notify="cancelled"))
    r("a cancel for another transfer during a transfer is ignored", receiving(5), frame("cancel", ID2), out(receiving(5)))
    r("data before the user accepted: closed", offered(), chunk(0, 1), out(IDLE, abort="unexpected"))
    r("done before the user accepted: closed", offered(), frame("done"), out(IDLE, abort="unexpected"))
    r("an accept from the sender: closed", offered(), frame("accept"), out(IDLE, abort="unexpected"))
    r("a chunk with nothing going on: closed", IDLE, chunk(0, 1), out(IDLE, abort="unexpected"))
    r("a done with nothing going on: closed", IDLE, frame("done"), out(IDLE, abort="unexpected"))
    r("an accept with nothing going on: closed", IDLE, frame("accept"), out(IDLE, abort="unexpected"))
    r("a decline with nothing going on: closed", IDLE, frame("decline", reason=0), out(IDLE, abort="unexpected"))
    r("a pairing answer during a transfer: closed", receiving(5), {"frame": {"type": "pair-yes"}}, out(IDLE, abort="unexpected"))
    r("a pairing answer with nothing going on: closed", IDLE, {"frame": {"type": "pair-no"}}, out(IDLE, abort="unexpected"))
    r("an accept during a transfer: closed", receiving(5), frame("accept"), out(IDLE, abort="unexpected"))
    r("a decline during a transfer: closed", receiving(5), frame("decline", reason=0), out(IDLE, abort="unexpected"))
    # Chunks: where the last one ended, never past the size.
    r("the first chunk", receiving(0), chunk(0, 4), out(receiving(4)))
    r("the next chunk", receiving(4), chunk(4, 4), out(receiving(8)))
    r("the last chunk reaches the size exactly", receiving(8), chunk(8, 2), out(receiving(10)))
    r("a replayed chunk: closed", receiving(4), chunk(0, 4), out(IDLE, abort="order"))
    r("the same chunk twice: closed", receiving(8), chunk(4, 4), out(IDLE, abort="order"))
    r("a skipped chunk: closed", receiving(4), chunk(8, 2), out(IDLE, abort="order"))
    r("a chunk past the size: closed", receiving(8), chunk(8, 3), out(IDLE, abort="overflow"))
    r("a chunk after the size is reached: closed", receiving(10), chunk(10, 1), out(IDLE, abort="overflow"))
    r("any chunk of an empty file: closed", receiving(0, size=0), chunk(0, 1), out(IDLE, abort="overflow"))
    r("a chunk of another transfer: closed", receiving(4), chunk(4, 4, ID2), out(IDLE, abort="id"))
    r("a done of another transfer: closed", receiving(10), frame("done", ID2), out(IDLE, abort="id"))
    r("done with every byte: the file is complete", receiving(10), frame("done"), out(IDLE, notify="complete"))
    r("done of an empty file", receiving(0, size=0), frame("done"), out(IDLE, notify="complete"))
    r("done one byte short: closed", receiving(9), frame("done"), out(IDLE, abort="short"))
    r("done at the start: closed", receiving(0), frame("done"), out(IDLE, abort="short"))

    def s(name, state, event, want):
        snd.append({"name": name, "state": state, "event": event, "out": want})

    SO, SS = {"s": "offered", "id": ID1}, {"s": "sending", "id": ID1}
    s("the receiver accepts", SO, frame("accept"), out(SS))
    s("the receiver accepts another transfer: closed", SO, frame("accept", ID2), out(IDLE, abort="id"))
    s("the receiver declines", SO, frame("decline", reason=0), out(IDLE, notify="declined"))
    s("the receiver declines another transfer: closed", SO, frame("decline", ID2, reason=0), out(IDLE, abort="id"))
    s("the receiver cancels before accepting", SO, frame("cancel"), out(IDLE, notify="cancelled"))
    s("the receiver sends data: closed", SO, chunk(0, 1), out(IDLE, abort="unexpected"))
    s("the receiver sends an offer: closed", SO, offer(), out(IDLE, abort="unexpected"))
    s("a pairing answer during the transfer: closed", SS, {"frame": {"type": "pair-yes"}}, out(IDLE, abort="unexpected"))
    s("an accept with nothing offered: closed", IDLE, frame("accept"), out(IDLE, abort="unexpected"))
    s("the receiver cancels during the transfer", SS, frame("cancel"), out(IDLE, notify="cancelled"))
    s("a second accept: closed", SS, frame("accept"), out(IDLE, abort="unexpected"))
    s("a decline during the transfer: closed", SS, frame("decline", reason=0), out(IDLE, abort="unexpected"))
    s("the user cancels an offer", SO, {"user": "cancel"}, out(IDLE, [{"type": "cancel", "id": ID1}], notify="cancelled"))
    s("the user cancels the transfer", SS, {"user": "cancel"}, out(IDLE, [{"type": "cancel", "id": ID1}], notify="cancelled"))
    s("the user cancels with nothing going on", IDLE, {"user": "cancel"}, out(IDLE))

    def trip(name, side, events, outs, start=IDLE):
        trips.append({"name": name, "side": side, "from": start, "events": events, "out": outs})

    # Whole transfers: the state after each event is the one before the next.
    trip("a transfer of 10 bytes in three chunks", "receiver", [offer(), {"user": "accept"}, chunk(0, 4), chunk(4, 4), chunk(8, 2), frame("done")],
         [out(offered(), notify="offer"), out(receiving(0), [{"type": "accept", "id": ID1}]), out(receiving(4)), out(receiving(8)), out(receiving(10)), out(IDLE, notify="complete")])
    trip("the second chunk is sent twice", "receiver", [offer(), {"user": "accept"}, chunk(0, 4), chunk(4, 4), chunk(4, 4)],
         [out(offered(), notify="offer"), out(receiving(0), [{"type": "accept", "id": ID1}]), out(receiving(4)), out(receiving(8)), out(IDLE, abort="order")])
    trip("the first chunk is lost and the second arrives", "receiver", [offer(), {"user": "accept"}, chunk(4, 4)],
         [out(offered(), notify="offer"), out(receiving(0), [{"type": "accept", "id": ID1}]), out(IDLE, abort="order")])
    trip("the sender stops one byte early", "receiver", [offer(), {"user": "accept"}, chunk(0, 9), frame("done")],
         [out(offered(), notify="offer"), out(receiving(0), [{"type": "accept", "id": ID1}]), out(receiving(9)), out(IDLE, abort="short")])
    trip("an offer nobody answers, then a new one", "receiver", [offer(), {"timeout": True}, offer(i=ID2)],
         [out(offered(), notify="offer"), out(IDLE, [decline(ID1, 1)], notify="expired"), out(offered(i=ID2), notify="offer")])
    trip("the user cancels half way and the sender's last chunk is already on its way", "receiver", [offer(), {"user": "accept"}, chunk(0, 4), {"user": "cancel"}, chunk(4, 4)],
         [out(offered(), notify="offer"), out(receiving(0), [{"type": "accept", "id": ID1}]), out(receiving(4)), out(IDLE, [{"type": "cancel", "id": ID1}], notify="cancelled"), out(IDLE, abort="unexpected")])
    trip("the offer is sent, the receiver accepts, then cancels", "sender", [frame("accept"), frame("cancel")], [out(SS), out(IDLE, notify="cancelled")], start=SO)

    def plan(name, size, chunk_size, want):
        plans.append({"name": name, "size": size, "chunkSize": chunk_size, "out": want})

    plan("an empty file has no chunks", 0, 4, [])
    plan("one byte", 1, 4, [[0, 1]])
    plan("an exact multiple", 8, 4, [[0, 4], [4, 4]])
    plan("a remainder", 10, 4, [[0, 4], [4, 4], [8, 2]])
    plan("a size one over the chunk", 5, 4, [[0, 4], [4, 1]])
    plan("the real chunk size and one byte more", 32769, 32768, [[0, 32768], [32768, 1]])
    plan("two real chunks exactly", 65536, 32768, [[0, 32768], [32768, 32768]])
    return {"version": 1, "chunkSize": 32768, "sizeMax": 4294967296, "aborts": ["unexpected", "id", "order", "overflow", "short"],
            "note": "receiver and sender: receiver_step / sender_step of reference.py, one event at a time ({state, event} -> out). A frame in an event is a decoded frame as in frames.json. "
                    "trips: the same over a script, starting from `from`; out holds the result after each event, the state of one being the state the next starts from. chunkPlans: the offsets and lengths a sender cuts a file into.",
            "receiver": rcv, "sender": snd, "trips": trips, "chunkPlans": plans}
EOF
cat > "${TMPDIR:-/tmp}/g20-t7-files.txt" <<'EOF'
    "flow-cases.json": (flow_cases, False),
EOF
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/build_cases.py "# @@BUILDERS" "${TMPDIR:-/tmp}/g20-t7-build.py"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/build_cases.py "    # @@FILES" "${TMPDIR:-/tmp}/g20-t7-files.txt"
python3 -B tests/fixtures/link/build_cases.py
```

Expected: five `wrote` lines; the last is `wrote flow-cases.json (28775 bytes)`.

- [ ] **Step 2: Add the replay and the fuzz, and run it to see it fail**

```bash
cat > "${TMPDIR:-/tmp}/g20-t7-checks.py" <<'EOF'
def check_flow():
    print("flow-cases.json")
    f = load("flow-cases.json")
    check("the constants are the ones the rules name", (f["chunkSize"], f["sizeMax"], f["aborts"]), (CHUNK_SIZE, SIZE_MAX, list(ABORTS)))
    for c in f["receiver"]:
        check("receiver: " + c["name"], receiver_step(c["state"], c["event"]), c["out"])
    for c in f["sender"]:
        check("sender: " + c["name"], sender_step(c["state"], c["event"]), c["out"])
    for c in f["trips"]:
        step = receiver_step if c["side"] == "receiver" else sender_step
        state, got = c["from"], []
        for ev in c["events"]:
            res = step(state, ev)
            got.append(res)
            state = res["state"]
        check("trip: " + c["name"], got, c["out"])
    for c in f["chunkPlans"]:
        check("chunks: " + c["name"], [list(x) for x in plan_chunks(c["size"], c["chunkSize"])], c["out"])
    # A seeded fuzz: random events from every state. Nothing raises, the received count never passes the size, an abort always lands in idle, only a click starts a transfer.
    rnd = random.Random(20261014)
    ids = ["01" * 16, "02" * 16]
    ok, last = True, None
    for _ in range(3000):
        state = {"s": "idle"}
        for _ in range(rnd.randrange(1, 30)):
            i = rnd.choice(ids)
            ev = rnd.choice([
                {"frame": {"type": "offer", "id": i, "size": rnd.choice([0, 5, 10, 2**32, 2**32 + 1]), "name": rnd.choice(["a.txt", "../x", "CON", "a\x00"]), "kind": ""}},
                {"frame": {"type": "chunk", "id": i, "offset": rnd.choice([0, 2, 4, 6, 8, 10]), "data": "ab" * rnd.randrange(1, 5)}},
                {"frame": {"type": rnd.choice(["done", "cancel", "accept"]), "id": i}},
                {"frame": {"type": "decline", "id": i, "reason": 0}},
                {"user": rnd.choice(["accept", "decline", "cancel"])}, {"timeout": True}])
            before = state
            res = receiver_step(state, ev)
            state = res["state"]
            if (res["abort"] is not None and (res["abort"] not in ABORTS or state != {"s": "idle"})
                    or (state["s"] == "receiving" and state["got"] > state["size"])
                    or (state["s"] == "receiving" and before["s"] != "receiving" and ev != {"user": "accept"})):
                ok, last = False, (before, ev, res)
                break
        if not ok:
            break
    check("3000 random event scripts: nothing raises, the count never passes the size, an abort lands in idle, only a click starts a transfer", (ok, last), (True, None))
EOF
printf '    check_flow()\n' > "${TMPDIR:-/tmp}/g20-t7-calls.txt"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "# @@CHECKS" "${TMPDIR:-/tmp}/g20-t7-checks.py"
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "    # @@CALLS" "${TMPDIR:-/tmp}/g20-t7-calls.txt"
python3 -B tests/fixtures/link/reference.py 2>&1 | tail -3
```

Expected: a traceback ending `NameError: name 'ABORTS' is not defined`.

- [ ] **Step 3: Add the rules**

```bash
cat > "${TMPDIR:-/tmp}/g20-t7-rules.py" <<'EOF'
# ---- what each side does with the frames it gets (Task 7) --------------------------------------------------------------
IDLE = {"s": "idle"}
ABORTS = ("unexpected", "id", "order", "overflow", "short")      # the reasons a connection is closed


def _out(state, send=(), notify=None, abort=None):
    return {"state": state, "send": list(send), "notify": notify, "abort": abort}


def receiver_step(state, ev):
    """The receiving side of one connection, one event at a time.
    state: {"s": "idle"} | {"s": "offered", id, size, name} | {"s": "receiving", id, size, got}  (name is the sanitized name, the one that is shown and saved).
    ev: {"frame": a decoded frame} | {"user": "accept" | "decline" | "cancel"} | {"timeout": true}.
    Returns {state, send: the frames to send, notify: what to tell the user (offer, expired, withdrawn, cancelled, complete) or None,
    abort: why the connection must close (one of ABORTS) or None; after an abort the state is idle}.
    Only a click moves offered to receiving. One transfer at a time. A chunk must start exactly where the last one ended and may not pass the size,
    and done is good only when every byte has come."""
    s = state["s"]
    if "user" in ev:
        u = ev["user"]
        if s == "offered" and u == "accept":
            return _out({"s": "receiving", "id": state["id"], "size": state["size"], "got": 0}, [{"type": "accept", "id": state["id"]}])
        if s == "offered" and u == "decline":
            return _out(IDLE, [{"type": "decline", "id": state["id"], "reason": DECLINE_USER}])
        if s == "receiving" and u in ("cancel", "decline"):
            return _out(IDLE, [{"type": "cancel", "id": state["id"]}], "cancelled")
        return _out(state)
    if ev.get("timeout"):
        if s == "offered":
            return _out(IDLE, [{"type": "decline", "id": state["id"], "reason": DECLINE_TIMEOUT}], "expired")
        return _out(state)
    f = ev["frame"]
    t = f["type"]
    if t.startswith("pair-"):
        return _out(IDLE, abort="unexpected")                       # a pairing answer has no place in a transfer
    if t == "offer":
        if s != "idle":
            return _out(state, [{"type": "decline", "id": f["id"], "reason": DECLINE_BUSY}])
        if f["size"] > SIZE_MAX:
            return _out(IDLE, [{"type": "decline", "id": f["id"], "reason": DECLINE_TOO_LARGE}])
        kind, name = sanitize_name(f["name"])
        if kind != "ok":
            return _out(IDLE, [{"type": "decline", "id": f["id"], "reason": DECLINE_BAD_OFFER}])
        return _out({"s": "offered", "id": f["id"], "size": f["size"], "name": name}, [], "offer")
    if t == "cancel":
        if s != "idle" and f["id"] == state["id"]:
            return _out(IDLE, [], "withdrawn" if s == "offered" else "cancelled")
        return _out(state)                                          # a cancel for a transfer we do not know is harmless
    if s == "receiving" and t in ("chunk", "done"):
        if f["id"] != state["id"]:
            return _out(IDLE, abort="id")
        if t == "chunk":
            if f["offset"] != state["got"]:
                return _out(IDLE, abort="order")                    # a replayed chunk or a skipped one
            if state["got"] + len(f["data"]) // 2 > state["size"]:
                return _out(IDLE, abort="overflow")
            return _out({**state, "got": state["got"] + len(f["data"]) // 2})
        if state["got"] != state["size"]:
            return _out(IDLE, abort="short")
        return _out(IDLE, [], "complete")
    return _out(IDLE, abort="unexpected")


def sender_step(state, ev):
    """The sending side. state: {"s": "idle"} | {"s": "offered", id} | {"s": "sending", id}. ev: {"frame": ...} | {"user": "cancel"}.
    Returns the same shape as receiver_step (notify: declined, cancelled)."""
    s = state["s"]
    if "user" in ev:
        if s in ("offered", "sending") and ev["user"] == "cancel":
            return _out(IDLE, [{"type": "cancel", "id": state["id"]}], "cancelled")
        return _out(state)
    f = ev["frame"]
    t = f["type"]
    if s == "idle" or t in ("offer", "chunk", "done") or t.startswith("pair-"):
        return _out(IDLE, abort="unexpected")
    if f["id"] != state["id"]:
        return _out(IDLE, abort="id")
    if s == "offered" and t == "accept":
        return _out({"s": "sending", "id": state["id"]})
    if s == "offered" and t == "decline":
        return _out(IDLE, [], "declined")
    if t == "cancel":
        return _out(IDLE, [], "cancelled")
    return _out(IDLE, abort="unexpected")


def plan_chunks(size, chunk_size=CHUNK_SIZE):
    """[(offset, length)] that cover size bytes; an empty file has none, and then the sender goes straight to done."""
    return [(o, min(chunk_size, size - o)) for o in range(0, size, chunk_size)]
EOF
python3 "${TMPDIR:-/tmp}/g20-insert.py" tests/fixtures/link/reference.py "# @@RULES" "${TMPDIR:-/tmp}/g20-t7-rules.py"
```

- [ ] **Step 4: Run it to see it pass**

```bash
bash scripts/test-link-contract.sh | grep -v "✓"
bash scripts/test-link-contract.sh | grep -c "✓"
```

Expected: the headings (`flow-cases.json` last), the information line, `all link contract checks passed`; and `512`.

- [ ] **Step 5: Prove it bites (a one-off, never committed)**

```bash
cat > "${TMPDIR:-/tmp}/g20-m7.json" <<'EOF'
[
 ["a replayed or skipped chunk is accepted", "            if f[\"offset\"] != state[\"got\"]:\n                return _out(IDLE, abort=\"order\")                    # a replayed chunk or a skipped one\n", ""],
 ["a chunk may pass the offered size", "            if state[\"got\"] + len(f[\"data\"]) // 2 > state[\"size\"]:\n                return _out(IDLE, abort=\"overflow\")\n", ""],
 ["done is good one byte short", "        if state[\"got\"] != state[\"size\"]:\n            return _out(IDLE, abort=\"short\")\n", ""],
 ["a second offer is not declined as busy", "        if s != \"idle\":\n            return _out(state, [{\"type\": \"decline\", \"id\": f[\"id\"], \"reason\": DECLINE_BUSY}])\n", ""],
 ["exactly 4 GiB is too large", "if f[\"size\"] > SIZE_MAX:", "if f[\"size\"] >= SIZE_MAX:"],
 ["a bad name still gets a card", "        if kind != \"ok\":\n            return _out(IDLE, [{\"type\": \"decline\", \"id\": f[\"id\"], \"reason\": DECLINE_BAD_OFFER}])\n", ""],
 ["the card shows the raw name", "return _out({\"s\": \"offered\", \"id\": f[\"id\"], \"size\": f[\"size\"], \"name\": name}, [], \"offer\")", "return _out({\"s\": \"offered\", \"id\": f[\"id\"], \"size\": f[\"size\"], \"name\": f[\"name\"]}, [], \"offer\")"],
 ["a chunk of another transfer is counted", "        if f[\"id\"] != state[\"id\"]:\n            return _out(IDLE, abort=\"id\")\n        if t == \"chunk\":", "        if t == \"chunk\":"],
 ["an accept from the sender starts the transfer without a click", "    if s == \"receiving\" and t in (\"chunk\", \"done\"):", "    if t == \"accept\" and s == \"offered\":\n        return _out({\"s\": \"receiving\", \"id\": state[\"id\"], \"size\": state[\"size\"], \"got\": 0})\n    if s == \"receiving\" and t in (\"chunk\", \"done\"):"],
 ["a cancel for another transfer ends this one", "        if s != \"idle\" and f[\"id\"] == state[\"id\"]:\n            return _out(IDLE, [], \"withdrawn\" if s == \"offered\" else \"cancelled\")", "        if s != \"idle\":\n            return _out(IDLE, [], \"withdrawn\" if s == \"offered\" else \"cancelled\")"]
]
EOF
python3 -B "${TMPDIR:-/tmp}/g20-mutate.py" "${TMPDIR:-/tmp}/g20-m7.json"
```

Expected: every change fails at least one check or ends in an error, and the numbers are these:

```text
  5 failing  a replayed or skipped chunk is accepted
  3 failing  a chunk may pass the offered size
  3 failing  done is good one byte short
  3 failing  a second offer is not declined as busy
  1 failing  exactly 4 GiB is too large
  2 failing  a bad name still gets a card
  1 failing  the card shows the raw name
  2 failing  a chunk of another transfer is counted
  2 failing  an accept from the sender starts the transfer without a click
  2 failing  a cancel for another transfer ends this one
```


- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
bash scripts/test-link-contract.sh | tail -3
git add tests/fixtures/link/reference.py tests/fixtures/link/build_cases.py tests/fixtures/link/flow-cases.json
cat > "${TMPDIR:-/tmp}/g20-msg7.txt" <<'EOF'
test(link): what the receiver and the sender do with each frame (G2-0)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -q -F "${TMPDIR:-/tmp}/g20-msg7.txt" && git log --oneline -7 && git show --stat --format= HEAD
```

Expected: three files committed.

---

### Task 8: The `transferOffer` flag in `cat-core.js`

**Files:**
- Modify: `design/prototype/cat-core.js` (the `desktopAlert` rule), `scripts/gen-cat-fixtures.mjs` (new keys and trips above the `@@DESKTOP-SECTIONS` marker), `docs/CAT-CONTRACT.md` (a section and a table row)
- Create: `tests/cat/desktop-offer.test.mjs`
- Regenerate: `tests/fixtures/cat/desktop-cases.json` (by `node scripts/gen-cat-fixtures.mjs`, never by hand)

**Interfaces:**
- Consumes: the cat contract as it is (`desktopAlert`, `desktopStep`, `trip` and `evOf` in the generator).
- Produces: `desktopAlert({..., transferOffer})` true when `transferOffer` is exactly `true`; in `desktop-cases.json` the new keys `offerNote` and `offerCases` (13 rows of `{name, input, out}`) and three new `trips` rows named "a transfer offer: ..." at the end; **`alertCases`, `note` and `catchNote` unchanged**.

The spec: an incoming transfer offer "is an alert like an approval: it opens the island even when hidden, holds it open, and the desktop cat flies to the notch for it. Nothing accepts it except a click." In `cat-core.js` terms it is `alertOn` and `alertOff` to `desktopStep` again, so there is no new phase, event or act. **Why `offerCases` and not new rows in `alertCases`:** the Mac replays `alertCases` through `DesktopCatTrip.alert(raw:)` (`tests/DesktopCatTripTests.swift`) and Windows/Linux through their TypeScript twin; a row with `transferOffer: true` would turn both red until the G2 app plans learn the flag. New keys and new trip rows keep every replay that runs today green, and the G2 plans adopt `offerCases`. `scripts/check-fixtures-additive.mjs 1627851` (the base the brief names) treats `desktop-cases.json` as a new file, because the file did not exist at that commit, and so proves nothing about it: the real proof is the same check against `HEAD` before the commit and against `notchmeow/rebrand` after it.

- [ ] **Step 1: Write the Node test and see it fail**

```bash
cat > tests/cat/desktop-offer.test.mjs <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';

// The incoming transfer offer (G2-0): a card from another machine is an alert to the desktop cat, like an approval. One flag, no new phase, event or act.
// docs/CAT-CONTRACT.md, "The transfer offer".
const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/desktop-cases.json', import.meta.url), 'utf8'));

test('desktopAlert: transferOffer counts only when it is exactly true', () => {
  const a = core.desktopAlert;
  assert.equal(a({ transferOffer: true }), true);
  assert.equal(a({ transferOffer: true, fileCatch: true }), true);
  for (const v of [false, 'true', 1, null, [true], {}, undefined]) assert.equal(a({ transferOffer: v }), false, JSON.stringify(v));
  for (const k of ['offer', 'transfer', 'transfer_offer', 'TransferOffer', 'transferOffers']) assert.equal(a({ [k]: true }), false, k);
});

test('the other alerts still count, and input that is not an object is still no alert', () => {
  const a = core.desktopAlert;
  for (const k of ['approval', 'question', 'chatApproval', 'fileCatch']) assert.equal(a({ [k]: true }), true, k);
  assert.equal(a({ pillStates: ['approval'] }), true);
  for (const v of [null, undefined, 'transferOffer', 1, true, [true]]) assert.equal(a(v), false, String(v));
});

test('a transfer offer adds no phase, event or act, and the older alert rows stand untouched', () => {
  assert.equal(core.DESKTOP_PHASES.length, 7);
  assert.equal(core.DESKTOP_EVENTS.length, 9);
  assert.equal(core.DESKTOP_ACTS.length, 11);
  assert.ok(fx.alertCases.length >= 23, 'alertCases keeps its rows');
  assert.ok(fx.alertCases.every(c => !JSON.stringify(c.input).includes('transferOffer')), 'no transferOffer in alertCases: apps that replay it today stay green');
});

test('offerCases replay, and each row that carries the flag as exactly true is an alert', () => {
  assert.ok(fx.offerCases.length >= 13);
  for (const c of fx.offerCases) assert.equal(core.desktopAlert(c.input), c.out, c.name);
  assert.ok(fx.offerCases.some(c => c.input.transferOffer === true && c.out === true));
  for (const c of fx.offerCases) if (c.input.transferOffer !== true && !['approval', 'question', 'chatApproval', 'fileCatch'].some(k => c.input[k] === true)) assert.equal(c.out, false, c.name);
});

test('the three "a transfer offer" trips are in trips, after the file catch ones', () => {
  const names = fx.trips.map(t => t.name);
  const first = names.findIndex(n => n.startsWith('a transfer offer'));
  assert.ok(first > names.findIndex(n => n.startsWith('a file catch')));
  assert.equal(names.filter(n => n.startsWith('a transfer offer')).length, 3);
});
EOF
node --test tests/cat/desktop-offer.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
```

Expected: `# tests 5`, `# pass 2`, `# fail 3` (the flag is not counted yet and `offerCases` does not exist; the test that the older alerts still count passes).

- [ ] **Step 2: Apply the edits**

```bash
python3 - <<'PYTHON'
# Task 7: the transferOffer flag. Run from the repository root. Every anchor must be there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8', newline='\n').write(s)

edit('design/prototype/cat-core.js', [
(" * names), or a file on its way into the island (`fileCatch`: dragged over it, waiting for the cat, or its drop flow on screen). A flag counts only when it is exactly true; input that is not\n * an object is no alert. Pure, never throws.\n",
 " * names), a file on its way into the island (`fileCatch`: dragged over it, waiting for the cat, or its drop flow on screen), or an incoming transfer offer from another machine\n * (`transferOffer`: a card is waiting for a click; sub-project G2). A flag counts only when it is exactly true; input that is not an object is no alert. Pure, never throws.\n"),
("o.chatApproval===true||o.fileCatch===true||(Array.isArray(o.pillStates)",
 "o.chatApproval===true||o.fileCatch===true||o.transferOffer===true||(Array.isArray(o.pillStates)"),
])

edit('scripts/gen-cat-fixtures.mjs', [(
"  // @@DESKTOP-SECTIONS: each task adds its keys to `out` immediately above this line.\n",
"""  // The incoming transfer offer (G2-0): a card from another machine waits for a click, which is an alert like an approval, so to desktopStep it is alertOn and alertOff again (no new phase, event or act).
  // New keys and new trip rows only: `alertCases`, `note` and `catchNote` stay exactly as they were, so the apps that replay them today keep passing. offerCases: desktopAlert(input) is out.
  out.offerNote = 'The incoming transfer offer. A card from another machine ("<name> wants to send <file>") waits for a click: an alert to the desktop cat, like an approval, so it is alertOn and alertOff to desktopStep and there is no new phase, event or act. offerCases: desktopAlert(input) is out for inputs that carry transferOffer (a flag counts only when it is exactly true). alertCases is unchanged and holds no transferOffer. The trips named "a transfer offer" are desktopStep over the events an offer sends.';
  out.offerCases = [
    ['an offer', { transferOffer: true }], ['an offer next to false flags', { transferOffer: true, approval: false, question: false, chatApproval: false, fileCatch: false, pillStates: [] }],
    ['an offer and a file on its way in', { transferOffer: true, fileCatch: true }], ['an offer and a pill that is working', { transferOffer: true, pillStates: ['working'] }],
    ['no offer, an approval', { transferOffer: false, approval: true }], ['the flag false', { transferOffer: false }], ['no flags', {}],
    ['a flag as text', { transferOffer: 'true' }], ['a flag as the number 1', { transferOffer: 1 }], ['a flag as null', { transferOffer: null }], ['a flag in a list', { transferOffer: [true] }],
    ['a flag as an object', { transferOffer: {} }], ['keys that are not the flag', { offer: true, transfer: true, transfer_offer: true, TransferOffer: true, transferOffers: true }],
  ].map(([name, input]) => ({ name, input, out: core.desktopAlert(input) }));
  out.trips.push(
    trip('a transfer offer: the cat flies in, the offer is answered, the cat flies back', 'onDesktop', ['alertOn', 'flightDone', 'alertOff', 'flightDone'].map(evOf)),
    trip('a transfer offer: it is answered before the cat has landed, and the cat turns round mid-flight', 'onDesktop', ['alertOn', 'alertOff', 'flightDone'].map(evOf)),
    trip('a transfer offer: with the cat at home it changes nothing', 'home', ['alertOn', 'alertOff'].map(evOf)),
  );
  // @@DESKTOP-SECTIONS: each task adds its keys to `out` immediately above this line.
""")])

edit('docs/CAT-CONTRACT.md', [
("and from the file catch `catchNote`, `catchWaitMs`, `alertCases` (`desktopAlert`) and `catchReady` (`desktopCatchReady`). See \"The desktop cat (H-0)\" and \"The file catch\". |",
 "and from the file catch `catchNote`, `catchWaitMs`, `alertCases` (`desktopAlert`) and `catchReady` (`desktopCatchReady`), and from the transfer offer `offerNote` and `offerCases` (`desktopAlert` again). See \"The desktop cat (H-0)\", \"The file catch\" and \"The transfer offer\". |"),
("\n## The wardrobe (I-0)\n",
 """
### The transfer offer (G2-0)

Sub-project G2 (`docs/LINK-CONTRACT.md`) lets another machine offer a file. The offer is a card ("<name> wants to send <file>", Accept and Decline) that only a click answers, so it is an alert like an approval: the island opens even when hidden, holds open, and the desktop cat flies to the notch. To `desktopStep` it is `alertOn` and `alertOff` again, so there is no new phase, event or act and every older row stands.

What is new is one flag and some fixture keys, all additive:

- `desktopAlert` also counts `transferOffer`: true only when exactly `true`, like the other flags (text, a number, `null`, a list or an object is false). Fixture: `offerCases`. **`alertCases` is untouched and holds no `transferOffer`**, so an app that replays it today keeps passing before it learns the flag.
- Three trips in `trips` are named "a transfer offer": the whole offer, an offer answered before the cat has landed (the cat turns round mid-flight), and an offer with the cat at home (nothing happens).

**What an app does with it.** It feeds `transferOffer` from the link's offer card, true from the moment the card is shown until it is answered, expired (2 minutes) or withdrawn. The G2 app plans add `offerCases` to their replay of `desktop-cases.json`.

## The wardrobe (I-0)
""")])
PYTHON
git diff --stat
```

Expected: `git diff --stat` shows `design/prototype/cat-core.js`, `docs/CAT-CONTRACT.md` and `scripts/gen-cat-fixtures.mjs` (about 6, 13 and 15 changed lines) and nothing else yet.

- [ ] **Step 3: Regenerate the fixture and run every cat check**

```bash
node scripts/gen-cat-fixtures.mjs | tail -1
node scripts/gen-cat-fixtures.mjs --check | tail -1
node --test tests/cat/*.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
node scripts/check-fixtures-additive.mjs HEAD | tail -2
node scripts/check-fixtures-additive.mjs 1627851 | tail -1
bash scripts/test-cat-contract.sh 2>&1 | tail -3
git status --short
```

Expected: `wrote 16 fixture files to tests/fixtures/cat`; `✓ 16 fixture files match cat-core.js`; `# tests 324`, `# pass 324`, `# fail 0`; a last pair of lines for `HEAD` ending `✓ fixtures changed only by addition since HEAD`; `✓ fixtures changed only by addition since 1627851`; the cat contract's last lines (`✓ 16 fixture files match cat-core.js`, `✓ two generator runs write identical bytes`); and a status of `M design/prototype/cat-core.js`, `M docs/CAT-CONTRACT.md`, `M scripts/gen-cat-fixtures.mjs`, `M tests/fixtures/cat/desktop-cases.json`, `?? tests/cat/desktop-offer.test.mjs`. **The number of cat tests is the cat contract's own plus the five new ones: if it differs from `324`, check that tests were added on `notchmeow/rebrand` since this plan was written.** `desktop-cases.json` gains about 20 lines and loses one (the old last trip row gains a trailing comma).

- [ ] **Step 4: Prove it bites (a one-off, never committed)**

```bash
python3 - <<'PYTHON'
import subprocess
path = "design/prototype/cat-core.js"
src = open(path, encoding="utf-8").read()
find = "o.fileCatch===true||o.transferOffer===true||"
assert src.count(find) == 1
open(path, "w", encoding="utf-8", newline="\n").write(src.replace(find, "o.fileCatch===true||"))
try:
    out = subprocess.run(["node", "--test", "tests/cat/desktop-offer.test.mjs"], capture_output=True, text=True).stdout
    print([l for l in out.splitlines() if l.startswith("# fail")])
finally:
    open(path, "w", encoding="utf-8", newline="\n").write(src)
PYTHON
git diff --stat design/prototype/cat-core.js
```

Expected: `['# fail 2']` and a diff stat for `cat-core.js` of the same size as in Step 2 (the file is back as Step 2 left it).

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/fixtures/cat/desktop-cases.json docs/CAT-CONTRACT.md tests/cat/desktop-offer.test.mjs
cat > "${TMPDIR:-/tmp}/g20-msg8.txt" <<'EOF'
feat(cat): an incoming transfer offer is an alert to the desktop cat (additive contract: transferOffer, offerCases) (G2-0)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -q -F "${TMPDIR:-/tmp}/g20-msg8.txt" && git log --oneline -8 && git show --stat --format= HEAD
node scripts/check-fixtures-additive.mjs notchmeow/rebrand | tail -1
```

Expected: five files committed; `✓ fixtures changed only by addition since notchmeow/rebrand`.

---

### Task 9: Docs, CI and the final checks

**Files:**
- Create: `docs/LINK-CONTRACT.md`
- Modify: `.github/workflows/build.yml` (one step after "Shelf contract"), `CLAUDE.md` and `ARCHITECT.md` (one bullet each), `docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md` (its G2-0 table)
- Create (outside the repository, never committed): `${TMPDIR:-/tmp}/g20-rules.txt`

**Interfaces:**
- Consumes: Tasks 1 to 7.
- Produces: the document the app plans cite, the CI step, and a spec table that says what the files pin.

Nothing in G2-0 is visible, so the owner's look is a plain read: what the rules answer to inputs that matter. The choices the spec left open were answered by the owner on 2026-10-14 (the section "The owner's answers" at the end of this plan), so there is no stop here: the table is printed for the record and pasted in the ledger. The numbers are printed by the reference itself, so the table cannot drift from the code.

- [ ] **Step 1: Print the table**

```bash
python3 -B -I - <<'PYTHON' | tee "${TMPDIR:-/tmp}/g20-rules.txt"
import sys, importlib.util
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('ref', 'tests/fixtures/link/reference.py')
r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
N, M, SI, SR = (bytes([b]) * 32 for b in (0xA1, 0xB1, 0xC1, 0xC2))
C = r.commit_of(N, SI).hex()
print('commitment of a nonce under a key:', C[:16] + '...', '| the code from two nonces and two keys:', r.pairing_code(N, M, SI, SR), '| with the nonces swapped:', r.pairing_code(M, N, SI, SR))
idle = {'s': 'idle', 'seen': [], 'last': None}
started = r.pair_responder_step(idle, {'commit': C, 'nonce': M.hex(), 'now': 1000})
def reveal(st, nonce=N, static=SI, now=2000):
    return r.pair_responder_step(st, {'reveal': {'nonce': nonce.hex(), 'static': static.hex(), 'own': SR.hex()}, 'now': now})
print('responder: a good reveal ->', reveal(started['state'])['notify'], reveal(started['state'])['state']['code'], '| a wrong nonce ->', reveal(started['state'], nonce=M)['because'], '| another key ->', reveal(started['state'], static=SR)['because'],
      '| after 2 minutes ->', reveal(started['state'], now=121000)['because'], '| with no commitment ->', reveal(idle)['because'])
print('responder: the same commitment again ->', r.pair_responder_step({**idle, 'seen': started['state']['seen'], 'last': 1000}, {'commit': C, 'nonce': M.hex(), 'now': 61000})['because'],
      '| another attempt after 20 s ->', r.pair_responder_step({**idle, 'seen': started['state']['seen'], 'last': 1000}, {'commit': '00' * 32, 'nonce': M.hex(), 'now': 21000})['because'])
print('clocks: attempt 29.999 s after the last', r.pairing_attempt_allowed(0, 29999), '| at 30 s', r.pairing_attempt_allowed(0, 30000), '| window at 119.999 s', r.pairing_window_open(0, 119999), '| at 120 s', r.pairing_window_open(0, 120000), '| offer at 120 s expired', r.offer_expired(0, 120000))
for raw in ['report.pdf', '../etc/passwd', '/etc/passwd', 'C:\\Windows\\x', 'a\x00b', 'invoice\u202efdp.exe', 'a\u200bb', '\uff0fetc', 'CON', 'NUL.tar.gz', 'a:b.txt', 'name.txt.', 'name.txt ', 're\u0301sume\u0301.docx', '...', 'x' * 300 + '.txt']:
    k, v = r.sanitize_name(raw)
    print('sanitize', ascii(raw if len(raw) < 40 else raw[:12] + '...'), '->', k, ascii(v) if len(v) < 40 else str(len(v.encode())) + ' bytes ending ' + v[-4:])
print('unique_name a.txt with a.txt and a (1).txt taken ->', r.unique_name('a.txt', ['a.txt', 'a (1).txt']), '| A.TXT taken ->', r.unique_name('a.txt', ['A.TXT']))
offer = {'type': 'offer', 'id': 'a1' * 16, 'size': 1048576, 'name': 'report.pdf', 'kind': 'application/pdf'}
print('an offer frame is', len(r.encode_frame(offer)), 'bytes:', r.encode_frame(offer).hex()[:60] + '...')
print('limits: chunk', r.CHUNK_MAX, 'sent in pieces of', r.CHUNK_SIZE, '| name on the wire', r.RAW_NAME_MAX, 'bytes, saved at most', r.NAME_BYTES_MAX, '| 4 GiB =', r.SIZE_MAX)
big = r.receiver_step({'s': 'idle'}, {'frame': {**offer, 'size': 4294967297}})
print('an offer of 4 GiB and a byte -> decline reason', big['send'][0]['reason'], '(3 = too large), no card:', big['notify'])
st = {'s': 'receiving', 'id': 'a1' * 16, 'size': 10, 'got': 4}
print('a chunk sent twice ->', r.receiver_step(st, {'frame': {'type': 'chunk', 'id': 'a1' * 16, 'offset': 0, 'data': 'ab' * 4}})['abort'], '| done one byte short ->', r.receiver_step({**st, 'got': 9}, {'frame': {'type': 'done', 'id': 'a1' * 16}})['abort'])
PYTHON
```

Expected: the lines below, which the reference prints itself.

```text
commitment of a nonce under a key: 4b8c8215defb279e... | the code from two nonces and two keys: 479411 | with the nonces swapped: 080624
responder: a good reveal -> show-code 479411 | a wrong nonce -> reveal-mismatch | another key -> reveal-mismatch | after 2 minutes -> reveal-late | with no commitment -> no-commit
responder: the same commitment again -> commit-replayed | another attempt after 20 s -> attempt-too-soon
clocks: attempt 29.999 s after the last False | at 30 s True | window at 119.999 s True | at 120 s False | offer at 120 s expired True
sanitize 'report.pdf' -> ok 'report.pdf'
sanitize '../etc/passwd' -> reject 'separator'
sanitize '/etc/passwd' -> reject 'separator'
sanitize 'C:\\Windows\\x' -> reject 'separator'
sanitize 'a\x00b' -> reject 'invisible'
sanitize 'invoice\u202efdp.exe' -> reject 'invisible'
sanitize 'a\u200bb' -> reject 'invisible'
sanitize '\uff0fetc' -> reject 'separator'
sanitize 'CON' -> ok '_CON'
sanitize 'NUL.tar.gz' -> ok '_NUL.tar.gz'
sanitize 'a:b.txt' -> ok 'a_b.txt'
sanitize 'name.txt.' -> ok 'name.txt'
sanitize 'name.txt ' -> ok 'name.txt'
sanitize 're\u0301sume\u0301.docx' -> ok 'r\xe9sum\xe9.docx'
sanitize '...' -> reject 'empty'
sanitize 'xxxxxxxxxxxx...' -> ok 200 bytes ending .txt
unique_name a.txt with a.txt and a (1).txt taken -> a (2).txt | A.TXT taken -> a (1).txt
an offer frame is 53 bytes: 01a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a10000000000100000000a726570...
limits: chunk 65494 sent in pieces of 32768 | name on the wire 1020 bytes, saved at most 200 | 4 GiB = 4294967296
an offer of 4 GiB and a byte -> decline reason 3 (3 = too large), no card: None
a chunk sent twice -> order | done one byte short -> short
```


Paste the table in the ledger. If a line differs from the owner's answers (the commitment step, 6 digits, 4 GiB, the 200-byte name, and so on), stop and report: a rule drifted from the answer.

- [ ] **Step 2: Write the document**

`````bash
cat > docs/LINK-CONTRACT.md <<'EOF'
# The link contract

Sub-project G2 (`docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md`, "G2. Between your machines" and "G1-0 and G2-0") moves files between a Mac and a Windows/Linux PC that both run NotchMeow, over the local network. The macOS app (Swift, on CryptoKit and `Network.framework`) and the Windows/Linux app (Rust, on the `snow` and `mdns-sd` crates, with TypeScript for the cards) each implement the same rules natively. Everything they must agree on to talk to each other is written once, here and in `tests/fixtures/link/`, and each app tests itself against the fixtures. The cross-app test of G2 (the Swift and the Rust code pair over loopback and send files both ways) comes on top of this contract and does not replace it.

**`tests/fixtures/link/reference.py` is the tie-breaker.** It is a Python program (standard library only) with every rule written as plainly as possible, including the X25519, ChaCha20 and Poly1305 that the Noise handshakes need (checked against the RFC 7748 and RFC 8439 test vectors). The JSON files are written by `build_cases.py`, with every expected answer typed out by hand (the Noise vectors and the pairing codes are pasted once from the reference and then frozen), so the fixtures and the reference check each other. If an app and a fixture disagree, the app is wrong. The reference is not constant-time and no app may use it.

The look of the cards, the discovery itself, the sockets, the Keychain items, the streaming of a file to disk and the quarantine attribute are not tested here. This contract is the bytes on the wire, the rules for what to accept, and the arithmetic that both ends must agree on.

## Run it

```
bash scripts/test-link-contract.sh                        # the reference against every fixture, then the no-drift check
python3 tests/fixtures/link/build_cases.py                # rewrite the JSON files after an intended change
python3 tests/fixtures/link/build_cases.py --check
```

Python 3.9 or newer, nothing to install; it takes a few seconds. CI runs the script next to the other contracts. Both app plans add their own replay of the files: G2-mac and G2-tauri.

## The files

| File | Pins |
|---|---|
| `noise-vectors.json` | `vectors[]` in the format of the published cacophony and `snow` vectors: `protocol_name`, the prologues, the static and ephemeral private keys (plain byte patterns), `handshake_hash` and `messages[]` of `{payload, ciphertext}`. Four of them: `xx-link` and `xx-empty` for `Noise_XX_25519_ChaChaPoly_SHA256`, `kk-link` and `kk-empty` for `Noise_KK_25519_ChaChaPoly_SHA256`. `rejectCases[]` damage what is delivered (a flipped bit, a short message, a replay, a lost message, a zero-point key, another prologue, another static key) and say at which message the conversation must stop (`failsAt`; for the two zero-point cases also `because`, the reference's own reason, so that a port checks that the zero key is refused as such and not only because the two sides' keys then disagree). |
| `pairing-cases.json` | `commits[]` (the commitment of a nonce under a static key), `codes[]` (the six digits from two nonces and two keys), `invalid[]`, `session` (the pairing inside the `xx-link` Noise vector), the clocks (`gapCases`: one pairing attempt every 30 s, `windowCases`: the pairing window of 2 minutes, `offerCases`: an offer unanswered for 2 minutes), and the two pairing machines: `responder[]` and `initiator[]` of `{state, event, out}` and `machineTrips[]`. Every refusal has a `because`. |
| `frames.json` | The limits and numbers; `frames[]` (each of the six frames and the two pairing answers as a dict and as hex, both ways), `rejects[]` (bytes that must not decode, with the error), `limits[]` (a chunk of 65494 or 65495 bytes, built from a recipe), `hello[]`, `txt[]` (the advert's TXT record), `preamble[]`, `records[]` (cutting a byte stream into records) and `recordEncode[]`. |
| `flow-cases.json` | What each side does with each frame: `receiver[]` and `sender[]` of `{state, event, out}`, `trips[]` (whole transfers, event by event) and `chunkPlans[]`. |
| `filename-cases.json` | `cases[]` of `{raw, out}`: the file-name sanitizer, with `out` either `{ok: name}` or `{reject: reason}`; `uniqueCases[]`: the name to use when the name is taken. |
| `reference.py` | Every rule, the replay of every file, and seeded fuzzes. |
| `build_cases.py` | Writes the JSON files (`--check` fails on drift). |

## On the wire

One TCP connection carries one conversation, pairing or transfer. Numbers are big-endian. Everything is a **record**: a `u16` length (1 to 65535, so 0 is an error and closes the connection) and that many bytes. A record holds one of: the preamble, one Noise handshake message, or one Noise transport message. `split_records` cuts a stream into whole records and keeps the rest.

1. **The preamble** is the first record, from the initiator, in the clear: 18 bytes, `version` (1), `mode` (1 pair, 2 transfer) and the sender's 16-byte `device id`. When pairing the id is 16 zero bytes (the machines do not know each other yet); in a transfer it must not be zero, and the responder uses it to find the stored key of that peer, because `KK` needs the initiator's static key before the first message. An id it does not know closes the connection.
2. **The handshake**, one record per Noise message: `Noise_XX_25519_ChaChaPoly_SHA256` (3 messages) for a pairing, `Noise_KK_25519_ChaChaPoly_SHA256` (2 messages) for a transfer, both with the **prologue** `notchmeow-link/1` (ASCII), so that two versions of the protocol cannot complete a handshake. The ephemeral keys are random; only the fixtures inject them. A DH result of 32 zero bytes (a low-order point) aborts. Nothing is sent after a failed handshake: the connection is closed.
3. **Pairing** runs in a fixed order, inside the `XX` handshake (details in "The pairing code" below). The payload of message 1 (in the clear, as `XX` has no key yet) is the initiator's **commitment**, 32 bytes. The payload of message 2 is the responder's **hello**, and of message 3 the initiator's hello, which **reveals** its nonce. A hello is `version` (1), the sender's 16-byte device id (not all zero), a 32-byte `nonce`, `name length` (`u8`) and the device name (1 to 63 bytes of strict UTF-8 with no control, format or line-separator character and no space at either end). It is encrypted, so the name on the "Pair with <name>?" card is the authenticated one; the name in the advert is not trusted. Once the reveal has been checked, both sides show the code, the user answers, and a `pair-yes` or `pair-no` tells the other side; a key is stored only when both said yes.
4. **Transfer**: after the `KK` handshake each Noise transport message holds one **frame**: a type byte, the 16-byte transfer id, then the body. Handshake payloads are empty.

| Frame | Type | Body |
|---|---|---|
| `offer` | 1 | `size` (`u64`), `name length` (`u16`, 1 to 1020), the name (strict UTF-8, as the sender has it), `kind length` (`u8`, 0 to 127), `kind` (printable ASCII, the file's type, advisory: never used to decide anything) |
| `accept` | 2 | nothing |
| `decline` | 3 | `reason` (`u8`): 0 the user said no, 1 nobody answered in 2 minutes, 2 busy (one transfer per peer), 3 too large, 4 the offer was not acceptable |
| `chunk` | 4 | `offset` (`u64`), then 1 to 65494 bytes of data |
| `done` | 5 | nothing |
| `cancel` | 6 | nothing |
| `pair-yes` | 33 | nothing, and no transfer id: the type byte alone. After a pairing, "They match" was clicked |
| `pair-no` | 34 | nothing, the type byte alone. The other side's user said the codes differ |

A frame may not have a byte left over (the `pair-yes` and `pair-no` frames travel in the transport messages that follow the pairing handshake and are one byte each), and a decoder must be strict: UTF-8 without surrogates, overlong forms or code points over U+10FFFF (a decoder that repairs bad bytes is wrong), and ASCII for `kind`. The limits are `chunkMax` 65494 (so that a chunk frame and the 16-byte tag fill a Noise message of 65535 bytes exactly), `rawNameMax` 1020 (255 code points of up to 4 bytes) and 4 GiB per transfer. A sender cuts a file into chunks of `chunkSize` 32768 bytes (`plan_chunks`) and accepts any chunk up to `chunkMax`.

The advert (`_notchmeow._tcp`) carries a TXT record with `v` (the text `1`), `id` (32 lower-case hex digits, not all zero) and `name` (as a device name). `parse_txt` accepts or rejects it, because anyone on the network can send one. It gives a machine something to show in a list and nothing more: only a paired key gets a session.

## The pairing code

The six-digit code must not be something a man in the middle can aim at. A code made from the handshake alone can be: the attacker, sitting between two machines, runs one handshake with each, and grinds its own keys offline until the two codes agree, about 10^6 tries for 6 digits. So the code is made with a **commit-then-reveal** step, the short-authenticated-string pattern of Vaudenay ("Secure Communications over Insecure Channels Based on Short Authenticated Strings", CRYPTO 2005), of ZRTP's hash commitment (RFC 6189) and of Bluetooth's numeric comparison (Core Specification, Vol 3, Part H, 2.3.5.6.2, with `f4` and `g2`). The owner chose it over a longer code on 2026-10-14.

1. The initiator draws a fresh 32-byte nonce `nI` and sends `commit_of(nI, sI)` = `SHA-256("notchmeow-link pairing commit v1" + sI + nI)` as the payload of message 1, where `sI` is its static public key. The commitment hides `nI` and binds `sI`.
2. The responder, which has seen only the commitment, answers with its nonce `nR` in its hello (message 2).
3. The initiator reveals `nI` in its hello (message 3). The responder opens message 3, which also shows it `sI`, and checks `commit_of(nI, sI)` against what it got first. A wrong nonce and a wrong key give the same refusal (`reveal-mismatch`) on purpose: the commitment cannot tell them apart and the attacker learns nothing from which it was.
4. Both compute `pairing_code(nI, nR, sI, sR)` = the first 8 bytes of `SHA-256("notchmeow-link pairing code v1" + sI + sR + nI + nR)` as a number, modulo 10^6, with leading zeros kept. Both users compare the two screens and answer.

**Why it holds.** Each of the attacker's choices towards each side (its static keys, its nonces) is made before the honest initiator's nonce is revealed, and the commitment stops the initiator, or an attacker playing the initiator, from choosing the nonce afterwards. So the code on each screen is a fresh unpredictable value to the attacker at the moment it commits to everything it can still vary, and it gets **one guess per pairing attempt**: about 1 in 10^6. An attempt is allowed once every 30 seconds, every failed one shows the users two different codes, and the window of 2 minutes covers the whole exchange. The static keys are in the code because the `XX` handshake authenticates them: a key substituted by a man in the middle gives a different code on the two screens.

**What is deliberately not in the code.** The handshake hash. The last sender's payload (its device name, free text) is in that hash and can still be varied after the sender has seen the other side's nonce, which would let the attacker grind the code offline again. The device name and id are not in the code either, for the same reason: the name on the card is whatever the other machine says it is, and the user decides by looking at the machine in front of them.

**The two machines.** `pair_responder_step` and `pair_initiator_step` run the order above one event at a time and are tested row by row. A refusal closes the connection and always has a cause (`because`): `commit-length`, `commit-replayed` (the same commitment seen again within the window: the responder keeps the recent ones across connections, `seen`), `attempt-too-soon`, `no-commit` (a reveal, or a nonce, with no commitment before it), `reveal-late`, `reveal-length`, `reveal-mismatch`, `unexpected`, `start-length`, `nonce-repeated`, `nonce-length`, `window-closed` (an answer after 2 minutes) and `said-no`. An answer that is not exactly `yes` is a no.

The clocks, in whole milliseconds on a monotonic clock (an app counts an attempt when it starts a pairing and when it accepts an incoming one): one pairing attempt every 30 s (`pairing_attempt_allowed`: allowed at exactly 30 s), the pairing window closes after 2 minutes (`pairing_window_open`: open below 120 s), and an unanswered offer is declined after 2 minutes (`offer_expired`: expired at 120 s). A clock that went back or a value that is not whole milliseconds counts as "no" for the first two and "expired" for the third.

## File names

`sanitize_name(raw)` gives `("ok", name)` or `("reject", reason)`. The name on the Accept card is the **sanitized** one, because it is the one that is saved.

**Rejected** (a real sender never sends these; the offer is declined as "not acceptable"): not text (`not-text`); a control, format, surrogate or line- or paragraph-separator character (`invisible`: Unicode categories Cc, Cf, Cs, Zl, Zp, so NUL, the C0 and C1 controls, DEL, every bidi control, the zero-width space, joiner and non-joiner, the word joiner, the byte order mark, the soft hyphen and the tag characters); a `/` or a `\` (`separator`: so no path, no `..` part, no absolute path, no UNC path); nothing left once spaces and dots are trimmed (`empty`: `.`, `..`, `...`, spaces). The checks run on the NFC form and on the NFKC form, so full-width solidus, reverse solidus and dots are caught as what they fold to. The order of the checks is the order above.

**Rewritten** (platform differences, not attacks): `< > : " | ? *` become `_` (the colon also stops an NTFS alternate data stream); spaces at the start and spaces and dots at the end go; a Windows device name (`CON`, `PRN`, `AUX`, `NUL`, `COM1`-`COM9`, `LPT1`-`LPT9`, the superscript digits, `CONIN$`, `CONOUT$`: the part before the first dot, ASCII case-insensitive, also after NFKC) gets a `_` in front; a name over **200 UTF-8 bytes** is cut at a code point, keeping an extension of up to 16 bytes. The kept name is **NFC** (never NFKC: a ligature stays a ligature).

`unique_name(name, taken)` is `name (1).ext`, `name (2).ext` and so on, the smallest free number from 1, comparing in NFC and case-insensitively (the usual volumes of both systems do), giving up after 9999 (`None`: the transfer fails). Only the last extension of 16 bytes or less is kept apart (`a.tar.gz` becomes `a.tar (1).gz`), and a leading dot is not an extension (`.bashrc (1)`). A name from a Windows sender of 255 UTF-16 units can be 765 bytes of UTF-8; that is why the wire allows 1020 bytes and the saved name is cut to 200.

## What each side does with each frame

`receiver_step(state, event)` and `sender_step(state, event)` are pure: a state, one event (a frame, a click, a timeout), and the answer `{state, send, notify, abort}`. Tables in `flow-cases.json`; the rules in short:

- **Receiver.** An `offer` while idle: a size over 4 GiB is declined (3), a name the sanitizer rejects is declined (4), otherwise the card is shown and the state is `offered` (an empty file is allowed). An `offer` while something else is going on is declined as busy (2) and changes nothing. **Only a click** (`accept`) starts the transfer; `decline` and a timeout answer with reasons 0 and 1. A `cancel` for the current transfer ends it; a `cancel` for any other id is ignored.
- **Chunks.** The `offset` must equal the bytes received so far (a replayed or a skipped chunk is `order`), the sum may not pass the offered size (`overflow`), the id must be the transfer's (`id`). `done` is good only when the count equals the offer exactly (`short` otherwise). Any other frame in any other state is `unexpected`. Every abort closes the connection; nothing is saved as complete.
- **Sender.** `accept` or `decline` for its offer's id move it on; a frame for another id, or one that makes no sense in the state, closes the connection.
- The Noise layer already refuses tampered, replayed and reordered messages (the nonce is the message count); the checks above catch a peer that is paired but wrong or hostile.

## Notes for ports

- **Noise.** Revision 34. `ChaChaPoly` is the 12-byte-nonce IETF ChaCha20-Poly1305 with a nonce of 32 zero bits and then the 64-bit message count, little-endian; not XChaCha. `SHA256` and the `HKDF` of the Noise spec (two outputs) are HMAC-SHA256. The hash of the protocol name is the name padded with zeros, because it is 31 bytes. Reading a message whose tag fails must not move the counter. The reference refuses a DH output of all zeros; CryptoKit and `snow` may already do so, and a port must anyway.
- **JSON.** Integers are whole numbers; the fixtures hold no float. Hex fields are lower-case. A fixture that holds text with escapes (`\u202e`) is read by a strict JSON reader, as for the shelf.
- **Strings.** Byte limits (name 200, device name 63, wire name 1020) are UTF-8 bytes; the number of characters is not a limit. Compare names after NFC. The Unicode categories come from the language's own tables; the fixtures use only long-assigned characters, so a Python, Swift or Rust of a different Unicode version agrees.
- **Time.** The gaps use a monotonic clock, in whole milliseconds.
- **Secrets.** The static private key and the peers' keys live in the Keychain or Credential Manager and never in a log, a file or a fixture. The keys in the fixtures are plain byte patterns made for tests: never use one as a real key.
- **Not in this contract:** discovery and browsing, the sockets and their timeouts, the Keychain and Credential Manager items (`link.static-key`, `link.peer.<id>`), the cards, writing the file (the folder `Downloads/NotchMeow/`, quarantine, mark-of-the-web), the Send menu, and the Debug fake peer.

## Decisions, answered by the owner

These are choices the spec did not make, answered by the owner on 2026-10-14. The fixtures pin the answers; a different answer is one edit in `reference.py` and `build_cases.py`, a regenerate, and a re-run of the ports' tests. The owner's answers are in the plan, "The owner's answers (2026-10-14)".

- The Noise vectors are generated by the reference with fixed keys and cross-checked with an independent implementation on CryptoKit; the published vectors can be added as more entries (`source`: `published`) without changing any code.
- The prologue is `notchmeow-link/1`; the preamble, the hello and the frame layouts above are this contract's own design.
- The pairing code comes from a commit-then-reveal step (the owner's decision), 6 digits only; the handshake hash is not an input and the reason is above.
- Chunks are cut at 32 KiB; 4 GB means 4 GiB inclusive (4294967296 bytes).
- The sanitizer rejects what only a hostile or broken sender sends and rewrites platform differences; the saved name is at most 200 bytes; a zero-width joiner is refused with the rest of Cf.
- The boundaries of the clocks, the decline reasons, and the extra file `flow-cases.json`.
EOF
`````

- [ ] **Step 3: Add the CI step, the two pointers and the spec's table**

```bash
python3 - <<'PYTHON'
# Task 8: the CI step, the two pointers and the spec's G2-0 table. Run from the repository root. Every anchor must be there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8', newline='\n').write(s)

edit('.github/workflows/build.yml', [(
"""      - name: Shelf contract (zone and shelf rules, fixtures, no drift)
        run: bash scripts/test-shelf-contract.sh
""",
"""      - name: Shelf contract (zone and shelf rules, fixtures, no drift)
        run: bash scripts/test-shelf-contract.sh

      - name: Link contract (Noise vectors, pairing code, frames, flow, file names, fixtures, no drift)
        run: bash scripts/test-link-contract.sh
""")])

edit('CLAUDE.md', [(
"- `docs/superpowers/specs/` — the NotchMeow design spec",
"- `tests/fixtures/link/`, `docs/LINK-CONTRACT.md` — the link contract (sub-project G2-0): the Noise vectors for `Noise_XX_25519_ChaChaPoly_SHA256` (pairing) and `Noise_KK_25519_ChaChaPoly_SHA256` (transfer), the pairing (a commit-then-reveal step so that a man in the middle gets one guess per attempt, the six-digit code from both nonces and both static keys, and the two machines that run it), the wire layout (records, the first record, hello, the six frames, the advert), what the receiver and the sender do with each frame, and the file-name sanitizer. `reference.py` (Python, standard library, with its own X25519 and ChaCha20-Poly1305 checked against the RFC vectors) decides when an app and a fixture disagree; `build_cases.py` writes the JSON files; `scripts/test-link-contract.sh` runs them. `desktopAlert` in `cat-core.js` also counts `transferOffer` (new `offerCases` in `desktop-cases.json`; `alertCases` untouched). No Swift, Rust or TypeScript source holds these rules until the G2 app plans port them.\n"
"- `docs/superpowers/specs/` — the NotchMeow design spec")])

edit('ARCHITECT.md', [(
"   - **Sub-project H on Windows/Linux:**",
"   - **Sub-project G2-0 (the link contract):** `tests/fixtures/link/` (`noise-vectors.json`, `pairing-cases.json` with the commit-then-reveal pairing machines, `frames.json`, `flow-cases.json`, `filename-cases.json`) with a Python `reference.py` that decides; `build_cases.py` writes the JSON, `scripts/test-link-contract.sh` checks it and CI runs that. Documented in `docs/LINK-CONTRACT.md`. The incoming transfer offer is an alert to the desktop cat through one more flag of `desktopAlert` (`transferOffer`, fixture `offerCases`). The G2 Mac and Windows/Linux plans port the rules and replay the fixtures.\n"
"   - **Sub-project H on Windows/Linux:**")])

edit('docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md', [
("| `noise-vectors.json` | The official published test vectors for `Noise_XX_25519_ChaChaPoly_SHA256` and `Noise_KK_25519_ChaChaPoly_SHA256`.",
 "| `noise-vectors.json` | Test vectors for `Noise_XX_25519_ChaChaPoly_SHA256` and `Noise_KK_25519_ChaChaPoly_SHA256` in the published format (generated by the reference and cross-checked with CryptoKit; the published ones can be added as more entries), and damaged-message cases that must stop the conversation."),
("| `pairing-cases.json` | Handshake hash, then the 6-digit code (the derivation is defined here once) |",
 "| `pairing-cases.json` | The commit-then-reveal pairing (the owner's decision of 2026-10-14, so that a man in the middle gets one guess per attempt): the commitment to a nonce and a static key, the 6-digit code from both nonces and both static keys (defined here once; no 8-digit value), the initiator's and the responder's machines with the cause of every refusal, and the clocks (one attempt every 30 seconds, a window of 2 minutes, an offer unanswered for 2 minutes) |"),
("| `frames.json` | Length-prefixed frame encoding for `offer`, `accept`, `decline`, `chunk`, `done` and `cancel`, plus malformed frames that must be rejected |",
 "| `frames.json` | Length-prefixed records, the first record, the hello, the advert's TXT record and the frame encoding for `offer`, `accept`, `decline`, `chunk`, `done` and `cancel`, plus malformed frames that must be rejected |\n| `flow-cases.json` | What the receiver and the sender do with each frame: busy, too large, a replayed or skipped chunk, a short `done`, a cancel |"),
("| `reference.py` | A Python standard-library reference for framing and file-name rules. The crypto is covered by the Noise vectors. |",
 "| `reference.py` | A Python standard-library reference for every rule above, with its own X25519 and ChaCha20-Poly1305 (checked against the RFC vectors) so that it can replay the Noise vectors; it decides when an app and a fixture disagree |\n| `build_cases.py` | Writes the JSON files with the expected answers typed out by hand (`--check` fails on drift) |"),
])
PYTHON
git diff --stat
```

Expected: `.github/workflows/build.yml` (3 insertions), `ARCHITECT.md` (1), `CLAUDE.md` (1) and the spec (a few lines) changed.

- [ ] **Step 4: Run every check**

```bash
bash -n scripts/test-link-contract.sh && bash scripts/test-link-contract.sh | tail -7
bash scripts/test-shelf-contract.sh | tail -3
bash scripts/test-cat-contract.sh 2>&1 | grep -E '^# (tests|pass|fail)|fixture files|identical'
node scripts/check-fixtures-additive.mjs 1627851 | tail -1
node scripts/check-fixtures-additive.mjs notchmeow/rebrand | tail -1
bash scripts/check-no-leftovers.sh | tail -6
grep -n "test-link-contract" .github/workflows/build.yml
git ls-files --others --exclude-standard
git status --short
```

Expected: the link contract's report ends `all link contract checks passed` followed by the five `matches build_cases.py` lines; the shelf contract still passes (`all shelf contract checks passed` and its two `matches` lines); the cat contract: `# tests 324`, `# pass 324`, `# fail 0`, `✓ 16 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`; both additive checks end with a tick; the no-leftovers script prints its ticks; the workflow step is found (one line); `git ls-files --others` lists only `docs/LINK-CONTRACT.md` and no `__pycache__` or `.pyc` anywhere; the status shows the four modified files and `?? docs/LINK-CONTRACT.md`.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add docs/LINK-CONTRACT.md .github/workflows/build.yml CLAUDE.md ARCHITECT.md docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md
cat > "${TMPDIR:-/tmp}/g20-msg9.txt" <<'EOF'
docs(link): the link contract document, the CI step and the pointers (G2-0)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -q -F "${TMPDIR:-/tmp}/g20-msg9.txt" && git log --oneline -9 && git show --stat --format= HEAD
```

Expected: five files listed; `git log` shows Tasks 1 to 8 on top of `notchmeow/rebrand`.

**Then the controller dispatches `nm-reviewer-deep` over the whole branch** (`git diff notchmeow/rebrand...HEAD`), with the security pass the spec asks for: the Noise state machine against the specification text (token order, the pre-messages, the prologue, the nonce layout, what happens to the counter on a refused message, the low-order check), the frame parser and the first-record rules (strictness, every length checked before it is used, nothing read past the end), the file-name sanitizer against every hostile name it can think of (and the Unicode-version risk of the category tables), the pairing's commit-then-reveal construction (does any input to the code stay free to vary after the other side's nonce is known; can a man in the middle aim the code; is the cause of every refusal tested)), the receiver's rules (can any sequence of frames save a file that was not accepted, or complete one that is short or long), anything a Swift or Rust port could read two ways (code points against bytes, a decoder that repairs bad UTF-8, `5.0` against `5`, the order of checks), that no existing source file other than `cat-core.js` and its generator moved and that the cat fixtures changed only by addition, and that every answer of the owner is in `docs/LINK-CONTRACT.md` or below. Then it reports to the main session with `SendMessage`.

---

## The owner's answers (2026-10-14)

The spec left these values open. The owner answered on 2026-10-14: the pairing question with a decision of their own (3), every other question with the option the draft recommended, and the timing. The fixtures pin the answers. A different answer later is one edit in `reference.py` and `build_cases.py`, a regenerate (and, for 1 to 4, a re-paste of the frozen Noise vectors and pairing values from the reference and a new CryptoKit cross-check), and the app plans pick it up.

**Timing.** G2-0 starts now, before G1-tauri. It touches none of G1's files.

1. **The Noise vectors: generated by the reference.** The plan was drafted without network access, so it cannot fetch the published vectors. The vectors are generated by the reference in the published format (`source: "generated"`, fixed byte-pattern keys), cross-checked in Task 2 by a second implementation on CryptoKit, and then replayed by `snow` in G2-tauri (a third). The main session, with network, may add the published `XX` and `KK` entries for `25519_ChaChaPoly_SHA256` from the cacophony / `snow` vector files as more entries of `vectors` (`source: "published"`): `noise_run` replays any entry of that format, so it is data only, and a published vector that does not replay is a finding for the security pass.
2. **The prologue: `notchmeow-link/1`** (ASCII) for both patterns, so that two protocol versions cannot complete a handshake (the advert's `v` says the same number).
3. **The pairing code: a commit-then-reveal step, 6 digits only.** The owner chose it over moving to 8 digits, because `XX` has no commitment and a man in the middle could grind a 6-digit (or 8-digit) code offline. The design (Task 3, `docs/LINK-CONTRACT.md`) is the short-authenticated-string pattern of Vaudenay, ZRTP and Bluetooth's numeric comparison: the initiator commits to a fresh nonce and its static key in the first Noise message, the responder answers with its nonce, the initiator reveals, and the code is a hash of both nonces and both static keys. A man in the middle gets **one guess per attempt**, about 1 in 10^6. The owner's brief suggested the handshake hash as an input as well; **it is left out on purpose**: the last sender's payload (its name) is in that hash and can still be varied after it has seen the other side's nonce, which would let the attacker grind again. The static keys carry the authentication, because `XX` authenticates them. Task 4 pins the five cases the owner named, each with a `because` that a port tests: a wrong reveal and a commitment that does not match the static key (both `reveal-mismatch`: a commitment cannot tell a wrong nonce from a wrong key, on purpose), a reveal before the commitment (`no-commit`), a replayed commitment (`commit-replayed`) and a reveal after the 2 minutes (`reveal-late`). This adds three things to the wire: a 32-byte nonce in the hello, the commitment as the payload of the first message, and the one-byte `pair-yes` and `pair-no` frames that tell the other side how the user answered (a key is stored only when both said yes). The 8-digit value is gone.
4. **The wire layout:** a `u16` record length around every Noise message; an 18-byte clear first record (version, mode, device id) so that the responder of a transfer can find the stored key `KK` needs; the device id, name and nonce inside the encrypted pairing payload (so the card shows the authenticated name, never the advert's); frames of a type byte, the 16-byte transfer id and the body, numbers big-endian.
5. **The chunk size:** a sender cuts 32768 bytes; a receiver accepts up to 65494 (the most one Noise message holds).
6. **The offer's "type":** `kind`, printable ASCII up to 127 bytes, advisory only and never used to decide anything, because received files are never opened automatically.
7. **"4 GB" means 4 GiB, inclusive:** 4294967296 bytes is accepted, one more is declined as too large without a card.
8. **The file-name policy:** *reject* (decline as "not acceptable") what a real sender never sends: a path or a separator, a control, format or line-separator character (Unicode Cc, Cf, Cs, Zl, Zp), nothing left once spaces and dots are trimmed; *rewrite* platform differences: `< > : " | ? *` to `_`, trailing dots and spaces, a leading space, a Windows device name gets a `_`, a name over 200 bytes is cut keeping a 16-byte extension. The checks look at the NFC and the NFKC form; the kept name is NFC.
9. **Zero-width joiners and the Cf category:** rejecting the whole format category (the rule the shelf contract uses for names) also refuses a zero-width joiner, so a name with a family or skin-tone emoji sequence is refused. Kept: one simple rule that covers every bidi and invisible character.
10. **The limits of the name:** 1020 bytes on the wire (255 code points of up to 4 bytes, so a Windows name is not refused), at most 200 bytes saved (room under Windows' 260-character paths for `Downloads\NotchMeow\` and ` (9999)`), at most 63 bytes for a device name.
11. **The boundaries of the clocks and who counts:** a pairing attempt is allowed at exactly 30 s, the window is open below 120 s, an offer expires at exactly 120 s; a clock that went back never grants an attempt and never keeps an offer alive; an app counts an attempt when it starts a pairing and when it accepts an incoming one.
12. **What is declined without bothering the user:** a second offer (busy), a size over 4 GiB (too large) and a name the sanitizer rejects (not acceptable) are declined with a reason and no card; any frame that makes no sense in the state (a chunk before the click, a replayed or skipped chunk, a short `done`, a pairing answer in a transfer) closes the connection; a `cancel` for a transfer the receiver does not know is ignored.
13. **A sixth fixture file:** the spec lists five for G2-0; the receiver's and sender's rules are in a sixth, `flow-cases.json`, because rules about what to do with a frame are a different kind of thing from bytes.
14. **`offerCases`, not new rows in `alertCases`:** the flag's rows go in a new key (`offerCases`) and the trips at the end, and `alertCases` stays as it is, because the Mac's `DesktopCatTripTests.swift` and the Windows/Linux replay run `alertCases` through their own code today and would turn red on a `transferOffer: true` row until G2-mac and G2-tauri learn the flag.

## Self-review notes

- **Spec coverage.** "Discovery": the advert's TXT record (id, name, version) and its checks (`parse_txt`, Task 6); the listener, the browsing and the "Visible on this network" switch are app work. "Pairing": `Noise_XX_25519_ChaChaPoly_SHA256` and the first record (Tasks 2 and 6), the 6-digit code made safe by a commit-then-reveal step (Tasks 3 and 4: the commitment, the code, the two machines, the answers that must both be yes), the 30-second and 2-minute clocks (Task 3), the hello that carries the device id, name and nonce (Task 6); the Keychain items `link.static-key` and `link.peer.<id>` are app work. "Transfer": `Noise_KK_25519_ChaChaPoly_SHA256` (Task 2), the offer with name, size and type, accept, decline, chunks, done and cancel (Task 6), the 2-minute auto-decline (Tasks 3 and 7), the `name (1).ext` rule (Task 5), the card as an alert to the desktop cat (Task 8). "Safety rules": only paired keys open sessions, every frame authenticated and a tampered, replayed or out-of-order frame aborting (Tasks 2 and 7), the sanitizer (Task 5), the byte count equal to the offer (Task 7), the 4 GB and one-active-transfer limits (Tasks 6 and 7), no automatic resume (Task 7: there is no resume frame). "G1-0 and G2-0": all five files plus `flow-cases.json`, `reference.py` and `build_cases.py` (Tasks 1 to 7), the `transferOffer` flag with `desktop-cases.json` regenerated (Task 8), `docs/LINK-CONTRACT.md` and the bullets (Task 9). "Checks": the contract replay is what both app plans add; the cross-app check, the Debug fake peer and the owner's manual checks are the app plans'. Out of scope here: the entitlements and Info.plist keys, quarantine and mark-of-the-web, the Send menu, Settings, the cards, discovery, the Keychain.
- **Placeholders.** None: every code step carries its full content, generated into this plan from the files the dry run ran.
- **Type consistency.** The names `Handshake`, `noise_run`, `commit_of`, `pairing_code`, `pair_responder_step`, `pair_initiator_step`, `pairing_attempt_allowed`, `pairing_window_open`, `offer_expired`, `sanitize_name`, `unique_name`, `encode_frame`, `decode_frame`, `encode_hello`, `decode_hello`, `split_records`, `decode_preamble`, `parse_txt`, `receiver_step`, `sender_step`, `plan_chunks`, `FrameError`, `NoiseError` and the constants (`PROLOGUE`, `COMMIT_LABEL`, `CODE_LABEL`, `NOISE_MAX`, `CHUNK_MAX`, `SIZE_MAX` and the rest) are the same in the builders, the reference, the document and the interface table; the fixture keys (`vectors`, `rejectCases`, `commits`, `codes`, `invalid`, `session`, `gapCases`, `windowCases`, `offerCases`, `responder`, `initiator`, `machineTrips`, `frames`, `rejects`, `limits`, `hello`, `txt`, `preamble`, `records`, `recordEncode`, `receiver`, `sender`, `trips`, `chunkPlans`, `uniqueCases`) likewise. `offerCases` also names the cat fixture's `transferOffer` rows: they are in different files and are different rules.
- **Review Focus** lines 1 to 5 each have named tests above.
- **What this plan deliberately does not do:** touch either app; add a Swift, Rust or TypeScript port; fetch anything from the network; add a Windows CI path (G2-tauri does, with its replay); define the Settings and the cards of the pairing (the machines say what to show and when, the apps draw it).

## Dry run (2026-10-14, second run, after the owner's answers)

Run before the plan was handed over, in a fresh throwaway clone made with `git clone --local --shared --branch notchmeow/rebrand` of the repository at `d6704bd`, on a new branch `g2-0/link-contract`. The plan's text was generated from the files the clone ran, then replayed from its first line to its last by a small script that executes every fenced `bash` block of Tasks 1 to 9 in order, the five-backtick block included, and prints what each printed. All 53 blocks exited 0 and printed the plan's `Expected:` lines. The commit steps ran in the clone, so each task started from its predecessor's commit; nothing was committed, pushed or edited in the main checkout, where the plan file is the only change. The first dry run (before the owner's answers) had 47 blocks and 8 tasks.

| Task | Result |
|---|---|
| 1 | The skeleton fails with `NameError` until the primitives exist; with them the eight RFC checks pass; the four changes (a rotation, the Poly1305 clamp, the X25519 constant, the tag comparison) fail 2, 2, 4 and 1 checks |
| 2 | The vectors write 12735 bytes; the replay fails with `NameError`, then passes (43 ticks); the CryptoKit program, written separately, reproduces all four vectors message for message, the new `xx-link` (a real commitment and two real hellos with nonces) included; the eight changes fail 4, 2, 4, 6, 4, 2, 7 and 12 checks (the last two also end in an error) |
| 3 | The commitment and the code of the plan's example agree with `openssl dgst -sha256`; 97 ticks; the thirteen changes fail 6, 6, 8, 8, 8, 5, 3, 9, 1, 1, 1, 1 and 3 checks |
| 4 | 45183 bytes; 155 ticks; the 400 simulated pairings give equal codes and store exactly when both say yes, the 400 attacks by a man in the middle match at most twice, 6000 random scripts never raise; the eleven changes fail 4, 2, 1, 1, 2, 5, 3, 6, 2, 0 (it ends in an error: caught) and 1 checks |
| 5 | 20927 bytes; 278 ticks; the ten changes fail 6, 11, 6, 1, 9, 10, 3, 3, 1 and 11 checks |
| 6 | 24618 bytes; 431 ticks (the `xx-link` payloads decode to the commitment, the nonces and the code of the pairing case); the ten changes fail 3, 6, 4, 2, 2, 1, 2, 1, 2 and 1 checks |
| 7 | 28775 bytes; 512 ticks; the ten changes fail 5, 3, 3, 3, 1, 2, 1, 2, 2 and 2 checks |
| 8 | The Node test fails 3 of 5 until the flag exists; the whole cat suite then passes (324 tests: the cat contract's 319 and the five new ones); both additive checks pass; with the flag taken out again the new tests fail 2 |
| 9 | The table prints as the plan says; the document and the edits apply; every contract passes; no `__pycache__` appears |

**What drafting and the dry runs changed in the plan:**
- **The handshake hash cannot be in the code.** The owner's brief suggested deriving the code from both nonces and the handshake hash. The hash includes the last message's payload, a device name that the last sender can still vary after it has seen the other side's nonce, so a man in the middle could grind that name offline and match the two codes again. The code is made from the two nonces and the two static keys instead, which are all fixed before the reveal. `docs/LINK-CONTRACT.md` says why.
- **A change that survived.** In the first run the check on "an ephemeral key that is the zero point" passed even with the zero-point refusal switched off, because the damaged message was refused anyway. The two cases now say why they must stop (`because: "low-order point"`) and the replay compares the reason.
- **A mutation helper that could not see a crash.** A change that makes the reference raise an error instead of failing a check was counted as "0 failing". The helper now says "and then an error", which also counts as caught.
- **Hidden characters in the plan's own text.** The first draft's source had a real right-to-left override and zero-width space in two places (the cases that test them). They are written as `\u202e` and `\u200b` escapes now, so the plan and the code hold no invisible character.
- **The additive check against `1627851` proves nothing about `desktop-cases.json`**, because that file did not exist at that commit. The plan runs the check against `HEAD` before the commit and against `notchmeow/rebrand` after it as well.
- **`alertCases` must not change** (the Mac's and Windows/Linux's replays); the `transferOffer` rows are a new key, `offerCases`.
- **The vectors are checked by a second implementation.** The CryptoKit program, written separately from the Noise specification, reproduces all four vectors (including the new `xx-link`, whose payloads are a real commitment and two real hellos) message for message.
- **A pairing answer in a transfer would have raised an error** in the receiver (no transfer id on it); both flow machines now close the connection on it, with rows.
- **No bytecode in the repository.** Every Python command is `python3 -B`.

**Not run, by rule:** no NotchMeow app and no Tauri app was launched, no `xcodebuild`, `cargo`, `npm install` or network command ran, and nothing was added to the Keychain. The only compiler used was `swiftc` for the scratch cross-check. The G2-mac and G2-tauri plans replay these fixtures with CryptoKit and `snow`; until they do, the published Noise vectors (answer 1) are the one external check that is missing.
