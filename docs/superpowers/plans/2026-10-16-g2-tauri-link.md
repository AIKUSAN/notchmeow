# G2-tauri: Between Your Machines, in the Windows and Linux App: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sub-project G2 on Windows and Linux, the twin of the merged Mac port (G2-mac). A PC that has "Visible on this network" turned on (off by default) can pair with a Mac or another Windows/Linux PC that runs NotchMeow (matching six-digit codes, "They match" on both), and then send files to it and receive files from it over the local network. The receiver sees an **Accept card** for every file, which is an alert like an approval and which nothing accepts but a click; an accepted file streams over a Noise-encrypted channel into `Downloads/NotchMeow/` (on Windows with the mark of the web), is never opened by the app, and a transfer that does not complete leaves no file. The shelf gets a "To a device" button. Settings gets a Devices section. The Mac and the PC speak the same bytes, because both replay `tests/fixtures/link/`.

**Architecture:** Rust does the cryptography, the sockets and the files; the page only draws. Under `windows/src-tauri/src/link/` there is no Tauri type: every pure rule is a Rust port of the G2-0 contract (`docs/LINK-CONTRACT.md`, `tests/fixtures/link/`) replayed against the fixtures (`bytes`, `name`, `frames`, `pairing`, `flow`), the Noise layer is a thin wrapper on the `snow` crate (`noise`), the rules around the service are plain values (`cards`: the one card, the run gate, the machine's one transfer place, the connection caps), and the secrets, the settings and the files are small modules of their own (`keystore` on the system's credential store, `settings`, `directory`, `files`). On top sit the conversations (`channel`, `pair_run`, `transfer`: tokio tasks over a `Transport` trait, tested between two in-memory ends and over loopback), the network (`net`: a TCP transport and the listener; `discovery` and `mdns`: the advert and the browser on `mdns-sd`) and `service`, **one actor** that owns all the state, handles one command at a time and sends the page a whole `Snapshot` every time something changes. `link_cmd.rs` is the only file that meets Tauri: the commands and the `link` event. The page keeps the last snapshot (`State.link`) and draws it: a new island view (`views/link.ts`), a Settings → Devices section, and "To a device" on the shelf. There is no listener and no advert until the user turns Visible on, the daemon for mDNS exists only while the machine is announced or someone looks at Devices or the shelf, and nothing polls.

**Tech Stack:** Rust (Tauri 2, tokio, `snow` 0.9, `mdns-sd` 0.11, `keyring` 3 which is already in the tree, `sha2`, `unicode-normalization` and `getrandom` which are already in `Cargo.lock`), TypeScript 5 and Vite 6 (already in `windows/`), Node 22 (`node --test` reading the TypeScript source with `--experimental-strip-types`), Swift (one test file and two scripts of the Mac side, for the follow-ups of G2-0b), `playwright-cli` (headless Chromium, for the pictures only). No new npm package.

**Spec:** `docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md`, revision 2026-10-14, sections "G2. Between your machines", "Checks", "Rounds", "Plans and order", "Risks" and "Done means". The contract is G2-0's, with G2-0b's three connection rules: `docs/LINK-CONTRACT.md` and `tests/fixtures/link/` (`noise-vectors.json`, `pairing-cases.json`, `frames.json`, `flow-cases.json`, `filename-cases.json`, `reference.py`, which decides when this plan's code and a fixture disagree). The Mac twin is merged: `docs/superpowers/plans/2026-10-15-g2-mac-link.md`, its code `NotchBuddy/Sources/App/Link*.swift` and its archived ledger `.claude/archive/sdd/g2-mac-link/progress.md`, whose review findings this plan builds in from the start (see "What the Mac learned" below). The format and the conventions are the last Windows plans': `docs/superpowers/plans/2026-10-14-g1-tauri-shelf.md` and `2026-10-14-f1-tauri-sidekick.md`.

**Base:** a new branch `g2/tauri-link` in a git worktree, from `notchmeow/rebrand` at **`dc91b739` or later**. `git merge-base --is-ancestor a589fcb8 HEAD` (G2-mac is merged) and `git merge-base --is-ancestor d2b23670 HEAD` (G2-0b, the contract's three connection rules) must both succeed. **Run it when U1b (`docs/superpowers/plans/2026-10-16-u1b-windows-island-parity.md`) is merged, or not beside it**: both plans edit `lib.rs`, `island.ts`, `state.ts`, `main.ts` and `desktop.ts`, and U1b's own text says it must not run beside this one. The Setup block checks every find text of this plan against the tree, so a base that moved is found before the first task, not in the middle of one.

## What the Mac learned, and this plan builds in

The Mac plan's ledger holds one review finding after another. Each one that is not Mac-specific is a requirement here, with a test that names it:

| The Mac's finding | Where it lives here |
|---|---|
| A failed read of the credential store must not make a fresh key or id (and lose every pairing); a damaged item is reported, never replaced | `keystore.rs`: `Lookup::Failed` is an error, only `Absent` makes a secret; tests `a_failed_read_never_makes_a_fresh_key_or_id`, `a_damaged_device_id_is_reported_and_not_replaced` (Task 6) |
| The paired list read from the store can come back empty when the store is locked: keep the last good map and say so | `Keystore::paired_machines(expecting_some)` → `Suspect` (Task 6) and `reload_peers` in the service (Task 13) |
| A completed file must not be deleted by a later discard; a dropped sink removes its partial file; a file that cannot be marked is not handed out; a discard never removes another file that took the name | `files.rs` (Task 7) |
| One card slot: another flow's card must never replace the one the user is about to click; a click is ignored for 700 ms after the card changes kind and when it was meant for another card; an offer is keyed by machine and transfer id | `cards.rs` `CardRules` (Task 5), the service's `present` (Task 13), the card's `shownOf` (Task 9) |
| A late event of a stopped conversation must act on nothing: tickets and a generation | `cards.rs` `RunGate` (Task 5); every hook of the service carries its ticket or generation (Task 13) |
| A connection must not be able to wedge a conversation or hold its place: the first frame within 10 s, a chunk within 60 s, an offer unanswered for 130 s given up by the sender, every frame this side sends given 2 s then the connection is cut, a cancel during the handshake waited for 2 s, at most 4 frames read ahead, 8 connections in all and 2 per machine, 8 pending handshakes and 2 per address, 10 s for a handshake | `channel.rs` (`IdleWatch`, `FrameWindow`, `send_best_effort`), `transfer.rs`, `net.rs`, `cards.rs` `ConnectionCaps` (Tasks 5, 11, 12) |
| Only a chunk is activity: a stream of other frames must not keep a stalled transfer or a silent connection alive | `transfer.rs`, test `only_a_chunk_pushes_the_stall_limit_back` (Task 11) |
| One decline per connection (the second ends it, nothing sent), one transfer for the whole machine, the claim given back at once when the machine declines the offer itself and again after the run is cleared | `flow::connection_step`, `cards.rs` `Busy`, `transfer.rs`, `service.rs` `receive_ended` (Tasks 4, 5, 11, 13) |
| Cancel on the sending side: the cancel frame goes first so the receiver sees "cancelled", the connection is cut only if the frame cannot go out; the status line says "Finished sending", never "Sent" or "Saved" (the protocol has no receipt) | `transfer.rs` `SendHandle::cancel`, `service.rs` `send_job` (Tasks 11, 13) |
| Forgetting a machine withdraws its waiting offer and cancels its running file at once | `service.rs` `refuse_transfer_from`, test `forgetting_a_machine_withdraws_its_waiting_offer` (Task 13) |
| Visible off cancels everything that is running and cuts every connection, also those with no run yet; a connection accepted by a stopped listener is closed however late its task runs | `service.rs` `stop_listening`, `preamble` (generation check), tests (Task 13) |
| A pairing code takes the card only if no other card with buttons is up and no offer is claimed (`reserve_card`); an incoming pairing runs only inside the gate | `cards.rs` `Busy::reserve_card`, `pair_run::run_incoming`, `service.rs` `preamble` (Tasks 5, 11, 13) |
| The clock used for the windows must count while the machine sleeps | `cards::now_ms` (`CLOCK_BOOTTIME`, `GetTickCount64`) (Task 5) |
| The default device name is the computer's own name: say so under the field (the Mac added "Machines on this network see this name.") | `settings/devices.ts` (Task 10) |
| A dev run must never touch the real pairings | `keystore::SERVICE` is `...notchmeow.debug` in a debug build (Task 6) |
| No name, size, address or id reaches a log; no picture or link source reads the machine's name or user | `Emit::log(&'static str)`, `scripts/link-tests/rust-wiring.test.mjs` (Tasks 13, 15) |

## Global Constraints

Every task's requirements include this section. Values are copied from the spec and from the contract; lines marked "(plan decision)" are choices this plan makes where they are silent, and are listed again under "Open questions for the owner".

- **Dependencies (CLAUDE.md: "No third-party dependencies unless truly unavoidable").** New in the build: `snow` 0.9 (Noise) and `mdns-sd` 0.11 (mDNS), **approved by the owner on 2026-10-14**. Named directly in `Cargo.toml` but already in `Cargo.lock` through other crates, so they add no code to the build: `sha2` 0.10 (the pairing commitment and the six digits), `unicode-normalization` 0.1 (NFC and NFKC for the file-name rule: the standard library has neither) and `getrandom` 0.2 (nonces, device ids, transfer ids). `keyring` 3 is already a direct dependency (`secrets.rs`). `tokio` gains the feature `rt-multi-thread` it already has through Tauri. No new npm package. `scripts/link-tests/rust-wiring.test.mjs` pins the list. **Why these cannot be avoided:** Noise's X25519, ChaCha20-Poly1305 and SHA-256 handshake is cryptography nobody should write twice (the contract demands the exact protocol, so a different library would not talk to the Mac); mDNS needs multicast sockets, a resolver and the DNS-SD record format, which are a library's work (the owner named the crate in the spec); the other three are one function each that the standard library lacks.
- **Every pure rule is replayed against `tests/fixtures/link/`** in Rust (`cargo test -p notchmeow link::`): the Noise vectors and the twenty damaged-message cases, the clocks, the commitment, the code, the two pairing machines and their trips, the six frames, the hello, the advert, the preamble, the records, the chunk plans, the receiver, the sender and their trips, **`places[]`, `connections[]` and `firstFrame[]`**, the 162 file-name cases and the collision cases. `tests/fixtures/link/reference.py` decides when this plan's code and a fixture disagree. The page holds no contract rule of its own: the one contract rule in TypeScript is `desktopAlert`'s `transferOffer` flag (`offerCases`).
- **Visible on this network is off by default.** Until the user turns it on in Settings → Devices there is no listener, no advert, no mDNS daemon, no Windows Firewall prompt. Once on it stays on until turned off (`link.json` holds the switch and the name; nothing else). A machine must be visible to pair and to receive; searching for others needs it on too and happens only while Settings → Devices or the shelf is on screen.
- **Pair once, accept each time.** Both screens show the same six digits (commit-then-reveal); a key is stored only when both users said "They match". At most one pairing attempt every 30 s; the pairing window is 2 minutes. **An incoming pairing is allowed only while Settings → Devices is on screen on this machine, or within 2 minutes after the user clicked Pair here** (the owner's answer of 2026-10-15; `pairing::Gate`). Outside the gate the hello is refused silently: nothing sent, the connection closed, no card, no alert. **Only a click accepts an offer.** An offer unanswered for 2 minutes is declined by itself. The Accept card is an alert like an approval: it opens the island even when hidden, holds it open, the desktop cat flies to the notch for it (`transferOffer` in `desktopAlert`) and the cats do not fall asleep through it.
- **Keys live in the credential store and nowhere else:** the Windows Credential Manager, or on Linux the Secret Service (GNOME Keyring, KWallet), through `keyring`: `link.static-key` (`{"k","p"}`), `link.device-id`, `link.peers` (the index: the stores cannot list their items) and `link.peer.<id>` (`{"n","k","t"}`). Never in a file, a setting, a log or a fixture. **Without a Secret Service on Linux every read fails; the link says so in Settings → Devices and stays off; it never falls back to a file** (plan decision, question 4). A debug build keeps all of them under the service `io.github.aikusan.notchmeow.debug`; a release build under `io.github.aikusan.notchmeow`. No test writes under the real name (the tests use a memory store).
- **Received files** go to `Downloads/NotchMeow/` (Windows: the Downloads known folder, which may be redirected; Linux: `XDG_DOWNLOAD_DIR` or `~/Downloads`), named by `name::sanitize_name` and numbered by `name::unique_name`, created **exclusively** (`create_new`: `CREATE_NEW` on Windows, `O_EXCL` on Linux, with `O_NOFOLLOW` and mode 0600 until complete), **never opened, run or followed**. Windows writes the **mark of the web** (`Zone.Identifier`, `ZoneId=3`) when the file is created, so even a partial file carries it; a file that cannot be marked (a drive without streams, such as FAT) is discarded and the transfer fails with "Transfer stopped" (plan decision, question 3). Limits: 4 GiB per transfer, one transfer at a time for the whole machine, no automatic resume, transfers end when the app quits. The received byte count must equal the offer; a transfer that does not complete leaves no file.
- **0 % CPU when the island is hidden; nothing polls.** The listener waits on a socket and every change comes from a callback or a channel. No interval, no polling loop, no thread sleep. The only sleeps are one-shots that exist while something is pending: an `IdleWatch`, the pairing window, an offer's 2 minutes, the listener's 10 s watchdog and its 50 ms accept back-off after an error (`rust-wiring.test.mjs` counts them). The mDNS daemon, which opens the multicast sockets and a thread, is made only when the machine is first announced or the first search starts and is shut down when both are over. On the page: `IntersectionObserver` and events; no timer.
- **No telemetry.** The log (`notchmeow.log`) gets fixed sentences only: "listening", "stopped listening", "a pairing ended", "a transfer started", "a transfer ended". No name, size, address or id. This computer's name is read once, in `link/settings.rs`, for the default device name.
- **Never restyle a shipping view.** New views follow the existing app style (the approval card's `card`, `stack`, `btn`, `.title`, `.sub`, `.code`, `.actions`; Settings' `.row`, `.switch`, `.hint`, `button`, `input`). Every edit to an existing file is listed in "File Structure" and is additive: a union member and a layout entry, one `map.set`, one field and one getter on `State`, one flag on the desktop cat's alert, one `||` on the sleep's `blocked`, one section in Settings, four lines in the shelf view, one icon, and the lines of `main.ts` that attach the backend. All the link's CSS is in its own file (`link/link.css`), every rule prefixed `lk-` but one modifier of the shelf's head (`sh-choosing`).
- **Frozen values:** the island view name `link`; the page event `link`; the command names `link_*`; the credential accounts above and the two service names; `link.json` with the keys `visible` and `deviceName`; the mDNS type `_notchmeow._tcp` and its TXT keys `v`, `id`, `name`; the dev query `?linkdev=`; the cat contract's `transferOffer`; pill IDs, cat IDs, the contract strings (`nm-hook`, `nm.sock`, `notchmeow-hook`, `nm_kind`, `nm_agent`) and the bundle identifiers.
- **The page holds ids, never a path, a key or an address.** `link_send` takes shelf ids and Rust finds the files; a card carries a `{kind, key}` back with every click; the snapshot has no key, no address and no path but the received folder, to show.
- **Rust runs only through `windows/scripts/cargo-linux.sh`, with `--target-dir /repo/windows/target/g2-tauri`, and never builds or pulls the Docker image.** Windows-only Rust (the Credential Manager store, the known-folder call, the `Zone.Identifier` write, `GetTickCount64`) is not compiled by anything the session can run: it is owed to CI (`windows-tests.yml`). Task 2 Step 3 is the **one step that downloads** (crates.io, through the container, for `snow` and `mdns-sd` and what they need): the controller asks the owner in chat and waits for a yes first.
- **Never edit `NotchBuddy/`, `docs/LINK-CONTRACT.md`, a fixture of `tests/fixtures/`, `design/prototype/cat-core.js`, `shared/theme.json` or a generated theme file.** The Mac side of this plan is two test-side files and two scripts (Task 1), and nothing under `NotchBuddy/`.
- **Models and commits** (CLAUDE.md): Haiku 5.5 first, Sonnet 5.5 only on a named trigger, never Opus or Fable. Each commit is local only, never pushed, lists only the files its task names, and ends with the `Co-Authored-By` line of the model that did the task: `Claude Haiku 5.5 <noreply@anthropic.com>` for `nm-implementer-light` and `nm-implementer`, `Claude Sonnet 5.5 <noreply@anthropic.com>` for `nm-implementer-deep`.
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app, and never start the Tauri app (`npm run tauri dev`, a built `notchmeow.exe`): the owner runs it. Serving the front end with `npx --no-install vite` and looking at it in the headless `playwright-cli` browser is allowed, and only that. The tests may open sockets on `127.0.0.1` only; nothing connects to another address, and no test or task uses mDNS or the real credential store.
  2. Install nothing, download nothing, use no network except `127.0.0.1`, and never run `docker build` or `docker pull`. **The one exception is Task 2 Step 3, and only after the owner's yes.** If `docker image inspect notchmeow-linux-dev` fails or the daemon is down, say so: the Rust steps are owed, and the TypeScript tasks go on.
  3. Use `trash`, never `rm -rf`. Pictures and one-off scripts go in `.claude/checkpoints/g2-tauri/` (gitignored). Stop the dev server by its saved PID only, close browsers by session name (`playwright-cli -s=<name> close`), never `close-all`, and run `playwright-cli` from `.claude/checkpoints/g2-tauri/` with the default `TMPDIR`.
  4. Never edit `design/prototype/cat-core.js`, a fixture of `tests/fixtures/`, `docs/LINK-CONTRACT.md`, `shared/theme.json`, `NotchBuddy/`, `windows/src/upload/`, `windows/src/views/upload.ts`, `windows/src/views/icons.ts` or a generated theme file. `windows/src/style.css` is not edited at all (the link has its own style sheet).
  5. Never read, print or write the real `~/.claude`, `%USERPROFILE%\.claude` or the owner's own folders, and never touch the real credential store or the real `Downloads`: the tests make their own temporary folders and use the memory store.
  6. If a step's find text occurs zero or two times, or a command is refused, stop and report: do not look for another way.
  7. Haiku 5.5 for every task except those the table below names (Tasks 2, 11, 12, 13); never Opus or Fable.
  8. Never rename a frozen value, and write no `Coucou` or `Mochi` name anywhere. Use only sample names in code, tests, comments and pictures ("Sam's MacBook Pro", "Desk PC", "Studio laptop", "Old netbook"), never a real person's or machine's name.
  9. A test that can hang (every conversation test) ends by itself; if a command runs longer than ten minutes, stop it by its PID only and report.

## Review Focus

The spec says what the link does. It is silent on these inputs and conditions, each of which would bite a person first (most likely first). Each names the test that pins it.

1. **A machine that is not paired, or a peer that keeps asking.** A stranger on the Wi-Fi opens a transfer with a paired id, sends a pairing attempt every few seconds, or opens connections and says nothing. Expected: a pairing hello outside the gate is refused silently (no card, no alert), an unknown device id is closed without an answer, a second attempt inside 30 s and a replayed commitment are refused, a connection that has not finished its handshake in 10 s is cut and at most 8 wait at once (2 per address), a connection that says nothing after its handshake is closed at 10 s and other frames do not keep it alive, a key that does not match the stored one cannot finish the handshake. Tests: Task 4 (`pairing` rows: `attempt-too-soon`, `commit-replayed`, the gate's edges at 119 999 ms and 120 s), Task 11 (`outside_the_gate_nothing_is_sent_and_no_card_is_shown`, `a_connection_that_says_nothing_after_its_handshake_is_closed_after_10_seconds`, `frames_that_are_not_an_offer_do_not_keep_a_silent_connection_alive`, `a_machine_that_is_not_paired_under_this_key_cannot_complete_the_handshake`), Task 12 (`at_most_two_connections_wait_from_one_address`, the watchdog test), Task 13 (`an_incoming_pairing_outside_the_gate_is_refused_silently`, `a_transfer_from_a_machine_that_is_not_paired_is_closed_without_an_answer`).
2. **A hostile or clumsy file name, and a name that is already taken.** `../../x`, `CON`, a zero-width character, a name 1 000 bytes long, a file with the same name in Downloads, a symbolic link with that name. Expected: the offer is declined as not acceptable or the name is rewritten, the saved name is at most 200 bytes, nothing is overwritten and nothing is followed through a link, and the machine's place is given back at once. Tests: Task 3 (162 name cases, the collision cases, a seeded walk), Task 7 (`a_name_that_is_taken_is_numbered...`, `a_link_with_the_wanted_name_is_not_followed`, `a_name_that_is_a_path_is_refused_by_the_sink_itself`), Task 11 (`a_hostile_name_is_declined_as_not_acceptable_and_nothing_is_written`).
3. **The connection or a user ends the transfer half way.** The other machine sleeps, the Wi-Fi drops, the sender cancels, the user clicks Cancel, the sender's file shrinks while it is read, the sender stops sending. Expected: both sides end, the partial file is deleted, the card says nothing was saved, and a transfer never "completes" with fewer bytes than offered. Tests: Task 11 (`the_receiver_cancels_in_the_middle_and_the_partial_file_is_gone`, `a_sender_that_stops_sending_is_cut_after_60_seconds_and_the_partial_file_goes`, `done_before_every_byte_has_come_is_short_and_saves_nothing`, `a_file_that_shrinks_while_it_is_sent_is_cancelled_by_the_sender`), Task 4 (`short`, `order`, `overflow` rows).
4. **No Secret Service, a blocked firewall, Visible turned off while something is going on.** Linux with no keyring running; Windows Firewall set to "Cancel" on the first prompt; the user turns Visible off with an offer on the island. Expected: the link says why it cannot start and stays off (no key is made, nothing is written to a file), turning Visible off stops the listener, cancels what is running and clears the card, and a key read that fails is never turned into a new key. Tests: Task 6 (`a_failed_read_never_makes_a_fresh_key_or_id`), Task 13 (`turning_visible_off_while_an_offer_waits_clears_the_card_and_cuts_the_connection`, `nothing_listens_and_nothing_is_announced_until_visible_is_turned_on`), owner checks 3 and 10 in Task 16.
5. **An Accept card nobody sees, or a card replaced under the cursor.** The island is hidden, folded, the user is in another app; two machines offer at once; a pairing code arrives while an offer waits. Expected: the card opens the island and the desktop cat flies in, it is not folded by the idle timer, it is declined after 2 minutes, a second offer is declined as busy and gets no card, a click that lands within 700 ms of a card changing kind or on a card that is gone does nothing. Tests: Task 5 (`CardRules`, `Busy`, `RunGate`), Task 8 (`transferOffer` in `desktopAlert`, the sleep), Task 9 (`cardTransition`), Task 11 (`an_offer_nobody_answers_is_declined_after_two_minutes_and_creates_no_file`, `a_second_transfer_while_one_runs_is_declined_as_busy_and_gets_no_card`), Task 13 (`a_click_meant_for_another_card_does_nothing`), owner check 6.

---

## File Structure

All paths are under `windows/` unless they say otherwise.

| Path | Responsibility |
|---|---|
| `src-tauri/src/link/bytes.rs`, `name.rs`, `frames.rs` | New. Lower-case hex and fixed-size ids; the file-name rule (`sanitize_name`, `unique_name`, with the hand-written Unicode tables); the wire shapes (records, preamble, hello, advert, the six frames, `plan_chunks`). Replay `frames.json` and `filename-cases.json`. |
| `src-tauri/src/link/pairing.rs`, `flow.rs` | New. The commitment, the six digits, the three clocks, **the gate on incoming pairings**, the two pairing machines; the receiver's and the sender's machines, **`place_step`, `connection_step`, `first_frame_expired`**. Replay `pairing-cases.json` and `flow-cases.json`. |
| `src-tauri/src/link/noise.rs` | New. A wrapper on `snow`: the two patterns, the prologue, the low-order check, the static-key helpers. Replays `noise-vectors.json`. |
| `src-tauri/src/link/cards.rs` | New. `CardRules`, `RunGate`, `Busy`, `ConnectionCaps`, `ReadLimit`, `now_ms`: the Mac's `LinkCardRules.swift`, case for case. |
| `src-tauri/src/link/identity.rs`, `keystore.rs`, `settings.rs`, `directory.rs` | New. `Identity` and `Peer`; the credential store (`SecretStore`, `MemoryStore`, `SystemStore` on `keyring`) and `Keystore`; `link.json`; the list of machines. |
| `src-tauri/src/link/files.rs` | New. `Sink` (exclusive create, numbering, 0600 then 0644, the mark of the web, discard), `Source`, the Downloads folder. |
| `src-tauri/src/link/channel.rs`, `pair_run.rs`, `transfer.rs`, `conformance.rs` | New. `Transport`, `Channel`, `IdleWatch`, `FrameWindow`, `MemoryEnd`; one pairing conversation on either side; one transfer on either side; the recorded conversations of `noise-vectors.json` played through the real runs. tokio. |
| `src-tauri/src/link/net.rs`, `discovery.rs`, `mdns.rs` | New. `TcpTransport` and `Listener`; the `Discovery` trait; its one network implementation on `mdns-sd`. |
| `src-tauri/src/link/service.rs`, `mod.rs`, `testutil.rs` | New. The actor: `Service`, `Snapshot`, `Config`, `Deps`, `Emit`; the module list; the fixture reader of the tests. |
| `src-tauri/src/link_cmd.rs`, `src-tauri/examples/link_peer.rs` | New. The only Tauri file of the link (the commands, the `link` event, `init`); the owner's real-protocol test peer. |
| `src/link/model.ts`, `text.ts`, `backend.ts`, `mock.ts` | New. The snapshot as the page holds it (`cleanSnapshot`, `cardTransition`, `LinkStore`, `LinkBackend`); the words of the cards; Rust's backend; the stand-in for a plain browser and the checks. |
| `src/link/devseed.ts`, `devlink.ts`, `link.css` | New. The states worth looking at; the `?dev` Link panel; every style of the link (all `lk-`). |
| `src/views/link.ts`, `src/views/shelfdevice.ts`, `src/island/link.ts`, `src/settings/devices.ts` | New. The island's link card; "To a device" on the shelf's head row; what the island does for a card; Settings → Devices. |
| `scripts/link-tests/model.test.mjs`, `alert.test.mjs`, `wiring.test.mjs`, `rust-wiring.test.mjs`, `snapshot-samples.json` | New. `npm run check:link`. |
| `src/core/state.ts`, `src/core/layout.ts`, `src/views/views.ts`, `src/views/shelf.ts`, `src/shelf/icons.ts` | Changed, additively: `State.link` and `linkOfferPending`; the `link` view name and its layout; one `map.set`; four lines in the shelf view; one icon. |
| `src/island/island.ts`, `src/island/desktop.ts`, `src/cat/desktop.ts`, `src/cat/dev.ts`, `src/main.ts`, `src/settings/main.ts`, `package.json` | Changed, additively: one `||` on the sleep's `blocked`; one flag to the desktop cat's alert, and its rule; the `?dev` panel; the attach and the island's two lines; the Devices section; `check:link`. |
| `src-tauri/Cargo.toml`, `Cargo.lock`, `src-tauri/src/lib.rs` | Changed: five dependencies and one tokio feature; the module, the commands, the service, the settings window's hide. |
| `README.md`, `../CLAUDE.md`, `../ARCHITECT.md`, `../docs/SPEC.md`, `../.github/workflows/windows-tests.yml`, `../.github/workflows/linux.yml` | Changed: the docs, the CI path filters and one step. |
| `../tests/LinkFlowTests.swift`, `../scripts/test-link-flow.sh`, `../scripts/check-fixtures-additive.mjs`, `../tests/cat/additive.test.mjs` | Changed (Task 1): the Mac's replay of `places[]`, `connections[]` and `firstFrame[]`; the additive check covers `tests/fixtures/link/`. |

**Staged edits.** Most tasks edit files earlier tasks created or changed. Every edit below is a Python script whose replacements assert that the find text occurs exactly once; the text is what the tree has after the tasks before it. Run each script from the repository root, as it is. If a find text occurs zero or two times, stop and report: the tree is not what the plan expects.

## Parity with the Mac, and where the PC differs

The bytes, the rules, the clocks and the files are the contract's, so the two apps talk to each other. The differences are the platform's:

| | Mac (G2-mac) | Windows and Linux (this plan) |
|---|---|---|
| Crypto | CryptoKit, hand-written Noise | `snow`, wrapped |
| Discovery | `Network.framework` (`NWListener`, `NWBrowser`) | `mdns-sd`, IPv4 only, daemon made on demand |
| Keys | Keychain (`SecItem`), listable | Credential Manager / Secret Service through `keyring`, **not listable** (an index item), fail closed without a Secret Service |
| Received file | quarantine attribute (by hand in the GitHub build, the sandbox in the App Store build) | Windows: `Zone.Identifier` stream; Linux: no mark exists |
| Settings storage | `UserDefaults` | `link.json`, written by Rust alone (the page's settings save can never drop it) |
| "Devices is open" | the Devices pane's `onAppear`, counted, with a window watcher | a **state** (`set_devices_open(bool)`), reported by the section's `IntersectionObserver`, forced to "not open" by Rust when the Settings window hides |
| Debug fake peer | a panel with a loopback peer in the app | the `?dev` Link panel (a stand-in service for the page) and `cargo run --example link_peer` (the real protocol, in a terminal) |
| Clock | `CLOCK_MONOTONIC_RAW` | `CLOCK_BOOTTIME` / `GetTickCount64` |
| Listener hardening (not in the contract) | 10 s handshake, 8 pending, 2 per address, 8 established, 2 per machine, 30 s/60 s/130 s watches | the same numbers (the Mac's reviews arrived at them) |

## Tasks and agents

CLAUDE.md: the lightest model that fits. **Haiku 5.5 first; Sonnet 5.5 only on a named trigger.** The code is given in full in every task and its tests prove it (a dry run of the pure Rust and the page is described at the end). **Tasks 2, 11, 12 and 13 are `nm-implementer-deep` (Sonnet 5.5, high): trigger 1**, platform APIs and concurrency the task must get right rather than copy: Task 2 meets the `snow` crate's API (it is not in the tree and could not be compiled while this plan was written, so the replay of the Noise vectors is what decides); Task 11 is tokio tasks, cancellation and ordering over a cipher state; Task 12 is sockets, the listener's caps and watchdog, and the `mdns-sd` crate (also not compilable while this plan was written); Task 13 is the actor that joins them to the app, the island's alert path and the Settings window. If a Haiku task's expected output differs and the cause is not obvious, or it fails twice, hand it to `nm-implementer-deep` (trigger 2) and say so in the ledger. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; the deep ones also `superpowers:systematic-debugging`; reviewers load `ponytail:ponytail-review`. The agents of Tasks 9 and 10 also load `playwright-cli`. Ponytail never cuts what this plan asks for, nor tests, security or privacy rules.

| # | Task | Agent, model, effort | Review |
|---|---|---|---|
| 0 | Worktree and baseline | the session | none |
| 1 | The Mac's follow-ups of G2-0b: the Swift replay of `places[]`, `connections[]`, `firstFrame[]`; the additive check covers the link | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 2 | Dependencies, the `link` module, hex, and the Noise layer on `snow` against the vectors | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `nm-reviewer` |
| 3 | The file-name rule and the wire shapes | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 4 | The pairing and the transfer rules: the machines, the clocks, the gate, the connection rules | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 5 | The rules around the service: the card, the run gate, the transfer place, the caps, the clock | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 6 | The credential store, the settings and the list of machines | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 7 | The files: the sink, the source, the Downloads folder, the mark of the web | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 8 | The page's link: the snapshot, the backend, the stand-in, `State.link`, the desktop alert | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 9 | The link card, the island's part, the `?dev` Link panel | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 10 | Settings → Devices and "To a device" on the shelf | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| | **Checkpoint 1:** the owner looks at the pictures | the executing session and the owner | none |
| 11 | The conversations: channel, pairing run, transfer runs, the recorded conversations | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `nm-reviewer` |
| 12 | The network: transport, listener, the advert and the browser | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `nm-reviewer` |
| 13 | The service, the commands and the app's wiring | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `nm-reviewer` |
| 14 | The test peer and the cross-app check | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 15 | Docs, CI and the pins | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| After 15 | The whole branch, with the security pass | `nm-reviewer-deep`, Sonnet 5.5, high (trigger 4) | none |
| 16 | **Checkpoint 2:** the pictures, then the real-machine checklist (with the Mac) | the executing session and the owner | none |

## Execution

One worktree chat session runs the whole plan: branch `g2/tauri-link`, model **Sonnet 5.5 at high effort** (trigger 5, and trigger 1 for Tasks 2, 11, 12 and 13: an app plan with a listener, new cryptography, a credential store and the island's alert path; `ARCHITECT.md`). Nothing is pushed. It edits `lib.rs`, `island.ts`, `state.ts`, `main.ts` and `desktop.ts`, so it must not run beside U1b (see "Base"); the Mac's G2 is merged, and G2-tauri touches nothing under `NotchBuddy/`. The session never starts the Tauri app: the owner's real-machine checks are Task 16.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up (it carries the owner's advance approval of the brief in step 3):

   > Run `git switch -c g2/tauri-link notchmeow/rebrand`, then the Setup block of `docs/superpowers/plans/2026-10-16-g2-tauri-link.md`: only its checks (the two `merge-base --is-ancestor` lines, the contract files, the find-text pre-flight, the baseline). Read `CLAUDE.md`, `ARCHITECT.md`, `windows/README.md`, that plan, `docs/LINK-CONTRACT.md` and `docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md`. If a check fails, say so and stop. Reply "ready" and stop. Do not start Task 1. The owner approves in advance the controller brief the main session will send as your next message.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message.

**Controller brief** (what the main session sends once the model is set):

> Run `docs/superpowers/plans/2026-10-16-g2-tauri-link.md` with `superpowers:subagent-driven-development`, task by task, on branch `g2/tauri-link`. You are the controller: Sonnet 5.5 at high effort (CLAUDE.md triggers 1 and 5). Dispatch each task to the agent the plan's "Tasks and agents" table names: `nm-implementer` (Haiku 5.5, high) by default, `nm-implementer-light` for the tasks the table gives it, `nm-implementer-deep` for Tasks 2, 11, 12 and 13 and for a task Haiku failed twice (then the trigger goes in the ledger); then `nm-reviewer` after every task, fixing what the review finds before the next one; and `nm-reviewer-deep` once over the whole branch at the end, with the security pass. Never Opus or Fable. Rules for you and for every subagent (put the plan's SUBAGENT RULES block in every brief):
>
> - **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder (under `.claude/worktrees/`), the second `g2/tauri-link`. If either is wrong, stop and report. Commit with `git commit -F -`, the message on stdin, ending with the `Co-Authored-By` line of the model that did the task. Commit once per task. **Never push.**
> - **Ledger.** Keep a manual ledger at `.superpowers/sdd/2026-10-16-g2-tauri-link/progress.md`: the base commit (`git merge-base HEAD notchmeow/rebrand`), then one line per task with its agent, model, commit hash, test lines and review verdict, and any escalation to `nm-implementer-deep` with the trigger.
> - **Briefs are task-sized.** A brief carries one task: its text, the Global Constraints, the SUBAGENT RULES and the files it names. Never hand a subagent the whole plan.
> - **Edits are exact.** An edit script's find text must occur exactly once in the file. **If it does not, stop and report** (the tree is not what the plan expects): never "fix" the find text or type a block from memory.
> - **Reviews** read `git diff "$(git merge-base HEAD notchmeow/rebrand)"...HEAD` (three dots), narrowed to the task's files, never `..` and never a diff against a moving working tree.
> - **Every shell block in the plan passes `bash -n` before it is run**, and a script you write passes it too.
> - **The apps.** **Never launch, quit, replace or open the NotchMeow in `/Applications`, and never start the Tauri app.** The pictures come from the Vite dev server and `playwright-cli`; the checks come from the test scripts. The owner runs the real app in Task 16.
> - **Rust.** Only through `windows/scripts/cargo-linux.sh` with `--target-dir /repo/windows/target/g2-tauri`. Never build or pull the Docker image: if `docker image inspect notchmeow-linux-dev` fails or the daemon is down, say so; the Rust steps are owed and the TypeScript tasks (8, 9, 10, 15) go on. **Task 2 Step 3 downloads crates (`snow`, `mdns-sd` and what they need): ask the owner in chat first and wait for a yes. No other step downloads.**
> - **Servers and processes.** Stop a process only by the PID you saved when you started it (`kill "$(cat .claude/checkpoints/g2-tauri/vite.pid)"`), never `kill $(lsof ...)`. Close `playwright-cli` browsers by session name, never `close-all`.
> - **Stop and report on any refusal** (a denied command, a permission prompt): do not look for a workaround.
> - **Ping the main session.** Address it by its name in `ListAgents`, `NotchMeow — fork research & cat design`, with `SendMessage`. At **Checkpoint 1**, at the end (Task 16), and whenever you stop (a refusal, a failed check, a find text that does not occur once, a question), send your report to it as well as writing it in your own chat, so the main session can double-check the work (its own clone, merge and full checks) before anything reaches the owner.
> - **Checkpoints.** Run Tasks 1 to 10, then stop for **Checkpoint 1** (the pictures; the list is under the checkpoint) and wait for the owner. After the owner's reply run Tasks 11 to 15, dispatch `nm-reviewer-deep` over the whole branch, fix what it finds (a small `nm-implementer` task, then a scoped re-review by `nm-reviewer`), and stop for **Checkpoint 2** (Task 16) with the pictures and the real-machine checklist.
>
> Report: the commits; for `windows/`: `npx --no-install tsc --noEmit`, `npm run check:link`, `npm run check:cat`, `npm run check:sidekick`, `npm run check:ai`, `npm run check:claude`, and the `cargo test --workspace` and `cargo check` counts (or that the image was missing); the output of `bash scripts/test-link-contract.sh`, `bash scripts/test-link-flow.sh` and `node --test tests/cat/additive.test.mjs`; the pictures of each checkpoint; the Windows `cargo check` and a release build (owed to CI); the recorded-conversation tests' result; and anything you could not settle.

Before any follow-up turn (a fix round, a question, a resumed run), the main session checks the session is still on its configured model and effort.

## Setup (the controller, once)

- [ ] **Step 1: Put the session's worktree on the plan's branch and check the base**

```bash
git status                                    # must be clean
git switch -c g2/tauri-link notchmeow/rebrand
git merge-base --is-ancestor a589fcb8 HEAD && echo "G2-mac is merged (a589fcb8)"
git merge-base --is-ancestor d2b23670 HEAD && echo "G2-0b is merged (d2b23670)"
git log --oneline -3
git ls-files docs/LINK-CONTRACT.md tests/fixtures/link/reference.py tests/fixtures/link/flow-cases.json docs/superpowers/plans/2026-10-16-g2-tauri-link.md NotchBuddy/Sources/App/LinkService.swift windows/src/shelf/rules.ts windows/src-tauri/src/shelf.rs
git rev-parse --show-toplevel; git branch --show-current
cp -cR "$MAIN_CHECKOUT/windows/node_modules" windows/node_modules      # MAIN_CHECKOUT: the folder of the main checkout of this repository (the one that has node_modules)
git status --short                            # still empty: the copy is ignored
mkdir -p .claude/checkpoints/g2-tauri .superpowers/sdd/2026-10-16-g2-tauri-link
(cd windows && node --version)                # 22.6 or newer
```

Expected: both `... is merged` lines, the seven paths, and a clean `git status --short`. If a line is missing the base is not what the plan expects: stop and tell the owner. The `node_modules` copy is an APFS clone (instant); it must be a real folder, not a symlink, because `.gitignore` ignores `/windows/node_modules` as a folder. This plan adds no npm package, so nothing is downloaded.

- [ ] **Step 2: Check the contract and the starting point, and write the baseline into the ledger**

```bash
bash scripts/test-link-contract.sh 2>&1 | tail -3
bash scripts/test-link-flow.sh 2>&1 | tail -2
(cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?")
(cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)")
(cd windows && npm run check:sidekick 2>&1 | grep -E "^ℹ (tests|pass|fail)")
(cd windows && npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1)
node --test tests/cat/additive.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
docker image inspect notchmeow-linux-dev >/dev/null 2>&1 && echo "image ok" || echo "image missing or the daemon is down: the Rust steps are owed"
```

Expected: the contract passes (`5 fixtures parse with JSON.parse`), `All tests passed.` for the flow test, `tsc exit 0` with no error before it, `ℹ pass N` equal to `ℹ tests N` and `ℹ fail 0` for both node runs, `All AI UI checks passed`, `All Claude Code UI checks passed`, `# fail 0` for the additive test and `image ok`. **Write each count into the ledger as the baseline**: later tasks compare against it (the numbers move when other plans merge, so this plan quotes none). If `image ok` does not print, **do not build the image**: do the TypeScript tasks only and report that the Rust steps (Tasks 2 to 7 and 11 to 14) are owed. Their code is complete either way, and CI runs `cargo test` when the owner pushes.

- [ ] **Step 3: The find-text pre-flight (so that a base that moved is found now)**

```bash
cd windows
for pair in \
 'src-tauri/src/lib.rs|mod island;' \
 'src-tauri/src/lib.rs|            shelf_send,' \
 'src-tauri/src/lib.rs|            tray::build(&handle)?;' \
 'src-tauri/src/lib.rs|                    app.state::<ai::AiState>().forget_custom_key();' \
 'src-tauri/Cargo.toml|tokio = { version = "1", features = ["net", "io-util", "sync", "time", "rt", "macros"] }' \
 'src-tauri/Cargo.toml|zip = { version = "8", default-features = false, features = ["deflate-flate2-zlib-rs"] }' \
 'src/core/state.ts|import { ShelfStore } from "../shelf/store.ts";' \
 'src/core/state.ts|  shelfCaps = { dragOut: false, send: false };' \
 'src/core/layout.ts|  | "shelf";' \
 'src/core/layout.ts|  greeting: { height: 150, botX: 320, botY: 90, botDiameter: 0, agentMode: "none" },' \
 'src/views/views.ts|import { buildShelf, type ShelfActions } from "./shelf";' \
 'src/views/views.ts|  map.set("shelf", buildShelf(actions.shelf));' \
 'src/views/shelf.ts|import type { ViewHost } from "./views";' \
 'src/views/shelf.ts|  const tiles = h("div", { class: "sh-tiles" });' \
 'src/views/shelf.ts|    sync() {' \
 'src/shelf/icons.ts|  check: "M5 12.5 10 17.5 19 7",' \
 'src/island/island.ts|    blocked: () => State.attentionNeeded,' \
 'src/island/desktop.ts|this.trip.alert(desktopAlert({ approval: State.attentionNeeded, fileCatch: State.fileCatch() }));' \
 'src/cat/desktop.ts|o.fileCatch === true' \
 'src/cat/dev.ts|  mountShelfDev(root, wrap);' \
 'src/main.ts|  void State.shelf.refresh();' \
 'src/main.ts|import { bridgeBackend, mockBackend } from "./shelf/backend";' \
 'src/settings/main.ts|import { sidekickSection } from "./sidekick";' \
 'src/settings/main.ts|    sidekick.el,' \
 'package.json|    "check:sidekick":' ; do
  f="${pair%%|*}"; t="${pair#*|}"; printf '%s  %s\n' "$(grep -cF -- "$t" "$f")" "$f: ${t:0:60}"
done
cd ..
```

Expected: every line starts with `1`. A `0` (or a `2`) means the tree moved: stop and report which line. (The edit scripts assert exactly-once on their full find texts, which are longer than these probes.)

---

## How to run this plan

**Blocks.** A code step is one of three things: **Create `path`** (the file's exact content, in the fenced block under it; write it with your file tool, from the repository root, nothing added and nothing left out), a `bash` block holding a Python script whose `edit` helper replaces text that must occur exactly once in the file it names, or a plain command. Run each block from the repository root, as it is. Never type a block from memory and never "improve" one. A `Run:` block's `Expected:` line says what it prints (every backticked literal must appear). A `Run:` block that starts with `cd windows` ends in `cd ..` and came back.

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
TD="--target-dir /repo/windows/target/g2-tauri"
$CL test $TD -p notchmeow link::        # every link test (the first run compiles Tauri: minutes)
$CL test $TD -p notchmeow link::frames  # one module
$CL check $TD -p notchmeow --all-targets
```

The container is Linux: the Linux Rust is compiled and tested; the Windows-only Rust is read, not compiled.

**Page commands.** From `windows/`: `npx --no-install tsc --noEmit`, `npm run check:link` (this plan's tests), `npm run check:cat` and the others.

**Red first, and what stands in for it.** Each Rust file carries its own tests, so a task creates the file whole and runs it; the red evidence is the **"prove it bites"** step of each task: it changes one line of the code, runs the tests, sees them fail, and puts the line back with the helper below (never committed). A task that only edits an existing file runs its test before and after.

**The "prove it bites" helpers** (written once, here; they refuse a change whose find text does not occur exactly once, and put the file back whatever happens, with a fresh modification time so that cargo notices):

```bash
mkdir -p .claude/checkpoints/g2-tauri
cat > .claude/checkpoints/g2-tauri/mut.py <<'EOF'
import sys, subprocess, pathlib, os
# usage (Rust): python3 .claude/checkpoints/g2-tauri/mut.py rust <file> <find> <replace> <cargo test filter>
# usage (page): python3 .claude/checkpoints/g2-tauri/mut.py node <file> <find> <replace> <test files...>      (run from windows/)
kind, path, old, new, rest = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:]
p = pathlib.Path(path); s = p.read_text(encoding="utf-8")
assert s.count(old) == 1, (path, old[:60], s.count(old))
try:
    p.write_text(s.replace(old, new), encoding="utf-8")
    if kind == "node":
        out = subprocess.run(["node", "--experimental-strip-types", "--test"] + rest, capture_output=True, text=True).stdout
        line = [l for l in out.splitlines() if l.startswith("# pass") or l.startswith("# fail")]
    else:
        out = subprocess.run(["windows/scripts/cargo-linux.sh", "test", "--target-dir", "/repo/windows/target/g2-tauri", "-p", "notchmeow", rest[0]], capture_output=True, text=True)
        line = [l for l in (out.stdout + out.stderr).splitlines() if l.startswith("test result")]
    print(os.path.basename(path), "|", new[:48].replace("\n", " "), "|", " ".join(line))
finally:
    p.write_text(s, encoding="utf-8")        # a fresh modification time
EOF
echo "helper written"
```

**Pixels.** There are no pixel tests. The look is checked by eye in a headless browser (`playwright-cli`, with Vite alone, never the Tauri app). Keep every picture in `.claude/checkpoints/g2-tauri/` and say what you saw. **What no test program and no headless browser can show** is what the owner's real-machine checks (Task 16) are for: the Windows Firewall prompt, a real second machine, mDNS across a real network, the credential store, the Downloads folder, the mark of the web, the island opening for a card on a real desktop; never claim them.

**Starting and stopping the dev server** (Tasks 9 and 10 use it; port 14641, so that it never meets another worktree's):

```bash
mkdir -p .claude/checkpoints/g2-tauri
cd windows
(npx --no-install vite --port 14641 --strictPort > ../.claude/checkpoints/g2-tauri/vite.log 2>&1 & echo $! > ../.claude/checkpoints/g2-tauri/vite.pid)
sleep 3
cd ..
tail -3 .claude/checkpoints/g2-tauri/vite.log
```

Expected: `VITE v6` and `http://127.0.0.1:14641/`. If it says the port is in use, another session has it: pick another port in `14641` to `14699` and use it everywhere below. When a task is done with it: `kill "$(cat .claude/checkpoints/g2-tauri/vite.pid)"` (nothing else) and, for each session it opened, `playwright-cli -s=<name> close`.

---
## Tasks


### Task 1: The Mac's follow-ups of G2-0b

**Agent:** `nm-implementer-light` (Haiku 5.5, medium). The code is given in full.

G2-0b put three rules in the contract (`places[]`, `connections[]`, `firstFrame[]` of `flow-cases.json`) that the Mac's replay does not run yet, and the additive check does not look at `tests/fixtures/link/`. Both were noted at the G2-0b merge. They come first because they are small, because this plan's Rust replays the same three tables (Task 4), and because a second implementation is the best moment to make sure the first one is tested against them.

**Files:**
- Modify: `tests/LinkFlowTests.swift`, `scripts/test-link-flow.sh`, `scripts/check-fixtures-additive.mjs`, `tests/cat/additive.test.mjs`

**Interfaces:**
- Consumes: `LinkBusy` (`NotchBuddy/Sources/App/LinkCardRules.swift`), `LinkFlow.receiverStep` and the test helpers already in `LinkFlowTests.swift`.
- Produces: the Mac's replay of `places[]` (through the **real** `LinkBusy`), `connections[]` and `firstFrame[]`; `linkDirApplies(isAncestor)` in the additive check. Nothing under `NotchBuddy/` changes.

**What the replay can and cannot say.** `places[]` runs through the real `LinkBusy`, so it pins the Mac's code. The Mac keeps the one-decline-per-connection count and the first-frame watch inline in `LinkTransferReceive.run` (an actor with sockets), not as functions, so `connections[]` and `firstFrame[]` run through a **model written from the contract** in the test file; the run itself is pinned by `scripts/test-link-session.sh`. The model's first-frame number is tied to the real constant by a grep in `scripts/test-link-flow.sh`. This is a gap in the Mac's structure, reported in this plan's final report: it is not fixed here.

- [ ] **Step 1: The Swift replay**

Run (from the repository root):

```bash
python3 - <<'EOF'
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")

edit("tests/LinkFlowTests.swift", '''    struct Lcg { var s: UInt64;''', '''    /// The rules the app keeps around one connection (docs/LINK-CONTRACT.md, "One decline per connection" and "The first frame"), as the contract's `receiver_connection_step` states them. The Mac keeps these
    /// inline in `LinkTransferReceive.run` (its `declines` count, its first-frame watch) and not as a function, so this is a model of that code written from the contract; the run itself is pinned by
    /// scripts/test-link-session.sh. The first-frame number is pinned to the real constant by scripts/test-link-flow.sh.
    static let machineDeclines: Set<UInt8> = [LinkFlow.Decline.busy, LinkFlow.Decline.tooLarge, LinkFlow.Decline.badOffer]

    static func connectionStep(_ state: LinkFlow.ReceiverState, _ declines: Int, _ e: [String: Any]) -> (out: [String: Any], state: LinkFlow.ReceiverState, declines: Int) {
        func pack(_ st: LinkFlow.ReceiverState, _ d: Int, _ send: [W.Frame] = [], _ notify: String? = nil, _ abort: String? = nil) -> ([String: Any], LinkFlow.ReceiverState, Int) {
            (["state": json(st), "declines": d, "send": send.map(json), "notify": notify ?? NSNull(), "abort": abort ?? NSNull()], st, d)
        }
        if e["silent"] as? Bool == true {
            if case .idle = state { return pack(.idle, declines, [], nil, "idle") }
            return pack(state, declines)
        }
        let isOffer: Bool = { if let f = e["frame"] as? [String: Any], f["type"] as? String == "offer" { return true }; return false }()
        let ev = receiverEvent(e)
        let res: LinkFlow.Out<LinkFlow.ReceiverState>
        if isOffer, case .idle = state, e["granted"] as? Bool == false, case .frame(.offer(let id, _, _, _)) = ev {
            res = LinkFlow.Out(state: state, send: [.decline(id: id, reason: LinkFlow.Decline.busy)])
        } else {
            res = LinkFlow.receiverStep(state, ev)
        }
        var d = declines
        if isOffer, res.send.contains(where: { if case .decline(_, let r) = $0 { return machineDeclines.contains(r) }; return false }) {
            if d >= 1 { return pack(.idle, d, [], nil, "declines") }
            d += 1
        }
        return pack(res.state, d, res.send, res.notify?.rawValue, res.abort?.rawValue)
    }

    /// Expired at exactly `firstFrameMs` after the handshake; a clock that went back, or a value that is not whole milliseconds, counts as expired.
    static func firstFrameExpired(_ handshake: Any?, _ now: Any?, limit: Int) -> Bool {
        func whole(_ v: Any?) -> Int? { guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.intValue >= 0 else { return nil }; return n.intValue }
        guard let h = whole(handshake), let n = whole(now) else { return true }
        return !(0 <= n - h && n - h < limit)
    }

    struct Lcg { var s: UInt64;''')

edit("tests/LinkFlowTests.swift", '''        CT.section("3000 random event scripts''', '''        CT.section("the machine's one transfer place, through the real LinkBusy (docs/LINK-CONTRACT.md, \\"One transfer for the whole machine\\")")
        diffs = []
        let placeIds = ["01010101010101010101010101010101", "02020202020202020202020202020202"]
        let places = f["places"] as! [[String: Any]]
        for t in places {
            let busy = LinkBusy()
            let from = t["from"] as! [String: Any]
            if let h = from["holder"] as? String { _ = busy.claim(h) }
            busy.setCardLocked(from["card"] as! Bool)
            let outs = t["out"] as! [[String: Any]]
            for (i, e) in (t["events"] as! [[String: Any]]).enumerated() {
                var granted: Bool?
                if let c = e["claim"] as? String { granted = busy.claim(c) }
                else if let r = e["release"] as? String { busy.release(r) }
                else if let on = e["card"] as? Bool { busy.setCardLocked(on) }
                let want = outs[i], wantHolder = (want["place"] as! [String: Any])["holder"] as? String
                let holders = placeIds.filter { busy.holds($0) }
                if granted != want["granted"] as? Bool || holders != (wantHolder.map { [$0] } ?? []) { diffs.append("\\(t["name"] as! String) step \\(i)") }
            }
        }
        CT.check("all \\(places.count) place trips, step by step", diffs, [])

        CT.section("one decline per connection, and the first-frame clock")
        diffs = []
        let connections = f["connections"] as! [[String: Any]]
        for t in connections {
            let from = t["from"] as! [String: Any]
            var state = receiverState(from["state"] as! [String: Any]), declines = from["declines"] as! Int
            let outs = t["out"] as! [[String: Any]]
            for (i, e) in (t["events"] as! [[String: Any]]).enumerated() {
                let r = connectionStep(state, declines, e)
                state = r.state; declines = r.declines
                let d = CT.diffs(r.out, outs[i]); if !d.isEmpty { diffs.append("\\(t["name"] as! String) step \\(i): \\(d.prefix(2))") }
            }
        }
        CT.check("all \\(connections.count) connection trips, step by step", diffs, [])
        let limit = (f["firstFrameMs"] as! NSNumber).intValue
        CT.check("the first-frame limit is 10 s", limit, 10_000)
        diffs = []
        let firstFrame = f["firstFrame"] as! [[String: Any]]
        for c in firstFrame where firstFrameExpired(c["handshake"], c["now"], limit: limit) != (c["out"] as! Bool) { diffs.append(c["name"] as! String) }
        CT.check("all \\(firstFrame.count) first-frame rows, 9 999 ms open and 10 000 ms closed", diffs, [])

        CT.section("3000 random event scripts''')

edit("scripts/test-link-flow.sh", '''    $APP/LinkBytes.swift $APP/LinkName.swift $APP/LinkFrames.swift $APP/LinkFlow.swift \\
''', '''    $APP/LinkBytes.swift $APP/LinkName.swift $APP/LinkFrames.swift $APP/LinkFlow.swift $APP/LinkCardRules.swift \\
''')
edit("scripts/test-link-flow.sh", '''    -o "$TEST_DIR/link-flow-tests"
"$TEST_DIR/link-flow-tests"''', '''    -o "$TEST_DIR/link-flow-tests"
"$TEST_DIR/link-flow-tests"
# The contract's first-frame limit (flow-cases.json: firstFrameMs) is the real constant of the receiving run.
grep -q 'static let firstFrameMs = 10_000' $APP/LinkTransferRun.swift || { echo "✗ LinkTransferReceive.firstFrameMs is not 10_000 any more: docs/LINK-CONTRACT.md and flow-cases.json say 10 s"; exit 1; }
echo "✓ LinkTransferReceive.firstFrameMs is 10_000, as the contract says"''')
EOF
```


- [ ] **Step 2: Run it**

Run: `bash scripts/test-link-flow.sh 2>&1 | tail -16`
Expected: the earlier sections unchanged (`all 50 receiver rows and 16 sender rows`), then `all 7 place trips, step by step`, `all 13 connection trips, step by step`, `the first-frame limit is 10 s`, `all 8 first-frame rows, 9 999 ms open and 10 000 ms closed`, `no script breaks an invariant`, `All tests passed.` and `✓ LinkTransferReceive.firstFrameMs is 10_000, as the contract says`.

- [ ] **Step 3: Prove it bites** (never committed; the script puts the files back)

Run:

```bash
python3 - <<'EOF'
import pathlib, subprocess
def mutate(path, old, new):
    p = pathlib.Path(path); s = p.read_text(encoding="utf-8"); assert s.count(old) == 1, (path, old, s.count(old))
    try:
        p.write_text(s.replace(old, new), encoding="utf-8")
        out = subprocess.run(["bash", "scripts/test-link-flow.sh"], capture_output=True, text=True).stdout
        print(path.split("/")[-1], "|", new[:40], "|", [l.strip() for l in out.splitlines() if "✗" in l or "failed" in l][:2])
    finally:
        p.write_text(s, encoding="utf-8")
mutate("tests/LinkFlowTests.swift", 'if d >= 1 { return pack(.idle, d, [], nil, "declines") }', 'if d >= 2 { return pack(.idle, d, [], nil, "declines") }')
mutate("NotchBuddy/Sources/App/LinkCardRules.swift", "!cardLocked && peers.isEmpty && peers.insert(id).inserted", "!cardLocked && peers.insert(id).inserted")
EOF
git status --short
```

Expected: the first line lists `✗ all 13 connection trips, step by step`, the second `✗ all 7 place trips, step by step`, and `git status --short` shows only the two test-side files and the script of Step 1.

- [ ] **Step 4: The additive check covers the link**

Run:

```bash
python3 - <<'EOF'
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")

S = "scripts/check-fixtures-additive.mjs"
edit(S, "// Proves the cat and sidekick fixtures changed only by addition since a base ref (default HEAD).", "// Proves the cat, sidekick and link fixtures changed only by addition since a base ref (default HEAD).")
edit(S, "const DIRS = ['tests/fixtures/cat', 'tests/fixtures/sidekick'];", "const DIRS = ['tests/fixtures/cat', 'tests/fixtures/sidekick', 'tests/fixtures/link'];")
edit(S, "const noComma = line => line.replace(/,$/, '');", """// G2-0b merged the link contract's three connection rules at this commit, and in doing so reworded one frame case (the busy decline), so a base that predates it fails on that line and not on a
// real change. The link directory is skipped for such a base.
const G2_0B = 'd2b23670';
const noComma = line => line.replace(/,$/, '');

/** Whether the link fixtures are compared against a base: only when the base has G2-0b. `isAncestor(commit)` says whether `commit` is in the base's history. */
export function linkDirApplies(isAncestor) { return isAncestor(G2_0B); }""")
edit(S, """  for (const dir of DIRS) {
    let names;""", """  const hasG2_0b = () => { try { git('merge-base', '--is-ancestor', G2_0B, ref); return true; } catch { return false; } };
  for (const dir of DIRS) {
    if (dir.endsWith('/link') && !linkDirApplies(hasG2_0b)) { console.log(`  - ${dir}/ at ${ref} predates G2-0b (${G2_0B}); skipped`); continue; }
    let names;""")

T = "tests/cat/additive.test.mjs"
edit(T, "import { checkAdditive } from '../../scripts/check-fixtures-additive.mjs';", "import { checkAdditive, linkDirApplies } from '../../scripts/check-fixtures-additive.mjs';")
p = pathlib.Path(T)
p.write_text(p.read_text(encoding="utf-8") + """
test('a reworded case in a link fixture fails, as in the base from before G2-0b', () => {
  const was = '{\\n  "frames": [\\n    {"name": "a decline: busy: one transfer per peer", "n": 3},\\n    {"name": "a cancel", "n": 6}\\n  ]\\n}\\n';
  const now = was.replace('busy: one transfer per peer', 'busy: this machine already has a transfer running');
  assert.equal(checkAdditive(was, now).problems.length, 1);
  assert.deepEqual(checkAdditive(was, was.replace('"n": 6}', '"n": 6},\\n    {"name": "a new case", "n": 7}')).problems, []);
});

test('the link fixtures are compared only against a base that has G2-0b', () => {
  assert.equal(linkDirApplies(() => true), true);
  assert.equal(linkDirApplies(() => false), false);
  const asked = [];
  linkDirApplies((c) => { asked.push(c); return true; });
  assert.deepEqual(asked, ['d2b23670']);
});
""", encoding="utf-8")
EOF
```


- [ ] **Step 5: Run it**

Run:

```bash
node --test tests/cat/additive.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
node scripts/check-fixtures-additive.mjs 6adc5a4 2>&1 | tail -3
node scripts/check-fixtures-additive.mjs d2b23670 2>&1 | tail -4
node scripts/check-fixtures-additive.mjs 2>&1 | tail -2
```

Expected: `# tests 7`, `# pass 7`, `# fail 0`; for `6adc5a4` the line `- tests/fixtures/link/ at 6adc5a4 predates G2-0b (d2b23670); skipped` and `✓ fixtures changed only by addition since 6adc5a4`; for `d2b23670` `✓ tests/fixtures/link: changed only by addition since d2b23670`; for `HEAD` the same sentence for `HEAD`. (A base before G2-0b reworded one frame case; that is why it is skipped, and why a base after it is compared.)

- [ ] **Step 6: Prove the rule bites**

Run:

```bash
python3 - <<'EOF'
import pathlib, subprocess
p = pathlib.Path("scripts/check-fixtures-additive.mjs"); s = p.read_text(encoding="utf-8")
assert s.count("const G2_0B = 'd2b23670';") == 1
try:
    p.write_text(s.replace("const G2_0B = 'd2b23670';", "const G2_0B = 'x';"), encoding="utf-8")
    out = subprocess.run(["node", "--test", "tests/cat/additive.test.mjs"], capture_output=True, text=True).stdout
    print([l for l in out.splitlines() if l.startswith("# pass") or l.startswith("# fail")])
finally:
    p.write_text(s, encoding="utf-8")
EOF
```

Expected: `['# pass 6', '# fail 1']`, and the file is back as Step 4 left it.

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and g2/tauri-link
git add tests/LinkFlowTests.swift scripts/test-link-flow.sh scripts/check-fixtures-additive.mjs tests/cat/additive.test.mjs
git commit -F - <<'MSG'
test(link): the Mac replays places, connections and first-frame rows; the additive check covers the link (G2-0b follow-ups)

places[] runs through the real LinkBusy; connections[] and firstFrame[] through a model of LinkTransferReceive's inline rules, with a grep that ties the 10 s to the real constant. check-fixtures-additive.mjs gains tests/fixtures/link/ and skips a base from before G2-0b, which reworded one frame case.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Then write the task's line in the ledger: the commit, the test counts, the agent and the model.

---


### Task 2: Dependencies, the `link` module, hex, and the Noise layer on `snow`

**Agent:** `nm-implementer-deep` (Sonnet 5.5, high; **trigger 1**: a crypto crate's API that is not in the tree and that this plan could not compile; the replay of the contract's Noise vectors is the oracle). Also loads `superpowers:systematic-debugging`.

**Files:**
- Create: `windows/src-tauri/src/link/mod.rs`, `bytes.rs`, `noise.rs`, `testutil.rs`
- Modify: `windows/src-tauri/Cargo.toml`, `windows/Cargo.lock`, `windows/src-tauri/src/lib.rs`

**Interfaces:**
- Consumes: `tests/fixtures/link/noise-vectors.json` and `pairing-cases.json` (`session`); the `snow` 0.9 crate.
- Produces (every later task relies on these): `link::bytes::{hex, unhex, id16, key32, is_id_hex, is_key_hex, ID_LEN}`; `link::noise::{Handshake, Transport, Pattern, NoiseError, PROLOGUE, FIXED_EPHEMERAL (tests), public_of, generate_static, is_low_order}` with `Handshake::new(pattern, initiator, &private, remote_static: Option<&[u8;32]>, prologue, ephemeral: Option<&[u8;32]>) -> Result<Handshake, NoiseError>`, `write(&mut self, payload) -> Result<Vec<u8>>`, `read(&mut self, message) -> Result<Vec<u8>>`, `remote_static()`, `handshake_hash()`, `finish(self) -> Result<Transport>`, and `Transport::{encrypt, decrypt}`; `link::testutil::{fixture, arr, name}` (tests only).

**What the wrapper adds to `snow`, and why.** The contract demands that a DH output of all zeros aborts; `snow` may refuse it or not, and the contract's two `low-order` cases say *where* the conversation must stop (message 1 for XX, message 0 for KK) and *why* ("low-order point"). The wrapper refuses a low-order ephemeral key itself, at the message where its DH happens (for the XX responder's first message that is the next `write`), and refuses a low-order static key at `finish`. `public_of` derives a public key from a stored private one through `snow`'s own resolver (no second curve library). `FIXED_EPHEMERAL` (test builds only) pins the ephemeral key of the next handshakes on a thread, for the recorded conversations of Task 11.

- [ ] **Step 1: The owner's yes (the controller does this, in chat, before anything below)**

Step 3 downloads crates from crates.io through the container: `snow` and `mdns-sd` and what they need (RustCrypto crates, `flume`, `if-addrs`, `socket2` and so on). The owner approved the two crates on 2026-10-14; this is the one download of the plan. Ask: "Task 2 downloads `snow` and `mdns-sd` and their dependencies through Docker. May I?" and wait for a yes. No yes: stop here and report that the Rust tasks 2 to 7 and 11 to 14 are owed.

- [ ] **Step 2: Cargo.toml and lib.rs**

Run:

```bash
python3 - <<'EOF'
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")

edit("windows/src-tauri/Cargo.toml", 'tokio = { version = "1", features = ["net", "io-util", "sync", "time", "rt", "macros"] }', 'tokio = { version = "1", features = ["net", "io-util", "sync", "time", "rt", "rt-multi-thread", "macros"] }')
edit("windows/src-tauri/Cargo.toml", 'zip = { version = "8", default-features = false, features = ["deflate-flate2-zlib-rs"] }\n', '''zip = { version = "8", default-features = false, features = ["deflate-flate2-zlib-rs"] }
# The link between the user's machines (sub-project G2). `snow` (Noise, MIT/Apache-2.0) and `mdns-sd` (mDNS, MIT/Apache-2.0) are new and were approved by the owner on 2026-10-14. The next three are
# already in Cargo.lock through other crates; naming them here adds no code to the build: `sha2` (the pairing commitment and code), `unicode-normalization` (NFC and NFKC in the file-name
# rule: the standard library has neither) and `getrandom` (nonces, device ids and transfer ids).
snow = "0.9"
mdns-sd = "0.11"
sha2 = "0.10"
unicode-normalization = "0.1"
getrandom = "0.2"
''')
edit("windows/src-tauri/src/lib.rs", "mod island;\nmod log;", "mod island;\npub mod link;\nmod log;")
EOF
```

- [ ] **Step 3: Fetch the crates (the one download) and see what the lock gained**

Run:

```bash
windows/scripts/cargo-linux.sh fetch
git diff --stat windows/Cargo.lock
git diff -U0 windows/Cargo.lock | grep -E '^-[^-]' | head
git diff -U0 windows/Cargo.lock | grep -E '^\+name = ' | sort | head -60
```

Expected: `windows/Cargo.lock` changed; **the third command prints nothing** (only additions: no existing crate changed version); the fourth lists `snow` and `mdns-sd` among the new packages. If the third command prints a line, a crate the app already uses was upgraded: stop and report it (then `git checkout windows/Cargo.lock` and run `cargo update -p <crate> --precise <the old version>` for each).

- [ ] **Step 4: Read the crates' API before writing against it**

`noise.rs` below is written from `snow` 0.9's documented API and could not be compiled while this plan was written. Look at what the downloaded source says:

```bash
docker run --rm -v notchmeow-linux-cargo:/usr/local/cargo/registry notchmeow-linux-dev bash -c '
cd /usr/local/cargo/registry/src/*/snow-0.9*/ && pwd &&
grep -n "pub fn fixed_ephemeral_key_for_testing_only\|pub fn local_private_key\|pub fn remote_public_key\|pub fn prologue\|pub fn build_initiator\|pub fn build_responder\|pub fn generate_keypair\|pub fn get_remote_static\|pub fn get_handshake_hash\|pub fn into_transport_mode\|pub fn is_handshake_finished\|pub fn write_message\|pub fn read_message" src/builder.rs src/handshakestate.rs src/transportstate.rs &&
grep -n "pub trait Dh" -A14 src/types.rs &&
grep -n "pub trait CryptoResolver" -A6 src/resolvers/mod.rs &&
grep -n "pub enum DHChoice" -A4 src/params/mod.rs src/params/*.rs'
```

Expected: each of those functions and traits is there. What to do if one is not: use the nearest name the source shows (for example the builder's methods may take `&'builder [u8]` and return `Self`; `fixed_ephemeral_key_for_testing_only` may sit behind a feature, which `Cargo.toml` then names); keep the wrapper's public API as it is in "Interfaces"; write what you changed in the ledger. **The tests of this task decide, not the text:** `every_vector_replays_byte_for_byte` and `every_damaged_conversation_stops_where_the_contract_says` must pass unchanged.

- [ ] **Step 5: The files**

Create `windows/src-tauri/src/link/mod.rs`:

```rust
// The link (sub-project G2): file transfer between the user's own machines. No Tauri type appears anywhere under this folder, so a test binary can run it (docs/LINK-CONTRACT.md).
// The pure rules are ports of tests/fixtures/link/reference.py and are replayed against tests/fixtures/link/; everything that touches a socket, the credential store or the disk is
// added by the tasks that need it. Each task adds its module on the marker line.

pub mod bytes;
pub mod noise;
// MODULES: add new modules above this line

#[cfg(test)]
pub(crate) mod testutil;
```

**Create `windows/src-tauri/src/link/testutil.rs`:**

```rust
// What the link's tests share: reading a fixture of tests/fixtures/link/ and a few JSON helpers.

use std::path::Path;

use serde_json::Value;

pub fn fixture(name: &str) -> Value {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/link").join(name);
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    serde_json::from_str(&text).unwrap_or_else(|e| panic!("parse {}: {e}", path.display()))
}

pub fn arr<'a>(v: &'a Value, key: &str) -> &'a Vec<Value> {
    v[key].as_array().unwrap_or_else(|| panic!("{key} is not a list"))
}

pub fn name(case: &Value) -> &str {
    case["name"].as_str().unwrap_or("?")
}
```


**Create `windows/src-tauri/src/link/bytes.rs`:**

```rust
// Hex and fixed-size byte helpers for the link. Hex is lower-case everywhere on the wire and in the stores (docs/LINK-CONTRACT.md, "Notes for ports"): upper case is not hex here.

pub const ID_LEN: usize = 16;

pub fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        out.push(DIGITS[(b >> 4) as usize] as char);
        out.push(DIGITS[(b & 15) as usize] as char);
    }
    out
}

fn nibble(c: u8) -> Option<u8> {
    match c {
        b'0'..=b'9' => Some(c - b'0'),
        b'a'..=b'f' => Some(c - b'a' + 10),
        _ => None,
    }
}

/// The bytes of lower-case hex, or None for odd length, a capital or any other character.
pub fn unhex(s: &str) -> Option<Vec<u8>> {
    let b = s.as_bytes();
    if b.len() % 2 != 0 {
        return None;
    }
    b.chunks(2).map(|p| Some(nibble(p[0])? << 4 | nibble(p[1])?)).collect()
}

/// A device id or transfer id: 16 bytes, 32 lower-case hex digits.
pub fn id16(s: &str) -> Option<[u8; ID_LEN]> {
    unhex(s)?.try_into().ok()
}

/// A nonce, a commitment or a public key: 32 bytes, 64 lower-case hex digits.
pub fn key32(s: &str) -> Option<[u8; 32]> {
    unhex(s)?.try_into().ok()
}

pub fn is_id_hex(s: &str) -> bool {
    id16(s).is_some()
}

pub fn is_key_hex(s: &str) -> bool {
    key32(s).is_some()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hex_round_trips_and_is_lower_case_only() {
        assert_eq!(hex(&[0, 1, 0xab, 0xff]), "0001abff");
        assert_eq!(unhex("0001abff"), Some(vec![0, 1, 0xab, 0xff]));
        assert_eq!(unhex("0001ABFF"), None, "capitals are not hex here");
        assert_eq!(unhex("abc"), None);
        assert_eq!(unhex("zz"), None);
        assert_eq!(unhex(""), Some(vec![]));
    }

    #[test]
    fn ids_and_keys_have_their_lengths() {
        assert!(is_id_hex(&"ab".repeat(16)));
        assert!(!is_id_hex(&"ab".repeat(15)));
        assert!(!is_id_hex(&"AB".repeat(16)));
        assert!(is_key_hex(&"cd".repeat(32)));
        assert!(!is_key_hex(&"cd".repeat(31)));
    }
}
```


**Create `windows/src-tauri/src/link/noise.rs`:**

```rust
// The link's Noise layer (docs/LINK-CONTRACT.md, "On the wire" and "Notes for ports"): `Noise_XX_25519_ChaChaPoly_SHA256` pairs two machines and `Noise_KK_25519_ChaChaPoly_SHA256`
// carries a transfer, both with the prologue `notchmeow-link/1`. The cryptography is the `snow` crate's (vetted, the owner approved it on 2026-10-14); this file is the thin wrapper that
// gives the rest of the link four things the contract asks for and `snow` does not promise:
//   * a Diffie-Hellman result of 32 zero bytes (a low-order point) is refused, in our own words ("low-order point"), at the message where the contract says it must stop;
//   * the KK handshake payloads are empty, and a non-empty one is refused (docs/LINK-CONTRACT.md, "Transfer") by the callers;
//   * a transport message that does not open does not move the counter (the wrapper never decrypts into the live state before the tag has passed: snow's own rule, pinned by a test);
//   * the secrets are plain byte arrays that the caller wipes (`Zeroizing` is not used: the keys live in the credential store and in this process only while a conversation runs).
// It is replayed against tests/fixtures/link/noise-vectors.json (all four vectors, byte for byte, and the twenty damaged-message cases).

use snow::resolvers::{CryptoResolver, DefaultResolver};
use snow::params::DHChoice;
use snow::types::Dh;
use snow::{Builder, HandshakeState, TransportState};

pub const PROLOGUE: &[u8] = b"notchmeow-link/1";
const XX: &str = "Noise_XX_25519_ChaChaPoly_SHA256";
const KK: &str = "Noise_KK_25519_ChaChaPoly_SHA256";
/// A Noise message is at most 65535 bytes (docs/LINK-CONTRACT.md).
const MAX: usize = 65535;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoiseError(pub String);

impl NoiseError {
    fn new(s: impl Into<String>) -> NoiseError {
        NoiseError(s.into())
    }
    pub fn low_order() -> NoiseError {
        NoiseError::new("low-order point")
    }
}

impl std::fmt::Display for NoiseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for NoiseError {}

impl From<snow::Error> for NoiseError {
    fn from(e: snow::Error) -> NoiseError {
        NoiseError(format!("noise: {e}"))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Pattern {
    Xx,
    Kk,
}

/// The points of order dividing 8 on Curve25519, as 32-byte little-endian encodings with the unused top bit cleared. A DH with any of them gives all zeros.
const LOW_ORDER: [[u8; 32]; 7] = [
    [0; 32],
    {
        let mut a = [0u8; 32];
        a[0] = 1;
        a
    },
    [0xe0, 0xeb, 0x7a, 0x7c, 0x3b, 0x41, 0xb8, 0xae, 0x16, 0x56, 0xe3, 0xfa, 0xf1, 0x9f, 0xc4, 0x6a, 0xda, 0x09, 0x8d, 0xeb, 0x9c, 0x32, 0xb1, 0xfd, 0x86, 0x62, 0x05, 0x16, 0x5f, 0x49, 0xb8, 0x00],
    [0x5f, 0x9c, 0x95, 0xbc, 0xa3, 0x50, 0x8c, 0x24, 0xb1, 0xd0, 0xb1, 0x55, 0x9c, 0x83, 0xef, 0x5b, 0x04, 0x44, 0x5c, 0xc4, 0x58, 0x1c, 0x8e, 0x86, 0xd8, 0x22, 0x4e, 0xdd, 0xd0, 0x9f, 0x11, 0x57],
    {
        let mut a = [0xffu8; 32];
        a[0] = 0xec;
        a[31] = 0x7f;
        a
    },
    {
        let mut a = [0xffu8; 32];
        a[0] = 0xed;
        a[31] = 0x7f;
        a
    },
    {
        let mut a = [0xffu8; 32];
        a[0] = 0xee;
        a[31] = 0x7f;
        a
    },
];

pub fn is_low_order(public: &[u8]) -> bool {
    let Ok(mut k) = <[u8; 32]>::try_from(public) else { return false };
    k[31] &= 0x7f;
    LOW_ORDER.contains(&k)
}

/// The public key of a static private key.
pub fn public_of(private: &[u8; 32]) -> Result<[u8; 32], NoiseError> {
    let mut dh = DefaultResolver.resolve_dh(&DHChoice::Curve25519).ok_or_else(|| NoiseError::new("no curve25519"))?;
    dh.set(private);
    dh.pubkey().try_into().map_err(|_| NoiseError::new("key length"))
}

/// A fresh static key pair (private, public).
pub fn generate_static() -> Result<([u8; 32], [u8; 32]), NoiseError> {
    let pair = Builder::new(XX.parse().map_err(|_| NoiseError::new("params"))?).generate_keypair()?;
    let private: [u8; 32] = pair.private.try_into().map_err(|_| NoiseError::new("key length"))?;
    let public: [u8; 32] = pair.public.try_into().map_err(|_| NoiseError::new("key length"))?;
    Ok((private, public))
}

#[cfg(test)]
thread_local! {
    /// The ephemeral key that the handshakes made next on this thread start with, for the recorded-conversation checks. Test builds only.
    pub(crate) static FIXED_EPHEMERAL: std::cell::Cell<Option<[u8; 32]>> = const { std::cell::Cell::new(None) };
}

pub struct Handshake {
    state: HandshakeState,
    pattern: Pattern,
    initiator: bool,
    /// How many handshake messages have gone by (written or read).
    index: usize,
    /// A zero-point ephemeral key that arrived where no DH uses it yet (the XX responder's first message): the refusal comes at the next `write`, where the contract's tables put it.
    deferred: Option<NoiseError>,
}

impl Handshake {
    /// `remote_static` is the other side's public key for KK (both sides know it before the first message) and None for XX. `ephemeral` pins the ephemeral key: the fixtures use it, nothing
    /// else may (a pinned key reused is a broken handshake).
    pub fn new(pattern: Pattern, initiator: bool, private: &[u8; 32], remote_static: Option<&[u8; 32]>, prologue: &[u8], ephemeral: Option<&[u8; 32]>) -> Result<Handshake, NoiseError> {
        let params = match pattern {
            Pattern::Xx => XX,
            Pattern::Kk => KK,
        }
        .parse()
        .map_err(|_| NoiseError::new("params"))?;
        // The fixtures pin the ephemeral key; in a test build the recorded-conversation checks (conformance.rs) pin it through `FIXED_EPHEMERAL`. In a release build nothing but the argument can.
        #[cfg(test)]
        let ephemeral = ephemeral.copied().or_else(|| FIXED_EPHEMERAL.with(|c| c.get()));
        #[cfg(not(test))]
        let ephemeral = ephemeral.copied();
        let mut b = Builder::new(params).local_private_key(private).prologue(prologue);
        if let Some(rs) = remote_static {
            if is_low_order(rs) {
                return Err(NoiseError::low_order());
            }
            b = b.remote_public_key(rs);
        }
        if let Some(e) = ephemeral.as_ref() {
            b = b.fixed_ephemeral_key_for_testing_only(e);
        }
        let state = if initiator { b.build_initiator()? } else { b.build_responder()? };
        Ok(Handshake { state, pattern, initiator, index: 0, deferred: None })
    }

    /// The next handshake message to send, carrying `payload`.
    pub fn write(&mut self, payload: &[u8]) -> Result<Vec<u8>, NoiseError> {
        if let Some(e) = self.deferred.take() {
            return Err(e);
        }
        let mut out = vec![0u8; MAX];
        let n = self.state.write_message(payload, &mut out)?;
        out.truncate(n);
        self.index += 1;
        Ok(out)
    }

    /// Opens the next handshake message and returns its payload. The ephemeral key at its front (every XX and KK message that starts with one: the first two) is refused when it is a
    /// low-order point: at once where the message's own DH uses it, at the next `write` where the first DH that uses it is in the reply (XX, responder, first message).
    pub fn read(&mut self, message: &[u8]) -> Result<Vec<u8>, NoiseError> {
        if self.index < 2 && message.len() >= 32 && is_low_order(&message[..32]) {
            let err = NoiseError::low_order();
            if self.pattern == Pattern::Xx && !self.initiator && self.index == 0 {
                self.deferred = Some(err);
            } else {
                return Err(err);
            }
        }
        let mut out = vec![0u8; MAX];
        let n = self.state.read_message(message, &mut out)?;
        out.truncate(n);
        self.index += 1;
        Ok(out)
    }

    pub fn is_finished(&self) -> bool {
        self.state.is_handshake_finished()
    }

    /// The other side's static public key, once the handshake has carried it (XX: after the second message for the initiator, the third for the responder; KK: known from the start).
    pub fn remote_static(&self) -> Option<[u8; 32]> {
        self.state.get_remote_static().and_then(|k| k.try_into().ok())
    }

    pub fn handshake_hash(&self) -> Vec<u8> {
        self.state.get_handshake_hash().to_vec()
    }

    /// The handshake is over: the transport state, and the other side's static key (refused when it is a low-order point).
    pub fn finish(self) -> Result<Transport, NoiseError> {
        if let Some(rs) = self.remote_static() {
            if is_low_order(&rs) {
                return Err(NoiseError::low_order());
            }
        }
        Ok(Transport { state: self.state.into_transport_mode()? })
    }
}

/// The two cipher states of an established session in one value: `encrypt` uses the sending counter and `decrypt` the receiving one, as the nonce is the message count of each direction.
pub struct Transport {
    state: TransportState,
}

impl Transport {
    pub fn encrypt(&mut self, plaintext: &[u8]) -> Result<Vec<u8>, NoiseError> {
        let mut out = vec![0u8; plaintext.len() + 16];
        let n = self.state.write_message(plaintext, &mut out)?;
        out.truncate(n);
        Ok(out)
    }

    pub fn decrypt(&mut self, ciphertext: &[u8]) -> Result<Vec<u8>, NoiseError> {
        if ciphertext.len() < 16 {
            return Err(NoiseError::new("message too short"));
        }
        let mut out = vec![0u8; ciphertext.len()];
        let n = self.state.read_message(ciphertext, &mut out)?;
        out.truncate(n);
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link::bytes::{hex, key32, unhex};
    use crate::link::testutil::{arr, fixture, name};
    use serde_json::Value;

    enum Run {
        Ok { ciphertexts: Vec<String>, hash: String },
        Fail { at: usize, because: String },
    }

    fn h32(v: &Value, key: &str) -> [u8; 32] {
        key32(v[key].as_str().unwrap()).unwrap()
    }

    /// `noise_run` of reference.py: plays a vector's whole conversation, both sides, in this process. A mutation damages what is delivered, never what is sent.
    fn noise_run(v: &Value, mutation: Option<&Value>) -> Run {
        let kind = mutation.and_then(|m| m["kind"].as_str());
        let pattern = if v["protocol_name"].as_str().unwrap().contains("_KK_") { Pattern::Kk } else { Pattern::Xx };
        let (isk, rsk) = (h32(v, "init_static"), h32(v, "resp_static"));
        let (ipub, rpub) = (public_of(&isk).unwrap(), public_of(&rsk).unwrap());
        let kk = pattern == Pattern::Kk;
        let init_prologue = if kind == Some("prologue") { unhex(mutation.unwrap()["prologue"].as_str().unwrap()).unwrap() } else { unhex(v["init_prologue"].as_str().unwrap()).unwrap() };
        let resp_prologue = unhex(v["resp_prologue"].as_str().unwrap()).unwrap();
        let resp_knows = if kind == Some("static") { h32(mutation.unwrap(), "respRemoteStatic") } else { ipub };
        let mut i_hs = Some(Handshake::new(pattern, true, &isk, kk.then_some(&rpub), &init_prologue, Some(&h32(v, "init_ephemeral"))).unwrap());
        let mut r_hs = Some(Handshake::new(pattern, false, &rsk, kk.then_some(&resp_knows), &resp_prologue, Some(&h32(v, "resp_ephemeral"))).unwrap());
        let nhs = if kk { 2 } else { 3 };
        let (mut sent, mut hash) = (Vec::new(), String::new());
        let (mut ti, mut tr): (Option<Transport>, Option<Transport>) = (None, None);
        for (n, msg) in arr(v, "messages").iter().enumerate() {
            let payload = unhex(msg["payload"].as_str().unwrap()).unwrap();
            let to_resp = n % 2 == 0;
            let c = if n < nhs {
                let hs = if to_resp { i_hs.as_mut().unwrap() } else { r_hs.as_mut().unwrap() };
                hs.write(&payload)
            } else {
                let t = if to_resp { ti.as_mut().unwrap() } else { tr.as_mut().unwrap() };
                t.encrypt(&payload)
            };
            let c = match c {
                Ok(c) => c,
                Err(e) => return Run::Fail { at: n, because: e.0 },
            };
            sent.push(hex(&c));
            let mut delivered = vec![c.clone()];
            if mutation.is_some_and(|m| m["message"].as_u64() == Some(n as u64)) {
                let m = mutation.unwrap();
                match kind {
                    Some("flip") => {
                        let o = m["offset"].as_u64().unwrap() as usize;
                        delivered[0][o] ^= 1;
                    }
                    Some("truncate") => {
                        let by = m["by"].as_u64().unwrap() as usize;
                        delivered[0].truncate(c.len() - by);
                    }
                    Some("low-order") => delivered[0][..32].copy_from_slice(&[0u8; 32]),
                    Some("replay") => delivered.push(c.clone()),
                    _ => {}
                }
            }
            if kind == Some("skip") && mutation.unwrap()["message"].as_u64().unwrap() as i64 - 2 == n as i64 {
                delivered.clear(); // sent, never arrived
            }
            for d in delivered {
                let got = if n < nhs {
                    let hs = if to_resp { r_hs.as_mut().unwrap() } else { i_hs.as_mut().unwrap() };
                    hs.read(&d)
                } else {
                    let t = if to_resp { tr.as_mut().unwrap() } else { ti.as_mut().unwrap() };
                    t.decrypt(&d)
                };
                match got {
                    Err(e) => return Run::Fail { at: n, because: e.0 },
                    // A damaged message may legitimately open to another payload (message 0 is not encrypted).
                    Ok(p) if d == c && p != payload => return Run::Fail { at: n, because: "payload".into() },
                    Ok(_) => {}
                }
            }
            if n == nhs - 1 {
                let (hi, hr) = (i_hs.as_ref().unwrap().handshake_hash(), r_hs.as_ref().unwrap().handshake_hash());
                if hi != hr {
                    return Run::Fail { at: n, because: "hash".into() };
                }
                hash = hex(&hi);
                ti = Some(match i_hs.take().unwrap().finish() {
                    Ok(t) => t,
                    Err(e) => return Run::Fail { at: n, because: e.0 },
                });
                tr = Some(match r_hs.take().unwrap().finish() {
                    Ok(t) => t,
                    Err(e) => return Run::Fail { at: n, because: e.0 },
                });
            }
        }
        Run::Ok { ciphertexts: sent, hash }
    }

    #[test]
    fn the_prologue_is_the_contracts() {
        assert_eq!(hex(PROLOGUE), fixture("noise-vectors.json")["prologue"].as_str().unwrap());
    }

    #[test]
    fn every_vector_replays_byte_for_byte() {
        let f = fixture("noise-vectors.json");
        let vectors = arr(&f, "vectors");
        assert_eq!(vectors.len(), 4);
        for v in vectors {
            match noise_run(v, None) {
                Run::Ok { ciphertexts, hash } => {
                    let want: Vec<&str> = arr(v, "messages").iter().map(|m| m["ciphertext"].as_str().unwrap()).collect();
                    assert_eq!(ciphertexts, want, "{}: every ciphertext", name(v));
                    assert_eq!(hash, v["handshake_hash"].as_str().unwrap(), "{}: the handshake hash", name(v));
                }
                Run::Fail { at, because } => panic!("{}: failed at message {at}: {because}", name(v)),
            }
        }
    }

    #[test]
    fn every_damaged_conversation_stops_where_the_contract_says() {
        let f = fixture("noise-vectors.json");
        let cases = arr(&f, "rejectCases");
        assert_eq!(cases.len(), 20);
        for c in cases {
            let v = arr(&f, "vectors").iter().find(|v| v["id"] == c["vector"]).unwrap();
            match noise_run(v, Some(c)) {
                Run::Ok { .. } => panic!("{}: nothing failed", name(c)),
                Run::Fail { at, because } => {
                    assert_eq!(at as u64, c["failsAt"].as_u64().unwrap(), "{}: failed at {at} ({because})", name(c));
                    if let Some(why) = c["because"].as_str() {
                        assert_eq!(because, why, "{}: the zero point is refused as such", name(c));
                    }
                }
            }
        }
    }

    #[test]
    fn public_keys_come_from_private_ones() {
        let f = fixture("pairing-cases.json");
        let s = &f["session"];
        let v = arr(&fixture("noise-vectors.json"), "vectors").iter().find(|v| v["id"] == s["vector"]).unwrap().clone();
        assert_eq!(hex(&public_of(&h32(&v, "init_static")).unwrap()), s["staticI"].as_str().unwrap());
        assert_eq!(hex(&public_of(&h32(&v, "resp_static")).unwrap()), s["staticR"].as_str().unwrap());
        let (private, public) = generate_static().unwrap();
        assert_eq!(public_of(&private).unwrap(), public);
    }

    #[test]
    fn the_low_order_points_are_refused_with_or_without_the_top_bit() {
        for p in LOW_ORDER {
            assert!(is_low_order(&p));
            let mut hi = p;
            hi[31] |= 0x80;
            assert!(is_low_order(&hi), "the top bit is ignored by X25519");
        }
        let (_, public) = generate_static().unwrap();
        assert!(!is_low_order(&public) && !is_low_order(&[]) && !is_low_order(&[7u8; 31]));
    }

    #[test]
    fn a_message_that_does_not_open_does_not_move_the_counter() {
        // A real XX pairing with random ephemerals, then a transport message with a flipped bit, then the genuine one: the genuine one still opens.
        let (a, _) = generate_static().unwrap();
        let (b, _) = generate_static().unwrap();
        let mut i = Handshake::new(Pattern::Xx, true, &a, None, PROLOGUE, None).unwrap();
        let mut r = Handshake::new(Pattern::Xx, false, &b, None, PROLOGUE, None).unwrap();
        let m0 = i.write(&[]).unwrap();
        r.read(&m0).unwrap();
        let m1 = r.write(&[]).unwrap();
        i.read(&m1).unwrap();
        let m2 = i.write(&[]).unwrap();
        r.read(&m2).unwrap();
        let (mut ti, mut tr) = (i.finish().unwrap(), r.finish().unwrap());
        let sealed = ti.encrypt(b"hello").unwrap();
        let mut damaged = sealed.clone();
        damaged[0] ^= 1;
        assert!(tr.decrypt(&damaged).is_err());
        assert_eq!(tr.decrypt(&sealed).unwrap(), b"hello", "the failed open left the counter where it was");
        assert!(tr.decrypt(&sealed).is_err(), "and a replay does not open");
    }

    #[test]
    fn another_prologue_cannot_complete_a_handshake() {
        let (a, _) = generate_static().unwrap();
        let (b, _) = generate_static().unwrap();
        let mut i = Handshake::new(Pattern::Xx, true, &a, None, b"notchmeow-link/2", None).unwrap();
        let mut r = Handshake::new(Pattern::Xx, false, &b, None, PROLOGUE, None).unwrap();
        let m0 = i.write(&[]).unwrap();
        r.read(&m0).unwrap();
        let m1 = r.write(&[]).unwrap();
        assert!(i.read(&m1).is_err());
    }
}
```


- [ ] **Step 6: Run the tests**

Run: `windows/scripts/cargo-linux.sh test --target-dir /repo/windows/target/g2-tauri -p notchmeow link::`
Expected: `test result: ok. 9 passed` (2 in `bytes`, 7 in `noise`: `the_prologue_is_the_contracts`, `every_vector_replays_byte_for_byte`, `every_damaged_conversation_stops_where_the_contract_says`, `public_keys_come_from_private_ones`, `the_low_order_points_are_refused_with_or_without_the_top_bit`, `a_message_that_does_not_open_does_not_move_the_counter`, `another_prologue_cannot_complete_a_handshake`). Fix the wrapper until they do, nothing else.

If `a_message_that_does_not_open_does_not_move_the_counter` fails, `snow` advanced its counter on a failed open. The conversation layer closes the connection on any failed message anyway, so no later task depends on it; but the contract says so, so make the wrapper carry its own counter check or report it to the controller: do not delete the test.

- [ ] **Step 7: Prove it bites**

Run:

```bash
python3 .claude/checkpoints/g2-tauri/mut.py rust windows/src-tauri/src/link/noise.rs 'if self.index < 2 && message.len() >= 32 && is_low_order(&message[..32]) {' 'if false && message.len() >= 32 && is_low_order(&message[..32]) {' link::noise
python3 .claude/checkpoints/g2-tauri/mut.py rust windows/src-tauri/src/link/noise.rs 'pub const PROLOGUE: &[u8] = b"notchmeow-link/1";' 'pub const PROLOGUE: &[u8] = b"notchmeow-link/2";' link::noise
```

Expected: the first ends `test result: FAILED. 6 passed; 1 failed` (the damaged-conversation test: the two zero-point cases), the second `FAILED` with at least `the_prologue_is_the_contracts` and `every_vector_replays_byte_for_byte` failing.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and g2/tauri-link
git add windows/src-tauri/Cargo.toml windows/Cargo.lock windows/src-tauri/src/lib.rs windows/src-tauri/src/link
git commit -F - <<'MSG'
feat(link): the link module, hex helpers and the Noise layer on snow, replayed against the contract's vectors (G2-tauri)

snow 0.9 and mdns-sd 0.11 (approved 2026-10-14) join the dependencies; sha2, unicode-normalization and getrandom are named directly and were in the lock already. noise.rs wraps snow: the two patterns with the link prologue, a low-order point refused as such at the message the contract names, public_of and generate_static, and a test-only pin of the ephemeral key. All four vectors replay byte for byte and the twenty damaged-message cases stop where the contract says.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Then write the task's line in the ledger: the commit, the test counts, the agent, the model and the trigger.

---


### Task 3: The file-name rule and the wire shapes

**Agent:** `nm-implementer-light` (Haiku 5.5, medium). The code is given in full.

**Files:**
- Create: `windows/src-tauri/src/link/name.rs`, `windows/src-tauri/src/link/frames.rs`
- Modify: `windows/src-tauri/src/link/mod.rs`

**Interfaces:**
- Consumes: `link::bytes`; `tests/fixtures/link/filename-cases.json` and `frames.json` (and `flow-cases.json`'s `chunkPlans`).
- Produces: `name::{sanitize_name(&str) -> Result<String, Reject>, unique_name(&str, &[String]) -> Option<String>, Reject, is_bad_category, is_invisible, is_space, NAME_BYTES_MAX}`; `frames::{Frame, FrameError, Mode, Preamble, Hello, Advert, Txt, OwnId, encode_record, split_records, encode_preamble, decode_preamble, encode_hello, decode_hello, device_name, parse_txt, encode_frame, decode_frame, plan_chunks, CHUNK_MAX, CHUNK_SIZE, SIZE_MAX, DEVICE_NAME_MAX, RAW_NAME_MAX, DECLINE_*}` and, in tests, `frames::tests::{frame_of, json_of}` (Task 4 reuses them).

**Notes on the port.** The reference's two Unicode tables (the invisible set and the whitespace set) are written out by hand, as the contract says: they are copied, not taken from a Unicode table, so the set does not move with a toolchain. NFC and NFKC come from the `unicode-normalization` crate (the standard library has neither). `unique_name` compares with `to_lowercase` where the reference uses Python's `casefold`: the two differ for the sharp s only, no fixture row has one, and the contract lists the fold as a known limit (the volume decides which names are the same file, and the file is created exclusively whatever this says).

- [ ] **Step 1: Register the modules**

Run:

```bash
python3 - <<'EOF'
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")
edit("windows/src-tauri/src/link/mod.rs", "// MODULES: add new modules above this line", "pub mod frames;\npub mod name;\n// MODULES: add new modules above this line")
EOF
```

- [ ] **Step 2: The files**

**Create `windows/src-tauri/src/link/name.rs`:**

```rust
// The link's file-name rules (docs/LINK-CONTRACT.md, "File names"): the name a received file is saved under, and the name to use when that one is taken. A port of `sanitize_name` and
// `unique_name` of tests/fixtures/link/reference.py, replayed against filename-cases.json. The invisible and whitespace sets are written out by hand, as the contract says: they do not
// follow a Unicode table. NFC and NFKC come from the `unicode-normalization` crate; the categories Cc, Cf, Zl and Zp are `char::is_control` and the table below (a Rust `&str` cannot hold a lone
// surrogate, Cs). Pure: no file, no clock.

use std::collections::HashSet;

use unicode_normalization::UnicodeNormalization;

pub const NAME_BYTES_MAX: usize = 200;
pub const EXT_BYTES_MAX: usize = 16;
pub const COLLISION_MAX: u32 = 9999;

/// Every Default_Ignorable code point of Unicode, and U+2800 (BRAILLE PATTERN BLANK). The same table as `INVISIBLE_RANGES` in the reference.
const INVISIBLE_RANGES: &[(u32, u32)] = &[
    (0x00AD, 0x00AD), (0x034F, 0x034F), (0x061C, 0x061C), (0x115F, 0x1160), (0x17B4, 0x17B5), (0x180B, 0x180F), (0x200B, 0x200F), (0x202A, 0x202E),
    (0x2060, 0x206F), (0x2800, 0x2800), (0x3164, 0x3164), (0xFE00, 0xFE0F), (0xFEFF, 0xFEFF), (0xFFA0, 0xFFA0), (0xFFF0, 0xFFF8), (0x1BCA0, 0x1BCA3),
    (0x1D173, 0x1D17A), (0xE0000, 0xE0FFF),
];

/// Unicode category Cf. Rust's standard library has no table for it.
const FORMAT_RANGES: &[(u32, u32)] = &[
    (0x00AD, 0x00AD), (0x0600, 0x0605), (0x061C, 0x061C), (0x06DD, 0x06DD), (0x070F, 0x070F), (0x0890, 0x0891), (0x08E2, 0x08E2), (0x180E, 0x180E),
    (0x200B, 0x200F), (0x202A, 0x202E), (0x2060, 0x2064), (0x2066, 0x206F), (0xFEFF, 0xFEFF), (0xFFF9, 0xFFFB), (0x110BD, 0x110BD), (0x110CD, 0x110CD),
    (0x13430, 0x1343F), (0x1BCA0, 0x1BCA3), (0x1D173, 0x1D17A), (0xE0001, 0xE0001), (0xE0020, 0xE007F),
];

fn in_ranges(c: char, ranges: &[(u32, u32)]) -> bool {
    let n = c as u32;
    ranges.iter().any(|&(lo, hi)| n >= lo && n <= hi)
}

/// A character that shows nothing: a code point of the invisible table. The file-name and the device-name rules both use it.
pub fn is_invisible(c: char) -> bool {
    in_ranges(c, INVISIBLE_RANGES)
}

/// Cc, Cf, Zl or Zp: a control, a format character, a line or a paragraph separator.
pub fn is_bad_category(c: char) -> bool {
    c.is_control() || in_ranges(c, FORMAT_RANGES) || c == '\u{2028}' || c == '\u{2029}'
}

/// U+0020 or a Zs character.
pub fn is_space(c: char) -> bool {
    matches!(c as u32, 0x20 | 0xA0 | 0x1680 | 0x2000..=0x200A | 0x202F | 0x205F | 0x3000)
}

/// The owner's whitespace set for file names (answer 2b): a run of these becomes one U+0020.
fn in_space_run(c: char) -> bool {
    matches!(c as u32, 0x09..=0x0D | 0x20 | 0x85 | 0xA0 | 0x1680 | 0x2000..=0x200A | 0x2028 | 0x2029 | 0x202F | 0x205F | 0x3000)
}

fn collapse(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut in_run = false;
    for c in s.chars() {
        if in_space_run(c) {
            if !in_run {
                out.push(' ');
            }
            in_run = true;
        } else {
            out.push(c);
            in_run = false;
        }
    }
    out
}

/// Spaces off the start; spaces and dots off the end.
fn trim(s: &str) -> String {
    let start = s.trim_start_matches(is_space);
    start.trim_end_matches(|c: char| c == '.' || is_space(c)).to_string()
}

const RESERVED: &[&str] = &[
    "CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$", "COM0", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT0", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6",
    "LPT7", "LPT8", "LPT9", "COM\u{b9}", "COM\u{b2}", "COM\u{b3}", "LPT\u{b9}", "LPT\u{b2}", "LPT\u{b3}",
];

/// A Windows device name as the part before the first dot, trailing spaces off, ASCII case-insensitively.
fn reserved(s: &str) -> bool {
    let stem = s.split('.').next().unwrap_or("").trim_end_matches(' ').to_ascii_uppercase();
    RESERVED.contains(&stem.as_str())
}

/// (stem, extension): the extension is the part from the last dot, only when it is at most 16 bytes and the dot is not the first character.
fn split_ext(name: &str) -> (&str, &str) {
    match name.rfind('.') {
        Some(i) if i > 0 && name.len() - i <= EXT_BYTES_MAX => (&name[..i], &name[i..]),
        _ => (name, ""),
    }
}

/// `name`, cut to 200 bytes at a code point, keeping an extension of up to 16 bytes; the spaces and dots the cut leaves at the end go.
fn cut(name: &str) -> String {
    if name.len() <= NAME_BYTES_MAX {
        return name.to_string();
    }
    let (stem, ext) = split_ext(name);
    let room = NAME_BYTES_MAX - ext.len();
    let mut out = String::new();
    for c in stem.chars() {
        if out.len() + c.len_utf8() > room {
            break;
        }
        out.push(c);
    }
    trim(&out) + ext
}

fn nfkc(s: &str) -> String {
    s.nfkc().collect()
}

fn illegal(c: char) -> char {
    if "<>:\"|?*".contains(c) { '_' } else { c }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Reject {
    NotText,
    Invisible,
    Separator,
    Empty,
}

impl Reject {
    pub fn as_str(self) -> &'static str {
        match self {
            Reject::NotText => "not-text",
            Reject::Invisible => "invisible",
            Reject::Separator => "separator",
            Reject::Empty => "empty",
        }
    }
}

/// The name a received file is saved under, or why it is refused. The checks run on the NFC and the NFKC form, the name that is kept is the NFC form.
pub fn sanitize_name(raw: &str) -> Result<String, Reject> {
    let nfc = collapse(&raw.nfc().collect::<String>());
    let kc = collapse(&nfkc(raw));
    if [&nfc, &kc].iter().any(|form| form.chars().any(|c| is_bad_category(c) || is_invisible(c))) {
        return Err(Reject::Invisible);
    }
    if [&nfc, &kc].iter().any(|form| form.chars().any(|c| c == '/' || c == '\\')) {
        return Err(Reject::Separator);
    }
    if trim(&nfc).is_empty() || trim(&kc).is_empty() {
        return Err(Reject::Empty);
    }
    let mut name = trim(&nfc.chars().map(illegal).collect::<String>());
    let probe = trim(&kc.chars().map(illegal).collect::<String>());
    if name.is_empty() {
        return Err(Reject::Empty);
    }
    if reserved(&name) || reserved(&probe) {
        name = format!("_{name}");
    }
    name = cut(&name);
    // The cut can leave a device name too ("CON" and spaces, the spaces cut away): the same test runs again on the cut name, NFC and NFKC.
    if reserved(&name) || reserved(&trim(&nfkc(&name))) {
        name = cut(&format!("_{name}"));
    }
    if name.starts_with('.') {
        name = cut(&format!("_{name}"));
    }
    if trim(&name).is_empty() || trim(&nfkc(&name)).is_empty() {
        return Err(Reject::Empty);
    }
    Ok(name)
}

fn key(name: &str) -> String {
    name.nfc().collect::<String>().to_lowercase()
}

/// `name` itself when no taken name equals it, else "stem (n)ext" for the smallest n from 1 that is free; None after 9999 tries. Names are compared in NFC and without regard to case.
/// (The reference folds case with Python's `casefold`, which turns a sharp s into "ss"; `to_lowercase` does not. The volume decides which names are the same file, the file is created
/// exclusively whatever this says, and the contract lists the fold as a known limit.)
pub fn unique_name(name: &str, taken: &[String]) -> Option<String> {
    let used: HashSet<String> = taken.iter().map(|t| key(t)).collect();
    if !used.contains(&key(name)) {
        return Some(name.to_string());
    }
    let (stem, ext) = split_ext(name);
    (1..=COLLISION_MAX).map(|n| format!("{stem} ({n}){ext}")).find(|cand| !used.contains(&key(cand)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link::testutil::{arr, fixture, name};
    use serde_json::Value;

    fn sanitize_value(raw: &Value) -> Value {
        match raw.as_str() {
            None => serde_json::json!({"reject": "not-text"}),
            Some(s) => match sanitize_name(s) {
                Ok(n) => serde_json::json!({"ok": n}),
                Err(r) => serde_json::json!({"reject": r.as_str()}),
            },
        }
    }

    #[test]
    fn the_constants_are_the_fixtures() {
        let f = fixture("filename-cases.json");
        assert_eq!(f["bytesMax"], NAME_BYTES_MAX);
        assert_eq!(f["extBytesMax"], EXT_BYTES_MAX);
        assert_eq!(f["collisionMax"], COLLISION_MAX);
    }

    #[test]
    fn every_name_case_of_the_fixture() {
        let f = fixture("filename-cases.json");
        let cases = arr(&f, "cases");
        assert!(cases.len() >= 160, "{} cases", cases.len());
        for c in cases {
            assert_eq!(sanitize_value(&c["raw"]), c["out"], "{}", name(c));
        }
    }

    #[test]
    fn every_collision_case_of_the_fixture() {
        let f = fixture("filename-cases.json");
        for c in arr(&f, "uniqueCases") {
            let mut taken: Vec<String> = c["taken"].as_array().unwrap().iter().map(|v| v.as_str().unwrap().to_string()).collect();
            if let Some(n) = c.get("takenNumbered") {
                let (stem, ext) = (n["stem"].as_str().unwrap(), n["ext"].as_str().unwrap());
                for i in n["from"].as_u64().unwrap()..=n["to"].as_u64().unwrap() {
                    taken.push(format!("{stem} ({i}){ext}"));
                }
            }
            let got = unique_name(c["wanted"].as_str().unwrap(), &taken);
            let want = c["out"].as_str();
            assert_eq!(got.as_deref(), want, "{}", name(c));
        }
    }

    #[test]
    fn a_saved_name_is_never_longer_than_200_bytes_never_a_path_and_never_empty() {
        // A seeded walk over awkward pieces: no input may panic, and what is accepted obeys the three rules.
        let pieces = ["a", "é", "e\u{301}", " ", ".", "..", "/", "\\", "CON", ":", "\u{202e}", "\u{1f408}", "\t", "\u{a0}", "x".repeat(150).leak() as &str, "\0", "ﬁ", "\u{ff0f}"];
        let mut seed: u64 = 20261015;
        let mut next = |n: usize| {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            ((seed >> 33) as usize) % n
        };
        for _ in 0..4000 {
            let raw: String = (0..1 + next(8)).map(|_| pieces[next(pieces.len())]).collect();
            if let Ok(saved) = sanitize_name(&raw) {
                assert!(saved.len() <= NAME_BYTES_MAX, "{raw:?} -> {saved:?}");
                assert!(!saved.contains('/') && !saved.contains('\\') && !saved.is_empty(), "{raw:?} -> {saved:?}");
                assert_eq!(sanitize_name(&saved).as_deref(), Ok(saved.as_str()), "a saved name is its own sanitized form: {raw:?} -> {saved:?}");
            }
        }
    }
}
```


**Create `windows/src-tauri/src/link/frames.rs`:**

```rust
// The link's wire shapes (docs/LINK-CONTRACT.md, "On the wire"): records, the first record, the hello, the advert's TXT record and the six frames with the two pairing answers. A port of the
// matching functions of tests/fixtures/link/reference.py, replayed against frames.json. Strict: a decoder that repairs bad bytes is wrong, and a frame may not have a byte left over.
// Pure: no socket, no clock.

use super::bytes::{self, ID_LEN};
use super::name::{is_bad_category, is_invisible};

pub const VERSION: u8 = 1;
pub const NOISE_MAX: usize = 65535;
pub const TAG: usize = 16;
/// The data in one chunk frame, so that the frame and the 16-byte tag fill one Noise message of 65535 bytes exactly.
pub const CHUNK_MAX: usize = NOISE_MAX - TAG - 1 - ID_LEN - 8;
/// What a sender cuts a file into.
pub const CHUNK_SIZE: usize = 32768;
pub const RAW_NAME_MAX: usize = 1020;
pub const KIND_MAX: usize = 127;
pub const DEVICE_NAME_MAX: usize = 63;
/// 4 GiB per transfer, inclusive.
pub const SIZE_MAX: u64 = 4 * 1024 * 1024 * 1024;

pub const DECLINE_USER: u8 = 0;
pub const DECLINE_TIMEOUT: u8 = 1;
pub const DECLINE_BUSY: u8 = 2;
pub const DECLINE_TOO_LARGE: u8 = 3;
pub const DECLINE_BAD_OFFER: u8 = 4;

const T_OFFER: u8 = 1;
const T_ACCEPT: u8 = 2;
const T_DECLINE: u8 = 3;
const T_CHUNK: u8 = 4;
const T_DONE: u8 = 5;
const T_CANCEL: u8 = 6;
const T_PAIR_YES: u8 = 0x21;
const T_PAIR_NO: u8 = 0x22;

/// Why bytes do not decode: the reference's own word for it (`code`), which a test compares.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FrameError(pub &'static str);

impl std::fmt::Display for FrameError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.0)
    }
}

impl std::error::Error for FrameError {}

type Id = [u8; ID_LEN];

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Frame {
    Offer { id: Id, size: u64, name: String, kind: String },
    Accept { id: Id },
    Decline { id: Id, reason: u8 },
    Chunk { id: Id, offset: u64, data: Vec<u8> },
    Done { id: Id },
    Cancel { id: Id },
    PairYes,
    PairNo,
}

impl Frame {
    /// The transfer id, for every frame that has one.
    pub fn id(&self) -> Option<Id> {
        match self {
            Frame::Offer { id, .. } | Frame::Accept { id } | Frame::Decline { id, .. } | Frame::Chunk { id, .. } | Frame::Done { id } | Frame::Cancel { id } => Some(*id),
            Frame::PairYes | Frame::PairNo => None,
        }
    }

    pub fn is_pairing_answer(&self) -> bool {
        matches!(self, Frame::PairYes | Frame::PairNo)
    }
}

// ── Records ──────────────────────────────────────────────────────────────────

/// A record is a u16 big-endian length (1 to 65535) and that many bytes.
pub fn encode_record(payload: &[u8]) -> Result<Vec<u8>, FrameError> {
    if payload.is_empty() || payload.len() > NOISE_MAX {
        return Err(FrameError("record-length"));
    }
    let mut out = Vec::with_capacity(2 + payload.len());
    out.extend_from_slice(&(payload.len() as u16).to_be_bytes());
    out.extend_from_slice(payload);
    Ok(out)
}

/// (the whole records at the start of `buf`, the rest): the rest is a record that has not arrived completely. A length of 0 is an error.
pub fn split_records(buf: &[u8]) -> Result<(Vec<Vec<u8>>, Vec<u8>), FrameError> {
    let (mut out, mut pos) = (Vec::new(), 0);
    while buf.len() - pos >= 2 {
        let n = u16::from_be_bytes([buf[pos], buf[pos + 1]]) as usize;
        if n == 0 {
            return Err(FrameError("record-empty"));
        }
        if buf.len() - pos - 2 < n {
            break;
        }
        out.push(buf[pos + 2..pos + 2 + n].to_vec());
        pos += 2 + n;
    }
    Ok((out, buf[pos..].to_vec()))
}

// ── The first record ─────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Pair,
    Transfer,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Preamble {
    pub mode: Mode,
    pub id: Id,
}

pub fn encode_preamble(mode: Mode, id: &Id) -> Vec<u8> {
    let mut out = vec![VERSION, if mode == Mode::Pair { 1 } else { 2 }];
    out.extend_from_slice(id);
    out
}

pub fn decode_preamble(b: &[u8]) -> Result<Preamble, FrameError> {
    if b.len() != 2 + ID_LEN {
        return Err(FrameError("length"));
    }
    if b[0] != VERSION {
        return Err(FrameError("version"));
    }
    let mode = match b[1] {
        1 => Mode::Pair,
        2 => Mode::Transfer,
        _ => return Err(FrameError("mode")),
    };
    let id: Id = b[2..].try_into().unwrap();
    if (mode == Mode::Pair) != (id == [0; ID_LEN]) {
        return Err(FrameError("device-id"));
    }
    Ok(Preamble { mode, id })
}

// ── The hello and the advert ─────────────────────────────────────────────────

/// A device name is shown on the pairing card: 1 to 63 bytes of strict UTF-8, no control, format or separator character, no invisible character, no space at either end.
pub fn device_name(raw: &[u8]) -> Result<String, FrameError> {
    if raw.is_empty() || raw.len() > DEVICE_NAME_MAX {
        return Err(FrameError("name-length"));
    }
    let s = std::str::from_utf8(raw).map_err(|_| FrameError("utf8"))?;
    if s.chars().any(|c| is_bad_category(c) || is_invisible(c)) || s != s.trim() {
        return Err(FrameError("name-chars"));
    }
    Ok(s.to_string())
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Hello {
    pub id: Id,
    pub nonce: [u8; 32],
    pub name: String,
}

/// The payload of the second and third pairing messages: version, device id, a 32-byte nonce, name length and name.
pub fn encode_hello(id: &Id, nonce: &[u8; 32], name: &str) -> Result<Vec<u8>, FrameError> {
    let nb = device_name(name.as_bytes())?;
    let mut out = vec![VERSION];
    out.extend_from_slice(id);
    out.extend_from_slice(nonce);
    out.push(nb.len() as u8);
    out.extend_from_slice(nb.as_bytes());
    Ok(out)
}

pub fn decode_hello(b: &[u8]) -> Result<Hello, FrameError> {
    if b.len() < 2 + ID_LEN + 32 {
        return Err(FrameError("truncated"));
    }
    if b[0] != VERSION {
        return Err(FrameError("version"));
    }
    let id: Id = b[1..1 + ID_LEN].try_into().unwrap();
    if id == [0; ID_LEN] {
        return Err(FrameError("device-id"));
    }
    let nonce: [u8; 32] = b[1 + ID_LEN..1 + ID_LEN + 32].try_into().unwrap();
    let n = b[1 + ID_LEN + 32] as usize;
    let body = &b[2 + ID_LEN + 32..];
    if body.len() < n {
        return Err(FrameError("truncated"));
    }
    if body.len() > n {
        return Err(FrameError("trailing"));
    }
    Ok(Hello { id, nonce, name: device_name(body)? })
}

/// What the advert's own id must be compared with. `Null` exists for the fixtures (a null `own_id` is present and is not an id: fail closed); an app passes `Absent` or `Id`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OwnId<'a> {
    Absent,
    Null,
    Id(&'a str),
}

/// The three TXT keys that matter. A key that is missing, or whose value is not text, is None.
#[derive(Debug, Clone, Copy, Default)]
pub struct Txt<'a> {
    pub v: Option<&'a str>,
    pub id: Option<&'a str>,
    pub name: Option<&'a str>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Advert {
    pub id: String,
    pub name: String,
}

/// An advert's TXT record. Anyone on the network can send one, so it is checked like a name on a card. It carries no key: a paired id under another key is decided at the hello.
pub fn parse_txt(txt: &Txt<'_>, own: OwnId<'_>) -> Result<Advert, FrameError> {
    if txt.v != Some("1") {
        return Err(FrameError("version"));
    }
    let id = match txt.id {
        Some(i) if bytes::is_id_hex(i) && i != "0".repeat(2 * ID_LEN) => i,
        _ => return Err(FrameError("device-id")),
    };
    match own {
        OwnId::Absent => {}
        OwnId::Null => return Err(FrameError("device-id")),
        OwnId::Id(o) if !bytes::is_id_hex(o) => return Err(FrameError("device-id")),
        OwnId::Id(o) if o == id => return Err(FrameError("own-id")),
        OwnId::Id(_) => {}
    }
    let name = txt.name.ok_or(FrameError("name-length"))?;
    Ok(Advert { id: id.to_string(), name: device_name(name.as_bytes())? })
}

// ── The six frames ───────────────────────────────────────────────────────────

pub fn encode_frame(f: &Frame) -> Result<Vec<u8>, FrameError> {
    Ok(match f {
        Frame::PairYes => vec![T_PAIR_YES],
        Frame::PairNo => vec![T_PAIR_NO],
        Frame::Offer { id, size, name, kind } => {
            if name.is_empty() || name.len() > RAW_NAME_MAX {
                return Err(FrameError("name-length"));
            }
            if kind.len() > KIND_MAX || !kind.bytes().all(|c| (0x20..=0x7E).contains(&c)) {
                return Err(FrameError("kind"));
            }
            let mut out = vec![T_OFFER];
            out.extend_from_slice(id);
            out.extend_from_slice(&size.to_be_bytes());
            out.extend_from_slice(&(name.len() as u16).to_be_bytes());
            out.extend_from_slice(name.as_bytes());
            out.push(kind.len() as u8);
            out.extend_from_slice(kind.as_bytes());
            out
        }
        Frame::Accept { id } => with_id(T_ACCEPT, id),
        Frame::Decline { id, reason } => {
            let mut out = with_id(T_DECLINE, id);
            out.push(*reason);
            out
        }
        Frame::Chunk { id, offset, data } => {
            if data.is_empty() {
                return Err(FrameError("chunk-empty"));
            }
            if data.len() > CHUNK_MAX {
                return Err(FrameError("chunk-long"));
            }
            let mut out = with_id(T_CHUNK, id);
            out.extend_from_slice(&offset.to_be_bytes());
            out.extend_from_slice(data);
            out
        }
        Frame::Done { id } => with_id(T_DONE, id),
        Frame::Cancel { id } => with_id(T_CANCEL, id),
    })
}

fn with_id(t: u8, id: &Id) -> Vec<u8> {
    let mut out = vec![t];
    out.extend_from_slice(id);
    out
}

pub fn decode_frame(b: &[u8]) -> Result<Frame, FrameError> {
    let Some((&t, body)) = b.split_first() else { return Err(FrameError("empty")) };
    if !matches!(t, T_OFFER..=T_CANCEL | T_PAIR_YES | T_PAIR_NO) {
        return Err(FrameError("unknown-type"));
    }
    if t == T_PAIR_YES || t == T_PAIR_NO {
        if !body.is_empty() {
            return Err(FrameError("trailing"));
        }
        return Ok(if t == T_PAIR_YES { Frame::PairYes } else { Frame::PairNo });
    }
    if body.len() < ID_LEN {
        return Err(FrameError("truncated"));
    }
    let id: Id = body[..ID_LEN].try_into().unwrap();
    let rest = &body[ID_LEN..];
    match t {
        T_ACCEPT | T_DONE | T_CANCEL => {
            if !rest.is_empty() {
                return Err(FrameError("trailing"));
            }
            Ok(match t {
                T_ACCEPT => Frame::Accept { id },
                T_DONE => Frame::Done { id },
                _ => Frame::Cancel { id },
            })
        }
        T_DECLINE => {
            match rest.len() {
                0 => return Err(FrameError("truncated")),
                1 => {}
                _ => return Err(FrameError("trailing")),
            }
            if rest[0] > DECLINE_BAD_OFFER {
                return Err(FrameError("reason"));
            }
            Ok(Frame::Decline { id, reason: rest[0] })
        }
        T_CHUNK => {
            if rest.len() < 8 {
                return Err(FrameError("truncated"));
            }
            let data = &rest[8..];
            if data.is_empty() {
                return Err(FrameError("chunk-empty"));
            }
            if data.len() > CHUNK_MAX {
                return Err(FrameError("chunk-long"));
            }
            Ok(Frame::Chunk { id, offset: u64::from_be_bytes(rest[..8].try_into().unwrap()), data: data.to_vec() })
        }
        _ => {
            if rest.len() < 10 {
                return Err(FrameError("truncated"));
            }
            let size = u64::from_be_bytes(rest[..8].try_into().unwrap());
            let n = u16::from_be_bytes([rest[8], rest[9]]) as usize;
            if !(1..=RAW_NAME_MAX).contains(&n) {
                return Err(FrameError("name-length"));
            }
            if rest.len() < 10 + n + 1 {
                return Err(FrameError("truncated"));
            }
            let (nb, k, kb) = (&rest[10..10 + n], rest[10 + n] as usize, &rest[11 + n..]);
            if kb.len() < k {
                return Err(FrameError("truncated"));
            }
            if kb.len() > k {
                return Err(FrameError("trailing"));
            }
            if k > KIND_MAX || kb.iter().any(|c| !(0x20..=0x7E).contains(c)) {
                return Err(FrameError("kind"));
            }
            let name = std::str::from_utf8(nb).map_err(|_| FrameError("utf8"))?.to_string();
            Ok(Frame::Offer { id, size, name, kind: String::from_utf8(kb.to_vec()).unwrap() })
        }
    }
}

/// [(offset, length)] that cover `size` bytes; an empty file has none, and then the sender goes straight to `done`.
pub fn plan_chunks(size: u64, chunk_size: usize) -> Vec<(u64, usize)> {
    let mut out = Vec::new();
    let mut offset = 0u64;
    while offset < size {
        let len = (size - offset).min(chunk_size as u64) as usize;
        out.push((offset, len));
        offset += len as u64;
    }
    out
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::link::testutil::{arr, fixture, name};
    use serde_json::{json, Value};

    pub fn frame_of(v: &Value) -> Frame {
        let id = bytes::id16(v["id"].as_str().unwrap_or("")).unwrap_or([0; 16]);
        match v["type"].as_str().unwrap() {
            "offer" => Frame::Offer { id, size: v["size"].as_u64().unwrap(), name: v["name"].as_str().unwrap().to_string(), kind: v["kind"].as_str().unwrap().to_string() },
            "accept" => Frame::Accept { id },
            "decline" => Frame::Decline { id, reason: v["reason"].as_u64().unwrap() as u8 },
            "chunk" => Frame::Chunk { id, offset: v["offset"].as_u64().unwrap(), data: bytes::unhex(v["data"].as_str().unwrap()).unwrap() },
            "done" => Frame::Done { id },
            "cancel" => Frame::Cancel { id },
            "pair-yes" => Frame::PairYes,
            "pair-no" => Frame::PairNo,
            other => panic!("frame type {other}"),
        }
    }

    pub fn json_of(f: &Frame) -> Value {
        let hex = |id: &Id| bytes::hex(id);
        match f {
            Frame::Offer { id, size, name, kind } => json!({"type": "offer", "id": hex(id), "size": size, "name": name, "kind": kind}),
            Frame::Accept { id } => json!({"type": "accept", "id": hex(id)}),
            Frame::Decline { id, reason } => json!({"type": "decline", "id": hex(id), "reason": reason}),
            Frame::Chunk { id, offset, data } => json!({"type": "chunk", "id": hex(id), "offset": offset, "data": bytes::hex(data)}),
            Frame::Done { id } => json!({"type": "done", "id": hex(id)}),
            Frame::Cancel { id } => json!({"type": "cancel", "id": hex(id)}),
            Frame::PairYes => json!({"type": "pair-yes"}),
            Frame::PairNo => json!({"type": "pair-no"}),
        }
    }

    #[test]
    fn the_limits_and_numbers_are_the_fixtures() {
        let f = fixture("frames.json");
        assert_eq!(f["noiseMax"], NOISE_MAX);
        assert_eq!(f["tag"], TAG);
        assert_eq!(f["idLen"], ID_LEN);
        assert_eq!(f["protocolVersion"], VERSION);
        assert_eq!(f["chunkMax"], CHUNK_MAX);
        assert_eq!(f["chunkSize"], CHUNK_SIZE);
        assert_eq!(f["rawNameMax"], RAW_NAME_MAX);
        assert_eq!(f["kindMax"], KIND_MAX);
        assert_eq!(f["deviceNameMax"], DEVICE_NAME_MAX);
        assert_eq!(f["sizeMax"], SIZE_MAX);
        assert_eq!(f["types"], json!({"offer": 1, "accept": 2, "decline": 3, "chunk": 4, "done": 5, "cancel": 6, "pairYes": 33, "pairNo": 34}));
        assert_eq!(f["declineReasons"], json!({"user": 0, "timeout": 1, "busy": 2, "tooLarge": 3, "badOffer": 4}));
    }

    #[test]
    fn every_frame_encodes_and_decodes_to_its_bytes() {
        let f = fixture("frames.json");
        for c in arr(&f, "frames") {
            let frame = frame_of(&c["frame"]);
            let want = bytes::unhex(c["hex"].as_str().unwrap()).unwrap();
            assert_eq!(encode_frame(&frame).unwrap(), want, "encode: {}", name(c));
            assert_eq!(decode_frame(&want).unwrap(), frame, "decode: {}", name(c));
        }
    }

    #[test]
    fn every_reject_names_its_error() {
        let f = fixture("frames.json");
        let rows = arr(&f, "rejects");
        assert!(rows.len() >= 35);
        for c in rows {
            let got = decode_frame(&bytes::unhex(c["hex"].as_str().unwrap()).unwrap());
            assert_eq!(got.err().map(|e| e.0), c["error"].as_str(), "{}", name(c));
        }
    }

    #[test]
    fn a_chunk_of_65494_bytes_is_the_most_and_65495_is_refused() {
        let f = fixture("frames.json");
        for c in arr(&f, "limits") {
            let id = bytes::id16(c["id"].as_str().unwrap()).unwrap();
            let fill = bytes::unhex(c["fill"].as_str().unwrap()).unwrap()[0];
            let data = vec![fill; c["count"].as_u64().unwrap() as usize];
            let frame = Frame::Chunk { id, offset: c["offset"].as_u64().unwrap(), data };
            let got = encode_frame(&frame).and_then(|b| decode_frame(&b)).map(|_| "ok").unwrap_or_else(|e| e.0);
            assert_eq!(got, c["out"].as_str().unwrap(), "{}", name(c));
        }
    }

    #[test]
    fn every_hello_case() {
        let f = fixture("frames.json");
        for c in arr(&f, "hello") {
            let got = match decode_hello(&bytes::unhex(c["hex"].as_str().unwrap()).unwrap()) {
                Ok(h) => json!({"id": bytes::hex(&h.id), "nonce": bytes::hex(&h.nonce), "name": h.name}),
                Err(e) => json!({"error": e.0}),
            };
            assert_eq!(got, c["out"], "{}", name(c));
            if let Some(ok) = c["out"].get("id") {
                let again = encode_hello(&bytes::id16(ok.as_str().unwrap()).unwrap(), &bytes::key32(c["out"]["nonce"].as_str().unwrap()).unwrap(), c["out"]["name"].as_str().unwrap()).unwrap();
                assert_eq!(bytes::hex(&again), c["hex"].as_str().unwrap(), "encode: {}", name(c));
            }
        }
    }

    #[test]
    fn every_advert_case() {
        let f = fixture("frames.json");
        for c in arr(&f, "txt") {
            let t = &c["txt"];
            let own = match c.get("ownId") {
                None => OwnId::Absent,
                Some(Value::Null) => OwnId::Null,
                Some(v) => OwnId::Id(v.as_str().unwrap()),
            };
            let got = match t.as_object() {
                None => json!({"error": "not-a-record"}),
                Some(m) => {
                    let get = |k: &str| m.get(k).and_then(Value::as_str);
                    match parse_txt(&Txt { v: get("v"), id: get("id"), name: get("name") }, own) {
                        Ok(a) => json!({"id": a.id, "name": a.name}),
                        Err(e) => json!({"error": e.0}),
                    }
                }
            };
            assert_eq!(got, c["out"], "{}", name(c));
        }
    }

    #[test]
    fn every_preamble_case() {
        let f = fixture("frames.json");
        for c in arr(&f, "preamble") {
            let got = match decode_preamble(&bytes::unhex(c["hex"].as_str().unwrap()).unwrap()) {
                Ok(p) => json!({"mode": if p.mode == Mode::Pair { "pair" } else { "transfer" }, "id": bytes::hex(&p.id)}),
                Err(e) => json!({"error": e.0}),
            };
            assert_eq!(got, c["out"], "{}", name(c));
        }
    }

    #[test]
    fn every_record_case() {
        let f = fixture("frames.json");
        for c in arr(&f, "records") {
            let got = match split_records(&bytes::unhex(c["hex"].as_str().unwrap()).unwrap()) {
                Ok((records, rest)) => json!({"records": records.iter().map(|r| bytes::hex(r)).collect::<Vec<_>>(), "rest": bytes::hex(&rest)}),
                Err(e) => json!({"error": e.0}),
            };
            assert_eq!(got, c["out"], "{}", name(c));
        }
        for c in arr(&f, "recordEncode") {
            let got = match encode_record(&bytes::unhex(c["payload"].as_str().unwrap()).unwrap()) {
                Ok(r) => json!({"hex": bytes::hex(&r)}),
                Err(e) => json!({"error": e.0}),
            };
            assert_eq!(got, c["out"], "{}", name(c));
        }
        let max = vec![7u8; NOISE_MAX];
        assert!(encode_record(&max).is_ok());
        assert_eq!(encode_record(&vec![7u8; NOISE_MAX + 1]).unwrap_err().0, "record-length");
    }

    #[test]
    fn a_hello_name_is_never_trusted_on_the_encode_side_either() {
        let id = [1u8; 16];
        assert!(encode_hello(&id, &[2; 32], "Desk PC").is_ok());
        assert_eq!(encode_hello(&id, &[2; 32], "").unwrap_err().0, "name-length");
        assert_eq!(encode_hello(&id, &[2; 32], &"n".repeat(64)).unwrap_err().0, "name-length");
        assert_eq!(encode_hello(&id, &[2; 32], " Desk").unwrap_err().0, "name-chars");
    }

    #[test]
    fn no_input_makes_the_decoders_panic() {
        // Seeded random bytes, with a real frame type at the front half of the time.
        let mut seed: u64 = 20261015;
        let mut next = |n: usize| {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            ((seed >> 33) as usize) % n
        };
        for _ in 0..8000 {
            let len = next(80);
            let mut b: Vec<u8> = (0..len).map(|_| next(256) as u8).collect();
            if !b.is_empty() && next(2) == 0 {
                b[0] = [1, 2, 3, 4, 5, 6, 0x21, 0x22][next(8)];
            }
            let _ = decode_frame(&b);
            let _ = decode_hello(&b);
            let _ = decode_preamble(&b);
            let _ = split_records(&b);
        }
    }

    #[test]
    fn chunk_plans() {
        let f = crate::link::testutil::fixture("flow-cases.json");
        for c in arr(&f, "chunkPlans") {
            let got: Vec<Value> = plan_chunks(c["size"].as_u64().unwrap(), c["chunkSize"].as_u64().unwrap() as usize).iter().map(|&(o, l)| json!([o, l])).collect();
            assert_eq!(Value::Array(got), c["out"], "{}", name(c));
        }
    }
}
```


- [ ] **Step 3: Run the tests**

Run:

```bash
windows/scripts/cargo-linux.sh test --target-dir /repo/windows/target/g2-tauri -p notchmeow link::name
windows/scripts/cargo-linux.sh test --target-dir /repo/windows/target/g2-tauri -p notchmeow link::frames
```

Expected: `test result: ok. 4 passed` (the 162 name cases and the 14 collision cases are two of the four) and `test result: ok. 11 passed` (every frame both ways, 37 rejects with their error words, the 65494/65495 limit, the hello, advert, preamble and record rows, an 8000-input no-panic walk and the chunk plans).

- [ ] **Step 4: Prove it bites**

Run:

```bash
M="python3 .claude/checkpoints/g2-tauri/mut.py rust"
$M windows/src-tauri/src/link/name.rs '(0x2060, 0x206F), (0x2800, 0x2800),' '(0x2060, 0x206F),' link::
$M windows/src-tauri/src/link/frames.rs '    if body.len() < n {' '    if body.len() < n + 1 {' link::frames
$M windows/src-tauri/src/link/frames.rs 'pub const CHUNK_MAX: usize = NOISE_MAX - TAG - 1 - ID_LEN - 8;' 'pub const CHUNK_MAX: usize = NOISE_MAX - TAG - 1 - ID_LEN - 9;' link::frames
```

Expected: each ends `test result: FAILED` (the first: `every_name_case_of_the_fixture` and `every_advert_case`; the second: `every_hello_case`; the third: `the_limits_and_numbers_are_the_fixtures` and `a_chunk_of_65494_bytes_is_the_most_and_65495_is_refused`).

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and g2/tauri-link
git add windows/src-tauri/src/link/mod.rs windows/src-tauri/src/link/name.rs windows/src-tauri/src/link/frames.rs
git commit -F - <<'MSG'
feat(link): the file-name rule and the wire shapes, replayed against the contract (G2-tauri)

sanitize_name and unique_name with the contract's hand-written invisible and whitespace tables (162 name cases, the collision cases, a seeded walk); records, the preamble, the hello, the advert's TXT record and the six frames with their strict decoders (every frame both ways, every reject with its word, the chunk limit, chunk plans).

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Then write the task's line in the ledger: the commit, the test counts, the agent and the model.

---


### Task 4: The pairing and the transfer rules: the machines, the clocks, the gate, the connection rules

**Agent:** `nm-implementer-light` (Haiku 5.5, medium). The code is given in full.

**Files:**
- Create: `windows/src-tauri/src/link/pairing.rs`, `windows/src-tauri/src/link/flow.rs`
- Modify: `windows/src-tauri/src/link/mod.rs`

**Interfaces:**
- Consumes: `link::bytes`, `link::frames` (`Frame`, the `DECLINE_*` numbers, `SIZE_MAX`, and in tests `frames::tests::{frame_of, json_of}`), `link::name::sanitize_name`; `pairing-cases.json` and `flow-cases.json`.
- Produces: `pairing::{commit_of, pairing_code, attempt_allowed, window_open, offer_expired, Gate, Responder, Initiator, REvent, IEvent, Reveal, Out, Say, Notify, Refusal, Ids, OwnId, RPhase, IPhase, Answers, responder_step, initiator_step, GAP_MS, WINDOW_MS, OFFER_TIMEOUT_MS}`; `flow::{receiver_step, sender_step, RState, SState, Event, SEvent, User, Notify, Abort, Out, first_frame_expired, Place, PlaceEvent, place_step, Conn, ConnEvent, ConnOut, connection_step, FIRST_FRAME_MS, DECLINES_PER_CONNECTION}`.

**The machines take events and read no clock.** The pairing machines and the transfer machines are pure: a state, one event (with the time and the nonces the caller drew) and the answer `{state, send, notify, because|abort}`. `Gate` is the owner's rule of 2026-10-15 (an incoming pairing only while Settings → Devices is on screen or within 2 minutes after a Pair click here) as plain values; its "Devices is open" is a count of openers here because the Mac's is; the service (Task 13) only ever sets it from a state (`set_devices_open(bool)`), so it cannot drift. `flow::connection_step` is the contract's `receiver_connection_step`: `receiver_step` plus the machine's one transfer place, one machine-made decline per connection and the first-frame clock. The runs in Task 11 call it directly, so the rule is run where it is tested.

- [ ] **Step 1: Register the modules**

Run:

```bash
python3 - <<'EOF'
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")
edit("windows/src-tauri/src/link/mod.rs", "// MODULES: add new modules above this line", "pub mod flow;\npub mod pairing;\n// MODULES: add new modules above this line")
EOF
```

- [ ] **Step 2: The files**

**Create `windows/src-tauri/src/link/pairing.rs`:**

```rust
// The pairing (docs/LINK-CONTRACT.md, "The pairing code"): the commitment, the six digits, the clocks, the gate on incoming pairings and the two machines (the responder's and the
// initiator's). A port of the matching functions of tests/fixtures/link/reference.py, replayed against pairing-cases.json. The machines take one event at a time and answer
// {state, send, notify, because}; they read no clock and draw no random number (the caller gives `now` and the nonces). Pure.
//
// Hex strings stay strings here, as in the reference: a value that is not exactly 64 (or 32) lower-case hex digits is a refusal named by the contract, so the machine checks them itself.

use std::collections::BTreeMap;

use sha2::{Digest, Sha256};

use super::bytes;

pub const COMMIT_LABEL: &[u8] = b"notchmeow-link pairing commit v1";
pub const CODE_LABEL: &[u8] = b"notchmeow-link pairing code v1";
pub const CODE_DIGITS: usize = 6;
/// At most one pairing attempt every 30 seconds.
pub const GAP_MS: i64 = 30_000;
/// The pairing window closes after 2 minutes.
pub const WINDOW_MS: i64 = 120_000;
/// An offer nobody answers is declined after 2 minutes.
pub const OFFER_TIMEOUT_MS: i64 = 120_000;

pub fn commit_of(nonce: &[u8; 32], static_pub: &[u8; 32]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(COMMIT_LABEL);
    h.update(static_pub);
    h.update(nonce);
    h.finalize().into()
}

/// The six digits both screens show: SHA-256 over the label, the initiator's static key, the responder's static key, the initiator's nonce and the responder's nonce; the first 8 bytes
/// as a big-endian number; modulo 10^6; leading zeros kept. The handshake hash is deliberately not an input.
pub fn pairing_code(nonce_i: &[u8; 32], nonce_r: &[u8; 32], static_i: &[u8; 32], static_r: &[u8; 32]) -> String {
    let mut h = Sha256::new();
    h.update(CODE_LABEL);
    h.update(static_i);
    h.update(static_r);
    h.update(nonce_i);
    h.update(nonce_r);
    let d = h.finalize();
    let n = u64::from_be_bytes(d[..8].try_into().unwrap()) % 1_000_000;
    format!("{n:06}")
}

// ── The clocks (whole milliseconds on a monotonic clock; a negative value is "not a time") ──

fn whole(ms: i64) -> bool {
    ms >= 0
}

/// `last` is None for the first attempt. Allowed when 30 s have passed (exactly 30 s is allowed); a clock that went back, or a value that is not a time, refuses.
pub fn attempt_allowed(last: Option<i64>, now: i64) -> bool {
    if !whole(now) || last.is_some_and(|l| !whole(l)) {
        return false;
    }
    last.map_or(true, |l| now - l >= GAP_MS)
}

/// Open below 120 s after `start`.
pub fn window_open(start: i64, now: i64) -> bool {
    whole(start) && whole(now) && (0..WINDOW_MS).contains(&(now - start))
}

/// Expired at exactly 120 s. A clock that went back, or a bad value, counts as expired: declining is the safe side.
pub fn offer_expired(offered: i64, now: i64) -> bool {
    !(whole(offered) && whole(now) && (0..OFFER_TIMEOUT_MS).contains(&(now - offered)))
}

/// Who may start an incoming pairing: only while Settings → Devices is open, or within 2 minutes after the user clicked "Pair a machine" here (the owner's answer of 2026-10-15). At any other
/// time the hello is refused silently. Several windows may show Devices, so the opening is a count.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Gate {
    devices_open: u32,
    clicked_at: Option<i64>,
}

impl Gate {
    pub fn devices_appeared(&mut self) {
        self.devices_open += 1;
    }
    pub fn devices_disappeared(&mut self) {
        self.devices_open = self.devices_open.saturating_sub(1);
    }
    pub fn pair_clicked(&mut self, now: i64) {
        self.clicked_at = Some(now);
    }
    /// `now` is None when there is no clock: refused unless Devices is open.
    pub fn allows(&self, now: Option<i64>) -> bool {
        self.devices_open > 0 || matches!((self.clicked_at, now), (Some(c), Some(n)) if window_open(c, n))
    }
}

// ── The two machines ─────────────────────────────────────────────────────────

/// Why a pairing was refused. The connection is closed, nothing is sent, and the cause stays in the local log; `as_str` is the contract's word.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Refusal {
    CommitLength,
    CommitReplayed,
    AttemptTooSoon,
    NoCommit,
    RevealLate,
    RevealLength,
    RevealMismatch,
    DeviceId,
    OwnId,
    IdKeyMismatch,
    Unexpected,
    StartLength,
    NonceRepeated,
    NonceLength,
    WindowClosed,
    SaidNo,
}

impl Refusal {
    pub fn as_str(self) -> &'static str {
        match self {
            Refusal::CommitLength => "commit-length",
            Refusal::CommitReplayed => "commit-replayed",
            Refusal::AttemptTooSoon => "attempt-too-soon",
            Refusal::NoCommit => "no-commit",
            Refusal::RevealLate => "reveal-late",
            Refusal::RevealLength => "reveal-length",
            Refusal::RevealMismatch => "reveal-mismatch",
            Refusal::DeviceId => "device-id",
            Refusal::OwnId => "own-id",
            Refusal::IdKeyMismatch => "id-key-mismatch",
            Refusal::Unexpected => "unexpected",
            Refusal::StartLength => "start-length",
            Refusal::NonceRepeated => "nonce-repeated",
            Refusal::NonceLength => "nonce-length",
            Refusal::WindowClosed => "window-closed",
            Refusal::SaidNo => "said-no",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Notify {
    NonceSent,
    CommitSent,
    ShowCode,
    Store,
    Discard,
}

impl Notify {
    pub fn as_str(self) -> &'static str {
        match self {
            Notify::NonceSent => "nonce-sent",
            Notify::CommitSent => "commit-sent",
            Notify::ShowCode => "show-code",
            Notify::Store => "store",
            Notify::Discard => "discard",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Say {
    Nonce(String),
    Commit(String),
    Reveal(String),
    Pair(bool),
}

/// A machine's own device id. `Null` exists for the fixtures (present and not an id: every hello is then refused); an app passes `Absent` until it has an id, then `Id`.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub enum OwnId {
    #[default]
    Absent,
    Null,
    Id(String),
}

/// The two inputs a machine keeps from one step to the next: its own device id and the devices it has paired (device id to the static key stored for it, both lower-case hex).
/// `paired` is None when it was not given (an empty map is a different state in the fixtures).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Ids {
    pub own_id: OwnId,
    pub paired: Option<BTreeMap<String, String>>,
}

fn id_hex(s: &str) -> bool {
    bytes::is_id_hex(s)
}

fn key_hex(s: &str) -> bool {
    bytes::is_key_hex(s)
}

/// False when the machine's own id, if it has one, is not 32 lower-case hex digits, or a paired id is not, or a paired key is not 64. Fail closed: a capital letter is never lower-cased.
fn ids_canonical(ids: &Ids) -> bool {
    let own = match &ids.own_id {
        OwnId::Absent => true,
        OwnId::Null => false,
        OwnId::Id(s) => id_hex(s),
    };
    own && ids.paired.iter().flatten().all(|(i, k)| id_hex(i) && key_hex(k))
}

/// Why a peer's hello is refused, given the machine's own id and its paired devices. The static key compared is the one the Noise handshake authenticated, never a value in the hello.
fn peer_refusal(ids: &Ids, peer_id: Option<&str>, peer_static: &str, length_reason: Refusal) -> Option<Refusal> {
    let Some(peer) = peer_id.filter(|p| id_hex(p)) else { return Some(length_reason) };
    if peer == "00".repeat(bytes::ID_LEN) {
        return Some(Refusal::DeviceId);
    }
    if !ids_canonical(ids) {
        return Some(Refusal::DeviceId);
    }
    if matches!(&ids.own_id, OwnId::Id(o) if o == peer) {
        return Some(Refusal::OwnId);
    }
    if ids.paired.as_ref().and_then(|p| p.get(peer)).is_some_and(|k| k != peer_static) {
        return Some(Refusal::IdKeyMismatch);
    }
    None
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Out<S> {
    pub state: S,
    pub send: Vec<Say>,
    pub notify: Option<Notify>,
    pub because: Option<Refusal>,
}

fn out<S>(state: S) -> Out<S> {
    Out { state, send: vec![], notify: None, because: None }
}

fn refuse<S>(state: S, because: Refusal) -> Out<S> {
    Out { because: Some(because), ..out(state) }
}

/// What the two users said, after the code is shown: `mine` is this user's click on "They match", `theirs` the other side's `pair-yes`. A "no" ends the pairing, so it is never kept here.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Answers {
    pub mine: bool,
    pub theirs: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Seen {
    pub commit: String,
    pub at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RPhase {
    Idle,
    Committed { commit: String, start: i64, nonce: String },
    Coded { start: i64, code: String, answers: Answers },
}

/// The responder: the machine that is asked to pair. `seen` is the recent commitments the app keeps across connections, `last` the time of the last attempt.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Responder {
    pub phase: RPhase,
    pub seen: Vec<Seen>,
    pub last: Option<i64>,
    pub ids: Ids,
}

impl Responder {
    pub fn new(ids: Ids) -> Responder {
        Responder { phase: RPhase::Idle, seen: vec![], last: None, ids }
    }
    fn idle(&self) -> Responder {
        Responder { phase: RPhase::Idle, ..self.clone() }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Reveal {
    pub nonce: String,
    pub static_key: String,
    pub own: String,
    pub peer_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum REvent {
    /// The first message arrived: the commitment, and the app's fresh nonce.
    Commit { commit: String, nonce: String, now: i64 },
    /// The third message was opened: the initiator's nonce and static key, this machine's own static key, and the initiator's device id from its hello.
    Reveal { reveal: Reveal, now: i64 },
    User { yes: bool, now: i64 },
    Peer { yes: bool, now: i64 },
    /// Anything the machine does not know: nothing changes.
    Other,
}

/// What both machines do after the code is shown: a click, or the other side's answer. Anything but exactly "yes" is a no.
fn answer<S>(answers: Answers, start: i64, who_mine: bool, yes: bool, now: i64, idle: S, keep: impl FnOnce(Answers) -> S) -> Out<S> {
    if !window_open(start, now) {
        return Out { notify: Some(Notify::Discard), because: Some(Refusal::WindowClosed), ..out(idle) };
    }
    if !yes {
        return Out { send: if who_mine { vec![Say::Pair(false)] } else { vec![] }, notify: Some(Notify::Discard), because: Some(Refusal::SaidNo), ..out(idle) };
    }
    let new = if who_mine { Answers { mine: true, ..answers } } else { Answers { theirs: true, ..answers } };
    let send = if who_mine { vec![Say::Pair(true)] } else { vec![] };
    if new.mine && new.theirs {
        return Out { send, notify: Some(Notify::Store), ..out(idle) };
    }
    Out { send, ..out(keep(new)) }
}

pub fn responder_step(m: &Responder, ev: &REvent) -> Out<Responder> {
    let idle = m.idle();
    match ev {
        REvent::Commit { commit, nonce, now } => {
            if !matches!(m.phase, RPhase::Idle) {
                return refuse(idle, Refusal::Unexpected);
            }
            if !key_hex(commit) || !key_hex(nonce) {
                return refuse(idle, Refusal::CommitLength);
            }
            if m.seen.iter().any(|e| &e.commit == commit && window_open(e.at, *now)) {
                return refuse(idle, Refusal::CommitReplayed); // checked before the gap, so a replay is named as one
            }
            if !attempt_allowed(m.last, *now) {
                return refuse(idle, Refusal::AttemptTooSoon);
            }
            let mut seen: Vec<Seen> = m.seen.iter().filter(|e| window_open(e.at, *now)).cloned().collect();
            seen.push(Seen { commit: commit.clone(), at: *now });
            Out {
                send: vec![Say::Nonce(nonce.clone())],
                notify: Some(Notify::NonceSent),
                ..out(Responder { phase: RPhase::Committed { commit: commit.clone(), start: *now, nonce: nonce.clone() }, seen, last: Some(*now), ids: m.ids.clone() })
            }
        }
        REvent::Reveal { reveal: r, now } => {
            let (commit, start, nonce) = match &m.phase {
                RPhase::Idle => return refuse(idle, Refusal::NoCommit), // a reveal with no commitment before it
                RPhase::Committed { commit, start, nonce } => (commit, *start, nonce),
                RPhase::Coded { .. } => return refuse(idle, Refusal::Unexpected),
            };
            if !window_open(start, *now) {
                return refuse(idle, Refusal::RevealLate);
            }
            let (Some(rn), Some(rs), Some(own)) = (bytes::key32(&r.nonce), bytes::key32(&r.static_key), bytes::key32(&r.own)) else { return refuse(idle, Refusal::RevealLength) };
            if bytes::hex(&commit_of(&rn, &rs)) != *commit {
                return refuse(idle, Refusal::RevealMismatch); // a wrong nonce and a wrong key look the same, on purpose
            }
            if let Some(why) = peer_refusal(&m.ids, r.peer_id.as_deref(), &r.static_key, Refusal::RevealLength) {
                return refuse(idle, why);
            }
            let code = pairing_code(&rn, &bytes::key32(nonce).unwrap_or([0; 32]), &rs, &own);
            Out { notify: Some(Notify::ShowCode), ..out(Responder { phase: RPhase::Coded { start, code, answers: Answers::default() }, ..idle }) }
        }
        REvent::User { yes, now } | REvent::Peer { yes, now } => {
            let RPhase::Coded { start, code, answers } = &m.phase else { return out(m.clone()) }; // an answer before there is a code is ignored
            let mine = matches!(ev, REvent::User { .. });
            answer(*answers, *start, mine, *yes, *now, idle, |a| Responder { phase: RPhase::Coded { start: *start, code: code.clone(), answers: a }, ..m.clone() })
        }
        REvent::Other => out(m.clone()),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IPhase {
    Idle,
    Started { nonce: String, static_key: String, start: i64 },
    Coded { start: i64, code: String, answers: Answers },
}

/// The initiator: the machine whose user started the pairing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Initiator {
    pub phase: IPhase,
    pub last: Option<i64>,
    pub ids: Ids,
}

impl Initiator {
    pub fn new(ids: Ids) -> Initiator {
        Initiator { phase: IPhase::Idle, last: None, ids }
    }
    fn idle(&self) -> Initiator {
        Initiator { phase: IPhase::Idle, ..self.clone() }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IEvent {
    /// The user chose Pair a machine: the app's fresh nonce and its static public key.
    Start { nonce: String, static_key: String, now: i64 },
    /// The second message was opened: the responder's nonce and static key, and the responder's device id from its hello.
    Nonce { nonce: String, peer_static: String, peer_id: Option<String>, now: i64 },
    User { yes: bool, now: i64 },
    Peer { yes: bool, now: i64 },
    Other,
}

pub fn initiator_step(m: &Initiator, ev: &IEvent) -> Out<Initiator> {
    let idle = m.idle();
    match ev {
        IEvent::Start { nonce, static_key, now } => {
            if !matches!(m.phase, IPhase::Idle) {
                return refuse(idle, Refusal::Unexpected);
            }
            let (Some(n), Some(s)) = (bytes::key32(nonce), bytes::key32(static_key)) else { return refuse(idle, Refusal::StartLength) };
            if !attempt_allowed(m.last, *now) {
                return refuse(idle, Refusal::AttemptTooSoon);
            }
            Out {
                send: vec![Say::Commit(bytes::hex(&commit_of(&n, &s)))],
                notify: Some(Notify::CommitSent),
                ..out(Initiator { phase: IPhase::Started { nonce: nonce.clone(), static_key: static_key.clone(), start: *now }, last: Some(*now), ids: m.ids.clone() })
            }
        }
        IEvent::Nonce { nonce, peer_static, peer_id, now } => {
            let (my_nonce, my_static, start) = match &m.phase {
                IPhase::Idle => return refuse(idle, Refusal::NoCommit), // the other side's nonce with no commitment of ours before it
                IPhase::Started { nonce, static_key, start } => (nonce, static_key, *start),
                IPhase::Coded { .. } => return refuse(idle, Refusal::NonceRepeated),
            };
            if !window_open(start, *now) {
                return refuse(idle, Refusal::RevealLate);
            }
            let (Some(rn), Some(rs)) = (bytes::key32(nonce), bytes::key32(peer_static)) else { return refuse(idle, Refusal::NonceLength) };
            if let Some(why) = peer_refusal(&m.ids, peer_id.as_deref(), peer_static, Refusal::NonceLength) {
                return refuse(idle, why);
            }
            let (Some(mn), Some(ms)) = (bytes::key32(my_nonce), bytes::key32(my_static)) else { return refuse(idle, Refusal::Unexpected) };
            let code = pairing_code(&mn, &rn, &ms, &rs);
            Out {
                send: vec![Say::Reveal(my_nonce.clone())],
                notify: Some(Notify::ShowCode),
                ..out(Initiator { phase: IPhase::Coded { start, code, answers: Answers::default() }, ..idle })
            }
        }
        IEvent::User { yes, now } | IEvent::Peer { yes, now } => {
            let IPhase::Coded { start, code, answers } = &m.phase else { return out(m.clone()) };
            let mine = matches!(ev, IEvent::User { .. });
            answer(*answers, *start, mine, *yes, *now, idle, |a| Initiator { phase: IPhase::Coded { start: *start, code: code.clone(), answers: a }, ..m.clone() })
        }
        IEvent::Other => out(m.clone()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link::testutil::{arr, fixture, name};
    use serde_json::{json, Map, Value};

    // ── JSON in and out, the fixtures' way ──

    fn s(v: &Value) -> String {
        v.as_str().unwrap().to_string()
    }

    fn ids_of(state: &Value) -> Ids {
        let own_id = match state.get("own_id") {
            None => OwnId::Absent,
            Some(Value::Null) => OwnId::Null,
            Some(v) => OwnId::Id(s(v)),
        };
        let paired = state.get("paired").map(|p| p.as_object().unwrap().iter().map(|(k, v)| (k.clone(), s(v))).collect());
        Ids { own_id, paired }
    }

    fn put_ids(o: &mut Map<String, Value>, ids: &Ids) {
        match &ids.own_id {
            OwnId::Absent => {}
            OwnId::Null => {
                o.insert("own_id".into(), Value::Null);
            }
            OwnId::Id(i) => {
                o.insert("own_id".into(), json!(i));
            }
        }
        if let Some(p) = &ids.paired {
            o.insert("paired".into(), Value::Object(p.iter().map(|(k, v)| (k.clone(), json!(v))).collect()));
        }
    }

    /// A field of an event that may be missing or not text: "" is not hex, and the machine refuses it by its length.
    fn t(v: &Value) -> String {
        v.as_str().unwrap_or("").to_string()
    }

    fn yes_of(v: &Value) -> bool {
        v == "yes"
    }

    fn answers_json(o: &mut Map<String, Value>, a: Answers) {
        o.insert("mine".into(), if a.mine { json!("yes") } else { Value::Null });
        o.insert("theirs".into(), if a.theirs { json!("yes") } else { Value::Null });
    }

    fn responder_of(v: &Value) -> Responder {
        let seen = v["seen"].as_array().unwrap().iter().map(|e| Seen { commit: s(&e["commit"]), at: e["at"].as_i64().unwrap() }).collect();
        let answers = Answers { mine: v["mine"] == "yes", theirs: v["theirs"] == "yes" };
        let phase = match v["s"].as_str().unwrap() {
            "idle" => RPhase::Idle,
            "committed" => RPhase::Committed { commit: s(&v["commit"]), start: v["start"].as_i64().unwrap(), nonce: s(&v["nonce"]) },
            "coded" => RPhase::Coded { start: v["start"].as_i64().unwrap(), code: s(&v["code"]), answers },
            other => panic!("state {other}"),
        };
        Responder { phase, seen, last: v["last"].as_i64(), ids: ids_of(v) }
    }

    fn responder_json(m: &Responder) -> Value {
        let mut o = Map::new();
        match &m.phase {
            RPhase::Idle => {
                o.insert("s".into(), json!("idle"));
            }
            RPhase::Committed { commit, start, nonce } => {
                o.insert("s".into(), json!("committed"));
                o.insert("commit".into(), json!(commit));
                o.insert("start".into(), json!(start));
                o.insert("nonce".into(), json!(nonce));
            }
            RPhase::Coded { start, code, answers } => {
                o.insert("s".into(), json!("coded"));
                o.insert("start".into(), json!(start));
                o.insert("code".into(), json!(code));
                answers_json(&mut o, *answers);
            }
        }
        o.insert("seen".into(), Value::Array(m.seen.iter().map(|e| json!({"commit": e.commit, "at": e.at})).collect()));
        o.insert("last".into(), json!(m.last));
        put_ids(&mut o, &m.ids);
        Value::Object(o)
    }

    fn initiator_of(v: &Value) -> Initiator {
        let answers = Answers { mine: v["mine"] == "yes", theirs: v["theirs"] == "yes" };
        let phase = match v["s"].as_str().unwrap() {
            "idle" => IPhase::Idle,
            "started" => IPhase::Started { nonce: s(&v["nonce"]), static_key: s(&v["static"]), start: v["start"].as_i64().unwrap() },
            "coded" => IPhase::Coded { start: v["start"].as_i64().unwrap(), code: s(&v["code"]), answers },
            other => panic!("state {other}"),
        };
        Initiator { phase, last: v["last"].as_i64(), ids: ids_of(v) }
    }

    fn initiator_json(m: &Initiator) -> Value {
        let mut o = Map::new();
        match &m.phase {
            IPhase::Idle => {
                o.insert("s".into(), json!("idle"));
            }
            IPhase::Started { nonce, static_key, start } => {
                o.insert("s".into(), json!("started"));
                o.insert("nonce".into(), json!(nonce));
                o.insert("static".into(), json!(static_key));
                o.insert("start".into(), json!(start));
            }
            IPhase::Coded { start, code, answers } => {
                o.insert("s".into(), json!("coded"));
                o.insert("start".into(), json!(start));
                o.insert("code".into(), json!(code));
                answers_json(&mut o, *answers);
            }
        }
        o.insert("last".into(), json!(m.last));
        put_ids(&mut o, &m.ids);
        Value::Object(o)
    }

    fn send_json(list: &[Say]) -> Value {
        Value::Array(
            list.iter()
                .map(|x| match x {
                    Say::Nonce(h) => json!({"nonce": h}),
                    Say::Commit(h) => json!({"commit": h}),
                    Say::Reveal(h) => json!({"reveal": h}),
                    Say::Pair(y) => json!({"pair": if *y { "yes" } else { "no" }}),
                })
                .collect(),
        )
    }

    fn out_json<S>(o: &Out<S>, state: Value) -> Value {
        json!({"state": state, "send": send_json(&o.send), "notify": o.notify.map(Notify::as_str), "because": o.because.map(Refusal::as_str)})
    }

    fn responder_event(e: &Value) -> REvent {
        let now = e["now"].as_i64().unwrap_or(0);
        if e.get("commit").is_some() {
            return REvent::Commit { commit: t(&e["commit"]), nonce: t(&e["nonce"]), now };
        }
        if let Some(r) = e.get("reveal") {
            let reveal = Reveal { nonce: t(&r["nonce"]), static_key: t(&r["static"]), own: t(&r["own"]), peer_id: r.get("peerId").and_then(Value::as_str).map(str::to_string) };
            return REvent::Reveal { reveal, now };
        }
        if let Some(u) = e.get("user") {
            return REvent::User { yes: yes_of(u), now };
        }
        if let Some(p) = e.get("peer") {
            return REvent::Peer { yes: yes_of(p), now };
        }
        REvent::Other
    }

    fn initiator_event(e: &Value) -> IEvent {
        let now = e["now"].as_i64().unwrap_or(0);
        if let Some(st) = e.get("start") {
            return IEvent::Start { nonce: t(&st["nonce"]), static_key: t(&st["static"]), now };
        }
        if e.get("nonce").is_some() {
            return IEvent::Nonce { nonce: t(&e["nonce"]), peer_static: t(&e["peerStatic"]), peer_id: e.get("peerId").and_then(Value::as_str).map(str::to_string), now };
        }
        if let Some(u) = e.get("user") {
            return IEvent::User { yes: yes_of(u), now };
        }
        if let Some(p) = e.get("peer") {
            return IEvent::Peer { yes: yes_of(p), now };
        }
        IEvent::Other
    }

    fn run_responder(state: &Value, ev: &Value) -> (Value, Value) {
        let o = responder_step(&responder_of(state), &responder_event(ev));
        let st = responder_json(&o.state);
        (out_json(&o, st.clone()), st)
    }

    fn run_initiator(state: &Value, ev: &Value) -> (Value, Value) {
        let o = initiator_step(&initiator_of(state), &initiator_event(ev));
        let st = initiator_json(&o.state);
        (out_json(&o, st.clone()), st)
    }

    // ── The tests ──

    #[test]
    fn the_numbers_are_the_fixtures() {
        let f = fixture("pairing-cases.json");
        assert_eq!(f["digits"], CODE_DIGITS);
        assert_eq!(f["commitLabel"].as_str().unwrap().as_bytes(), COMMIT_LABEL);
        assert_eq!(f["codeLabel"].as_str().unwrap().as_bytes(), CODE_LABEL);
        assert_eq!(f["gapMs"], GAP_MS);
        assert_eq!(f["windowMs"], WINDOW_MS);
        assert_eq!(f["offerTimeoutMs"], OFFER_TIMEOUT_MS);
    }

    #[test]
    fn commitments_and_codes() {
        let f = fixture("pairing-cases.json");
        for c in arr(&f, "commits") {
            let got = commit_of(&bytes::key32(c["nonce"].as_str().unwrap()).unwrap(), &bytes::key32(c["static"].as_str().unwrap()).unwrap());
            assert_eq!(bytes::hex(&got), c["commit"].as_str().unwrap(), "{}", name(c));
        }
        for c in arr(&f, "codes") {
            let k = |n: &str| bytes::key32(c[n].as_str().unwrap()).unwrap();
            assert_eq!(pairing_code(&k("nonceI"), &k("nonceR"), &k("staticI"), &k("staticR")), c["code"].as_str().unwrap(), "{}", name(c));
        }
        // Invalid inputs never get this far: the machines check the length first.
        for c in arr(&f, "invalid") {
            assert!(c["value"].as_str().map_or(true, |v| bytes::key32(v).is_none()), "{}", name(c));
        }
    }

    #[test]
    fn the_session_of_the_xx_vector_has_this_commitment_and_this_code() {
        let f = fixture("pairing-cases.json");
        let t = &f["session"];
        let k = |n: &str| bytes::key32(t[n].as_str().unwrap()).unwrap();
        assert_eq!(bytes::hex(&commit_of(&k("nonceI"), &k("staticI"))), t["commit"].as_str().unwrap());
        assert_eq!(pairing_code(&k("nonceI"), &k("nonceR"), &k("staticI"), &k("staticR")), t["code"].as_str().unwrap());
    }

    fn ms(v: &Value) -> i64 {
        v.as_i64().unwrap_or(-1) // text, true, null: not a time
    }

    #[test]
    fn the_three_clocks() {
        let f = fixture("pairing-cases.json");
        for c in arr(&f, "gapCases") {
            let last = if c["last"].is_null() { None } else { Some(ms(&c["last"])) };
            assert_eq!(attempt_allowed(last, ms(&c["now"])), c["out"].as_bool().unwrap(), "{}", name(c));
        }
        for c in arr(&f, "windowCases") {
            assert_eq!(window_open(ms(&c["start"]), ms(&c["now"])), c["out"].as_bool().unwrap(), "{}", name(c));
        }
        for c in arr(&f, "offerCases") {
            assert_eq!(offer_expired(ms(&c["offered"]), ms(&c["now"])), c["out"].as_bool().unwrap(), "{}", name(c));
        }
    }

    #[test]
    fn the_responder_row_by_row() {
        let f = fixture("pairing-cases.json");
        let rows = arr(&f, "responder");
        assert!(rows.len() >= 47);
        for c in rows {
            assert_eq!(run_responder(&c["state"], &c["event"]).0, c["out"], "{}", name(c));
        }
    }

    #[test]
    fn the_initiator_row_by_row() {
        let f = fixture("pairing-cases.json");
        let rows = arr(&f, "initiator");
        assert!(rows.len() >= 27);
        for c in rows {
            assert_eq!(run_initiator(&c["state"], &c["event"]).0, c["out"], "{}", name(c));
        }
    }

    #[test]
    fn whole_pairings_event_by_event() {
        let f = fixture("pairing-cases.json");
        for t in arr(&f, "machineTrips") {
            let mut state = t["from"].clone();
            let outs = t["out"].as_array().unwrap();
            for (i, e) in t["events"].as_array().unwrap().iter().enumerate() {
                let (got, next) = if t["side"] == "responder" { run_responder(&state, e) } else { run_initiator(&state, e) };
                assert_eq!(got, outs[i], "{} step {i}", name(t));
                state = next;
            }
        }
    }

    #[test]
    fn the_gate_opens_for_devices_and_for_two_minutes_after_a_click() {
        let mut g = Gate::default();
        assert!(!g.allows(Some(0)), "nothing open, no click");
        g.pair_clicked(1_000);
        assert!(g.allows(Some(1_000)), "open at the click");
        assert!(g.allows(Some(120_999)), "open 1 ms before 2 minutes");
        assert!(!g.allows(Some(121_000)), "closed at exactly 120 s");
        assert!(!g.allows(Some(500)), "a clock that went back");
        assert!(!g.allows(None), "no clock");
        g.devices_appeared();
        assert!(g.allows(None), "Devices open: any time");
        g.devices_appeared();
        g.devices_disappeared();
        assert!(g.allows(Some(900_000)), "two windows showed Devices, one closed");
        g.devices_disappeared();
        g.devices_disappeared();
        assert!(!g.allows(Some(900_000)), "closing more than was opened does not go below zero");
    }
}
```


**Create `windows/src-tauri/src/link/flow.rs`:**

```rust
// What each side of a transfer does with each frame (docs/LINK-CONTRACT.md, "What each side does with each frame"), and the three rules the app keeps around one connection: the machine's one
// transfer place, one machine-made decline per connection, and the first-frame clock. A port of `receiver_step`, `sender_step`, `place_step`, `receiver_connection_step` and
// `first_frame_expired` of tests/fixtures/link/reference.py, replayed against flow-cases.json. Pure: a state, one event, and the answer; no socket, no clock, no disk.
//
// Only a click (`User(Accept)`) starts a transfer. One transfer at a time on a connection; the app asks the machine's one transfer place (`Place`) before it lets an offer through.

use super::bytes::ID_LEN;
use super::frames::{Frame, DECLINE_BAD_OFFER, DECLINE_BUSY, DECLINE_TIMEOUT, DECLINE_TOO_LARGE, DECLINE_USER, SIZE_MAX};
use super::name::sanitize_name;

type Id = [u8; ID_LEN];

/// A transfer connection whose handshake is done must have an offer in hand within this long.
pub const FIRST_FRAME_MS: i64 = 10_000;
/// The machine-made declines one connection may send; the next one closes it.
pub const DECLINES_PER_CONNECTION: u32 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Notify {
    Offer,
    Expired,
    Withdrawn,
    Cancelled,
    Complete,
    Declined,
}

impl Notify {
    pub fn as_str(self) -> &'static str {
        match self {
            Notify::Offer => "offer",
            Notify::Expired => "expired",
            Notify::Withdrawn => "withdrawn",
            Notify::Cancelled => "cancelled",
            Notify::Complete => "complete",
            Notify::Declined => "declined",
        }
    }
}

/// Why a connection must close. After an abort the state is idle and nothing is saved as complete. `Declines` and `Idle` come from the connection rules.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Abort {
    Unexpected,
    Id,
    Order,
    Overflow,
    Short,
    Declines,
    Idle,
}

impl Abort {
    pub fn as_str(self) -> &'static str {
        match self {
            Abort::Unexpected => "unexpected",
            Abort::Id => "id",
            Abort::Order => "order",
            Abort::Overflow => "overflow",
            Abort::Short => "short",
            Abort::Declines => "declines",
            Abort::Idle => "idle",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Out<S> {
    pub state: S,
    pub send: Vec<Frame>,
    pub notify: Option<Notify>,
    pub abort: Option<Abort>,
}

fn out<S>(state: S, send: Vec<Frame>, notify: Option<Notify>, abort: Option<Abort>) -> Out<S> {
    Out { state, send, notify, abort }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum User {
    Accept,
    Decline,
    Cancel,
}

// ── The receiver ─────────────────────────────────────────────────────────────

/// `name` is the sanitized name, the one that is shown and saved.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RState {
    Idle,
    Offered { id: Id, size: u64, name: String },
    Receiving { id: Id, size: u64, got: u64 },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    Frame(Frame),
    User(User),
    Timeout,
}

fn decline(id: Id, reason: u8) -> Frame {
    Frame::Decline { id, reason }
}

pub fn receiver_step(state: &RState, ev: &Event) -> Out<RState> {
    use RState::*;
    match ev {
        Event::User(u) => match (state, u) {
            (Offered { id, size, .. }, User::Accept) => out(Receiving { id: *id, size: *size, got: 0 }, vec![Frame::Accept { id: *id }], None, None),
            (Offered { id, .. }, User::Decline) => out(Idle, vec![decline(*id, DECLINE_USER)], None, None),
            (Receiving { id, .. }, User::Cancel | User::Decline) => out(Idle, vec![Frame::Cancel { id: *id }], Some(Notify::Cancelled), None),
            _ => out(state.clone(), vec![], None, None),
        },
        Event::Timeout => match state {
            Offered { id, .. } => out(Idle, vec![decline(*id, DECLINE_TIMEOUT)], Some(Notify::Expired), None),
            _ => out(state.clone(), vec![], None, None),
        },
        Event::Frame(f) => {
            if f.is_pairing_answer() {
                return out(Idle, vec![], None, Some(Abort::Unexpected)); // a pairing answer has no place in a transfer
            }
            match f {
                Frame::Offer { id, size, name, .. } => {
                    if !matches!(state, Idle) {
                        return out(state.clone(), vec![decline(*id, DECLINE_BUSY)], None, None);
                    }
                    if *size > SIZE_MAX {
                        return out(Idle, vec![decline(*id, DECLINE_TOO_LARGE)], None, None);
                    }
                    match sanitize_name(name) {
                        Ok(saved) => out(Offered { id: *id, size: *size, name: saved }, vec![], Some(Notify::Offer), None),
                        Err(_) => out(Idle, vec![decline(*id, DECLINE_BAD_OFFER)], None, None),
                    }
                }
                Frame::Cancel { id } => match state {
                    Offered { id: mine, .. } if mine == id => out(Idle, vec![], Some(Notify::Withdrawn), None),
                    Receiving { id: mine, .. } if mine == id => out(Idle, vec![], Some(Notify::Cancelled), None),
                    _ => out(state.clone(), vec![], None, None), // a cancel for a transfer we do not know is harmless
                },
                Frame::Chunk { id, offset, data } => match state {
                    Receiving { id: mine, size, got } => {
                        if id != mine {
                            return out(Idle, vec![], None, Some(Abort::Id));
                        }
                        if offset != got {
                            return out(Idle, vec![], None, Some(Abort::Order)); // a replayed chunk or a skipped one
                        }
                        if got + data.len() as u64 > *size {
                            return out(Idle, vec![], None, Some(Abort::Overflow));
                        }
                        out(Receiving { id: *mine, size: *size, got: got + data.len() as u64 }, vec![], None, None)
                    }
                    _ => out(Idle, vec![], None, Some(Abort::Unexpected)),
                },
                Frame::Done { id } => match state {
                    Receiving { id: mine, size, got } => {
                        if id != mine {
                            return out(Idle, vec![], None, Some(Abort::Id));
                        }
                        if got != size {
                            return out(Idle, vec![], None, Some(Abort::Short));
                        }
                        out(Idle, vec![], Some(Notify::Complete), None)
                    }
                    _ => out(Idle, vec![], None, Some(Abort::Unexpected)),
                },
                _ => out(Idle, vec![], None, Some(Abort::Unexpected)),
            }
        }
    }
}

// ── The sender ───────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SState {
    Idle,
    Offered { id: Id },
    Sending { id: Id },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SEvent {
    Frame(Frame),
    UserCancel,
}

pub fn sender_step(state: &SState, ev: &SEvent) -> Out<SState> {
    use SState::*;
    let id = match state {
        Idle => None,
        Offered { id } | Sending { id } => Some(*id),
    };
    match ev {
        SEvent::UserCancel => match id {
            Some(id) => out(Idle, vec![Frame::Cancel { id }], Some(Notify::Cancelled), None),
            None => out(state.clone(), vec![], None, None),
        },
        SEvent::Frame(f) => {
            if id.is_none() && matches!(f, Frame::Cancel { .. }) {
                return out(state.clone(), vec![], None, None); // a cancel with no transfer running is ignored
            }
            let Some(mine) = id else { return out(Idle, vec![], None, Some(Abort::Unexpected)) };
            if matches!(f, Frame::Offer { .. } | Frame::Chunk { .. } | Frame::Done { .. }) || f.is_pairing_answer() {
                return out(Idle, vec![], None, Some(Abort::Unexpected));
            }
            if f.id() != Some(mine) {
                return out(Idle, vec![], None, Some(Abort::Id));
            }
            match (state, f) {
                (Offered { .. }, Frame::Accept { .. }) => out(Sending { id: mine }, vec![], None, None),
                (Offered { .. }, Frame::Decline { .. }) => out(Idle, vec![], Some(Notify::Declined), None),
                (_, Frame::Cancel { .. }) => out(Idle, vec![], Some(Notify::Cancelled), None),
                _ => out(Idle, vec![], None, Some(Abort::Unexpected)),
            }
        }
    }
}

// ── The rules around one connection ──────────────────────────────────────────

/// The first-frame clock: expired at exactly 10 s after the handshake. A clock that went back, or a value that is not a time (negative), counts as expired.
pub fn first_frame_expired(handshake_ms: i64, now_ms: i64) -> bool {
    !(handshake_ms >= 0 && now_ms >= 0 && (0..FIRST_FRAME_MS).contains(&(now_ms - handshake_ms)))
}

/// The machine's one transfer place, for every peer. `holder` is the id that holds it; `card` is true while a card with buttons is on the island.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Place {
    pub holder: Option<String>,
    pub card: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PlaceEvent {
    /// An offer asks for the place: granted only when nobody holds it and no card is up, and then the claimant holds it.
    Claim(String),
    /// The holder gives it back; another id changes nothing.
    Release(String),
    /// A card with buttons goes up or comes down.
    Card(bool),
}

/// (the new place, Some(granted) for a claim).
pub fn place_step(place: &Place, ev: &PlaceEvent) -> (Place, Option<bool>) {
    match ev {
        PlaceEvent::Claim(id) => {
            if place.holder.is_none() && !place.card {
                (Place { holder: Some(id.clone()), card: place.card }, Some(true))
            } else {
                (place.clone(), Some(false))
            }
        }
        PlaceEvent::Release(id) => (Place { holder: if place.holder.as_ref() == Some(id) { None } else { place.holder.clone() }, card: place.card }, None),
        PlaceEvent::Card(on) => (Place { holder: place.holder.clone(), card: *on }, None),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Conn {
    pub state: RState,
    /// The machine-made declines this connection has sent.
    pub declines: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConnEvent {
    /// A receiver event. An offer may carry `granted`, the place's answer to its claim (true when absent).
    Receiver { event: Event, granted: Option<bool> },
    /// The first-frame clock has run out.
    Silent,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConnOut {
    pub conn: Conn,
    pub send: Vec<Frame>,
    pub notify: Option<Notify>,
    pub abort: Option<Abort>,
}

fn machine_decline(f: &Frame) -> bool {
    matches!(f, Frame::Decline { reason, .. } if matches!(*reason, DECLINE_BUSY | DECLINE_TOO_LARGE | DECLINE_BAD_OFFER))
}

/// One connection of the receiver as the app runs it: `receiver_step` plus the rules above. An offer that comes while the connection is idle asks the place: a refused one is declined as
/// busy (2) and the state does not change. A machine-made decline sent for an offer counts; the second one is not sent, the connection is closed (`Declines`). The user's no and a timeout do
/// not count. A silent clock closes an idle connection (`Idle`); in any other state its report is stale and does nothing.
pub fn connection_step(conn: &Conn, ev: &ConnEvent) -> ConnOut {
    let keep = |conn: &Conn, send, notify, abort| ConnOut { conn: conn.clone(), send, notify, abort };
    match ev {
        ConnEvent::Silent => {
            if conn.state == RState::Idle {
                return keep(&Conn { state: RState::Idle, declines: conn.declines }, vec![], None, Some(Abort::Idle));
            }
            keep(conn, vec![], None, None)
        }
        ConnEvent::Receiver { event, granted } => {
            let offer = matches!(event, Event::Frame(Frame::Offer { .. }));
            let res = match event {
                Event::Frame(Frame::Offer { id, .. }) if conn.state == RState::Idle && !granted.unwrap_or(true) => out(conn.state.clone(), vec![decline(*id, DECLINE_BUSY)], None, None),
                _ => receiver_step(&conn.state, event),
            };
            let mut declines = conn.declines;
            if offer && res.send.iter().any(machine_decline) {
                if declines >= DECLINES_PER_CONNECTION {
                    return ConnOut { conn: Conn { state: RState::Idle, declines }, send: vec![], notify: None, abort: Some(Abort::Declines) };
                }
                declines += 1;
            }
            ConnOut { conn: Conn { state: res.state, declines }, send: res.send, notify: res.notify, abort: res.abort }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link::bytes;
    use crate::link::frames::tests::{frame_of, json_of};
    use crate::link::testutil::{arr, fixture, name};
    use serde_json::{json, Value};

    fn id_of(v: &Value) -> Id {
        bytes::id16(v.as_str().unwrap()).unwrap()
    }

    fn rstate_of(v: &Value) -> RState {
        match v["s"].as_str().unwrap() {
            "idle" => RState::Idle,
            "offered" => RState::Offered { id: id_of(&v["id"]), size: v["size"].as_u64().unwrap(), name: v["name"].as_str().unwrap().to_string() },
            "receiving" => RState::Receiving { id: id_of(&v["id"]), size: v["size"].as_u64().unwrap(), got: v["got"].as_u64().unwrap() },
            other => panic!("state {other}"),
        }
    }

    fn rstate_json(s: &RState) -> Value {
        match s {
            RState::Idle => json!({"s": "idle"}),
            RState::Offered { id, size, name } => json!({"s": "offered", "id": bytes::hex(id), "size": size, "name": name}),
            RState::Receiving { id, size, got } => json!({"s": "receiving", "id": bytes::hex(id), "size": size, "got": got}),
        }
    }

    fn sstate_of(v: &Value) -> SState {
        match v["s"].as_str().unwrap() {
            "idle" => SState::Idle,
            "offered" => SState::Offered { id: id_of(&v["id"]) },
            "sending" => SState::Sending { id: id_of(&v["id"]) },
            other => panic!("state {other}"),
        }
    }

    fn sstate_json(s: &SState) -> Value {
        match s {
            SState::Idle => json!({"s": "idle"}),
            SState::Offered { id } => json!({"s": "offered", "id": bytes::hex(id)}),
            SState::Sending { id } => json!({"s": "sending", "id": bytes::hex(id)}),
        }
    }

    fn event_of(e: &Value) -> Event {
        if let Some(f) = e.get("frame") {
            return Event::Frame(frame_of(f));
        }
        if let Some(u) = e.get("user") {
            return Event::User(match u.as_str().unwrap() {
                "accept" => User::Accept,
                "decline" => User::Decline,
                "cancel" => User::Cancel,
                other => panic!("user {other}"),
            });
        }
        assert!(e.get("timeout").is_some(), "event {e}");
        Event::Timeout
    }

    fn out_json<S>(o: &Out<S>, state: Value) -> Value {
        json!({"state": state, "send": o.send.iter().map(json_of).collect::<Vec<_>>(), "notify": o.notify.map(Notify::as_str), "abort": o.abort.map(Abort::as_str)})
    }

    fn run_receiver(state: &Value, ev: &Value) -> (Value, Value) {
        let o = receiver_step(&rstate_of(state), &event_of(ev));
        let st = rstate_json(&o.state);
        (out_json(&o, st.clone()), st)
    }

    fn run_sender(state: &Value, ev: &Value) -> (Value, Value) {
        let event = match (ev.get("frame"), ev.get("user")) {
            (Some(f), _) => SEvent::Frame(frame_of(f)),
            (_, Some(u)) => {
                assert_eq!(u, "cancel");
                SEvent::UserCancel
            }
            _ => panic!("event {ev}"),
        };
        let o = sender_step(&sstate_of(state), &event);
        let st = sstate_json(&o.state);
        (out_json(&o, st.clone()), st)
    }

    #[test]
    fn the_constants_are_the_fixtures() {
        let f = fixture("flow-cases.json");
        assert_eq!(f["chunkSize"], crate::link::frames::CHUNK_SIZE);
        assert_eq!(f["sizeMax"], SIZE_MAX);
        assert_eq!(f["firstFrameMs"], FIRST_FRAME_MS);
        assert_eq!(f["aborts"], json!(["unexpected", "id", "order", "overflow", "short"]));
    }

    #[test]
    fn the_receiver_and_the_sender_row_by_row() {
        let f = fixture("flow-cases.json");
        let (r, s) = (arr(&f, "receiver"), arr(&f, "sender"));
        assert!(r.len() >= 50 && s.len() >= 16);
        for c in r {
            assert_eq!(run_receiver(&c["state"], &c["event"]).0, c["out"], "receiver: {}", name(c));
        }
        for c in s {
            assert_eq!(run_sender(&c["state"], &c["event"]).0, c["out"], "sender: {}", name(c));
        }
    }

    #[test]
    fn whole_transfers_step_by_step() {
        let f = fixture("flow-cases.json");
        for t in arr(&f, "trips") {
            let mut state = t["from"].clone();
            let outs = t["out"].as_array().unwrap();
            for (i, e) in t["events"].as_array().unwrap().iter().enumerate() {
                let (got, next) = if t["side"] == "receiver" { run_receiver(&state, e) } else { run_sender(&state, e) };
                assert_eq!(got, outs[i], "{} step {i}", name(t));
                state = next;
            }
        }
    }

    #[test]
    fn the_machines_one_transfer_place() {
        let f = fixture("flow-cases.json");
        for t in arr(&f, "places") {
            let from = &t["from"];
            let mut place = Place { holder: from["holder"].as_str().map(str::to_string), card: from["card"].as_bool().unwrap() };
            let outs = t["out"].as_array().unwrap();
            for (i, e) in t["events"].as_array().unwrap().iter().enumerate() {
                let ev = if let Some(c) = e.get("claim") {
                    PlaceEvent::Claim(c.as_str().unwrap().to_string())
                } else if let Some(r) = e.get("release") {
                    PlaceEvent::Release(r.as_str().unwrap().to_string())
                } else {
                    PlaceEvent::Card(e["card"].as_bool().unwrap())
                };
                let (next, granted) = place_step(&place, &ev);
                place = next;
                let got = json!({"place": {"holder": place.holder, "card": place.card}, "granted": granted});
                assert_eq!(got, outs[i], "{} step {i}", name(t));
            }
        }
    }

    #[test]
    fn one_decline_per_connection_and_the_first_frame_clock() {
        let f = fixture("flow-cases.json");
        let rows = arr(&f, "connections");
        assert!(rows.len() >= 13);
        for t in rows {
            let from = &t["from"];
            let mut conn = Conn { state: rstate_of(&from["state"]), declines: from["declines"].as_u64().unwrap() as u32 };
            let outs = t["out"].as_array().unwrap();
            for (i, e) in t["events"].as_array().unwrap().iter().enumerate() {
                let ev = if e.get("silent").is_some() { ConnEvent::Silent } else { ConnEvent::Receiver { event: event_of(e), granted: e.get("granted").and_then(Value::as_bool) } };
                let o = connection_step(&conn, &ev);
                conn = o.conn.clone();
                let got = json!({"state": rstate_json(&conn.state), "declines": conn.declines, "send": o.send.iter().map(json_of).collect::<Vec<_>>(), "notify": o.notify.map(Notify::as_str), "abort": o.abort.map(Abort::as_str)});
                assert_eq!(got, outs[i], "{} step {i}", name(t));
            }
        }
        for c in arr(&f, "firstFrame") {
            let ms = |v: &Value| v.as_i64().unwrap_or(-1);
            assert_eq!(first_frame_expired(ms(&c["handshake"]), ms(&c["now"])), c["out"].as_bool().unwrap(), "{}", name(c));
        }
    }

    #[test]
    fn no_script_breaks_an_invariant() {
        // 3000 random scripts of events at one receiver: nothing panics, the count never passes the size, an abort lands in idle, only a click starts a transfer.
        let mut seed: u64 = 20261015;
        let mut next = |n: usize| {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            ((seed >> 33) as usize) % n
        };
        let ids = [[1u8; 16], [2u8; 16]];
        let names = ["a.txt", "../x", "CON", "a\0"];
        let sizes = [0u64, 5, 10, 1 << 32, (1 << 32) + 1];
        let offsets = [0u64, 2, 4, 6, 8, 10];
        for _ in 0..3000 {
            let mut state = RState::Idle;
            for _ in 0..1 + next(29) {
                let id = ids[next(2)];
                let ev = match next(6) {
                    0 => Event::Frame(Frame::Offer { id, size: sizes[next(5)], name: names[next(4)].to_string(), kind: String::new() }),
                    1 => Event::Frame(Frame::Chunk { id, offset: offsets[next(6)], data: vec![0xAB; 1 + next(4)] }),
                    2 => Event::Frame([Frame::Done { id }, Frame::Cancel { id }, Frame::Accept { id }][next(3)].clone()),
                    3 => Event::Frame(Frame::Decline { id, reason: 0 }),
                    4 => Event::User([User::Accept, User::Decline, User::Cancel][next(3)]),
                    _ => Event::Timeout,
                };
                let before = state.clone();
                let res = receiver_step(&state, &ev);
                state = res.state.clone();
                let started_by_click = !(matches!(state, RState::Receiving { .. }) && !matches!(before, RState::Receiving { .. })) || ev == Event::User(User::Accept);
                let overshoot = matches!(&state, RState::Receiving { size, got, .. } if got > size);
                assert!(!(res.abort.is_some() && state != RState::Idle) && !overshoot && started_by_click, "{before:?} {ev:?} -> {res:?}");
            }
        }
    }
}
```


- [ ] **Step 3: Run the tests**

Run:

```bash
windows/scripts/cargo-linux.sh test --target-dir /repo/windows/target/g2-tauri -p notchmeow link::pairing
windows/scripts/cargo-linux.sh test --target-dir /repo/windows/target/g2-tauri -p notchmeow link::flow
```

Expected: `test result: ok. 8 passed` (the commitments and the codes, the session of the `xx-link` vector, the three clocks' 29 boundary rows, the 47 responder rows, the 27 initiator rows, the five whole pairings, the gate's edges) and `test result: ok. 6 passed` (the 50 receiver rows and 16 sender rows, the nine whole transfers, **the seven `places[]` trips, the 13 `connections[]` trips and the 8 `firstFrame[]` rows**, and a 3000-script walk).

- [ ] **Step 4: Prove it bites**

Run:

```bash
M="python3 .claude/checkpoints/g2-tauri/mut.py rust"
$M windows/src-tauri/src/link/pairing.rs 'pub const GAP_MS: i64 = 30_000;' 'pub const GAP_MS: i64 = 29_000;' link::pairing
$M windows/src-tauri/src/link/flow.rs 'pub const DECLINES_PER_CONNECTION: u32 = 1;' 'pub const DECLINES_PER_CONNECTION: u32 = 2;' link::flow
$M windows/src-tauri/src/link/flow.rs 'pub const FIRST_FRAME_MS: i64 = 10_000;' 'pub const FIRST_FRAME_MS: i64 = 10_001;' link::flow
$M windows/src-tauri/src/link/pairing.rs 'if self.devices_open > 0' 'if true' link::pairing
```

Expected: the first `FAILED` (`the_three_clocks`, `the_numbers_are_the_fixtures`), the second `FAILED` (`one_decline_per_connection_and_the_first_frame_clock`), the third `FAILED` (`the_constants_are_the_fixtures` and the same test). The fourth is not a valid mutation (the gate keeps `devices_open` as a field: the helper stops with an assertion error that the text does not occur once): skip it. If you want the gate's proof, change `self.devices_open > 0 ||` to `false ||` in `Gate::allows` by the same helper and expect `the_gate_opens_for_devices_and_for_two_minutes_after_a_click` to fail.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current     # this session's worktree, and g2/tauri-link
git add windows/src-tauri/src/link/mod.rs windows/src-tauri/src/link/pairing.rs windows/src-tauri/src/link/flow.rs
git commit -F - <<'MSG'
feat(link): the pairing and transfer machines, the clocks, the gate and the connection rules, replayed against the contract (G2-tauri)

Commit-then-reveal pairing (commitment, six digits, the responder's and initiator's machines and their trips, the 30 s gap, the 2 minute window), the gate on incoming pairings, the receiver's and sender's machines and trips, and the three rules around one connection: the machine's one transfer place, one machine-made decline per connection and the 10 s first-frame clock (places[], connections[], firstFrame[]).

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Then write the task's line in the ledger: the commit, the test counts, the agent and the model.

---


### Task 5: The rules around the service: the card, the run gate, the transfer place, the caps, the clock

**Agent:** `nm-implementer-light` (Haiku 5.5, medium). The code is given in full.

**Files:**
- Create: `windows/src-tauri/src/link/cards.rs`
- Modify: `windows/src-tauri/src/link/mod.rs`

**Interfaces:**
- Consumes: nothing from the other link files (`libc` on Linux and the `windows` crate's `Win32_System_SystemInformation` feature, both already in `Cargo.toml`).
- Produces: `cards::{SETTLE_MS, Kind, Shown, offer_key, CardRules, RunGate, Ticket, Busy, ConnectionCaps, ReadLimit, now_ms}`. `CardRules` is the island's **one card slot** (a pairing code, an offer, progress and a result share it; an interactive card is never replaced by another flow's, a click inside 700 ms of a change or on a card that is gone does nothing, a flow that ends clears the card only if it is still its own). `RunGate` gives every conversation a ticket so that a late event from a stopped conversation is stale. `Busy` is the machine's one transfer place (`claim`, `reserve_card`; replayed against `places[]`). `ConnectionCaps` is 8 open and 2 per machine. `ReadLimit` is "read the paired machines again at most every 5 s". `now_ms()` is whole monotonic milliseconds that include sleep. These are the Mac's `LinkCardRules.swift` rules, case for case; the Mac's tests are the cases below.

- [ ] **Step 1: Register the module**

Run:

```bash
python3 - <<'EOF'
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")
edit("windows/src-tauri/src/link/mod.rs", "// MODULES: add new modules above this line", "pub mod cards;\n// MODULES: add new modules above this line")
EOF
```

- [ ] **Step 2: The file**

**Create `windows/src-tauri/src/link/cards.rs`:**

```rust
// The rules around the service, as plain values (sub-project G2): who holds the island's one link card and when a click may act on it, which conversation a late event belongs to, the
// machine's one transfer place, how many connections may be open, and how often the paired machines are read again. The Mac's twins are `LinkCardRules`, `LinkRunGate`, `LinkBusy`,
// `LinkConnectionCaps`, `LinkReadLimit` and `LinkClock` (NotchBuddy/Sources/App/LinkCardRules.swift); the cases below are the Mac's own test cases, ported. No clock is read in the rules:
// `now` is whole monotonic milliseconds, given by the caller (`now_ms`).

use std::collections::{HashMap, HashSet};
use std::sync::Mutex;

/// A click on a card that has only just changed kind is ignored for this long: a click aimed at the card that was there must not land on the button of the one that replaced it.
pub const SETTLE_MS: i64 = 700;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Pair,
    Offer,
    Receiving,
    Result,
}

impl Kind {
    /// A card with buttons the user is about to press (a result is only read, and may give way).
    pub fn interactive(self) -> bool {
        self != Kind::Result
    }
}

/// What the user was shown: the kind of card and a key for what it is about (the pairing code with the other machine's name, the offer key, the words of a result). The "answered" flag and
/// the progress are not part of it, so the user's own answer or a progress tick is not "another card".
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Shown {
    pub kind: Kind,
    pub key: String,
}

/// What identifies one offer: the machine and the id it chose. A transfer id alone is the other machine's own number, so two machines may use the same one.
pub fn offer_key(peer_id: &str, transfer_id: &str) -> String {
    format!("{peer_id}|{transfer_id}")
}

/// The service has a single card slot for pairing codes, offers, progress and results. What is on it is something the user is about to click: a pairing code or an offer from another machine
/// must never replace it (a click meant for "Accept" would land on another machine's "They match"), and a flow that ends must not wipe the card of another one.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CardRules {
    owner: Option<String>,
    shown: Option<Shown>,
    changed_at: i64,
}

impl CardRules {
    pub fn owner(&self) -> Option<&str> {
        self.owner.as_deref()
    }
    pub fn shown(&self) -> Option<&Shown> {
        self.shown.as_ref()
    }
    /// When the card last changed kind (or owner).
    pub fn changed_at(&self) -> i64 {
        self.changed_at
    }
    pub fn interactive(&self) -> bool {
        self.shown.as_ref().is_some_and(|s| s.kind.interactive())
    }

    /// A flow asks to put `card` on the island. False when another flow's card with buttons is up: nothing changes then, and the flow must not show anything.
    pub fn show(&mut self, card: Shown, owner: &str, now: i64) -> bool {
        if self.interactive() && self.owner.as_deref() != Some(owner) {
            return false;
        }
        if self.shown.as_ref().map(|s| s.kind) != Some(card.kind) || self.owner.as_deref() != Some(owner) {
            self.changed_at = now;
        }
        self.owner = Some(owner.to_string());
        self.shown = Some(card);
        true
    }

    /// A flow is over and has no card to leave: clears the card only if it is this flow's. False (and nothing changes) when the card belongs to another one.
    pub fn end(&mut self, owner: &str) -> bool {
        if self.owner.as_deref() != Some(owner) {
            return false;
        }
        self.owner = None;
        self.shown = None;
        true
    }

    /// May a click act now? `card` is the card the user saw when they clicked (None: the current one). False for a card that is no longer the one shown, and while the card is still settling.
    pub fn accepts(&self, card: Option<&Shown>, now: i64) -> bool {
        let Some(current) = &self.shown else { return false };
        if card.is_some_and(|c| c != current) {
            return false;
        }
        now - self.changed_at >= SETTLE_MS
    }
}

/// Which conversation a late event belongs to. Every hook a conversation gives the service reaches it through a task that may run after the conversation was cancelled, so the hook carries the
/// ticket its conversation was made under and the service acts only if that ticket is still the current one. A stop (Visible turned off) ends all of them at once, and a run that ended or was
/// replaced is stale as soon as another begins.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Ticket {
    pub generation: u64,
    pub serial: u64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RunGate {
    generation: u64,
    serial: u64,
    pair: Option<Ticket>,
    receive: Option<Ticket>,
}

impl RunGate {
    /// Counts the stops. Whatever awaits remembers the number it started under.
    pub fn generation(&self) -> u64 {
        self.generation
    }
    pub fn stop(&mut self) {
        self.generation += 1;
        self.pair = None;
        self.receive = None;
    }
    pub fn begin_pair(&mut self) -> Ticket {
        let t = self.next();
        self.pair = Some(t);
        t
    }
    pub fn begin_receive(&mut self) -> Ticket {
        let t = self.next();
        self.receive = Some(t);
        t
    }
    fn next(&mut self) -> Ticket {
        self.serial += 1;
        Ticket { generation: self.generation, serial: self.serial }
    }
    pub fn end_pair(&mut self) {
        self.pair = None;
    }
    pub fn end_receive(&mut self) {
        self.receive = None;
    }
    pub fn is_pair(&self, t: Ticket) -> bool {
        self.pair == Some(t) && t.generation == self.generation
    }
    pub fn is_receive(&self, t: Ticket) -> bool {
        self.receive == Some(t) && t.generation == self.generation
    }
}

/// Who may take the island's card, decided where the transfer's own task can ask without leaving it (so the answer is exact when the offer arrives, not when the service gets to it). It is
/// the contract's `place_step` with a lock: one transfer for the whole machine.
#[derive(Debug, Default)]
pub struct Busy {
    inner: Mutex<BusyInner>,
}

#[derive(Debug, Default)]
struct BusyInner {
    peers: HashSet<String>,
    card_locked: bool,
}

impl Busy {
    /// False when a transfer is already claimed (by any machine: the island has one card), or a card with buttons is on the island (the offer is then declined as busy, and no card is shown).
    pub fn claim(&self, id: &str) -> bool {
        let mut g = self.inner.lock().unwrap();
        if g.card_locked || !g.peers.is_empty() {
            return false;
        }
        g.peers.insert(id.to_string())
    }
    pub fn release(&self, id: &str) {
        self.inner.lock().unwrap().peers.remove(id);
    }
    /// This peer's offer holds the machine's one transfer place: an Accept click for an offer whose run has ended is not for it.
    pub fn holds(&self, id: &str) -> bool {
        self.inner.lock().unwrap().peers.contains(id)
    }
    pub fn set_card_locked(&self, on: bool) {
        self.inner.lock().unwrap().card_locked = on;
    }
    /// A pairing code is about to take the card. False when an offer has been claimed and has not got its card yet (the pairing is ended instead; nothing is shown for it). Otherwise the card
    /// is locked at once, so an offer that arrives next is declined as busy at its claim, not after it passed.
    pub fn reserve_card(&self) -> bool {
        let mut g = self.inner.lock().unwrap();
        if !g.peers.is_empty() {
            return false;
        }
        g.card_locked = true;
        true
    }
}

/// How many connections may be established at once (their handshake done): 8 in all and 2 for one machine, so a machine that holds connections open and says nothing cannot take every
/// descriptor or crowd the other machines out. Connections that have not finished their handshake are bounded by the listener's own pending cap and its 10 seconds.
#[derive(Debug, Default)]
pub struct ConnectionCaps {
    owners: Mutex<HashMap<u64, String>>,
}

impl ConnectionCaps {
    pub const TOTAL: usize = 8;
    pub const PER_PEER: usize = 2;

    /// True when the connection `id` of `peer` may go on (and is counted from now until `release`).
    pub fn admit(&self, id: u64, peer: &str) -> bool {
        let mut g = self.owners.lock().unwrap();
        if g.contains_key(&id) {
            return true;
        }
        if g.len() >= Self::TOTAL || g.values().filter(|p| p.as_str() == peer).count() >= Self::PER_PEER {
            return false;
        }
        g.insert(id, peer.to_string());
        true
    }
    pub fn release(&self, id: u64) {
        self.owners.lock().unwrap().remove(&id);
    }
    pub fn count(&self) -> usize {
        self.owners.lock().unwrap().len()
    }
}

/// How often the paired machines are read from the credential store on a miss (an id this machine does not know) or by choice: once in 5 s, so a peer that sends ids that are not paired cannot
/// make the machine read the store in a loop, and a read that failed for a moment is tried again soon.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ReadLimit {
    last: Option<i64>,
}

impl ReadLimit {
    pub const GAP_MS: i64 = 5_000;
    pub fn due(&self, now: i64) -> bool {
        self.last.map_or(true, |l| now - l >= Self::GAP_MS)
    }
    /// A read happened (whoever asked for it).
    pub fn read(&mut self, now: i64) {
        self.last = Some(now);
    }
}

/// The link's whole-millisecond clock: monotonic, and it keeps counting while the machine sleeps, as a window that was measured by it and one that was slept for should end together.
/// Only differences mean anything. Linux: `CLOCK_BOOTTIME`. Windows: `GetTickCount64`, which includes sleep (the unbiased interrupt time does not).
pub fn now_ms() -> i64 {
    #[cfg(target_os = "linux")]
    {
        let mut ts = libc::timespec { tv_sec: 0, tv_nsec: 0 };
        // SAFETY: `ts` is a valid timespec and CLOCK_BOOTTIME exists on every Linux this app supports.
        unsafe { libc::clock_gettime(libc::CLOCK_BOOTTIME, &mut ts) };
        ts.tv_sec as i64 * 1000 + ts.tv_nsec as i64 / 1_000_000
    }
    #[cfg(windows)]
    {
        // SAFETY: no arguments, no pointer.
        unsafe { windows::Win32::System::SystemInformation::GetTickCount64() as i64 }
    }
    #[cfg(not(any(target_os = "linux", windows)))]
    {
        use std::sync::OnceLock;
        use std::time::Instant;
        static START: OnceLock<Instant> = OnceLock::new();
        START.get_or_init(Instant::now).elapsed().as_millis() as i64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn shown(kind: Kind, key: &str) -> Shown {
        Shown { kind, key: key.to_string() }
    }

    #[test]
    fn nothing_on_the_island() {
        let r = CardRules::default();
        assert!(!r.interactive() && !r.accepts(None, 100_000) && !r.accepts(Some(&shown(Kind::Pair, "483291|Desk PC")), 100_000));
    }

    #[test]
    fn a_card_in_front_of_the_user_is_never_replaced_by_another_flows() {
        let (pair, other_pair, offer, result) = (shown(Kind::Pair, "483291|Desk PC"), shown(Kind::Pair, "111111|Old laptop"), shown(Kind::Offer, "t1"), shown(Kind::Result, "Paired|This PC and Desk PC"));
        let mut r = CardRules::default();
        assert!(r.show(pair.clone(), "pair:A", 1_000) && r.interactive());
        assert!(!r.show(other_pair, "pair:B", 2_000) && r.shown() == Some(&pair) && r.owner() == Some("pair:A"));
        assert!(!r.show(offer.clone(), "transfer:t1", 2_000) && r.shown() == Some(&pair));
        assert!(!r.show(result, "pair:B", 2_000) && r.shown() == Some(&pair));

        let mut r = CardRules::default();
        r.show(offer.clone(), "transfer:t1", 1_000);
        assert!(!r.show(pair, "pair:A", 5_000));
        assert!(!r.show(shown(Kind::Offer, "t2"), "transfer:t2", 5_000));
        assert_eq!(r.shown(), Some(&offer));
        let receiving = shown(Kind::Receiving, "t1");
        assert!(r.show(receiving.clone(), "transfer:t1", 9_000) && r.shown() == Some(&receiving));
        assert_eq!(r.changed_at(), 9_000, "a change of kind");
    }

    #[test]
    fn a_card_that_is_over_gives_way() {
        let mut r = CardRules::default();
        r.show(shown(Kind::Result, "Paired|x"), "pair:A", 1_000);
        assert!(!r.interactive());
        let offer = shown(Kind::Offer, "t1");
        assert!(r.show(offer.clone(), "transfer:t1", 2_000) && r.shown() == Some(&offer));
        assert_eq!(r.changed_at(), 2_000);
    }

    #[test]
    fn a_flow_that_ends_changes_the_card_only_if_it_is_still_its_own() {
        let pair = shown(Kind::Pair, "483291|Desk PC");
        let mut r = CardRules::default();
        r.show(pair.clone(), "pair:A", 1_000);
        assert!(!r.end("transfer:t1") && r.shown() == Some(&pair));
        assert!(r.end("pair:A") && r.shown().is_none() && !r.interactive());
        let result = shown(Kind::Result, "Paired|x");
        let mut r = CardRules::default();
        r.show(shown(Kind::Offer, "t1"), "transfer:t1", 1_000);
        assert!(!r.show(result.clone(), "pair:A", 2_000), "another flow's result does not overwrite the offer");
        assert!(r.show(result.clone(), "transfer:t1", 3_000) && r.shown() == Some(&result), "its own result does");
    }

    #[test]
    fn a_click() {
        let (pair, other_pair, offer, result) = (shown(Kind::Pair, "483291|Desk PC"), shown(Kind::Pair, "111111|Old laptop"), shown(Kind::Offer, "t1"), shown(Kind::Result, "Paired|x"));
        let mut r = CardRules::default();
        r.show(pair.clone(), "pair:A", 10_000);
        assert_eq!([r.accepts(Some(&pair), 10_000), r.accepts(Some(&pair), 10_699), r.accepts(Some(&pair), 10_700)], [false, false, true], "700 ms of quiet");
        assert_eq!([r.accepts(Some(&other_pair), 50_000), r.accepts(Some(&offer), 50_000), r.accepts(Some(&result), 50_000)], [false; 3]);
        assert_eq!([r.accepts(None, 10_100), r.accepts(None, 20_000)], [false, true], "without an identity: the current card once it has settled");
        r.show(pair.clone(), "pair:A", 30_000);
        assert!(r.accepts(Some(&pair), 30_000), "the user's own answer (same card, same kind) does not start a new quiet period");
        r.show(result.clone(), "pair:A", 40_000);
        assert_eq!([r.accepts(Some(&result), 40_300), r.accepts(Some(&result), 40_700), r.accepts(Some(&pair), 41_000)], [false, true, false]);
    }

    #[test]
    fn an_offer_is_identified_by_the_machine_and_the_transfer_id_together() {
        let (desk, laptop) = (offer_key("d1", "t1"), offer_key("l1", "t1"));
        assert_ne!(desk, laptop);
        assert_eq!(desk, offer_key("d1", "t1"));
        let (desk_offer, laptop_offer) = (shown(Kind::Offer, &desk), shown(Kind::Offer, &laptop));
        let mut r = CardRules::default();
        r.show(desk_offer.clone(), &format!("transfer:{desk}"), 1_000);
        assert!(!r.accepts(Some(&laptop_offer), 9_000));
        assert!(!r.show(laptop_offer, &format!("transfer:{laptop}"), 9_000));
        assert!(r.accepts(Some(&desk_offer), 9_000));
    }

    #[test]
    fn a_late_event_from_a_stopped_conversation_is_stale() {
        let mut g = RunGate::default();
        let first = g.begin_receive();
        assert!(g.is_receive(first) && !g.is_pair(first));
        g.stop();
        assert!(!g.is_receive(first) && g.generation() == 1);
        let second = g.begin_receive();
        assert!(second != first && g.is_receive(second) && !g.is_receive(first));
        g.end_receive();
        assert!(!g.is_receive(second), "ending the run makes its ticket stale at once");
        let third = g.begin_receive();
        assert!(!g.is_receive(second) && g.is_receive(third));
        let pair = g.begin_pair();
        g.stop();
        assert!(!g.is_pair(pair));
        let again = g.begin_pair();
        g.end_pair();
        assert!(!g.is_pair(again));
    }

    #[test]
    fn a_second_offer_is_declined_as_busy_before_any_card_can_be_taken_from_it() {
        let b = Busy::default();
        assert_eq!([b.claim("d1"), b.claim("d1")], [true, false]);
        assert!(!b.reserve_card(), "a pairing code cannot take the card while an offer is claimed and has none yet");
        assert!(b.holds("d1"));
        b.release("d1");
        assert!(!b.holds("d1"));
        assert_eq!([b.reserve_card(), b.claim("d2")], [true, false], "a pairing code reserves the card; an offer that arrives next is refused at the claim");
        b.set_card_locked(false);
        assert!(b.claim("d2"));
        let one = Busy::default();
        assert_eq!([one.claim("d1"), one.claim("d2")], [true, false]);
        one.release("d1");
        assert!(one.claim("d2"), "one transfer for the whole machine, then the next");
    }

    /// The contract's `places[]` (docs/LINK-CONTRACT.md, "One transfer for the whole machine") through the real `Busy`: its answers are the table's.
    #[test]
    fn busy_gives_the_contracts_answers_for_the_machines_one_transfer_place() {
        use crate::link::testutil::{arr, fixture, name};
        let f = fixture("flow-cases.json");
        for t in arr(&f, "places") {
            let busy = Busy::default();
            if let Some(h) = t["from"]["holder"].as_str() {
                assert!(busy.claim(h));
            }
            busy.set_card_locked(t["from"]["card"].as_bool().unwrap());
            for (i, e) in t["events"].as_array().unwrap().iter().enumerate() {
                let want = &t["out"][i];
                let granted = if let Some(c) = e.get("claim") {
                    Some(busy.claim(c.as_str().unwrap()))
                } else if let Some(r) = e.get("release") {
                    busy.release(r.as_str().unwrap());
                    None
                } else {
                    busy.set_card_locked(e["card"].as_bool().unwrap());
                    None
                };
                assert_eq!(granted, want["granted"].as_bool(), "{} step {i}", name(t));
                let holder = want["place"]["holder"].as_str();
                assert_eq!(holder.is_some_and(|h| busy.holds(h)), holder.is_some(), "{} step {i}: the holder", name(t));
            }
        }
    }

    #[test]
    fn how_many_connections_may_be_established() {
        let caps = ConnectionCaps::default();
        assert_eq!([caps.admit(0, "d1"), caps.admit(1, "d1"), caps.admit(2, "d1")], [true, true, false], "a machine gets 2, not 3");
        assert!(caps.admit(0, "d1") && caps.count() == 2, "asking again for a counted connection changes nothing");
        for (i, p) in [(3, "d2"), (4, "d2"), (5, "d3"), (6, "d3"), (7, "d4"), (8, "d4")] {
            assert!(caps.admit(i, p));
        }
        assert_eq!(caps.count(), 8);
        assert!(!caps.admit(99, "d5"), "the ninth is refused, whoever it is");
        caps.release(0);
        assert_eq!([caps.admit(100, "d1"), caps.admit(101, "d5")], [true, false]);
    }

    #[test]
    fn the_paired_map_is_read_again_but_not_in_a_loop() {
        let mut limit = ReadLimit::default();
        assert!(limit.due(1_000));
        limit.read(1_000);
        assert_eq!([limit.due(1_000), limit.due(5_999), limit.due(6_000)], [false, false, true]);
        limit.read(6_000);
        assert_eq!([limit.due(10_999), limit.due(11_000)], [false, true]);
    }

    #[test]
    fn the_clock_moves_in_whole_milliseconds() {
        let t0 = now_ms();
        std::thread::sleep(std::time::Duration::from_millis(250));
        let dt = now_ms() - t0;
        assert!((250..450).contains(&dt), "250 ms of sleep read as {dt}");
    }
}
```


- [ ] **Step 3: Run the tests**

Run: `windows/scripts/cargo-linux.sh test --target-dir /repo/windows/target/g2-tauri -p notchmeow link::cards`

Expected: `test result: ok. 12 passed` (the click and the 700 ms settle, an interactive card is never replaced, a card that is over gives way, a flow that ends clears only its own card, an offer is the machine and the id together, a late event from a stopped conversation is stale, the paired map is read again at most every 5 s, a second offer is declined as busy before a card can be taken from it, the connection caps, the clock in whole milliseconds, and `busy_gives_the_contracts_answers_for_the_machines_one_transfer_place`, which replays the seven `places[]` trips of `flow-cases.json` through the real `Busy`).

- [ ] **Step 4: Prove it bites**

Run:

```bash
M="python3 .claude/checkpoints/g2-tauri/mut.py rust"
$M windows/src-tauri/src/link/cards.rs 'pub const SETTLE_MS: i64 = 700;' 'pub const SETTLE_MS: i64 = 600;' link::cards
$M windows/src-tauri/src/link/cards.rs 'pub const TOTAL: usize = 8;' 'pub const TOTAL: usize = 9;' link::cards
$M windows/src-tauri/src/link/cards.rs 'pub const GAP_MS: i64 = 5_000;' 'pub const GAP_MS: i64 = 4_000;' link::cards
```

Expected: each ends in `FAILED` for at least one of the tests above.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/src-tauri/src/link/mod.rs windows/src-tauri/src/link/cards.rs
git commit -F - <<'MSG'
feat(link): the island's one card, the run gate, the machine's one transfer place, the caps and the clock (G2-tauri)

Ports of the Mac's LinkCardRules, LinkRunGate, LinkBusy, LinkConnectionCaps, LinkReadLimit and LinkClock, case for case; Busy is also replayed against places[] of the contract.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Write the task's line in the ledger.

---

### Task 6: The credential store, the settings and the list of machines

**Agent:** `nm-implementer` (Haiku 5.5, high). The code is given in full; the judgment is in reading the tests when `keyring` behaves differently on one OS.

**Files:**
- Create: `windows/src-tauri/src/link/identity.rs`, `keystore.rs`, `settings.rs`, `directory.rs`
- Modify: `windows/src-tauri/src/link/mod.rs`

**Interfaces:**
- Consumes: `bytes` (`hex`, `is_id_hex`, `is_key_hex`, `ID_LEN`), `frames::{device_name, DEVICE_NAME_MAX, Advert}`, `name::{is_bad_category, is_invisible, is_space}`, `noise::public_of`.
- Produces: `identity::{Identity, Peer}`; `keystore::{SERVICE, Lookup, SecretStore, MemoryStore, SystemStore, Keystore, KeyError, StoreError}` (`Keystore::{identity, peers, add_peer, remove_peer, static_key}`); `settings::{LinkSettings, clean, load, save, valid_name, default_name, host_name, is_true}`; `directory::{RowState, Row, rows}`.

**Where the secrets live, and what a failure means.** The static key (32 bytes), the device id (16) and each paired machine's name and public key go in the operating system's credential store through `keyring` (Windows Credential Manager, Linux Secret Service), under the service name `io.github.aikusan.notchmeow` (a Debug build uses `...notchmeow.debug`, so the owner's own build cannot read or damage the release's items). `keyring` **cannot list** items, so one item, `link.peers`, holds the ids of the paired machines and `link.peer.<id>` holds each machine. The store answers a read in three ways (`Lookup::{Found, Absent, Failed}`): **only `Absent` may lead to a new secret being made**. A read that fails (no Secret Service running, a locked store, a refused prompt, an item that will not decode) is reported as `KeyError::Unreadable` and nothing is made, nothing is written to a file and the link stays off with a sentence for Settings → Devices (Task 13 shows it). An empty `link.peers` list where machines were known is suspect and a damaged item fails the read; a failed write keeps what was there and says so. No secret appears in an error or in a `Debug` print (a test pins it). `link.json` (Visible, the device name) holds no secret and is written by Rust alone.

- [ ] **Step 1: Register the modules**

Run:

```bash
python3 - <<'EOF'
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")
edit("windows/src-tauri/src/link/mod.rs", "// MODULES: add new modules above this line", "pub mod directory;\npub mod identity;\npub mod keystore;\npub mod settings;\n// MODULES: add new modules above this line")
EOF
```

- [ ] **Step 2: The files**

**Create `windows/src-tauri/src/link/identity.rs`:**

```rust
// Who this machine is and who it has paired with (sub-project G2). The static private key and the device id come from the credential store (`keystore.rs`); a conversation is given them as an
// `Identity`, and the machines it has paired with as `Peer`s.

/// This machine, as a conversation sees it. `key` is the static private key: it never reaches a log, a file or the page (`Debug` hides it).
#[derive(Clone)]
pub struct Identity {
    /// 32 lower-case hex digits, never all zero.
    pub device_id: String,
    /// What the other machine's card shows (`frames::device_name` accepts it).
    pub name: String,
    pub key: [u8; 32],
    pub public: [u8; 32],
}

impl std::fmt::Debug for Identity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Identity").field("device_id", &self.device_id).field("name", &self.name).field("key", &"(hidden)").finish()
    }
}

/// A machine this one has paired with: its device id, the name it gave (authenticated, from its hello), its static public key (64 lower-case hex digits) and when it was paired (seconds).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Peer {
    pub id: String,
    pub name: String,
    pub key: String,
    pub at: i64,
}
```


**Create `windows/src-tauri/src/link/keystore.rs`:**

```rust
// The link's secrets (sub-project G2): this machine's static private key, its device id, and one item for each machine it has paired. They live in the operating system's credential store
// (the Windows Credential Manager, or on Linux the Secret Service: GNOME Keyring, KWallet) and nowhere else: never in a file, a setting, a log or a fixture (docs/LINK-CONTRACT.md "Notes
// for ports"). The account names are frozen like the pill IDs:
//   `link.static-key`   {"k": private key, "p": public key}, 64 lower-case hex digits each
//   `link.device-id`    this machine's random device id, 32 lower-case hex digits, never all zero
//   `link.peers`        the ids of the paired machines, a JSON list (the credential stores cannot list their items, so this list is the index)
//   `link.peer.<id>`    {"n": name, "k": public key, "t": seconds} for each paired machine
// `Keystore` takes the store it reads and writes, so the tests run it on a memory store.
//
// A read that fails is an error and never a fresh secret: only an item that is **absent** may lead to a new key or device id, so a locked or missing credential store can never replace
// the key and lose every pairing. **Without a Secret Service on Linux** (no GNOME Keyring or KWallet running) every read fails, the link says so in Settings → Devices and stays off; it
// does not fall back to a file. A debug build keeps all of it under a service name of its own, so a dev run can never touch the real pairings.

use std::collections::BTreeMap;
use std::sync::Mutex;

use serde_json::{json, Value};

use super::bytes::{self, hex, is_id_hex, is_key_hex, ID_LEN};
use super::frames::device_name;
use super::identity::Peer;
use super::noise;

/// The credential store's service name.
pub const SERVICE: &str = if cfg!(debug_assertions) { "io.github.aikusan.notchmeow.debug" } else { "io.github.aikusan.notchmeow" };

pub const ACCOUNT_KEY: &str = "link.static-key";
pub const ACCOUNT_ID: &str = "link.device-id";
pub const ACCOUNT_PEERS: &str = "link.peers";
const PEER_PREFIX: &str = "link.peer.";

/// What a store says about one item: there, not there, or not readable. Only `Absent` may lead to a new secret being made.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Lookup {
    Absent,
    Found(String),
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StoreError;

pub trait SecretStore: Send + Sync {
    fn get(&self, account: &str) -> Lookup;
    /// Writes the item, replacing what is there. Never deletes first: a failed write leaves the old item.
    fn put(&self, account: &str, value: &str) -> Result<(), StoreError>;
    /// Removes the item; an item that is not there is not an error.
    fn delete(&self, account: &str) -> Result<(), StoreError>;
}

/// A store in memory, for the tests: nothing here touches the credential store.
#[derive(Default)]
pub struct MemoryStore {
    items: Mutex<BTreeMap<String, String>>,
    pub fail_reads: std::sync::atomic::AtomicBool,
    pub fail_writes: std::sync::atomic::AtomicBool,
}

impl SecretStore for MemoryStore {
    fn get(&self, account: &str) -> Lookup {
        if self.fail_reads.load(std::sync::atomic::Ordering::SeqCst) {
            return Lookup::Failed;
        }
        self.items.lock().unwrap().get(account).map_or(Lookup::Absent, |v| Lookup::Found(v.clone()))
    }
    fn put(&self, account: &str, value: &str) -> Result<(), StoreError> {
        if self.fail_writes.load(std::sync::atomic::Ordering::SeqCst) {
            return Err(StoreError);
        }
        self.items.lock().unwrap().insert(account.to_string(), value.to_string());
        Ok(())
    }
    fn delete(&self, account: &str) -> Result<(), StoreError> {
        self.items.lock().unwrap().remove(account);
        Ok(())
    }
}

impl MemoryStore {
    pub fn accounts(&self) -> Vec<String> {
        self.items.lock().unwrap().keys().cloned().collect()
    }
}

/// The real credential store (the `keyring` crate: Windows Credential Manager, Linux Secret Service).
#[cfg(any(windows, target_os = "linux"))]
pub struct SystemStore {
    service: String,
}

#[cfg(any(windows, target_os = "linux"))]
impl SystemStore {
    pub fn new() -> SystemStore {
        SystemStore { service: SERVICE.to_string() }
    }
    /// A store under another service name (the opt-in real-store test uses one made for its run).
    pub fn with_service(service: &str) -> SystemStore {
        SystemStore { service: service.to_string() }
    }
}

#[cfg(any(windows, target_os = "linux"))]
impl Default for SystemStore {
    fn default() -> SystemStore {
        SystemStore::new()
    }
}

/// What a `keyring` error means for a read: no such item is `Absent`, anything else (no Secret Service, a locked store, a refused prompt, an item that will not decode) is `Failed`.
#[cfg(any(windows, target_os = "linux"))]
pub fn lookup_of(result: Result<String, keyring::Error>) -> Lookup {
    match result {
        Ok(v) => Lookup::Found(v),
        Err(keyring::Error::NoEntry) => Lookup::Absent,
        Err(_) => Lookup::Failed,
    }
}

#[cfg(any(windows, target_os = "linux"))]
impl SecretStore for SystemStore {
    fn get(&self, account: &str) -> Lookup {
        match keyring::Entry::new(&self.service, account) {
            Ok(e) => lookup_of(e.get_password()),
            Err(_) => Lookup::Failed,
        }
    }
    fn put(&self, account: &str, value: &str) -> Result<(), StoreError> {
        keyring::Entry::new(&self.service, account).and_then(|e| e.set_password(value)).map_err(|_| StoreError)
    }
    fn delete(&self, account: &str) -> Result<(), StoreError> {
        match keyring::Entry::new(&self.service, account).map(|e| e.delete_credential()) {
            Ok(Ok(())) | Ok(Err(keyring::Error::NoEntry)) => Ok(()),
            _ => Err(StoreError),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KeyError {
    /// The store could not be read (locked, no Secret Service, a refused prompt). Nothing is replaced.
    Unreadable,
    /// An item is there and is not what it should be. It is never replaced; the user is told.
    Corrupt(String),
    /// The store would not take a write.
    Write,
    /// A map that came back empty where machines were known: a locked store lists nothing, so the last good map is kept.
    Suspect,
    /// A pairing that must not be stored: the id is this machine's own, not an id, or paired under another key.
    Refused(&'static str),
}

impl std::fmt::Display for KeyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            KeyError::Unreadable => f.write_str("the credential store could not be read"),
            KeyError::Corrupt(what) => write!(f, "an item of the credential store is damaged: {what}"),
            KeyError::Write => f.write_str("the credential store would not take a write"),
            KeyError::Suspect => f.write_str("the credential store listed nothing where machines were known"),
            KeyError::Refused(why) => write!(f, "refused: {why}"),
        }
    }
}

impl std::error::Error for KeyError {}

pub struct Keystore<S: SecretStore> {
    store: S,
    /// One writer at a time: the first use of a secret and a change to the paired machines are read-then-write. (One instance of the app runs; the single-instance plugin sees to that.)
    turn: Mutex<()>,
}

fn random<const N: usize>() -> Option<[u8; N]> {
    let mut b = [0u8; N];
    getrandom::getrandom(&mut b).ok()?;
    Some(b)
}

impl<S: SecretStore> Keystore<S> {
    pub fn new(store: S) -> Keystore<S> {
        Keystore { store, turn: Mutex::new(()) }
    }

    pub fn store(&self) -> &S {
        &self.store
    }

    /// This machine's device id. Made on first use (the item is absent), never when the read failed.
    pub fn device_id(&self) -> Result<String, KeyError> {
        let _turn = self.turn.lock().unwrap();
        match self.store.get(ACCOUNT_ID) {
            Lookup::Found(v) if is_id_hex(&v) && v != "0".repeat(2 * ID_LEN) => Ok(v),
            Lookup::Found(_) => Err(KeyError::Corrupt(ACCOUNT_ID.into())),
            Lookup::Failed => Err(KeyError::Unreadable),
            Lookup::Absent => {
                let id = hex(&random::<ID_LEN>().ok_or(KeyError::Write)?);
                if id == "0".repeat(2 * ID_LEN) {
                    return Err(KeyError::Write);
                }
                self.store.put(ACCOUNT_ID, &id).map_err(|_| KeyError::Write)?;
                Ok(id)
            }
        }
    }

    /// The static key pair (private, public). Made on first use, never when the read failed; an item whose public half is not the private half's is damaged.
    pub fn static_key(&self) -> Result<([u8; 32], [u8; 32]), KeyError> {
        let _turn = self.turn.lock().unwrap();
        match self.store.get(ACCOUNT_KEY) {
            Lookup::Found(v) => {
                let corrupt = || KeyError::Corrupt(ACCOUNT_KEY.into());
                let j: Value = serde_json::from_str(&v).map_err(|_| corrupt())?;
                let (k, p) = (bytes::key32(j["k"].as_str().unwrap_or("")).ok_or_else(corrupt)?, bytes::key32(j["p"].as_str().unwrap_or("")).ok_or_else(corrupt)?);
                if noise::public_of(&k).map_err(|_| corrupt())? != p {
                    return Err(corrupt());
                }
                Ok((k, p))
            }
            Lookup::Failed => Err(KeyError::Unreadable),
            Lookup::Absent => {
                let (k, p) = noise::generate_static().map_err(|_| KeyError::Write)?;
                self.store.put(ACCOUNT_KEY, &json!({"k": hex(&k), "p": hex(&p)}).to_string()).map_err(|_| KeyError::Write)?;
                Ok((k, p))
            }
        }
    }

    fn index(&self) -> Result<Vec<String>, KeyError> {
        match self.store.get(ACCOUNT_PEERS) {
            Lookup::Absent => Ok(vec![]),
            Lookup::Failed => Err(KeyError::Unreadable),
            Lookup::Found(v) => {
                let list: Vec<String> = serde_json::from_str(&v).map_err(|_| KeyError::Corrupt(ACCOUNT_PEERS.into()))?;
                if list.iter().any(|i| !is_id_hex(i)) {
                    return Err(KeyError::Corrupt(ACCOUNT_PEERS.into()));
                }
                Ok(list)
            }
        }
    }

    fn peer(&self, id: &str) -> Result<Peer, KeyError> {
        let account = format!("{PEER_PREFIX}{id}");
        let corrupt = || KeyError::Corrupt(account.clone());
        match self.store.get(&account) {
            Lookup::Failed => Err(KeyError::Unreadable),
            Lookup::Absent => Err(corrupt()),
            Lookup::Found(v) => {
                let j: Value = serde_json::from_str(&v).map_err(|_| corrupt())?;
                let name = device_name(j["n"].as_str().ok_or_else(corrupt)?.as_bytes()).map_err(|_| corrupt())?;
                let key = j["k"].as_str().filter(|k| is_key_hex(k)).ok_or_else(corrupt)?.to_string();
                Ok(Peer { id: id.to_string(), name, key, at: j["t"].as_i64().unwrap_or(0) })
            }
        }
    }

    /// The paired machines, by id. A machine with an item that will not read is an error for the whole map (the caller keeps its last good one); `expecting_some` says the caller knew
    /// machines before, and a map that comes back empty then is `Suspect` (a locked store lists nothing).
    pub fn paired_machines(&self, expecting_some: bool) -> Result<BTreeMap<String, Peer>, KeyError> {
        let _turn = self.turn.lock().unwrap();
        self.read_all(expecting_some)
    }

    fn read_all(&self, expecting_some: bool) -> Result<BTreeMap<String, Peer>, KeyError> {
        let ids = self.index()?;
        let mut map = BTreeMap::new();
        for id in ids {
            map.insert(id.clone(), self.peer(&id)?);
        }
        if expecting_some && map.is_empty() {
            return Err(KeyError::Suspect);
        }
        Ok(map)
    }

    /// Stores a machine that both users said "They match" to. The paired map is read again here, at the moment of storing (two pairings can overlap for up to two minutes): an id that is this
    /// machine's own, or that is paired under another key, is refused; the same id under the same key updates its name.
    pub fn add(&self, peer: &Peer, own_id: &str) -> Result<(), KeyError> {
        let _turn = self.turn.lock().unwrap();
        if !is_id_hex(&peer.id) || peer.id == "0".repeat(2 * ID_LEN) {
            return Err(KeyError::Refused("device-id"));
        }
        if peer.id == own_id {
            return Err(KeyError::Refused("own-id"));
        }
        if !is_key_hex(&peer.key) || device_name(peer.name.as_bytes()).is_err() {
            return Err(KeyError::Refused("peer"));
        }
        let mut ids = self.index()?;
        if ids.contains(&peer.id) {
            if self.peer(&peer.id)?.key != peer.key {
                return Err(KeyError::Refused("id-key-mismatch"));
            }
        } else {
            ids.push(peer.id.clone());
        }
        // The item first, then the index: a crash between the two leaves an item nobody lists, never a listed machine without its key.
        self.store.put(&format!("{PEER_PREFIX}{}", peer.id), &json!({"n": peer.name, "k": peer.key, "t": peer.at}).to_string()).map_err(|_| KeyError::Write)?;
        self.store.put(ACCOUNT_PEERS, &serde_json::to_string(&ids).unwrap()).map_err(|_| KeyError::Write)
    }

    /// Forgets a machine: out of the index first (so it is no longer trusted), then its item goes.
    pub fn forget(&self, id: &str) -> Result<(), KeyError> {
        let _turn = self.turn.lock().unwrap();
        let mut ids = self.index()?;
        ids.retain(|i| i != id);
        self.store.put(ACCOUNT_PEERS, &serde_json::to_string(&ids).unwrap()).map_err(|_| KeyError::Write)?;
        self.store.delete(&format!("{PEER_PREFIX}{id}")).map_err(|_| KeyError::Write)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::Ordering;

    fn ks() -> Keystore<MemoryStore> {
        Keystore::new(MemoryStore::default())
    }

    fn peer(tag: u8, key: u8) -> Peer {
        Peer { id: hex(&[tag; 16]), name: format!("Machine {tag}"), key: hex(&[key; 32]), at: 1_700_000_000 }
    }

    #[test]
    fn the_service_name_of_a_debug_build_is_its_own() {
        assert_eq!(SERVICE, if cfg!(debug_assertions) { "io.github.aikusan.notchmeow.debug" } else { "io.github.aikusan.notchmeow" });
    }

    #[test]
    fn the_device_id_is_made_once_and_kept() {
        let k = ks();
        let id = k.device_id().unwrap();
        assert!(is_id_hex(&id) && id != "0".repeat(32));
        assert_eq!(k.device_id().unwrap(), id);
    }

    #[test]
    fn the_static_key_is_made_once_and_its_public_half_is_checked() {
        let k = ks();
        let (a, pa) = k.static_key().unwrap();
        let (b, pb) = k.static_key().unwrap();
        assert_eq!((a, pa), (b, pb));
        assert_eq!(noise::public_of(&a).unwrap(), pa);
        k.store().put(ACCOUNT_KEY, &json!({"k": hex(&a), "p": hex(&[1u8; 32])}).to_string()).unwrap();
        assert_eq!(k.static_key().unwrap_err(), KeyError::Corrupt(ACCOUNT_KEY.into()), "a key whose public half does not match is damaged, not replaced");
        assert!(matches!(k.store().get(ACCOUNT_KEY), Lookup::Found(v) if v.contains(&hex(&[1u8; 32]))), "and it is still there");
    }

    #[test]
    fn a_failed_read_never_makes_a_fresh_key_or_id() {
        let k = ks();
        let (_, pub1) = k.static_key().unwrap();
        let id = k.device_id().unwrap();
        k.store().fail_reads.store(true, Ordering::SeqCst);
        assert_eq!(k.static_key().unwrap_err(), KeyError::Unreadable);
        assert_eq!(k.device_id().unwrap_err(), KeyError::Unreadable);
        k.store().fail_reads.store(false, Ordering::SeqCst);
        assert_eq!(k.static_key().unwrap().1, pub1, "the key is the one that was there");
        assert_eq!(k.device_id().unwrap(), id);
        assert!(k.paired_machines(false).is_ok());
    }

    #[test]
    fn a_damaged_device_id_is_reported_and_not_replaced() {
        let k = ks();
        k.store().put(ACCOUNT_ID, "not an id").unwrap();
        assert_eq!(k.device_id().unwrap_err(), KeyError::Corrupt(ACCOUNT_ID.into()));
        k.store().put(ACCOUNT_ID, &"0".repeat(32)).unwrap();
        assert_eq!(k.device_id().unwrap_err(), KeyError::Corrupt(ACCOUNT_ID.into()));
    }

    #[test]
    fn a_pairing_is_stored_listed_and_forgotten() {
        let k = ks();
        let own = hex(&[9u8; 16]);
        k.add(&peer(1, 1), &own).unwrap();
        k.add(&peer(2, 2), &own).unwrap();
        let map = k.paired_machines(false).unwrap();
        assert_eq!(map.len(), 2);
        assert_eq!(map[&hex(&[1u8; 16])], peer(1, 1));
        k.forget(&hex(&[1u8; 16])).unwrap();
        assert_eq!(k.paired_machines(true).unwrap().keys().collect::<Vec<_>>(), vec![&hex(&[2u8; 16])]);
        assert!(!k.store().accounts().contains(&format!("link.peer.{}", hex(&[1u8; 16]))), "its item is gone");
    }

    #[test]
    fn the_same_machine_again_updates_its_name_and_another_key_is_refused() {
        let k = ks();
        let own = hex(&[9u8; 16]);
        k.add(&peer(1, 1), &own).unwrap();
        let mut renamed = peer(1, 1);
        renamed.name = "New name".into();
        k.add(&renamed, &own).unwrap();
        assert_eq!(k.paired_machines(false).unwrap()[&hex(&[1u8; 16])].name, "New name");
        assert_eq!(k.add(&peer(1, 7), &own).unwrap_err(), KeyError::Refused("id-key-mismatch"), "the user removes the device first to re-pair");
        assert_eq!(k.paired_machines(false).unwrap()[&hex(&[1u8; 16])].key, hex(&[1u8; 32]));
    }

    #[test]
    fn this_machines_own_id_and_bad_peers_are_refused() {
        let k = ks();
        let own = hex(&[9u8; 16]);
        assert_eq!(k.add(&peer(9, 1), &own).unwrap_err(), KeyError::Refused("own-id"));
        let mut zero = peer(1, 1);
        zero.id = "0".repeat(32);
        assert_eq!(k.add(&zero, &own).unwrap_err(), KeyError::Refused("device-id"));
        let mut bad_key = peer(1, 1);
        bad_key.key = "AB".repeat(32);
        assert_eq!(k.add(&bad_key, &own).unwrap_err(), KeyError::Refused("peer"));
        let mut bad_name = peer(1, 1);
        bad_name.name = " padded ".into();
        assert_eq!(k.add(&bad_name, &own).unwrap_err(), KeyError::Refused("peer"));
        assert!(k.paired_machines(false).unwrap().is_empty());
    }

    #[test]
    fn an_empty_list_where_machines_were_known_is_suspect_and_a_damaged_item_fails_the_read() {
        let k = ks();
        let own = hex(&[9u8; 16]);
        k.add(&peer(1, 1), &own).unwrap();
        k.store().put(ACCOUNT_PEERS, "[]").unwrap();
        assert_eq!(k.paired_machines(true).unwrap_err(), KeyError::Suspect);
        assert!(k.paired_machines(false).unwrap().is_empty());
        k.store().put(ACCOUNT_PEERS, &format!("[\"{}\"]", hex(&[1u8; 16]))).unwrap();
        k.store().put(&format!("link.peer.{}", hex(&[1u8; 16])), "{\"n\":\"x\"}").unwrap();
        assert!(matches!(k.paired_machines(false).unwrap_err(), KeyError::Corrupt(_)));
        // An index that names a machine whose item is gone is damaged too.
        k.store().delete(&format!("link.peer.{}", hex(&[1u8; 16]))).unwrap();
        assert!(matches!(k.paired_machines(false).unwrap_err(), KeyError::Corrupt(_)));
    }

    #[test]
    fn a_failed_write_keeps_what_was_there_and_says_so() {
        let k = ks();
        let own = hex(&[9u8; 16]);
        k.add(&peer(1, 1), &own).unwrap();
        k.store().fail_writes.store(true, Ordering::SeqCst);
        assert_eq!(k.add(&peer(2, 2), &own).unwrap_err(), KeyError::Write);
        assert_eq!(k.forget(&hex(&[1u8; 16])).unwrap_err(), KeyError::Write);
        k.store().fail_writes.store(false, Ordering::SeqCst);
        assert_eq!(k.paired_machines(false).unwrap().len(), 1);
    }

    #[test]
    fn no_secret_appears_in_an_error_or_a_debug_print() {
        let k = ks();
        let (private, _) = k.static_key().unwrap();
        for e in [KeyError::Unreadable, KeyError::Corrupt("link.static-key".into()), KeyError::Write, KeyError::Suspect, KeyError::Refused("own-id")] {
            assert!(!format!("{e} {e:?}").contains(&hex(&private)));
        }
    }
}
```


**Create `windows/src-tauri/src/link/settings.rs`:**

```rust
// What the link saves and how it is cleaned (sub-project G2): whether this machine is visible on the network, and the name the other machines show for it. Two values in `link.json` in the
// app's data folder, written by Rust alone (the page never saves them, so a settings save from the page can never drop them): `visible` (a boolean, **off until the user turns it on** in
// Settings → Devices: until then there is no listener, no advert and no firewall prompt) and `deviceName` (text). Secrets are not here: the keys and the paired machines are in the credential
// store (`keystore.rs`). The Mac's twin is LinkSettings.swift (`link.visible` and `link.deviceName` in UserDefaults).

use std::path::Path;

use serde_json::{json, Value};

use super::frames::{device_name, DEVICE_NAME_MAX};
use super::name::{is_bad_category, is_invisible, is_space};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LinkSettings {
    pub visible: bool,
    pub device_name: String,
}

/// `true` only for the boolean true: the number 1 and the text "true" are off (a settings file can be hand-edited).
pub fn is_true(v: Option<&Value>) -> bool {
    matches!(v, Some(Value::Bool(true)))
}

/// A name that the other machine's card would accept (`frames::device_name`: 1 to 63 bytes, no control, format or invisible character, no space at either end), or None.
pub fn valid_name(v: Option<&Value>) -> Option<String> {
    device_name(v?.as_str()?.as_bytes()).ok()
}

/// The name offered by default, from the computer's own name ("Desk PC"): the characters a card would refuse are dropped, the ends trimmed, the rest cut to 63 bytes at a character.
/// A name with nothing left is "Computer".
pub fn default_name(host: &str) -> String {
    let kept: Vec<char> = host.chars().filter(|&c| !is_bad_category(c) && !is_invisible(c)).collect();
    let (mut start, mut end) = (0, kept.len());
    while start < end && is_space(kept[start]) {
        start += 1;
    }
    while end > start && is_space(kept[end - 1]) {
        end -= 1;
    }
    let (mut out, mut bytes) = (String::new(), 0);
    for &c in &kept[start..end] {
        if bytes + c.len_utf8() > DEVICE_NAME_MAX {
            break;
        }
        out.push(c);
        bytes += c.len_utf8();
    }
    let out = out.trim_end_matches(is_space).to_string();
    if out.is_empty() { "Computer".to_string() } else { out }
}

/// Everything stored, cleaned: visible only when exactly `true`, the name when it passes `valid_name`, else the default from `host`. Never fails.
pub fn clean(raw: &Value, host: &str) -> LinkSettings {
    LinkSettings { visible: is_true(raw.get("visible")), device_name: valid_name(raw.get("deviceName")).unwrap_or_else(|| default_name(host)) }
}

pub fn load(path: &Path, host: &str) -> LinkSettings {
    let raw = std::fs::read(path).ok().and_then(|b| serde_json::from_slice::<Value>(&b).ok()).unwrap_or(Value::Null);
    clean(&raw, host)
}

/// Writes the file whole through a temporary one, so a crash leaves the old file or the new one, never half of one.
pub fn save(path: &Path, s: &LinkSettings) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, serde_json::to_vec_pretty(&json!({"visible": s.visible, "deviceName": s.device_name}))?)?;
    std::fs::rename(&tmp, path)
}

/// This computer's name, for the default device name only. Windows: `COMPUTERNAME`. Linux: the kernel's hostname. It is read at launch for that one purpose and nowhere else
/// (`scripts/link-tests/privacy.test.mjs` pins that no other file of the link reads it, and the pictures never do).
pub fn host_name() -> String {
    #[cfg(windows)]
    {
        std::env::var("COMPUTERNAME").unwrap_or_default()
    }
    #[cfg(not(windows))]
    {
        std::fs::read_to_string("/proc/sys/kernel/hostname").or_else(|_| std::fs::read_to_string("/etc/hostname")).unwrap_or_default().trim().to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(tag: &str) -> std::path::PathBuf {
        static N: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let dir = std::env::temp_dir().join(format!("notchmeow-linkset-{tag}-{}-{}", std::process::id(), N.fetch_add(1, std::sync::atomic::Ordering::Relaxed)));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn visible_is_off_unless_it_is_exactly_true() {
        for v in [json!(null), json!(1), json!("true"), json!([true]), json!({}), json!(0)] {
            assert!(!clean(&json!({"visible": v}), "Desk PC").visible, "{v}");
        }
        assert!(!clean(&json!({}), "Desk PC").visible && !clean(&Value::Null, "Desk PC").visible, "off by default");
        assert!(clean(&json!({"visible": true}), "Desk PC").visible);
    }

    #[test]
    fn a_stored_name_is_kept_when_a_card_would_accept_it_and_replaced_by_the_default_when_not() {
        assert_eq!(clean(&json!({"deviceName": "Studio PC"}), "Desk PC").device_name, "Studio PC");
        for bad in [json!(""), json!(" padded"), json!("a\nb"), json!("a\u{202e}b"), json!("x".repeat(64)), json!(7), json!(null)] {
            assert_eq!(clean(&json!({"deviceName": bad}), "Desk PC").device_name, "Desk PC", "{bad}");
        }
        assert_eq!(clean(&json!({"deviceName": "x".repeat(63)}), "Desk PC").device_name.len(), 63);
    }

    #[test]
    fn the_default_name_is_the_computers_cleaned() {
        assert_eq!(default_name("Desk PC"), "Desk PC");
        assert_eq!(default_name("  Sam's MacBook Pro  "), "Sam's MacBook Pro");
        assert_eq!(default_name("Desk\u{202e}PC\n"), "DeskPC");
        assert_eq!(default_name(""), "Computer");
        assert_eq!(default_name("\u{200b}\u{200b}"), "Computer");
        let long = default_name(&"é".repeat(60));
        assert!(long.len() <= 63 && long.chars().all(|c| c == 'é') && long.len() == 62, "cut at a character, not in the middle of one: {} bytes", long.len());
        assert!(device_name(default_name("a  ").as_bytes()).is_ok());
    }

    #[test]
    fn what_is_saved_is_what_is_loaded_and_a_damaged_file_is_the_default() {
        let dir = temp("save");
        let path = dir.join("link.json");
        assert_eq!(load(&path, "Desk PC"), LinkSettings { visible: false, device_name: "Desk PC".into() });
        let s = LinkSettings { visible: true, device_name: "Studio PC".into() };
        save(&path, &s).unwrap();
        assert_eq!(load(&path, "Desk PC"), s);
        std::fs::write(&path, "{ not json").unwrap();
        assert_eq!(load(&path, "Desk PC"), LinkSettings { visible: false, device_name: "Desk PC".into() });
        assert!(!dir.join("link.json.tmp").exists());
    }
}
```


**Create `windows/src-tauri/src/link/directory.rs`:**

```rust
// What Settings → Devices lists and what the shelf's "To a device" offers: the machines seen on the network and the machines paired, merged. Pure, so the order and the states are tested.
// The Mac's twin is `LinkDirectory` (LinkSettings.swift).

use std::collections::{BTreeMap, HashMap};

use super::frames::Advert;
use super::identity::Peer;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RowState {
    /// Paired, and its advert is on the network now.
    PairedOnline,
    /// Paired, not seen.
    PairedOffline,
    /// Seen, not paired.
    Available,
}

impl RowState {
    pub fn as_str(self) -> &'static str {
        match self {
            RowState::PairedOnline => "pairedOnline",
            RowState::PairedOffline => "pairedOffline",
            RowState::Available => "available",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Row {
    pub id: String,
    pub name: String,
    pub state: RowState,
}

fn by_name(a: &Row, b: &Row) -> std::cmp::Ordering {
    a.name.to_lowercase().cmp(&b.name.to_lowercase()).then_with(|| a.name.cmp(&b.name))
}

/// Paired machines that are online first (a paired machine's name is the authenticated one it gave when it paired, not the advert's), then the paired that are not, then the machines only seen,
/// each group by name. An advert with this machine's own id is never listed (`parse_txt` refuses it already; this is the second line).
pub fn rows(adverts: &[Advert], peers: &BTreeMap<String, Peer>, own_id: &str) -> Vec<Row> {
    let seen: HashMap<&str, &Advert> = adverts.iter().filter(|a| a.id != own_id).map(|a| (a.id.as_str(), a)).collect();
    let mut online = vec![];
    let mut offline = vec![];
    for p in peers.values() {
        let state = if seen.contains_key(p.id.as_str()) { RowState::PairedOnline } else { RowState::PairedOffline };
        let row = Row { id: p.id.clone(), name: p.name.clone(), state };
        if state == RowState::PairedOnline { online.push(row) } else { offline.push(row) }
    }
    let mut others: Vec<Row> = seen.values().filter(|a| !peers.contains_key(&a.id)).map(|a| Row { id: a.id.clone(), name: a.name.clone(), state: RowState::Available }).collect();
    online.sort_by(by_name);
    offline.sort_by(by_name);
    others.sort_by(by_name);
    online.into_iter().chain(offline).chain(others).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ad(id: &str, name: &str) -> Advert {
        Advert { id: id.repeat(32), name: name.into() }
    }

    fn peer(id: &str, name: &str) -> (String, Peer) {
        (id.repeat(32), Peer { id: id.repeat(32), name: name.into(), key: "ab".repeat(32), at: 0 })
    }

    #[test]
    fn paired_online_then_paired_offline_then_the_others_each_by_name() {
        let peers: BTreeMap<String, Peer> = [peer("1", "Zed laptop"), peer("2", "Alpha PC"), peer("3", "Mid tower")].into_iter().collect();
        let adverts = [ad("1", "zed (advert name)"), ad("4", "Beta"), ad("5", "alpha two"), ad("3", "Mid")];
        let got: Vec<(String, RowState)> = rows(&adverts, &peers, &"f".repeat(32)).into_iter().map(|r| (r.name, r.state)).collect();
        assert_eq!(
            got,
            vec![
                ("Mid tower".into(), RowState::PairedOnline),
                ("Zed laptop".into(), RowState::PairedOnline),
                ("Alpha PC".into(), RowState::PairedOffline),
                ("alpha two".into(), RowState::Available),
                ("Beta".into(), RowState::Available),
            ],
            "a paired machine keeps the name it gave when it paired, not the advert's"
        );
    }

    #[test]
    fn this_machines_own_advert_is_never_listed() {
        let own = "e".repeat(32);
        let got = rows(&[ad("e", "Me"), ad("a", "Other")], &BTreeMap::new(), &own);
        assert_eq!(got.len(), 1);
        assert_eq!(got[0].name, "Other");
    }

    #[test]
    fn two_adverts_with_one_id_make_one_row() {
        let got = rows(&[ad("a", "First"), ad("a", "Second")], &BTreeMap::new(), &"f".repeat(32));
        assert_eq!(got.len(), 1);
    }
}
```


- [ ] **Step 3: Run the tests**

Run:

```bash
windows/scripts/cargo-linux.sh test --target-dir /repo/windows/target/g2-tauri -p notchmeow link::keystore
windows/scripts/cargo-linux.sh test --target-dir /repo/windows/target/g2-tauri -p notchmeow link::settings
windows/scripts/cargo-linux.sh test --target-dir /repo/windows/target/g2-tauri -p notchmeow link::directory
```

Expected: `11 passed` (the Review Focus 4 test is `a_failed_read_never_makes_a_fresh_key_or_id`: a store whose reads fail returns `Unreadable` and leaves the store with **no** item and the device with no id), `4 passed` and `3 passed`. In the Linux container no Secret Service runs, so `SystemStore` is only compiled here, never exercised: the check of the real store is the owner's (Task 16, checks 3 and 10).

- [ ] **Step 4: Prove it bites**

Run:

```bash
M="python3 .claude/checkpoints/g2-tauri/mut.py rust"
$M windows/src-tauri/src/link/keystore.rs 'map_or(Lookup::Absent, |v| Lookup::Found(v.clone()))' 'map_or(Lookup::Failed, |v| Lookup::Found(v.clone()))' link::keystore
$M windows/src-tauri/src/link/keystore.rs 'return Lookup::Failed;' 'return Lookup::Absent;' link::keystore
```

Expected: both `FAILED`; the second one is the Review Focus 4 test: a failing store must never read as an empty one.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/src-tauri/src/link/mod.rs windows/src-tauri/src/link/identity.rs windows/src-tauri/src/link/keystore.rs windows/src-tauri/src/link/settings.rs windows/src-tauri/src/link/directory.rs
git commit -F - <<'MSG'
feat(link): the credential store, link.json and the list of machines (G2-tauri)

The static key, the device id and the paired machines live in the OS credential store through keyring (an index item, because keyring cannot list): only an absent item may lead to a new secret, a failed read never does. link.json holds Visible and the device name; the directory merges adverts with the paired machines.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Write the task's line in the ledger.

---

### Task 7: The files: the sink, the source, the Downloads folder, the mark of the web

**Agent:** `nm-implementer` (Haiku 5.5, high). The code is given in full. If a Windows-only compile problem shows up in Task 15's Windows check, it goes to `nm-implementer-deep`.

**Files:**
- Create: `windows/src-tauri/src/link/files.rs`
- Modify: `windows/src-tauri/src/link/mod.rs`

**Interfaces:**
- Consumes: `frames::{RAW_NAME_MAX, SIZE_MAX}`, `name::unique_name`.
- Produces: `files::{Sink, SinkError, Source, SourceError, default_folder, parse_user_dirs, MARK_BY_HAND}`. `Sink::new(folder, wanted_name, mark)` then `open() -> Result<PathBuf, SinkError>` makes the file **exclusively** (`create_new`; a name the volume says is taken is numbered by `unique_name` and tried again, nothing is overwritten; a wanted name that is a path is refused by the sink itself), never follows a link (Linux: `O_NOFOLLOW`), writes it private (0600); `write(&[u8])`; `finish() -> Result<PathBuf, SinkError>` makes it ordinary (0644) and syncs it; `discard()` deletes only the file this sink made (an identity check on the device and inode, so a file the user moved away is not confused with another that took its name) and does nothing after a successful `finish`; dropping a sink that did not finish discards it. With `mark` set (Windows: `MARK_BY_HAND`), `open` writes the `Zone.Identifier` alternate stream (`ZoneId=3`), the twin of the Mac's quarantine attribute, **before** a byte is written, and never opens the file afterwards. `Source::open(path)` is a regular file only (a FIFO or a folder is `NotAFile`; Linux opens with `O_NONBLOCK`), `read(count)`, `close()`, and carries `path`, `name`, `size`, `kind`.

**What the mark of the web does and does not do.** Windows asks "Do you want to open this file?" for a file with `ZoneId=3` in its `Zone.Identifier` stream, and SmartScreen looks at it. If the stream cannot be written (a drive that is not NTFS), the file is **not** handed out looking trusted: `open` fails closed with `SinkError::Mark` (the empty file is deleted and the transfer ends as "Could not save"), which is the owner's default for open question 3. Linux has no such mark; the folder is the only separation (`Downloads/NotchMeow/`). A received file is **never opened** by NotchMeow.

- [ ] **Step 1: Register the module**

Run:

```bash
python3 - <<'EOF'
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")
edit("windows/src-tauri/src/link/mod.rs", "// MODULES: add new modules above this line", "pub mod files;\n// MODULES: add new modules above this line")
EOF
```

- [ ] **Step 2: The file**

**Create `windows/src-tauri/src/link/files.rs`:**

```rust
// Files on the link (sub-project G2): where a received file is written and how, and how a file is read to be sent. The Mac's twin is LinkFiles.swift.
//
// Receiving. The folder is `Downloads/NotchMeow/`. The name is the sanitized one (`name.rs`), made free with `unique_name` and then **created exclusively** (`create_new`: `O_EXCL` on Linux,
// `CREATE_NEW` on Windows): the sanitizer compares names the way the usual volumes do, but the volume decides which names are the same file, so on "already exists" the next free name is
// tried (docs/LINK-CONTRACT.md, known limits). On Linux the file is never followed through a link (`O_NOFOLLOW`), is created private (0600) and made ordinary (0644) only when it is
// complete. The file is never opened by the app. A transfer that does not complete leaves nothing behind (`discard`). On Windows the mark of the web (the `Zone.Identifier` stream, zone 3,
// "the Internet") is written when the file is created, so that even a partial file carries it, as the Mac's quarantine attribute does; a file that cannot be marked is not handed out
// (it is discarded and the transfer fails). Linux has no standard mark.

use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use super::frames::{RAW_NAME_MAX, SIZE_MAX};
use super::name::unique_name;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SinkError {
    NoFolder,
    NoFreeName,
    /// Windows: the file could not be marked as downloaded (a drive that has no streams, such as FAT).
    Mark,
    Io,
}

/// Windows writes the mark of the web; Linux has none.
pub const MARK_BY_HAND: bool = cfg!(windows);

/// `Downloads/NotchMeow/` of the user.
pub fn default_folder() -> PathBuf {
    downloads_dir().join("NotchMeow")
}

#[cfg(windows)]
fn downloads_dir() -> PathBuf {
    use windows::Win32::System::Com::CoTaskMemFree;
    use windows::Win32::UI::Shell::{FOLDERID_Downloads, SHGetKnownFolderPath, KF_FLAG_DEFAULT};
    // SAFETY: the known-folder call returns a CoTaskMem string that is read once and freed once.
    let known = unsafe {
        SHGetKnownFolderPath(&FOLDERID_Downloads, KF_FLAG_DEFAULT, None).ok().and_then(|p| {
            let s = p.to_string().ok();
            CoTaskMemFree(Some(p.0 as *const _));
            s
        })
    };
    known.map(PathBuf::from).unwrap_or_else(|| crate::platform::home_dir().join("Downloads"))
}

#[cfg(not(windows))]
fn downloads_dir() -> PathBuf {
    let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("."));
    let config = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).unwrap_or_else(|| home.join(".config"));
    std::fs::read_to_string(config.join("user-dirs.dirs")).ok().and_then(|t| parse_user_dirs(&t, &home)).unwrap_or_else(|| home.join("Downloads"))
}

/// The XDG download folder from the text of `user-dirs.dirs` (`XDG_DOWNLOAD_DIR="$HOME/Downloads"`), or None when it is not there or does not name a folder under `home`.
#[cfg_attr(windows, allow(dead_code))]
pub fn parse_user_dirs(text: &str, home: &Path) -> Option<PathBuf> {
    let line = text.lines().map(str::trim).find(|l| l.starts_with("XDG_DOWNLOAD_DIR="))?;
    let value = line.trim_start_matches("XDG_DOWNLOAD_DIR=").trim().trim_matches('"');
    let path = if let Some(rest) = value.strip_prefix("$HOME") { home.join(rest.trim_start_matches('/')) } else { PathBuf::from(value) };
    (path.is_absolute() && path != home).then_some(path)
}

pub struct Sink {
    folder: PathBuf,
    wanted: String,
    mark: bool,
    file: Option<File>,
    path: Option<PathBuf>,
    finished: bool,
    written: u64,
    /// The device and inode of the file this sink created (Linux), so that a discard never removes another file that has taken the name.
    made: Option<(u64, u64)>,
}

impl Sink {
    pub fn new(folder: PathBuf, name: &str, mark: bool) -> Sink {
        Sink { folder, wanted: name.to_string(), mark, file: None, path: None, finished: false, written: 0, made: None }
    }

    pub fn written(&self) -> u64 {
        self.written
    }

    /// Creates the file under a free name and returns its path.
    pub fn open(&mut self) -> Result<PathBuf, SinkError> {
        // The wanted name is one file name in the folder, never a path (the sanitizer refuses these too; this is the second guard).
        if self.wanted.contains('/') || self.wanted.contains('\\') || self.wanted == "." || self.wanted == ".." {
            return Err(SinkError::Io);
        }
        std::fs::create_dir_all(&self.folder).map_err(|_| SinkError::NoFolder)?;
        let mut taken: Vec<String> = std::fs::read_dir(&self.folder).map(|d| d.filter_map(|e| e.ok()?.file_name().into_string().ok()).collect()).unwrap_or_default();
        for _ in 0..200 {
            let name = unique_name(&self.wanted, &taken).ok_or(SinkError::NoFreeName)?;
            let target = self.folder.join(&name);
            match create_exclusive(&target) {
                Ok(file) => {
                    #[cfg(unix)]
                    {
                        use std::os::unix::fs::MetadataExt;
                        self.made = file.metadata().ok().map(|m| (m.dev(), m.ino()));
                    }
                    self.file = Some(file);
                    self.path = Some(target.clone());
                    // A file that cannot be marked is not handed out; it goes, partial or not.
                    if self.mark && !mark_as_downloaded(&target) {
                        self.discard();
                        return Err(SinkError::Mark);
                    }
                    return Ok(target);
                }
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => taken.push(name), // the volume says this name is taken: the next free one
                Err(_) => return Err(SinkError::Io),
            }
        }
        Err(SinkError::NoFreeName)
    }

    pub fn write(&mut self, data: &[u8]) -> Result<(), SinkError> {
        let file = self.file.as_mut().ok_or(SinkError::Io)?;
        file.write_all(data).map_err(|_| SinkError::Io)?;
        self.written += data.len() as u64;
        Ok(())
    }

    /// The transfer is complete: make the file ordinary, then close it. On failure the partial file is removed.
    pub fn finish(&mut self) -> Result<PathBuf, SinkError> {
        let (Some(file), Some(path)) = (self.file.take(), self.path.clone()) else { return Err(SinkError::Io) };
        let done = (|| {
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                file.set_permissions(std::fs::Permissions::from_mode(0o644))?; // on the open descriptor: the very file being closed becomes ordinary
            }
            file.sync_all()
        })();
        drop(file);
        if done.is_err() {
            self.finished = false;
            let _ = std::fs::remove_file(&path);
            self.path = None;
            return Err(SinkError::Io);
        }
        self.finished = true;
        Ok(path)
    }

    /// The transfer did not complete: close and remove the partial file. After a successful `finish` it does nothing, so a completed download stays.
    pub fn discard(&mut self) {
        if self.finished {
            return;
        }
        self.file = None;
        if let Some(path) = self.path.take() {
            #[cfg(unix)]
            {
                use std::os::unix::fs::MetadataExt;
                // The user may have moved ours away, and another file may have taken the name: only the file this sink made is removed.
                if let (Some(made), Ok(now)) = (self.made, std::fs::symlink_metadata(&path)) {
                    if (now.dev(), now.ino()) != made {
                        return;
                    }
                }
            }
            let _ = std::fs::remove_file(&path);
            #[cfg(windows)]
            let _ = std::fs::remove_file(stream_path(&path));
        }
    }
}

/// A sink released before `finish` is discarded: its partial file does not outlive it.
impl Drop for Sink {
    fn drop(&mut self) {
        self.discard();
    }
}

fn create_exclusive(path: &Path) -> std::io::Result<File> {
    let mut o = OpenOptions::new();
    o.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        o.mode(0o600);
        #[cfg(target_os = "linux")]
        o.custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC);
    }
    o.open(path)
}

#[cfg(windows)]
fn stream_path(file: &Path) -> PathBuf {
    let mut s = file.as_os_str().to_owned();
    s.push(":Zone.Identifier");
    PathBuf::from(s)
}

/// Windows: the mark of the web, zone 3 (the Internet), so that Explorer, SmartScreen and Office treat the file as downloaded. Not Windows: nothing to do.
#[cfg(windows)]
fn mark_as_downloaded(file: &Path) -> bool {
    std::fs::write(stream_path(file), "[ZoneTransfer]\r\nZoneId=3\r\n").is_ok()
}

#[cfg(not(windows))]
fn mark_as_downloaded(_file: &Path) -> bool {
    true
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SourceError {
    NotAFile,
    TooLarge,
    NameTooLong,
    Unreadable,
}

/// A file read to be sent: a regular file of at most 4 GiB whose name fits the wire. A folder, a device, a link to either and a file that is too big are refused when the user clicks Send.
pub struct Source {
    pub path: PathBuf,
    pub name: String,
    pub size: u64,
    pub kind: String,
    file: Option<File>,
}

impl Source {
    pub fn open(path: &Path) -> Result<Source, SourceError> {
        let mut o = OpenOptions::new();
        o.read(true);
        #[cfg(target_os = "linux")]
        {
            use std::os::unix::fs::OpenOptionsExt;
            o.custom_flags(libc::O_NONBLOCK | libc::O_CLOEXEC); // a FIFO swapped in after a name check cannot block this open
        }
        let file = o.open(path).map_err(|e| if e.kind() == std::io::ErrorKind::NotFound { SourceError::NotAFile } else { SourceError::Unreadable })?;
        let meta = file.metadata().map_err(|_| SourceError::Unreadable)?; // what was opened is checked, not the name
        if !meta.is_file() {
            return Err(SourceError::NotAFile);
        }
        if meta.len() > SIZE_MAX {
            return Err(SourceError::TooLarge);
        }
        let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("").to_string();
        if name.is_empty() || name.len() > RAW_NAME_MAX {
            return Err(SourceError::NameTooLong);
        }
        let kind = mime_for(path.extension().and_then(|e| e.to_str()).unwrap_or("")).to_string();
        Ok(Source { path: path.to_path_buf(), name, size: meta.len(), kind, file: Some(file) })
    }

    /// The next piece, up to `count` bytes; empty at the end of the file.
    pub fn read(&mut self, count: usize) -> Result<Vec<u8>, SourceError> {
        let file = self.file.as_mut().ok_or(SourceError::Unreadable)?;
        let mut buf = vec![0u8; count];
        let mut filled = 0;
        while filled < count {
            match file.read(&mut buf[filled..]) {
                Ok(0) => break,
                Ok(n) => filled += n,
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                Err(_) => return Err(SourceError::Unreadable),
            }
        }
        buf.truncate(filled);
        Ok(buf)
    }

    pub fn close(&mut self) {
        self.file = None;
    }
}

/// The file's type by its extension: advisory only (the receiver never decides anything by it), printable ASCII, empty when unknown.
fn mime_for(ext: &str) -> &'static str {
    match ext.to_ascii_lowercase().as_str() {
        "txt" | "log" => "text/plain",
        "md" => "text/markdown",
        "html" | "htm" => "text/html",
        "csv" => "text/csv",
        "json" => "application/json",
        "pdf" => "application/pdf",
        "zip" => "application/zip",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "svg" => "image/svg+xml",
        "mp3" => "audio/mpeg",
        "wav" => "audio/wav",
        "mp4" => "video/mp4",
        "mov" => "video/quicktime",
        _ => "",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    fn temp(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("notchmeow-link-{tag}-{}-{}", std::process::id(), COUNTER.fetch_add(1, Ordering::Relaxed)));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn names(dir: &Path) -> Vec<String> {
        let mut v: Vec<String> = std::fs::read_dir(dir).unwrap().map(|e| e.unwrap().file_name().into_string().unwrap()).collect();
        v.sort();
        v
    }

    #[test]
    fn a_file_is_created_written_and_finished() {
        let dir = temp("sink");
        let mut s = Sink::new(dir.join("NotchMeow"), "a.txt", false);
        let path = s.open().unwrap();
        s.write(b"hello ").unwrap();
        s.write(b"world").unwrap();
        assert_eq!(s.written(), 11);
        let done = s.finish().unwrap();
        assert_eq!(done, path);
        assert_eq!(std::fs::read(&done).unwrap(), b"hello world");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(std::fs::metadata(&done).unwrap().permissions().mode() & 0o777, 0o644, "ordinary once complete");
        }
        drop(s);
        assert!(done.exists(), "a completed download stays when the sink is dropped");
    }

    #[test]
    fn a_name_that_is_taken_is_numbered_and_nothing_is_overwritten() {
        let dir = temp("taken");
        std::fs::write(dir.join("a.txt"), "mine").unwrap();
        let mut s = Sink::new(dir.clone(), "a.txt", false);
        let path = s.open().unwrap();
        assert_eq!(path.file_name().unwrap(), "a (1).txt");
        s.write(b"x").unwrap();
        s.finish().unwrap();
        assert_eq!(std::fs::read(dir.join("a.txt")).unwrap(), b"mine");
        let mut again = Sink::new(dir.clone(), "A.TXT", false);
        assert_eq!(again.open().unwrap().file_name().unwrap(), "A (2).TXT", "case does not matter on the volumes that fold it");
    }

    #[cfg(unix)]
    #[test]
    fn a_link_with_the_wanted_name_is_not_followed() {
        let dir = temp("link");
        let elsewhere = temp("elsewhere").join("victim.txt");
        std::fs::write(&elsewhere, "keep").unwrap();
        std::os::unix::fs::symlink(&elsewhere, dir.join("a.txt")).unwrap();
        let mut s = Sink::new(dir.clone(), "a.txt", false);
        let path = s.open().unwrap();
        s.write(b"new").unwrap();
        s.finish().unwrap();
        assert_eq!(path.file_name().unwrap(), "a (1).txt");
        assert_eq!(std::fs::read(&elsewhere).unwrap(), b"keep");
    }

    #[test]
    fn a_dangling_link_with_the_wanted_name_is_not_followed_either() {
        #[cfg(unix)]
        {
            let dir = temp("dangling");
            std::os::unix::fs::symlink(dir.join("nowhere"), dir.join("a.txt")).unwrap();
            let mut s = Sink::new(dir.clone(), "a.txt", false);
            assert_eq!(s.open().unwrap().file_name().unwrap(), "a (1).txt");
            assert!(!dir.join("nowhere").exists(), "nothing was created through the link");
        }
    }

    #[test]
    fn a_transfer_that_does_not_complete_leaves_no_file() {
        let dir = temp("discard");
        let mut s = Sink::new(dir.clone(), "a.bin", false);
        s.open().unwrap();
        s.write(&[1, 2, 3]).unwrap();
        s.discard();
        assert!(names(&dir).is_empty());
        let mut d = Sink::new(dir.clone(), "b.bin", false);
        d.open().unwrap();
        drop(d);
        assert!(names(&dir).is_empty(), "a sink dropped before finish is discarded");
        let mut f = Sink::new(dir.clone(), "c.bin", false);
        f.open().unwrap();
        f.write(&[1]).unwrap();
        f.finish().unwrap();
        f.discard();
        assert_eq!(names(&dir), vec!["c.bin"], "discard after finish does not delete the completed file");
    }

    #[test]
    fn a_file_the_user_moved_away_is_not_confused_with_another_that_took_its_name() {
        #[cfg(unix)]
        {
            let dir = temp("moved");
            let mut s = Sink::new(dir.clone(), "a.bin", false);
            let path = s.open().unwrap();
            std::fs::rename(&path, dir.join("moved.bin")).unwrap();
            std::fs::write(&path, "somebody else's").unwrap();
            s.discard();
            assert_eq!(std::fs::read(&path).unwrap(), b"somebody else's");
        }
    }

    #[test]
    fn a_name_that_is_a_path_is_refused_by_the_sink_itself() {
        let dir = temp("path");
        for bad in ["../x", "a/b", "a\\b", "..", "."] {
            assert_eq!(Sink::new(dir.clone(), bad, false).open().unwrap_err(), SinkError::Io, "{bad}");
        }
        assert!(names(&dir).is_empty());
    }

    #[test]
    fn a_source_is_a_regular_file_only() {
        let dir = temp("source");
        let file = dir.join("hello.pdf");
        std::fs::write(&file, vec![9u8; 70_000]).unwrap();
        let mut src = Source::open(&file).unwrap();
        assert_eq!((src.name.as_str(), src.size, src.kind.as_str()), ("hello.pdf", 70_000, "application/pdf"));
        assert_eq!(src.read(32768).unwrap().len(), 32768);
        assert_eq!(src.read(32768).unwrap().len(), 32768);
        assert_eq!(src.read(32768).unwrap().len(), 4464);
        assert!(src.read(32768).unwrap().is_empty(), "empty at the end");
        #[cfg(unix)]
        assert_eq!(Source::open(&dir).err(), Some(SourceError::NotAFile), "a folder");
        #[cfg(windows)]
        assert!(Source::open(&dir).is_err(), "a folder");
        assert_eq!(Source::open(&dir.join("gone")).err(), Some(SourceError::NotAFile));
        std::fs::write(dir.join("no-type"), "x").unwrap();
        assert_eq!(Source::open(&dir.join("no-type")).unwrap().kind, "");
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(&dir, dir.join("link-to-folder")).unwrap();
            assert_eq!(Source::open(&dir.join("link-to-folder")).err(), Some(SourceError::NotAFile), "a link to a folder");
            assert_eq!(Source::open(Path::new("/dev/null")).err(), Some(SourceError::NotAFile), "a device");
        }
    }

    #[test]
    fn the_xdg_download_folder_is_read_from_user_dirs() {
        let home = Path::new("/home/sam");
        assert_eq!(parse_user_dirs("XDG_DOCUMENTS_DIR=\"$HOME/Docs\"\nXDG_DOWNLOAD_DIR=\"$HOME/Telechargements\"\n", home), Some(PathBuf::from("/home/sam/Telechargements")));
        assert_eq!(parse_user_dirs("XDG_DOWNLOAD_DIR=\"/data/dl\"", home), Some(PathBuf::from("/data/dl")));
        assert_eq!(parse_user_dirs("XDG_DOWNLOAD_DIR=\"$HOME/\"", home), None, "the home folder itself is not a download folder");
        assert_eq!(parse_user_dirs("XDG_DOWNLOAD_DIR=\"relative\"", home), None);
        assert_eq!(parse_user_dirs("", home), None);
    }

    #[test]
    fn the_default_folder_ends_in_downloads_notchmeow() {
        let f = default_folder();
        assert_eq!(f.file_name().unwrap(), "NotchMeow");
    }
}
```


- [ ] **Step 3: Run the tests**

Run: `windows/scripts/cargo-linux.sh test --target-dir /repo/windows/target/g2-tauri -p notchmeow link::files`

Expected: `test result: ok. 10 passed` (including the Review Focus 2 tests `a_name_that_is_taken_is_numbered_and_nothing_is_overwritten`, `a_link_with_the_wanted_name_is_not_followed`, `a_dangling_link_with_the_wanted_name_is_not_followed_either` and `a_name_that_is_a_path_is_refused_by_the_sink_itself`, and `a_transfer_that_does_not_complete_leaves_no_file`). The Windows branch (`Zone.Identifier`, `SHGetKnownFolderPath`) is compiled by Task 15's Windows check and exercised by the owner (Task 16, check 5).

- [ ] **Step 4: Prove it bites**

Run:

```bash
M="python3 .claude/checkpoints/g2-tauri/mut.py rust"
$M windows/src-tauri/src/link/files.rs 'o.custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC);' 'o.custom_flags(libc::O_CLOEXEC);' link::files
$M windows/src-tauri/src/link/files.rs 'o.write(true).create_new(true);' 'o.write(true).create(true).truncate(true);' link::files
```

Expected: both `FAILED` (the link is followed; an existing file is overwritten).

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/src-tauri/src/link/mod.rs windows/src-tauri/src/link/files.rs
git commit -F - <<'MSG'
feat(link): the received file's sink, the source, the Downloads folder and the mark of the web (G2-tauri)

Exclusive create, numbering, no link followed, private until complete, discard that only deletes its own file; Zone.Identifier on Windows (fail closed), the XDG download folder on Linux. A received file is never opened.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Write the task's line in the ledger.

---


### Task 8: The page's link: the snapshot, the backend, the stand-in, `State.link`, the desktop alert

**Agent:** `nm-implementer` (Haiku 5.5, high). The files are given in full; the judgment is in the additive edits.

**Files:**
- Create: `windows/src/link/model.ts`, `windows/src/link/text.ts`, `windows/src/link/backend.ts`, `windows/src/link/mock.ts`, `windows/src/link/devseed.ts`
- Create: `windows/scripts/link-tests/model.test.mjs`, `windows/scripts/link-tests/alert.test.mjs`, `windows/scripts/link-tests/snapshot-samples.json`
- Modify: `windows/src/core/state.ts`, `windows/src/core/layout.ts`, `windows/src/island/island.ts`, `windows/src/island/desktop.ts`, `windows/src/cat/desktop.ts`, `windows/package.json`

**Interfaces:**
- Consumes: `desktopAlert` of `cat/desktop.ts` and `offerCases` of `tests/fixtures/cat/desktop-cases.json` (already in the tree: `transferOffer` is G2-0's).
- Produces, for Tasks 9 and 10 and for Rust (Task 13):
  - `link/model.ts`: `LinkSnapshot { visible, name, listening, rows[], card, ... }`, `LinkCard { kind: "pair"|"offer"|"receiving"|"result", key, code?, peer?, answered?, name?, size?, received?, title?, detail?, canReveal? }`, `LinkRow { id, name, state: "pairedOnline"|"pairedOffline"|"available" }`, `ShownRef { kind, key }`, `LinkBackend` (the 15 calls: `state`, `onSnapshot`, `setVisible`, `setName`, `setDevicesOpen`, `setShelfOpen`, `pair`, `answerPair`, `respondOffer`, `cancelReceiving`, `dismiss`, `forget`, `send`, `cancelSending`, `revealResult`, `revealFolder`), `LinkStore` (`snapshot`, `backend`, `attach`, `apply`, `offerPending`), `cleanSnapshot(unknown)`, `LINK_EMPTY`, `cardTransition(prev, next, viewIsLink) -> {alert, hold, release, collapse}`, `shownOf(card)`, `offerPending(card)`, and the rule for the shelf's device button.
  - `link/text.ts`: the words of the cards. `link/backend.ts`: `bridgeLinkBackend()` (Rust's `link_*` commands and the `link` event). `link/mock.ts`: `mockLinkBackend()`, the stand-in for a plain browser, which refuses a name a card would refuse and records its calls. `link/devseed.ts` (dev server only, sample names only, `ID`, `ROWS`, `CARDS`, `SEEDS`, `devBackend(name)`): the states worth looking at as snapshots; the model tests read them, Task 9's panel and Task 10's `?linkdev=` page draw them, and nothing a release build runs imports it.
  - `State.link` (a `LinkStore`) and `State.linkOfferPending`; the `link` view name and its layout; `transferOffer` as the desktop cat's fifth alert flag; the cats' sleep is blocked while an offer waits.
  - `snapshot-samples.json`: the sample snapshots shared with Rust. The Rust service test (Task 13, `the_snapshot_the_page_gets_is_the_sample_file`) serializes its own `Snapshot` and requires it to equal the sample, and the page's `cleanSnapshot` must keep every sample whole; so the two sides cannot drift apart.

**What the page holds.** The page never holds a key, an address or a path. It holds the last snapshot Rust sent (whole, every time something changes), cleans it (`cleanSnapshot`: a value of a shape it does not know becomes "nothing" and never throws, a text is cut, so a hostile peer's name cannot fill the page) and, on a click, hands Rust the card the click was meant for (`{kind, key}`), so that Rust acts only if that card is still the one on screen (Review Focus 5).

- [ ] **Step 1: Create the files**

**Create `windows/src/link/model.ts`:**

```ts
// The link as the page holds it (sub-project G2): the last snapshot Rust sent, and the few rules the page applies to it. The service, the keys, the sockets and the files are Rust's
// (src-tauri/src/link/); the page holds what to draw and never a key, an address or a path. Pure and DOM-free: the backend is handed in, so the plain-Node checks fake it.
//
// A snapshot is everything the page needs, whole, every time something changes. The page cleans what it is given (`cleanSnapshot`): a value of a shape it does not know becomes "nothing"
// and never throws, so a newer Rust cannot break an older page.

export type LinkRowState = "pairedOnline" | "pairedOffline" | "available";
export type LinkCardKind = "pair" | "offer" | "receiving" | "result";

export interface LinkRow {
  id: string;
  name: string;
  state: LinkRowState;
}

/** One card on the island. `key` says what it is about; a click carries `{kind, key}` back so that Rust acts only on the card the click was meant for. */
export interface LinkCard {
  kind: LinkCardKind;
  key: string;
  /** pair: the six digits. */
  code?: string;
  /** pair, offer, receiving: the other machine's authenticated name. */
  peer?: string;
  /** pair: this user has answered. */
  answered?: boolean;
  /** offer, receiving: the sanitized name, the one that will be saved. */
  name?: string;
  size?: number;
  received?: number;
  /** result. */
  title?: string;
  detail?: string;
  /** result: a file was saved, so "Show in folder" is there. */
  canReveal?: boolean;
}

export interface LinkSnapshot {
  visible: boolean;
  name: string;
  listening: boolean;
  /** A sentence for Settings → Devices when the listener or the credential store could not do what was asked. */
  problem: string | null;
  /** A one-line note after a pairing that did not happen. */
  note: string | null;
  rows: LinkRow[];
  card: LinkCard | null;
  /** One line for the shelf while this machine sends ("Sending a.pdf to Desk PC, 45 %"). */
  sendStatus: string | null;
  sending: boolean;
  /** Where received files go, to show. */
  folder: string;
}

export const LINK_EMPTY: LinkSnapshot = { visible: false, name: "", listening: false, problem: null, note: null, rows: [], card: null, sendStatus: null, sending: false, folder: "" };

const ROW_STATES: readonly string[] = ["pairedOnline", "pairedOffline", "available"];
const CARD_KINDS: readonly string[] = ["pair", "offer", "receiving", "result"];

const text = (v: unknown, max = 2000): string | undefined => (typeof v === "string" ? v.slice(0, max) : undefined);
const count = (v: unknown): number | undefined => (typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : undefined);

function cleanCard(raw: unknown): LinkCard | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  if (typeof r.kind !== "string" || !CARD_KINDS.includes(r.kind) || typeof r.key !== "string") return null;
  const card: LinkCard = { kind: r.kind as LinkCardKind, key: r.key.slice(0, 2000) };
  const set = <K extends keyof LinkCard>(k: K, v: LinkCard[K] | undefined) => {
    if (v !== undefined) card[k] = v;
  };
  set("code", text(r.code, 12));
  set("peer", text(r.peer, 200));
  set("answered", typeof r.answered === "boolean" ? r.answered : undefined);
  set("name", text(r.name, 400));
  set("size", count(r.size));
  set("received", count(r.received));
  set("title", text(r.title, 200));
  set("detail", text(r.detail, 600));
  set("canReveal", typeof r.canReveal === "boolean" ? r.canReveal : undefined);
  return card;
}

/** Whatever Rust sent, as a snapshot: unknown shapes are dropped, never thrown at. */
export function cleanSnapshot(raw: unknown): LinkSnapshot {
  if (!raw || typeof raw !== "object") return LINK_EMPTY;
  const r = raw as Record<string, unknown>;
  const rows: LinkRow[] = [];
  if (Array.isArray(r.rows)) {
    for (const x of r.rows) {
      const o = x as Record<string, unknown> | null;
      if (o && typeof o.id === "string" && typeof o.name === "string" && typeof o.state === "string" && ROW_STATES.includes(o.state)) {
        rows.push({ id: o.id, name: o.name.slice(0, 200), state: o.state as LinkRowState });
      }
    }
  }
  return {
    visible: r.visible === true,
    name: text(r.name, 200) ?? "",
    listening: r.listening === true,
    problem: text(r.problem, 600) ?? null,
    note: text(r.note, 300) ?? null,
    rows,
    card: cleanCard(r.card),
    sendStatus: text(r.sendStatus, 600) ?? null,
    sending: r.sending === true,
    folder: text(r.folder, 600) ?? "",
  };
}

/** The card a click is meant for: what the user saw. */
export interface ShownRef {
  kind: LinkCardKind;
  key: string;
}

export const shownOf = (card: LinkCard): ShownRef => ({ kind: card.kind, key: card.key });

/** A card with buttons the user is about to press holds the island open; a result is only read. */
export const holdsIsland = (card: LinkCard | null): boolean => card !== null && card.kind !== "result";

/** An offer waits for a click: an alert like an approval (the desktop cat flies to the notch for it, the cats do not sleep through it). */
export const offerPending = (card: LinkCard | null): boolean => card?.kind === "offer";

/** What the island does when the card changes. */
export interface CardTransition {
  /** Open the island on the link view. */
  alert: boolean;
  /** Keep it open against the delayed collapse. */
  hold: boolean;
  /** Let it auto-close again. */
  release: boolean;
  /** Close it: the card went and the link view was showing. */
  collapse: boolean;
}

/** A new card, or a card of another kind, opens the island (the quiet period of Rust's `CardRules` covers the click); the same kind again (the user's own answer, a progress tick) does not. */
export function cardTransition(prev: LinkCard | null, next: LinkCard | null, linkViewShowing: boolean): CardTransition {
  const changedKind = next !== null && (prev === null || prev.kind !== next.kind);
  return { alert: changedKind, hold: holdsIsland(next), release: holdsIsland(prev) && !holdsIsland(next), collapse: next === null && linkViewShowing };
}

/** Which machines the shelf offers: the paired ones, online first (Rust already orders the rows that way). */
export const sendTargets = (rows: readonly LinkRow[]): LinkRow[] => rows.filter((r) => r.state === "pairedOnline");

/** "To a device" shows when the link is on or a machine is paired. */
export const showDeviceButton = (s: LinkSnapshot): boolean => s.visible || s.rows.some((r) => r.state !== "available");

/** What the page can ask of the service. Every call only posts a request; the answer is the next snapshot. */
export interface LinkBackend {
  state(): Promise<LinkSnapshot>;
  onSnapshot(cb: (s: LinkSnapshot) => void): () => void;
  setVisible(on: boolean): void;
  setName(name: string): Promise<boolean>;
  setDevicesOpen(open: boolean): void;
  setShelfOpen(open: boolean): void;
  pair(id: string): void;
  answerPair(yes: boolean, shown: ShownRef | null): void;
  respondOffer(accept: boolean, shown: ShownRef | null): void;
  cancelReceiving(shown: ShownRef | null): void;
  dismiss(shown: ShownRef | null): void;
  forget(id: string): void;
  /** Shelf ids, never paths: Rust finds the files. */
  send(ids: string[], to: string): void;
  cancelSending(): void;
  revealResult(): void;
  revealFolder(): void;
}

/** The page's link: the last snapshot, the backend, and who is told when it changes. */
export class LinkStore {
  snapshot: LinkSnapshot = LINK_EMPTY;
  backend: LinkBackend | null = null;
  private stop: (() => void) | null = null;
  private readonly changed: () => void;
  constructor(changed: () => void = () => {}) {
    this.changed = changed;
  }

  /** Starts hearing the backend. The first state is read at once; after that the backend pushes. Returns what changed from, for the island's card rule. */
  attach(backend: LinkBackend, onChange?: (prev: LinkSnapshot, next: LinkSnapshot) => void): void {
    this.stop?.();
    this.backend = backend;
    this.stop = backend.onSnapshot((s) => this.apply(s, onChange));
    void backend.state().then((s) => this.apply(s, onChange)).catch(() => {});
  }

  apply(next: LinkSnapshot, onChange?: (prev: LinkSnapshot, next: LinkSnapshot) => void): void {
    const prev = this.snapshot;
    if (JSON.stringify(prev) === JSON.stringify(next)) return;
    this.snapshot = next;
    onChange?.(prev, next);
    this.changed();
  }

  get offerPending(): boolean {
    return offerPending(this.snapshot.card);
  }
}
```


**Create `windows/src/link/text.ts`:**

```ts
// The words of the link's cards and of Settings → Devices, as small pure functions (sub-project G2). The Mac's twin is `LinkText` in LinkViews.swift.

export { sizeLabel } from "../shelf/store.ts";

/** "483 291": the six digits in two groups, to read out and compare across a desk. */
export function spaced(code: string): string {
  return /^\d{6}$/.test(code) ? `${code.slice(0, 3)} ${code.slice(3)}` : code;
}

/** Whole percent of a transfer, 0 to 100. An empty file is done. */
export function percent(done: number, total: number): number {
  if (!(total > 0)) return 100;
  return Math.max(0, Math.min(100, Math.floor((done * 100) / total)));
}

/** What Settings → Devices says of a machine. */
export function stateWords(state: "pairedOnline" | "pairedOffline" | "available"): string {
  return state === "pairedOnline" ? "Paired" : state === "pairedOffline" ? "Paired, not seen" : "Available";
}

/** The screen reader's reading of the code: "4 8 3 2 9 1". */
export function readCode(code: string): string {
  return code.split("").join(" ");
}

/** The help under the machines list, by system: the firewall on Windows, mDNS on Linux. */
export function permissionHelp(platform: "windows" | "linux" | "other"): string {
  if (platform === "windows") return "If the list stays empty, check that Windows Defender Firewall allows NotchMeow on private networks (Windows asks the first time Visible turns on).";
  if (platform === "linux") return "If the list stays empty, check that your firewall allows UDP 5353 (mDNS) and NotchMeow's incoming connections on the local network.";
  return "If the list stays empty, check that your firewall allows NotchMeow on the local network.";
}
```


**Create `windows/src/link/backend.ts`:**

```ts
// The link's backend inside the app (sub-project G2): Rust's commands and its "link" event. In a plain browser (`npm run dev`, the `?dev` page) the stand-in of mock.ts is used instead.

import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { IS_TAURI } from "../core/bridge";
import { LINK_EMPTY, cleanSnapshot } from "./model.ts";
import type { LinkBackend } from "./model.ts";

const post = (cmd: string, args?: Record<string, unknown>): void => {
  if (!IS_TAURI) return;
  invoke(cmd, args).catch((err) => console.error(`[notchmeow] ${cmd} failed`, err));
};

/** Rust's commands (src-tauri/src/link_cmd.rs). The page holds ids and never a path, a key or an address: `send` takes shelf ids, and Rust finds the files. */
export function bridgeLinkBackend(): LinkBackend {
  return {
    state: async () => (IS_TAURI ? cleanSnapshot(await invoke("link_state")) : LINK_EMPTY),
    onSnapshot: (cb) => {
      let off: (() => void) | null = null;
      let gone = false;
      if (IS_TAURI) {
        void listen<unknown>("link", (e) => cb(cleanSnapshot(e.payload))).then((f) => {
          if (gone) f();
          else off = f;
        });
      }
      return () => {
        gone = true;
        off?.();
      };
    },
    setVisible: (on) => post("link_set_visible", { on }),
    setName: async (name) => (IS_TAURI ? ((await invoke("link_set_name", { name })) as boolean) : false),
    setDevicesOpen: (open) => post("link_devices_open", { open }),
    setShelfOpen: (open) => post("link_shelf_open", { open }),
    pair: (id) => post("link_pair", { id }),
    answerPair: (yes, shown) => post("link_answer_pair", { yes, shown }),
    respondOffer: (accept, shown) => post("link_respond_offer", { accept, shown }),
    cancelReceiving: (shown) => post("link_cancel_receiving", { shown }),
    dismiss: (shown) => post("link_dismiss", { shown }),
    forget: (id) => post("link_forget", { id }),
    send: (ids, to) => post("link_send", { ids, to }),
    cancelSending: () => post("link_cancel_sending"),
    revealResult: () => post("link_reveal_result"),
    revealFolder: () => post("link_reveal_folder"),
  };
}
```


**Create `windows/src/link/mock.ts`:**

```ts
// A stand-in link for a plain browser (sub-project G2): `npm run dev` and the `?dev` page show the link's cards and Settings → Devices working with no app behind it, and the checks run it
// in plain Node. It keeps a snapshot, every call changes it as the real one would (a little), and `set` lets the `?dev` panel (devlink.ts) put it in any state. It records the calls.

import { LINK_EMPTY } from "./model.ts";
import type { LinkBackend, LinkSnapshot, ShownRef } from "./model.ts";

/** A name a card would accept, as Rust decides it: 1 to 63 bytes, no control or invisible character, no space at either end. The stand-in's copy of the rule is only for the `?dev` page. */
function nameOk(name: string): boolean {
  const bytes = new TextEncoder().encode(name).length;
  return bytes >= 1 && bytes <= 63 && name === name.trim() && !/[\p{Cc}\p{Cf}\u2028\u2029]/u.test(name);
}

/** A stand-in link: it keeps a snapshot, every call changes it as the real one would (a little), and `set` lets the `?dev` panel put it in any state. It records the calls for the checks. */
export function mockLinkBackend(seed: Partial<LinkSnapshot> = {}): LinkBackend & { snapshot: LinkSnapshot; calls: string[]; set(next: Partial<LinkSnapshot>): void } {
  const listeners = new Set<(s: LinkSnapshot) => void>();
  const self = {
    snapshot: { ...LINK_EMPTY, name: "Desk PC", folder: "C:\\Users\\Sam\\Downloads\\NotchMeow", ...seed } as LinkSnapshot,
    calls: [] as string[],
    set(next: Partial<LinkSnapshot>) {
      self.snapshot = { ...self.snapshot, ...next };
      for (const l of listeners) l(self.snapshot);
    },
    state: async () => self.snapshot,
    onSnapshot(cb: (s: LinkSnapshot) => void) {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    setVisible(on: boolean) {
      self.calls.push(`visible ${on}`);
      self.set({ visible: on, listening: on });
    },
    async setName(name: string) {
      self.calls.push(`name ${name}`);
      if (!nameOk(name)) return false;
      self.set({ name });
      return true;
    },
    setDevicesOpen: (open: boolean) => void self.calls.push(`devices ${open}`),
    setShelfOpen: (open: boolean) => void self.calls.push(`shelf ${open}`),
    pair: (id: string) => void self.calls.push(`pair ${id}`),
    answerPair: (yes: boolean, shown: ShownRef | null) => void self.calls.push(`answerPair ${yes} ${shown?.key ?? "-"}`),
    respondOffer: (accept: boolean, shown: ShownRef | null) => void self.calls.push(`respondOffer ${accept} ${shown?.key ?? "-"}`),
    cancelReceiving: (shown: ShownRef | null) => void self.calls.push(`cancelReceiving ${shown?.key ?? "-"}`),
    dismiss(shown: ShownRef | null) {
      self.calls.push(`dismiss ${shown?.key ?? "-"}`);
      if (self.snapshot.card?.kind === "result") self.set({ card: null });
    },
    forget(id: string) {
      self.calls.push(`forget ${id}`);
      self.set({ rows: self.snapshot.rows.filter((r) => r.id !== id) });
    },
    send: (ids: string[], to: string) => void self.calls.push(`send ${ids.join(",")} ${to}`),
    cancelSending: () => void self.calls.push("cancelSending"),
    revealResult: () => void self.calls.push("revealResult"),
    revealFolder: () => void self.calls.push("revealFolder"),
  };
  return self;
}
```


**Create `windows/src/link/devseed.ts`:**

```ts
// Dev server only (sub-project G2): the states of the link worth looking at, as snapshots, for the `?dev` page's Link panel and for `settings.html?linkdev=<state>`. Sample names only. Nothing
// here is imported by a release build: both callers load it behind `import.meta.env.DEV`.

import { mockLinkBackend } from "./mock.ts";
import type { LinkCard, LinkRow, LinkSnapshot } from "./model.ts";

export const ID = { mac: "a1".repeat(16), desk: "b2".repeat(16), laptop: "c3".repeat(16), netbook: "d4".repeat(16) } as const;

export const ROWS: Record<string, LinkRow[]> = {
  none: [],
  two: [
    { id: ID.mac, name: "Sam's MacBook Pro", state: "pairedOnline" },
    { id: ID.laptop, name: "Studio laptop", state: "pairedOnline" },
    { id: ID.netbook, name: "Old netbook", state: "pairedOffline" },
    { id: ID.desk, name: "Desk PC", state: "available" },
  ],
  offline: [{ id: ID.netbook, name: "Old netbook", state: "pairedOffline" }],
};

export const CARDS: Record<string, LinkCard> = {
  pair: { kind: "pair", key: "483291|Sam's MacBook Pro", code: "483291", peer: "Sam's MacBook Pro", answered: false },
  pairAnswered: { kind: "pair", key: "483291|Sam's MacBook Pro", code: "483291", peer: "Sam's MacBook Pro", answered: true },
  offer: { kind: "offer", key: `${ID.mac}|t1`, name: "Quarterly report.pdf", size: 2_400_000, peer: "Sam's MacBook Pro" },
  offerLong: { kind: "offer", key: `${ID.mac}|t2`, name: "A very long file name that goes on and on and on for the whole width of the card, final version 7.docx", size: 48_000_000, peer: "Sam's MacBook Pro with a long machine name" },
  receiving0: { kind: "receiving", key: `${ID.mac}|t1`, name: "Quarterly report.pdf", size: 2_400_000, received: 0, peer: "Sam's MacBook Pro" },
  receiving45: { kind: "receiving", key: `${ID.mac}|t1`, name: "Quarterly report.pdf", size: 2_400_000, received: 1_080_000, peer: "Sam's MacBook Pro" },
  receiving100: { kind: "receiving", key: `${ID.mac}|t1`, name: "Quarterly report.pdf", size: 2_400_000, received: 2_400_000, peer: "Sam's MacBook Pro" },
  received: { kind: "result", key: "Received|Saved as Quarterly report.pdf", title: "Received", detail: "Saved as Quarterly report.pdf in Downloads/NotchMeow.", canReveal: true },
  paired: { kind: "result", key: "Paired|x", title: "Paired", detail: "This computer and Sam's MacBook Pro can now send files to each other.", canReveal: false },
  notPaired: { kind: "result", key: "Not paired|x", title: "Not paired", detail: "The other machine said the codes did not match.", canReveal: false },
  expired: { kind: "result", key: "Offer expired|x", title: "Offer expired", detail: "Nobody answered in 2 minutes, so it was declined.", canReveal: false },
  cancelled: { kind: "result", key: "Transfer cancelled|x", title: "Transfer cancelled", detail: "Nothing was saved.", canReveal: false },
  stopped: { kind: "result", key: "Transfer stopped|x", title: "Transfer stopped", detail: "The connection ended before the file was complete. Nothing was saved.", canReveal: false },
};

/** `settings.html?linkdev=<name>`: off, on, empty, problem, note. */
export const SEEDS: Record<string, Partial<LinkSnapshot>> = {
  off: {},
  on: { visible: true, listening: true, rows: ROWS.two },
  empty: { visible: true, listening: true, rows: ROWS.none },
  problem: { visible: true, listening: false, problem: "This computer could not start listening.", rows: ROWS.offline },
  note: { visible: true, listening: true, rows: ROWS.two, note: "Wait 30 seconds before trying again." },
};

export function devBackend(name: string) {
  return mockLinkBackend(SEEDS[name] ?? SEEDS.on);
}
```


**Create `windows/scripts/link-tests/snapshot-samples.json`:**

```json
[
  {
    "name": "off, nothing paired",
    "snapshot": { "visible": false, "name": "Desk PC", "listening": false, "problem": null, "note": null, "rows": [], "card": null, "sendStatus": null, "sending": false, "folder": "C:\\Users\\Sam\\Downloads\\NotchMeow" }
  },
  {
    "name": "on, three machines, a note",
    "snapshot": {
      "visible": true, "name": "Desk PC", "listening": true, "problem": null, "note": "Wait 30 seconds before trying again.",
      "rows": [
        { "id": "a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1", "name": "Sam's MacBook Pro", "state": "pairedOnline" },
        { "id": "b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2", "name": "Old netbook", "state": "pairedOffline" },
        { "id": "c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3", "name": "Studio laptop", "state": "available" }
      ],
      "card": null, "sendStatus": "Sending report.pdf to Sam's MacBook Pro, 45 %", "sending": true, "folder": "/home/sam/Downloads/NotchMeow"
    }
  },
  {
    "name": "a pairing code, not answered",
    "snapshot": { "visible": true, "name": "Desk PC", "listening": true, "problem": "This computer could not announce itself on the network.", "note": null, "rows": [], "card": { "kind": "pair", "key": "483291|Sam's MacBook Pro", "code": "483291", "peer": "Sam's MacBook Pro", "answered": false }, "sendStatus": null, "sending": false, "folder": "" }
  },
  {
    "name": "an offer",
    "snapshot": { "visible": true, "name": "Desk PC", "listening": true, "problem": null, "note": null, "rows": [], "card": { "kind": "offer", "key": "a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1|0102", "name": "Quarterly report.pdf", "size": 2400000, "peer": "Sam's MacBook Pro" }, "sendStatus": null, "sending": false, "folder": "" }
  },
  {
    "name": "a file coming in",
    "snapshot": { "visible": true, "name": "Desk PC", "listening": true, "problem": null, "note": null, "rows": [], "card": { "kind": "receiving", "key": "a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1|0102", "name": "Quarterly report.pdf", "size": 2400000, "received": 1080000, "peer": "Sam's MacBook Pro" }, "sendStatus": null, "sending": false, "folder": "" }
  },
  {
    "name": "a result with a saved file",
    "snapshot": { "visible": true, "name": "Desk PC", "listening": true, "problem": null, "note": null, "rows": [], "card": { "kind": "result", "key": "Received|Saved as Quarterly report.pdf in Downloads/NotchMeow.", "title": "Received", "detail": "Saved as Quarterly report.pdf in Downloads/NotchMeow.", "canReveal": true }, "sendStatus": null, "sending": false, "folder": "" }
  }
]
```


**Create `windows/scripts/link-tests/model.test.mjs`:**

```js
import test from "node:test";
import assert from "node:assert/strict";
import { LINK_EMPTY, LinkStore, cardTransition, cleanSnapshot, holdsIsland, offerPending, sendTargets, shownOf, showDeviceButton } from "../../src/link/model.ts";
import { mockLinkBackend } from "../../src/link/mock.ts";
import { percent, permissionHelp, readCode, spaced, stateWords } from "../../src/link/text.ts";
import { CARDS, ROWS } from "../../src/link/devseed.ts";

// The link as the page holds it (G2): the snapshot Rust sends is cleaned, never thrown at; the island's rule for a card; the words of the cards.

test("a snapshot is whatever Rust said, cleaned: unknown shapes are dropped and nothing throws", () => {
  for (const bad of [null, undefined, 5, "x", [], true]) assert.deepEqual(cleanSnapshot(bad), LINK_EMPTY);
  const s = cleanSnapshot({
    visible: true, name: "Desk PC", listening: 1, problem: 7, note: "n", sendStatus: ["x"], sending: "yes", folder: "C:\\Downloads\\NotchMeow",
    rows: [{ id: "a", name: "A", state: "pairedOnline" }, { id: "b", name: "B", state: "ghost" }, null, { id: 3, name: "C", state: "available" }, "x"],
    card: { kind: "offer", key: "k", name: "a.txt", size: 12, received: -4, answered: "yes", extra: "dropped" },
  });
  assert.equal(s.visible, true);
  assert.equal(s.listening, false, "only the boolean true counts");
  assert.equal(s.problem, null);
  assert.equal(s.sendStatus, null);
  assert.equal(s.sending, false);
  assert.deepEqual(s.rows, [{ id: "a", name: "A", state: "pairedOnline" }]);
  assert.deepEqual(s.card, { kind: "offer", key: "k", name: "a.txt", size: 12 }, "a negative count and a non-boolean flag are left out, an unknown field is dropped");
  assert.equal(cleanSnapshot({ card: { kind: "weird", key: "k" } }).card, null);
  assert.equal(cleanSnapshot({ card: { kind: "pair" } }).card, null, "a card with no key is no card");
});

test("a long text is cut, so a hostile peer's name cannot fill the page", () => {
  const s = cleanSnapshot({ card: { kind: "pair", key: "k", peer: "x".repeat(5000), code: "1".repeat(50) }, rows: [{ id: "a", name: "y".repeat(5000), state: "available" }] });
  assert.equal(s.card.peer.length, 200);
  assert.equal(s.card.code.length, 12);
  assert.equal(s.rows[0].name.length, 200);
});

test("which cards hold the island, and which is an alert", () => {
  for (const [name, c] of Object.entries(CARDS)) {
    assert.equal(holdsIsland(c), !["received", "paired", "notPaired", "expired", "cancelled", "stopped"].includes(name), name);
    assert.equal(offerPending(c), name === "offer" || name === "offerLong", name);
  }
  assert.equal(holdsIsland(null), false);
  assert.equal(offerPending(null), false);
});

test("the island's rule for a card: a new card or a new kind opens it, the same kind again does not, a card with buttons holds it, the end lets it go", () => {
  const T = (prev, next, link = false) => cardTransition(prev ? CARDS[prev] : null, next ? CARDS[next] : null, link);
  assert.deepEqual(T(null, "offer"), { alert: true, hold: true, release: false, collapse: false }, "an offer arrives");
  assert.deepEqual(T("offer", "receiving45"), { alert: true, hold: true, release: false, collapse: false }, "a change of kind (offer to receiving) opens it again");
  assert.deepEqual(T("receiving0", "receiving45"), { alert: false, hold: true, release: false, collapse: false }, "progress is the same kind: nothing opens");
  assert.deepEqual(T("pair", "pairAnswered"), { alert: false, hold: true, release: false, collapse: false }, "the user's own answer is the same kind");
  assert.deepEqual(T("receiving100", "received"), { alert: true, hold: false, release: true, collapse: false }, "the end: a result, no hold");
  assert.deepEqual(T("received", null, true), { alert: false, hold: false, release: false, collapse: true }, "a card that goes while the link view shows closes the island");
  assert.deepEqual(T("received", null, false), { alert: false, hold: false, release: false, collapse: false }, "and not when the island shows something else");
  assert.deepEqual(T("offer", null, true), { alert: false, hold: false, release: true, collapse: true }, "an offer withdrawn");
});

test("the shelf offers the machines that are paired and online, and the device button shows when the link is on or a machine is paired", () => {
  assert.deepEqual(sendTargets(ROWS.two).map((r) => r.name), ["Sam's MacBook Pro", "Studio laptop"]);
  assert.deepEqual(sendTargets(ROWS.offline), []);
  assert.equal(showDeviceButton({ ...LINK_EMPTY }), false, "nothing on, nobody paired");
  assert.equal(showDeviceButton({ ...LINK_EMPTY, visible: true }), true);
  assert.equal(showDeviceButton({ ...LINK_EMPTY, rows: ROWS.offline }), true);
  assert.equal(showDeviceButton({ ...LINK_EMPTY, rows: [{ id: "x", name: "X", state: "available" }] }), false, "a machine only seen is not a destination");
});

test("a click carries the card it was meant for: its kind and what it is about", () => {
  assert.deepEqual(shownOf(CARDS.offer), { kind: "offer", key: CARDS.offer.key });
});

test("the store keeps the last snapshot, tells the island only about a real change, and reads the first state at once", async () => {
  let notified = 0;
  const seen = [];
  const store = new LinkStore(() => notified++);
  const mock = mockLinkBackend({ visible: true });
  store.attach(mock, (prev, next) => seen.push([prev.card?.kind ?? null, next.card?.kind ?? null]));
  await new Promise((r) => setTimeout(r, 0));
  assert.equal(store.snapshot.visible, true);
  const base = notified;
  mock.set({ card: CARDS.offer });
  mock.set({ card: CARDS.offer }); // the same again
  assert.equal(notified, base + 1, "an identical snapshot changes nothing");
  assert.deepEqual(seen.at(-1), [null, "offer"]);
  assert.equal(store.offerPending, true);
  mock.set({ card: null });
  assert.equal(store.offerPending, false);
});

test("the stand-in link refuses a name a card would refuse, records the calls, and forgets a machine", async () => {
  const mock = mockLinkBackend({ rows: ROWS.two });
  assert.equal(await mock.setName(" padded"), false);
  assert.equal(await mock.setName("a\u202eb"), false);
  assert.equal(await mock.setName("x".repeat(64)), false);
  assert.equal(await mock.setName("Studio PC"), true);
  assert.equal(mock.snapshot.name, "Studio PC");
  mock.forget(ROWS.two[0].id);
  assert.equal(mock.snapshot.rows.length, 3);
  mock.respondOffer(true, shownOf(CARDS.offer));
  assert.match(mock.calls.at(-1), /^respondOffer true /);
});

test("the words of the cards", () => {
  assert.equal(spaced("483291"), "483 291");
  assert.equal(spaced("12"), "12", "not six digits: as it is");
  assert.equal(readCode("483291"), "4 8 3 2 9 1");
  assert.equal(percent(0, 100), 0);
  assert.equal(percent(1080000, 2400000), 45);
  assert.equal(percent(5, 0), 100, "an empty file is done");
  assert.equal(percent(200, 100), 100);
  assert.equal(percent(-5, 100), 0);
  assert.equal(stateWords("pairedOnline"), "Paired");
  assert.equal(stateWords("pairedOffline"), "Paired, not seen");
  assert.equal(stateWords("available"), "Available");
  assert.match(permissionHelp("windows"), /Windows Defender Firewall/);
  assert.match(permissionHelp("linux"), /5353/);
});

import fs from "node:fs";

// The one sample file that Rust and the page both read (Rust: src-tauri/src/link/service.rs, `the_snapshot_the_page_gets_is_the_sample_file`): what Rust serializes is what the page keeps whole.
test("every sample snapshot of the shared file is kept whole by the page's clean-up", () => {
  const samples = JSON.parse(fs.readFileSync(new URL("./snapshot-samples.json", import.meta.url), "utf8"));
  assert.ok(samples.length >= 6);
  for (const s of samples) assert.deepEqual(cleanSnapshot(s.snapshot), s.snapshot, s.name);
});
```


**Create `windows/scripts/link-tests/alert.test.mjs`:**

```js
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { desktopAlert } from "../../src/cat/desktop.ts";

// An incoming transfer offer is an alert to the desktop cat (docs/CAT-CONTRACT.md: `transferOffer` in desktopAlert, G2-0). The fixture's `offerCases` replay here; `alertCases` are untouched.
const fx = JSON.parse(fs.readFileSync(new URL("../../../tests/fixtures/cat/desktop-cases.json", import.meta.url), "utf8"));
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

test("every offerCase of the cat contract", () => {
  assert.ok(fx.offerCases.length >= 5, "the fixture has its rows");
  for (const c of fx.offerCases) assert.equal(desktopAlert(c.input), c.out, c.name);
});

test("the old alertCases still hold, and a flag counts only when it is exactly true", () => {
  for (const c of fx.alertCases) assert.equal(desktopAlert(c.input), c.out, c.name);
  for (const v of [1, "true", [], {}, null, undefined, 0]) assert.equal(desktopAlert({ transferOffer: v }), false, String(v));
  assert.equal(desktopAlert({ transferOffer: true }), true);
});

test("the island passes the pending offer to the desktop cat and to the cats' sleep, and State says when one waits", () => {
  assert.match(source("island/desktop.ts"), /desktopAlert\(\{ approval: State\.attentionNeeded, fileCatch: State\.fileCatch\(\), transferOffer: State\.linkOfferPending \}\)/);
  assert.match(source("island/island.ts"), /blocked: \(\) => State\.attentionNeeded \|\| State\.linkOfferPending,/);
  assert.match(source("core/state.ts"), /get linkOfferPending\(\): boolean \{\s*return this\.link\.offerPending;\s*\}/);
});
```


- [ ] **Step 2: Run the tests before the edits (the alert tests must fail, the model tests pass)**

```bash
cd windows
node --experimental-strip-types --test --test-reporter=spec scripts/link-tests/model.test.mjs 2>&1 | grep -E "^ℹ (tests|pass|fail)"
node --experimental-strip-types --test --test-reporter=spec scripts/link-tests/alert.test.mjs 2>&1 | grep -E "^ℹ (tests|pass|fail)"
cd ..
```

Expected: the first prints `ℹ tests 10`, `ℹ pass 10`, `ℹ fail 0`; the second prints `ℹ fail 3` (nothing passes the offer yet: that is the red).

- [ ] **Step 3: The additive edits**

```bash
python3 - <<'EOF'
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")

# State: the link, and the alert the cats' sleep and the desktop cat read
edit("windows/src/core/state.ts", 'import { ShelfStore } from "../shelf/store.ts";', 'import { ShelfStore } from "../shelf/store.ts";\nimport { LinkStore } from "../link/model.ts";')
edit("windows/src/core/state.ts", "  shelfCaps = { dragOut: false, send: false };\n", '''  shelfCaps = { dragOut: false, send: false };

  /** The link between this machine and the user's others (sub-project G2): what Rust last said, and the backend. Empty until main.ts hands it a backend and reads it. */
  link = new LinkStore(() => this.notify());

  /** An offer from another machine waits for a click: an alert like an approval (the desktop cat flies to the notch for it, island/sleep.ts does not let the cats fall asleep). */
  get linkOfferPending(): boolean {
    return this.link.offerPending;
  }
''')

# the view name and its layout (laid out as the approval card is)
edit("windows/src/core/layout.ts", '  | "shelf";', '  | "shelf"\n  | "link";')
edit("windows/src/core/layout.ts", '  greeting: { height: 150, botX: 320, botY: 90, botDiameter: 0, agentMode: "none" },\n', '''  greeting: { height: 150, botX: 320, botY: 90, botDiameter: 0, agentMode: "none" },
  // The link's card (sub-project G2): a pairing code, an offer from another machine, a file coming in, the end of any of them. Laid out as the approval card is.
  link: { height: 160, botX: 62, botY: null, botDiameter: 56, agentMode: "column" },
''')

# the cats' sleep and the desktop cat
edit("windows/src/island/island.ts", "    blocked: () => State.attentionNeeded,", "    blocked: () => State.attentionNeeded || State.linkOfferPending,")
edit("windows/src/island/desktop.ts", "this.trip.alert(desktopAlert({ approval: State.attentionNeeded, fileCatch: State.fileCatch() }));", "this.trip.alert(desktopAlert({ approval: State.attentionNeeded, fileCatch: State.fileCatch(), transferOffer: State.linkOfferPending }));")
edit("windows/src/cat/desktop.ts", "o.fileCatch === true", "o.fileCatch === true || o.transferOffer === true")

# npm run check:link
edit("windows/package.json", '    "check:sidekick":', '    "check:link": "node --experimental-strip-types --test --test-reporter=spec scripts/link-tests/*.test.mjs",\n    "check:sidekick":')
EOF
```

- [ ] **Step 4: Run the page checks**

```bash
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:link 2>&1 | grep -E "^ℹ (tests|pass|fail)"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
cd ..
```

Expected: `tsc exit 0`; `ℹ tests 13`, `ℹ pass 13`, `ℹ fail 0` for `check:link` (10 + 3); `check:cat` passes as it did in the baseline (the `alertCases` of the cat contract are untouched).

- [ ] **Step 5: Prove it bites**

```bash
cd windows
M="python3 ../.claude/checkpoints/g2-tauri/mut.py node"
$M src/cat/desktop.ts 'o.fileCatch === true || o.transferOffer === true' 'o.fileCatch === true' scripts/link-tests/alert.test.mjs
$M src/island/island.ts 'State.attentionNeeded || State.linkOfferPending' 'State.attentionNeeded' scripts/link-tests/alert.test.mjs
$M src/link/model.ts 'JSON.stringify(prev) === JSON.stringify(next)' 'false' scripts/link-tests/model.test.mjs
cd ..
```

Expected: each prints `# fail` with a number above 0 (the offer is no alert; the sleep is not blocked; the store tells the island about a change that is none).

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/src/link windows/scripts/link-tests windows/src/core/state.ts windows/src/core/layout.ts windows/src/island/island.ts windows/src/island/desktop.ts windows/src/cat/desktop.ts windows/package.json
git commit -F - <<'MSG'
feat(link): the page's link, its snapshot rules, the backend and the stand-in (G2-tauri)

LinkStore holds the last snapshot Rust sent and cleans what it is given; the backend is Rust's commands and its link event, the stand-in serves a plain browser. A waiting offer is an alert to the desktop cat (transferOffer) and keeps the cats awake; the link view has its layout.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Write the task's line in the ledger.

---


### Task 9: The link card, the island's part, the `?dev` Link panel

**Agent:** `nm-implementer` (Haiku 5.5, high). The files are given in full.

**Files:**
- Create: `windows/src/link/link.css` (all of the link's styles, including the ones Task 10's views use), `windows/src/views/link.ts`, `windows/src/island/link.ts`, `windows/src/link/devlink.ts`
- Modify: `windows/src/views/views.ts`, `windows/src/cat/dev.ts`, `windows/src/main.ts`

**Interfaces:**
- Consumes: Task 8's `LinkStore`, `LinkBackend`, `cardTransition`, `shownOf`, `holdsIsland`, `LINK_EMPTY`, `mockLinkBackend`; the island's `alert`, `holdOpen`, `dropPin`, `collapse` (the `Island` methods `main.ts` already holds).
- Produces: `views/link.ts` `buildLink()` (a view like every other: `{ el, sync() }`, registered as `link`); `island/link.ts` `linkChanged(host, prev, next, viewIsLink?, pinnedByRequest?)`, `shelfLooking(view, mode)`, `ShelfLook`; `link/devlink.ts` `mountLinkDev(root, before)`; `window.__nm.link` (the stand-in, dev server only).

**What a card does.** Five faces, one view: pairing code (the six digits in two groups, "No" and "They match"; after a click it says it is waiting for the other machine), an offer ("`<machine>` wants to send you a file", the **sanitized** name and the size, "Decline" and "Accept"), receiving (a progress bar and Cancel), and a result (title, detail, "OK", and "Show in folder" when a file was saved). Every button hands Rust the card it was drawn on (`shownOf(card)`), so a click that lands within 700 ms of a change of card, or on a card that is gone, does nothing (Task 5, `CardRules`). **Nothing says yes to an offer except the Accept button** (a wiring test pins it in Task 10). A new card, or one of another kind, opens the island on the `link` view even when it is hidden (the island's own `alert`); a card with buttons holds it open against the idle timer; when the buttons are gone the hold goes unless a permission request still holds it; a card that is gone closes an island that was showing it. No timer in the view or in `island/link.ts`: the 2 minutes of an offer and the 700 ms settle are Rust's.

- [ ] **Step 1: Create the files**

**Create `windows/src/link/link.css`:**

```css
/* The link between your machines (sub-project G2): the island's link card, the "To a device" bar on the shelf and the machines list of Settings → Devices. Only new classes, all
   prefixed lk-, plus one modifier of the shelf head (sh-choosing). No rule of a shipped view changes. The colours are the existing variables. */

.lk-body {
  height: 100%;
}

.lk-title {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.lk-name {
  max-width: 100%;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.lk-pairrow {
  display: flex;
  align-items: center;
  gap: 12px;
  min-width: 0;
}

/* Large enough to read out and compare across a desk. */
.lk-code {
  font: 600 24px var(--mono);
  letter-spacing: 0.04em;
  color: var(--ink);
  white-space: nowrap;
  user-select: text;
}

.lk-pairrow .sub {
  font-size: 12px;
  min-width: 0;
}

.lk-detail {
  font: 400 12px var(--font);
  color: var(--dim);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.lk-bar {
  height: 6px;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.1);
  overflow: hidden;
}

.lk-fill {
  height: 100%;
  width: 0;
  border-radius: 999px;
  background: var(--cyan);
  transition: width 0.12s linear;
}

.lk-progressrow {
  display: flex;
  align-items: center;
  gap: 8px;
}

.lk-words {
  font-size: 11px;
  font-variant-numeric: tabular-nums;
}

.lk-spacer {
  flex: 1;
}

.lk-body .btn:disabled {
  opacity: 0.55;
}

/* ── "To a device" on the shelf's head row ── */

.lk-devbar {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

.lk-line {
  font: 400 11px var(--font);
  color: var(--dim);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  min-width: 0;
}

.lk-cancel {
  font: 400 11px var(--font);
  color: var(--dim);
  background: none;
  border: 0;
  padding: 0;
  cursor: default;
  flex: 0 0 auto;
}

.lk-chips {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-width: 0;
}

.lk-chip {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  display: inline-block;
}

.lk-chip.off {
  opacity: 0.35;
}

.lk-none {
  font: 400 11px var(--font);
  color: var(--dim);
  white-space: nowrap;
}

/* While the machines are listed, the head shows only the title and the list. */
.sh-head.sh-choosing > :not(.sh-title):not(.lk-devbar) {
  display: none;
}

/* ── Settings → Devices (the settings page) ── */

.lk-sub {
  font-weight: 600;
  color: var(--ink);
  margin-top: 4px;
}

.lk-machines {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.lk-machine {
  flex-wrap: nowrap;
}

.lk-mname {
  min-width: 0;
  max-width: 190px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.lk-mstate {
  min-width: 100px;
}
```


**Create `windows/src/views/link.ts`:**

```ts
// The link's island view (sub-project G2): the card for a pairing (the six digits to compare), for an offer from another machine (Accept and Decline), for a file coming in (progress and
// Cancel) and for the end of any of them. A new view in the island's own style (the same card, wash, buttons and type as the approval card); no existing view changes. The card comes from
// `State.link`, Rust's last snapshot; every button hands back the card it was drawn on, so Rust does nothing for a click that was meant for a card that has since been replaced, or that
// came in the first 700 ms after the card changed kind. Nothing here accepts for the user: Accept is a button, and a button is a click.

import { h, clear } from "./dom";
import { State } from "../core/state";
import { washRGBA, type Wash } from "../core/layout";
import { percent, readCode, sizeLabel, spaced } from "../link/text.ts";
import { shownOf } from "../link/model.ts";
import type { LinkCard } from "../link/model.ts";
import type { ViewHost } from "./views";

function card(wash: Wash, ...children: (Node | string)[]): HTMLElement {
  const el = h("div", { class: wash ? "card wash" : "card" }, ...children);
  if (wash) el.style.setProperty("--wash", washRGBA(wash));
  return el;
}

function btn(label: string, kind: "primary" | "secondary", onClick: () => void, disabled = false): HTMLElement {
  return h("button", { class: `btn ${kind}`, onclick: onClick, disabled }, h("span", { text: label }));
}

function stack(...children: Node[]): HTMLElement {
  const el = h("div", { class: "stack" }, ...children);
  el.style.padding = "4px 16px 4px 116px";
  return el;
}

export function buildLink(): ViewHost {
  const body = h("div", { class: "lk-body" });
  const el = h("div", { class: "view" }, body);
  let drawn = "";
  /** The progress bar and its words, kept so that a tick of progress changes them and does not rebuild the card (a button under the pointer is not replaced). */
  let bar: HTMLElement | null = null;
  let words: HTMLElement | null = null;

  const backend = () => State.link.backend;

  function pair(c: LinkCard): HTMLElement {
    const peer = c.peer ?? "that machine";
    const answered = c.answered === true;
    const code = h("span", { class: "lk-code", text: spaced(c.code ?? ""), "aria-label": `Pairing code ${readCode(c.code ?? "")}` });
    return card(
      "indigo",
      stack(
        h("div", { class: "title lk-title", text: `Pair with ${peer}?` }),
        h("div", { class: "lk-pairrow" }, code, h("span", { class: "sub", text: `Check that ${peer} shows the same six digits.` })),
        h("div", { class: "actions" },
          btn("No", "secondary", () => backend()?.answerPair(false, shownOf(c)), answered),
          btn(answered ? `Waiting for ${peer}` : "They match", "primary", () => backend()?.answerPair(true, shownOf(c)), answered),
        ),
      ),
    );
  }

  function offer(c: LinkCard): HTMLElement {
    return card(
      "cyan",
      stack(
        h("div", { class: "title lk-title", text: `${c.peer ?? "A machine"} wants to send you a file` }),
        // The name is the sanitized one: the one that would be saved.
        h("div", { class: "code lk-name", text: `${c.name ?? ""}  ${sizeLabel(c.size ?? 0)}` }),
        h("div", { class: "sub", text: "Saved in Downloads/NotchMeow, never opened. Declined after 2 minutes." }),
        h("div", { class: "actions" }, btn("Decline", "secondary", () => backend()?.respondOffer(false, shownOf(c))), btn("Accept", "primary", () => backend()?.respondOffer(true, shownOf(c)))),
      ),
    );
  }

  function receiving(c: LinkCard): HTMLElement {
    bar = h("div", { class: "lk-fill" });
    words = h("span", { class: "sub lk-words" });
    return card(
      "cyan",
      stack(
        h("div", { class: "title lk-title lk-name", text: `Receiving ${c.name ?? ""} from ${c.peer ?? "a machine"}` }),
        h("div", { class: "lk-bar", role: "progressbar", "aria-label": "Receiving" }, bar),
        h("div", { class: "lk-progressrow" }, words, h("span", { class: "lk-spacer" }), btn("Cancel", "secondary", () => backend()?.cancelReceiving(shownOf(c)))),
      ),
    );
  }

  function result(c: LinkCard): HTMLElement {
    return card(
      c.canReveal ? "green" : "soft",
      stack(
        h("div", { class: "title lk-title", text: c.title ?? "" }),
        h("div", { class: "lk-detail", text: c.detail ?? "" }),
        h("div", { class: "actions" }, c.canReveal ? btn("Show in folder", "secondary", () => backend()?.revealResult()) : null, btn("OK", "primary", () => backend()?.dismiss(shownOf(c)))),
      ),
    );
  }

  function progress(c: LinkCard) {
    if (!bar || !words) return;
    const done = c.received ?? 0, total = c.size ?? 0, pct = percent(done, total);
    bar.style.width = `${pct}%`;
    words.textContent = `${sizeLabel(done)} of ${sizeLabel(total)}, ${pct} %`;
  }

  return {
    el,
    sync() {
      const c = State.link.snapshot.card;
      // Rebuilt only when the card is another one (its kind, what it is about, whether it was answered), never for a tick of progress.
      const key = c ? JSON.stringify([c.kind, c.key, c.answered === true, c.title, c.detail, c.canReveal === true, c.peer, c.name, c.size]) : "none";
      if (key !== drawn) {
        drawn = key;
        bar = words = null;
        clear(body);
        if (c) body.append(c.kind === "pair" ? pair(c) : c.kind === "offer" ? offer(c) : c.kind === "receiving" ? receiving(c) : result(c));
      }
      if (c?.kind === "receiving") progress(c);
    },
  };
}
```


**Create `windows/src/island/link.ts`:**

```ts
// What the island does for the link (sub-project G2): when a card comes, goes or changes kind, and when the shelf is on screen. Pure rules over the snapshot, plus two tiny drivers that main.ts
// hands the island to. The island itself changes only by the lines that call these (main.ts) and by `State.linkOfferPending` in two places: the desktop cat's alert and the cats' sleep.

import { State } from "../core/state";
import { cardTransition } from "../link/model.ts";
import type { LinkSnapshot } from "../link/model.ts";
import type { IslandMode, IslandViewName } from "../core/layout";

/** The part of the island the link drives: the island's own methods. */
export interface LinkIslandHost {
  alert(view: IslandViewName): void;
  holdOpen(): void;
  dropPin(): void;
  collapse(): void;
}

/**
 * A card came, went or changed kind. A new card, or one of another kind, opens the island on the link view even when it is hidden (the island's own `alert`), and a card with buttons holds
 * it open against the delayed collapse; when the buttons are gone the hold goes (unless a permission request still holds it); when the card is gone and the link view was showing, the
 * island closes. The order matters: `alert` sets the hold from the permission request, and the link's hold comes after it.
 */
export function linkChanged(host: LinkIslandHost, prev: LinkSnapshot, next: LinkSnapshot, viewIsLink: boolean = State.view === "link", pinnedByRequest: boolean = State.isPinned): void {
  const t = cardTransition(prev.card, next.card, viewIsLink);
  if (t.alert) host.alert("link");
  if (t.hold) host.holdOpen();
  if (t.release && !pinnedByRequest) host.dropPin();
  if (t.collapse) host.collapse();
}

/** The shelf is on screen: its view showing in an open island. Rust looks for the machines only while Devices or the shelf is. */
export function shelfLooking(view: IslandViewName, mode: IslandMode): boolean {
  return view === "shelf" && mode === "expanded";
}

/** Says the shelf is open (or not) when that changes, and not otherwise. */
export class ShelfLook {
  private said: boolean | null = null;
  sync(view: IslandViewName, mode: IslandMode, say: (open: boolean) => void): void {
    const open = shelfLooking(view, mode);
    if (open === this.said) return;
    this.said = open;
    say(open);
  }
}
```


**Create `windows/src/link/devlink.ts`:**

```ts
// The `?dev` page's "Link" panel (sub-project G2), the Windows/Linux counterpart of the Mac's Debug fake peer panel: the real link card inside an island frame, fed by a stand-in link
// (mock.ts) that this panel moves through every state worth looking at, with the island's decision for each change (island/link.ts) and the calls the buttons made. Settings → Devices is
// looked at on `settings.html?linkdev=on` (its style sheet cannot share a page with this one). The shelf's "To a device" bar shows in the Shelf panel: tick two files there, then pick
// "Two machines online" here. Open http://127.0.0.1:1420/?dev with `npx vite` (no Tauri window needed). Only the dev server serves it (cat/dev.ts is loaded behind `import.meta.env.DEV`).

import { BotEngine } from "../cat/engine.ts";
import { PRESETS } from "../cat/presets.ts";
import { State } from "../core/state.ts";
import { VIEW_LAYOUTS } from "../core/layout.ts";
import { buildLink } from "../views/link.ts";
import { THEME } from "../theme.generated.ts";
import { holdsIsland, cardTransition } from "./model.ts";
import { CARDS, ROWS } from "./devseed.ts";
import { mockLinkBackend } from "./mock.ts";

const B = THEME.brand;
const BTN = `font:inherit;font-size:12px;color:${B.ink};background:${B.button};border:1px solid ${B.line};border-radius:8px;padding:4px 10px;cursor:pointer`;

function button(label: string, onclick: () => void): HTMLButtonElement {
  const b = document.createElement("button");
  b.style.cssText = BTN; b.textContent = label; b.onclick = onclick;
  return b;
}

export function mountLinkDev(root: HTMLElement, before: Node | null): void {
  const mock = mockLinkBackend({ visible: true, listening: true, rows: ROWS.two });
  const decisions: string[] = [];
  State.link.attach(mock, (prev, next) => {
    const t = cardTransition(prev.card, next.card, true);
    decisions.push(`${prev.card?.kind ?? "none"} -> ${next.card?.kind ?? "none"}: ${["alert", "hold", "release", "collapse"].filter((k) => t[k as keyof typeof t]).join(" + ") || "nothing"}`);
    paint();
  });
  const view = buildLink();
  view.el.classList.add("on");

  const box = document.createElement("section");
  box.id = "link-dev";
  box.style.cssText = `background:${B.panel};border:1px solid ${B.line};border-radius:16px;padding:16px;margin-bottom:20px`;
  box.innerHTML = `<h2 style="font-size:17px;font-weight:600;margin:0 0 2px">Link (between your machines)</h2>
    <p style="color:${B.dim};margin:0 0 12px;font-size:13px">The link's card in its island, fed by a stand-in service. Each button puts the card in a state; the buttons on the card call the stand-in, which records them below. "The island does" is what island/link.ts decides for each change. Nothing here is the real link: it never opens a socket.</p>`;

  const stage = document.createElement("div");
  stage.style.cssText = "position:relative;width:640px;height:160px;background:#000;border-radius:0 0 22px 22px;overflow:hidden;margin:6px 0 12px";
  const slot = document.createElement("div");
  slot.style.cssText = "position:absolute;left:10px;right:10px;top:42px;bottom:8px";
  slot.append(view.el);
  const cat = document.createElement("canvas");
  const L = VIEW_LAYOUTS.link, D = L.botDiameter / 0.6, dpr = Math.min(2, devicePixelRatio || 1);
  cat.width = Math.round(D * dpr); cat.height = Math.round(D * dpr);
  cat.style.cssText = `position:absolute;left:${L.botX - D / 2}px;top:${88 - D / 2}px;width:${D}px;height:${D}px;pointer-events:none`;
  const engine = new BotEngine(PRESETS.shrimpy, { quiet: true, now: () => 0, rand: () => 0.5 });
  const paintCat = () => {
    const c = cat.getContext("2d")!;
    c.setTransform(dpr, 0, 0, dpr, 0, 0); c.clearRect(0, 0, D, D);
    engine.update(1 / 60); engine.draw(c, D, D);
  };
  stage.append(slot, cat);
  box.append(stage);

  const row = (label: string, ...buttons: HTMLButtonElement[]) => {
    const r = document.createElement("div");
    r.style.cssText = "display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px;align-items:center;font-size:12px";
    r.append(label, ...buttons);
    box.append(r);
  };
  const show = (name: keyof typeof CARDS) => () => mock.set({ card: CARDS[name] });
  row("Pairing:", button("Code", show("pair")), button("Answered", show("pairAnswered")), button("Paired", show("paired")), button("Not paired", show("notPaired")));
  row("Offer:", button("An offer", show("offer")), button("A long name", show("offerLong")), button("Expired", show("expired")));
  row("Receiving:", button("0 %", show("receiving0")), button("45 %", show("receiving45")), button("100 %", show("receiving100")), button("Received", show("received")), button("Cancelled", show("cancelled")), button("Stopped", show("stopped")));
  row("Card:", button("None", () => mock.set({ card: null })));
  row("Machines:", button("Two machines online", () => mock.set({ rows: ROWS.two, visible: true })), button("One offline", () => mock.set({ rows: ROWS.offline })), button("None", () => mock.set({ rows: ROWS.none })));
  row("Sending:", button("Waiting", () => mock.set({ sending: true, sendStatus: "Waiting for Desk PC to accept report.pdf" })), button("45 %", () => mock.set({ sending: true, sendStatus: "Sending report.pdf to Desk PC, 45 %" })), button("Done", () => mock.set({ sending: false, sendStatus: "Finished sending report.pdf to Desk PC" })), button("Clear", () => mock.set({ sending: false, sendStatus: null })));

  const out = document.createElement("pre");
  out.id = "link-dev-out";
  out.style.cssText = `color:${B.dim};font-size:12px;margin:0;white-space:pre-wrap`;
  box.append(out);

  function paint() {
    view.sync();
    const card = State.link.snapshot.card;
    out.textContent = `Card: ${card ? `${card.kind} (holds the island: ${holdsIsland(card)})` : "none"}\nThe island does: ${decisions.slice(-3).join("  |  ") || "nothing yet"}\nCalls: ${mock.calls.slice(-4).join("  |  ") || "none yet"}`;
  }
  State.subscribe(paint);
  paint();
  root.insertBefore(box, before);
  let frames = 0;
  const tick = () => { paintCat(); if (++frames < 30) requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
}
```


- [ ] **Step 2: The additive edits**

```bash
python3 - <<'EOF'
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")

# the link view, registered after the shelf
edit("windows/src/views/views.ts", 'import { buildShelf, type ShelfActions } from "./shelf";', 'import { buildShelf, type ShelfActions } from "./shelf";\nimport { buildLink } from "./link";')
edit("windows/src/views/views.ts", '  map.set("shelf", buildShelf(actions.shelf));\n', '  map.set("shelf", buildShelf(actions.shelf));\n  map.set("link", buildLink());\n')

# cat/dev.ts: the ?dev page's Link panel (the import goes right after the shelf panel's)
import re
p = pathlib.Path("windows/src/cat/dev.ts"); s = p.read_text(encoding="utf-8")
m = re.search(r'^import \{ mountShelfDev \}.*$', s, re.M)
assert m, "the import of mountShelfDev moved"
edit("windows/src/cat/dev.ts", m.group(0), m.group(0) + '\nimport { mountLinkDev } from "../link/devlink.ts";')
edit("windows/src/cat/dev.ts", "  mountShelfDev(root, wrap);\n", "  mountShelfDev(root, wrap);\n  // ── Sub-project G2: the link between your machines ──\n  mountLinkDev(root, wrap);\n")

# main.ts: the backend, the island's rule for a card, the shelf's sight, the dev handle
edit("windows/src/main.ts", 'import { bridgeBackend, mockBackend } from "./shelf/backend";', '''import { bridgeBackend, mockBackend } from "./shelf/backend";
import { bridgeLinkBackend } from "./link/backend";
import { ShelfLook, linkChanged } from "./island/link";
import "./link/link.css";''')
edit("windows/src/main.ts", "  void State.shelf.refresh();\n", '''  void State.shelf.refresh();
  // The link between this machine and the user's others (sub-project G2): Rust's service inside the app, a stand-in on the dev server, nothing in a release build opened in a browser.
  // The snapshot decides what the island does for a card (island/link.ts); the shelf says when it is on screen, so that Rust looks for the machines only then.
  const linkBackend = IS_TAURI ? bridgeLinkBackend() : import.meta.env.DEV ? (await import("./link/mock")).mockLinkBackend() : null;
  if (linkBackend) State.link.attach(linkBackend, (prev, next) => linkChanged(island, prev, next));
  const shelfLook = new ShelfLook();
  State.subscribe(() => shelfLook.sync(State.view, State.mode, (open) => State.link.backend?.setShelfOpen(open)));
''')
edit("windows/src/main.ts", "  if (import.meta.env.DEV) (window as unknown as { __nm: { sk: unknown } }).__nm.sk = Hub.sk;\n", "  if (import.meta.env.DEV) (window as unknown as { __nm: { sk: unknown } }).__nm.sk = Hub.sk;\n  if (import.meta.env.DEV) (window as unknown as { __nm: { link: unknown } }).__nm.link = State.link.backend;\n")
EOF
cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; cd ..
```

Expected: `tsc exit 0` with nothing before it. If `tsc` names `island` as used before its declaration in `main.ts`, the `edit` of `void State.shelf.refresh();` landed above `const island = new Island(root);`: that line is below it in the base this plan was written on (`const island` precedes `State.shelf.attach`), and a different order is a moved tree: stop and report.

- [ ] **Step 3: Start the dev server and look at every card**

Start the dev server as in "How to run" (port 14641). Then write the script and run it:

```bash
mkdir -p .claude/checkpoints/g2-tauri
cat > .claude/checkpoints/g2-tauri/cards.js <<'EOF'
async page => {
  await page.setViewportSize({ width: 1000, height: 1500 });
  await page.goto('http://127.0.0.1:14641/?dev');
  await page.waitForSelector('#link-dev');
  await page.waitForTimeout(1500);
  const box = page.locator('#link-dev');
  const out = '.claude/checkpoints/g2-tauri';
  const list = [['Code','pair'],['Answered','pairAnswered'],['An offer','offer'],['A long name','offerLong'],['0 %','receiving0'],['45 %','receiving45'],['Received','received'],['Paired','paired'],['Not paired','notPaired'],['Expired','expired'],['Cancelled','cancelled'],['Stopped','stopped']];
  for (const [label, file] of list) {
    await box.getByRole('button', { name: label, exact: true }).first().click();
    await page.waitForTimeout(200);
    await box.locator('div').nth(0).screenshot({ path: out + '/card-' + file + '.png' });
  }
  return 'ok';
}
EOF
~/.local/bin/playwright-cli -s=g2 open about:blank >/dev/null 2>&1
~/.local/bin/playwright-cli -s=g2 --raw run-code --filename=.claude/checkpoints/g2-tauri/cards.js | tail -1
ls .claude/checkpoints/g2-tauri/card-*.png | wc -l
```

Expected: `"ok"` and `12`. If `run-code` refuses the relative `out` path, replace `out` by the absolute path of `.claude/checkpoints/g2-tauri` in the script (nothing else). **Look at each picture** and write what you saw in the ledger. What the author of this plan saw in a scratch copy: the cat at the left of a black island strip, a title line, the six digits in large monospace (`483 291`) with the help text beside them and "No" / "They match" under, a long machine name and a long file name both cut with an ellipsis on **one** line each (the offer's explanation is a single line: it was two lines and pushed the title out of the card before it was shortened), a progress bar with `1.1 MB of 2.4 MB, 45 %` and Cancel at the right, and a result with its title, its detail and "OK" (and "Show in folder" for a received file). A card whose text is cut at the top or the bottom, or a button outside the strip, is a bug: fix it in `link.css` or `views/link.ts` (never in a shipped view) and look again.

- [ ] **Step 4: The click rules, in the browser**

```bash
cat > .claude/checkpoints/g2-tauri/clicks.js <<'EOF'
async page => {
  await page.goto('http://127.0.0.1:14641/?dev');
  await page.waitForSelector('#link-dev');
  const box = page.locator('#link-dev');
  await box.getByRole('button', { name: 'An offer', exact: true }).click();
  await box.getByRole('button', { name: 'Accept', exact: true }).click();
  await box.getByRole('button', { name: 'Code', exact: true }).click();
  await box.getByRole('button', { name: 'They match', exact: true }).click();
  const calls = await page.evaluate(() => window.__nm.link.calls ?? null);
  return JSON.stringify(calls);
}
EOF
~/.local/bin/playwright-cli -s=g2 --raw run-code --filename=.claude/checkpoints/g2-tauri/clicks.js | tail -1
```

Expected: a list with `respondOffer` once (accept true, with the offer's `{kind, key}`) and `answerPair` once (yes true, with the pairing card's `{kind, key}`): the stand-in records the card each click carried. (If `calls` prints `null`, read `mock.calls` in `link/mock.ts`: the panel's "Calls:" line at the bottom of the panel shows the same list.)

- [ ] **Step 5: Stop the server, run the checks, commit**

```bash
kill "$(cat .claude/checkpoints/g2-tauri/vite.pid)"; ~/.local/bin/playwright-cli -s=g2 close >/dev/null 2>&1
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:link 2>&1 | grep -E "^ℹ (tests|pass|fail)"
cd ..
git rev-parse --show-toplevel; git branch --show-current
git add windows/src/link windows/src/views/link.ts windows/src/island/link.ts windows/src/views/views.ts windows/src/cat/dev.ts windows/src/main.ts
git commit -F - <<'MSG'
feat(link): the link card, the island's part and the ?dev Link panel (G2-tauri)

One view for the pairing code, an offer, a file coming in and the end of each; every button hands Rust the card it was drawn on, and only the Accept button accepts. A card opens the island and holds it while it has buttons; the dev panel moves a stand-in through every state.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Expected: `tsc exit 0`, `ℹ tests 13`, `ℹ pass 13`, `ℹ fail 0` (the wiring tests arrive in Task 10). Write the task's line in the ledger, with the list of pictures.

---


### Task 10: Settings → Devices and "To a device" on the shelf

**Agent:** `nm-implementer` (Haiku 5.5, high). The files are given in full.

**Files:**
- Create: `windows/src/settings/devices.ts`, `windows/src/views/shelfdevice.ts`, `windows/scripts/link-tests/wiring.test.mjs`
- Modify: `windows/src/shelf/icons.ts`, `windows/src/views/shelf.ts`, `windows/src/settings/main.ts`

**Interfaces:**
- Consumes: Task 8's `LinkBackend`, `State.link`, `sendTargets`, `showDeviceButton`, `devBackend` (Task 9), `link.css` (Task 9).
- Produces: `settings/devices.ts` `devicesSection({ backend, platform }) -> { el }` and `platformOf(navigatorPlatform)`; `views/shelfdevice.ts` `buildDeviceBar() -> { el, sync() }`; `SHELF_ICONS.device`; the wiring pins (`scripts/link-tests/wiring.test.mjs`, 9 tests).

**Settings → Devices.** A new section between Sidekick and General, drawn from Rust's snapshot and in the style of the sections above it (a card, a switch, a text field, a list): **Visible on this network** (the switch: nothing listens and nothing is announced until it is on), the machine's **Name** (Rust refuses a name a card would refuse: `setName` answers `false` and the field shows the old name again), the **Machines** list (a paired machine shows "Paired" or "Paired, not seen" and a Forget button; one that is only seen shows "Available" and a Pair button), why it cannot listen when it cannot (`problem`: for example no Secret Service on Linux, with its sentence), a note (`note`: "Wait 30 seconds before trying again."), the firewall help of the system (`permissionHelp`: Windows Firewall on Windows, UDP 5353 on Linux) and **Received files** (the Downloads folder and "Show folder"). It tells Rust that it is on screen **as a state**: an `IntersectionObserver` on the section calls `setDevicesOpen(true|false)`, and `pagehide` calls `setDevicesOpen(false)`; there is no timer, and Rust forces "not open" when the Settings window hides (Task 13). While it is open and Visible is on, Rust browses; otherwise it does not.

**To a device on the shelf.** `views/shelfdevice.ts` is a new file; `views/shelf.ts` gains four lines (the import, the bar's creation, its element in the head row, its `sync`) and nothing else. The shelf view's own tests stay green because it calls no `.link` and no `Bridge` itself. The button shows only when the link is on or a machine is paired **and** something is ticked; pressing it shows the machines that are paired and online as chips, and pressing a chip hands Rust the ticked **ids** and the machine's id (Rust finds the files; the page never holds a path). A send in progress has one status line with Cancel. Sending always starts with a click.

- [ ] **Step 1: Create the files**

**Create `windows/src/settings/devices.ts`:**

```ts
// Settings → Devices (sub-project G2): whether this machine is visible on the network, the name it shows, the machines it can see or has paired, and where received files go. A new section built
// from the Settings window's own rows (.row, .switch, .hint, button, input): no existing section changes. The section keeps no state of its own: it draws the link's last snapshot
// (Rust's) and every change goes to Rust, which answers with the next snapshot.
//
// "Devices is open" matters to Rust twice: another machine may start a pairing with this one only while it is, and the machines are looked for only while it is. So the section says when
// it is on screen (visible in the window, in a window that is shown) and when it is not, as a state and not as a count: saying it twice changes nothing, and Rust puts it right to "not
// open" whenever the window hides.

import { h, clear } from "../views/dom";
import { permissionHelp, stateWords } from "../link/text.ts";
import type { LinkBackend, LinkRow, LinkSnapshot } from "../link/model.ts";
import { LINK_EMPTY } from "../link/model.ts";

export type Platform = "windows" | "linux" | "other";

export function platformOf(navigatorPlatform: string): Platform {
  return /^win/i.test(navigatorPlatform) ? "windows" : /linux|x11/i.test(navigatorPlatform) ? "linux" : "other";
}

export interface DevicesHost {
  backend: LinkBackend;
  platform: Platform;
}

const NAME_REFUSED = "That name cannot be shown on another machine's card: use 1 to 63 characters, no control or invisible characters, no space at either end.";

function setSwitch(el: HTMLElement, on: boolean): void {
  el.classList.toggle("on", on);
  el.setAttribute("aria-pressed", String(on));
}

const DOT: Record<LinkRow["state"], string> = { pairedOnline: "#22c55e", pairedOffline: "rgba(255,255,255,0.35)", available: "#60a5fa" };

export function devicesSection(host: DevicesHost): { el: HTMLElement; sync(s: LinkSnapshot): void; dispose(): void } {
  const { backend } = host;
  let snap: LinkSnapshot = LINK_EMPTY;
  let forgetting: string | null = null;
  let nameRefused = false;
  let rowsKey = "";

  // Built once: a press changes its switch in place, so keyboard focus stays on it.
  const visible = h("button", { class: "switch", "aria-label": "Visible on this network" });
  visible.addEventListener("click", () => backend.setVisible(!visible.classList.contains("on")));
  const name = h("input", { type: "text", "aria-label": "Name shown to other machines", maxlength: "200", placeholder: "Name shown to other machines" });
  const commitName = async () => {
    const ok = await backend.setName(name.value);
    nameRefused = !ok;
    paintName();
  };
  name.addEventListener("keydown", (e) => { if (e.key === "Enter") void commitName(); });
  name.addEventListener("blur", () => { if (name.value !== snap.name) void commitName(); });
  const nameWarn = h("div", { class: "hint warn", text: NAME_REFUSED });
  const status = h("div", { class: "hint" });
  const list = h("div", { class: "lk-machines" });
  const note = h("div", { class: "hint warn" });
  const folder = h("div", { class: "hint" });

  const el = h(
    "section",
    { id: "devices-section", "data-link": "devices" },
    h("h2", {}, h("span", { text: "Devices" })),
    h("div", { class: "row" }, h("label", { text: "Visible on this network" }), visible),
    h("div", { class: "hint", text: "Other Macs and PCs running NotchMeow can see this one and offer to pair. Until you turn this on, nothing listens and nothing is announced. Only machines you have paired can ever send a file." }),
    h("div", { class: "row" }, h("label", { text: "Name" }), name),
    h("div", { class: "hint", text: "Machines on this network see this name." }),
    nameWarn,
    status,
    h("div", { class: "hint lk-sub", text: "Machines" }),
    list,
    note,
    h("div", { class: "hint", id: "devices-help", text: permissionHelp(host.platform) }),
    h("div", { class: "hint lk-sub", text: "Received files" }),
    h("div", { class: "hint", text: "Files you accept are saved in Downloads/NotchMeow. On Windows they are marked as downloaded from the Internet, and they are never opened for you." }),
    folder,
    h("div", { class: "row" }, h("button", { text: "Show folder", onclick: () => backend.revealFolder() })),
  );

  function paintName() {
    nameWarn.style.display = nameRefused ? "" : "none";
  }

  function paintRows() {
    const key = JSON.stringify([snap.visible, snap.rows, forgetting]);
    if (key === rowsKey) return;
    rowsKey = key;
    clear(list);
    if (!snap.visible && snap.rows.length === 0) {
      list.append(h("div", { class: "hint", text: "Turn on Visible on this network to find machines and pair with them." }));
    } else if (snap.rows.length === 0) {
      list.append(
        h("div", { class: "hint", text: "No machines found" }),
        h("div", { class: "hint", text: "Both machines need NotchMeow running, Visible on this network turned on, and to be on the same network. Some office and guest networks block this." }),
      );
    }
    for (const r of snap.rows) {
      const actions =
        r.state === "available"
          ? [h("button", { class: "primary", text: "Pair", onclick: () => backend.pair(r.id) })]
          : forgetting === r.id
            ? [
                h("button", { class: "danger", text: `Forget ${r.name}?`, onclick: () => { forgetting = null; backend.forget(r.id); } }),
                h("button", { text: "Keep", onclick: () => { forgetting = null; paintRows(); } }),
              ]
            : [h("button", { text: "Forget", onclick: () => { forgetting = r.id; rowsKey = ""; paintRows(); } })];
      list.append(
        h("div", { class: "row lk-machine" },
          h("i", { class: "dot", style: `background:${DOT[r.state]}` }),
          h("span", { class: "lk-mname", text: r.name }),
          h("span", { class: "hint lk-mstate", text: stateWords(r.state) }),
          h("span", { class: "spacer" }),
          ...actions,
        ),
      );
    }
  }

  function sync(next: LinkSnapshot) {
    snap = next;
    setSwitch(visible, snap.visible);
    if (document.activeElement !== name) name.value = snap.name;
    paintName();
    status.style.display = snap.visible || snap.problem ? "" : "none";
    status.className = snap.problem ? "hint warn" : "hint";
    status.textContent = snap.problem ?? (snap.listening ? "Listening on your network." : "Starting…");
    note.style.display = snap.note ? "" : "none";
    note.textContent = snap.note ?? "";
    folder.textContent = snap.folder ? `Folder: ${snap.folder}` : "";
    folder.style.display = snap.folder ? "" : "none";
    paintRows();
  }

  // ── "Devices is open" ──
  // On screen means: the section is in view in the window, the window is shown, and the page is visible. A window that hides is put right by Rust (it says "not open" itself); one that
  // is shown again says so with the focus event.
  let inView = false;
  let said: boolean | null = null;
  const report = () => {
    const open = inView && !document.hidden;
    if (open === said) return;
    said = open;
    backend.setDevicesOpen(open);
  };
  const observer = new IntersectionObserver((entries) => {
    inView = entries.some((e) => e.isIntersecting);
    report();
  }, { threshold: 0.2 });
  observer.observe(el);
  const onVisibility = () => report();
  const onFocus = () => { said = null; report(); };
  document.addEventListener("visibilitychange", onVisibility);
  window.addEventListener("focus", onFocus);
  window.addEventListener("pagehide", () => backend.setDevicesOpen(false));

  const off = backend.onSnapshot(sync);
  void backend.state().then(sync).catch(() => {});
  sync(LINK_EMPTY);

  return {
    el,
    sync,
    dispose() {
      off();
      observer.disconnect();
      document.removeEventListener("visibilitychange", onVisibility);
      window.removeEventListener("focus", onFocus);
      backend.setDevicesOpen(false);
    },
  };
}
```


**Create `windows/src/views/shelfdevice.ts`:**

```ts
// "To a device" on the shelf's head row (sub-project G2): an icon-only button that shows when the link is on or a machine is paired and something is ticked, the machines to send to (chips)
// when it is pressed, and the one status line of a send in progress with its Cancel. A new file the shelf view includes; the shelf's own buttons and tiles are untouched. The shelf holds ids
// and never a path: pressing a chip hands Rust the ticked ids and the machine's id, and Rust finds the files. Sending always starts with a click.

import { h, svg, clear } from "./dom";
import { Bridge } from "../core/bridge";
import { State } from "../core/state";
import { SHELF_ICONS } from "../shelf/icons";
import { sendTargets, showDeviceButton } from "../link/model.ts";

/** Names this wide are cut short with an ellipsis (a chip can carry any name). */
const CHIP_MAX = "9em";

export function buildDeviceBar(): { el: HTMLElement; sync(): void } {
  let choosing = false;
  const status = h("span", { class: "lk-line" });
  const cancel = h("button", { class: "lk-cancel", title: "Stop sending", "aria-label": "Cancel sending", text: "Cancel", onclick: () => State.link.backend?.cancelSending() });
  const button = h("button", { class: "btn secondary sh-small lk-devbtn", title: "To a device", "aria-label": "Send to a device", onclick: () => { choosing = !choosing; sync(); } }, svg(SHELF_ICONS.device, 14, { stroke: 1.7 }));
  const chips = h("span", { class: "lk-chips" });
  const el = h("span", { class: "lk-devbar" }, status, cancel, button, chips);
  let key = "";

  function sync() {
    const snap = State.link.snapshot;
    const selected = [...State.shelf.selected];
    const canSend = showDeviceButton(snap) && selected.length > 0;
    // Nothing ticked, or no device button to open the machines from: the chips close, so a later selection shows the buttons and not the chips.
    if (!canSend) choosing = false;
    el.parentElement?.classList.toggle("sh-choosing", choosing);
    status.textContent = snap.sendStatus ?? "";
    status.style.display = snap.sendStatus && !choosing ? "" : "none";
    cancel.style.display = snap.sending && !choosing ? "" : "none";
    button.style.display = canSend && !choosing ? "" : "none";
    chips.style.display = choosing ? "" : "none";
    const next = JSON.stringify([choosing, snap.rows, selected.length]);
    if (next === key) return;
    key = next;
    clear(chips);
    if (!choosing) return;
    const targets = snap.rows.filter((r) => r.state !== "available");
    for (const r of targets) {
      const online = r.state === "pairedOnline";
      chips.append(
        h("button", {
          class: online ? "btn secondary sh-small lk-chip" : "btn secondary sh-small lk-chip off",
          title: online ? `Send to ${r.name}` : `${r.name} is not on the network`,
          disabled: !online,
          style: `max-width:${CHIP_MAX}`,
          text: r.name,
          onclick: () => {
            choosing = false;
            State.link.backend?.send([...State.shelf.selected], r.id);
            sync();
          },
        }),
      );
    }
    if (sendTargets(snap.rows).length === 0) {
      chips.append(
        h("span", { class: "lk-none", text: targets.length ? "No paired machine is on the network." : "Pair a machine in Settings → Devices." }),
        h("button", { class: "btn secondary sh-small", text: "Open Devices", onclick: () => void Bridge.openSettingsWindow() }),
      );
    }
    chips.append(h("button", { class: "btn secondary sh-small lk-close", title: "Back", "aria-label": "Close the list of machines", text: "×", onclick: () => { choosing = false; sync(); } }));
  }

  return { el, sync };
}
```


**Create `windows/scripts/link-tests/wiring.test.mjs`:**

```js
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Where the link (G2) is wired into the page, pinned as source text: no test program can run the island's DOM, so these say what must stay true. What the cards look like is looked at in the `?dev`
// page's Link panel and in settings.html?linkdev=on (the checkpoint's pictures).
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const walk = (dir) => fs.readdirSync(new URL(`../../src/${dir}`, import.meta.url), { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(`${dir}${e.name}/`) : [`${dir}${e.name}`]));
const all = walk("").filter((f) => f.endsWith(".ts"));
/** The code of a source file without its comments, for the checks that read what the code does and not what it says. */
const code = (rel) => source(rel).replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");

test("the link view is new: registered after the shelf, laid out like the approval card, and no other view is touched", () => {
  const views = source("views/views.ts");
  assert.match(views, /import \{ buildLink \} from "\.\/link";/);
  assert.match(views, /map\.set\("shelf", buildShelf\(actions\.shelf\)\);\s*map\.set\("link", buildLink\(\)\);/);
  const layout = source("core/layout.ts");
  assert.match(layout, /\| "shelf"\s*\| "link";/);
  assert.match(layout, /link: \{ height: 160, botX: 62, botY: null, botDiameter: 56, agentMode: "column" \},/);
  assert.doesNotMatch(source("views/upload.ts"), /link/i, "the upload views are not touched");
});

test("the card never accepts for the user: the only call that says yes to an offer is the Accept button", () => {
  const callers = all.filter((f) => /\brespondOffer\(\s*true/.test(source(f)));
  assert.deepEqual(callers, ["views/link.ts"]);
  const view = source("views/link.ts");
  assert.match(view, /btn\("Accept", "primary", \(\) => backend\(\)\?\.respondOffer\(true, shownOf\(c\)\)\)/);
  assert.match(view, /btn\("Decline", "secondary", \(\) => backend\(\)\?\.respondOffer\(false, shownOf\(c\)\)\)/);
  assert.doesNotMatch(view, /setInterval|setTimeout|requestAnimationFrame|Bridge|invoke\(/, "the view draws; it has no timer and calls nothing out but through the backend");
});

test("every button of a card hands back the card it was drawn on", () => {
  const view = source("views/link.ts");
  for (const call of ["answerPair(false", "answerPair(true", "respondOffer(false", "respondOffer(true", "cancelReceiving(", "dismiss("]) {
    const at = view.indexOf(call);
    assert.ok(at > 0, call);
    assert.match(view.slice(at, at + 90), /shownOf\(c\)/, call);
  }
});

test("the shelf's device bar is a new file the shelf view includes; the shelf view itself gains four lines and calls nothing out", () => {
  const shelf = source("views/shelf.ts");
  assert.match(shelf, /import \{ buildDeviceBar \} from "\.\/shelfdevice";/);
  assert.match(shelf, /const device = buildDeviceBar\(\);/);
  assert.match(shelf, /h\("div", \{ class: "sh-head" \}, title, count, device\.el, h\("span", \{ class: "sh-spacer" \}\), sendMany, clearAll\)/);
  assert.match(shelf, /sync\(\) \{\s*device\.sync\(\);/);
  assert.doesNotMatch(shelf, /\.link|Bridge/, "the shelf view's own pin: no call out; the device bar is the other file");
  const bar = source("views/shelfdevice.ts");
  assert.match(bar, /State\.link\.backend\?\.send\(\[\.\.\.State\.shelf\.selected\], r\.id\)/, "ids of the shelf and the machine's id; never a path");
  assert.doesNotMatch(bar, /setInterval|setTimeout|requestAnimationFrame|\.path\b/);
  assert.match(source("shelf/icons.ts"), /device: "M5 6h14v9H5zM2 19h20",/);
});

test("the page hands Rust ids, never a path, a key or an address", () => {
  assert.match(source("link/backend.ts"), /send: \(ids, to\) => post\("link_send", \{ ids, to \}\),/);
  assert.doesNotMatch(code("link/backend.ts"), /path|address|hostname|secret/i);
  assert.doesNotMatch(code("link/model.ts"), /\bpath\b|address/i);
});

test("main.ts attaches the backend, tells the island about a card, and says when the shelf is on screen; the mock and the dev seeds load only on the dev server", () => {
  const main = source("main.ts");
  assert.match(main, /import \{ bridgeLinkBackend \} from "\.\/link\/backend";/);
  assert.match(main, /import \{ ShelfLook, linkChanged \} from "\.\/island\/link";/);
  assert.match(main, /import "\.\/link\/link\.css";/);
  assert.match(main, /const linkBackend = IS_TAURI \? bridgeLinkBackend\(\) : import\.meta\.env\.DEV \? \(await import\("\.\/link\/mock"\)\)\.mockLinkBackend\(\) : null;/);
  assert.match(main, /State\.link\.attach\(linkBackend, \(prev, next\) => linkChanged\(island, prev, next\)\);/);
  assert.match(main, /State\.subscribe\(\(\) => shelfLook\.sync\(State\.view, State\.mode, \(open\) => State\.link\.backend\?\.setShelfOpen\(open\)\)\);/);
  const settings = source("settings/main.ts");
  assert.match(settings, /const linkdev = import\.meta\.env\.DEV \? new URLSearchParams\(location\.search\)\.get\("linkdev"\) : null;/);
  assert.match(settings, /\(await import\("\.\.\/link\/devseed"\)\)\.devBackend\(linkdev\)/);
  assert.match(settings, /sidekick\.el,\s*devices\.el,\s*generalSection\(\),/);
  assert.match(source("cat/dev.ts"), /mountLinkDev\(root, wrap\);/);
  const importers = all.filter((f) => /from "\.{1,2}\/(link\/)?(mock|devseed|devlink)(\.ts)?"/.test(source(f)));
  assert.deepEqual(importers.sort(), ["cat/dev.ts", "link/devlink.ts", "link/devseed.ts"].sort(), "static imports of the stand-in are the dev panel's alone; main.ts and settings use a dynamic import behind DEV");
});

test("the style sheet only gains lk- rules and one modifier of the shelf head; no rule of a shipped view changes", () => {
  const css = source("link/link.css").replace(/\/\*[\s\S]*?\*\//g, "");
  const selectors = [...css.matchAll(/([^{}]+)\{/g)].flatMap((m) => m[1].split(",").map((s) => s.trim()));
  assert.ok(selectors.length > 20);
  for (const s of selectors) assert.match(s, /^(\.lk-[\w-]+(\.off)?|\.lk-body \.btn:disabled|\.lk-pairrow \.sub|\.sh-head\.sh-choosing > :not\(\.sh-title\):not\(\.lk-devbar\))$/, s);
});

test("Settings → Devices says when it is on screen as a state, from the section's visibility, and has no timer", () => {
  const dev = source("settings/devices.ts");
  assert.match(dev, /new IntersectionObserver\(/);
  assert.match(dev, /backend\.setDevicesOpen\(open\)/);
  assert.match(dev, /window\.addEventListener\("pagehide", \(\) => backend\.setDevicesOpen\(false\)\)/);
  assert.doesNotMatch(dev, /setInterval|setTimeout|requestAnimationFrame/);
  assert.match(dev, /btn|h\("button", \{ class: "switch"/);
});

test("the island's part: a card opens it, a card with buttons holds it, the shelf's sight is a state; no timer in island/link.ts", () => {
  const isl = source("island/link.ts");
  assert.match(isl, /if \(t\.alert\) host\.alert\("link"\);\s*if \(t\.hold\) host\.holdOpen\(\);\s*if \(t\.release && !pinnedByRequest\) host\.dropPin\(\);\s*if \(t\.collapse\) host\.collapse\(\);/);
  assert.doesNotMatch(isl, /setInterval|setTimeout|requestAnimationFrame/);
});
```


- [ ] **Step 2: Run the wiring tests before the edits (they must fail)**

```bash
cd windows
node --experimental-strip-types --test --test-reporter=spec scripts/link-tests/wiring.test.mjs 2>&1 | grep -E "^ℹ (tests|pass|fail)"
cd ..
```

Expected: `ℹ tests 9` and `ℹ fail` above 0 (the shelf, the icon and Settings are not wired yet).

- [ ] **Step 3: The additive edits**

```bash
python3 - <<'EOF'
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")

# the laptop icon
edit("windows/src/shelf/icons.ts", '  check: "M5 12.5 10 17.5 19 7",\n', '  check: "M5 12.5 10 17.5 19 7",\n  // a laptop (To a device, sub-project G2)\n  device: "M5 6h14v9H5zM2 19h20",\n')

# the shelf: four lines
edit("windows/src/views/shelf.ts", 'import type { ViewHost } from "./views";', 'import type { ViewHost } from "./views";\nimport { buildDeviceBar } from "./shelfdevice";')
edit("windows/src/views/shelf.ts", '  const tiles = h("div", { class: "sh-tiles" });\n', '  const device = buildDeviceBar();\n  const tiles = h("div", { class: "sh-tiles" });\n')
edit("windows/src/views/shelf.ts", 'h("div", { class: "sh-head" }, title, count, h("span", { class: "sh-spacer" }), sendMany, clearAll)', 'h("div", { class: "sh-head" }, title, count, device.el, h("span", { class: "sh-spacer" }), sendMany, clearAll)')
edit("windows/src/views/shelf.ts", "    sync() {\n      const s = State.shelf, caps = State.shelfCaps;\n", "    sync() {\n      const s = State.shelf, caps = State.shelfCaps;\n      device.sync();\n")

# Settings: the section, between Sidekick and General
edit("windows/src/settings/main.ts", 'import { sidekickSection } from "./sidekick";', '''import { sidekickSection } from "./sidekick";
import { devicesSection, platformOf } from "./devices";
import { bridgeLinkBackend } from "../link/backend";
import "../link/link.css";''')
edit("windows/src/settings/main.ts", '  clear(root);\n  root.append(\n    h("h1", {}, h("span", { text: "NotchMeow" })', '''  // Settings → Devices (sub-project G2): drawn from Rust's link snapshot, and it tells Rust when it is on screen.
  // On the dev server, `settings.html?linkdev=on` (or off, empty, problem, note) draws the section from a stand-in, for looking at it without the app.
  const linkdev = import.meta.env.DEV ? new URLSearchParams(location.search).get("linkdev") : null;
  const devices = devicesSection({ backend: linkdev ? (await import("../link/devseed")).devBackend(linkdev) : bridgeLinkBackend(), platform: platformOf(navigator.platform) });

  clear(root);
  root.append(
    h("h1", {}, h("span", { text: "NotchMeow" })''')
edit("windows/src/settings/main.ts", "    sidekick.el,\n", "    sidekick.el,\n    devices.el,\n")
EOF
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:link 2>&1 | grep -E "^ℹ (tests|pass|fail)"
cd ..
```

Expected: `tsc exit 0`; `ℹ tests 22`, `ℹ pass 22`, `ℹ fail 0` (10 model, 3 alert, 9 wiring). If the `shelf.ts` test of the shelf (`windows/scripts/` has none for it, but `npm run check:cat` and the dev panel use the view) shows a difference, the shelf view's only changes are these four lines.

- [ ] **Step 4: Prove it bites**

```bash
cd windows
M="python3 ../.claude/checkpoints/g2-tauri/mut.py node"
$M src/views/link.ts 'btn("Accept", "primary", () => backend()?.respondOffer(true, shownOf(c)))' 'btn("Accept", "primary", () => backend()?.respondOffer(true, null))' scripts/link-tests/wiring.test.mjs
$M src/settings/devices.ts 'window.addEventListener("pagehide", () => backend.setDevicesOpen(false))' '0' scripts/link-tests/wiring.test.mjs
$M src/island/link.ts 'if (t.hold) host.holdOpen();' '' scripts/link-tests/wiring.test.mjs
cd ..
```

Expected: each prints `# fail` above 0 (a card whose click does not name its card; a Settings window that never says it left; a card with buttons that does not hold the island).

- [ ] **Step 5: Look at Settings → Devices and the shelf's button**

Start the dev server (port 14641) and run:

```bash
cat > .claude/checkpoints/g2-tauri/devices.js <<'EOF'
async page => {
  await page.setViewportSize({ width: 760, height: 1400 });
  const out = '.claude/checkpoints/g2-tauri';
  for (const s of ['off', 'on', 'empty', 'problem', 'note']) {
    await page.goto('http://127.0.0.1:14641/settings.html?linkdev=' + s);
    await page.waitForTimeout(1000);
    const h = page.getByText('Visible on this network').first();
    await h.scrollIntoViewIfNeeded();
    const sec = h.locator('xpath=ancestor::*[contains(@class,"card") or self::section][1]');
    await sec.screenshot({ path: out + '/devices-' + s + '.png' });
  }
  return 'ok';
}
EOF
~/.local/bin/playwright-cli -s=g2 open about:blank >/dev/null 2>&1
~/.local/bin/playwright-cli -s=g2 --raw run-code --filename=.claude/checkpoints/g2-tauri/devices.js | tail -1
```

Expected: `"ok"` and five pictures. **Look at them.** What the author saw in a scratch copy for `on`: the card titled Devices with the switch "Visible on this network" on, the explanation, the Name field ("Desk PC"), "Listening on your network.", then Machines: a green dot "Sam's MacBook Pro  Paired" and "Studio laptop  Paired" each with Forget at the right, a grey dot "Old netbook  Paired, not seen" with Forget, a blue dot "Desk PC  Available" with a white Pair button, the firewall sentence, and "Received files" with the folder and "Show folder". For `problem` the sentence of the problem shows in place of "Listening on your network."; for `off` the list is hidden and nothing says it is listening.

Then the shelf's button: open `http://127.0.0.1:14641/?dev` in the session, press **Drop 3 files** and **Tick two** in the Shelf panel, then **Two machines online** in the Link panel, and take a picture of the Shelf panel (`#shelf-dev`): the head row of the shelf shows a small laptop button next to the count; pressing it shows two chips (`Sam's MacBook Pro`, `Studio laptop`: the paired machines that are online; the offline one is not offered) and hides the Clear all button while the chips are open; pressing a chip adds a line to the Link panel's "Calls:" (`send` with the two ids and the machine's id, no path). With nothing ticked there is no laptop button. Close the session and stop the server.

- [ ] **Step 6: Commit**

```bash
kill "$(cat .claude/checkpoints/g2-tauri/vite.pid)"; ~/.local/bin/playwright-cli -s=g2 close >/dev/null 2>&1
git rev-parse --show-toplevel; git branch --show-current
git add windows/src/settings/devices.ts windows/src/views/shelfdevice.ts windows/scripts/link-tests/wiring.test.mjs windows/src/shelf/icons.ts windows/src/views/shelf.ts windows/src/settings/main.ts
git commit -F - <<'MSG'
feat(link): Settings -> Devices and "To a device" on the shelf (G2-tauri)

The Devices section (Visible, Name, Machines with Pair and Forget, the system's firewall help, Received files) says as a state when it is on screen; the shelf's head row gets a "To a device" button in a new file, and a send has one status line with Cancel. Wiring tests pin that only the Accept button accepts, that every button names its card, and that no shipped view's style changes.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Write the task's line in the ledger.

---

## Checkpoint 1: the owner looks at the pictures

**Who:** the executing session (it sends the pictures) and the owner (who answers). Nothing is built after Task 10 until the owner has answered, because the card's words and the Devices section are what the owner will live with; the Rust tasks that follow do not change them.

**Pictures to send** (all from `.claude/checkpoints/g2-tauri/`, rendered from the dev server, never the real app): `card-pair.png`, `card-pairAnswered.png`, `card-offer.png`, `card-offerLong.png`, `card-receiving45.png`, `card-received.png`, `card-paired.png`, `card-notPaired.png`, `card-expired.png`, `card-cancelled.png`, `card-stopped.png`, `devices-on.png`, `devices-off.png`, `devices-problem.png`, and the shelf's head row with two files ticked, with and without the chips.

**What to ask:**
1. Are the words right? In particular "`<machine>` wants to send you a file", "Saved in Downloads/NotchMeow, never opened. Declined after 2 minutes.", and the results ("Received", "Not paired", "Offer expired", "Transfer cancelled", "Transfer stopped"). Are they the same as the Mac's, where a card is the same?
2. Is the Devices section where and how the owner wants it (between Sidekick and General, one card)?
3. On Windows the Mac's Show in Finder is "Show in folder": fine?

Record the answers in the ledger and apply a change as a fix commit to `link.css`, `views/link.ts` or `settings/devices.ts` (never to a shipped view) before Task 11.

---


### Task 11: The conversations: channel, pairing run, transfer runs, the recorded conversations

**Agent:** `nm-implementer-deep` (**Sonnet 5.5, high; CLAUDE.md trigger 1**: async concurrency and the timers that keep a stranger from holding a connection). Add `superpowers:systematic-debugging` to the skills. The code is given in full; if a test fails against the real `snow`, the executor debugs it, it does not weaken the test.

**Files:**
- Create: `windows/src-tauri/src/link/channel.rs`, `pair_run.rs`, `transfer.rs`, `conformance.rs`
- Modify: `windows/src-tauri/src/link/mod.rs`

**Interfaces:**
- Consumes: Tasks 2 to 7 (`noise::{Handshake, Pattern, PROLOGUE, FIXED_EPHEMERAL}`, `frames`, `pairing`, `flow`, `cards`, `identity`, `files`).
- Produces:
  - `channel::{Transport (async trait: send(Vec<u8>), receive() -> Vec<u8>, close(), abort()), MemoryEnd::pair(), Channel<T>, IdleWatch, FrameWindow, LinkError, handshake_send, handshake_receive}`. `Transport` carries whole records (the real one, Task 12, cuts a TCP stream into u16-length records). `Channel::send_within(frame, grace_ms)` and `send_best_effort` give a frame this long and then cut the connection, so a peer that stopped reading cannot hold a conversation in a send. `IdleWatch` is a one-shot timer that exists only while its phase lasts; `FrameWindow` hands on at most 4 frames the conversation has not taken yet.
  - `pair_run::{run_incoming, run_initiator, run_responder, PairHooks { show_code, handshake_done }, PairHandle { answer(bool), cancel() }, PairInbox, pair_channel(), PairOutcome, Clock}`: one pairing conversation on either side, a thin I/O wrapper around `pairing::{Responder, Initiator}`; `run_incoming` also asks the **gate** (`pairing::Gate`) first and, outside it, sends nothing and shows nothing.
  - `transfer::{run_receive, run_send, receive_channel(), send_channel(), ReceiveHooks { offered, progress, claim, release, handshake_done, admit, release_at_end }, ReceiveTimings, SendHooks, SendTimings, ReceiveHandle { respond(bool), cancel(), holds_claim() }, SendHandle { cancel() }, TransferOutcome { Completed(Option<PathBuf>), Declined{reason}, Expired, Cancelled, Withdrawn, Aborted(String) }, Offer}`. The runs call `flow::connection_step` directly, so one machine-made decline per connection, the 10 s first-frame clock and the machine's one transfer place (`claim`) are run where they are tested. **Only `ReceiveHandle::respond(true)` accepts, and it is called from the Accept button's command alone.**
  - `conformance` (test only): the recorded conversations of `noise-vectors.json` played through the real runs.

**The numbers every wait has** (the Mac's reviews arrived at them; `the_default_watches_are_the_macs_and_the_reviews_numbers` and `four_frames_may_wait_for_the_conversation` pin them): first frame after the handshake 10 s; chunk stall 60 s; the offer a user may leave unanswered 2 minutes (the receiver's), 130 s for the sender to give up on its own; a frame this side sends is waited for 2 s; the sender's handshake 10 s; 4 frames in the window. Nothing in these files sleeps in a loop or polls: every wait is one `tokio::time::timeout` or one `IdleWatch`.

**The recorded conversations (the cross-check that can run in a container).** `tests/fixtures/link/noise-vectors.json` holds conversations the Mac's CryptoKit code produced and an independent implementation confirmed (`tests/link-crosscheck/`). `conformance.rs` pins the next handshake's ephemeral key on the test thread (`FIXED_EPHEMERAL`), starts each **real run** with the vector's keys, nonces and names, and plays the recording as the other side: what the run writes must be the recording's bytes (the commitment, the two hellos, the preamble, the Noise messages), what it shows must be the recorded six digits. So the Windows/Linux app and the Mac app agree byte for byte on pairing and on the transfer handshake without ever running together. The vector's transport payloads are test bytes and not frames, so each replay stops after the handshake: the frames after it are covered by this task's loopback tests, and the two apps' agreement on them by the real-machine check (Task 16) and by the contract's frame fixtures (Task 3).

- [ ] **Step 1: Register the modules**

Run:

```bash
python3 - <<'EOF'
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")
edit("windows/src-tauri/src/link/mod.rs", "// MODULES: add new modules above this line", "pub mod channel;\npub mod pair_run;\npub mod transfer;\n// MODULES: add new modules above this line")
edit("windows/src-tauri/src/link/mod.rs", "#[cfg(test)]\npub(crate) mod testutil;", "#[cfg(test)]\nmod conformance;\n\n#[cfg(test)]\npub(crate) mod testutil;")
EOF
```

- [ ] **Step 2: The files**

**Create `windows/src-tauri/src/link/channel.rs`:**

```rust
// The link's connection layer (sub-project G2): a transport that carries whole records, and the channel that puts Noise transport messages and frames on it, with the small helpers every
// conversation uses to make sure nothing waits for ever. No socket in this file: the real transport (`net.rs`) cuts a TCP stream into records, and the tests use `MemoryEnd`. The Mac's
// twin is LinkChannel.swift.

use std::future::Future;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex as StdMutex};

use tokio::sync::{mpsc, Mutex, Notify, Semaphore};
use tokio::time::{Duration, Instant};

use super::frames::{self, Frame, FrameError, NOISE_MAX};
use super::noise::{Handshake, NoiseError, Transport as NoiseTransport};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LinkError {
    Closed,
    /// The other side broke the protocol, or a message did not open.
    Violation(String),
    Io(String),
}

impl std::fmt::Display for LinkError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            LinkError::Closed => f.write_str("closed"),
            LinkError::Violation(s) => write!(f, "violation: {s}"),
            LinkError::Io(s) => write!(f, "io: {s}"),
        }
    }
}

impl std::error::Error for LinkError {}

impl From<NoiseError> for LinkError {
    fn from(e: NoiseError) -> LinkError {
        LinkError::Violation(format!("noise {e}"))
    }
}

impl From<FrameError> for LinkError {
    fn from(e: FrameError) -> LinkError {
        LinkError::Violation(format!("frame {e}"))
    }
}

/// Carries whole records (one record is one Noise message, or the preamble): `send` takes a record's bytes, 1 to 65535 of them, and `receive` gives the bytes of the next whole record without the
/// length prefix that the wire puts in front (`frames::encode_record`, which the real transport applies). `receive` fails when the other end has closed.
pub trait Transport: Send + Sync + 'static {
    fn send(&self, record: Vec<u8>) -> impl Future<Output = Result<(), LinkError>> + Send;
    fn receive(&self) -> impl Future<Output = Result<Vec<u8>, LinkError>> + Send;
    /// Flushes what was sent and closes. Calling it twice is harmless.
    fn close(&self) -> impl Future<Output = ()> + Send;
    /// Hard stop, from any task: nothing is flushed, and a send or a read that is pending fails at once. For a peer that stopped reading (a `close` would wait behind its stalled bytes).
    fn abort(&self);
}

/// A one-shot deadline that activity pushes back: it fires `fire` once, `ms` milliseconds after the last `touch` (or after it was made), and then it is over. It never polls: it sleeps for
/// the time that is left, wakes once, and either fires or sleeps for what is left again. Made when something is pending, stopped when it is not (`stop`, or by being dropped), so nothing
/// sleeps for a conversation that ended. Must be made inside a tokio runtime.
pub struct IdleWatch {
    state: Arc<WatchState>,
    task: tokio::task::JoinHandle<()>,
}

struct WatchState {
    last: StdMutex<Instant>,
    over: AtomicBool,
}

impl IdleWatch {
    pub fn new(ms: u64, fire: impl FnOnce() + Send + 'static) -> IdleWatch {
        IdleWatch::on(&tokio::runtime::Handle::current(), ms, fire)
    }

    /// The same on a given runtime, for a caller that is not inside one (a click arriving from the window's own thread).
    pub fn on(runtime: &tokio::runtime::Handle, ms: u64, fire: impl FnOnce() + Send + 'static) -> IdleWatch {
        let state = Arc::new(WatchState { last: StdMutex::new(Instant::now()), over: AtomicBool::new(false) });
        let s = state.clone();
        let limit = Duration::from_millis(ms);
        let task = runtime.spawn(async move {
            loop {
                if s.over.load(Ordering::SeqCst) {
                    return;
                }
                let left = limit.saturating_sub(s.last.lock().unwrap().elapsed());
                if left.is_zero() {
                    if !s.over.swap(true, Ordering::SeqCst) {
                        fire();
                    }
                    return;
                }
                tokio::time::sleep(left).await;
            }
        });
        IdleWatch { state, task }
    }

    /// Something happened: the deadline moves.
    pub fn touch(&self) {
        *self.state.last.lock().unwrap() = Instant::now();
    }

    pub fn stop(&self) {
        self.state.over.store(true, Ordering::SeqCst);
        self.task.abort();
    }
}

impl Drop for IdleWatch {
    fn drop(&mut self) {
        self.stop();
    }
}

/// How many frames a reader may have handed on and not yet seen taken. The reader asks for a place (`take`) before it reads the next frame, and the conversation gives it back (`give`) when it
/// takes the frame from its queue, so a peer that sends faster than the conversation works leaves its bytes in the socket (where TCP slows it down), not in memory.
#[derive(Clone)]
pub struct FrameWindow {
    free: Arc<Semaphore>,
}

impl FrameWindow {
    pub const FRAMES: usize = 4;

    pub fn new() -> FrameWindow {
        FrameWindow { free: Arc::new(Semaphore::new(Self::FRAMES)) }
    }
    /// False when the conversation is over and the reader should stop.
    pub async fn take(&self) -> bool {
        match self.free.acquire().await {
            Ok(p) => {
                p.forget();
                true
            }
            Err(_) => false,
        }
    }
    pub fn give(&self) {
        self.free.add_permits(1);
    }
    /// The conversation is over: a reader that is waiting for a place is let go.
    pub fn close(&self) {
        self.free.close();
    }
}

impl Default for FrameWindow {
    fn default() -> FrameWindow {
        FrameWindow::new()
    }
}

/// Frames over an established Noise session. One sender at a time: a frame is encrypted and handed to the transport under a lock that is released in call order, so the nonces go out in the
/// order they were taken (a second sender waits for its turn, first come first served).
pub struct Channel<T: Transport> {
    transport: Arc<T>,
    noise: StdMutex<NoiseTransport>,
    send_turn: Mutex<()>,
}

impl<T: Transport> Channel<T> {
    pub fn new(transport: Arc<T>, noise: NoiseTransport) -> Channel<T> {
        Channel { transport, noise: StdMutex::new(noise), send_turn: Mutex::new(()) }
    }

    pub fn transport(&self) -> &Arc<T> {
        &self.transport
    }

    pub async fn send_frame(&self, frame: &Frame) -> Result<(), LinkError> {
        let _turn = self.send_turn.lock().await;
        let sealed = self.noise.lock().unwrap().encrypt(&frames::encode_frame(frame)?)?;
        self.transport.send(sealed).await
    }

    /// The next frame. A message that does not open, a frame that does not decode and a closed transport all end the conversation with an error.
    pub async fn receive_frame(&self) -> Result<Frame, LinkError> {
        let record = self.transport.receive().await?;
        let plain = self.noise.lock().unwrap().decrypt(&record)?;
        Ok(frames::decode_frame(&plain)?)
    }

    /// Sends one frame and waits for it no longer than `grace_ms`: the connection may be stuck behind bytes the peer does not read, and a conversation that waited for ever would hold everything it
    /// holds (a place among the connections, the transfer place). After the grace the transport is cut, which fails the stuck send and every read, and the conversation ends.
    pub async fn send_within(&self, frame: &Frame, grace_ms: u64) -> Result<(), LinkError> {
        let t = self.transport.clone();
        let cut = IdleWatch::new(grace_ms, move || t.abort());
        let sent = self.send_frame(frame).await;
        cut.stop();
        sent
    }

    /// `send_within` for a frame whose failure the conversation learns of anyway, from its reader.
    pub async fn send_best_effort(&self, frame: &Frame, grace_ms: u64) {
        let _ = self.send_within(frame, grace_ms).await;
    }

    pub async fn close(&self) {
        self.transport.close().await;
    }
}

/// Handshake messages over a transport, one record each.
pub async fn handshake_send<T: Transport>(t: &T, hs: &mut Handshake, payload: &[u8]) -> Result<(), LinkError> {
    let message = hs.write(payload)?;
    if message.is_empty() || message.len() > NOISE_MAX {
        return Err(LinkError::Violation("handshake length".into()));
    }
    t.send(message).await
}

pub async fn handshake_receive<T: Transport>(t: &T, hs: &mut Handshake) -> Result<Vec<u8>, LinkError> {
    let message = t.receive().await?;
    Ok(hs.read(&message)?)
}

/// Two ends of an in-memory connection, for the tests (no sockets, no network). Records come out in the order they went in; after `close` the other end
/// reads what was already sent and then sees the end.
pub struct MemoryEnd {
    tx: StdMutex<Option<mpsc::UnboundedSender<Vec<u8>>>>,
    rx: Mutex<mpsc::UnboundedReceiver<Vec<u8>>>,
    closed: AtomicBool,
    cut: Notify,
}

impl MemoryEnd {
    pub fn pair() -> (Arc<MemoryEnd>, Arc<MemoryEnd>) {
        let (a_tx, b_rx) = mpsc::unbounded_channel();
        let (b_tx, a_rx) = mpsc::unbounded_channel();
        let end = |tx, rx| Arc::new(MemoryEnd { tx: StdMutex::new(Some(tx)), rx: Mutex::new(rx), closed: AtomicBool::new(false), cut: Notify::new() });
        (end(a_tx, a_rx), end(b_tx, b_rx))
    }

    fn shut(&self) {
        self.closed.store(true, Ordering::SeqCst);
        self.tx.lock().unwrap().take();
        self.cut.notify_waiters();
    }
}

impl Transport for MemoryEnd {
    async fn send(&self, record: Vec<u8>) -> Result<(), LinkError> {
        if record.is_empty() || record.len() > NOISE_MAX {
            return Err(LinkError::Violation("record length".into())); // what the real transport's length prefix would refuse
        }
        if self.closed.load(Ordering::SeqCst) {
            return Err(LinkError::Closed);
        }
        match self.tx.lock().unwrap().as_ref() {
            Some(tx) => tx.send(record).map_err(|_| LinkError::Closed),
            None => Err(LinkError::Closed),
        }
    }

    async fn receive(&self) -> Result<Vec<u8>, LinkError> {
        let mut rx = self.rx.lock().await;
        loop {
            if let Ok(record) = rx.try_recv() {
                return Ok(record);
            }
            if self.closed.load(Ordering::SeqCst) {
                return Err(LinkError::Closed);
            }
            tokio::select! {
                got = rx.recv() => return got.ok_or(LinkError::Closed),
                _ = self.cut.notified() => {}
            }
        }
    }

    async fn close(&self) {
        self.shut();
    }

    fn abort(&self) {
        self.shut();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link::noise::{generate_static, Pattern, PROLOGUE};
    use std::sync::atomic::AtomicUsize;

    /// A real XX handshake between two ends, so that frames travel encrypted.
    async fn session() -> (Channel<MemoryEnd>, Channel<MemoryEnd>) {
        let (a, b) = MemoryEnd::pair();
        let ((ka, _), (kb, _)) = (generate_static().unwrap(), generate_static().unwrap());
        let mut hi = Handshake::new(Pattern::Xx, true, &ka, None, PROLOGUE, None).unwrap();
        let mut hr = Handshake::new(Pattern::Xx, false, &kb, None, PROLOGUE, None).unwrap();
        handshake_send(&*a, &mut hi, b"").await.unwrap();
        handshake_receive(&*b, &mut hr).await.unwrap();
        handshake_send(&*b, &mut hr, b"").await.unwrap();
        handshake_receive(&*a, &mut hi).await.unwrap();
        handshake_send(&*a, &mut hi, b"").await.unwrap();
        handshake_receive(&*b, &mut hr).await.unwrap();
        (Channel::new(a, hi.finish().unwrap()), Channel::new(b, hr.finish().unwrap()))
    }

    #[tokio::test]
    async fn frames_go_both_ways_in_order() {
        let (a, b) = session().await;
        let id = [7u8; 16];
        for n in 0..5u64 {
            a.send_frame(&Frame::Chunk { id, offset: n, data: vec![n as u8; 10] }).await.unwrap();
        }
        for n in 0..5u64 {
            assert_eq!(b.receive_frame().await.unwrap(), Frame::Chunk { id, offset: n, data: vec![n as u8; 10] });
        }
        b.send_frame(&Frame::Accept { id }).await.unwrap();
        assert_eq!(a.receive_frame().await.unwrap(), Frame::Accept { id });
    }

    #[tokio::test]
    async fn two_senders_at_once_keep_the_nonces_in_order() {
        let (a, b) = session().await;
        let a = Arc::new(a);
        let id = [1u8; 16];
        let tasks: Vec<_> = (0..20u64).map(|n| {
            let a = a.clone();
            tokio::spawn(async move { a.send_frame(&Frame::Chunk { id, offset: n, data: vec![1; 3] }).await })
        }).collect();
        for t in tasks {
            t.await.unwrap().unwrap();
        }
        for _ in 0..20 {
            b.receive_frame().await.unwrap(); // every message opens: none was sent out of the order it was sealed in
        }
    }

    #[tokio::test]
    async fn a_closed_end_reads_what_was_sent_and_then_the_end() {
        let (a, b) = MemoryEnd::pair();
        a.send(vec![1, 2, 3]).await.unwrap();
        a.close().await;
        assert_eq!(b.receive().await.unwrap(), vec![1, 2, 3]);
        assert_eq!(b.receive().await.unwrap_err(), LinkError::Closed);
        assert_eq!(a.send(vec![1]).await.unwrap_err(), LinkError::Closed);
        assert_eq!(a.send(vec![]).await.unwrap_err(), LinkError::Violation("record length".into()));
    }

    #[tokio::test]
    async fn an_abort_fails_a_pending_read_at_once() {
        let (a, _b) = MemoryEnd::pair();
        let a2 = a.clone();
        let pending = tokio::spawn(async move { a2.receive().await });
        tokio::task::yield_now().await;
        a.abort();
        assert_eq!(pending.await.unwrap().unwrap_err(), LinkError::Closed);
    }

    #[tokio::test(start_paused = true)]
    async fn an_idle_watch_fires_once_after_its_time_and_a_touch_pushes_it_back() {
        let fired = Arc::new(AtomicUsize::new(0));
        let f = fired.clone();
        let watch = IdleWatch::new(1_000, move || { f.fetch_add(1, Ordering::SeqCst); });
        tokio::time::sleep(Duration::from_millis(900)).await;
        watch.touch();
        tokio::time::sleep(Duration::from_millis(900)).await;
        assert_eq!(fired.load(Ordering::SeqCst), 0, "touched at 900 ms: not due at 1800 ms");
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert_eq!(fired.load(Ordering::SeqCst), 1);
        tokio::time::sleep(Duration::from_secs(10)).await;
        assert_eq!(fired.load(Ordering::SeqCst), 1, "once");
    }

    #[tokio::test(start_paused = true)]
    async fn a_stopped_or_dropped_watch_never_fires() {
        let fired = Arc::new(AtomicUsize::new(0));
        let f = fired.clone();
        let watch = IdleWatch::new(100, move || { f.fetch_add(1, Ordering::SeqCst); });
        watch.stop();
        let g = fired.clone();
        drop(IdleWatch::new(100, move || { g.fetch_add(1, Ordering::SeqCst); }));
        tokio::time::sleep(Duration::from_secs(5)).await;
        assert_eq!(fired.load(Ordering::SeqCst), 0);
    }

    #[tokio::test(start_paused = true)]
    async fn a_send_that_the_peer_never_reads_is_cut_after_the_grace() {
        struct Stuck(Arc<AtomicBool>);
        impl Transport for Stuck {
            async fn send(&self, _r: Vec<u8>) -> Result<(), LinkError> {
                std::future::pending::<()>().await;
                Ok(())
            }
            async fn receive(&self) -> Result<Vec<u8>, LinkError> { Err(LinkError::Closed) }
            async fn close(&self) {}
            fn abort(&self) { self.0.store(true, Ordering::SeqCst); }
        }
        let cut = Arc::new(AtomicBool::new(false));
        let (ka, _) = generate_static().unwrap();
        let (kb, _) = generate_static().unwrap();
        // The handshake needs a working transport, so the noise state comes from a memory pair and the stuck transport carries only the frame.
        let (a, b) = MemoryEnd::pair();
        let mut hi = Handshake::new(Pattern::Xx, true, &ka, None, PROLOGUE, None).unwrap();
        let mut hr = Handshake::new(Pattern::Xx, false, &kb, None, PROLOGUE, None).unwrap();
        handshake_send(&*a, &mut hi, b"").await.unwrap();
        handshake_receive(&*b, &mut hr).await.unwrap();
        handshake_send(&*b, &mut hr, b"").await.unwrap();
        handshake_receive(&*a, &mut hi).await.unwrap();
        handshake_send(&*a, &mut hi, b"").await.unwrap();
        handshake_receive(&*b, &mut hr).await.unwrap();
        let channel = Arc::new(Channel::new(Arc::new(Stuck(cut.clone())), hi.finish().unwrap()));
        let c = channel.clone();
        let sending = tokio::spawn(async move { c.send_best_effort(&Frame::Cancel { id: [1; 16] }, 2_000).await });
        tokio::time::sleep(Duration::from_millis(1_900)).await;
        assert!(!cut.load(Ordering::SeqCst), "not yet");
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(cut.load(Ordering::SeqCst), "cut after the 2 s grace");
        sending.abort();
    }

    #[tokio::test]
    async fn the_frame_window_holds_a_fifth_frame_until_one_is_taken() {
        let w = FrameWindow::new();
        for _ in 0..FrameWindow::FRAMES {
            assert!(w.take().await);
        }
        let w2 = w.clone();
        let fifth = tokio::spawn(async move { w2.take().await });
        tokio::task::yield_now().await;
        assert!(!fifth.is_finished(), "the reader waits");
        w.give();
        assert!(fifth.await.unwrap());
        let w3 = w.clone();
        let waiting = tokio::spawn(async move { w3.take().await });
        tokio::task::yield_now().await;
        w.close();
        assert!(!waiting.await.unwrap(), "a closed window lets the reader go");
    }

    #[test]
    fn four_frames_may_wait_for_the_conversation() {
        assert_eq!(FrameWindow::FRAMES, 4);
    }
}
```


**Create `windows/src-tauri/src/link/pair_run.rs`:**

```rust
// One pairing conversation (docs/LINK-CONTRACT.md, "The pairing code"), on either side. The rules are the pure machines of `pairing.rs`, run one event at a time; this file only does the I/O
// around them: the preamble, the three `XX` handshake messages (commitment, hello with the responder's nonce, hello with the initiator's reveal), the code, the user's answer, the other side's
// answer, and the two minutes of the window. Nothing is stored here: a `Paired` outcome says that **both users said yes**, and the caller writes the key (`Keystore::add` re-checks the paired
// map at that moment). Nothing here reads a clock or draws a random number of its own: `clock` (whole milliseconds, monotonic) and the nonce come in, so a test can run both sides in one
// process. The Mac's twin is LinkPairRun.swift.

use std::sync::Arc;

use tokio::sync::mpsc;
use tokio::time::Duration;

use super::bytes::{hex, key32, id16};
use super::channel::{handshake_receive, handshake_send, Channel, LinkError, Transport};
use super::frames::{decode_hello, encode_hello, encode_preamble, Frame, Mode};
use super::identity::{Identity, Peer};
use super::noise::{Handshake, Pattern, PROLOGUE};
use super::pairing::{self, IEvent, IPhase, Initiator, Notify, REvent, RPhase, Responder, Reveal, Say};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PairOutcome {
    Paired(Peer),
    /// A user said no: this machine's (`by_me`) or the other's.
    Declined { by_me: bool },
    /// A rule or the wire refused: a `pairing::Refusal` word, or "closed", "handshake", "unexpected-frame".
    Refused(String),
}

/// Tells the service what happens inside a pairing.
#[derive(Clone)]
pub struct PairHooks {
    /// The code is known: show it, with the other machine's authenticated name.
    pub show_code: Arc<dyn Fn(String, String) + Send + Sync>,
    /// The handshake is over (the other side is authenticated); the connection no longer needs the listener's watchdog.
    pub handshake_done: Arc<dyn Fn() + Send + Sync>,
}

/// A frame the pairing connection may carry, a click, the end of the window or the end of the connection.
pub(crate) enum Event {
    User(bool),
    Frame(Frame),
    Closed,
    WindowEnded,
}

/// What the service holds to answer a pairing: the click on "They match" or "No", and the cancel that comes with closing the card.
#[derive(Clone)]
pub struct PairHandle {
    tx: mpsc::UnboundedSender<Event>,
}

impl PairHandle {
    pub fn answer(&self, yes: bool) {
        let _ = self.tx.send(Event::User(yes));
    }
    /// The user closed the card: a no, and the conversation ends.
    pub fn cancel(&self) {
        let _ = self.tx.send(Event::User(false));
    }
}

pub struct PairInbox {
    tx: mpsc::UnboundedSender<Event>,
    rx: mpsc::UnboundedReceiver<Event>,
}

pub fn pair_channel() -> (PairHandle, PairInbox) {
    let (tx, rx) = mpsc::unbounded_channel();
    (PairHandle { tx: tx.clone() }, PairInbox { tx, rx })
}

pub type Clock = Arc<dyn Fn() -> i64 + Send + Sync>;

enum Machine<'a> {
    Initiator(&'a mut Initiator),
    Responder(&'a mut Responder),
}

impl Machine<'_> {
    /// Steps the machine with the user's click or the other side's answer; what it says is (notify, send, because).
    fn answer(&mut self, mine: bool, yes: bool, now: i64) -> (Option<Notify>, Vec<Say>, Option<pairing::Refusal>) {
        match self {
            Machine::Initiator(m) => {
                let o = pairing::initiator_step(m, &if mine { IEvent::User { yes, now } } else { IEvent::Peer { yes, now } });
                **m = o.state;
                (o.notify, o.send, o.because)
            }
            Machine::Responder(m) => {
                let o = pairing::responder_step(m, &if mine { REvent::User { yes, now } } else { REvent::Peer { yes, now } });
                **m = o.state;
                (o.notify, o.send, o.because)
            }
        }
    }
}

/// An incoming pairing connection, behind the gate: when the gate is closed nothing is sent and the connection is closed, as for any other refused hello, and nobody sees a card. The
/// service uses this one function for every incoming pairing, so the rule is tested where it is applied. None when refused.
#[allow(clippy::too_many_arguments)]
pub async fn run_incoming<T: Transport>(transport: Arc<T>, identity: &Identity, nonce: [u8; 32], clock: Clock, gate: &pairing::Gate, state: Responder, hooks: &PairHooks, inbox: PairInbox) -> Option<(PairOutcome, Responder)> {
    if !gate.allows(Some(clock())) {
        transport.close().await;
        return None;
    }
    Some(run_responder(transport, identity, nonce, clock, state, hooks, inbox).await)
}

fn closed(e: LinkError) -> PairOutcome {
    let _ = e;
    PairOutcome::Refused("handshake".into())
}

pub async fn run_initiator<T: Transport>(transport: Arc<T>, identity: &Identity, nonce: [u8; 32], clock: Clock, start: Initiator, hooks: &PairHooks, inbox: PairInbox) -> (PairOutcome, Initiator) {
    let mut st = start;
    let outcome = match initiate(&transport, identity, nonce, &clock, &mut st, hooks, inbox).await {
        Ok(o) => o,
        Err(e) => {
            st.phase = IPhase::Idle;
            closed(e)
        }
    };
    transport.close().await;
    (outcome, st)
}

async fn initiate<T: Transport>(transport: &Arc<T>, identity: &Identity, nonce: [u8; 32], clock: &Clock, st: &mut Initiator, hooks: &PairHooks, inbox: PairInbox) -> Result<PairOutcome, LinkError> {
    let mut hs = Handshake::new(Pattern::Xx, true, &identity.key, None, PROLOGUE, None)?;
    let o = pairing::initiator_step(st, &IEvent::Start { nonce: hex(&nonce), static_key: hex(&identity.public), now: clock() });
    *st = o.state;
    if let Some(why) = o.because {
        return Ok(PairOutcome::Refused(why.as_str().into()));
    }
    let Some(Say::Commit(commit_hex)) = o.send.first() else { return Ok(PairOutcome::Refused("handshake".into())) };
    let commit = key32(commit_hex).ok_or_else(|| LinkError::Violation("commit".into()))?;
    transport.send(encode_preamble(Mode::Pair, &[0; 16])).await?;
    handshake_send(&**transport, &mut hs, &commit).await?;
    let hello = decode_hello(&handshake_receive(&**transport, &mut hs).await?)?;
    let remote = hs.remote_static().ok_or_else(|| LinkError::Violation("no remote key".into()))?;
    let o2 = pairing::initiator_step(st, &IEvent::Nonce { nonce: hex(&hello.nonce), peer_static: hex(&remote), peer_id: Some(hex(&hello.id)), now: clock() });
    *st = o2.state;
    if let Some(why) = o2.because {
        return Ok(PairOutcome::Refused(why.as_str().into()));
    }
    let my_id = id16(&identity.device_id).ok_or_else(|| LinkError::Violation("device id".into()))?;
    let reveal = encode_hello(&my_id, &nonce, &identity.name)?;
    handshake_send(&**transport, &mut hs, &reveal).await?;
    let noise = hs.finish()?;
    let IPhase::Coded { start: started_at, code, .. } = st.phase.clone() else { return Err(LinkError::Violation("no code".into())) };
    let peer = Peer { id: hex(&hello.id), name: hello.name.clone(), key: hex(&remote), at: unix_seconds() };
    (hooks.handshake_done)();
    (hooks.show_code)(code, hello.name);
    let channel = Arc::new(Channel::new(transport.clone(), noise));
    Ok(answers(channel, started_at, peer, clock, Machine::Initiator(st), inbox).await)
}

/// The preamble was read already (the listener reads it to tell a pairing from a transfer).
pub async fn run_responder<T: Transport>(transport: Arc<T>, identity: &Identity, nonce: [u8; 32], clock: Clock, start: Responder, hooks: &PairHooks, inbox: PairInbox) -> (PairOutcome, Responder) {
    let mut st = start;
    let outcome = match respond(&transport, identity, nonce, &clock, &mut st, hooks, inbox).await {
        Ok(o) => o,
        Err(e) => {
            st.phase = RPhase::Idle;
            closed(e)
        }
    };
    transport.close().await;
    (outcome, st)
}

async fn respond<T: Transport>(transport: &Arc<T>, identity: &Identity, nonce: [u8; 32], clock: &Clock, st: &mut Responder, hooks: &PairHooks, inbox: PairInbox) -> Result<PairOutcome, LinkError> {
    let mut hs = Handshake::new(Pattern::Xx, false, &identity.key, None, PROLOGUE, None)?;
    let commit = handshake_receive(&**transport, &mut hs).await?;
    let o = pairing::responder_step(st, &REvent::Commit { commit: hex(&commit), nonce: hex(&nonce), now: clock() });
    *st = o.state;
    if let Some(why) = o.because {
        return Ok(PairOutcome::Refused(why.as_str().into()));
    }
    let my_id = id16(&identity.device_id).ok_or_else(|| LinkError::Violation("device id".into()))?;
    handshake_send(&**transport, &mut hs, &encode_hello(&my_id, &nonce, &identity.name)?).await?;
    let reveal = decode_hello(&handshake_receive(&**transport, &mut hs).await?)?;
    let remote = hs.remote_static().ok_or_else(|| LinkError::Violation("no remote key".into()))?;
    let o2 = pairing::responder_step(
        st,
        &REvent::Reveal { reveal: Reveal { nonce: hex(&reveal.nonce), static_key: hex(&remote), own: hex(&identity.public), peer_id: Some(hex(&reveal.id)) }, now: clock() },
    );
    *st = o2.state;
    if let Some(why) = o2.because {
        return Ok(PairOutcome::Refused(why.as_str().into()));
    }
    let noise = hs.finish()?;
    let RPhase::Coded { start: started_at, code, .. } = st.phase.clone() else { return Err(LinkError::Violation("no code".into())) };
    let peer = Peer { id: hex(&reveal.id), name: reveal.name.clone(), key: hex(&remote), at: unix_seconds() };
    (hooks.handshake_done)();
    (hooks.show_code)(code, reveal.name);
    let channel = Arc::new(Channel::new(transport.clone(), noise));
    Ok(answers(channel, started_at, peer, clock, Machine::Responder(st), inbox).await)
}

fn unix_seconds() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

/// After the code is shown: the user's click and the other side's `pair-yes` or `pair-no`, in either order, inside the window. The only frames a pairing connection may carry.
async fn answers<T: Transport>(channel: Arc<Channel<T>>, window_start: i64, peer: Peer, clock: &Clock, mut machine: Machine<'_>, inbox: PairInbox) -> PairOutcome {
    let PairInbox { tx, mut rx } = inbox;
    let reader = {
        let (channel, tx) = (channel.clone(), tx.clone());
        tokio::spawn(async move {
            loop {
                match channel.receive_frame().await {
                    Ok(f) => {
                        if tx.send(Event::Frame(f)).is_err() {
                            return;
                        }
                    }
                    Err(_) => {
                        let _ = tx.send(Event::Closed);
                        return;
                    }
                }
            }
        })
    };
    let remaining = (pairing::WINDOW_MS - (clock() - window_start)).max(0) as u64;
    let timer = {
        let tx = tx.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(remaining)).await;
            let _ = tx.send(Event::WindowEnded);
        })
    };
    let outcome = loop {
        let Some(event) = rx.recv().await else { break PairOutcome::Refused("closed".into()) };
        let (mine, yes) = match event {
            Event::User(yes) => (true, yes),
            Event::Frame(Frame::PairYes) => (false, true),
            Event::Frame(Frame::PairNo) => (false, false),
            Event::Frame(_) => break PairOutcome::Refused("unexpected-frame".into()),
            Event::Closed => break PairOutcome::Refused("closed".into()),
            Event::WindowEnded => break PairOutcome::Refused(pairing::Refusal::WindowClosed.as_str().into()),
        };
        let (notify, send, because) = machine.answer(mine, yes, clock());
        // Our own answer must leave before anything is stored: a pair-yes that never left would leave the other side waiting for it alone, with a key stored on this side only.
        let mut failed = false;
        for s in &send {
            if let Say::Pair(y) = s {
                if channel.send_within(&if *y { Frame::PairYes } else { Frame::PairNo }, 2_000).await.is_err() {
                    failed = true;
                }
            }
        }
        if failed {
            break PairOutcome::Refused("closed".into());
        }
        match notify {
            Some(Notify::Store) => break PairOutcome::Paired(peer),
            Some(Notify::Discard) => {
                break if because == Some(pairing::Refusal::SaidNo) { PairOutcome::Declined { by_me: mine } } else { PairOutcome::Refused(because.map_or("discard", |b| b.as_str()).into()) };
            }
            _ => {}
        }
    };
    reader.abort();
    timer.abort();
    outcome
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link::channel::MemoryEnd;
    use crate::link::frames::decode_preamble;
    use crate::link::noise::{generate_static, public_of};
    use crate::link::pairing::{Gate, Ids, OwnId};
    use std::collections::BTreeMap;
    use std::sync::atomic::{AtomicI64, AtomicUsize, Ordering};
    use std::sync::Mutex as StdMutex;

    fn identity(tag: u8, name: &str) -> Identity {
        let (key, public) = generate_static().unwrap();
        assert_eq!(public_of(&key).unwrap(), public);
        Identity { device_id: hex(&[tag; 16]), name: name.to_string(), key, public }
    }

    struct Side {
        shown: Arc<StdMutex<Vec<(String, String)>>>,
        done: Arc<AtomicUsize>,
        hooks: PairHooks,
    }

    fn side() -> Side {
        let shown = Arc::new(StdMutex::new(Vec::new()));
        let done = Arc::new(AtomicUsize::new(0));
        let (s, d) = (shown.clone(), done.clone());
        let hooks = PairHooks { show_code: Arc::new(move |c, n| s.lock().unwrap().push((c, n))), handshake_done: Arc::new(move || { d.fetch_add(1, Ordering::SeqCst); }) };
        Side { shown, done, hooks }
    }

    fn clock() -> (Clock, Arc<AtomicI64>) {
        let t = Arc::new(AtomicI64::new(1_000));
        let c = t.clone();
        (Arc::new(move || c.load(Ordering::SeqCst)), t)
    }

    async fn wait_for_code(s: &Side) -> String {
        for _ in 0..2000 {
            if let Some((c, _)) = s.shown.lock().unwrap().first() {
                return c.clone();
            }
            tokio::time::sleep(Duration::from_millis(1)).await;
        }
        panic!("no code was shown");
    }

    struct Run {
        init: tokio::task::JoinHandle<(PairOutcome, Initiator)>,
        resp: tokio::task::JoinHandle<Option<(PairOutcome, Responder)>>,
        ih: PairHandle,
        rh: PairHandle,
        i_side: Side,
        r_side: Side,
    }

    fn start(i_id: &Identity, r_id: &Identity, i_state: Initiator, r_state: Responder, gate: Gate, clk: Clock) -> Run {
        let (a, b) = MemoryEnd::pair();
        let (i_side, r_side) = (side(), side());
        let (ih, ii) = pair_channel();
        let (rh, ri) = pair_channel();
        let (i_id, r_id, i_hooks, r_hooks, c2) = (i_id.clone(), r_id.clone(), i_side.hooks.clone(), r_side.hooks.clone(), clk.clone());
        let init = tokio::spawn(async move { run_initiator(a, &i_id, [0xA1; 32], clk, i_state, &i_hooks, ii).await });
        let resp = tokio::spawn(async move {
            // The listener reads the preamble first.
            let pre = decode_preamble(&b.receive().await.unwrap()).unwrap();
            assert_eq!(pre.mode, Mode::Pair);
            run_incoming(b, &r_id, [0xB1; 32], c2, &gate, r_state, &r_hooks, ri).await
        });
        Run { init, resp, ih, rh, i_side, r_side }
    }

    fn open_gate() -> Gate {
        let mut g = Gate::default();
        g.devices_appeared();
        g
    }

    #[tokio::test]
    async fn both_users_say_they_match_and_each_side_keeps_the_other() {
        let (i, r) = (identity(1, "Sam's MacBook Pro"), identity(2, "Desk PC"));
        let (clk, _) = clock();
        let run = start(&i, &r, Initiator::new(Ids::default()), Responder::new(Ids::default()), open_gate(), clk);
        let (ci, cr) = (wait_for_code(&run.i_side).await, wait_for_code(&run.r_side).await);
        assert_eq!(ci, cr, "both screens show the same six digits");
        assert_eq!(ci.len(), 6);
        assert_eq!(run.i_side.shown.lock().unwrap()[0].1, "Desk PC", "the initiator sees the responder's authenticated name");
        assert_eq!(run.r_side.shown.lock().unwrap()[0].1, "Sam's MacBook Pro");
        run.ih.answer(true);
        run.rh.answer(true);
        let (io, _) = run.init.await.unwrap();
        let (ro, _) = run.resp.await.unwrap().unwrap();
        assert_eq!(io, PairOutcome::Paired(Peer { id: r.device_id.clone(), name: "Desk PC".into(), key: hex(&r.public), at: match &io { PairOutcome::Paired(p) => p.at, _ => 0 } }));
        match ro {
            PairOutcome::Paired(p) => assert_eq!((p.id, p.name, p.key), (i.device_id.clone(), "Sam's MacBook Pro".to_string(), hex(&i.public))),
            other => panic!("{other:?}"),
        }
        assert_eq!(run.i_side.done.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn one_no_stores_nothing_on_either_side() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, _) = clock();
        let run = start(&i, &r, Initiator::new(Ids::default()), Responder::new(Ids::default()), open_gate(), clk);
        wait_for_code(&run.i_side).await;
        wait_for_code(&run.r_side).await;
        run.ih.answer(true);
        run.rh.answer(false);
        assert_eq!(run.init.await.unwrap().0, PairOutcome::Declined { by_me: false });
        assert_eq!(run.resp.await.unwrap().unwrap().0, PairOutcome::Declined { by_me: true });
    }

    #[tokio::test]
    async fn closing_the_card_is_a_no() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, _) = clock();
        let run = start(&i, &r, Initiator::new(Ids::default()), Responder::new(Ids::default()), open_gate(), clk);
        wait_for_code(&run.i_side).await;
        wait_for_code(&run.r_side).await;
        run.ih.cancel();
        assert_eq!(run.init.await.unwrap().0, PairOutcome::Declined { by_me: true });
        assert_eq!(run.resp.await.unwrap().unwrap().0, PairOutcome::Declined { by_me: false });
    }

    #[tokio::test]
    async fn outside_the_gate_nothing_is_sent_and_no_card_is_shown() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, _) = clock();
        let run = start(&i, &r, Initiator::new(Ids::default()), Responder::new(Ids::default()), Gate::default(), clk);
        assert!(run.resp.await.unwrap().is_none(), "refused silently");
        assert_eq!(run.init.await.unwrap().0, PairOutcome::Refused("handshake".into()), "the initiator sees only a closed connection");
        assert!(run.r_side.shown.lock().unwrap().is_empty() && run.i_side.shown.lock().unwrap().is_empty());
        assert_eq!(run.r_side.done.load(Ordering::SeqCst), 0);
    }

    #[tokio::test]
    async fn the_gate_is_open_for_two_minutes_after_a_click_and_not_a_millisecond_longer() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        for (now, runs) in [(121_000i64 - 1, true), (121_000, false)] {
            let mut gate = Gate::default();
            gate.pair_clicked(1_000);
            let t = Arc::new(AtomicI64::new(now));
            let c = t.clone();
            let clk: Clock = Arc::new(move || c.load(Ordering::SeqCst));
            let run = start(&i, &r, Initiator::new(Ids::default()), Responder::new(Ids::default()), gate, clk);
            if runs {
                wait_for_code(&run.r_side).await;
                run.rh.answer(false);
                run.ih.answer(false);
            }
            let got = run.resp.await.unwrap();
            assert_eq!(got.is_some(), runs, "at {now}");
            let _ = run.init.await;
        }
    }

    #[tokio::test(start_paused = true)]
    async fn nobody_answering_ends_it_when_the_window_closes() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, t) = clock();
        let run = start(&i, &r, Initiator::new(Ids::default()), Responder::new(Ids::default()), open_gate(), clk);
        wait_for_code(&run.i_side).await;
        wait_for_code(&run.r_side).await;
        t.fetch_add(120_000, Ordering::SeqCst);
        tokio::time::sleep(Duration::from_millis(120_001)).await;
        assert_eq!(run.init.await.unwrap().0, PairOutcome::Refused("window-closed".into()));
        assert_eq!(run.resp.await.unwrap().unwrap().0, PairOutcome::Refused("window-closed".into()));
    }

    #[tokio::test]
    async fn a_second_attempt_inside_30_seconds_is_refused() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, t) = clock();
        let mut machine = Initiator::new(Ids::default());
        machine.last = Some(t.load(Ordering::SeqCst) - 29_999);
        let run = start(&i, &r, machine, Responder::new(Ids::default()), open_gate(), clk);
        let (io, _) = run.init.await.unwrap();
        assert_eq!(io, PairOutcome::Refused("attempt-too-soon".into()));
        let _ = run.resp.await;
    }

    #[tokio::test]
    async fn an_id_paired_under_another_key_is_refused_by_the_initiator() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, _) = clock();
        let mut paired = BTreeMap::new();
        paired.insert(r.device_id.clone(), hex(&[9u8; 32]));
        let ids = Ids { own_id: OwnId::Id(i.device_id.clone()), paired: Some(paired) };
        let run = start(&i, &r, Initiator::new(ids), Responder::new(Ids::default()), open_gate(), clk);
        assert_eq!(run.init.await.unwrap().0, PairOutcome::Refused("id-key-mismatch".into()));
        assert_eq!(run.r_side.shown.lock().unwrap().len(), 0);
        let _ = run.resp.await;
    }

    #[tokio::test]
    async fn a_frame_that_is_not_an_answer_ends_the_pairing() {
        // The responder is played by hand: after a real handshake it sends a transfer frame where a pairing answer belongs.
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, _) = clock();
        let (a, b) = MemoryEnd::pair();
        let side_i = side();
        let (_ih, ii) = pair_channel();
        let (i2, hooks) = (i.clone(), side_i.hooks.clone());
        let init = tokio::spawn(async move { run_initiator(a, &i2, [0xA1; 32], clk, Initiator::new(Ids::default()), &hooks, ii).await });
        decode_preamble(&b.receive().await.unwrap()).unwrap();
        let mut hs = Handshake::new(Pattern::Xx, false, &r.key, None, PROLOGUE, None).unwrap();
        handshake_receive(&*b, &mut hs).await.unwrap();
        let hello = encode_hello(&id16(&r.device_id).unwrap(), &[0xB1; 32], &r.name).unwrap();
        handshake_send(&*b, &mut hs, &hello).await.unwrap();
        decode_hello(&handshake_receive(&*b, &mut hs).await.unwrap()).unwrap();
        let channel = Channel::new(b.clone(), hs.finish().unwrap());
        channel.send_frame(&Frame::Accept { id: [3; 16] }).await.unwrap();
        assert_eq!(init.await.unwrap().0, PairOutcome::Refused("unexpected-frame".into()));
    }
}
```


**Create `windows/src-tauri/src/link/transfer.rs`:**

```rust
// One transfer conversation (docs/LINK-CONTRACT.md, "What each side does with each frame"), on either side. The rules are the pure machines of `flow.rs` (the connection rules included),
// run one event at a time; this file does the I/O around them: the preamble and the two `KK` handshake messages, the offer, the user's answer, the chunks to or from disk, progress, cancel,
// and the two minutes an offer may wait. Only a click on Accept accepts an offer (`ReceiveHandle::respond(true)` is called from that button alone): nothing in this file accepts for the user.
// The Mac's twin is LinkTransferRun.swift, with every fix of its reviews.
//
// A transfer runs only between paired machines: the sender knows the receiver's stored key, and the receiver looks up the sender's device id from the preamble and refuses one it does not know
// (the caller does that before it makes a run). Nothing here draws a random number except the transfer id the sender makes.
//
// Nothing waits for ever. A connection whose handshake is done must send its first frame within 10 s (a sender sends its offer right after the handshake) and nothing but a file coming in
// pushes that back; while a file comes in, a chunk must come within 60 s (the offer that waits for a click has its own 2 minutes); a sender whose offer nobody answers gives up after 130 s,
// and one whose bytes stop going out after 60 s. A sender's user may cancel at any time: its cancel frame is given 2 s like every frame, and a cancel that comes while the handshake is still
// going is waited for 2 s too, then the connection is cut (the conversation reads nothing before its offer is out). A frame this side sends is given 2 s (`Channel::send_best_effort`), then
// the connection is cut, so a peer that stopped reading cannot hold the conversation in a send. A conversation that is cut for that reason saves nothing. Each of those is a one-shot
// `IdleWatch` that exists only while its phase lasts, and each reader hands on at most `FrameWindow::FRAMES` frames the conversation has not taken yet. A peer gets one decline per connection
// (a sender makes a connection for each file): the second ends the connection.
//
// The disk is written from the conversation's own task: a chunk is at most 32 KiB, and a write of that size is not worth a thread of its own.

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex as StdMutex};

use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use tokio::time::Duration;

use super::bytes::{hex, id16, key32};
use super::channel::{handshake_receive, handshake_send, Channel, FrameWindow, IdleWatch, LinkError, Transport};
use super::files::{Sink, Source};
use super::flow::{self, Abort, ConnEvent, Conn, Event, Notify, RState, SEvent, SState, User};
use super::frames::{encode_preamble, Frame, Mode, CHUNK_SIZE, DECLINE_USER, plan_chunks};
use super::identity::{Identity, Peer};
use super::noise::{Handshake, Pattern, PROLOGUE};
use super::pairing::OFFER_TIMEOUT_MS;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransferOutcome {
    /// The received file's path; None on the sending side.
    Completed(Option<PathBuf>),
    /// The receiver said no (sender), or this side's own decline (receiver: reason 0).
    Declined { reason: u8 },
    /// Nobody answered the offer in 2 minutes.
    Expired,
    /// Either user cancelled during the transfer, or the other side did.
    Cancelled,
    /// The sender withdrew an offer that was waiting.
    Withdrawn,
    /// A rule or the wire ended it: a `flow::Abort` word, or "closed", "handshake", "disk", "idle", "stalled", "busy".
    Aborted(String),
}

/// What the Accept card shows. `name` is the **sanitized** name, the one that will be saved.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Offer {
    pub transfer_id: String,
    pub name: String,
    pub size: u64,
    pub peer_id: String,
    pub peer_name: String,
}

// ── Receiving ────────────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct ReceiveHooks {
    /// An offer is waiting for a click. Show the card.
    pub offered: Arc<dyn Fn(Offer) + Send + Sync>,
    pub progress: Arc<dyn Fn(u64, u64) + Send + Sync>,
    /// One active transfer for the whole machine (`Busy`), whichever peer it is from: false when another transfer is already claimed, or a card with buttons is on the island (the offer is then
    /// declined as busy). The argument says whose offer it is; it does not make the claim per machine.
    pub claim: Arc<dyn Fn(&str) -> bool + Send + Sync>,
    pub release: Arc<dyn Fn(&str) + Send + Sync>,
    /// The handshake is over; the connection no longer needs the listener's watchdog.
    pub handshake_done: Arc<dyn Fn() + Send + Sync>,
    /// Asked once, when the handshake is over and before anything is read: false closes the connection (too many connections are open already, `ConnectionCaps`). Nothing is shown for it.
    pub admit: Arc<dyn Fn() -> bool + Send + Sync>,
    /// false: the run does not give its claim back when it ends, its caller does (`ReceiveHandle::holds_claim`), once it has cleared what it keeps for the run. The early give-back of an offer
    /// this side refused itself is not affected.
    pub release_at_end: bool,
}

#[derive(Debug, Clone, Copy)]
pub struct ReceiveTimings {
    /// A connection that has finished its handshake must send its first frame within this long.
    pub first_frame_ms: u64,
    /// While a file comes in, the time the other side may take between two chunks.
    pub stall_ms: u64,
    /// A frame this side sends is waited for no longer than this.
    pub grace_ms: u64,
    pub offer_timeout_ms: u64,
}

impl Default for ReceiveTimings {
    fn default() -> ReceiveTimings {
        ReceiveTimings { first_frame_ms: flow::FIRST_FRAME_MS as u64, stall_ms: 60_000, grace_ms: 2_000, offer_timeout_ms: OFFER_TIMEOUT_MS as u64 }
    }
}

enum RxEvent {
    Frame(Frame),
    Closed,
    User(User),
    Timeout,
    Silent,
    Stalled,
}

/// What the service holds to answer an offer: the click, the cancel, and whether the run holds the machine's transfer place.
#[derive(Clone)]
pub struct ReceiveHandle {
    tx: mpsc::UnboundedSender<RxEvent>,
    holds: Arc<AtomicBool>,
}

impl ReceiveHandle {
    /// The user's click on Accept (true) or Decline (false).
    pub fn respond(&self, accept: bool) {
        let _ = self.tx.send(RxEvent::User(if accept { User::Accept } else { User::Decline }));
    }
    /// The user cancels the transfer that is running (or declines the offer that is waiting).
    pub fn cancel(&self) {
        let _ = self.tx.send(RxEvent::User(User::Cancel));
    }
    /// True from the moment this run's offer took the machine's one transfer place until it was given back. A caller that set `release_at_end` to false reads it after the run.
    pub fn holds_claim(&self) -> bool {
        self.holds.load(Ordering::SeqCst)
    }
}

pub struct ReceiveInbox {
    tx: mpsc::UnboundedSender<RxEvent>,
    rx: mpsc::UnboundedReceiver<RxEvent>,
    holds: Arc<AtomicBool>,
}

pub fn receive_channel() -> (ReceiveHandle, ReceiveInbox) {
    let (tx, rx) = mpsc::unbounded_channel();
    let holds = Arc::new(AtomicBool::new(false));
    (ReceiveHandle { tx: tx.clone(), holds: holds.clone() }, ReceiveInbox { tx, rx, holds })
}

/// What a run must stop when it returns, whichever way it returns.
struct Cleanup {
    reader: Option<JoinHandle<()>>,
    timer: Option<JoinHandle<()>>,
    watch: Option<IdleWatch>,
    window: FrameWindow,
}

impl Drop for Cleanup {
    fn drop(&mut self) {
        if let Some(r) = &self.reader {
            r.abort();
        }
        if let Some(t) = &self.timer {
            t.abort();
        }
        if let Some(w) = &self.watch {
            w.stop();
        }
        self.window.close();
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Waiting {
    Nothing,
    FirstFrame,
    Chunk,
}

/// The preamble was read already. Runs the `KK` handshake, then the conversation. `mark` is whether the file gets the mark of the web (Windows).
#[allow(clippy::too_many_arguments)]
pub async fn run_receive<T: Transport>(transport: Arc<T>, identity: &Identity, peer: &Peer, folder: PathBuf, mark: bool, hooks: &ReceiveHooks, timings: ReceiveTimings, inbox: ReceiveInbox) -> TransferOutcome {
    let ReceiveInbox { tx: post, mut rx, holds } = inbox;
    let mut sink: Option<Sink> = None;

    async fn end<T: Transport>(transport: &Arc<T>, hooks: &ReceiveHooks, peer: &Peer, holds: &AtomicBool, sink: &mut Option<Sink>, grace_ms: u64, outcome: TransferOutcome) -> TransferOutcome {
        if !matches!(outcome, TransferOutcome::Completed(_)) {
            if let Some(s) = sink.as_mut() {
                s.discard();
            }
        }
        if holds.load(Ordering::SeqCst) && hooks.release_at_end {
            holds.store(false, Ordering::SeqCst);
            (hooks.release)(&peer.id);
        }
        let t = transport.clone();
        let cut = IdleWatch::new(grace_ms, move || t.abort()); // a close waits behind bytes a peer does not read
        transport.close().await;
        cut.stop();
        outcome
    }
    macro_rules! finish {
        ($o:expr) => {
            return end(&transport, hooks, peer, &holds, &mut sink, timings.grace_ms, $o).await
        };
    }

    let channel = {
        let Some(remote) = key32(&peer.key) else { finish!(TransferOutcome::Aborted("handshake".into())) };
        let shaken: Result<Channel<T>, LinkError> = async {
            let mut hs = Handshake::new(Pattern::Kk, false, &identity.key, Some(&remote), PROLOGUE, None)?;
            let first = handshake_receive(&*transport, &mut hs).await?;
            if !first.is_empty() {
                return Err(LinkError::Violation("kk payload".into())); // the KK payloads are empty (docs/LINK-CONTRACT.md); a port refuses a non-empty one
            }
            handshake_send(&*transport, &mut hs, &[]).await?;
            Ok(Channel::new(transport.clone(), hs.finish()?))
        }
        .await;
        match shaken {
            Ok(c) => Arc::new(c),
            Err(_) => finish!(TransferOutcome::Aborted("handshake".into())),
        }
    };
    if !(hooks.admit)() {
        finish!(TransferOutcome::Aborted("busy".into()));
    }
    (hooks.handshake_done)();

    let window = FrameWindow::new();
    let mut cleanup = Cleanup { reader: None, timer: None, watch: None, window: window.clone() };
    cleanup.reader = Some({
        let (channel, post, window) = (channel.clone(), post.clone(), window.clone());
        tokio::spawn(async move {
            loop {
                if !window.take().await {
                    return;
                }
                match channel.receive_frame().await {
                    Ok(f) => {
                        if post.send(RxEvent::Frame(f)).is_err() {
                            return;
                        }
                    }
                    Err(_) => {
                        let _ = post.send(RxEvent::Closed);
                        return;
                    }
                }
            }
        })
    });

    // What the connection is waited for: its first frame (while no offer is in hand), then a chunk at a time (while a file comes in). An offer that waits for the click has `timer`, not this.
    let mut waiting = Waiting::Nothing;
    macro_rules! wait_for {
        ($state:expr) => {{
            let want = match $state {
                RState::Idle => Waiting::FirstFrame,
                RState::Offered { .. } => Waiting::Nothing,
                RState::Receiving { .. } => Waiting::Chunk,
            };
            if want != waiting {
                if let Some(w) = cleanup.watch.take() {
                    w.stop();
                }
                waiting = want;
                // The watch cuts the connection itself, before it posts: the conversation may be stuck in a send and not read its queue until the cut fails that send.
                cleanup.watch = match want {
                    Waiting::Nothing => None,
                    Waiting::FirstFrame => {
                        let (t, p) = (transport.clone(), post.clone());
                        Some(IdleWatch::new(timings.first_frame_ms, move || { t.abort(); let _ = p.send(RxEvent::Silent); }))
                    }
                    Waiting::Chunk => {
                        let (t, p) = (transport.clone(), post.clone());
                        Some(IdleWatch::new(timings.stall_ms, move || { t.abort(); let _ = p.send(RxEvent::Stalled); }))
                    }
                };
            }
        }};
    }
    wait_for!(&RState::Idle);

    let mut conn = Conn { state: RState::Idle, declines: 0 };
    let (mut total, mut offered_name) = (0u64, String::new());
    while let Some(event) = rx.recv().await {
        let ev = match event {
            RxEvent::Closed => finish!(TransferOutcome::Aborted("closed".into())),
            // A report that was on its way when the connection moved on (an offer came in, a chunk did) is not for the phase it finds.
            RxEvent::Silent => {
                if waiting != Waiting::FirstFrame {
                    continue;
                }
                transport.abort();
                finish!(TransferOutcome::Aborted("idle".into()))
            }
            RxEvent::Stalled => {
                if waiting != Waiting::Chunk {
                    continue;
                }
                transport.abort();
                finish!(TransferOutcome::Aborted("stalled".into()))
            }
            RxEvent::Frame(f) => {
                window.give();
                // Only a chunk is activity: while a file comes in the limit is pushed back by chunks and by nothing else a peer sends (a cancel for another transfer, an offer), and while nothing
                // is going on the first-frame limit is not pushed back at all, so no stream of frames keeps a connection alive.
                if matches!(conn.state, RState::Receiving { .. }) && matches!(f, Frame::Chunk { .. }) {
                    if let Some(w) = &cleanup.watch {
                        w.touch();
                    }
                }
                Event::Frame(f)
            }
            RxEvent::User(u) => Event::User(u),
            RxEvent::Timeout => Event::Timeout,
        };
        // Busy across connections: the machine models this connection only. The machine has one transfer place (`hooks.claim`), whichever peer it is asked for.
        let is_offer = matches!(ev, Event::Frame(Frame::Offer { .. }));
        let mut granted = None;
        if is_offer && conn.state == RState::Idle && !holds.load(Ordering::SeqCst) {
            let ok = (hooks.claim)(&peer.id);
            if ok {
                holds.store(true, Ordering::SeqCst);
            }
            granted = Some(ok);
        }
        let out = flow::connection_step(&conn, &ConnEvent::Receiver { event: ev.clone(), granted });
        conn = out.conn.clone();
        for f in &out.send {
            channel.send_best_effort(f, timings.grace_ms).await;
        }
        if let Some(abort) = out.abort {
            // The second decline the machine makes on one connection is not answered: the connection is cut, so a peer that sends offers without end holds no place and churns no claim.
            if abort == Abort::Declines {
                transport.abort();
            }
            finish!(TransferOutcome::Aborted(abort.as_str().into()));
        }
        // The machine declined the offer itself (too large, a name it refuses): no card will come, so the machine's transfer place goes now, not when the connection closes.
        if holds.load(Ordering::SeqCst) && is_offer && conn.state == RState::Idle {
            holds.store(false, Ordering::SeqCst);
            (hooks.release)(&peer.id);
        }

        match out.notify {
            Some(Notify::Offer) => {
                if let RState::Offered { id, size, name } = &conn.state {
                    total = *size;
                    offered_name = name.clone();
                    if let Some(t) = cleanup.timer.take() {
                        t.abort();
                    }
                    let (p, ms) = (post.clone(), timings.offer_timeout_ms);
                    cleanup.timer = Some(tokio::spawn(async move {
                        tokio::time::sleep(Duration::from_millis(ms)).await;
                        let _ = p.send(RxEvent::Timeout);
                    }));
                    (hooks.offered)(Offer { transfer_id: hex(id), name: name.clone(), size: *size, peer_id: peer.id.clone(), peer_name: peer.name.clone() });
                }
            }
            Some(Notify::Expired) => finish!(TransferOutcome::Expired),
            Some(Notify::Withdrawn) => finish!(TransferOutcome::Withdrawn),
            Some(Notify::Cancelled) => finish!(TransferOutcome::Cancelled),
            Some(Notify::Complete) => match sink.as_mut().map(Sink::finish) {
                Some(Ok(path)) => finish!(TransferOutcome::Completed(Some(path))),
                _ => finish!(TransferOutcome::Aborted("disk".into())),
            },
            _ => {}
        }

        wait_for!(&conn.state);

        // Effects of the new state.
        match (&ev, &conn.state) {
            (Event::User(User::Accept), RState::Receiving { id, .. }) => {
                if let Some(t) = cleanup.timer.take() {
                    t.abort();
                }
                // Only now is anything created on disk. A file that cannot be created ends the transfer with a cancel the other side sees.
                let mut s = Sink::new(folder.clone(), &offered_name, mark);
                match s.open() {
                    Ok(_) => sink = Some(s),
                    Err(_) => {
                        channel.send_best_effort(&Frame::Cancel { id: *id }, timings.grace_ms).await;
                        finish!(TransferOutcome::Aborted("disk".into()));
                    }
                }
            }
            (Event::Frame(Frame::Chunk { data, .. }), RState::Receiving { id, got, .. }) => {
                if sink.as_mut().map(|s| s.write(data)).transpose().is_err() {
                    channel.send_best_effort(&Frame::Cancel { id: *id }, timings.grace_ms).await;
                    finish!(TransferOutcome::Aborted("disk".into()));
                }
                (hooks.progress)(*got, total);
            }
            (Event::User(User::Decline), RState::Idle) => finish!(TransferOutcome::Declined { reason: DECLINE_USER }),
            _ => {}
        }
    }
    finish!(TransferOutcome::Aborted("closed".into()))
}

// ── Sending ──────────────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct SendHooks {
    pub progress: Arc<dyn Fn(u64, u64) + Send + Sync>,
}

#[derive(Debug, Clone, Copy)]
pub struct SendTimings {
    /// The other side has this long to answer the handshake (the listener gives a connection 10 s for it too).
    pub handshake_ms: u64,
    /// An offer nobody answers is given up after this long: a little more than the 2 minutes the receiver gives its user, so the receiver's own "did not answer in time" arrives first.
    pub accept_wait_ms: u64,
    /// While the file goes out, the longest the other side may take without letting one more chunk through.
    pub stall_ms: u64,
    /// A cancel is sent and not waited for longer than this: after it the connection is cut, however stuck it is.
    pub grace_ms: u64,
}

impl Default for SendTimings {
    fn default() -> SendTimings {
        SendTimings { handshake_ms: 10_000, accept_wait_ms: 130_000, stall_ms: 60_000, grace_ms: 2_000 }
    }
}

/// How the chunk pump ended: all sent (`done`), the file could not be read or changed size (`disk`, the file's fault), or a send failed (`lost`, the connection's fault).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Pump {
    Done,
    Disk,
    Lost,
}

enum TxEvent {
    Frame(Frame),
    Closed,
    Cancel,
    Pumped(Pump),
    Unanswered,
    Stalled,
}

/// The deadline of a cancel that comes before the loop reads events (the handshake and the offer): armed by the cancel, ended when the offer is out (or the run is), and then it never fires.
struct HandshakeCut {
    state: StdMutex<(bool, Option<IdleWatch>)>,
}

impl HandshakeCut {
    fn arm(&self, runtime: &tokio::runtime::Handle, ms: u64, cut: impl FnOnce() + Send + 'static) {
        let mut g = self.state.lock().unwrap();
        if !g.0 && g.1.is_none() {
            g.1 = Some(IdleWatch::on(runtime, ms, cut));
        }
    }
    fn end(&self) {
        let mut g = self.state.lock().unwrap();
        g.0 = true;
        if let Some(w) = g.1.take() {
            w.stop();
        }
    }
}

#[derive(Clone)]
pub struct SendHandle {
    tx: mpsc::UnboundedSender<TxEvent>,
    cut: Arc<HandshakeCut>,
    runtime: tokio::runtime::Handle,
    abort: Arc<dyn Fn() + Send + Sync>,
    grace_ms: u64,
}

impl SendHandle {
    /// The user cancels: the run sends its cancel frame and ends, and the connection is cut only if that frame cannot go out within the grace, so the other side's user sees a cancel and not a
    /// connection that dropped. While the handshake is still going nothing is read (the cancel is read once the offer is out): the cancel is then given the grace for that to happen, and the
    /// connection is cut when it has not.
    pub fn cancel(&self) {
        let _ = self.tx.send(TxEvent::Cancel);
        let abort = self.abort.clone();
        self.cut.arm(&self.runtime, self.grace_ms, move || abort());
    }
}

pub struct SendInbox {
    tx: mpsc::UnboundedSender<TxEvent>,
    rx: mpsc::UnboundedReceiver<TxEvent>,
    cut: Arc<HandshakeCut>,
}

/// Made inside the runtime the run will use. `timings.grace_ms` must be the one the run gets.
pub fn send_channel<T: Transport>(transport: &Arc<T>, grace_ms: u64) -> (SendHandle, SendInbox) {
    let (tx, rx) = mpsc::unbounded_channel();
    let cut = Arc::new(HandshakeCut { state: StdMutex::new((false, None)) });
    let t = transport.clone();
    (SendHandle { tx: tx.clone(), cut: cut.clone(), runtime: tokio::runtime::Handle::current(), abort: Arc::new(move || t.abort()), grace_ms }, SendInbox { tx, rx, cut })
}

pub async fn run_send<T: Transport>(transport: Arc<T>, identity: &Identity, peer: &Peer, source: Source, hooks: &SendHooks, timings: SendTimings, inbox: SendInbox) -> TransferOutcome {
    let SendInbox { tx: post, mut rx, cut } = inbox;
    let source = Arc::new(StdMutex::new(source));
    macro_rules! finish {
        ($o:expr) => {{
            cut.end();
            source.lock().unwrap().close();
            transport.close().await;
            return $o;
        }};
    }
    // The handshake has a deadline of its own: a machine that accepts the connection and then says nothing does not hold the send for ever.
    let handshake = {
        let t = transport.clone();
        IdleWatch::new(timings.handshake_ms, move || t.abort())
    };
    let channel = {
        let (Some(remote), Some(me)) = (key32(&peer.key), id16(&identity.device_id)) else {
            handshake.stop();
            finish!(TransferOutcome::Aborted("handshake".into()))
        };
        let shaken: Result<Channel<T>, LinkError> = async {
            let mut hs = Handshake::new(Pattern::Kk, true, &identity.key, Some(&remote), PROLOGUE, None)?;
            transport.send(encode_preamble(Mode::Transfer, &me)).await?;
            handshake_send(&*transport, &mut hs, &[]).await?;
            let reply = handshake_receive(&*transport, &mut hs).await?;
            if !reply.is_empty() {
                return Err(LinkError::Violation("kk payload".into()));
            }
            Ok(Channel::new(transport.clone(), hs.finish()?))
        }
        .await;
        handshake.stop();
        match shaken {
            Ok(c) => Arc::new(c),
            Err(_) => finish!(TransferOutcome::Aborted("handshake".into())),
        }
    };

    let mut id = [0u8; 16];
    if getrandom::getrandom(&mut id).is_err() {
        finish!(TransferOutcome::Aborted("handshake".into()));
    }
    let (size, offer) = {
        let s = source.lock().unwrap();
        (s.size, Frame::Offer { id, size: s.size, name: s.name.clone(), kind: s.kind.clone() })
    };
    if channel.send_frame(&offer).await.is_err() {
        finish!(TransferOutcome::Aborted("closed".into()));
    }
    cut.end(); // from here the loop below reads a cancel and sends it as a frame

    let window = FrameWindow::new();
    let mut live = SendCleanup { reader: None, pump: None, wait: None, window: window.clone() };
    live.reader = Some({
        let (channel, post, window) = (channel.clone(), post.clone(), window.clone());
        tokio::spawn(async move {
            loop {
                if !window.take().await {
                    return;
                }
                match channel.receive_frame().await {
                    Ok(f) => {
                        if post.send(TxEvent::Frame(f)).is_err() {
                            return;
                        }
                    }
                    Err(_) => {
                        let _ = post.send(TxEvent::Closed);
                        return;
                    }
                }
            }
        })
    });
    // While the offer waits: the answer, within `accept_wait_ms`. While the file goes out: a chunk through within `stall_ms` (the pump touches it after each one).
    live.wait = Some({
        let p = post.clone();
        Arc::new(IdleWatch::new(timings.accept_wait_ms, move || {
            let _ = p.send(TxEvent::Unanswered);
        }))
    });

    let mut state = SState::Offered { id };
    while let Some(event) = rx.recv().await {
        let ev = match event {
            TxEvent::Closed => finish!(TransferOutcome::Aborted("closed".into())),
            TxEvent::Cancel => SEvent::UserCancel,
            TxEvent::Frame(f) => {
                window.give();
                SEvent::Frame(f)
            }
            TxEvent::Unanswered => {
                if !matches!(state, SState::Offered { .. }) {
                    continue; // it was on its way when the answer came
                }
                channel.send_best_effort(&Frame::Cancel { id }, timings.grace_ms).await;
                finish!(TransferOutcome::Expired)
            }
            TxEvent::Stalled => {
                if !matches!(state, SState::Sending { .. }) {
                    continue;
                }
                transport.abort();
                finish!(TransferOutcome::Aborted("stalled".into()))
            }
            TxEvent::Pumped(end) => match end {
                Pump::Done => finish!(TransferOutcome::Completed(None)),
                Pump::Disk => {
                    channel.send_best_effort(&Frame::Cancel { id }, timings.grace_ms).await;
                    finish!(TransferOutcome::Aborted("disk".into()))
                }
                Pump::Lost => finish!(TransferOutcome::Aborted("closed".into())),
            },
        };
        let decline_reason = if let SEvent::Frame(Frame::Decline { reason, .. }) = &ev { *reason } else { 0 };
        let was_offered = matches!(state, SState::Offered { .. });
        let user_cancel = matches!(ev, SEvent::UserCancel);
        let out = flow::sender_step(&state, &ev);
        state = out.state.clone();
        for f in &out.send {
            channel.send_best_effort(f, timings.grace_ms).await;
        }
        if let Some(abort) = out.abort {
            finish!(TransferOutcome::Aborted(abort.as_str().into()));
        }
        match out.notify {
            Some(Notify::Declined) => finish!(TransferOutcome::Declined { reason: decline_reason }),
            Some(Notify::Cancelled) => finish!(if was_offered && user_cancel { TransferOutcome::Withdrawn } else { TransferOutcome::Cancelled }),
            _ => {}
        }
        if was_offered && matches!(state, SState::Sending { .. }) {
            // Accepted: cut the file into chunks and send them, one at a time, each waiting for the transport. A file that is shorter or longer than it was when the offer went out is cancelled.
            // A read that fails or comes back short is the file's fault ("disk"); a send that fails is the connection's ("closed"). A pump that was cancelled posts nothing.
            let moving = {
                let p = post.clone();
                Arc::new(IdleWatch::new(timings.stall_ms, move || {
                    let _ = p.send(TxEvent::Stalled);
                }))
            };
            if let Some(w) = live.wait.replace(moving.clone()) {
                w.stop();
            }
            let (channel, source, post, hooks) = (channel.clone(), source.clone(), post.clone(), hooks.clone());
            live.pump = Some(tokio::spawn(async move {
                let end = |how: Pump| {
                    let _ = post.send(TxEvent::Pumped(how));
                };
                let mut sent = 0u64;
                for (offset, len) in plan_chunks(size, CHUNK_SIZE) {
                    let data = match source.lock().unwrap().read(len) {
                        Ok(d) if d.len() == len => d,
                        _ => return end(Pump::Disk),
                    };
                    if channel.send_frame(&Frame::Chunk { id, offset, data }).await.is_err() {
                        return end(Pump::Lost);
                    }
                    moving.touch();
                    sent += len as u64;
                    (hooks.progress)(sent, size);
                }
                let tail = source.lock().unwrap().read(1);
                if !matches!(tail, Ok(ref t) if t.is_empty()) {
                    return end(Pump::Disk);
                }
                if channel.send_frame(&Frame::Done { id }).await.is_err() {
                    return end(Pump::Lost);
                }
                end(Pump::Done)
            }));
        }
    }
    finish!(TransferOutcome::Aborted("closed".into()))
}

/// What a sending run must stop when it returns, whichever way it returns.
struct SendCleanup {
    reader: Option<JoinHandle<()>>,
    pump: Option<JoinHandle<()>>,
    wait: Option<Arc<IdleWatch>>,
    window: FrameWindow,
}

impl Drop for SendCleanup {
    fn drop(&mut self) {
        for h in [&self.reader, &self.pump].into_iter().flatten() {
            h.abort();
        }
        if let Some(w) = &self.wait {
            w.stop();
        }
        self.window.close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link::cards::Busy;
    use crate::link::channel::MemoryEnd;
    use crate::link::frames::{decode_preamble, SIZE_MAX};
    use crate::link::noise::generate_static;
    use sha2::{Digest, Sha256};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tokio::sync::Semaphore;

    fn temp(tag: &str) -> PathBuf {
        static N: AtomicUsize = AtomicUsize::new(0);
        let dir = std::env::temp_dir().join(format!("notchmeow-xfer-{tag}-{}-{}", std::process::id(), N.fetch_add(1, Ordering::Relaxed)));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn files_in(dir: &PathBuf) -> Vec<String> {
        let mut v: Vec<String> = std::fs::read_dir(dir).map(|d| d.map(|e| e.unwrap().file_name().into_string().unwrap()).collect()).unwrap_or_default();
        v.sort();
        v
    }

    struct Pair {
        sender: Identity,
        receiver: Identity,
        /// The receiver as the sender knows it, and the sender as the receiver knows it.
        r_as_peer: Peer,
        s_as_peer: Peer,
    }

    fn pair() -> Pair {
        let mk = |tag: u8, name: &str| {
            let (key, public) = generate_static().unwrap();
            Identity { device_id: hex(&[tag; 16]), name: name.into(), key, public }
        };
        let (s, r) = (mk(1, "Sam's MacBook Pro"), mk(2, "Desk PC"));
        let r_as_peer = Peer { id: r.device_id.clone(), name: r.name.clone(), key: hex(&r.public), at: 0 };
        let s_as_peer = Peer { id: s.device_id.clone(), name: s.name.clone(), key: hex(&s.public), at: 0 };
        Pair { sender: s, receiver: r, r_as_peer, s_as_peer }
    }

    struct Seen {
        offers: Arc<StdMutex<Vec<Offer>>>,
        progress: Arc<StdMutex<Vec<(u64, u64)>>>,
        hooks: ReceiveHooks,
        busy: Arc<Busy>,
    }

    fn receive_hooks(busy: Arc<Busy>) -> Seen {
        let offers = Arc::new(StdMutex::new(Vec::new()));
        let progress = Arc::new(StdMutex::new(Vec::new()));
        let (o, p, b1, b2) = (offers.clone(), progress.clone(), busy.clone(), busy.clone());
        let hooks = ReceiveHooks {
            offered: Arc::new(move |offer| o.lock().unwrap().push(offer)),
            progress: Arc::new(move |g, t| p.lock().unwrap().push((g, t))),
            claim: Arc::new(move |id| b1.claim(id)),
            release: Arc::new(move |id| b2.release(id)),
            handshake_done: Arc::new(|| {}),
            admit: Arc::new(|| true),
            release_at_end: true,
        };
        Seen { offers, progress, hooks, busy }
    }

    fn spawn_receiver<T: Transport>(end: Arc<T>, p: &Pair, folder: PathBuf, seen: &Seen, timings: ReceiveTimings) -> (ReceiveHandle, JoinHandle<TransferOutcome>) {
        let (handle, inbox) = receive_channel();
        let (id, peer, hooks) = (p.receiver.clone(), p.s_as_peer.clone(), seen.hooks.clone());
        let task = tokio::spawn(async move {
            decode_preamble(&end.receive().await.unwrap()).unwrap(); // the listener reads the preamble first
            run_receive(end, &id, &peer, folder, false, &hooks, timings, inbox).await
        });
        (handle, task)
    }

    fn spawn_sender<T: Transport>(end: Arc<T>, p: &Pair, path: &std::path::Path, timings: SendTimings) -> (SendHandle, JoinHandle<TransferOutcome>, Arc<StdMutex<Vec<(u64, u64)>>>) {
        let (handle, inbox) = send_channel(&end, timings.grace_ms);
        let progress = Arc::new(StdMutex::new(Vec::new()));
        let pr = progress.clone();
        let (id, peer, path) = (p.sender.clone(), p.r_as_peer.clone(), path.to_path_buf());
        let task = tokio::spawn(async move {
            let source = Source::open(&path).unwrap();
            run_send(end, &id, &peer, source, &SendHooks { progress: Arc::new(move |s, t| pr.lock().unwrap().push((s, t))) }, timings, inbox).await
        });
        (handle, task, progress)
    }

    async fn until<F: Fn() -> bool>(what: &str, f: F) {
        for _ in 0..3000 {
            if f() {
                return;
            }
            tokio::time::sleep(Duration::from_millis(2)).await;
        }
        panic!("never happened: {what}");
    }

    fn sha(b: &[u8]) -> String {
        hex(&Sha256::digest(b))
    }

    fn write_file(dir: &PathBuf, name: &str, size: usize) -> (PathBuf, Vec<u8>) {
        let data: Vec<u8> = (0..size).map(|i| (i * 31 % 251) as u8).collect();
        let path = dir.join(name);
        std::fs::write(&path, &data).unwrap();
        (path, data)
    }

    #[tokio::test]
    async fn a_file_goes_over_in_chunks_after_a_click_and_arrives_whole() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let (path, data) = write_file(&src_dir, "report.bin", 100_000);
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let (_sh, stask, sent) = spawn_sender(a, &p, &path, SendTimings::default());
        until("the offer card", || !seen.offers.lock().unwrap().is_empty()).await;
        let offer = seen.offers.lock().unwrap()[0].clone();
        assert_eq!((offer.name.as_str(), offer.size, offer.peer_name.as_str()), ("report.bin", 100_000, "Sam's MacBook Pro"));
        assert!(files_in(&dest).is_empty(), "nothing is written before the click");
        rh.respond(true);
        assert_eq!(stask.await.unwrap(), TransferOutcome::Completed(None));
        let got = match rtask.await.unwrap() {
            TransferOutcome::Completed(Some(path)) => path,
            other => panic!("{other:?}"),
        };
        assert_eq!(sha(&std::fs::read(&got).unwrap()), sha(&data));
        assert_eq!(files_in(&dest), vec!["report.bin"]);
        assert_eq!(*seen.progress.lock().unwrap().last().unwrap(), (100_000, 100_000));
        assert_eq!(sent.lock().unwrap().iter().map(|x| x.0).collect::<Vec<_>>(), vec![32768, 65536, 98304, 100_000]);
        assert!(!seen.busy.holds(&p.s_as_peer.id), "the place is given back");
    }

    #[tokio::test]
    async fn an_empty_file_is_a_transfer_with_no_chunks() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let path = src_dir.join("empty.txt");
        std::fs::write(&path, "").unwrap();
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let (_sh, stask, _) = spawn_sender(a, &p, &path, SendTimings::default());
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        rh.respond(true);
        assert_eq!(stask.await.unwrap(), TransferOutcome::Completed(None));
        assert!(matches!(rtask.await.unwrap(), TransferOutcome::Completed(Some(_))));
        assert_eq!(std::fs::read(dest.join("empty.txt")).unwrap(), b"");
    }

    #[tokio::test]
    async fn a_click_on_decline_saves_nothing_and_the_sender_hears_no() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let (path, _) = write_file(&src_dir, "a.bin", 1000);
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let (_sh, stask, _) = spawn_sender(a, &p, &path, SendTimings::default());
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        rh.respond(false);
        assert_eq!(stask.await.unwrap(), TransferOutcome::Declined { reason: 0 });
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Declined { reason: 0 });
        assert!(files_in(&dest).is_empty());
        assert!(!seen.busy.holds(&p.s_as_peer.id));
    }

    #[tokio::test(start_paused = true)]
    async fn an_offer_nobody_answers_is_declined_after_two_minutes_and_creates_no_file() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let (path, _) = write_file(&src_dir, "a.bin", 1000);
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let (_sh, stask, _) = spawn_sender(a, &p, &path, SendTimings::default());
        tokio::time::sleep(Duration::from_millis(119_000)).await;
        assert!(!rtask.is_finished());
        tokio::time::sleep(Duration::from_millis(1_500)).await;
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Expired);
        assert_eq!(stask.await.unwrap(), TransferOutcome::Declined { reason: 1 });
        assert!(files_in(&dest).is_empty());
    }

    #[tokio::test(start_paused = true)]
    async fn a_sender_whose_offer_nobody_answers_gives_up_on_its_own_after_130_seconds() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let (path, _) = write_file(&src_dir, "a.bin", 1000);
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let timings = ReceiveTimings { offer_timeout_ms: 10 * 60_000, ..ReceiveTimings::default() };
        let (_rh, _rtask) = spawn_receiver(b, &p, dest, &seen, timings);
        let (_sh, stask, _) = spawn_sender(a, &p, &path, SendTimings::default());
        tokio::time::sleep(Duration::from_millis(129_000)).await;
        assert!(!stask.is_finished());
        tokio::time::sleep(Duration::from_millis(2_000)).await;
        assert_eq!(stask.await.unwrap(), TransferOutcome::Expired);
    }

    /// A transport that lets the first `free` sends through and holds the rest until `open` is called: a connection that is slow, so a transfer can be stopped half way.
    struct Paced {
        inner: Arc<MemoryEnd>,
        left: Arc<Semaphore>,
    }

    impl Transport for Paced {
        async fn send(&self, record: Vec<u8>) -> Result<(), LinkError> {
            self.left.acquire().await.map_err(|_| LinkError::Closed)?.forget();
            self.inner.send(record).await
        }
        async fn receive(&self) -> Result<Vec<u8>, LinkError> {
            self.inner.receive().await
        }
        async fn close(&self) {
            self.left.close();
            self.inner.close().await
        }
        fn abort(&self) {
            self.left.close();
            self.inner.abort()
        }
    }

    #[tokio::test]
    async fn the_receiver_cancels_in_the_middle_and_the_partial_file_is_gone() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let (path, _) = write_file(&src_dir, "big.bin", 400_000);
        let (a, b) = MemoryEnd::pair();
        let left = Arc::new(Semaphore::new(3 + 2)); // the preamble, the handshake message, the offer, and two chunks
        let paced = Arc::new(Paced { inner: a, left: left.clone() });
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let (_sh, stask, _) = spawn_sender(paced, &p, &path, SendTimings::default());
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        rh.respond(true);
        until("two chunks", || seen.progress.lock().unwrap().len() >= 2).await;
        assert_eq!(files_in(&dest), vec!["big.bin"], "the file exists while it comes in");
        rh.cancel();
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Cancelled);
        assert_eq!(stask.await.unwrap(), TransferOutcome::Cancelled, "the sender sees a cancel, not a dropped connection");
        assert!(files_in(&dest).is_empty(), "nothing is left");
        assert!(!seen.busy.holds(&p.s_as_peer.id));
    }

    #[tokio::test]
    async fn the_sender_cancels_while_the_offer_waits_and_the_receiver_sees_it_withdrawn() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let (path, _) = write_file(&src_dir, "a.bin", 1000);
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let (sh, stask, _) = spawn_sender(a, &p, &path, SendTimings::default());
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        sh.cancel();
        assert_eq!(stask.await.unwrap(), TransferOutcome::Withdrawn);
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Withdrawn);
        assert!(files_in(&dest).is_empty());
    }

    #[tokio::test]
    async fn a_second_transfer_while_one_runs_is_declined_as_busy_and_gets_no_card() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let (path, _) = write_file(&src_dir, "a.bin", 1000);
        let busy = Arc::new(Busy::default());
        let (first, second) = (receive_hooks(busy.clone()), receive_hooks(busy.clone()));
        let (a1, b1) = MemoryEnd::pair();
        let (a2, b2) = MemoryEnd::pair();
        let (rh1, rtask1) = spawn_receiver(b1, &p, dest.clone(), &first, ReceiveTimings::default());
        let (_s1, stask1, _) = spawn_sender(a1, &p, &path, SendTimings::default());
        until("the first offer", || !first.offers.lock().unwrap().is_empty()).await;
        let (_rh2, rtask2) = spawn_receiver(b2, &p, dest.clone(), &second, ReceiveTimings::default());
        let (_s2, stask2, _) = spawn_sender(a2, &p, &path, SendTimings::default());
        assert_eq!(stask2.await.unwrap(), TransferOutcome::Declined { reason: 2 });
        assert!(second.offers.lock().unwrap().is_empty(), "no card for the second");
        let _ = rtask2.await;
        rh1.respond(true);
        assert_eq!(stask1.await.unwrap(), TransferOutcome::Completed(None));
        let _ = rtask1.await;
    }

    /// The sender played by hand over a real KK handshake, for the cases a real sender never produces.
    async fn manual_sender(end: Arc<MemoryEnd>, p: &Pair) -> Arc<Channel<MemoryEnd>> {
        let remote = key32(&p.r_as_peer.key).unwrap();
        let mut hs = Handshake::new(Pattern::Kk, true, &p.sender.key, Some(&remote), PROLOGUE, None).unwrap();
        end.send(encode_preamble(Mode::Transfer, &id16(&p.sender.device_id).unwrap())).await.unwrap();
        handshake_send(&*end, &mut hs, &[]).await.unwrap();
        handshake_receive(&*end, &mut hs).await.unwrap();
        Arc::new(Channel::new(end, hs.finish().unwrap()))
    }

    fn offer(id: u8, size: u64, name: &str) -> Frame {
        Frame::Offer { id: [id; 16], size, name: name.into(), kind: String::new() }
    }

    #[tokio::test]
    async fn a_hostile_name_is_declined_as_not_acceptable_and_nothing_is_written() {
        let p = pair();
        let dest = temp("dest");
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let ch = manual_sender(a, &p).await;
        ch.send_frame(&offer(1, 10, "../../etc/passwd")).await.unwrap();
        assert_eq!(ch.receive_frame().await.unwrap(), Frame::Decline { id: [1; 16], reason: 4 });
        assert!(seen.offers.lock().unwrap().is_empty());
        assert!(!seen.busy.holds(&p.s_as_peer.id), "the place goes back at once when the machine declined the offer itself");
        // A valid offer after one machine-made decline still gets its card.
        ch.send_frame(&offer(2, 10, "ok.txt")).await.unwrap();
        until("the card", || !seen.offers.lock().unwrap().is_empty()).await;
        ch.send_frame(&Frame::Cancel { id: [2; 16] }).await.unwrap();
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Withdrawn);
        assert!(files_in(&dest).is_empty());
    }

    #[tokio::test]
    async fn the_second_machine_made_decline_on_a_connection_ends_it() {
        let p = pair();
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, rtask) = spawn_receiver(b, &p, temp("dest"), &seen, ReceiveTimings::default());
        let ch = manual_sender(a, &p).await;
        ch.send_frame(&offer(1, 10, "../x")).await.unwrap();
        assert!(matches!(ch.receive_frame().await.unwrap(), Frame::Decline { reason: 4, .. }));
        ch.send_frame(&offer(2, 10, "../y")).await.unwrap();
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Aborted("declines".into()));
        assert!(ch.receive_frame().await.is_err(), "nothing was sent for the second, the connection is closed");
    }

    #[tokio::test]
    async fn a_file_over_4_gib_is_declined_as_too_large() {
        let p = pair();
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, _rtask) = spawn_receiver(b, &p, temp("dest"), &seen, ReceiveTimings::default());
        let ch = manual_sender(a, &p).await;
        ch.send_frame(&offer(1, SIZE_MAX + 1, "big.bin")).await.unwrap();
        assert_eq!(ch.receive_frame().await.unwrap(), Frame::Decline { id: [1; 16], reason: 3 });
        ch.send_frame(&offer(2, SIZE_MAX, "exactly.bin")).await.unwrap();
        until("4 GiB itself gets a card", || !seen.offers.lock().unwrap().is_empty()).await;
    }

    #[tokio::test(start_paused = true)]
    async fn a_connection_that_says_nothing_after_its_handshake_is_closed_after_10_seconds() {
        let p = pair();
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, rtask) = spawn_receiver(b, &p, temp("dest"), &seen, ReceiveTimings::default());
        let _ch = manual_sender(a, &p).await;
        tokio::time::sleep(Duration::from_millis(9_900)).await;
        assert!(!rtask.is_finished());
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Aborted("idle".into()));
    }

    #[tokio::test(start_paused = true)]
    async fn frames_that_are_not_an_offer_do_not_keep_a_silent_connection_alive() {
        let p = pair();
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, rtask) = spawn_receiver(b, &p, temp("dest"), &seen, ReceiveTimings::default());
        let ch = manual_sender(a, &p).await;
        for _ in 0..8 {
            tokio::time::sleep(Duration::from_millis(1_000)).await;
            let _ = ch.send_frame(&Frame::Cancel { id: [9; 16] }).await; // a cancel for a transfer it does not know
        }
        tokio::time::sleep(Duration::from_millis(2_100)).await;
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Aborted("idle".into()));
    }

    #[tokio::test(start_paused = true)]
    async fn a_sender_that_stops_sending_is_cut_after_60_seconds_and_the_partial_file_goes() {
        let p = pair();
        let dest = temp("dest");
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let ch = manual_sender(a, &p).await;
        ch.send_frame(&offer(1, 100, "slow.bin")).await.unwrap();
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        rh.respond(true);
        assert_eq!(ch.receive_frame().await.unwrap(), Frame::Accept { id: [1; 16] });
        ch.send_frame(&Frame::Chunk { id: [1; 16], offset: 0, data: vec![7; 10] }).await.unwrap();
        tokio::time::sleep(Duration::from_millis(59_000)).await;
        assert!(!rtask.is_finished());
        tokio::time::sleep(Duration::from_millis(2_000)).await;
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Aborted("stalled".into()));
        assert!(files_in(&dest).is_empty());
    }

    #[tokio::test(start_paused = true)]
    async fn only_a_chunk_pushes_the_stall_limit_back() {
        let p = pair();
        let dest = temp("dest");
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let ch = manual_sender(a, &p).await;
        ch.send_frame(&offer(1, 100, "slow.bin")).await.unwrap();
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        rh.respond(true);
        ch.receive_frame().await.unwrap();
        // Every second a cancel for a transfer the connection does not know: harmless, and not a sign of life.
        for _ in 0..58 {
            tokio::time::sleep(Duration::from_millis(1_000)).await;
            ch.send_frame(&Frame::Cancel { id: [9; 16] }).await.unwrap();
        }
        tokio::time::sleep(Duration::from_millis(3_000)).await;
        tokio::task::yield_now().await;
        assert!(rtask.is_finished(), "cut 60 s after the accept: the cancels did not count as life");
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Aborted("stalled".into()));
        assert!(files_in(&dest).is_empty());
    }

    #[tokio::test]
    async fn done_before_every_byte_has_come_is_short_and_saves_nothing() {
        let p = pair();
        let dest = temp("dest");
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let ch = manual_sender(a, &p).await;
        ch.send_frame(&offer(1, 10, "short.bin")).await.unwrap();
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        rh.respond(true);
        ch.receive_frame().await.unwrap();
        ch.send_frame(&Frame::Chunk { id: [1; 16], offset: 0, data: vec![1; 5] }).await.unwrap();
        ch.send_frame(&Frame::Done { id: [1; 16] }).await.unwrap();
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Aborted("short".into()));
        assert!(files_in(&dest).is_empty());
    }

    #[tokio::test]
    async fn a_chunk_out_of_order_or_past_the_size_ends_it() {
        for (frames, why) in [
            (vec![Frame::Chunk { id: [1; 16], offset: 5, data: vec![1; 5] }], "order"),
            (vec![Frame::Chunk { id: [1; 16], offset: 0, data: vec![1; 11] }], "overflow"),
            (vec![Frame::Chunk { id: [2; 16], offset: 0, data: vec![1; 5] }], "id"),
        ] {
            let p = pair();
            let dest = temp("dest");
            let (a, b) = MemoryEnd::pair();
            let seen = receive_hooks(Arc::new(Busy::default()));
            let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
            let ch = manual_sender(a, &p).await;
            ch.send_frame(&offer(1, 10, "x.bin")).await.unwrap();
            until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
            rh.respond(true);
            ch.receive_frame().await.unwrap();
            for f in &frames {
                ch.send_frame(f).await.unwrap();
            }
            assert_eq!(rtask.await.unwrap(), TransferOutcome::Aborted(why.into()), "{why}");
            assert!(files_in(&dest).is_empty(), "{why}");
        }
    }

    #[tokio::test]
    async fn a_machine_that_is_not_paired_under_this_key_cannot_complete_the_handshake() {
        let p = pair();
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, rtask) = spawn_receiver(b, &p, temp("dest"), &seen, ReceiveTimings::default());
        // A stranger who knows the sender's device id but holds another key.
        let (stranger, _) = generate_static().unwrap();
        let remote = key32(&p.r_as_peer.key).unwrap();
        let mut hs = Handshake::new(Pattern::Kk, true, &stranger, Some(&remote), PROLOGUE, None).unwrap();
        a.send(encode_preamble(Mode::Transfer, &id16(&p.sender.device_id).unwrap())).await.unwrap();
        handshake_send(&*a, &mut hs, &[]).await.unwrap();
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Aborted("handshake".into()));
        assert!(seen.offers.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn a_kk_handshake_that_carries_a_payload_is_refused() {
        let p = pair();
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, rtask) = spawn_receiver(b, &p, temp("dest"), &seen, ReceiveTimings::default());
        let remote = key32(&p.r_as_peer.key).unwrap();
        let mut hs = Handshake::new(Pattern::Kk, true, &p.sender.key, Some(&remote), PROLOGUE, None).unwrap();
        a.send(encode_preamble(Mode::Transfer, &id16(&p.sender.device_id).unwrap())).await.unwrap();
        handshake_send(&*a, &mut hs, b"smuggled").await.unwrap();
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Aborted("handshake".into()));
    }

    #[tokio::test]
    async fn a_run_that_the_connection_caps_refuse_shows_nothing() {
        let p = pair();
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let mut hooks = seen.hooks.clone();
        hooks.admit = Arc::new(|| false);
        let (handle, inbox) = receive_channel();
        let (id, peer) = (p.receiver.clone(), p.s_as_peer.clone());
        let task = tokio::spawn(async move {
            decode_preamble(&b.receive().await.unwrap()).unwrap();
            run_receive(b, &id, &peer, temp("dest"), false, &hooks, ReceiveTimings::default(), inbox).await
        });
        let _ch = manual_sender(a, &p).await;
        assert_eq!(task.await.unwrap(), TransferOutcome::Aborted("busy".into()));
        assert!(!handle.holds_claim() && seen.offers.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn a_file_that_shrinks_while_it_is_sent_is_cancelled_by_the_sender() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let (path, _) = write_file(&src_dir, "shrinks.bin", 80_000);
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let (handle, inbox) = send_channel(&a, 2_000);
        let (id, peer) = (p.sender.clone(), p.r_as_peer.clone());
        let source = Source::open(&path).unwrap();
        std::fs::write(&path, vec![0u8; 10_000]).unwrap(); // the file is cut down after the offer's size was read; the open handle sees the new length on read
        let task = tokio::spawn(async move { run_send(a, &id, &peer, source, &SendHooks { progress: Arc::new(|_, _| {}) }, SendTimings::default(), inbox).await });
        let _ = handle;
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        rh.respond(true);
        assert_eq!(task.await.unwrap(), TransferOutcome::Aborted("disk".into()));
        assert!(matches!(rtask.await.unwrap(), TransferOutcome::Cancelled));
        assert!(files_in(&dest).is_empty(), "a transfer never completes with fewer bytes than offered");
    }

    #[test]
    fn the_default_watches_are_the_macs_and_the_reviews_numbers() {
        let r = ReceiveTimings::default();
        assert_eq!((r.first_frame_ms, r.stall_ms, r.grace_ms, r.offer_timeout_ms), (10_000, 60_000, 2_000, 120_000));
        let s = SendTimings::default();
        assert_eq!((s.handshake_ms, s.accept_wait_ms, s.stall_ms, s.grace_ms), (10_000, 130_000, 60_000, 2_000));
    }
}
```


**Create `windows/src-tauri/src/link/conformance.rs`:**

```rust
// The recorded conversations (sub-project G2, the cross-check with the Mac): the conversation of `noise-vectors.json` is bytes that the Mac's CryptoKit code produced and an independent
// implementation (`tests/link-crosscheck/xcheck.swift`) confirmed. Here the **real runs** of this app (`run_responder`, `run_initiator`, `run_receive`, `run_send`) are started with the
// vector's keys, ephemeral keys, nonces and names, and the other side is the recording: what the run writes must be the recording's bytes, and what it reads is the recording's. So the
// pairing's payloads (the commitment, the two hellos), the preamble, the Noise messages and the code that comes out are the same on both apps, byte for byte, without the two apps ever
// running together. (The vector's transport messages hold test bytes and not frames, so the replay stops after the handshake.) The ephemeral key is pinned through
// `noise::FIXED_EPHEMERAL`, which exists in test builds only.

use std::sync::{Arc, Mutex};

use serde_json::Value;

use super::bytes::{hex, id16, key32, unhex};
use super::channel::{MemoryEnd, Transport};
use super::files::Source;
use super::frames::{decode_hello, decode_preamble, Mode};
use super::identity::{Identity, Peer};
use super::noise::{public_of, FIXED_EPHEMERAL};
use super::pair_run::{pair_channel, run_initiator, run_responder, Clock, PairHooks};
use super::pairing::{Ids, Initiator, Responder};
use super::testutil::{arr, fixture};
use super::transfer::{receive_channel, run_receive, run_send, send_channel, ReceiveHooks, ReceiveTimings, SendHooks, SendTimings};

fn vector(id: &str) -> Value {
    arr(&fixture("noise-vectors.json"), "vectors").iter().find(|v| v["id"] == id).unwrap_or_else(|| panic!("vector {id}")).clone()
}

fn bytes_of(v: &Value, i: usize, field: &str) -> Vec<u8> {
    unhex(arr(v, "messages")[i][field].as_str().unwrap()).unwrap()
}

fn key(v: &Value, name: &str) -> [u8; 32] {
    key32(v[name].as_str().unwrap()).unwrap()
}

fn clock() -> Clock {
    Arc::new(|| 1_000)
}

fn identity(private: [u8; 32], device_id: [u8; 16], name: &str) -> Identity {
    Identity { device_id: hex(&device_id), name: name.to_string(), key: private, public: public_of(&private).unwrap() }
}

fn hooks(shown: Arc<Mutex<Vec<(String, String)>>>) -> PairHooks {
    PairHooks { show_code: Arc::new(move |code, name| shown.lock().unwrap().push((code, name))), handshake_done: Arc::new(|| {}) }
}

async fn code_shown(shown: &Arc<Mutex<Vec<(String, String)>>>) -> (String, String) {
    for _ in 0..2000 {
        if let Some(x) = shown.lock().unwrap().first() {
            return x.clone();
        }
        tokio::time::sleep(std::time::Duration::from_millis(2)).await;
    }
    panic!("no code was shown");
}

#[tokio::test]
async fn the_responder_run_speaks_the_recorded_pairing_byte_for_byte_and_shows_the_recorded_code() {
    let v = vector("xx-link");
    let session = &fixture("pairing-cases.json")["session"];
    let my_hello = decode_hello(&bytes_of(&v, 1, "payload")).unwrap(); // the responder's hello: its id, its nonce, its name
    let their_hello = decode_hello(&bytes_of(&v, 2, "payload")).unwrap();
    let me = identity(key(&v, "resp_static"), my_hello.id, &my_hello.name);
    FIXED_EPHEMERAL.with(|c| c.set(Some(key(&v, "resp_ephemeral"))));
    let (recording, end) = MemoryEnd::pair();
    let shown = Arc::new(Mutex::new(Vec::new()));
    let (_handle, inbox) = pair_channel();
    let h = hooks(shown.clone());
    let nonce = my_hello.nonce;
    let run = tokio::spawn(async move {
        let pre = decode_preamble(&end.receive().await.unwrap()).unwrap(); // the listener reads the preamble first
        assert_eq!(pre.mode, Mode::Pair);
        run_responder(end, &me, nonce, clock(), Responder::new(Ids::default()), &h, inbox).await
    });
    recording.send(super::frames::encode_preamble(Mode::Pair, &[0; 16])).await.unwrap();
    recording.send(bytes_of(&v, 0, "ciphertext")).await.unwrap();
    assert_eq!(recording.receive().await.unwrap(), bytes_of(&v, 1, "ciphertext"), "the responder's reply is the recording's");
    recording.send(bytes_of(&v, 2, "ciphertext")).await.unwrap();
    let (code, peer_name) = code_shown(&shown).await;
    assert_eq!(code, session["code"].as_str().unwrap(), "the six digits are the recorded ones");
    assert_eq!(peer_name, their_hello.name);
    recording.close().await;
    let _ = run.await;
}

#[tokio::test]
async fn the_initiator_run_speaks_the_recorded_pairing_byte_for_byte_and_shows_the_recorded_code() {
    let v = vector("xx-link");
    let session = &fixture("pairing-cases.json")["session"];
    let their_hello = decode_hello(&bytes_of(&v, 1, "payload")).unwrap();
    let my_hello = decode_hello(&bytes_of(&v, 2, "payload")).unwrap(); // the initiator's reveal: its id, its nonce, its name
    let me = identity(key(&v, "init_static"), my_hello.id, &my_hello.name);
    FIXED_EPHEMERAL.with(|c| c.set(Some(key(&v, "init_ephemeral"))));
    let (end, recording) = MemoryEnd::pair();
    let shown = Arc::new(Mutex::new(Vec::new()));
    let (_handle, inbox) = pair_channel();
    let h = hooks(shown.clone());
    let nonce = my_hello.nonce;
    let run = tokio::spawn(async move { run_initiator(end, &me, nonce, clock(), Initiator::new(Ids::default()), &h, inbox).await });
    let pre = decode_preamble(&recording.receive().await.unwrap()).unwrap();
    assert_eq!((pre.mode, pre.id), (Mode::Pair, [0; 16]));
    assert_eq!(recording.receive().await.unwrap(), bytes_of(&v, 0, "ciphertext"), "the commitment goes out as recorded");
    recording.send(bytes_of(&v, 1, "ciphertext")).await.unwrap();
    assert_eq!(recording.receive().await.unwrap(), bytes_of(&v, 2, "ciphertext"), "and so does the reveal");
    let (code, peer_name) = code_shown(&shown).await;
    assert_eq!(code, session["code"].as_str().unwrap(), "the six digits are the recorded ones");
    assert_eq!(peer_name, their_hello.name);
    recording.close().await;
    let _ = run.await;
}

fn receive_hooks() -> ReceiveHooks {
    ReceiveHooks {
        offered: Arc::new(|_| {}),
        progress: Arc::new(|_, _| {}),
        claim: Arc::new(|_| true),
        release: Arc::new(|_| {}),
        handshake_done: Arc::new(|| {}),
        admit: Arc::new(|| true),
        release_at_end: true,
    }
}

#[tokio::test]
async fn the_receiving_run_answers_the_recorded_transfer_handshake_byte_for_byte() {
    let v = vector("kk-link");
    let sender = identity(key(&v, "init_static"), [0x11; 16], "Sender");
    let me = identity(key(&v, "resp_static"), [0x22; 16], "Receiver");
    let peer = Peer { id: sender.device_id.clone(), name: sender.name.clone(), key: hex(&sender.public), at: 0 };
    FIXED_EPHEMERAL.with(|c| c.set(Some(key(&v, "resp_ephemeral"))));
    let (recording, end) = MemoryEnd::pair();
    let (_handle, inbox) = receive_channel();
    let run = tokio::spawn(async move {
        decode_preamble(&end.receive().await.unwrap()).unwrap();
        run_receive(end, &me, &peer, std::env::temp_dir().join("notchmeow-conformance"), false, &receive_hooks(), ReceiveTimings::default(), inbox).await
    });
    recording.send(super::frames::encode_preamble(Mode::Transfer, &id16(&sender.device_id).unwrap())).await.unwrap();
    recording.send(bytes_of(&v, 0, "ciphertext")).await.unwrap();
    assert_eq!(recording.receive().await.unwrap(), bytes_of(&v, 1, "ciphertext"), "the receiver's reply is the recording's");
    recording.close().await;
    let _ = run.await;
}

#[tokio::test]
async fn the_sending_run_opens_the_recorded_transfer_handshake_byte_for_byte() {
    let v = vector("kk-link");
    let me = identity(key(&v, "init_static"), [0x11; 16], "Sender");
    let receiver = identity(key(&v, "resp_static"), [0x22; 16], "Receiver");
    let peer = Peer { id: receiver.device_id.clone(), name: receiver.name.clone(), key: hex(&receiver.public), at: 0 };
    FIXED_EPHEMERAL.with(|c| c.set(Some(key(&v, "init_ephemeral"))));
    let dir = std::env::temp_dir().join(format!("notchmeow-conformance-src-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join("a.txt");
    std::fs::write(&file, b"hello").unwrap();
    let (end, recording) = MemoryEnd::pair();
    let (_handle, inbox) = send_channel(&end, 2_000);
    let source = Source::open(&file).unwrap();
    let run = tokio::spawn(async move { run_send(end, &me, &peer, source, &SendHooks { progress: Arc::new(|_, _| {}) }, SendTimings::default(), inbox).await });
    let pre = decode_preamble(&recording.receive().await.unwrap()).unwrap();
    assert_eq!((pre.mode, hex(&pre.id)), (Mode::Transfer, hex(&[0x11; 16])));
    assert_eq!(recording.receive().await.unwrap(), bytes_of(&v, 0, "ciphertext"), "the sender's opening is the recording's");
    recording.send(bytes_of(&v, 1, "ciphertext")).await.unwrap();
    recording.close().await;
    let _ = run.await;
}
```


- [ ] **Step 3: Run the tests**

Run:

```bash
for m in channel pair_run transfer conformance; do windows/scripts/cargo-linux.sh test --target-dir /repo/windows/target/g2-tauri -p notchmeow link::$m 2>&1 | grep -E "test result|FAILED|panicked"; done
```

Expected: `ok. 9 passed` (channel), `ok. 9 passed` (pair_run), `ok. 22 passed` (transfer), `ok. 4 passed` (conformance). **If `conformance` fails** the two apps disagree, or `noise.rs` (Task 2) does not behave as the recording: read the failing assertion (it names the message), compare with `tests/fixtures/link/noise-vectors.json`, and fix the code that is wrong. **The Mac's own copy of this conversation is the reference** (`tests/link-crosscheck/xcheck.swift` confirms the vectors independently): never edit a vector or an expected byte to make a test pass. The tests of the other three modules were written and run against a stand-in Noise during the drafting of this plan (see "Dry run"); a failure there that depends on how `snow` treats a payload, a short message or a nonce is the real finding of this task: report it with the message.

The Review Focus tests of this task are in the lists above: `outside_the_gate_nothing_is_sent_and_no_card_is_shown`, `a_machine_that_is_not_paired_under_this_key_cannot_complete_the_handshake`, `a_connection_that_says_nothing_after_its_handshake_is_closed_after_10_seconds`, `frames_that_are_not_an_offer_do_not_keep_a_silent_connection_alive` (focus 1); `a_hostile_name_is_declined_as_not_acceptable_and_nothing_is_written` (2); `the_receiver_cancels_in_the_middle_and_the_partial_file_is_gone`, `a_sender_that_stops_sending_is_cut_after_60_seconds_and_the_partial_file_goes`, `done_before_every_byte_has_come_is_short_and_saves_nothing`, `a_file_that_shrinks_while_it_is_sent_is_cancelled_by_the_sender` (3); `an_offer_nobody_answers_is_declined_after_two_minutes_and_creates_no_file`, `a_second_transfer_while_one_runs_is_declined_as_busy_and_gets_no_card` (5).

- [ ] **Step 4: Prove it bites**

Run:

```bash
M="python3 .claude/checkpoints/g2-tauri/mut.py rust"
$M windows/src-tauri/src/link/channel.rs 'pub const FRAMES: usize = 4;' 'pub const FRAMES: usize = 5;' link::channel
$M windows/src-tauri/src/link/transfer.rs 'accept_wait_ms: 130_000' 'accept_wait_ms: 131_000' link::transfer
$M windows/src-tauri/src/link/transfer.rs 'stall_ms: 60_000, grace_ms: 2_000, offer_timeout_ms' 'stall_ms: 61_000, grace_ms: 2_000, offer_timeout_ms' link::transfer
```

Expected: each prints `FAILED` (`four_frames_may_wait_for_the_conversation`; `the_default_watches_are_the_macs_and_the_reviews_numbers` twice). The same changes made in the first draft of the plan left every test green: that is why these two tests exist.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/src-tauri/src/link/mod.rs windows/src-tauri/src/link/channel.rs windows/src-tauri/src/link/pair_run.rs windows/src-tauri/src/link/transfer.rs windows/src-tauri/src/link/conformance.rs
git commit -F - <<'MSG'
feat(link): the connection layer, the pairing run and the transfer runs, and the recorded conversations (G2-tauri)

Transport, Channel, IdleWatch and FrameWindow; one pairing conversation and one transfer conversation on either side, with every watch the Mac's reviews arrived at (10 s first frame, 60 s chunk stall, 2 minute offer, 130 s sender wait, 2 s per frame, 4 frames in the window); the real runs replayed against the recorded conversations of noise-vectors.json, byte for byte.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Write the task's line in the ledger.

---


### Task 12: The network: transport, listener, the advert and the browser

**Agent:** `nm-implementer-deep` (**Sonnet 5.5, high; trigger 1**: sockets, a listener that strangers can reach, a multicast daemon, threads). The code is given in full. `net.rs` and `discovery.rs` were compiled and tested while the plan was drafted; **`mdns.rs` was written against `mdns-sd` 0.11 from its documented API and never compiled** (the crate was not available offline): step 3 is the check, and the executor adapts the file to the crate's real API where it differs, changing nothing else.

**Files:**
- Create: `windows/src-tauri/src/link/net.rs`, `discovery.rs`, `mdns.rs`
- Modify: `windows/src-tauri/src/link/mod.rs`

**Interfaces:**
- Consumes: `channel::{Transport, LinkError}`, `frames::{encode_record, split_records, Advert, parse_txt, Txt, OwnId}`.
- Produces: `net::{TcpTransport::{new(stream), connect(addr, timeout), peer_ip()}, Listener::{start(bind, on_connection, handshake), port(), stop()}, PendingSlot { is_finished(), finish() }, OnConnection, MAX_PENDING (8), MAX_PENDING_PER_SOURCE (2), HANDSHAKE_SECONDS (10)}`; `discovery::{Discovery (advertise(id, name, port), stop_advertising(), browse(own_id, on_results), stop_browsing()), Found { advert, addr }, OnResults, SERVICE_TYPE = "_notchmeow._tcp.local."}`; `mdns::Mdns` (`Discovery` over `mdns-sd`, `Mdns::new()`).

**What a stranger on the Wi-Fi can and cannot do here.** The listener exists only while the service starts it (Task 13: only when Visible is on); it binds IPv4 on a port the system picks and **nothing listens before that**. A connection that has not finished its handshake in 10 s is cut (a watchdog that is one task per connection, a one-shot timer), at most 8 wait for that at once and 2 from one address (the address is a key in memory, never logged; a ninth or a third is closed without a byte), a record of length 0 closes the connection, a record is at most 65 535 bytes so the buffer stays small, and `abort()` cuts a pending read at once and the peer sees the end (the transport holds a second handle on the socket for that, so a stuck read cannot hold a shutdown). Nothing polls: the accept loop and each read wait on their sockets. The advert carries only `v`, `id` and `name` (the contract's TXT record); the DNS host name is made from the first 8 hex digits of the device id and **never from the computer's name**; IPv6 is switched off in the daemon, as the listener is IPv4. The mDNS daemon opens multicast sockets and starts a thread when it is made, so `Mdns` makes it **on first use and shuts it down when nothing is announced and nobody is searching**: with Visible off and neither Devices nor the shelf on screen, the process has no mDNS socket (a wiring pin in Task 13 checks that `ServiceDaemon::new` is called in this one place).

- [ ] **Step 1: Register the modules**

Run:

```bash
python3 - <<'EOF'
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")
edit("windows/src-tauri/src/link/mod.rs", "// MODULES: add new modules above this line", "pub mod discovery;\npub mod mdns;\npub mod net;\n// MODULES: add new modules above this line")
EOF
```

- [ ] **Step 2: The files**

**Create `windows/src-tauri/src/link/net.rs`:**

```rust
// The link on the network (sub-project G2): a transport over a TCP connection, and the listener that accepts connections. Everything here is event-driven: the listener waits on a socket and the
// connection reads wait on their sockets, and **nothing polls**. There is no listener until the service is told the machine is visible on the network (Settings → Devices, off by default).
// The Mac's twin is LinkNetwork.swift (the advert and the browser are `discovery.rs` here).
//
// Hardening that the contract does not need but a listener on a LAN does: a connection that has not finished its handshake in 10 seconds is cut, and no more than 8 connections wait at once
// for that (`MAX_PENDING`), 2 of them from one address (`MAX_PENDING_PER_SOURCE`; the address is a key in memory, never logged); records are cut by `frames::split_records` (a length of 0
// closes, a record is at most 65535 bytes, so the buffer stays small).

use std::collections::{HashMap, VecDeque};
use std::net::{IpAddr, Shutdown, SocketAddr};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex as StdMutex};
use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{Mutex, Notify};
use tokio::task::JoinHandle;

use super::channel::{LinkError, Transport};
use super::frames::{encode_record, split_records};

struct ReadSide {
    half: OwnedReadHalf,
    buffer: Vec<u8>,
    queue: VecDeque<Vec<u8>>,
    ended: bool,
}

/// A TCP connection as a `Transport`: the bytes of the stream are cut into whole records on the way in and given a length on the way out. One reader at a time (the conversation's reader task).
pub struct TcpTransport {
    read: Mutex<ReadSide>,
    write: Mutex<Option<OwnedWriteHalf>>,
    /// A second handle on the same socket, so that `abort` can cut it from any thread: a `shutdown` fails a pending read and a pending write at once, even one stuck behind a peer that stopped reading.
    killer: std::net::TcpStream,
    aborted: AtomicBool,
    cut: Notify,
}

impl TcpTransport {
    pub fn new(stream: TcpStream) -> std::io::Result<Arc<TcpTransport>> {
        let std_stream = stream.into_std()?;
        let killer = std_stream.try_clone()?;
        std_stream.set_nonblocking(true)?;
        let stream = TcpStream::from_std(std_stream)?;
        let _ = stream.set_nodelay(true);
        let (half, write) = stream.into_split();
        Ok(Arc::new(TcpTransport { read: Mutex::new(ReadSide { half, buffer: Vec::new(), queue: VecDeque::new(), ended: false }), write: Mutex::new(Some(write)), killer, aborted: AtomicBool::new(false), cut: Notify::new() }))
    }

    /// Opens a connection and waits for it no longer than `timeout`.
    pub async fn connect(addr: SocketAddr, timeout: Duration) -> Result<Arc<TcpTransport>, LinkError> {
        let stream = tokio::time::timeout(timeout, TcpStream::connect(addr)).await.map_err(|_| LinkError::Io("connect timeout".into()))?.map_err(|e| LinkError::Io(e.kind().to_string()))?;
        TcpTransport::new(stream).map_err(|e| LinkError::Io(e.kind().to_string()))
    }

    /// The other end's address, as a key for the per-address cap. Never logged, never shown.
    pub fn peer_ip(&self) -> Option<IpAddr> {
        self.killer.peer_addr().ok().map(|a| a.ip())
    }
}

impl Transport for TcpTransport {
    async fn send(&self, record: Vec<u8>) -> Result<(), LinkError> {
        let framed = encode_record(&record).map_err(|_| LinkError::Violation("record length".into()))?;
        if self.aborted.load(Ordering::SeqCst) {
            return Err(LinkError::Closed);
        }
        let mut guard = self.write.lock().await;
        let Some(w) = guard.as_mut() else { return Err(LinkError::Closed) };
        tokio::select! {
            r = w.write_all(&framed) => r.map_err(|e| LinkError::Io(e.kind().to_string())),
            _ = self.cut.notified() => Err(LinkError::Closed),
        }
    }

    async fn receive(&self) -> Result<Vec<u8>, LinkError> {
        let mut side = self.read.lock().await;
        let mut chunk = vec![0u8; 65_537];
        loop {
            if let Some(r) = side.queue.pop_front() {
                return Ok(r);
            }
            if side.ended || self.aborted.load(Ordering::SeqCst) {
                return Err(LinkError::Closed);
            }
            let n = tokio::select! {
                n = side.half.read(&mut chunk) => n.unwrap_or(0),
                _ = self.cut.notified() => 0,
            };
            if n == 0 {
                side.ended = true;
                return Err(LinkError::Closed);
            }
            side.buffer.extend_from_slice(&chunk[..n]);
            match split_records(&side.buffer) {
                Ok((records, rest)) => {
                    side.buffer = rest;
                    side.queue.extend(records);
                }
                Err(_) => {
                    side.ended = true;
                    let _ = self.killer.shutdown(Shutdown::Both); // a record of length 0
                    return Err(LinkError::Violation("record".into()));
                }
            }
        }
    }

    /// Sends what is queued, tells the other side the stream is finished, and closes. A cut connection has nothing to flush.
    async fn close(&self) {
        if self.aborted.load(Ordering::SeqCst) {
            return;
        }
        if let Some(mut w) = self.write.lock().await.take() {
            let _ = tokio::select! { r = w.shutdown() => r, _ = self.cut.notified() => Ok(()) };
        }
        let _ = self.killer.shutdown(Shutdown::Both);
    }

    /// Hard stop: for a connection that is too slow. The pending reads and writes then fail and the conversation ends.
    fn abort(&self) {
        self.aborted.store(true, Ordering::SeqCst);
        let _ = self.killer.shutdown(Shutdown::Both);
        self.cut.notify_waiters();
    }
}

pub const MAX_PENDING: usize = 8;
pub const MAX_PENDING_PER_SOURCE: usize = 2;
pub const HANDSHAKE_SECONDS: u64 = 10;

/// A connection that has been accepted but has not finished its handshake. The service calls `finish()` when it has (or when it refuses the connection); until then a watchdog cuts the connection
/// `HANDSHAKE_SECONDS` after it was accepted, and the slot counts against `MAX_PENDING`.
#[derive(Clone)]
pub struct PendingSlot {
    inner: Arc<SlotInner>,
}

struct SlotInner {
    done: AtomicBool,
    release: StdMutex<Option<Box<dyn FnOnce() + Send>>>,
    watchdog: StdMutex<Option<JoinHandle<()>>>,
}

impl PendingSlot {
    pub fn is_finished(&self) -> bool {
        self.inner.done.load(Ordering::SeqCst)
    }

    pub fn finish(&self) {
        if self.inner.done.swap(true, Ordering::SeqCst) {
            return;
        }
        if let Some(w) = self.inner.watchdog.lock().unwrap().take() {
            w.abort();
        }
        if let Some(r) = self.inner.release.lock().unwrap().take() {
            r();
        }
    }
}

#[derive(Default)]
struct Pending {
    total: usize,
    by_source: HashMap<IpAddr, usize>,
}

pub type OnConnection = Arc<dyn Fn(Arc<TcpTransport>, PendingSlot) + Send + Sync>;

/// The listener: accepts connections and hands each new one to the service. It exists only while the machine is visible on the network.
pub struct Listener {
    port: u16,
    stop: Arc<Notify>,
    stopped: Arc<AtomicBool>,
    task: JoinHandle<()>,
}

impl Listener {
    /// Starts listening. `bind` is `0.0.0.0:0` for the network (the system chooses the port) and `127.0.0.1:0` for the tests. IPv4 only: the advert is IPv4 only too (`discovery.rs`).
    pub async fn start(bind: SocketAddr, on_connection: OnConnection, handshake: Duration) -> std::io::Result<Listener> {
        let listener = TcpListener::bind(bind).await?;
        let port = listener.local_addr()?.port();
        let (stop, stopped) = (Arc::new(Notify::new()), Arc::new(AtomicBool::new(false)));
        let (s, flag) = (stop.clone(), stopped.clone());
        let pending = Arc::new(StdMutex::new(Pending::default()));
        let task = tokio::spawn(async move {
            loop {
                if flag.load(Ordering::SeqCst) {
                    return;
                }
                let accepted = tokio::select! {
                    a = listener.accept() => a,
                    _ = s.notified() => return,
                };
                let Ok((stream, from)) = accepted else {
                    tokio::time::sleep(Duration::from_millis(50)).await; // a transient accept error (descriptors): do not spin
                    continue;
                };
                let source = from.ip();
                let admitted = {
                    let mut p = pending.lock().unwrap();
                    if p.total >= MAX_PENDING || p.by_source.get(&source).copied().unwrap_or(0) >= MAX_PENDING_PER_SOURCE {
                        false
                    } else {
                        p.total += 1;
                        *p.by_source.entry(source).or_insert(0) += 1;
                        true
                    }
                };
                if !admitted {
                    drop(stream);
                    continue;
                }
                let Ok(transport) = TcpTransport::new(stream) else {
                    release(&pending, source);
                    continue;
                };
                let pend = pending.clone();
                let slot = PendingSlot { inner: Arc::new(SlotInner { done: AtomicBool::new(false), release: StdMutex::new(Some(Box::new(move || release(&pend, source)))), watchdog: StdMutex::new(None) }) };
                // The handshake clock starts at accept: the watchdog cuts the connection if the service has not finished the handshake in time.
                let (wslot, wt) = (slot.clone(), transport.clone());
                let dog = tokio::spawn(async move {
                    tokio::time::sleep(handshake).await;
                    if !wslot.is_finished() {
                        wt.abort();
                        wslot.finish();
                    }
                });
                *slot.inner.watchdog.lock().unwrap() = Some(dog);
                on_connection(transport, slot);
            }
        });
        Ok(Listener { port, stop, stopped, task })
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    pub fn stop(&self) {
        self.stopped.store(true, Ordering::SeqCst);
        self.stop.notify_one();
        self.task.abort();
    }
}

impl Drop for Listener {
    fn drop(&mut self) {
        self.stop();
    }
}

fn release(pending: &Arc<StdMutex<Pending>>, source: IpAddr) {
    let mut p = pending.lock().unwrap();
    p.total = p.total.saturating_sub(1);
    if let Some(n) = p.by_source.get_mut(&source) {
        *n = n.saturating_sub(1);
        if *n == 0 {
            p.by_source.remove(&source);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;

    fn lo() -> SocketAddr {
        "127.0.0.1:0".parse().unwrap()
    }

    /// A listener on the loopback address that hands every connection to a channel, with its slot.
    async fn listen(handshake: Duration) -> (Listener, tokio::sync::mpsc::UnboundedReceiver<(Arc<TcpTransport>, PendingSlot)>) {
        let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
        let l = Listener::start(lo(), Arc::new(move |t, s| { let _ = tx.send((t, s)); }), handshake).await.unwrap();
        (l, rx)
    }

    #[tokio::test]
    async fn records_go_both_ways_over_real_tcp() {
        let (l, mut rx) = listen(Duration::from_secs(10)).await;
        let client = TcpTransport::connect(SocketAddr::new("127.0.0.1".parse().unwrap(), l.port()), Duration::from_secs(5)).await.unwrap();
        let (server, slot) = rx.recv().await.unwrap();
        client.send(vec![1, 2, 3]).await.unwrap();
        client.send(vec![9; 65_535]).await.unwrap();
        assert_eq!(server.receive().await.unwrap(), vec![1, 2, 3]);
        assert_eq!(server.receive().await.unwrap().len(), 65_535);
        server.send(vec![7; 100]).await.unwrap();
        assert_eq!(client.receive().await.unwrap(), vec![7; 100]);
        assert_eq!(client.send(vec![0; 65_536]).await.unwrap_err(), LinkError::Violation("record length".into()));
        assert_eq!(client.send(vec![]).await.unwrap_err(), LinkError::Violation("record length".into()));
        slot.finish();
        client.close().await;
        assert_eq!(server.receive().await.unwrap_err(), LinkError::Closed);
    }

    #[tokio::test]
    async fn a_record_of_length_zero_closes_the_connection() {
        let (l, mut rx) = listen(Duration::from_secs(10)).await;
        let mut raw = TcpStream::connect(SocketAddr::new("127.0.0.1".parse().unwrap(), l.port())).await.unwrap();
        let (server, _slot) = rx.recv().await.unwrap();
        raw.write_all(&[0, 0]).await.unwrap();
        assert_eq!(server.receive().await.unwrap_err(), LinkError::Violation("record".into()));
        assert_eq!(server.receive().await.unwrap_err(), LinkError::Closed);
    }

    #[tokio::test]
    async fn two_records_in_one_segment_and_one_record_in_two_come_out_whole() {
        let (l, mut rx) = listen(Duration::from_secs(10)).await;
        let mut raw = TcpStream::connect(SocketAddr::new("127.0.0.1".parse().unwrap(), l.port())).await.unwrap();
        let (server, _slot) = rx.recv().await.unwrap();
        raw.write_all(&[0, 2, 0xAA, 0xBB, 0, 1, 0xCC, 0, 3, 1]).await.unwrap();
        assert_eq!(server.receive().await.unwrap(), vec![0xAA, 0xBB]);
        assert_eq!(server.receive().await.unwrap(), vec![0xCC]);
        raw.write_all(&[2, 3]).await.unwrap();
        assert_eq!(server.receive().await.unwrap(), vec![1, 2, 3]);
    }

    #[tokio::test]
    async fn an_abort_cuts_a_pending_read_at_once_and_the_peer_sees_the_end() {
        let (l, mut rx) = listen(Duration::from_secs(10)).await;
        let client = TcpTransport::connect(SocketAddr::new("127.0.0.1".parse().unwrap(), l.port()), Duration::from_secs(5)).await.unwrap();
        let (server, _slot) = rx.recv().await.unwrap();
        let s2 = server.clone();
        let pending = tokio::spawn(async move { s2.receive().await });
        tokio::task::yield_now().await;
        server.abort();
        assert_eq!(pending.await.unwrap().unwrap_err(), LinkError::Closed);
        assert_eq!(client.receive().await.unwrap_err(), LinkError::Closed);
        assert_eq!(server.send(vec![1]).await.unwrap_err(), LinkError::Closed);
    }

    // Real time and a short handshake: a paused clock would run a connect's own timeout out before the socket answered.
    #[tokio::test]
    async fn a_connection_that_does_not_finish_its_handshake_in_time_is_cut_and_its_place_freed() {
        let (l, mut rx) = listen(Duration::from_millis(300)).await;
        let addr = SocketAddr::new("127.0.0.1".parse().unwrap(), l.port());
        let silent = TcpTransport::connect(addr, Duration::from_secs(5)).await.unwrap();
        let (server, slot) = rx.recv().await.unwrap();
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert!(!slot.is_finished());
        tokio::time::sleep(Duration::from_millis(400)).await;
        assert!(slot.is_finished(), "the watchdog fired");
        assert_eq!(server.receive().await.unwrap_err(), LinkError::Closed);
        assert_eq!(silent.receive().await.unwrap_err(), LinkError::Closed);
    }

    #[tokio::test]
    async fn at_most_two_connections_wait_from_one_address() {
        let (l, mut rx) = listen(Duration::from_secs(60)).await;
        let addr = SocketAddr::new("127.0.0.1".parse().unwrap(), l.port());
        let mut clients = vec![];
        for _ in 0..4 {
            clients.push(TcpStream::connect(addr).await.unwrap());
        }
        let got = Arc::new(AtomicUsize::new(0));
        let mut slots = vec![];
        while let Ok(Some(x)) = tokio::time::timeout(Duration::from_millis(300), rx.recv()).await {
            got.fetch_add(1, Ordering::SeqCst);
            slots.push(x);
        }
        assert_eq!(got.load(Ordering::SeqCst), 2, "the third and fourth connection from this address were dropped at once");
        slots.remove(0).1.finish();
        let _again = TcpStream::connect(addr).await.unwrap();
        let next = tokio::time::timeout(Duration::from_secs(2), rx.recv()).await.unwrap();
        assert!(next.is_some(), "a place that was freed is used again");
        drop(clients);
    }

    #[tokio::test]
    async fn a_stopped_listener_accepts_nothing() {
        let (l, _rx) = listen(Duration::from_secs(10)).await;
        let addr = SocketAddr::new("127.0.0.1".parse().unwrap(), l.port());
        l.stop();
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert!(TcpStream::connect(addr).await.is_err(), "nothing listens");
    }

    #[test]
    fn the_listener_numbers_are_the_macs_and_the_reviews_numbers() {
        assert_eq!((MAX_PENDING, MAX_PENDING_PER_SOURCE, HANDSHAKE_SECONDS), (8, 2, 10));
    }
}
```


**Create `windows/src-tauri/src/link/discovery.rs`:**

```rust
// Finding the other machines (sub-project G2, docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md, "Discovery"): the advert of this machine and the browser for the others, both
// `_notchmeow._tcp` over mDNS. The service talks to this small trait, so everything above it is tested without a network; `Mdns` (the `mdns-sd` crate, pure Rust, no Avahi needed) is the
// one implementation that touches the network. The advert carries only `v`, `id` and `name`; it gives a machine something to show in a list and nothing more: only a paired key gets a session.

use std::net::SocketAddr;
use std::sync::Arc;

use super::frames::Advert;

pub const SERVICE_TYPE: &str = "_notchmeow._tcp.local.";

/// A machine seen on the network: what its advert says, and where to connect to it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Found {
    pub advert: Advert,
    pub addr: SocketAddr,
}

pub type OnResults = Arc<dyn Fn(Vec<Found>) + Send + Sync>;

pub trait Discovery: Send + Sync + 'static {
    /// Announces this machine (or announces it again under a new name). `Err` is a sentence for Settings → Devices.
    fn advertise(&self, id: &str, name: &str, port: u16) -> Result<(), String>;
    fn stop_advertising(&self);
    /// Starts looking for the others; `on_results` gets the whole list every time it changes. An advert that does not pass `parse_txt` (version, id, name, this machine's own id) is not listed.
    fn browse(&self, own_id: &str, on_results: OnResults) -> Result<(), String>;
    fn stop_browsing(&self);
}
```


**Create `windows/src-tauri/src/link/mdns.rs`:**

```rust
// The one implementation of `Discovery` that touches the network (sub-project G2): `_notchmeow._tcp` over mDNS with the `mdns-sd` crate (pure Rust, no Avahi or Bonjour service needed; the owner
// approved the crate on 2026-10-14). The advert carries only `v`, `id` and `name`; the host name in the DNS records is made from the first eight digits of the device id, never from the
// computer's name. IPv4 only, as the listener is: IPv6 is switched off in the daemon.
//
// **The daemon exists only while something needs it.** Making a `ServiceDaemon` opens the multicast sockets and starts its thread, so it is made when the machine is first announced or the
// first search starts, and shut down when both are over: with Visible off and nobody looking at Devices or the shelf, this file holds nothing and the process has no mDNS socket.
// `scripts/link-tests/wiring.test.mjs` pins that `ServiceDaemon::new` is called only here, in `daemon()`.

use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::sync::Mutex;

use mdns_sd::{IfKind, ServiceDaemon, ServiceEvent, ServiceInfo};

use super::discovery::{Discovery, Found, OnResults, SERVICE_TYPE};
use super::frames::{parse_txt, OwnId, Txt};

#[derive(Default)]
struct Inner {
    daemon: Option<ServiceDaemon>,
    /// The full name of the service this machine announces, while it does.
    advertised: Option<String>,
    browsing: bool,
}

#[derive(Default)]
pub struct Mdns {
    inner: Mutex<Inner>,
}

impl Mdns {
    pub fn new() -> Mdns {
        Mdns::default()
    }

    /// The daemon, made on first use. IPv6 is switched off: the advert and the listener are IPv4.
    fn daemon(inner: &mut Inner) -> Result<ServiceDaemon, String> {
        if let Some(d) = &inner.daemon {
            return Ok(d.clone());
        }
        let d = ServiceDaemon::new().map_err(|e| e.to_string())?;
        let _ = d.disable_interface(IfKind::IPv6);
        inner.daemon = Some(d.clone());
        Ok(d)
    }

    /// The daemon is shut down when nothing is announced and nobody is searching.
    fn release(inner: &mut Inner) {
        if inner.advertised.is_none() && !inner.browsing {
            if let Some(d) = inner.daemon.take() {
                let _ = d.shutdown();
            }
        }
    }
}

impl Discovery for Mdns {
    fn advertise(&self, id: &str, name: &str, port: u16) -> Result<(), String> {
        let mut inner = self.inner.lock().unwrap();
        let daemon = Mdns::daemon(&mut inner)?;
        if let Some(old) = inner.advertised.take() {
            let _ = daemon.unregister(&old);
        }
        let instance = &id[..12.min(id.len())];
        let host = format!("notchmeow-{}.local.", &id[..8.min(id.len())]);
        let mut txt = HashMap::new();
        txt.insert("v".to_string(), "1".to_string());
        txt.insert("id".to_string(), id.to_string());
        txt.insert("name".to_string(), name.to_string());
        let info = ServiceInfo::new(SERVICE_TYPE, instance, &host, "", port, txt).map_err(|e| e.to_string())?.enable_addr_auto();
        let full = info.get_fullname().to_string();
        match daemon.register(info) {
            Ok(()) => {
                inner.advertised = Some(full);
                Ok(())
            }
            Err(e) => {
                Mdns::release(&mut inner);
                Err(e.to_string())
            }
        }
    }

    fn stop_advertising(&self) {
        let mut inner = self.inner.lock().unwrap();
        if let (Some(d), Some(full)) = (inner.daemon.clone(), inner.advertised.take()) {
            let _ = d.unregister(&full);
        }
        Mdns::release(&mut inner);
    }

    fn browse(&self, own_id: &str, on_results: OnResults) -> Result<(), String> {
        let mut inner = self.inner.lock().unwrap();
        if inner.browsing {
            return Ok(());
        }
        let daemon = Mdns::daemon(&mut inner)?;
        let receiver = daemon.browse(SERVICE_TYPE).map_err(|e| e.to_string())?;
        inner.browsing = true;
        let own = own_id.to_string();
        // One thread that waits on the daemon's channel (it sleeps in `recv`, nothing polls) and ends when the search is stopped or the daemon is shut down.
        std::thread::spawn(move || {
            let mut found: HashMap<String, Found> = HashMap::new();
            while let Ok(event) = receiver.recv() {
                match event {
                    ServiceEvent::ServiceResolved(info) => {
                        let get = |k: &str| info.get_property_val_str(k);
                        let advert = parse_txt(&Txt { v: get("v"), id: get("id"), name: get("name") }, OwnId::Id(&own));
                        let addr = info.get_addresses().iter().find_map(|a| if let IpAddr::V4(v4) = a { Some(*v4) } else { None });
                        // An advert that does not pass the contract's checks (version, id, name, this machine's own id) is not listed.
                        if let (Ok(advert), Some(ip)) = (advert, addr) {
                            found.insert(info.get_fullname().to_string(), Found { advert, addr: SocketAddr::new(IpAddr::V4(ip), info.get_port()) });
                        } else {
                            found.remove(info.get_fullname());
                        }
                    }
                    ServiceEvent::ServiceRemoved(_, full) => {
                        found.remove(&full);
                    }
                    ServiceEvent::SearchStopped(_) => return,
                    _ => continue,
                }
                on_results(found.values().cloned().collect());
            }
        });
        Ok(())
    }

    fn stop_browsing(&self) {
        let mut inner = self.inner.lock().unwrap();
        if inner.browsing {
            if let Some(d) = &inner.daemon {
                let _ = d.stop_browse(SERVICE_TYPE);
            }
            inner.browsing = false;
        }
        Mdns::release(&mut inner);
    }
}
```


- [ ] **Step 3: Check `mdns.rs` against the crate, then build**

The crates were fetched in Task 2. Read the API this file uses in the crate's own source (inside the container, the registry is under `$CARGO_HOME`):

```bash
docker run --rm -v notchmeow-linux-cargo:/usr/local/cargo/registry notchmeow-linux-dev bash -c 'D=$(ls -d /usr/local/cargo/registry/src/*/mdns-sd-0.11* | head -1); echo "$D"; grep -rn "pub fn new\|pub fn disable_interface\|pub fn enable_addr_auto\|pub fn get_fullname\|pub fn get_property_val_str\|pub fn get_addresses\|pub fn get_port\|pub fn register\|pub fn unregister\|pub fn browse\|pub fn stop_browse\|pub fn shutdown\|pub enum IfKind\|pub enum ServiceEvent" "$D/src" | cut -c1-190' | head -40
```

(`cargo-linux.sh` only runs `cargo`, so this uses the same image and cargo volume directly; the volume has the sources after Task 2's fetch.) What `mdns.rs` needs, and the shapes to check: `ServiceDaemon::new() -> Result<ServiceDaemon>`; `disable_interface(IfKind)` with `IfKind::IPv6`; `ServiceInfo::new(ty, instance, host, ip, port, properties)` taking `""` as the address list with `.enable_addr_auto()`; `get_fullname()`; `register(info) -> Result<()>`; `unregister(&str)`; `browse(ty) -> Result<Receiver<ServiceEvent>>`; `ServiceEvent::{ServiceResolved(info), ServiceRemoved(ty, fullname), SearchStopped(ty)}`; `info.get_property_val_str(key) -> Option<&str>`, `get_addresses()`, `get_port()`; `stop_browse(&str)`; `shutdown()`. Where one differs (a renamed method, a returned type), change **that line only** and keep the behaviour: IPv4 only, the lazy daemon, the one waiting thread, the advert's three keys and the host name from the id. If `IfKind::IPv6` does not exist in the pinned version, filter the addresses to IPv4 in `browse` (already done there) and keep the advert's `enable_addr_auto` as is; say so in the ledger.

Then build and run the tests:

```bash
windows/scripts/cargo-linux.sh check --target-dir /repo/windows/target/g2-tauri -p notchmeow --all-targets 2>&1 | grep -E "^(error|warning: unused)" -A6 | head -30
windows/scripts/cargo-linux.sh test --target-dir /repo/windows/target/g2-tauri -p notchmeow link::net 2>&1 | grep -E "test result|FAILED|panicked"
```

Expected: no `error`; `ok. 8 passed` (a record of length 0 closes the connection, an abort cuts a pending read and the peer sees the end, records go both ways over real TCP, two records in one segment and one in two come out whole, a stopped listener accepts nothing, **at most two connections wait from one address**, **a connection that does not finish its handshake in time is cut and its place freed**, and `the_listener_numbers_are_the_macs_and_the_reviews_numbers`). `Mdns` has no test that runs in a container (there is no second machine and multicast is not routed in it): it is exercised by Task 14's peer and by the owner (Task 16, checks 1 and 4).

- [ ] **Step 4: Prove it bites**

Run:

```bash
M="python3 .claude/checkpoints/g2-tauri/mut.py rust"
$M windows/src-tauri/src/link/net.rs 'pub const MAX_PENDING: usize = 8;' 'pub const MAX_PENDING: usize = 9;' link::net
$M windows/src-tauri/src/link/net.rs 'pub const MAX_PENDING_PER_SOURCE: usize = 2;' 'pub const MAX_PENDING_PER_SOURCE: usize = 3;' link::net
```

Expected: each `FAILED`.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/src-tauri/src/link/mod.rs windows/src-tauri/src/link/net.rs windows/src-tauri/src/link/discovery.rs windows/src-tauri/src/link/mdns.rs windows/Cargo.lock
git commit -F - <<'MSG'
feat(link): the TCP transport, the listener, and the mDNS advert and browser (G2-tauri)

A listener that exists only when told to, cuts a connection that has not finished its handshake in 10 s, holds at most 8 such connections and 2 per address; the advert carries only v, id and name and is made on mdns-sd, whose daemon exists only while something is announced or searched.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Write the task's line in the ledger, with whatever `mdns.rs` needed changed.

---


### Task 13: The service, the commands and the app's wiring

**Agent:** `nm-implementer-deep` (**Sonnet 5.5, high; trigger 1**: an actor that owns every decision and a Tauri integration). Add `superpowers:systematic-debugging` to the skills. `service.rs` and its 11 tests were compiled and run while the plan was drafted (with the stand-in Noise, over real loopback TCP and in-memory stores); `link_cmd.rs` and the `lib.rs` edits were written against the app's existing code and the Tauri API and **not compiled** (Tauri builds only in the container, and the draft had no `snow`, `mdns-sd` or `keyring`): step 3 is where they are compiled for the first time, and the executor fixes what the compiler says about **those two files only**.

**Files:**
- Create: `windows/src-tauri/src/link/service.rs`, `windows/src-tauri/src/link_cmd.rs`, `windows/scripts/link-tests/rust-wiring.test.mjs`
- Modify: `windows/src-tauri/src/link/mod.rs`, `windows/src-tauri/src/lib.rs`

**Interfaces:**
- Consumes: everything above; `crate::shelf_store().resolve(&ids) -> Vec<PathBuf>` (the shelf's own store, in `lib.rs`), `crate::platform::{reveal_file, reveal_folder}`, `crate::settings::local_dir()`, `crate::log::line`, and the page's `link_*` calls (Task 8's `bridgeLinkBackend`).
- Produces: `service::{Service, Config, Deps, Emit, Snapshot, CardView, RowView, ShownView, key_problem}`; `link_cmd::{init, LinkHandle, settings_hidden}` and the 15 commands `link_state`, `link_set_visible`, `link_set_name`, `link_devices_open`, `link_shelf_open`, `link_pair`, `link_answer_pair`, `link_respond_offer`, `link_cancel_receiving`, `link_dismiss`, `link_forget`, `link_send`, `link_cancel_sending`, `link_reveal_result`, `link_reveal_folder`; the `link` event (a whole `Snapshot`, camelCase, every time something changes).

**What the service is.** An **actor**: one task owns all the state and handles one command at a time; everything that runs for a while (a pairing, a transfer, a send, each connection) is a task of its own that reports back with a command, so every decision is made in one place and in order. A `Snapshot` is complete on every emit, so the page never has to merge. What makes it safe to leave running: **nothing listens until the user turns Visible on** (off by default: no listener, no advert, no firewall prompt before that; the browser runs only while Settings → Devices or the shelf is on screen and Visible is on); turning Visible off stops the listener, cancels what is running, cuts the connections and makes every late event of those stale (`RunGate`); an incoming pairing runs only while Devices is open or within 2 minutes after a Pair click here (the gate); the island has **one card** (`CardRules`); one transfer for the whole machine (`Busy`), 8 connections and 2 per machine (`ConnectionCaps`), the paired machines read again at most every 5 s (`ReadLimit`); **only a click accepts an offer** (`respond_offer(true)` is reached by the Accept button's command alone); forgetting a machine withdraws its waiting offer; a click whose `{kind, key}` is not the card on screen does nothing. **If the credential store cannot be read** (no Secret Service on Linux, a locked store, a refused prompt), the service says why in `problem` (`key_problem()`: "Start or unlock it: nothing is kept in a file instead, so the link stays off until it works"), the listener does not start, nothing is made and nothing is written. **The log holds fixed sentences only** (`listening`, `stopped listening`, `a pairing ended`, `a transfer ended`, `a transfer started`): never a name, a size, an address or an id.

**The Windows firewall, and the Linux notes.** The first time the listener binds on Windows, Windows Defender Firewall asks whether to allow NotchMeow on private and public networks. The prompt appears because Visible was turned on (never before). If the user cancels it, the app still listens but nothing can reach it: the machine shows nothing on the other's list and the Devices help says what to check (`permissionHelp`). On Linux the listener is not blocked unless a firewall is on; mDNS needs UDP 5353 open. These are described in Settings → Devices, in `windows/README.md` (Task 15) and checked by the owner (Task 16).

- [ ] **Step 1: Register the module and add the files**

```bash
python3 - <<'EOF'
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")
edit("windows/src-tauri/src/link/mod.rs", "// MODULES: add new modules above this line", "pub mod service;\n// MODULES: add new modules above this line")
EOF
```

**Create `windows/src-tauri/src/link/service.rs`:**

```rust
// The link's one holder (sub-project G2): the listener and its advert, the browser, the pairing, the cards, the receiving and the sending, joined into one service that the app talks to. The
// Mac's twin is LinkService.swift, with every fix of its reviews. It is an actor: one task owns all the state and handles one command at a time, and everything that runs for a while (a
// pairing, a transfer, a send, the listener's connections) is a task of its own that reports back with a command, so the decisions are made in one place and in order.
//
// What makes it safe to leave running:
//   * **Nothing listens until the user turns Visible on** (off by default). No listener, no advert, no firewall prompt before that; the browser runs only while Settings → Devices or the shelf is
//     on screen. Turning Visible off stops the listener, cancels what is running and cuts the connections, and every late event of those is made stale (`RunGate`).
//   * **An incoming pairing runs only while Devices is open, or within 2 minutes after the user clicked Pair here** (`pairing::Gate`); otherwise the hello is refused silently.
//   * **The island has one card** (`CardRules`): a pairing code or an offer from another machine never replaces a card the user is about to click, and a click is ignored for 700 ms after the
//     card changed kind and when it was meant for a card that is gone.
//   * **One transfer for the whole machine** (`Busy`), 8 connections in all and 2 per machine (`ConnectionCaps`), the paired machines read again at most once in 5 s (`ReadLimit`).
//   * **Only a click accepts an offer.** Nothing in this file calls `respond(true)` except `respond_offer(true)`, which only a click reaches.
//   * **No name, size, address or id reaches the log**: the log lines are fixed sentences.

use std::collections::{BTreeMap, HashMap};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex as StdMutex};
use std::time::Duration;

use serde::Serialize;
use tokio::sync::{mpsc, oneshot, Notify};

use super::bytes::hex;
use super::cards::{self, offer_key, Busy, CardRules, ConnectionCaps, Kind, ReadLimit, RunGate, Shown, Ticket};
use super::channel::{IdleWatch, Transport};
use super::directory::{self, Row};
use super::discovery::{Discovery, Found};
use super::files::{Source, SourceError};
use super::frames::{decode_preamble, Advert, Mode, Preamble};
use super::identity::{Identity, Peer};
use super::keystore::{KeyError, Keystore, SecretStore};
use super::net::{Listener, PendingSlot, TcpTransport, HANDSHAKE_SECONDS};
use super::pair_run::{pair_channel, run_incoming, run_initiator, Clock, PairHandle, PairHooks, PairOutcome};
use super::pairing::{Gate, Ids, Initiator, OwnId, Refusal, Responder};
use super::settings::{self, LinkSettings};
use super::transfer::{receive_channel, run_receive, run_send, send_channel, Offer, ReceiveHandle, ReceiveHooks, ReceiveTimings, SendHandle, SendHooks, SendTimings, TransferOutcome};

// ── What the page sees ───────────────────────────────────────────────────────

/// One card on the island. `kind` is `pair`, `offer`, `receiving` or `result`; `key` says what it is about (a click carries it back so that it acts only on the card it was meant for).
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CardView {
    pub kind: &'static str,
    pub key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub peer: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub answered: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub received: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
    /// A result with a saved file: the card offers "Show in folder".
    #[serde(skip_serializing_if = "Option::is_none")]
    pub can_reveal: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct RowView {
    pub id: String,
    pub name: String,
    pub state: &'static str,
}

/// Everything the page needs, whole, every time something changes. The page keeps the last one.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub visible: bool,
    pub name: String,
    pub listening: bool,
    pub problem: Option<String>,
    pub note: Option<String>,
    pub rows: Vec<RowView>,
    pub card: Option<CardView>,
    pub send_status: Option<String>,
    pub sending: bool,
    pub folder: String,
}

/// Where the service's news goes (the app turns them into events for the pages) and the log.
pub trait Emit: Send + Sync + 'static {
    fn snapshot(&self, snapshot: &Snapshot);
    /// A fixed sentence: never a name, a size, an address or an id.
    fn log(&self, line: &'static str);
}

// ── Setup ────────────────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct Config {
    /// `link.json`.
    pub settings_path: PathBuf,
    /// `Downloads/NotchMeow`.
    pub folder: PathBuf,
    /// The computer's name, for the default device name only.
    pub host: String,
    /// The mark of the web on received files (Windows).
    pub mark: bool,
    /// `0.0.0.0:0` on the network; `127.0.0.1:0` in the tests.
    pub bind: SocketAddr,
    pub handshake: Duration,
    pub connect_timeout: Duration,
    pub receive: ReceiveTimings,
    pub send: SendTimings,
}

impl Config {
    pub fn app(settings_path: PathBuf, folder: PathBuf, host: String) -> Config {
        Config {
            settings_path,
            folder,
            host,
            mark: super::files::MARK_BY_HAND,
            bind: "0.0.0.0:0".parse().unwrap(),
            handshake: Duration::from_secs(HANDSHAKE_SECONDS),
            connect_timeout: Duration::from_secs(10),
            receive: ReceiveTimings::default(),
            send: SendTimings::default(),
        }
    }
}

pub struct Deps {
    pub keystore: Arc<Keystore<Arc<dyn SecretStore>>>,
    pub discovery: Arc<dyn Discovery>,
    pub emit: Arc<dyn Emit>,
}

impl<T: SecretStore + ?Sized> SecretStore for Arc<T> {
    fn get(&self, account: &str) -> super::keystore::Lookup {
        (**self).get(account)
    }
    fn put(&self, account: &str, value: &str) -> Result<(), super::keystore::StoreError> {
        (**self).put(account, value)
    }
    fn delete(&self, account: &str) -> Result<(), super::keystore::StoreError> {
        (**self).delete(account)
    }
}

/// The platform's words for a credential store that cannot be read.
pub fn key_problem() -> &'static str {
    if cfg!(windows) {
        "The link's key could not be read from the Windows Credential Manager. Nothing is kept in a file instead."
    } else {
        "The link's key could not be read from the Secret Service (GNOME Keyring or KWallet). Start or unlock it: nothing is kept in a file instead, so the link stays off until it works."
    }
}
const PEERS_PROBLEM: &str = "The paired machines could not be read from the credential store.";
const LISTEN_PROBLEM: &str = "This computer could not start listening.";
const ADVERT_PROBLEM: &str = "This computer could not announce itself on the network.";

// ── Commands ─────────────────────────────────────────────────────────────────

/// The card a click was meant for, as the page saw it.
#[derive(Debug, Clone, PartialEq, Eq, serde::Deserialize)]
pub struct ShownView {
    pub kind: String,
    pub key: String,
}

/// The card a click was meant for: None inside means "the one on the island"; the outer None is a click whose kind is not one of ours (ignored).
fn parse_shown(shown: &Option<ShownView>) -> Option<Option<Shown>> {
    match shown {
        None => Some(None),
        Some(s) => s.to_shown().map(Some),
    }
}

impl ShownView {
    fn to_shown(&self) -> Option<Shown> {
        let kind = match self.kind.as_str() {
            "pair" => Kind::Pair,
            "offer" => Kind::Offer,
            "receiving" => Kind::Receiving,
            "result" => Kind::Result,
            _ => return None,
        };
        Some(Shown { kind, key: self.key.clone() })
    }
}

enum Cmd {
    // From the app.
    Start,
    SetVisible(bool),
    SetName(String, oneshot::Sender<bool>),
    DevicesOpen(bool),
    ShelfOpen(bool),
    Pair(String),
    AnswerPair(bool, Option<ShownView>),
    RespondOffer(bool, Option<ShownView>),
    CancelReceiving(Option<ShownView>),
    Dismiss(Option<ShownView>),
    Forget(String),
    Send(Vec<PathBuf>, String),
    CancelSending,
    RevealPath(oneshot::Sender<Option<PathBuf>>),
    Snapshot(oneshot::Sender<Snapshot>),
    // From the tasks the service started.
    Browsed(Vec<Found>, u64),
    Preamble { transport: Arc<TcpTransport>, slot: PendingSlot, gen: u64, pre: Preamble },
    Track { conn: u64, transport: Arc<TcpTransport>, gen: u64 },
    Untrack(u64),
    OutboundFailed(u64),
    PairCode { ticket: Ticket, code: String, name: String },
    PairEnded { outcome: PairOutcome, initiator: Option<Initiator>, responder: Option<Responder>, own_id: String, gen: u64, outbound: bool },
    IncomingRefused(u64),
    OfferArrived { offer: Offer, handle: ReceiveHandle, conn: u64, gen: u64 },
    Progress { conn: u64, got: u64 },
    ReceiveEnded { conn: u64, outcome: TransferOutcome, gen: u64, handle: ReceiveHandle, peer_id: String },
    SendStatus(String, u64),
    SendDone(u64),
}

/// The handle the app holds. Every method only posts a command; the actor does the work.
#[derive(Clone)]
pub struct Service {
    tx: mpsc::UnboundedSender<Cmd>,
}

impl Service {
    /// `spawner` starts the actor on the app's async runtime (`|f| { tauri::async_runtime::spawn(f); }`; the tests pass `|f| { tokio::spawn(f); }`): this folder knows no Tauri type.
    pub fn spawn(spawner: impl FnOnce(std::pin::Pin<Box<dyn std::future::Future<Output = ()> + Send>>), cfg: Config, deps: Deps) -> Service {
        let (tx, rx) = mpsc::unbounded_channel();
        let settings = settings::load(&cfg.settings_path, &cfg.host);
        let core = Core::new(cfg, deps, settings, tx.clone());
        spawner(Box::pin(core.run(rx)));
        Service { tx }
    }

    fn post(&self, c: Cmd) {
        let _ = self.tx.send(c);
    }

    /// At launch: reads the paired machines and, only when the user has turned Visible on, starts the listener. Costs nothing otherwise.
    pub fn start(&self) {
        self.post(Cmd::Start);
    }
    pub fn set_visible(&self, on: bool) {
        self.post(Cmd::SetVisible(on));
    }
    /// False when the name is not one a card would accept.
    pub async fn set_device_name(&self, name: String) -> bool {
        let (tx, rx) = oneshot::channel();
        self.post(Cmd::SetName(name, tx));
        rx.await.unwrap_or(false)
    }
    /// Settings → Devices is on screen (or not): while it is, another machine may start a pairing with this one, and the machines are looked for. It says how things are now, not what
    /// changed, so saying it twice changes nothing and a missed "closed" is put right by the next one.
    pub fn set_devices_open(&self, open: bool) {
        self.post(Cmd::DevicesOpen(open));
    }
    /// The shelf is on screen (or not): while it is, the machines are looked for.
    pub fn set_shelf_open(&self, open: bool) {
        self.post(Cmd::ShelfOpen(open));
    }
    /// "Pair a machine": this machine starts a pairing with a machine it has seen.
    pub fn pair(&self, id: String) {
        self.post(Cmd::Pair(id));
    }
    pub fn answer_pair(&self, yes: bool, shown: Option<ShownView>) {
        self.post(Cmd::AnswerPair(yes, shown));
    }
    /// The only way an offer is accepted: a click on Accept.
    pub fn respond_offer(&self, accept: bool, shown: Option<ShownView>) {
        self.post(Cmd::RespondOffer(accept, shown));
    }
    pub fn cancel_receiving(&self, shown: Option<ShownView>) {
        self.post(Cmd::CancelReceiving(shown));
    }
    /// The OK on a result, or the close of any card.
    pub fn dismiss(&self, shown: Option<ShownView>) {
        self.post(Cmd::Dismiss(shown));
    }
    pub fn forget(&self, id: String) {
        self.post(Cmd::Forget(id));
    }
    /// Sends these files, one connection for each, one after the other, each needing the other user's Accept.
    pub fn send(&self, paths: Vec<PathBuf>, to: String) {
        self.post(Cmd::Send(paths, to));
    }
    pub fn cancel_sending(&self) {
        self.post(Cmd::CancelSending);
    }
    /// The file the result card is about, for "Show in folder".
    pub async fn result_file(&self) -> Option<PathBuf> {
        let (tx, rx) = oneshot::channel();
        self.post(Cmd::RevealPath(tx));
        rx.await.ok().flatten()
    }
    pub async fn snapshot(&self) -> Option<Snapshot> {
        let (tx, rx) = oneshot::channel();
        self.post(Cmd::Snapshot(tx));
        rx.await.ok()
    }
}

// ── The core ─────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Eq)]
enum Card {
    Pair { code: String, peer: String, answered: bool },
    Offer(Offer),
    Receiving(Offer, u64),
    Result { title: String, detail: String, file: Option<PathBuf> },
}

impl Card {
    /// The flow a card with buttons belongs to. A result is given the flow that ended by that flow itself.
    fn flow(&self) -> Option<String> {
        match self {
            Card::Pair { code, peer, .. } => Some(format!("pair:{code}|{peer}")),
            Card::Offer(o) | Card::Receiving(o, _) => Some(format!("transfer:{}", offer_key(&o.peer_id, &o.transfer_id))),
            Card::Result { .. } => None,
        }
    }

    fn shown(&self) -> Shown {
        match self {
            Card::Pair { code, peer, .. } => Shown { kind: Kind::Pair, key: format!("{code}|{peer}") },
            Card::Offer(o) => Shown { kind: Kind::Offer, key: offer_key(&o.peer_id, &o.transfer_id) },
            Card::Receiving(o, _) => Shown { kind: Kind::Receiving, key: offer_key(&o.peer_id, &o.transfer_id) },
            Card::Result { title, detail, .. } => Shown { kind: Kind::Result, key: format!("{title}|{detail}") },
        }
    }

    fn holds_island(&self) -> bool {
        !matches!(self, Card::Result { .. })
    }

    fn view(&self) -> CardView {
        let s = self.shown();
        let base = CardView { kind: kind_word(s.kind), key: s.key, code: None, peer: None, answered: None, name: None, size: None, received: None, title: None, detail: None, can_reveal: None };
        match self {
            Card::Pair { code, peer, answered } => CardView { code: Some(code.clone()), peer: Some(peer.clone()), answered: Some(*answered), ..base },
            Card::Offer(o) => CardView { name: Some(o.name.clone()), size: Some(o.size), peer: Some(o.peer_name.clone()), ..base },
            Card::Receiving(o, got) => CardView { name: Some(o.name.clone()), size: Some(o.size), received: Some(*got), peer: Some(o.peer_name.clone()), ..base },
            Card::Result { title, detail, file } => CardView { title: Some(title.clone()), detail: Some(detail.clone()), can_reveal: Some(file.is_some()), ..base },
        }
    }
}

fn kind_word(k: Kind) -> &'static str {
    match k {
        Kind::Pair => "pair",
        Kind::Offer => "offer",
        Kind::Receiving => "receiving",
        Kind::Result => "result",
    }
}

struct Own {
    device_id: String,
    key: [u8; 32],
    public: [u8; 32],
}

struct Receiving {
    conn: u64,
    ticket: Ticket,
    handle: ReceiveHandle,
    flow: String,
}

/// What a send in progress is made of, shared between the actor and the task that does it.
struct SendControl {
    cancelled: AtomicBool,
    handle: StdMutex<Option<SendHandle>>,
    connecting: Notify,
}

struct Core {
    cfg: Config,
    deps: Deps,
    tx: mpsc::UnboundedSender<Cmd>,
    settings: LinkSettings,
    rows: Vec<Row>,
    listening: bool,
    problem: Option<String>,
    note: Option<String>,
    card: Option<Card>,
    send_status: Option<String>,
    sending: bool,
    listener: Option<Listener>,
    devices_open: bool,
    shelf_open: bool,
    browse_token: Option<u64>,
    seen: HashMap<String, Found>,
    pairing: (Initiator, Responder),
    pair_handle: Option<PairHandle>,
    pair_gate: Gate,
    pairing_incoming: bool,
    outbound: bool,
    receive: Option<Receiving>,
    send_control: Option<Arc<SendControl>>,
    busy: Arc<Busy>,
    caps: Arc<ConnectionCaps>,
    peers: BTreeMap<String, Peer>,
    read_limit: ReadLimit,
    own: Option<Own>,
    rules: CardRules,
    pair_flow: Option<String>,
    gate: RunGate,
    active: HashMap<u64, Arc<TcpTransport>>,
    next: u64,
    last_published: Option<Snapshot>,
    last_progress_at: i64,
}

fn clock() -> Clock {
    Arc::new(cards::now_ms)
}

fn random32() -> [u8; 32] {
    let mut b = [0u8; 32];
    let _ = getrandom::getrandom(&mut b);
    b
}

impl Core {
    fn new(cfg: Config, deps: Deps, settings: LinkSettings, tx: mpsc::UnboundedSender<Cmd>) -> Core {
        Core {
            cfg,
            deps,
            tx,
            settings,
            rows: vec![],
            listening: false,
            problem: None,
            note: None,
            card: None,
            send_status: None,
            sending: false,
            listener: None,
            devices_open: false,
            shelf_open: false,
            browse_token: None,
            seen: HashMap::new(),
            pairing: (Initiator::new(Ids::default()), Responder::new(Ids::default())),
            pair_handle: None,
            pair_gate: Gate::default(),
            pairing_incoming: false,
            outbound: false,
            receive: None,
            send_control: None,
            busy: Arc::new(Busy::default()),
            caps: Arc::new(ConnectionCaps::default()),
            peers: BTreeMap::new(),
            read_limit: ReadLimit::default(),
            own: None,
            rules: CardRules::default(),
            pair_flow: None,
            gate: RunGate::default(),
            active: HashMap::new(),
            next: 1,
            last_published: None,
            last_progress_at: 0,
        }
    }

    async fn run(mut self, mut rx: mpsc::UnboundedReceiver<Cmd>) {
        while let Some(cmd) = rx.recv().await {
            self.handle(cmd).await;
            self.publish(false);
        }
    }

    fn id(&mut self) -> u64 {
        self.next += 1;
        self.next
    }

    fn generation(&self) -> u64 {
        self.gate.generation()
    }

    fn log(&self, line: &'static str) {
        self.deps.emit.log(line);
    }

    fn snapshot(&self) -> Snapshot {
        Snapshot {
            visible: self.settings.visible,
            name: self.settings.device_name.clone(),
            listening: self.listening,
            problem: self.problem.clone(),
            note: self.note.clone(),
            rows: self.rows.iter().map(|r| RowView { id: r.id.clone(), name: r.name.clone(), state: r.state.as_str() }).collect(),
            card: self.card.as_ref().map(Card::view),
            send_status: self.send_status.clone(),
            sending: self.sending,
            folder: self.cfg.folder.display().to_string(),
        }
    }

    /// Tells the page, when something it shows has changed. `force` is for progress ticks, which are the same card with more bytes and are let through at most every 100 ms.
    fn publish(&mut self, force: bool) {
        let now = self.snapshot();
        if !force && self.last_published.as_ref() == Some(&now) {
            return;
        }
        self.deps.emit.snapshot(&now);
        self.last_published = Some(now);
    }

    async fn handle(&mut self, cmd: Cmd) {
        match cmd {
            Cmd::Start => {
                self.reload_peers();
                if self.settings.visible {
                    self.start_listening().await;
                }
            }
            Cmd::SetVisible(on) => self.set_visible(on).await,
            Cmd::SetName(name, reply) => {
                let ok = self.set_device_name(&name).await;
                let _ = reply.send(ok);
            }
            Cmd::DevicesOpen(open) => {
                if open == self.devices_open {
                    return;
                }
                self.devices_open = open;
                if open {
                    self.pair_gate.devices_appeared();
                    self.reload_peers();
                    if self.settings.visible && !self.listening {
                        self.start_listening().await;
                    }
                    self.start_browser();
                } else {
                    self.pair_gate.devices_disappeared();
                    self.looking_ended();
                }
            }
            Cmd::ShelfOpen(open) => {
                if open == self.shelf_open {
                    return;
                }
                self.shelf_open = open;
                if open {
                    self.start_browser();
                } else {
                    self.looking_ended();
                }
            }
            Cmd::Browsed(results, token) => {
                if self.browse_token == Some(token) {
                    self.seen = results.into_iter().map(|f| (f.advert.id.clone(), f)).collect();
                    self.refresh_rows();
                }
            }
            Cmd::Pair(id) => self.pair(&id).await,
            Cmd::AnswerPair(yes, shown) => self.answer_pair(yes, shown),
            Cmd::RespondOffer(accept, shown) => self.respond_offer(accept, shown),
            Cmd::CancelReceiving(shown) => self.cancel_receiving(shown),
            Cmd::Dismiss(shown) => self.dismiss(shown),
            Cmd::Forget(id) => self.forget(&id),
            Cmd::Send(paths, to) => self.send(paths, &to).await,
            Cmd::CancelSending => self.cancel_sending(),
            Cmd::RevealPath(reply) => {
                let _ = reply.send(match &self.card {
                    Some(Card::Result { file, .. }) => file.clone(),
                    _ => None,
                });
            }
            Cmd::Snapshot(reply) => {
                let _ = reply.send(self.snapshot());
            }
            Cmd::Preamble { transport, slot, gen, pre } => self.preamble(transport, slot, gen, pre).await,
            Cmd::Track { conn, transport, gen } => {
                if gen == self.generation() {
                    self.active.insert(conn, transport);
                } else {
                    transport.abort(); // Visible was turned off while connecting
                }
            }
            Cmd::Untrack(conn) => {
                self.active.remove(&conn);
            }
            Cmd::OutboundFailed(gen) => {
                if gen == self.generation() {
                    self.outbound = false;
                    self.pair_handle = None;
                    self.gate.end_pair();
                    self.note = Some("Could not reach that machine.".into());
                }
            }
            Cmd::PairCode { ticket, code, name } => self.code_known(ticket, code, name),
            Cmd::PairEnded { outcome, initiator, responder, own_id, gen, outbound } => self.pair_ended(outcome, initiator, responder, &own_id, gen, outbound),
            Cmd::IncomingRefused(gen) => {
                if gen == self.generation() {
                    self.pairing_incoming = false;
                    self.pair_handle = None;
                    self.gate.end_pair();
                }
            }
            Cmd::OfferArrived { offer, handle, conn, gen } => self.offer_arrived(offer, handle, conn, gen),
            Cmd::Progress { conn, got } => self.progressed(conn, got),
            Cmd::ReceiveEnded { conn, outcome, gen, handle, peer_id } => self.receive_ended(conn, outcome, gen, handle, &peer_id),
            Cmd::SendStatus(text, gen) => {
                if gen == self.generation() && self.sending {
                    self.send_status = Some(text);
                }
            }
            Cmd::SendDone(gen) => {
                if gen == self.generation() {
                    self.sending = false;
                    self.send_control = None;
                }
            }
        }
    }

    // ── Start, stop, settings ──

    async fn set_visible(&mut self, on: bool) {
        if on == self.settings.visible {
            return;
        }
        self.settings.visible = on;
        let _ = settings::save(&self.cfg.settings_path, &self.settings);
        if on {
            self.reload_peers();
            self.start_listening().await;
            self.start_browser(); // Devices or the shelf was already open: turning Visible on starts the search
        } else {
            self.stop_listening();
            self.stop_browser();
        }
        self.refresh_rows();
    }

    /// False when the name is not one a card would accept.
    async fn set_device_name(&mut self, name: &str) -> bool {
        let Some(valid) = settings::valid_name(Some(&serde_json::Value::String(name.to_string()))) else { return false };
        if valid == self.settings.device_name {
            return true;
        }
        self.settings.device_name = valid;
        let _ = settings::save(&self.cfg.settings_path, &self.settings);
        // The advert carries the name, so it is announced again. Connections that were accepted are sockets of their own and the conversations on them do not depend on the listener: a pairing or a
        // transfer that is running is not touched (this is not `stop_listening`).
        if let (true, Some(l)) = (self.settings.visible, &self.listener) {
            if let Some(own) = &self.own {
                if self.deps.discovery.advertise(&own.device_id, &self.settings.device_name, l.port()).is_err() {
                    self.problem = Some(ADVERT_PROBLEM.into());
                }
            }
        }
        true
    }

    fn report(&mut self, line: &str, failed: bool) {
        if failed {
            self.problem = Some(line.to_string());
        } else if self.problem.as_deref() == Some(line) {
            self.problem = None;
        }
    }

    /// This machine's identity, from memory once it has been read. A read that fails is not kept: the next call reads again, and Devices says it could not be read until one works.
    fn identity(&mut self) -> Option<Identity> {
        if self.own.is_none() {
            let read = (|| -> Result<Own, KeyError> {
                let device_id = self.deps.keystore.device_id()?;
                let (key, public) = self.deps.keystore.static_key()?;
                Ok(Own { device_id, key, public })
            })();
            match read {
                Ok(own) => {
                    self.own = Some(own);
                    self.report(key_problem(), false);
                }
                Err(_) => {
                    self.report(key_problem(), true);
                    return None;
                }
            }
        }
        let o = self.own.as_ref()?;
        Some(Identity { device_id: o.device_id.clone(), name: self.settings.device_name.clone(), key: o.key, public: o.public })
    }

    /// The device id alone, for the browser and the list (they do not need the key): from memory, or read once.
    fn device_id(&mut self) -> Option<String> {
        if self.own.is_none() {
            let _ = self.identity();
        }
        self.own.as_ref().map(|o| o.device_id.clone())
    }

    async fn start_listening(&mut self) {
        if self.listener.is_some() {
            return;
        }
        let Some(me) = self.identity() else { return };
        let (tx, gen) = (self.tx.clone(), self.generation());
        let on_connection: super::net::OnConnection = Arc::new(move |transport, slot| {
            let tx = tx.clone();
            tokio::spawn(async move {
                // The first record comes first: nothing is looked up, read from the credential store or decided for a connection that has not sent a valid one. The slot's watchdog bounds the wait.
                let pre = match transport.receive().await.ok().and_then(|r| decode_preamble(&r).ok()) {
                    Some(p) => p,
                    None => {
                        slot.finish();
                        transport.close().await;
                        return;
                    }
                };
                let _ = tx.send(Cmd::Preamble { transport, slot, gen, pre });
            });
        });
        match Listener::start(self.cfg.bind, on_connection, self.cfg.handshake).await {
            Ok(l) => {
                let port = l.port();
                match self.deps.discovery.advertise(&me.device_id, &me.name, port) {
                    Ok(()) => {
                        self.listener = Some(l);
                        self.listening = true;
                        if self.problem.as_deref() == Some(LISTEN_PROBLEM) || self.problem.as_deref() == Some(ADVERT_PROBLEM) {
                            self.problem = None;
                        }
                        self.log("listening");
                    }
                    Err(_) => {
                        l.stop();
                        self.problem = Some(ADVERT_PROBLEM.into());
                    }
                }
            }
            Err(_) => {
                self.listening = false;
                self.problem = Some(LISTEN_PROBLEM.into());
            }
        }
    }

    /// Visible turned off: nothing keeps running. Conversations are cancelled and their connections cut (also those that have no run yet), and everything that was awaiting is made stale by the
    /// new generation. A card that belonged to one of them goes, since nothing is left to answer.
    fn stop_listening(&mut self) {
        self.gate.stop();
        self.listener = None;
        self.deps.discovery.stop_advertising();
        self.listening = false;
        if let Some(h) = self.pair_handle.take() {
            h.cancel();
        }
        if let Some(r) = self.receive.take() {
            r.handle.cancel();
        }
        if let Some(c) = self.send_control.take() {
            c.cancelled.store(true, Ordering::SeqCst);
            if let Some(h) = c.handle.lock().unwrap().take() {
                h.cancel();
            }
            c.connecting.notify_waiters();
        }
        self.outbound = false;
        self.pairing_incoming = false;
        self.sending = false;
        self.pair_flow = None;
        self.send_status = None;
        for (_, t) in self.active.drain() {
            t.abort();
        }
        self.rules = CardRules::default();
        self.card = None;
        self.busy.set_card_locked(false);
        self.log("stopped listening");
    }

    // ── Browsing (only while Devices or the shelf is open) ──

    /// Someone is looking at the machines: Devices or the shelf.
    fn looking(&self) -> bool {
        self.devices_open || self.shelf_open
    }

    /// One of them stopped looking: the search ends when both have.
    fn looking_ended(&mut self) {
        if self.looking() {
            return;
        }
        self.stop_browser();
        if !self.sending {
            self.send_status = None; // the last line of a finished send does not wait for the next time the shelf opens
        }
        self.refresh_rows();
    }

    fn start_browser(&mut self) {
        if self.browse_token.is_some() || !self.looking() || !self.settings.visible {
            return;
        }
        let Some(id) = self.device_id() else { return };
        let token = self.id();
        let tx = self.tx.clone();
        match self.deps.discovery.browse(&id, Arc::new(move |results| { let _ = tx.send(Cmd::Browsed(results, token)); })) {
            Ok(()) => self.browse_token = Some(token),
            Err(_) => self.note = Some("This computer could not look for other machines.".into()),
        }
    }

    fn stop_browser(&mut self) {
        if self.browse_token.take().is_some() {
            self.deps.discovery.stop_browsing();
        }
        self.seen.clear();
    }

    /// Builds the list from what is in memory: no credential-store read (the browser may report many times a second).
    fn refresh_rows(&mut self) {
        let own = self.device_id().unwrap_or_default();
        let adverts: Vec<Advert> = self.seen.values().map(|f| f.advert.clone()).collect();
        self.rows = directory::rows(&adverts, &self.peers, &own);
    }

    /// The read of the paired machines: at launch, when Visible is turned on, when Devices opens, on a miss, and after a pairing was stored or a machine forgotten. A read that cannot be trusted
    /// (an item that will not read, or nothing at all where there were machines) keeps the last good map and puts a line in Devices.
    fn reload_peers(&mut self) {
        self.read_limit.read(cards::now_ms());
        match self.deps.keystore.paired_machines(!self.peers.is_empty()) {
            Ok(map) => {
                self.peers = map;
                self.report(PEERS_PROBLEM, false);
            }
            Err(_) => self.report(PEERS_PROBLEM, true),
        }
        self.refresh_rows();
    }

    /// A paired machine, from memory; when it is not there the store is read again, at most once in 5 s, so a read that failed for a moment does not leave a paired machine unknown until the next
    /// launch, and a peer that sends ids that are not paired cannot make this machine read the store in a loop.
    fn paired_peer(&mut self, id: &str) -> Option<Peer> {
        if !self.peers.contains_key(id) && self.read_limit.due(cards::now_ms()) {
            self.reload_peers();
        }
        self.peers.get(id).cloned()
    }

    fn forget(&mut self, id: &str) {
        if self.deps.keystore.forget(id).is_err() {
            self.problem = Some(PEERS_PROBLEM.into());
        }
        self.peers.remove(id); // so that what is left is the whole map, and a read that finds none is a failed one
        self.refuse_transfer_from(id);
        self.reload_peers();
    }

    /// A machine that was just forgotten is no longer trusted: an offer of it that waits for a click is declined and a file of it that comes in is cancelled, and the card goes now, so no click
    /// can accept or complete what that machine started. The run answers for its own end.
    fn refuse_transfer_from(&mut self, id: &str) {
        let Some(r) = &self.receive else { return };
        let flow = r.flow.clone();
        if self.card.as_ref().and_then(Card::flow).as_deref() != Some(flow.as_str()) {
            return;
        }
        match &self.card {
            Some(Card::Offer(o)) if o.peer_id == id => r.handle.respond(false),
            Some(Card::Receiving(o, _)) if o.peer_id == id => r.handle.cancel(),
            _ => return,
        }
        self.receive = None;
        self.gate.end_receive();
        self.present(None, &flow);
    }

    // ── The card ──

    /// The one way a flow changes the card: `card` is its card, or None to take its card away. False when another flow's card with buttons is on the island (the card is then left as it is, and
    /// nothing is shown), or when `card` is None and the card on the island is not this flow's.
    fn present(&mut self, new: Option<Card>, owner: &str) -> bool {
        match new {
            None => {
                if !self.rules.end(owner) {
                    return false;
                }
                self.card = None;
            }
            Some(card) => {
                if !self.rules.show(card.shown(), owner, cards::now_ms()) {
                    return false;
                }
                self.card = Some(card);
            }
        }
        let hold = self.card.as_ref().is_some_and(Card::holds_island);
        self.busy.set_card_locked(hold); // an offer that arrives now is declined as busy, whatever task its run is on
        true
    }

    // ── Pairing ──

    async fn pair(&mut self, id: &str) {
        if !self.settings.visible {
            self.note = Some("Turn on Visible on this network first.".into());
            return;
        }
        if self.pair_handle.is_some() || self.outbound || self.pairing_incoming {
            return;
        }
        let Some(target) = self.seen.get(id).cloned() else { return };
        let Some(me) = self.identity() else { return };
        if self.rules.interactive() {
            self.note = Some("Answer the card on the island first.".into());
            return;
        }
        self.outbound = true;
        self.pair_gate.pair_clicked(cards::now_ms());
        self.note = None;
        let (gen, conn, ticket) = (self.generation(), self.id(), self.gate.begin_pair());
        let (handle, inbox) = pair_channel();
        self.pair_handle = Some(handle);
        let mut state = self.pairing.0.clone();
        state.ids = self.pair_ids(&me);
        let (tx, timeout, handshake) = (self.tx.clone(), self.cfg.connect_timeout, self.cfg.handshake);
        tokio::spawn(async move {
            let transport = match TcpTransport::connect(target.addr, timeout).await {
                Ok(t) => t,
                Err(_) => {
                    let _ = tx.send(Cmd::OutboundFailed(gen));
                    return;
                }
            };
            let _ = tx.send(Cmd::Track { conn, transport: transport.clone(), gen });
            // The handshake has 10 seconds, as the listener gives one on the other side: a machine that connects and then says nothing does not hold this machine's pairing slot.
            let deadline = Arc::new({
                let t = transport.clone();
                IdleWatch::new(handshake.as_millis() as u64, move || t.abort())
            });
            let (tx_code, tx_done, d2) = (tx.clone(), tx.clone(), deadline.clone());
            let hooks = PairHooks {
                show_code: Arc::new(move |code, name| { let _ = tx_code.send(Cmd::PairCode { ticket, code, name }); }),
                handshake_done: Arc::new(move || d2.stop()),
            };
            let own_id = me.device_id.clone();
            let (outcome, next) = run_initiator(transport, &me, random32(), clock(), state, &hooks, inbox).await;
            deadline.stop();
            let _ = tx_done.send(Cmd::PairEnded { outcome, initiator: Some(next), responder: None, own_id, gen, outbound: true });
            let _ = tx.send(Cmd::Untrack(conn));
        });
    }

    /// The snapshot a pairing starts with: from memory (the store re-reads itself when a key is stored).
    fn pair_ids(&self, me: &Identity) -> Ids {
        Ids { own_id: OwnId::Id(me.device_id.clone()), paired: Some(self.peers.iter().map(|(k, p)| (k.clone(), p.key.clone())).collect()) }
    }

    /// The code of a pairing is known. It takes the card only if no other flow's card with buttons is up (or an offer is claimed and about to take it); otherwise the pairing is ended (nothing was
    /// ever shown for it). A code that comes from a stopped or replaced pairing (`ticket` is not the current one) does nothing, and does not touch the current run.
    fn code_known(&mut self, ticket: Ticket, code: String, name: String) {
        if !self.gate.is_pair(ticket) {
            return;
        }
        let card = Card::Pair { code, peer: name, answered: false };
        let flow = card.flow().unwrap_or_default();
        if self.busy.reserve_card() && self.present(Some(card), &flow) {
            self.pair_flow = Some(flow);
        } else if let Some(h) = &self.pair_handle {
            h.cancel();
        }
    }

    /// The user's click on "They match" or "No". `shown` is the card the click was meant for (None: the one on the island).
    fn answer_pair(&mut self, yes: bool, shown: Option<ShownView>) {
        let Some(Card::Pair { code, peer, answered: false }) = self.card.clone() else { return };
        let card = Card::Pair { code, peer, answered: true };
        let Some(shown) = parse_shown(&shown) else { return };
        if !self.rules.accepts(shown.as_ref(), cards::now_ms()) || self.pair_flow != self.card.as_ref().and_then(Card::flow) {
            return; // pair_flow is set only by the current run's own code
        }
        let Some(handle) = self.pair_handle.clone() else { return };
        let flow = card.flow().unwrap_or_default();
        self.present(Some(card), &flow);
        handle.answer(yes);
    }

    /// `gen` is the generation the pairing started under: after Visible was turned off nothing of it is touched, and only a pairing both users said yes to is kept. `started` is true for a pairing this
    /// user started: only that one may leave a note in Devices (a machine that connects and is refused must not write on this machine's screen).
    fn pair_ended(&mut self, outcome: PairOutcome, initiator: Option<Initiator>, responder: Option<Responder>, own_id: &str, gen: u64, started: bool) {
        let flow = self.pair_flow.clone();
        self.log("a pairing ended");
        if let Some(i) = initiator {
            self.pairing.0 = i;
        }
        if let Some(r) = responder {
            self.pairing.1 = r;
        }
        if gen != self.generation() {
            if let PairOutcome::Paired(peer) = outcome {
                let _ = self.deps.keystore.add(&peer, own_id);
                self.reload_peers();
            }
            return;
        }
        self.pair_handle = None;
        self.outbound = false;
        self.pairing_incoming = false;
        self.pair_flow = None;
        self.gate.end_pair();
        match outcome {
            PairOutcome::Paired(peer) => {
                // Both users said yes. The paired map is read again at the moment of storing (two pairings can overlap for up to two minutes).
                let result = match self.deps.keystore.add(&peer, own_id) {
                    Ok(()) => {
                        self.reload_peers();
                        Card::Result { title: "Paired".into(), detail: format!("This computer and {} can now send files to each other.", peer.name), file: None }
                    }
                    Err(_) => Card::Result { title: "Not paired".into(), detail: "That machine could not be saved.".into(), file: None },
                };
                if let Some(f) = flow {
                    self.present(Some(result), &f);
                }
            }
            PairOutcome::Declined { by_me } => {
                if let Some(f) = flow {
                    let card = if by_me { None } else { Some(Card::Result { title: "Not paired".into(), detail: "The other machine said the codes did not match.".into(), file: None }) };
                    self.present(card, &f);
                }
            }
            PairOutcome::Refused(why) => {
                if let Some(f) = flow {
                    self.present(None, &f);
                }
                if started {
                    self.note = Some(if why == Refusal::AttemptTooSoon.as_str() { "Wait 30 seconds before trying again.".into() } else { "The pairing did not go through.".into() });
                }
            }
        }
        self.refresh_rows();
    }

    // ── Incoming connections ──

    /// `gen` is the generation the listener that accepted the socket was built under: a connection that was accepted before Visible was turned off is closed, however late its task runs.
    async fn preamble(&mut self, transport: Arc<TcpTransport>, slot: PendingSlot, gen: u64, pre: Preamble) {
        // Nothing is accepted while the machine is not visible: a connection that a stopped listener had already taken is closed.
        if gen != self.generation() || !self.settings.visible {
            slot.finish();
            tokio::spawn(async move { transport.close().await });
            return;
        }
        let conn = self.id();
        self.active.insert(conn, transport.clone());
        let tx = self.tx.clone();
        match pre.mode {
            Mode::Pair => {
                // Outside the gate (Devices closed and no Pair click in the last 2 minutes), while another pairing runs, or while a card with buttons is on the island: refused silently, nothing sent,
                // no card, no alert. A code from another machine never appears in front of a card the user is about to click.
                let allowed = self.pair_handle.is_none() && !self.outbound && !self.pairing_incoming && !self.rules.interactive() && self.pair_gate.allows(Some(cards::now_ms()));
                let me = if allowed { self.identity() } else { None };
                let Some(me) = me else {
                    slot.finish();
                    self.active.remove(&conn);
                    tokio::spawn(async move { transport.close().await });
                    return;
                };
                self.pairing_incoming = true;
                let ticket = self.gate.begin_pair();
                let (handle, inbox) = pair_channel();
                self.pair_handle = Some(handle);
                let mut state = self.pairing.1.clone();
                state.ids = self.pair_ids(&me);
                let gate = self.pair_gate.clone();
                tokio::spawn(async move {
                    let (tx_code, s2) = (tx.clone(), slot.clone());
                    let hooks = PairHooks {
                        show_code: Arc::new(move |code, name| { let _ = tx_code.send(Cmd::PairCode { ticket, code, name }); }),
                        handshake_done: Arc::new(move || s2.finish()),
                    };
                    let own_id = me.device_id.clone();
                    let result = run_incoming(transport, &me, random32(), clock(), &gate, state, &hooks, inbox).await;
                    slot.finish();
                    match result {
                        None => {
                            let _ = tx.send(Cmd::IncomingRefused(gen));
                        }
                        Some((outcome, next)) => {
                            let _ = tx.send(Cmd::PairEnded { outcome, initiator: None, responder: Some(next), own_id, gen, outbound: false });
                        }
                    }
                    let _ = tx.send(Cmd::Untrack(conn));
                });
            }
            Mode::Transfer => {
                // A transfer runs only between paired machines: an id this machine does not know is closed without an answer.
                let id = hex(&pre.id);
                let (Some(peer), Some(me)) = (self.paired_peer(&id), self.identity()) else {
                    slot.finish();
                    self.active.remove(&conn);
                    tokio::spawn(async move { transport.close().await });
                    return;
                };
                self.log("a transfer started");
                let (busy, caps) = (self.busy.clone(), self.caps.clone());
                let (folder, mark, timings) = (self.cfg.folder.clone(), self.cfg.mark, self.cfg.receive);
                tokio::spawn(async move {
                    // The run is not "the" receive run until its offer is waiting for a click (`OfferArrived`): a connection that has only said hello holds nothing and blocks nobody. A second offer still
                    // gets its answer, "busy" (reason 2), and no card, because its claim fails (`Busy`). The run keeps its transfer place until the service gives it back.
                    let (handle, inbox) = receive_channel();
                    let (t_offer, t_progress, s_done, c_admit, pid) = (tx.clone(), tx.clone(), slot.clone(), caps.clone(), peer.id.clone());
                    let (h_offer, pid2) = (handle.clone(), peer.id.clone());
                    let (b1, b2) = (busy.clone(), busy.clone());
                    let hooks = ReceiveHooks {
                        offered: Arc::new(move |offer| { let _ = t_offer.send(Cmd::OfferArrived { offer, handle: h_offer.clone(), conn, gen }); }),
                        progress: Arc::new(move |got, _| { let _ = t_progress.send(Cmd::Progress { conn, got }); }),
                        claim: Arc::new(move |p| b1.claim(p)),
                        release: Arc::new(move |p| b2.release(p)),
                        handshake_done: Arc::new(move || s_done.finish()),
                        admit: Arc::new(move || c_admit.admit(conn, &pid)),
                        release_at_end: false,
                    };
                    let outcome = run_receive(transport, &me, &peer, folder, mark, &hooks, timings, inbox).await;
                    slot.finish();
                    caps.release(conn);
                    let _ = tx.send(Cmd::ReceiveEnded { conn, outcome, gen, handle, peer_id: pid2 });
                    let _ = tx.send(Cmd::Untrack(conn));
                });
            }
        }
    }

    /// An offer is waiting for a click: its run becomes the receive run now (not when its connection was accepted), and it takes the card only if no other flow's card with buttons is up;
    /// otherwise it is declined, and the user never sees it. An offer of a run that was made before Visible was turned off shows nothing and answers nothing.
    fn offer_arrived(&mut self, offer: Offer, handle: ReceiveHandle, conn: u64, gen: u64) {
        if gen != self.generation() {
            return;
        }
        // Another run still holds the place (its claim is given back after it is cleared), so this is not reached by a run that is over; if it ever is, this one is declined rather than put beside it.
        if self.receive.is_some() {
            handle.respond(false);
            return;
        }
        let ticket = self.gate.begin_receive();
        let card = Card::Offer(offer);
        let flow = card.flow().unwrap_or_default();
        if self.present(Some(card), &flow) {
            self.receive = Some(Receiving { conn, ticket, handle, flow });
        } else {
            self.gate.end_receive();
            handle.respond(false);
        }
    }

    /// Bytes came in. A run has one offer, so the connection stands for it: the tick counts only when it is from the run whose offer is the card on the island.
    fn progressed(&mut self, conn: u64, got: u64) {
        let Some(r) = &self.receive else { return };
        if r.conn != conn || !self.gate.is_receive(r.ticket) {
            return;
        }
        let flow = r.flow.clone();
        match self.card.clone() {
            Some(Card::Offer(o)) | Some(Card::Receiving(o, _)) if self.card.as_ref().and_then(Card::flow).as_deref() == Some(flow.as_str()) => {
                let size = o.size;
                self.present(Some(Card::Receiving(o, got)), &flow);
                let now = cards::now_ms();
                if got >= size || now - self.last_progress_at >= 100 {
                    self.last_progress_at = now;
                    self.publish(true);
                }
            }
            _ => {}
        }
    }

    /// The user's click on Accept or Decline. The only way an offer is accepted. `shown` is the card the click was meant for (None: the one on the island).
    fn respond_offer(&mut self, accept: bool, shown: Option<ShownView>) {
        let Some(Card::Offer(o)) = self.card.clone() else { return };
        let Some(shown) = parse_shown(&shown) else { return };
        let Some(r) = &self.receive else { return };
        if !self.rules.accepts(shown.as_ref(), cards::now_ms()) || self.card.as_ref().and_then(Card::flow).as_deref() != Some(r.flow.as_str()) {
            return;
        }
        let (handle, flow) = (r.handle.clone(), r.flow.clone());
        // An offer whose run has already ended (expired, withdrawn) is not accepted: the end is on its way and shows what happened.
        if accept {
            if !self.busy.holds(&o.peer_id) {
                return;
            }
            self.present(Some(Card::Receiving(o, 0)), &flow);
        }
        handle.respond(accept);
    }

    fn cancel_receiving(&mut self, shown: Option<ShownView>) {
        let Some(Card::Receiving(..)) = self.card else { return };
        let Some(shown) = parse_shown(&shown) else { return };
        let Some(r) = &self.receive else { return };
        if self.rules.accepts(shown.as_ref(), cards::now_ms()) && self.card.as_ref().and_then(Card::flow).as_deref() == Some(r.flow.as_str()) {
            r.handle.cancel();
        }
    }

    fn receive_ended(&mut self, conn: u64, outcome: TransferOutcome, gen: u64, handle: ReceiveHandle, peer_id: &str) {
        self.log("a transfer ended");
        // The island first, so that no click reaches a run that is over; the transfer place is given back after that.
        if gen == self.generation() {
            if let Some(r) = &self.receive {
                if r.conn == conn {
                    let flow = r.flow.clone();
                    self.receive = None;
                    self.gate.end_receive();
                    let result = match outcome {
                        TransferOutcome::Completed(path) => Some(Card::Result {
                            title: "Received".into(),
                            detail: match &path {
                                Some(p) => format!("Saved as {} in Downloads/NotchMeow.", p.file_name().and_then(|n| n.to_str()).unwrap_or("the file")),
                                None => "Saved.".into(),
                            },
                            file: path,
                        }),
                        TransferOutcome::Declined { .. } | TransferOutcome::Withdrawn => None,
                        TransferOutcome::Expired => Some(Card::Result { title: "Offer expired".into(), detail: "Nobody answered in 2 minutes, so it was declined.".into(), file: None }),
                        TransferOutcome::Cancelled => Some(Card::Result { title: "Transfer cancelled".into(), detail: "Nothing was saved.".into(), file: None }),
                        TransferOutcome::Aborted(_) => Some(Card::Result { title: "Transfer stopped".into(), detail: "The connection ended before the file was complete. Nothing was saved.".into(), file: None }),
                    };
                    self.present(result, &flow);
                }
            }
        }
        if handle.holds_claim() {
            self.busy.release(peer_id);
        }
    }

    /// The OK on a result, or the close of any card: what the user dismissed is answered "no" / "cancel" for its flow, and a result goes.
    fn dismiss(&mut self, shown: Option<ShownView>) {
        match self.card.clone() {
            Some(Card::Offer(_)) => self.respond_offer(false, shown),
            Some(Card::Pair { answered: false, .. }) => self.answer_pair(false, shown),
            Some(Card::Receiving(..)) => self.cancel_receiving(shown),
            Some(Card::Result { .. }) => {
                let Some(s) = parse_shown(&shown) else { return };
                if self.rules.accepts(s.as_ref(), cards::now_ms()) {
                    let owner = self.rules.owner().unwrap_or("").to_string();
                    self.present(None, &owner);
                }
            }
            _ => {}
        }
    }

    // ── Sending ──

    async fn send(&mut self, paths: Vec<PathBuf>, to: &str) {
        if self.sending || self.send_control.is_some() {
            return;
        }
        let Some(peer) = self.paired_peer(to) else {
            self.send_status = Some("That machine is not on the network.".into());
            return;
        };
        let (Some(target), Some(me)) = (self.seen.get(to).cloned(), self.identity()) else {
            self.send_status = Some("That machine is not on the network.".into());
            return;
        };
        self.sending = true;
        let ctrl = Arc::new(SendControl { cancelled: AtomicBool::new(false), handle: StdMutex::new(None), connecting: Notify::new() });
        self.send_control = Some(ctrl.clone());
        let (gen, tx, cfg) = (self.generation(), self.tx.clone(), self.cfg.clone());
        let conn = self.id();
        tokio::spawn(send_job(tx, ctrl, me, peer, target.addr, paths, gen, conn, cfg));
    }

    /// The Cancel on the shelf's status line. The files that were still to go are not sent, and the send ends within 2 s, whatever phase it is in. A run that exists sends its cancel frame first (the
    /// other side's user then sees "cancelled", not a connection that dropped), and cuts the connection itself only if that frame cannot go out in time. Before there is a run (connecting) there
    /// is nobody to tell, and the connection attempt is dropped now.
    fn cancel_sending(&mut self) {
        if !self.sending {
            return;
        }
        let Some(c) = &self.send_control else { return };
        c.cancelled.store(true, Ordering::SeqCst);
        match c.handle.lock().unwrap().clone() {
            Some(h) => h.cancel(),
            None => {
                c.connecting.notify_waiters();
                self.send_status = Some("Cancelled".into());
            }
        }
    }
}

#[allow(clippy::too_many_arguments)]
async fn send_job(tx: mpsc::UnboundedSender<Cmd>, ctrl: Arc<SendControl>, me: Identity, peer: Peer, addr: SocketAddr, paths: Vec<PathBuf>, gen: u64, conn: u64, cfg: Config) {
    let status = |text: String| {
        let _ = tx.send(Cmd::SendStatus(text, gen));
    };
    let mut sent = 0usize;
    for path in paths {
        if ctrl.cancelled.load(Ordering::SeqCst) {
            break;
        }
        let source = match Source::open(&path) {
            Ok(s) => s,
            Err(e) => {
                let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("That file");
                status(match e {
                    SourceError::NotAFile | SourceError::TooLarge | SourceError::NameTooLong => format!("{name} cannot be sent (a folder, a file over 4 GB, or a name that is too long)."),
                    SourceError::Unreadable => format!("{name} cannot be read."),
                });
                continue;
            }
        };
        let name = source.name.clone();
        status(format!("Waiting for {} to accept {name}", peer.name));
        let transport = tokio::select! {
            t = TcpTransport::connect(addr, cfg.connect_timeout) => t,
            _ = ctrl.connecting.notified() => { status("Cancelled".into()); break; }
        };
        let transport = match transport {
            Ok(t) => t,
            Err(_) => {
                status(if ctrl.cancelled.load(Ordering::SeqCst) { "Cancelled".to_string() } else { format!("Could not reach {}.", peer.name) });
                break;
            }
        };
        // Cancel was clicked while connecting: there is no run to cancel yet, and none is made.
        if ctrl.cancelled.load(Ordering::SeqCst) {
            transport.abort();
            status("Cancelled".into());
            break;
        }
        let _ = tx.send(Cmd::Track { conn, transport: transport.clone(), gen });
        let (handle, inbox) = send_channel(&transport, cfg.send.grace_ms);
        *ctrl.handle.lock().unwrap() = Some(handle);
        let (txp, pname, last) = (tx.clone(), name.clone(), Arc::new(StdMutex::new(-1i64)));
        let peer_name = peer.name.clone();
        let hooks = SendHooks {
            progress: Arc::new(move |done, total| {
                let pct = if total == 0 { 100 } else { (done * 100 / total).min(100) as i64 };
                let mut l = last.lock().unwrap();
                if *l != pct {
                    *l = pct;
                    let _ = txp.send(Cmd::SendStatus(format!("Sending {pname} to {peer_name}, {pct} %"), gen));
                }
            }),
        };
        let outcome = run_send(transport, &me, &peer, source, &hooks, cfg.send, inbox).await;
        *ctrl.handle.lock().unwrap() = None;
        let _ = tx.send(Cmd::Untrack(conn));
        let cancelled = ctrl.cancelled.load(Ordering::SeqCst);
        match outcome {
            // The protocol has no receipt: all the bytes and the end marker went out, which is all this side can say.
            TransferOutcome::Completed(_) => {
                sent += 1;
                status(format!("Finished sending {name} to {}", peer.name));
            }
            TransferOutcome::Declined { reason } => status(match reason {
                1 => format!("{} did not answer in time", peer.name),
                2 => format!("{} is receiving something else right now", peer.name),
                3 => format!("{name} is too large"),
                _ => format!("{} declined {name}", peer.name),
            }),
            TransferOutcome::Expired => {
                status(format!("{} did not answer in time", peer.name));
                ctrl.cancelled.store(true, Ordering::SeqCst);
            }
            TransferOutcome::Withdrawn | TransferOutcome::Cancelled => {
                status("Cancelled".into());
                ctrl.cancelled.store(true, Ordering::SeqCst);
            }
            TransferOutcome::Aborted(_) => status(if cancelled { "Cancelled".to_string() } else { format!("The connection to {} ended", peer.name) }),
        }
    }
    if sent > 1 && !ctrl.cancelled.load(Ordering::SeqCst) {
        status(format!("Finished sending {sent} files to {}", peer.name));
    }
    let _ = tx.send(Cmd::SendDone(gen));
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link::discovery::OnResults;
    use crate::link::keystore::MemoryStore;
    use sha2::{Digest, Sha256};
    use std::sync::atomic::AtomicUsize;

    #[derive(Default)]
    struct FakeDiscovery {
        advert: StdMutex<Option<(String, String, u16)>>,
        adverts: AtomicUsize,
        results: StdMutex<Option<OnResults>>,
    }

    impl Discovery for FakeDiscovery {
        fn advertise(&self, id: &str, name: &str, port: u16) -> Result<(), String> {
            self.adverts.fetch_add(1, Ordering::SeqCst);
            *self.advert.lock().unwrap() = Some((id.into(), name.into(), port));
            Ok(())
        }
        fn stop_advertising(&self) {
            *self.advert.lock().unwrap() = None;
        }
        fn browse(&self, _own: &str, on: OnResults) -> Result<(), String> {
            *self.results.lock().unwrap() = Some(on);
            Ok(())
        }
        fn stop_browsing(&self) {
            *self.results.lock().unwrap() = None;
        }
    }

    impl FakeDiscovery {
        fn show(&self, found: Vec<Found>) {
            if let Some(cb) = &*self.results.lock().unwrap() {
                cb(found);
            }
        }
    }

    #[derive(Default)]
    struct Capture {
        snaps: StdMutex<Vec<Snapshot>>,
        logs: StdMutex<Vec<String>>,
    }

    impl Emit for Capture {
        fn snapshot(&self, s: &Snapshot) {
            self.snaps.lock().unwrap().push(s.clone());
        }
        fn log(&self, line: &'static str) {
            self.logs.lock().unwrap().push(line.to_string());
        }
    }

    struct Node {
        svc: Service,
        disc: Arc<FakeDiscovery>,
        cap: Arc<Capture>,
        folder: PathBuf,
        dir: PathBuf,
    }

    fn temp(tag: &str) -> PathBuf {
        static N: AtomicUsize = AtomicUsize::new(0);
        let d = std::env::temp_dir().join(format!("notchmeow-svc-{tag}-{}-{}", std::process::id(), N.fetch_add(1, Ordering::Relaxed)));
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn node(name: &str) -> Node {
        let dir = temp("node");
        let folder = dir.join("Downloads").join("NotchMeow");
        let mut cfg = Config::app(dir.join("link.json"), folder.clone(), name.to_string());
        cfg.bind = "127.0.0.1:0".parse().unwrap();
        let (disc, cap) = (Arc::new(FakeDiscovery::default()), Arc::new(Capture::default()));
        let store: Arc<dyn SecretStore> = Arc::new(MemoryStore::default());
        let deps = Deps { keystore: Arc::new(Keystore::new(store)), discovery: disc.clone(), emit: cap.clone() };
        let svc = Service::spawn(|f| { tokio::spawn(f); }, cfg, deps);
        svc.start();
        Node { svc, disc, cap, folder, dir }
    }

    async fn until(what: &str, f: impl Fn() -> bool) {
        for _ in 0..1500 {
            if f() {
                return;
            }
            tokio::time::sleep(Duration::from_millis(4)).await;
        }
        panic!("never happened: {what}");
    }

    fn last(n: &Node) -> Option<Snapshot> {
        n.cap.snaps.lock().unwrap().last().cloned()
    }

    async fn wait_snap(n: &Node, what: &str, f: impl Fn(&Snapshot) -> bool) {
        until(what, || last(n).is_some_and(|s| f(&s))).await;
    }

    fn card_kind(n: &Node) -> Option<&'static str> {
        last(n).and_then(|s| s.card).map(|c| c.kind)
    }

    /// B is visible, A has found it and both are paired, as two users agreeing would leave them.
    async fn paired() -> (Node, Node) {
        let (a, b) = (node("Sam's MacBook Pro"), node("Desk PC"));
        a.svc.set_visible(true);
        b.svc.set_visible(true);
        wait_snap(&a, "A listens", |s| s.listening).await;
        wait_snap(&b, "B listens", |s| s.listening).await;
        a.svc.set_shelf_open(true);
        let (id, name, port) = b.disc.advert.lock().unwrap().clone().unwrap();
        until("A browses", || a.disc.results.lock().unwrap().is_some()).await;
        a.disc.show(vec![Found { advert: Advert { id: id.clone(), name }, addr: format!("127.0.0.1:{port}").parse().unwrap() }]);
        wait_snap(&a, "A lists B", |s| s.rows.iter().any(|r| r.id == id)).await;
        b.svc.set_devices_open(true);
        a.svc.pair(id.clone());
        wait_snap(&a, "A's code", |s| s.card.as_ref().is_some_and(|c| c.kind == "pair")).await;
        wait_snap(&b, "B's code", |s| s.card.as_ref().is_some_and(|c| c.kind == "pair")).await;
        let (ca, cb) = (last(&a).unwrap().card.unwrap().code.unwrap(), last(&b).unwrap().card.unwrap().code.unwrap());
        assert_eq!(ca, cb, "both screens show the same six digits");
        tokio::time::sleep(Duration::from_millis(750)).await; // the quiet period of a card that has just appeared
        a.svc.answer_pair(true, None);
        b.svc.answer_pair(true, None);
        wait_snap(&a, "A paired", |s| s.card.as_ref().is_some_and(|c| c.title.as_deref() == Some("Paired"))).await;
        wait_snap(&b, "B paired", |s| s.card.as_ref().is_some_and(|c| c.title.as_deref() == Some("Paired"))).await;
        tokio::time::sleep(Duration::from_millis(750)).await;
        a.svc.dismiss(None);
        b.svc.dismiss(None);
        wait_snap(&a, "A clear", |s| s.card.is_none()).await;
        wait_snap(&b, "B clear", |s| s.card.is_none()).await;
        (a, b)
    }

    fn sha(b: &[u8]) -> String {
        hex(&Sha256::digest(b))
    }

    /// The one sample file that Rust and the page both read (windows/scripts/link-tests/snapshot-samples.json; the page's side is model.test.mjs): what is serialized here is what the page keeps whole.
    #[test]
    fn the_snapshot_the_page_gets_is_the_sample_file() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../scripts/link-tests/snapshot-samples.json");
        let samples: Vec<serde_json::Value> = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        let blank = |folder: &str| Snapshot { visible: true, name: "Desk PC".into(), listening: true, problem: None, note: None, rows: vec![], card: None, send_status: None, sending: false, folder: folder.into() };
        let card = |kind: &'static str, key: &str| CardView { kind, key: key.into(), code: None, peer: None, answered: None, name: None, size: None, received: None, title: None, detail: None, can_reveal: None };
        let row = |id: &str, name: &str, state: &'static str| RowView { id: id.repeat(16), name: name.into(), state };
        let built = vec![
            Snapshot { visible: false, listening: false, ..blank("C:\\Users\\Sam\\Downloads\\NotchMeow") },
            Snapshot {
                note: Some("Wait 30 seconds before trying again.".into()),
                rows: vec![row("a1", "Sam's MacBook Pro", "pairedOnline"), row("b2", "Old netbook", "pairedOffline"), row("c3", "Studio laptop", "available")],
                send_status: Some("Sending report.pdf to Sam's MacBook Pro, 45 %".into()),
                sending: true,
                ..blank("/home/sam/Downloads/NotchMeow")
            },
            Snapshot { problem: Some(ADVERT_PROBLEM.into()), card: Some(CardView { code: Some("483291".into()), peer: Some("Sam's MacBook Pro".into()), answered: Some(false), ..card("pair", "483291|Sam's MacBook Pro") }), ..blank("") },
            Snapshot { card: Some(CardView { name: Some("Quarterly report.pdf".into()), size: Some(2_400_000), peer: Some("Sam's MacBook Pro".into()), ..card("offer", &format!("{}|0102", "a1".repeat(16))) }), ..blank("") },
            Snapshot {
                card: Some(CardView { name: Some("Quarterly report.pdf".into()), size: Some(2_400_000), received: Some(1_080_000), peer: Some("Sam's MacBook Pro".into()), ..card("receiving", &format!("{}|0102", "a1".repeat(16))) }),
                ..blank("")
            },
            Snapshot {
                card: Some(CardView {
                    title: Some("Received".into()),
                    detail: Some("Saved as Quarterly report.pdf in Downloads/NotchMeow.".into()),
                    can_reveal: Some(true),
                    ..card("result", "Received|Saved as Quarterly report.pdf in Downloads/NotchMeow.")
                }),
                ..blank("")
            },
        ];
        assert_eq!(built.len(), samples.len());
        for (b, s) in built.iter().zip(&samples) {
            assert_eq!(serde_json::to_value(b).unwrap(), s["snapshot"], "{}", s["name"]);
        }
    }

    #[tokio::test]
    async fn nothing_listens_and_nothing_is_announced_until_visible_is_turned_on() {
        let n = node("Desk PC");
        let s = n.svc.snapshot().await.unwrap();
        assert!(!s.visible && !s.listening);
        assert!(n.disc.advert.lock().unwrap().is_none(), "no advert");
        assert!(n.disc.results.lock().unwrap().is_none(), "no browser");
        n.svc.set_devices_open(true);
        let s = n.svc.snapshot().await.unwrap();
        assert!(!s.listening && n.disc.results.lock().unwrap().is_none(), "opening Devices does not start anything while Visible is off");
        assert!(n.cap.logs.lock().unwrap().is_empty());
        n.svc.set_visible(true);
        wait_snap(&n, "listening", |s| s.listening).await;
        let (id, name, port) = n.disc.advert.lock().unwrap().clone().unwrap();
        assert!(crate::link::bytes::is_id_hex(&id) && name == "Desk PC" && port > 0);
        assert!(n.disc.results.lock().unwrap().is_some(), "Devices was open: turning Visible on starts the search");
        n.svc.set_visible(false);
        wait_snap(&n, "stopped", |s| !s.listening).await;
        assert!(n.disc.advert.lock().unwrap().is_none(), "the advert goes with the listener");
        assert!(n.disc.results.lock().unwrap().is_none(), "and the browser");
        let saved = settings::load(&n.dir.join("link.json"), "x");
        assert!(!saved.visible, "off is saved");
    }

    #[tokio::test]
    async fn the_search_runs_while_devices_or_the_shelf_is_on_screen_and_stops_when_neither_is() {
        let n = node("Desk PC");
        n.svc.set_visible(true);
        wait_snap(&n, "listening", |s| s.listening).await;
        assert!(n.disc.results.lock().unwrap().is_none(), "visible, but nobody is looking");
        n.svc.set_devices_open(true);
        n.svc.set_devices_open(true); // saying it twice changes nothing
        n.svc.set_shelf_open(true);
        until("browsing", || n.disc.results.lock().unwrap().is_some()).await;
        n.svc.set_devices_open(false);
        n.svc.set_devices_open(false);
        let _ = n.svc.snapshot().await;
        assert!(n.disc.results.lock().unwrap().is_some(), "the shelf is still open");
        n.svc.set_shelf_open(false);
        let _ = n.svc.snapshot().await;
        assert!(n.disc.results.lock().unwrap().is_none(), "nobody looks: the browser is gone");
    }

    #[tokio::test]
    async fn a_name_a_card_would_refuse_is_not_taken_and_a_new_name_is_announced_again() {
        let n = node("Desk PC");
        n.svc.set_visible(true);
        wait_snap(&n, "listening", |s| s.listening).await;
        assert!(!n.svc.set_device_name(" padded".into()).await);
        assert!(!n.svc.set_device_name("a\u{202e}b".into()).await);
        assert!(n.svc.set_device_name("Studio PC".into()).await);
        assert_eq!(n.disc.advert.lock().unwrap().clone().unwrap().1, "Studio PC");
        assert_eq!(n.disc.adverts.load(Ordering::SeqCst), 2);
        assert!(last(&n).unwrap().listening, "the listener was not restarted");
    }

    #[tokio::test]
    async fn two_machines_pair_with_matching_codes_and_send_a_file_that_arrives_whole() {
        let (a, b) = paired().await;
        let ids = (a.disc.advert.lock().unwrap().clone().unwrap().0, b.disc.advert.lock().unwrap().clone().unwrap().0);
        assert_eq!(last(&a).unwrap().rows[0].state, "pairedOnline");
        assert_eq!(last(&b).unwrap().rows[0].id, ids.0, "B knows A too");
        let src = temp("src");
        let data: Vec<u8> = (0..150_000).map(|i| (i % 253) as u8).collect();
        let file = src.join("report.pdf");
        std::fs::write(&file, &data).unwrap();
        a.svc.send(vec![file], ids.1.clone());
        wait_snap(&b, "the offer", |s| s.card.as_ref().is_some_and(|c| c.kind == "offer")).await;
        let card = last(&b).unwrap().card.unwrap();
        assert_eq!((card.name.as_deref(), card.size, card.peer.as_deref()), (Some("report.pdf"), Some(150_000), Some("Sam's MacBook Pro")));
        assert!(!b.folder.exists() || std::fs::read_dir(&b.folder).unwrap().next().is_none(), "nothing is written before the click");
        // A click inside the 700 ms quiet period does nothing; later it accepts.
        b.svc.respond_offer(true, None);
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert_eq!(card_kind(&b), Some("offer"), "too early");
        tokio::time::sleep(Duration::from_millis(700)).await;
        b.svc.respond_offer(true, Some(ShownView { kind: "offer".into(), key: card.key.clone() }));
        wait_snap(&b, "received", |s| s.card.as_ref().is_some_and(|c| c.title.as_deref() == Some("Received"))).await;
        let saved = b.folder.join("report.pdf");
        assert_eq!(sha(&std::fs::read(&saved).unwrap()), sha(&data));
        assert_eq!(b.svc.result_file().await, Some(saved));
        wait_snap(&a, "A's line", |s| s.send_status.as_deref().is_some_and(|t| t.starts_with("Finished sending report.pdf to Desk PC"))).await;
        wait_snap(&a, "A done", |s| !s.sending).await;
        let logs = b.cap.logs.lock().unwrap().join("|");
        assert!(!logs.contains("report") && !logs.contains("Desk") && !logs.contains("127.0.0.1"), "the log holds fixed sentences only: {logs}");
    }

    #[tokio::test]
    async fn a_click_meant_for_another_card_does_nothing() {
        let (a, b) = paired().await;
        let bid = b.disc.advert.lock().unwrap().clone().unwrap().0;
        let src = temp("src");
        std::fs::write(src.join("a.bin"), vec![1u8; 1000]).unwrap();
        a.svc.send(vec![src.join("a.bin")], bid);
        wait_snap(&b, "the offer", |s| s.card.is_some()).await;
        tokio::time::sleep(Duration::from_millis(750)).await;
        b.svc.respond_offer(true, Some(ShownView { kind: "offer".into(), key: "someone else|t9".into() }));
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert_eq!(card_kind(&b), Some("offer"), "a click for a card that is not the one shown does nothing");
        b.svc.respond_offer(false, None);
        wait_snap(&b, "declined", |s| s.card.is_none()).await;
        wait_snap(&a, "A hears no", |s| s.send_status.as_deref() == Some("Desk PC declined a.bin")).await;
        assert!(b.folder.read_dir().map(|mut d| d.next().is_none()).unwrap_or(true));
    }

    #[tokio::test]
    async fn an_incoming_pairing_outside_the_gate_is_refused_silently() {
        let (a, b) = (node("Sam's MacBook Pro"), node("Desk PC"));
        a.svc.set_visible(true);
        b.svc.set_visible(true);
        wait_snap(&a, "A listens", |s| s.listening).await;
        wait_snap(&b, "B listens", |s| s.listening).await;
        a.svc.set_shelf_open(true);
        until("A browses", || a.disc.results.lock().unwrap().is_some()).await;
        let (id, name, port) = b.disc.advert.lock().unwrap().clone().unwrap();
        a.disc.show(vec![Found { advert: Advert { id: id.clone(), name }, addr: format!("127.0.0.1:{port}").parse().unwrap() }]);
        wait_snap(&a, "A lists B", |s| !s.rows.is_empty()).await;
        a.svc.pair(id);
        wait_snap(&a, "A's note", |s| s.note.as_deref() == Some("The pairing did not go through.")).await;
        assert!(last(&b).unwrap().card.is_none(), "no card on B");
        assert!(b.cap.logs.lock().unwrap().iter().all(|l| l != "a pairing ended"), "B did not run a pairing at all");
    }

    #[tokio::test]
    async fn turning_visible_off_while_an_offer_waits_clears_the_card_and_cuts_the_connection() {
        let (a, b) = paired().await;
        let bid = b.disc.advert.lock().unwrap().clone().unwrap().0;
        let src = temp("src");
        std::fs::write(src.join("a.bin"), vec![1u8; 1000]).unwrap();
        a.svc.send(vec![src.join("a.bin")], bid);
        wait_snap(&b, "the offer", |s| s.card.is_some()).await;
        b.svc.set_visible(false);
        wait_snap(&b, "card gone", |s| s.card.is_none() && !s.listening).await;
        wait_snap(&a, "A sees the connection end", |s| s.send_status.as_deref() == Some("The connection to Desk PC ended")).await;
    }

    #[tokio::test]
    async fn forgetting_a_machine_withdraws_its_waiting_offer() {
        let (a, b) = paired().await;
        let (aid, bid) = (a.disc.advert.lock().unwrap().clone().unwrap().0, b.disc.advert.lock().unwrap().clone().unwrap().0);
        let src = temp("src");
        std::fs::write(src.join("a.bin"), vec![1u8; 1000]).unwrap();
        a.svc.send(vec![src.join("a.bin")], bid);
        wait_snap(&b, "the offer", |s| s.card.is_some()).await;
        b.svc.forget(aid);
        wait_snap(&b, "card gone", |s| s.card.is_none() && s.rows.is_empty()).await;
    }

    #[tokio::test]
    async fn a_transfer_from_a_machine_that_is_not_paired_is_closed_without_an_answer() {
        let (a, b) = paired().await;
        let (aid, bid) = (a.disc.advert.lock().unwrap().clone().unwrap().0, b.disc.advert.lock().unwrap().clone().unwrap().0);
        b.svc.forget(aid);
        wait_snap(&b, "forgotten", |s| s.rows.is_empty()).await;
        let src = temp("src");
        std::fs::write(src.join("a.bin"), vec![1u8; 1000]).unwrap();
        a.svc.send(vec![src.join("a.bin")], bid);
        wait_snap(&a, "A's line", |s| s.send_status.as_deref() == Some("The connection to Desk PC ended")).await;
        assert!(last(&b).unwrap().card.is_none());
    }

    #[tokio::test]
    async fn cancelling_a_send_ends_it_and_the_files_still_to_go_are_not_sent() {
        let (a, b) = paired().await;
        let bid = b.disc.advert.lock().unwrap().clone().unwrap().0;
        let src = temp("src");
        for n in ["1.bin", "2.bin", "3.bin"] {
            std::fs::write(src.join(n), vec![1u8; 1000]).unwrap();
        }
        a.svc.send(vec![src.join("1.bin"), src.join("2.bin"), src.join("3.bin")], bid);
        wait_snap(&b, "the first offer", |s| s.card.as_ref().is_some_and(|c| c.kind == "offer")).await;
        a.svc.cancel_sending();
        wait_snap(&a, "cancelled", |s| s.send_status.as_deref() == Some("Cancelled") && !s.sending).await;
        wait_snap(&b, "B's card goes", |s| s.card.as_ref().map_or(true, |c| c.kind == "result")).await;
        tokio::time::sleep(Duration::from_millis(200)).await;
        let offers = b.cap.snaps.lock().unwrap().iter().filter(|s| s.card.as_ref().is_some_and(|c| c.kind == "offer")).map(|s| s.card.as_ref().unwrap().name.clone()).collect::<std::collections::HashSet<_>>();
        assert_eq!(offers.len(), 1, "only the first file was ever offered: {offers:?}");
    }
}
```


**Create `windows/src-tauri/src/link_cmd.rs`:**

```rust
// The link's commands and events (sub-project G2): the thin Tauri layer over `link::service`. The folder `link/` knows no Tauri type; this file is where the service meets the app: it builds
// the service from the app's folders and the system's credential store and mDNS, turns the service's snapshots into the `link` event that the island and the Settings window listen to,
// and exposes the service's calls as commands. Every command only posts a request; the answer is the next snapshot. The page holds ids and never a path, a key or an address: `link_send`
// takes shelf ids and Rust finds the files.

use std::path::PathBuf;
use std::sync::Arc;

use tauri::{AppHandle, Emitter, State};

use crate::link::discovery::Discovery;
use crate::link::files;
use crate::link::keystore::{Keystore, SecretStore, SystemStore};
use crate::link::mdns::Mdns;
use crate::link::service::{Config, Deps, Emit, Service, ShownView, Snapshot};
use crate::{log, platform, settings};

/// The service, as the app manages it.
pub struct LinkHandle(pub Service);

struct TauriEmit(AppHandle);

impl Emit for TauriEmit {
    fn snapshot(&self, s: &Snapshot) {
        let _ = self.0.emit("link", s);
    }
    /// A fixed sentence: never a name, a size, an address or an id.
    fn log(&self, line: &'static str) {
        log::line(line);
    }
}

/// Builds the service. It listens and announces nothing until the user turns Visible on in Settings → Devices.
pub fn init(app: &AppHandle) -> Service {
    let cfg = Config::app(settings::local_dir().join("link.json"), files::default_folder(), crate::link::settings::host_name());
    let store: Arc<dyn SecretStore> = Arc::new(SystemStore::new());
    let discovery: Arc<dyn Discovery> = Arc::new(Mdns::new());
    let deps = Deps { keystore: Arc::new(Keystore::new(store)), discovery, emit: Arc::new(TauriEmit(app.clone())) };
    Service::spawn(|f| { tauri::async_runtime::spawn(f); }, cfg, deps)
}

#[tauri::command]
pub async fn link_state(link: State<'_, LinkHandle>) -> Result<Snapshot, String> {
    link.0.snapshot().await.ok_or_else(|| "the link is not running".to_string())
}

#[tauri::command]
pub fn link_set_visible(link: State<'_, LinkHandle>, on: bool) {
    link.0.set_visible(on);
}

#[tauri::command]
pub async fn link_set_name(link: State<'_, LinkHandle>, name: String) -> Result<bool, String> {
    Ok(link.0.set_device_name(name).await)
}

#[tauri::command]
pub fn link_devices_open(link: State<'_, LinkHandle>, open: bool) {
    link.0.set_devices_open(open);
}

#[tauri::command]
pub fn link_shelf_open(link: State<'_, LinkHandle>, open: bool) {
    link.0.set_shelf_open(open);
}

#[tauri::command]
pub fn link_pair(link: State<'_, LinkHandle>, id: String) {
    link.0.pair(id);
}

#[tauri::command]
pub fn link_answer_pair(link: State<'_, LinkHandle>, yes: bool, shown: Option<ShownView>) {
    link.0.answer_pair(yes, shown);
}

/// The only way an offer is accepted: the page calls it from the Accept button, and nothing else calls it with `true`.
#[tauri::command]
pub fn link_respond_offer(link: State<'_, LinkHandle>, accept: bool, shown: Option<ShownView>) {
    link.0.respond_offer(accept, shown);
}

#[tauri::command]
pub fn link_cancel_receiving(link: State<'_, LinkHandle>, shown: Option<ShownView>) {
    link.0.cancel_receiving(shown);
}

#[tauri::command]
pub fn link_dismiss(link: State<'_, LinkHandle>, shown: Option<ShownView>) {
    link.0.dismiss(shown);
}

#[tauri::command]
pub fn link_forget(link: State<'_, LinkHandle>, id: String) {
    link.0.forget(id);
}

/// "To a device": these shelf items go to this machine, one connection each, each needing the other user's Accept. Rust finds the files from the ids.
#[tauri::command]
pub async fn link_send(link: State<'_, LinkHandle>, ids: Vec<String>, to: String) -> Result<(), String> {
    let paths: Vec<PathBuf> = tauri::async_runtime::spawn_blocking(move || crate::shelf_store().resolve(&ids)).await.map_err(|e| e.to_string())?;
    if !paths.is_empty() {
        link.0.send(paths, to);
    }
    Ok(())
}

#[tauri::command]
pub fn link_cancel_sending(link: State<'_, LinkHandle>) {
    link.0.cancel_sending();
}

/// "Show in folder" on the result card of a saved file.
#[tauri::command]
pub async fn link_reveal_result(link: State<'_, LinkHandle>) -> Result<(), String> {
    if let Some(file) = link.0.result_file().await {
        platform::reveal_file(&file);
    }
    Ok(())
}

/// "Show folder" in Settings → Devices: the folder is made first, so that it can be shown before the first file has come.
#[tauri::command]
pub fn link_reveal_folder() {
    let folder = files::default_folder();
    let _ = std::fs::create_dir_all(&folder);
    platform::reveal_folder(&folder.to_string_lossy());
}

/// The Settings window hid: Devices is no longer open, whatever the page last said.
pub fn settings_hidden(app: &AppHandle) {
    use tauri::Manager;
    if let Some(link) = app.try_state::<LinkHandle>() {
        link.0.set_devices_open(false);
    }
}
```


**Create `windows/scripts/link-tests/rust-wiring.test.mjs`:**

```js
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Where the link (G2) is wired on the Rust side, and what it must never do, pinned as source text. The Windows-only Rust is compiled by CI (windows-tests.yml), not here; the behaviour is
// tested by `cargo test -p notchmeow link::` (windows/scripts/cargo-linux.sh). These are the properties that no unit test can see: a thing that must not appear, and a thing that must appear once.
const read = (rel) => fs.readFileSync(new URL(`../../src-tauri/${rel}`, import.meta.url), "utf8");
const linkDir = new URL("../../src-tauri/src/link/", import.meta.url);
const linkFiles = fs.readdirSync(linkDir).filter((f) => f.endsWith(".rs"));
/** A Rust file without its test module and its comments: what the program does. */
const prod = (rel) => {
  const t = read(rel);
  const i = t.indexOf("#[cfg(test)]\nmod tests");
  const body = i < 0 ? t : t.slice(0, i);
  return body.replace(/^\s*\/\/.*$/gm, "");
};
const linkProd = linkFiles.filter((f) => f !== "conformance.rs" && f !== "testutil.rs").map((f) => [f, prod(`src/link/${f}`)]);

test("lib.rs holds the module, the commands and the service, and the settings window's hide puts Devices away", () => {
  const lib = read("src/lib.rs");
  assert.match(lib, /mod island;\npub mod link;\nmod link_cmd;\nmod log;/);
  for (const c of ["state", "set_visible", "set_name", "devices_open", "shelf_open", "pair", "answer_pair", "respond_offer", "cancel_receiving", "dismiss", "forget", "send", "cancel_sending", "reveal_result", "reveal_folder"]) {
    assert.ok(lib.includes(`            link_cmd::link_${c},\n`), `link_${c} is registered`);
  }
  assert.match(lib, /let link = link_cmd::init\(&handle\);\s*app\.manage\(link_cmd::LinkHandle\(link\.clone\(\)\)\);\s*link\.start\(\);/);
  assert.match(lib, /app\.state::<ai::AiState>\(\)\.forget_custom_key\(\);\s*\/\/[^\n]*\n\s*link_cmd::settings_hidden\(&app\);/);
});

test("the dependencies are the three the lock already holds and the two the owner approved, and nothing else is new", () => {
  const toml = read("Cargo.toml");
  const section = toml.slice(toml.indexOf("[dependencies]"), toml.indexOf("[dev-dependencies]"));
  const names = [...section.matchAll(/^([a-z0-9_-]+) = /gm)].map((m) => m[1]);
  assert.deepEqual(names.sort(), ["getrandom", "lopdf", "mdns-sd", "reqwest", "serde", "serde_json", "sha2", "snow", "tauri", "tauri-plugin-autostart", "tauri-plugin-single-instance", "tokio", "unicode-normalization", "zip"].sort());
  assert.match(section, /^snow = "0\.9"$/m);
  assert.match(section, /^mdns-sd = "0\.11"$/m);
  assert.match(section, /^tokio = \{ version = "1", features = \["net", "io-util", "sync", "time", "rt", "rt-multi-thread", "macros"\] \}$/m);
  assert.doesNotMatch(toml, /^(ring|openssl|native-tls|rustls|chacha20poly1305|x25519|curve25519|if-addrs|socket2|keyring) = .*link/m, "no second crypto stack of its own");
});

test("one-shot timers only: the only sleeps are an idle watch's, the pairing window, an offer's two minutes, the listener's watchdog and its accept back-off; no interval, no thread sleep", () => {
  const sleeps = Object.fromEntries(linkProd.map(([f, t]) => [f, (t.match(/time::sleep\(/g) ?? []).length]).filter(([, n]) => n > 0));
  assert.deepEqual(sleeps, { "channel.rs": 1, "net.rs": 2, "pair_run.rs": 1, "transfer.rs": 1 });
  for (const [f, t] of linkProd) {
    assert.doesNotMatch(t, /interval\(|thread::sleep|Instant::now\(\)\s*\+|loop \{\s*tokio::time/, f);
  }
});

test("a socket is opened in net.rs and the multicast daemon in mdns.rs, each once", () => {
  const where = (re) => linkProd.filter(([, t]) => re.test(t)).map(([f]) => f);
  assert.deepEqual(where(/TcpListener::bind/), ["net.rs"]);
  assert.deepEqual(where(/UdpSocket/), []);
  assert.deepEqual(where(/ServiceDaemon::new\(\)/), ["mdns.rs"]);
  assert.deepEqual(where(/std::thread::spawn/), ["mdns.rs"], "the one thread is the browser's, asleep in recv()");
  assert.equal((prod("src/link/mdns.rs").match(/ServiceDaemon::new\(\)/g) ?? []).length, 1);
});

test("nothing listens before Visible: the listener starts in one place, and that place is reached only when the machine is visible", () => {
  const svc = prod("src/link/service.rs");
  assert.equal((svc.match(/Listener::start\(/g) ?? []).length, 1);
  assert.match(svc, /async fn start_listening\(&mut self\) \{\s*if self\.listener\.is_some\(\) \{\s*return;\s*\}/);
  const calls = [...svc.matchAll(/self\.start_listening\(\)\.await;/g)].length;
  assert.equal(calls, 3, "start (guarded), set_visible, devices open (guarded)");
  assert.match(svc, /if self\.settings\.visible \{\s*self\.start_listening\(\)\.await;\s*\}/);
  assert.match(svc, /if self\.settings\.visible && !self\.listening \{\s*self\.start_listening\(\)\.await;/);
  assert.match(svc, /if on \{\s*self\.reload_peers\(\);\s*self\.start_listening\(\)\.await;/);
  assert.match(svc, /if self\.browse_token\.is_some\(\) \|\| !self\.looking\(\) \|\| !self\.settings\.visible \{/, "the browser also needs Visible and someone looking");
  assert.match(read("src/link/settings.rs"), /LinkSettings \{ visible: is_true\(raw\.get\("visible"\)\)/, "off unless exactly true");
});

test("only a click accepts: nothing in the link says yes to an offer by itself", () => {
  for (const [f, t] of linkProd) assert.doesNotMatch(t, /respond\(true\)/, f);
  const svc = prod("src/link/service.rs");
  assert.equal((svc.match(/handle\.respond\(accept\)/g) ?? []).length, 1, "one place, in respond_offer, with the user's answer");
  assert.match(svc, /fn respond_offer\(&mut self, accept: bool, shown: Option<ShownView>\)/);
  assert.match(prod("src/link_cmd.rs"), /pub fn link_respond_offer\(link: State<'_, LinkHandle>, accept: bool, shown: Option<ShownView>\) \{\s*link\.0\.respond_offer\(accept, shown\);/);
});

test("a received file is never opened, run or followed: no process is started and nothing is opened from the link", () => {
  for (const [f, t] of [...linkProd, ["link_cmd.rs", prod("src/link_cmd.rs")]]) {
    assert.doesNotMatch(t, /Command::new|ShellExecute|open_url|opener|xdg-open|start_process/, f);
  }
  const cmd = prod("src/link_cmd.rs");
  assert.ok((cmd.match(/platform::reveal_file|platform::reveal_folder/g) ?? []).length === 2, "show in folder is the only thing done with a file");
  const files = prod("src/link/files.rs");
  assert.match(files, /create_new\(true\)/, "a received file is created exclusively");
  assert.match(files, /O_NOFOLLOW/);
  assert.match(files, /ZoneId=3/, "Windows: the mark of the web, zone 3");
  assert.match(files, /Zone\.Identifier/);
});

test("no secret on disk, no name in a log: the credential store is the keystore's alone, the log holds fixed sentences", () => {
  const where = (re) => linkProd.filter(([, t]) => re.test(t)).map(([f]) => f);
  assert.deepEqual(where(/keyring::/), ["keystore.rs"]);
  assert.deepEqual(where(/std::fs::(write|File::create)|fs::write\(/), ["files.rs", "settings.rs"], "the files the link writes: the mark of a received file (files.rs) and link.json, which holds the switch and the name");
  assert.match(prod("src/link/settings.rs"), /json!\(\{"visible": s\.visible, "deviceName": s\.device_name\}\)/, "and it holds the switch and the name, nothing else");
  assert.deepEqual(where(/println!|eprintln!|dbg!|log::line/), []);
  const cmd = prod("src/link_cmd.rs");
  assert.match(cmd, /fn log\(&self, line: &'static str\) \{\s*log::line\(line\);/);
  assert.equal((cmd.match(/log::line\(/g) ?? []).length, 1);
  const svc = read("src/link/service.rs");
  const lines = [...svc.matchAll(/self\.log\("([^"]+)"\)/g)].map((m) => m[1]);
  assert.deepEqual([...new Set(lines)].sort(), ["a pairing ended", "a transfer ended", "a transfer started", "listening", "stopped listening"]);
});

test("this computer's name is read in one place, for the default device name only", () => {
  const where = (re) => linkProd.filter(([, t]) => re.test(t)).map(([f]) => f);
  assert.deepEqual(where(/COMPUTERNAME|kernel\/hostname|\/etc\/hostname|gethostname/), ["settings.rs"]);
  assert.doesNotMatch(prod("src/link_cmd.rs").replace(/crate::link::settings::host_name\(\)/, ""), /COMPUTERNAME|hostname/);
  assert.doesNotMatch(prod("src/link/mdns.rs"), /host_name\(\)|COMPUTERNAME/, "the advert's host name is made from the device id");
  assert.match(prod("src/link/mdns.rs"), /format!\("notchmeow-\{\}\.local\.", &id\[\.\.8\.min\(id\.len\(\)\)\]\)/);
});

test("a debug build keeps its keys under a service name of its own", () => {
  assert.match(prod("src/link/keystore.rs"), /pub const SERVICE: &str = if cfg!\(debug_assertions\) \{ "io\.github\.aikusan\.notchmeow\.debug" \} else \{ "io\.github\.aikusan\.notchmeow" \};/);
});

test("the state the page sees is serialized by one type, and the commands take ids", () => {
  const cmd = prod("src/link_cmd.rs");
  assert.match(cmd, /crate::shelf_store\(\)\.resolve\(&ids\)/);
  assert.doesNotMatch(cmd, /pub (async )?fn link_\w+\([^)]*(PathBuf|Path\b|path:)/, "no command takes a path from the page");
});
```


- [ ] **Step 2: Wire `lib.rs`**

```bash
python3 - <<'EOF'
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")
L = "windows/src-tauri/src/lib.rs"
edit(L, "mod island;\nmod log;", "mod island;\npub mod link;\nmod link_cmd;\nmod log;")
cmds = "".join(f"            link_cmd::link_{c},\n" for c in ["state", "set_visible", "set_name", "devices_open", "shelf_open", "pair", "answer_pair", "respond_offer", "cancel_receiving", "dismiss", "forget", "send", "cancel_sending", "reveal_result", "reveal_folder"])
edit(L, "            shelf_send,\n", "            shelf_send,\n" + cmds)
edit(L, "            tray::build(&handle)?;\n", """            tray::build(&handle)?;
            // The link between the user's machines (sub-project G2): built here, it listens and announces nothing until the user turns Visible on in Settings -> Devices.
            let link = link_cmd::init(&handle);
            app.manage(link_cmd::LinkHandle(link.clone()));
            link.start();
""")
edit(L, "                    app.state::<ai::AiState>().forget_custom_key();\n", """                    app.state::<ai::AiState>().forget_custom_key();
                    // Settings → Devices is no longer on screen, whatever the page last said: Rust is the one that knows the window went away.
                    link_cmd::settings_hidden(&app);
""")
EOF
```

- [ ] **Step 3: Compile (the first time `snow`, `mdns-sd`, `keyring` and Tauri meet this code) and run**

```bash
windows/scripts/cargo-linux.sh check --target-dir /repo/windows/target/g2-tauri -p notchmeow --all-targets 2>&1 | grep -E "^(error|warning)" -A8 | head -60
for m in service; do windows/scripts/cargo-linux.sh test --target-dir /repo/windows/target/g2-tauri -p notchmeow link::$m 2>&1 | grep -E "test result|FAILED|panicked"; done
windows/scripts/cargo-linux.sh test --target-dir /repo/windows/target/g2-tauri -p notchmeow link:: 2>&1 | grep -E "test result|FAILED|panicked"
cd windows && npm run check:link 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..
```

Expected: no `error` (a `warning` of an unused import in `link_cmd.rs` is fixed by removing that import; any other warning in the link folder is reported); `ok. 11 passed` for `link::service`, then every `link::` test passes (the count is the sum of Tasks 2 to 12 and this one; write it in the ledger), and `check:link` prints `ℹ tests 33`, `ℹ pass 33`, `ℹ fail 0` (10 model, 3 alert, 9 wiring, 11 rust wiring). If `app.manage` or `link.start()` is not in scope in `lib.rs`'s `setup`, `tauri::Manager` is already imported by that file (it uses `app.state`): fix the call, never the pin; the wiring test reads exactly these three lines.

The service tests are the Review Focus ones: `an_incoming_pairing_outside_the_gate_is_refused_silently` and `a_transfer_from_a_machine_that_is_not_paired_is_closed_without_an_answer` (1); `turning_visible_off_while_an_offer_waits_clears_the_card_and_cuts_the_connection`, `nothing_listens_and_nothing_is_announced_until_visible_is_turned_on` (4); `a_click_meant_for_another_card_does_nothing` (5); and the whole-conversation one: `two_machines_pair_with_matching_codes_and_send_a_file_that_arrives_whole` (two services, real loopback TCP, real files, in-memory keys: pair, then send, then compare the bytes). `the_snapshot_the_page_gets_is_the_sample_file` serializes a `Snapshot` and requires it to equal `windows/scripts/link-tests/snapshot-samples.json`, which the page's `cleanSnapshot` keeps whole (Task 8): **the two sides cannot drift apart without a test failing**.

- [ ] **Step 4: Prove it bites**

```bash
M="python3 .claude/checkpoints/g2-tauri/mut.py rust"
$M windows/src-tauri/src/link/service.rs '        if self.browse_token.is_some() || !self.looking() || !self.settings.visible {' '        if self.browse_token.is_some() || !self.looking() {' link::service
cd windows
N="python3 ../.claude/checkpoints/g2-tauri/mut.py node"
$N src-tauri/src/link_cmd.rs 'link.0.respond_offer(accept, shown);' 'link.0.respond_offer(true, shown);' scripts/link-tests/rust-wiring.test.mjs
$N src-tauri/src/link/service.rs '        handle.respond(accept);' '        handle.respond(true);' scripts/link-tests/rust-wiring.test.mjs
cd ..
```

Expected: the first prints `FAILED` (the search must not run while the machine is invisible); the other two print `# fail` above 0 (the Accept path must say yes only with the user's answer).

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/src-tauri/src/link/mod.rs windows/src-tauri/src/link/service.rs windows/src-tauri/src/link_cmd.rs windows/src-tauri/src/lib.rs windows/scripts/link-tests/rust-wiring.test.mjs
git commit -F - <<'MSG'
feat(link): the service, the commands and the app's wiring (G2-tauri)

One actor owns the cards, the pairing, the receiving, the sending, the listener and the browser: nothing listens until Visible is on, an incoming pairing needs the gate, one card at a time, one transfer per machine, only a click accepts, and every late event of a stopped conversation is stale. link_cmd.rs is the only Tauri file of the link: 15 commands and the link event.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Write the task's line in the ledger.

---


### Task 14: The test peer and the cross-app check

**Agent:** `nm-implementer` (Haiku 5.5, high). The files are given in full and were run while the plan was drafted (the example compiled and the two-process script passed, with a stand-in Noise: step 3 is the first run on the real one).

**Files:**
- Create: `windows/src-tauri/examples/link_peer.rs`, `windows/scripts/link-peers.sh`, `windows/scripts/test-link-peers.sh`

**Interfaces:**
- Consumes: the whole `link` module (`Service`, `Config`, `Deps`, `Emit`, `Keystore`, `MemoryStore`, `Mdns`, `Discovery`, `Found`, `Advert`). The example is **outside the app**: it is built only by `cargo build --example`, a release of the app does not contain it, and it uses `MemoryStore`, never the credential store.
- Produces: `cargo run --example link_peer -- "Name" [--bind ADDR] [--peer ID@ADDR/NAME]`: a terminal peer with a new identity per run that speaks the real protocol (commands `visible`, `id`, `list`, `pair N`, `yes`, `no`, `accept`, `decline`, `send PATH N`, `cancel`, `quit`); `windows/scripts/link-peers.sh BIN` (two peers in two processes, on loopback, checking the digits and a SHA-256); `windows/scripts/test-link-peers.sh` (builds the example and runs the script in the Linux container).

**The cross-app check, as far as a container can take it.** Three layers, from the most automatic to the one only the owner can run:
1. **Recorded conversations** (Task 11, `conformance.rs`): the app's real pairing and transfer-handshake runs play against bytes that the Mac's code produced, and must write the same bytes. This runs in `cargo test` and is the check that the **two apps agree on the wire**, byte for byte, without running together.
2. **Two real processes** (this task, `test-link-peers.sh`): two `link_peer` processes, each a whole service, pair over real TCP on loopback with the real Noise and the real files, both showing **the same six digits**; one sends a 300 000-byte file, the other accepts and its copy has the same SHA-256; a second file is declined and never written. `--bind` and `--peer` replace mDNS (no multicast in a container), so this tests the protocol, the service and the disk, and not mDNS or the credential store.
3. **The Mac and a PC** (Task 16, checks 4 and 5, by the owner): `link_peer` run on the same network as the Mac's Debug build, discovery by mDNS, pairing with the Mac, files both ways. The Swift test binary that the Mac plan's Task 16 describes (a loopback check of the Swift and Rust code in one script) is not built by either plan yet; when it is, `link_peer --bind ... --peer ...` is the Rust side it needs, and `link-peers.sh` shows the choreography (the 700 ms settle before a click, the gate, the order of the calls).

- [ ] **Step 1: Create the files**

**Create `windows/src-tauri/examples/link_peer.rs`:**

```rust
// A real-protocol test peer for the link (sub-project G2), for the owner's check on real machines and for whoever tests the Mac against the PC: it runs the same `link::service` as the app,
// with the same Noise, frames and files, but with its keys in memory (a new identity each run, so each run pairs again) and a plain terminal in place of the island. Run it next to the Mac's
// Debug build (or a second PC) on the same network:
//
//     cargo run --example link_peer -- "Test peer"
//
// When mDNS is blocked (a guest Wi-Fi, a container), name the other machine yourself: it prints its own id and the address it listens on, and takes the other one's with `--peer`:
//
//     cargo run --example link_peer -- "Test peer" --bind 127.0.0.1:47001 --peer 0123...(32 hex digits)@127.0.0.1:47002/Other
//
// Commands, one per line: `visible`, `id`, `list`, `pair N`, `yes`, `no`, `accept`, `decline`, `send PATH N`, `cancel`, `quit`. It prints the six digits, every offer, and what was received.
// Received files go to a folder under the system's temporary folder, which it prints. It never starts on its own: nothing listens until `visible`. This file is an example and is not part of
// the app: a release build does not contain it.

use std::io::BufRead;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};

use notchmeow_lib::link::discovery::{Discovery, Found, OnResults};
use notchmeow_lib::link::frames::Advert;
use notchmeow_lib::link::keystore::{Keystore, MemoryStore, SecretStore};
use notchmeow_lib::link::mdns::Mdns;
use notchmeow_lib::link::service::{Config, Deps, Emit, Service, ShownView, Snapshot};

/// A machine named on the command line instead of found by mDNS: it is "seen" at once, at the address given.
struct Fixed(Found);

impl Discovery for Fixed {
    fn advertise(&self, _id: &str, _name: &str, _port: u16) -> Result<(), String> {
        Ok(())
    }
    fn stop_advertising(&self) {}
    fn browse(&self, own_id: &str, on_results: OnResults) -> Result<(), String> {
        if self.0.advert.id != own_id {
            on_results(vec![self.0.clone()]);
        }
        Ok(())
    }
    fn stop_browsing(&self) {}
}

struct Print(Mutex<Option<Snapshot>>);

impl Emit for Print {
    fn snapshot(&self, s: &Snapshot) {
        let mut last = self.0.lock().unwrap();
        let was = last.clone();
        if was.as_ref().map(|w| (&w.card, &w.rows, &w.send_status, &w.note, &w.problem)) != Some((&s.card, &s.rows, &s.send_status, &s.note, &s.problem)) {
            if let Some(c) = &s.card {
                println!("card: {} {:?} code={:?} peer={:?} name={:?} received={:?} title={:?} detail={:?}", c.kind, c.key, c.code, c.peer, c.name, c.received, c.title, c.detail);
            } else if was.as_ref().is_some_and(|w| w.card.is_some()) {
                println!("card: none");
            }
            if let Some(t) = &s.send_status {
                println!("send: {t}");
            }
            if let Some(n) = &s.note {
                println!("note: {n}");
            }
            if let Some(p) = &s.problem {
                println!("problem: {p}");
            }
            for (i, r) in s.rows.iter().enumerate() {
                println!("  [{i}] {} ({})", r.name, r.state);
            }
        }
        *last = Some(s.clone());
    }
    fn log(&self, line: &'static str) {
        println!("log: {line}");
    }
}

/// `ID@ADDR/NAME`: the id is 32 lower-case hex digits, the address `host:port`, the name the other machine's.
fn parse_peer(text: &str) -> Option<Found> {
    let (id, rest) = text.split_once('@')?;
    let (addr, name) = rest.split_once('/')?;
    Some(Found { advert: Advert { id: id.to_string(), name: name.to_string() }, addr: addr.parse::<SocketAddr>().ok()? })
}

fn main() {
    let mut args = std::env::args().skip(1);
    let mut name = "Test peer".to_string();
    let (mut bind, mut peer): (Option<SocketAddr>, Option<Found>) = (None, None);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--bind" => bind = args.next().and_then(|v| v.parse().ok()),
            "--peer" => peer = args.next().and_then(|v| parse_peer(&v)),
            other => name = other.to_string(),
        }
    }
    let dir = std::env::temp_dir().join(format!("notchmeow-link-peer-{}", std::process::id()));
    let folder = dir.join("received");
    std::fs::create_dir_all(&dir).expect("a folder to work in");
    let runtime = tokio::runtime::Runtime::new().expect("a runtime");
    let store: Arc<dyn SecretStore> = Arc::new(MemoryStore::default());
    let keystore = Arc::new(Keystore::new(store));
    let own_id = keystore.device_id().expect("an id in memory");
    let discovery: Arc<dyn Discovery> = match peer {
        Some(found) => Arc::new(Fixed(found)),
        None => Arc::new(Mdns::new()),
    };
    let print = Arc::new(Print(Mutex::new(None)));
    let mut cfg = Config::app(dir.join("link.json"), folder.clone(), name.clone());
    if let Some(b) = bind {
        cfg.bind = b;
    }
    let handle = runtime.handle().clone();
    let svc = Service::spawn(move |f| { handle.spawn(f); }, cfg, Deps { keystore, discovery, emit: print });
    svc.start();
    println!("NotchMeow link test peer \"{name}\", id {own_id}. Received files: {}", folder.display());
    println!("Commands: visible, id, list, pair N, yes, no, accept, decline, send PATH N, cancel, quit");
    let _guard = runtime.enter();
    // The terminal counts as Devices being open: this peer is there to be paired with.
    svc.set_devices_open(true);
    let shown = |svc: &Service| runtime.block_on(svc.snapshot()).and_then(|s| s.card).map(|c| ShownView { kind: c.kind.to_string(), key: c.key });
    for line in std::io::stdin().lock().lines().map_while(Result::ok) {
        let mut parts = line.trim().splitn(3, ' ');
        match (parts.next(), parts.next(), parts.next()) {
            (Some("visible"), _, _) => svc.set_visible(true),
            (Some("id"), _, _) => println!("{own_id}"),
            (Some("list"), _, _) => {
                if let Some(s) = runtime.block_on(svc.snapshot()) {
                    for (i, r) in s.rows.iter().enumerate() {
                        println!("  [{i}] {} ({})", r.name, r.state);
                    }
                }
            }
            (Some("pair"), Some(n), _) => {
                if let Some(r) = runtime.block_on(svc.snapshot()).and_then(|s| n.parse::<usize>().ok().and_then(|i| s.rows.get(i).cloned())) {
                    svc.pair(r.id);
                }
            }
            (Some("yes"), _, _) => svc.answer_pair(true, shown(&svc)),
            (Some("no"), _, _) => svc.answer_pair(false, shown(&svc)),
            (Some("accept"), _, _) => svc.respond_offer(true, shown(&svc)),
            (Some("decline"), _, _) => svc.respond_offer(false, shown(&svc)),
            (Some("send"), Some(path), Some(n)) => {
                if let Some(r) = runtime.block_on(svc.snapshot()).and_then(|s| n.trim().parse::<usize>().ok().and_then(|i| s.rows.get(i).cloned())) {
                    svc.send(vec![path.into()], r.id);
                }
            }
            (Some("cancel"), _, _) => svc.cancel_sending(),
            (Some("quit"), _, _) => break,
            _ => println!("?"),
        }
    }
}
```


**Create `windows/scripts/link-peers.sh`:**

```bash
#!/usr/bin/env bash
# Two real link_peer processes on this computer (sub-project G2): the same service, Noise, frames, files and TCP as the app, in two processes, each with its own keys in memory. Machine A listens,
# machine B names A on the command line (no mDNS, no credential store: this is the protocol and the files). B pairs with A and both say the digits match; B sends a file and A accepts; B sends a
# second file and A declines. It checks that both showed the same six digits, that A's copy has B's SHA-256 and that the declined file was never written.
#
# usage: windows/scripts/link-peers.sh PATH/TO/link_peer          (windows/scripts/test-link-peers.sh builds it and runs this in the Linux container)
set -euo pipefail
BIN="${1:?usage: link-peers.sh PATH/TO/link_peer}"
W="$(mktemp -d)"
trap 'exec 7>&- 8>&- 2>/dev/null || true; kill $(jobs -p) 2>/dev/null || true; rm -rf "$W"' EXIT
mkfifo "$W/a.in" "$W/b.in"
head -c 300000 /dev/urandom > "$W/one.bin"
head -c 1000 /dev/urandom > "$W/two.bin"
sha() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

wait_for() {   # wait_for FILE PATTERN [SECONDS]
  local i; for ((i = 0; i < ${3:-30} * 10; i++)); do grep -qE "$2" "$1" 2>/dev/null && return 0; sleep 0.1; done
  echo "TIMEOUT waiting for '$2' in $1"; echo "--- A"; cat "$W/a.out"; echo "--- B"; cat "$W/b.out"; exit 1
}

PORT=$((20000 + RANDOM % 20000))
"$BIN" "Desk PC" --bind "127.0.0.1:$PORT" < "$W/a.in" > "$W/a.out" 2>&1 &
exec 7> "$W/a.in"
wait_for "$W/a.out" 'Commands:'
echo id >&7; wait_for "$W/a.out" '^[0-9a-f]{32}$'
A_ID="$(grep -E '^[0-9a-f]{32}$' "$W/a.out" | head -1)"
A_FOLDER="$(sed -n 's/.*Received files: //p' "$W/a.out" | head -1)"

"$BIN" "Sam's laptop" --bind 127.0.0.1:0 --peer "$A_ID@127.0.0.1:$PORT/Desk PC" < "$W/b.in" > "$W/b.out" 2>&1 &
exec 8> "$W/b.in"
wait_for "$W/b.out" 'Commands:'
echo visible >&7; echo visible >&8
wait_for "$W/a.out" 'log: listening'; wait_for "$W/b.out" 'log: listening'
wait_for "$W/b.out" '\[0\] Desk PC \(available\)'

echo "pair 0" >&8
wait_for "$W/a.out" 'card: pair'; wait_for "$W/b.out" 'card: pair'
CODE_A="$(grep -o 'code=Some("[0-9]*")' "$W/a.out" | head -1)"; CODE_B="$(grep -o 'code=Some("[0-9]*")' "$W/b.out" | head -1)"
[ -n "$CODE_A" ] && [ "$CODE_A" = "$CODE_B" ] || { echo "the two machines showed different digits: $CODE_A / $CODE_B"; exit 1; }
sleep 1   # a click within 700 ms of a card appearing is ignored (the settle rule)
echo yes >&7; echo yes >&8
wait_for "$W/a.out" 'result "Paired'; wait_for "$W/b.out" 'result "Paired'

echo "send $W/one.bin 0" >&8
wait_for "$W/a.out" 'card: offer.*name=Some\("one.bin"\)'
sleep 1; echo accept >&7
wait_for "$W/a.out" 'result "Received'; wait_for "$W/b.out" 'Finished sending one.bin'
[ "$(sha "$A_FOLDER/one.bin")" = "$(sha "$W/one.bin")" ] || { echo "the received file differs from the one sent"; exit 1; }

echo "send $W/two.bin 0" >&8
wait_for "$W/a.out" 'card: offer.*name=Some\("two.bin"\)'
sleep 1; echo decline >&7
wait_for "$W/b.out" 'send: Desk PC declined two.bin'
[ ! -e "$A_FOLDER/two.bin" ] || { echo "a declined file was written"; exit 1; }
echo quit >&7; echo quit >&8
echo "link peers: ok (same digits on both machines, a file that arrived with its SHA-256, a declined file that was never written)"
```


Create `windows/scripts/test-link-peers.sh`:

```bash
#!/usr/bin/env bash
# Builds the link_peer example and runs windows/scripts/link-peers.sh with it in the Linux container (Docker Desktop must be running). Two processes, real TCP on loopback, real Noise and files.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
"$repo/windows/scripts/cargo-linux.sh" build --target-dir /repo/windows/target/g2-tauri -p notchmeow --example link_peer
exec docker run --rm \
  -v "$repo":/repo \
  -v notchmeow-linux-target:/repo/windows/target \
  -v notchmeow-linux-cargo:/usr/local/cargo/registry \
  -w /repo/windows \
  notchmeow-linux-dev \
  bash /repo/windows/scripts/link-peers.sh /repo/windows/target/g2-tauri/debug/examples/link_peer
```

```bash
chmod +x windows/scripts/link-peers.sh windows/scripts/test-link-peers.sh
bash -n windows/scripts/link-peers.sh && bash -n windows/scripts/test-link-peers.sh && echo "syntax ok"
```

- [ ] **Step 2: Build the example**

```bash
windows/scripts/cargo-linux.sh build --target-dir /repo/windows/target/g2-tauri -p notchmeow --example link_peer 2>&1 | grep -E "^(error|warning)" -A7 | head -30
```

Expected: no `error` (the example uses only what Tasks 6, 12 and 13 made public; if a name differs, fix the example, never the library).

- [ ] **Step 3: Run the two processes**

```bash
bash windows/scripts/test-link-peers.sh 2>&1 | tail -5
```

Expected: `link peers: ok (same digits on both machines, a file that arrived with its SHA-256, a declined file that was never written)`. A `TIMEOUT waiting for '...'` line names the step, and prints both peers' output: read it before anything else. (The first run on the real `snow` is also the first time two processes use it: a failure in the handshake here is a real finding of Task 2 or 11, not of this task.)

- [ ] **Step 4: Prove it bites**

Make the receiving disk lose the last byte of each chunk, run the check, and undo it (`files.rs` was committed in Task 7, so `git checkout` restores it):

```bash
python3 - <<'EOF'
import pathlib
p = pathlib.Path("windows/src-tauri/src/link/files.rs"); t = p.read_text(encoding="utf-8")
a = "file.write_all(data).map_err(|_| SinkError::Io)?;"
assert t.count(a) == 1
p.write_text(t.replace(a, "file.write_all(&data[..data.len().saturating_sub(1)]).map_err(|_| SinkError::Io)?;"), encoding="utf-8")
EOF
bash windows/scripts/test-link-peers.sh 2>&1 | tail -2
git checkout -- windows/src-tauri/src/link/files.rs
```

Expected: `the received file differs from the one sent`.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git status --short windows/src-tauri/src/link/files.rs      # must print nothing
git add windows/src-tauri/examples/link_peer.rs windows/scripts/link-peers.sh windows/scripts/test-link-peers.sh
git commit -F - <<'MSG'
feat(link): a real-protocol test peer and a two-process check (G2-tauri)

cargo run --example link_peer is the whole link service with keys in memory and a terminal for an island; link-peers.sh runs two of them on loopback and checks the digits, a file's SHA-256 and a declined file. It is the Rust side for any check against the Mac's app, by mDNS or with --peer.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Write the task's line in the ledger.

---


### Task 15: Docs, CI and the pins

**Agent:** `nm-implementer-light` (Haiku 5.5, medium). Every text is given in full; the edits are additive and the script refuses a find that does not occur exactly once.

**Files:**
- Modify: `windows/README.md`, `CLAUDE.md`, `ARCHITECT.md`, `docs/SPEC.md`, `.github/workflows/windows-tests.yml`, `.github/workflows/linux.yml`

**Interfaces:** consumes the names of Tasks 2 to 14; produces nothing the code needs. `docs/SPEC.md` is in French, like the rest of that file.

- [ ] **Step 1: The edits**

Save this script to a file (it holds long texts; a heredoc of it would end at the first `EOF` inside) and run it from the repository root:

```bash
mkdir -p .claude/checkpoints/g2-tauri
cat > .claude/checkpoints/g2-tauri/docs_edit.py <<'PYEOF'
import pathlib
def edit(path, find, repl):
    p = pathlib.Path(path); t = p.read_text(encoding="utf-8")
    assert t.count(find) == 1, (path, find[:70], t.count(find))
    p.write_text(t.replace(find, repl), encoding="utf-8")

# ── windows/README.md: for people, for testers, and where it differs from the Mac ──
edit("windows/README.md", "\n## Claude Code\n", """
## Between your machines

The shelf can send a file to your other Macs and PCs that run NotchMeow on the same network. **Settings → Devices → Visible on this network** is **off** until you turn it on: until then nothing listens, nothing is announced, and Windows asks no firewall question. Turn it on, and the machines you can see are listed; **Pair** one, check that both screens show the same six digits, and click **They match** on each. After that, tick files on the shelf, press the small laptop button and pick a machine: the other machine shows a card with the file's name and size, **only its Accept button accepts** (the island opens for it even if it was hidden, and the desktop cat flies in), and a card nobody answers is declined after 2 minutes. A received file is saved in `Downloads\\NotchMeow\\` (`~/Downloads/NotchMeow/` on Linux), never opened, never overwritten (a taken name gets a number), at most 4 GiB, one transfer at a time. On Windows it is marked as downloaded from the Internet (the mark of the web), so Explorer and SmartScreen treat it like a file from a browser; Linux has no such mark. The keys live in the Windows Credential Manager or the Linux Secret Service, never in a file. **Windows:** the first time Visible is on, Windows Defender Firewall asks whether to allow NotchMeow: allow it on private networks, or the other machines will not see this one. **Linux:** the link needs a running Secret Service (GNOME Keyring or KWallet); without one it says so and stays off, and keeps nothing in a file instead. Your firewall must allow UDP 5353 (mDNS) and NotchMeow's incoming connections on the local network. The link is IPv4 only.

## Claude Code
""")
edit("windows/README.md", "\n## What's different from the Mac version\n", """
### Testing the link

The link (sub-project G2) follows `tests/fixtures/link/` (`docs/LINK-CONTRACT.md`). **Rust does all of it**, in `src-tauri/src/link/` (no Tauri type in that folder; `src-tauri/src/link_cmd.rs` is the one Tauri file: 15 commands and the `link` event): the pure rules are ports of `reference.py` replayed by `cargo test` (`name`, `frames`, `pairing`, `flow` with `places[]`, `connections[]` and `firstFrame[]`, `cards`, `noise` on the vetted `snow` crate), `channel`/`pair_run`/`transfer` are the conversations over `Transport` (in memory in the tests, `net.rs` on TCP in the app), `conformance.rs` plays the real runs against the recorded conversations of `noise-vectors.json` byte for byte, `service.rs` is the actor that owns every decision, and `mdns.rs` is the advert and the browser on `mdns-sd`. The page (`src/link/`, `views/link.ts`, `views/shelfdevice.ts`, `island/link.ts`, `settings/devices.ts`) holds only what Rust last said (`LinkStore`) and ids, never a key, an address or a path; `npm run check:link` replays the snapshot samples shared with Rust, the island's rule for a card, the desktop cat's alert for an offer and the wiring pins, and `windows/scripts/cargo-linux.sh test -p notchmeow link::` runs the Rust. **Two new crates** were approved by the owner on 2026-10-14: `snow` (Noise, MIT/Apache-2.0) and `mdns-sd` (mDNS, MIT/Apache-2.0); `sha2`, `unicode-normalization` and `getrandom` were already in the lock. `?dev` has a **Link** panel (the real card in an island frame, fed by a stand-in service that never opens a socket) and `http://127.0.0.1:1420/settings.html?linkdev=on` (or `off`, `empty`, `problem`, `note`) draws Settings → Devices from the same stand-in. `windows/scripts/test-link-peers.sh` runs two real `link_peer` processes (`cargo run --example link_peer`, keys in memory, a terminal for an island) on loopback in the Linux container and checks the six digits, a file's SHA-256 and a declined file; run `link_peer` next to the Mac's Debug build to pair with it by mDNS. **Owed to the owner's real machines and CI:** the Windows Firewall prompt, the Windows Credential Manager, the Linux Secret Service, mDNS across a real network, the Downloads folder, the mark of the web, and the compile of the Windows-only Rust.

## What's different from the Mac version
""")
edit("windows/README.md", "nobody is at the desk.\n", """nobody is at the desk.
- The link keeps its keys in the Windows Credential Manager or the Linux Secret Service through the `keyring` crate, which cannot list items, so one item (`link.peers`) lists the paired machines; a store that cannot be read makes the link say why and stay off, and never makes a new key. A Debug build uses its own service name. Settings are in `link.json` (Visible and the name), written by Rust alone. A received file on Windows carries a `Zone.Identifier` stream (the Mac's quarantine attribute); if the drive cannot hold one (not NTFS) the file is refused, not saved unmarked. The advert and the listener are IPv4 only. "Devices is open" is the Devices section being visible in the single Settings page, reported by the page as a state and forced off by Rust when the Settings window hides. The Mac's Debug fake peer is the `?dev` Link panel and `link_peer` here.
""")

# ── CLAUDE.md ──
edit("CLAUDE.md", "- `docs/index.html`, `docs/testers.html`, `docs/site.css`", """- Sub-project G2 on Windows/Linux (between your machines): all of it is Rust under `windows/src-tauri/src/link/` (no Tauri type in that folder; `link_cmd.rs` is the one Tauri file). The pure rules are ports of `tests/fixtures/link/reference.py` replayed by `cargo test` (`name.rs` with hand-written Unicode tables, `frames.rs`, `pairing.rs` with the gate on incoming pairings, `flow.rs` with `place_step`, `connection_step` and `first_frame_expired`, `cards.rs` with `CardRules`, `RunGate`, `Busy`, `ConnectionCaps`, `ReadLimit`), `noise.rs` wraps the vetted `snow` crate (never a Noise or curve of our own) and is replayed against `noise-vectors.json`, `conformance.rs` plays the real pairing and handshake runs against those recorded conversations byte for byte, `channel.rs`/`pair_run.rs`/`transfer.rs` are the conversations over a `Transport` (`MemoryEnd` in tests, `net.rs` on TCP), `service.rs` is the one actor that owns every decision and emits a whole `Snapshot` (the `link` event), `mdns.rs` is the advert and browser on `mdns-sd` (the daemon exists only while something is announced or searched), `keystore.rs` keeps the keys in the OS credential store through `keyring` (not listable: a `link.peers` index item; a read that fails is `Unreadable`, never a new key; no file fallback), `files.rs` writes a received file (exclusive create, `Zone.Identifier` on Windows, never opened). **Nothing listens until Visible is on; an incoming pairing runs only while Devices is open or within 2 minutes after a Pair click here; only a click accepts an offer; one transfer per machine; the log holds fixed sentences only.** The page side is `windows/src/link/` (`LinkStore` holds the last snapshot and ids, never a key, an address or a path), `views/link.ts`, `views/shelfdevice.ts` (a new file: `views/shelf.ts` gained four lines), `island/link.ts`, `settings/devices.ts`, `link/link.css` (all `lk-`); `npm run check:link` runs the page checks and the pins, `windows/scripts/test-link-peers.sh` runs two real `link_peer` processes. New crates `snow` and `mdns-sd` were approved by the owner on 2026-10-14.
- `docs/index.html`, `docs/testers.html`, `docs/site.css`""")

# ── ARCHITECT.md ──
edit("ARCHITECT.md", "   - **Sub-project H on Windows/Linux:**", """   - **Sub-project G2 on Windows/Linux (between your machines):** `src-tauri/src/link/` is Tauri-free and replays `tests/fixtures/link/`; `link::service::Service` is an actor (one task owns all state, tasks of its own run each pairing, transfer and connection and report back by command) that emits a whole `Snapshot` as the `link` event, and `link_cmd.rs` is the only Tauri file (15 `link_*` commands; `link_send` takes shelf ids and `crate::shelf_store().resolve` finds the paths). Flow: `link_set_visible(true)` starts `net::Listener` (IPv4, a system port) and `mdns::Mdns` advertises; Settings → Devices or the shelf on screen (`link_devices_open`, `link_shelf_open`, states and not counters) starts the browser; a pairing (Noise XX, commit-then-reveal, six digits) or a transfer (Noise KK, offer, chunks) is a run over a `Transport`; an offer becomes the `link` island card (`island/link.ts` opens and holds the island, `transferOffer` calls the desktop cat). Keys live in the OS credential store (`keystore.rs`, `keyring`); a read that fails turns the link off with a sentence. `conformance.rs` and `windows/scripts/test-link-peers.sh` are the cross-checks with the Mac; the Mac's twin is `LinkService.swift`.
   - **Sub-project H on Windows/Linux:**""")

# ── docs/SPEC.md (French) ──
edit("docs/SPEC.md", "`LinkViews`, `LinkDevPeer`.\n", """`LinkViews`, `LinkDevPeer`.

**Windows et Linux (G2-tauri).** Même contrat, même comportement, tout en Rust (`windows/src-tauri/src/link/`) ; la page ne garde que le dernier état envoyé par Rust et des identifiants, jamais une clé, une adresse ou un chemin.

- **Clés** : dans le Gestionnaire d'identifiants Windows ou le Secret Service Linux (`keyring`), jamais dans un fichier. Si le Secret Service manque ou est verrouillé, le lien le dit (« Start or unlock it… ») et reste éteint : aucune clé n'est créée, rien n'est écrit sur le disque. Un build Debug garde ses clés sous son propre nom de service (`io.github.aikusan.notchmeow.debug`).
- **Visible sur ce réseau** : désactivé par défaut ; rien n'écoute et rien n'est annoncé avant. Windows demande une fois l'autorisation du pare-feu (à accorder sur les réseaux privés) ; Linux a besoin de l'UDP 5353 (mDNS) et des connexions entrantes. IPv4 seulement.
- **Appareils ouvert** : la section Appareils visible dans la page de Réglages (un état, pas un compteur) ; Rust le remet à « fermé » quand la fenêtre des Réglages se cache.
- **Réception** : `Downloads\\NotchMeow\\` (`~/Downloads/NotchMeow/`), jamais ouvert ; sous Windows le flux `Zone.Identifier` (`ZoneId=3`, la marque du web, l'équivalent de la quarantaine du Mac) ; si le disque ne peut pas le porter, le fichier est refusé. Linux n'a pas de marque.
- **Cartes de l'île** : code de jumelage, offre (seul le bouton Accept accepte, l'île s'ouvre et le chat de bureau vole vers le notch), réception, fin ; un clic sur une carte qui vient de changer (moins de 700 ms) ou qui a disparu ne fait rien.
- **Étagère** : « To a device » est un fichier à part (`views/shelfdevice.ts`) ; la vue de l'étagère n'a gagné que quatre lignes.
- **Vérifications** : `cargo test` rejoue les fixtures et les conversations enregistrées ; `npm run check:link` ; `windows/scripts/test-link-peers.sh` (deux processus `link_peer` sur 127.0.0.1) ; l'essai avec le Mac et avec un vrai PC est celui du propriétaire.
""")

# ── CI ──
edit(".github/workflows/windows-tests.yml", "      - 'tests/fixtures/shelf/**'\n", "      - 'tests/fixtures/shelf/**'\n      - 'tests/fixtures/link/**'\n")
edit(".github/workflows/windows-tests.yml", "      - name: Sidekick checks\n        run: npm run check:sidekick\n", "      - name: Sidekick checks\n        run: npm run check:sidekick\n      - name: Link checks\n        run: npm run check:link\n")
edit(".github/workflows/linux.yml", "      - 'tests/fixtures/ai/**'\n      - 'tests/fake_local_llm.py'\n", "      - 'tests/fixtures/ai/**'\n      - 'tests/fixtures/link/**'\n      - 'tests/fake_local_llm.py'\n")
PYEOF
python3 .claude/checkpoints/g2-tauri/docs_edit.py && echo "edits ok"
```

Expected: `edits ok`.

- [ ] **Step 2: Check the edits**

```bash
git diff --stat
python3 - <<'EOF'
import re, pathlib
for f in ["windows/README.md", "CLAUDE.md", "ARCHITECT.md", "docs/SPEC.md", ".github/workflows/windows-tests.yml", ".github/workflows/linux.yml"]:
    t = pathlib.Path(f).read_text(encoding="utf-8")
    assert "G2" in t or "link" in t, f
print("each file mentions the link")
EOF
grep -n "tests/fixtures/link" .github/workflows/windows-tests.yml .github/workflows/linux.yml
grep -n "check:link" .github/workflows/windows-tests.yml windows/package.json
```

Expected: six files in the diff stat, `each file mentions the link`, the two workflows list `tests/fixtures/link/**`, and `check:link` appears in `windows-tests.yml` and `package.json`.

- [ ] **Step 3: Every check, once, before the review**

```bash
bash scripts/test-link-contract.sh 2>&1 | tail -2
bash scripts/test-link-flow.sh 2>&1 | tail -1
node --test tests/cat/additive.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
for s in link cat sidekick; do npm run check:$s 2>&1 | grep -E "^ℹ (tests|pass|fail)"; done
npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1
cd ..
windows/scripts/cargo-linux.sh test --target-dir /repo/windows/target/g2-tauri --workspace 2>&1 | grep -E "test result|FAILED|panicked"
windows/scripts/cargo-linux.sh check --target-dir /repo/windows/target/g2-tauri -p notchmeow --all-targets 2>&1 | grep -cE "^warning" 
bash scripts/check-site.sh 2>&1 | tail -1
```

Expected: the contract and the flow test pass, `# fail 0`, `tsc exit 0`, every node run `ℹ fail 0` (the counts equal the baseline of Setup plus this plan's 33 for `check:link`), `All AI UI checks passed`, `All Claude Code UI checks passed`, every Rust `test result: ok` (the sum is the baseline plus this plan's tests; write it down) and `0` warnings, and `check-site.sh` passes (the site bundle did not change: this plan touches no cat code). Write every number in the ledger.

- [ ] **Step 4: Commit**

```bash
git rev-parse --show-toplevel; git branch --show-current
git add windows/README.md CLAUDE.md ARCHITECT.md docs/SPEC.md .github/workflows/windows-tests.yml .github/workflows/linux.yml
git commit -F - <<'MSG'
docs(link): G2-tauri in the README, CLAUDE.md, ARCHITECT.md and the spec; CI paths and the link checks (G2-tauri)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
MSG
git log --oneline -1
```

Write the task's line in the ledger. Then the controller runs the whole-branch review (next section).

---

## After Task 15: the whole-branch review

`nm-reviewer-deep` (Sonnet 5.5, high; trigger 4: a security and privacy review). Brief: the merge-base diff of the branch (`git diff $(git merge-base HEAD <the branch's base>)..HEAD`), `docs/LINK-CONTRACT.md`, `docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md`, this plan's Global Constraints and Review Focus, and the Mac's `LinkService.swift` and `LinkTransferRun.swift` for what the Mac learned. Ask it to check, with file and line for each finding: (1) that nothing is reachable before Visible is on and nothing is accepted without a click; (2) that no key, name, address, id, path or file name reaches a log, a panic message, a `Debug` print, the page, a file or the network beyond the contract; (3) that every wait ends (no unbounded await, no timer that outlives its phase, no task that survives Visible off); (4) that `noise.rs` refuses what the contract says and nothing in the link uses a second crypto stack; (5) that `files.rs` cannot be made to write outside `Downloads/NotchMeow/`, follow a link or leave a partial file; (6) the lock order and the `.await` points in `service.rs` (no lock held across an await); (7) that the page never learns more than it should, and that no shipped view's look changed (`git diff` of `views/*.ts` and `style.css`). Findings go to the controller, who fixes by `nm-implementer-deep` and has the fix re-reviewed.

---


### Task 16: Checkpoint 2: the pictures, then the real-machine checklist (with the Mac)

No code and no commit. The executing session stops here and reports to the main session (with `SendMessage`); the main session sends the owner the pictures and the checklist. **No agent launches the real app, and no agent runs anything on the owner's machines.** The agent's part is the pictures from the dev server and the commands that run in the container; the owner's part is below.

- [ ] **Step 1: The pictures again, from the final tree**

Start the dev server (port 14641), run `cards.js` (Task 9) and `devices.js` (Task 10) again, plus the shelf's button with and without chips, into `.claude/checkpoints/g2-tauri/`, and stop the server. Say in the report which pictures changed since Checkpoint 1 and why.

- [ ] **Step 2: Report**

The commits (one per task and the review's fix commits); every test line of Task 15, Step 3; the whole-branch review's findings and what was fixed; the paths of the PNGs; the result of `bash windows/scripts/test-link-peers.sh`; the recorded conversations' result (`link::conformance`: 4 passed); what `mdns.rs` needed changed (Task 12); and anything that could not be settled (the Windows-only Rust and the real credential store were not compiled or run: say so).

- [ ] **Step 3: The owner's real-machine checklist**

Build with `cd windows && npm install && npm run tauri dev` (or a tester build) on **a Windows PC**, and, for the Linux lines, on a Linux desktop. The Mac side is the Mac's Debug build or tester build of the same period (`G2-mac`, merged). Items 1 to 3 need only this PC; 4 onward need the Mac or a second PC. In order:

1. **Nothing until you ask.** Fresh start (no `link.json`): Settings → Devices shows **Visible on this network off**. In Resource Monitor (Network → Listening Ports) or `ss -ltnup | grep notchmeow` nothing of NotchMeow listens besides what it already did before this version, and **Windows Defender Firewall has not asked anything**. Quit and reopen: still off. With Settings open on Devices and Visible off, still nothing listens (the machines are only looked for when Visible is on).
2. **Turning it on.** Switch it on: on Windows the firewall prompt appears **once**; allow it on private networks. The line says "Listening on your network." and the list fills with the machines on the network (the Mac, if it is Visible). Switch it off: the listener goes (the same tools), the Mac's list drops this PC within a few seconds.
3. **The credential store.** On Windows: Control Panel → Credential Manager → Windows Credentials shows `link.static-key`, `link.device-id` (and one `link.peers` and one `link.peer.<id>` after pairing) under `io.github.aikusan.notchmeow` (or `...notchmeow.debug` for a Debug run), and **no file of the link under `%LOCALAPPDATA%\NotchMeow\` holds a key** (only `link.json`: Visible and the name). On Linux **with no Secret Service running** (stop GNOME Keyring or start in a bare session): Settings → Devices says the key could not be read and why, Visible does nothing, **no new file appears** in `~/.local/share/notchmeow/` or `~/.config/notchmeow/`, and starting the keyring and reopening Settings makes it work.
4. **Pair with the Mac.** On the Mac: Settings → Devices open, Visible on. On this PC: Visible on, the Mac shows as Available; **Pair**: the Mac shows "Pair with `<this PC's name>`?" **only because its Devices is open** (close the Mac's Settings, wait 2 minutes since its last Pair click, press Pair on the PC again: nothing appears on the Mac and the PC says the connection ended; this is the gate). With it open, both screens show **the same six digits**; click **They match** on both: both say Paired and list each other. Try again with **No** on one side (wait 30 s between tries: "Wait 30 seconds before trying again." must show if you do not).
5. **A file from the Mac, and one to it.** Mac → PC: the island opens **even if it was hidden**, the card names the file and its size, **nothing is written until Accept**; Accept; progress; "Received" with **Show in folder** (Explorer opens with the file selected). The file is in `Downloads\NotchMeow\`; **Windows asks "Do you want to open this file?" when you open a `.exe` or a `.docx` from it** (the mark of the web), and in PowerShell `Get-Content -Path .\file -Stream Zone.Identifier` prints `ZoneId=3`. Send the same name again: `name (1).ext`. PC → Mac: tick a file on the shelf, press the laptop button, pick the Mac; the Mac shows its Accept card; the shelf head says it is waiting, then sending, then "Finished sending"; **compare the SHA-256** of both copies (`Get-FileHash` / `shasum -a 256`). Do both with a file larger than 100 MB.
6. **The alert, the idle timer, the expiry.** With the desktop cat out, send a file from the Mac: the cat flies to the notch and waits; decline: it goes home. Send one and do nothing: while the card is up the island does not fold, and after 2 minutes the card says the offer expired and nothing is saved. Send while the PC's island is hidden or the PC is in another app: the island still opens.
7. **Cancel, refuse, two at once.** Accept a 200 MB file and click Cancel: "Transfer cancelled", the partial file is gone, and the Mac's side says so. Send two files at once from the Mac: one card at a time. From the Mac, offer a file with a path in its name (the Mac's Debug fake peer has one): declined as not acceptable, nothing saved.
8. **The network drops.** Turn this PC's Wi-Fi off in the middle of a transfer: both sides end ("Transfer stopped"), nothing partial remains. Turn it back on: the machines see each other again without restarting anything.
9. **The Linux notes.** On Linux: the received file is in `~/Downloads/NotchMeow/` (or the folder `xdg-user-dir DOWNLOAD` names), `ls -l` shows `-rw-r--r--`, Show in folder opens the file manager, and **with the firewall on and UDP 5353 closed** the list stays empty and Settings → Devices says what to check (the help line).
10. **The firewall prompt cancelled** (Windows: reset the rule first, `netsh advfirewall firewall delete rule name=all program="<path to the exe>"`, then **Cancel** the prompt): the PC listens but the Mac cannot reach it; Devices still says "Listening on your network." and the help line says what to check; nothing crashes; allowing it later in Windows Defender Firewall makes it work without a restart.
11. **CPU and the process.** With the link on and the island hidden, Task Manager shows NotchMeow at 0 % idle; with Visible **off** there is **no** extra thread or socket from the link (`Get-NetUDPEndpoint -OwningProcess <pid>` lists no 5353). Quit from the tray: the listener is gone at once.
12. **`link_peer` against the Mac.** On the PC (or in WSL/another Linux box) run `cargo run --example link_peer -- "Test peer"`, type `visible`: the Mac's list shows "Test peer"; pair from the Mac and say `yes`; send a file from the Mac and say `accept`: the file arrives; `send <path> 0` sends one to the Mac. This is the real Rust protocol against the Mac's code with nothing of the app's page in between.
13. **Forget.** Forget the Mac in Devices (the Forget button): the machine goes back to Available; check Credential Manager no longer has `link.peer.<its id>`. A waiting offer from that Mac is declined at once.

Write the answers in the report: each line passes, fails, or needs a change. **A line that fails is a finding, not a flake**: report it with what was on screen.

- [ ] **Step 4: After the owner's answers**

Fixes are made by `nm-implementer-deep` (a failure whose cause is unknown is trigger 2) with a regression test where a test can see it, re-reviewed by `nm-reviewer`, and the whole-branch review is repeated only if a fix touched `service.rs`, `noise.rs`, `files.rs` or `keystore.rs`. The owner merges; **nothing is pushed by the plan**.

---


## Questions for the owner

Five, each with the default this plan is built on (the plan runs as written unless the owner says otherwise before Task 2).

1. **The dependencies.** `snow` 0.9 and `mdns-sd` 0.11 were approved on 2026-10-14. Task 2 also names three crates directly that are **already in `Cargo.lock`** through other crates (`sha2`, `unicode-normalization`, `getrandom`) and downloads the two new ones from crates.io (the plan's one network use, in the container, once). Default: yes, nothing else is added; `keyring` was already a dependency and is used as it is.
2. **When to run it relative to U1b.** G2-tauri and U1b (`2026-10-16-u1b-windows-island-parity.md`) edit the same files (`lib.rs`, `island.ts`, `state.ts`, `main.ts`, `desktop.ts`, `style.css`); neither may run beside the other. Default: **U1b first** (it is the shorter and changes how the island is laid out, which the link card sits in), then this plan from the merged tree; the Setup pre-flight finds a base that moved.
3. **A drive that cannot hold the mark of the web.** On Windows a received file gets a `Zone.Identifier` stream; on a non-NTFS Downloads folder (FAT, a network share) it cannot. Default: **fail closed** (the transfer ends as "Could not save" and no unmarked file is left), as the Mac's quarantine is never skipped. The alternative is to save it unmarked with a note.
4. **IPv4 only, and no keyring means no link.** The listener and the advert are IPv4 (IPv6 is switched off in the mDNS daemon), as a first version; and on Linux without a Secret Service the link stays off with a sentence and **never** falls back to a key file. Default: both as written.
5. **What "Devices is open" means here.** The Mac's is the Devices pane being on screen. The PC's Settings is one scrolling page, so it is the **Devices section being visible** in that page (an `IntersectionObserver`), reported as a state and forced off by Rust when the Settings window hides. Default: as written; the consequence is that an incoming pairing is accepted while the Settings window is open and Devices is scrolled into view, and for 2 minutes after a Pair click here.

## What is different from the Mac, and what in the Mac's code contradicts the contract

Nothing in the Mac's merged code contradicts `docs/LINK-CONTRACT.md`. Notes for whoever reads both:

- The Mac keeps the "one machine-made decline per connection" count and the 10 s first-frame watch **inline** in `LinkTransferReceive.run`, not as pure functions, so the contract's `connections[]` and `firstFrame[]` rows can only be replayed against a test-side model there (Task 1 adds that replay, with a model); `places[]` replays through the real `LinkBusy`. In this plan the Rust runs call `flow::connection_step` directly, so all three are replayed through the rule the runs use.
- `unique_name`'s case folding is `to_lowercase` in Rust and Foundation's `folding(options: .caseInsensitive)` on the Mac: they differ for `ß` (the contract lists case folding as a known limit and has no fixture row for it).
- A fixture base from before G2-0b (`6adc5a4`) words one frame case differently ("busy: one transfer per peer"); the additive check (Task 1) skips such a base.

## Dry run

Before this plan was handed over its code was run, in a scratch copy of the crate and of `windows/` outside the repository (nothing was committed, no branch was made, no file of the repository was edited, the app was never launched, no machine was contacted):

- **Rust, 130 tests.** The pure rules and everything above them (`bytes`, `name`, `frames`, `pairing`, `flow`, `cards`, `identity`, `keystore`, `settings`, `directory`, `files`, `channel`, `pair_run`, `transfer`, `net`, `service`) were compiled and run offline against `tests/fixtures/link/` with a **stand-in Noise** (the real `snow` was not in the offline cache): the 162 name cases, every frame case, the 74 machine rows and the whole pairings, the 50 + 16 flow rows, `places[]`, `connections[]` and `firstFrame[]`, `Busy`'s trips, the caps, the paused-time watches, real TCP on loopback, and two whole services pairing and sending a file over real sockets with in-memory stores. Each "prove it bites" line of Tasks 4 to 13 was run and fails as stated; two of them **did not fail the first time** (the default watches and the listener numbers were not pinned), and two tests were added (`the_default_watches_are_the_macs_and_the_reviews_numbers`, `four_frames_may_wait_for_the_conversation`, `the_listener_numbers_are_the_macs_and_the_reviews_numbers`).
- **Two processes.** `link_peer` was built and two of them paired over loopback and moved a file with `link-peers.sh` (the stand-in Noise, so this proves the service and the files, not the cryptography); a deliberately damaged receive was caught.
- **The page.** `tsc --noEmit` passes with every file of Tasks 8 to 10 and every additive edit applied to a copy of `windows/`; `npm run check:link` passes (33 tests: model 10, alert 3, wiring 9, Rust wiring 11). The dev server was started on the copy and the Link panel and Settings → Devices were looked at in headless Chromium: the cards (code, offer, receiving, results) and the Devices section in its states drew as described in Tasks 9 and 10. **Found and fixed by looking:** the offer card's explanation wrapped to two lines and pushed its title out of the card (shortened to one line).
- **Swift.** The Task 1 replay was written against `tests/LinkFlowTests.swift` and run in a scratch copy of the test harness (the three new sections pass; the additive check script fails on a changed base row and passes on an addition).
- **Not run, and why it matters.** (a) Everything that needs the real **`snow`**: `noise.rs`, its vector replay, `conformance.rs` (compiled against the stand-in, not run on real bytes) and every conversation test with the real cipher: Task 2 and Task 11 are the first time they run, and a failure there is a real finding. (b) **`mdns.rs`** (`mdns-sd`'s API was written from its documentation; Task 12 checks it against the crate's source). (c) **`keyring`'s `SystemStore`**, `link_cmd.rs`, the `lib.rs` edits and Tauri's compile (container only). (d) **All Windows-only Rust** (`SHGetKnownFolderPath`, `Zone.Identifier`, `GetTickCount64`, the keyring Windows backend): read, never compiled, and owed to CI. (e) The Windows Firewall, a real network, the Mac, a real credential store and the Downloads folder: the owner's Task 16. The plan never claims (a) to (e) as passed.

## Owner's answers (2026-10-16)

Runs after U1b merges. **The crates download needs the owner's own approval at that step:** the session stops before Task 2's download and reports each crate's name, version, source (crates.io) and size; the main session asks the owner and passes the answer back. The plan's other defaults stand: fail closed on a non-NTFS Downloads folder, IPv4 only, no Secret Service means the link stays off with a sentence and no file fallback, and "Devices open" is the Devices section visible in Settings.
