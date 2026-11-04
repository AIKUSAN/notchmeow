# Sub-project G: file shelf and transfer

**Status:** Revision 2 written 2026-10-14 for the owner's review; design first approved in chat 2026-10-04.
**Parent spec:** `docs/superpowers/specs/2026-10-03-notchmeow-design.md`, sub-project G.

The owner asked for file transfer in four senses. Two of them belong to other sub-projects:
- **Files to the AI:** sub-project E1, built.
- **Files to your agents** (drop a file on a cat to hand it to that cat's agent): sub-project F1. F1 will add its meaning to the Ask half, not a third half.

G covers the other two:
- **G1, shelf and send:** park files in the notch, drag them out later, and send them to a phone or another device.
- **G2, between your machines:** move files between a Mac and a Windows/Linux PC that both run NotchMeow, over the local network.

## Revision 2026-10-14

The spec was approved before sub-projects A, B and H, the wing fix and E3 were built. This revision keeps every decision the owner made. It changes how they are built so they fit the code as it is now. Items marked **[New]** are added by this revision. The six open questions were answered by the owner on 2026-10-14; the answers are below and are folded into the text.

What changed:
- **The drop view is a shipping canvas now.** The two halves are kept (approved), but built as an additive layer. The Ask half is today's canvas, unchanged. A render check proves it.
- **[New] How the shelf opens.** The spec never said. Entry points are listed under "The shelf view".
- **[New] The compact badge** can only show while the island is already compact. It never wakes a hidden island. It sits at the end of the right wing and fades with it.
- **[New] The desktop cat.** A Shelf drop does not wait for the desktop cat and clears the file alert. An incoming transfer offer is an alert to the desktop cat (one new additive flag in the contract).
- **[New] Dragging out** needs a hold-open rule and a self-drop guard on the Mac, and a native drag source on Windows and Linux (spike first, with a stated fallback).
- **Mac drop types.** Promised files and browser images are accepted, but only over Shelf. Ask accepts exactly what it accepts today.
- **Many files.** Shelf takes several; Ask still takes one. A full shelf refuses extra items instead of dropping old ones.
- **G2 build facts.** App Store entitlements and Info.plist changes are listed, including the Downloads entitlement the first spec missed. The mDNS crate is named. Secrets allowlist and quarantine/mark-of-the-web are added.
- **"Visible on this network" is off by default** (the first spec had it on).
- **Plans and order** are rewritten. G1 and G2 are separate rounds, each with its own contract plan.

Answered by the owner on 2026-10-14 (every question took the recommended option):

| # | Question | Answer |
|---|---|---|
| 1 | How the shelf opens, and where the badge sits | A drop on the Shelf half, a menu-bar item (tray item on Windows/Linux) and a click on the badge. The badge is one more cell at the right end of the wing, shown only while the island is already compact, and it fades with the wing. An optional `shelf` shortcut, off by default. |
| 2 | "Visible on this network" | Off until the user turns it on in Settings → Devices. |
| 3 | Drag-out on Windows and Linux | A spike first (a native drag source: Windows OLE, Linux GTK `text/uri-list`). If Linux fails, Linux ships without drag-out and keeps Ask, Send and Show in folder. |
| 4 | New third-party code for G2 | `snow` and `mdns-sd` are approved for Windows/Linux. The Mac adds nothing. |
| 5 | Received files in the App Store build | `~/Downloads/NotchMeow/`, with the `files.downloads.read-write` entitlement. |
| 6 | How the rounds are cut | G1 (shelf and send) first with its own small contract plan, then G2 with its own contract and a security review. |

## Decisions

| Topic | Decision |
|---|---|
| Drop choice | **Two drop zones.** While files are dragged over the notch, it opens into **Ask** (left: the cat catches the file, as today) and **Shelf** (right: a tray). The Ask half is today's canvas, unchanged. |
| Shelf storage | **Links, with copies only when needed.** A secure bookmark (macOS) or a path (Windows/Linux) points to the original. Files with no original are copied. The shelf survives restarts. |
| G2 trust | **Pair once, accept each time.** The receiver clicks Accept on every transfer. Keys live in the Keychain or Credential Manager. |
| Pairing check | **Matching codes.** Both screens show the same 6-digit code, derived from both nonces and both static keys by a commit-then-reveal (the short-authenticated-string pattern), and the user clicks **They match** on both. The code is limited to one pairing attempt every 30 seconds and a 2-minute window. A typed code was rejected: without a password-authenticated key exchange, which the Mac can't get without a dependency, an eavesdropper could brute-force it offline. A man in the middle gets one guess per attempt. |
| G2 connection | **A shared contract, then a Noise-based encrypted channel in both apps.** Bonjour discovery. macOS builds on CryptoKit, with no new dependency. Windows/Linux uses the `snow` crate and the `mdns-sd` crate (both approved by the owner on 2026-10-14). |
| Rounds **[New]** | **G1 and G2 are separate rounds.** G1 (shelf and send) ships first. G2 (between your machines) follows with its own contract, plans and security review. |
| How the shelf opens **[New]** | A drop on the Shelf half, a menu-bar or tray item, a click on the badge, and an optional `shelf` shortcut (off by default). |
| Visible on this network **[New]** | **Off until the user turns it on** in Settings → Devices. |
| Drag-out on Windows and Linux **[New]** | **Spike first.** If Linux fails, Linux ships without drag-out. |
| Received files, App Store build **[New]** | `~/Downloads/NotchMeow/`, with the `files.downloads.read-write` entitlement. |

## Rules that apply (from `CLAUDE.md`) **[New]**

- Never restyle what ships. Every change to an existing view is listed here, and each is additive.
- macOS is primary: the Mac gets at least what Windows/Linux gets, including dev tools (a Debug fake peer and a Debug shelf panel).
- No telemetry. The log says only that a send started, never names or recipients.
- Secrets live in the Keychain or Credential Manager, never on disk.
- No new third-party code unless unavoidable. The new ones: `snow` and `mdns-sd` (Windows/Linux only).
- 0 % CPU when the island is hidden. Nothing here adds a timer or a poll.
- The App Store build is sandboxed. The GitHub build is not. Both build the same code; `scripts/check-app-binary.sh` proves what each contains.

## G1. Shelf and send

### Dropping
- Dragging files over the notch opens it into two halves, split at the island's centre line. Releasing over **Ask** behaves exactly as today's drop (first file only, the cat catches it, the desktop cat waits its turn).
- Releasing over **Shelf** adds all the files to the shelf, with no wait and no catch. The cat looks at the tray because it already follows the pointer. **[New]** It plays no new motion.
- **The half is decided by the pointer's position at release.** On the Mac that is the drag's own location. On Windows and Linux it is the last polled cursor position, because the drop event carries paths only. One pure rule, `zoneAt`, is in the shared contract.
- **What the Shelf accepts [New]:**
  - macOS: file URLs, promised files (Mail, Photos, screenshot thumbnails) and images from a browser. Over **Ask**, the same drags are refused, as today.
  - Windows and Linux: paths only. Nothing without an original can arrive, so the copy rule is Mac-only in practice.
  - Folders are accepted as links. Ask and Send to a machine refuse them. The share sheet and Show in folder accept them.
- **After a Shelf drop [New]:** the drop takes a fresh drop token, clears the file-drag alert and stops the upload sequence. The desktop cat, if it was flying in, goes back by its normal rule. The island shows the Shelf view.
- **Full shelf [New]:** items past 30 are refused with a short note. Nothing old is removed silently. The one exception, approved by the owner, is on the read side: reading `shelf.json` keeps the 30 newest items (see `docs/SHELF-CONTRACT.md`).

### The shelf view
A new island view (`.shelf`), in the existing style. No existing view changes.
- **Each item:** a thumbnail or file icon, the name and the size.
- **Actions per item:**
  - drag out to anywhere (Finder, Mail, chats, terminals);
  - **Ask**, which hands the file to the chat the way a drop on Ask does (it flies to the cat's mouth and resets the conversation, as a drop does). One item at a time, no folders. The button's hint says that it starts a new chat;
  - **Send**;
  - **Show in Finder** or **Show in Explorer**;
  - **Remove**.
- **Clear all** empties the shelf.
- **Multi-select** lets several items be sent at once. Ask is off while several are selected.
- **Cap:** at most 30 items, newest first.
- **Compact badge [New]:** a small count while the shelf isn't empty.
  - It shows only while the island is already compact. The shelf never keeps an island visible and never wakes a hidden one.
  - It is one more cell at the right end of the wing. It fades with the wing when the pointer is over it, and it does not touch Two cats or the kitten layouts.
- **How the shelf opens [New]:**
  1. a drop on the Shelf half;
  2. a menu-bar item on the Mac and a tray item on Windows/Linux;
  3. clicking the badge;
  4. an optional global shortcut `shelf` (a new frozen action ID, off by default; the Mac only, as for every shortcut). It goes through `ShortcutLogic.swift` like the others.

  `.shelf` is added to `IslandView` with its `viewLayouts` entry and to every exhaustive switch.
- **Dragging out [New]:**
  - macOS: while an item is being dragged, the island stays open and the panel keeps taking the mouse. The drop view ignores a drag that started inside the app, so an item dragged out and back in is not added twice.
  - Windows: a native drag source in Rust (an OLE data object with the file), started from the tile. Tauri's drag-and-drop setting turns the page's own drag off, so the page cannot do it. The spike is the first task of the Windows/Linux plan, before any shelf UI depends on it.
  - Linux: a GTK drag source with `text/uri-list`. Same spike. **If it fails on Linux, Linux ships without drag-out** (Mac and Windows only), and keeps Ask, Send and Show in folder.

### Storage
- **macOS:** a security-scoped bookmark per item, so it works in the App Store sandbox (the GitHub build is not sandboxed and uses plain bookmarks through the same code). Items with no original are copied into `Application Support/NotchMeow/shelf/<id>/`: promised files, browser images and screenshot thumbnails.
- **Windows/Linux:** the plain path, with the same copy rule into the app data folder.
- **The shelf is never the inbox [New].** The Ask copy still goes to `inbox`, which overwrites by name, and on Windows is swept after a week. Shelf copies live in `shelf/`, in a folder per item, so neither touches them.
- **The list** is kept in `shelf.json` in the app's support folder. Reading it goes through one clean-up rule in the shared contract (hostile files, duplicates, the cap, unknown fields), as for the Cat settings.
- **Missing originals:** an item whose original has moved or been deleted shows as missing, with Remove.
- **Removing** an item deletes its copy, if any. Originals are never touched.
- **When checks run:** whether files still exist is checked only when the shelf opens. Nothing runs in the background.

### Send

| Platform | Send |
|---|---|
| macOS | The standard share picker (`NSSharingServicePicker`) plus a one-click **AirDrop** button (`NSSharingService(named: .sendViaAirDrop)`). The island stays open while the picker is showing. |
| Windows | The system Share window (`DataTransferManager` via `IDataTransferManagerInterop::ShowShareUIForWindow`). Needs two `windows` crate features, no new crate. |
| Linux | **Show in folder**, because there is no system share |
| All, once G2 exists | Paired NotchMeow machines that are online come first in the Send menu. A shelf item can also be dragged onto a machine's chip. |

**Rules:**
- Sending always starts with a user click.
- The OS share sheet keeps recipients private from NotchMeow.
- The log records only that a send started, never names or recipients.
- Both the picker and the Share window need a short spike in the plan (the island is a non-key panel on the Mac and a click-through layered window on Windows).

## G2. Between your machines

### Discovery
- **Advertising.** Each running NotchMeow advertises `_notchmeow._tcp` over Bonjour/mDNS. The TXT record carries only a random device ID, a display name and the protocol version.
- **Who gets an answer.** Only paired keys get a session. Unpaired machines see the advert and nothing else.
- **Visibility.** Settings → Devices → Visible on this network (**default: off**). Until the user turns it on there is no listener, no advert of the machine's name and no local-network prompt. Once on, it stays on until turned off. While it is off, Send and Pair a machine show a one-line note with a switch to Devices. A machine must be visible to pair and to receive; browsing for others needs it on too.
- **Browsing** runs only while the Send menu or Settings → Devices is open.
- **Implementation [New]:** macOS uses `Network.framework` (`NWListener`, `NWBrowser`). Windows and Linux use the `mdns-sd` crate (pure Rust, no Avahi needed).

### Pairing
1. One machine starts it from Settings → Devices → Pair a machine. The other machine shows a "Pair with <name>?" card.
2. The two machines run **Noise_XX_25519_ChaChaPoly_SHA256** and exchange long-term static keys.
3. Both show the same 6-digit code, derived from the two nonces and the two static keys after the commit-then-reveal steps. The user confirms **They match** on both machines.
4. On confirmation, each machine stores the peer's static public key, device ID and name in the Keychain or Credential Manager (`link.static-key`, and one `link.peer.<id>` item per machine **[New]**). A mismatch or a "No" on either side stores nothing.
5. Settings → Devices lists paired machines, each with **Forget**.
6. **[New]** At most one pairing attempt every 30 seconds, and the pairing window closes after 2 minutes. The contract is 6 digits (the owner decided on 2026-10-14: a man in the middle gets one guess per attempt, about 1 in a million, so 8 digits are not needed).

### Transfer
1. The sender picks a paired, online machine. A **Noise_KK_25519_ChaChaPoly_SHA256** session opens with the stored keys.
2. The sender sends an **offer**: name, size and type, with no content.
3. The receiver shows a card: "<name> wants to send <file> (<size>)", with **Accept** and **Decline**. If unanswered for 2 minutes, the offer is declined automatically. **[New]** The card is an alert like an approval: it opens the island even when hidden, holds it open, and the desktop cat flies to the notch for it. Nothing accepts it except a click.
4. On accept, encrypted **chunks** stream with progress on both sides. Either side may cancel.
5. The file is saved to `Downloads/NotchMeow/`. A name collision becomes `name (1).ext`, and so on.

### Safety rules
- Only paired static keys open sessions. Every frame is authenticated, and a tampered, replayed or out-of-order frame aborts the transfer.
- **File names are sanitized.** No path separators, `..`, control characters or reserved Windows names (`CON`, `NUL` and so on). They are length-limited. The received byte count must equal the offer.
- Received files are never opened automatically. macOS sets the quarantine attribute (by hand in the GitHub build; the sandbox does it in the App Store build). **[New]** Windows writes the mark-of-the-web stream. Linux has no standard mark.
- **Limits:**
  - 4 GB per transfer;
  - one transfer at a time for the whole machine (`docs/LINK-CONTRACT.md`);
  - no automatic resume;
  - transfers end when the app quits.
- **App Store build:**
  - the `com.apple.security.network.server` entitlement;
  - **[New]** the `com.apple.security.files.downloads.read-write` entitlement, because a sandboxed app cannot reach `~/Downloads` without it. The owner chose this over a receive folder the user picks once;
  - `NSLocalNetworkUsageDescription`, **[New]** reworded because the key exists already for AI model servers (one text now covers both);
  - `NSBonjourServices` = `_notchmeow._tcp`.

  The first use triggers macOS's local-network prompt, and Windows may ask about its firewall. If these are declined, Settings → Devices explains how to re-enable them.
- **Performance:**
  - the listener waits on a socket, with no polling;
  - Bonjour browsing runs only while Send or Devices is open;
  - CPU is 0 % when the island is hidden.

## G1-0 and G2-0. The contracts **[New split]**

### G1-0. The shelf contract (`tests/fixtures/shelf/`)

| File | Pins |
|---|---|
| `shelf-cases.json` | The clean-up of `shelf.json` (`shelfClean`: unknown fields, hostile ids, names and links, duplicates, the 30-item cap, newest first) and the Shelf drop (`shelfAdd`: `added`, `duplicate`, `full` or `invalid` for each file; an overflow is refused, nothing old is removed) |
| `zone-cases.json` | `zoneAt(x, width)`: which half a pointer is in, the centre line, outside the island |
| `reference.py` | A Python standard-library reference for the three rules; it decides when an app and a fixture disagree |
| `build_cases.py` | Writes the two JSON files with the expected answers typed out by hand (`--check` fails on drift) |

### G2-0. The link contract (`tests/fixtures/link/`)

| File | Pins |
|---|---|
| `noise-vectors.json` | Test vectors for `Noise_XX_25519_ChaChaPoly_SHA256` and `Noise_KK_25519_ChaChaPoly_SHA256` in the published format (generated by the reference and cross-checked with CryptoKit; the published ones can be added as more entries), and damaged-message cases that must stop the conversation. The macOS CryptoKit implementation must pass every vector; the `snow` crate must pass them too in G2-tauri. |
| `pairing-cases.json` | The commit-then-reveal pairing (the owner's decision of 2026-10-14, so that a man in the middle gets one guess per attempt): the commitment to a nonce and a static key, the 6-digit code from both nonces and both static keys (defined here once; no 8-digit value), the initiator's and the responder's machines with the cause of every refusal, and the clocks (one attempt every 30 seconds, a window of 2 minutes, an offer unanswered for 2 minutes) |
| `frames.json` | Length-prefixed records, the first record, the hello, the advert's TXT record and the frame encoding for `offer`, `accept`, `decline`, `chunk`, `done` and `cancel`, plus malformed frames that must be rejected |
| `flow-cases.json` | What the receiver and the sender do with each frame: busy, too large, a replayed or skipped chunk, a short `done`, a cancel |
| `filename-cases.json` | Raw names (paths, `..`, control characters, reserved names, over-long names, emoji), then the sanitized name or a rejection |
| `reference.py` | A Python standard-library reference for every rule above, with its own X25519 and ChaCha20-Poly1305 (checked against the RFC vectors) so that it can replay the Noise vectors; it decides when an app and a fixture disagree |
| `build_cases.py` | Writes the JSON files with the expected answers typed out by hand (`--check` fails on drift) |

**[New]** G2-0 also adds the `transferOffer` flag to the desktop cat's alert rule in `cat-core.js` (`desktopAlert`), an additive change with `desktop-cases.json` regenerated by `node scripts/gen-cat-fixtures.mjs`.

## Checks
- **Contract:** both apps test against `tests/fixtures/shelf/` (G1) and `tests/fixtures/link/` (G2).
- **Cross-app (G2):** on one Mac, the Swift link code and the Rust link code (a module with no Tauri types, run as a small test binary) pair over loopback, then send files both ways, verified by SHA-256.
- **G1:**
  - the bookmark round trip;
  - missing originals;
  - copy cleanup on remove;
  - the 30-item cap and the refused overflow;
  - drop-zone hit testing on both platforms;
  - **[New]** the Ask half is unchanged (a render check);
  - **[New]** a Shelf drop with the desktop cat out: no wait, the cat goes home;
  - **[New]** an item dragged out and back is not added twice;
  - **[New]** the badge never wakes a hidden island;
  - the Send entry points on each platform;
  - wiring tests that pin the call sites in the app files no test program can compile, as for H.
- **Security:** the G2 final review includes a dedicated security pass over the Noise implementation, the frame parser, the file-name sanitizer and the pairing code's strength. The G1 final review includes the bookmark and copy handling.
- **Debug tools [New]:** a Debug-only shelf panel and a fake peer on loopback on the Mac, compiled out of Release and App Store (a marker in `check-app-binary.sh`). Windows gets the `?dev` equivalent.
- **Owner's manual checks:**
  - drag in and out of the shelf;
  - drop on Ask and on Shelf with the desktop cat out;
  - AirDrop to a phone;
  - pair the Mac and a PC, then send both ways;
  - Decline, Cancel and the size limit;
  - the permission prompts.

## Rounds

Two rounds, G1 then G2, as the owner chose on 2026-10-14. Each round has a small contract plan first, shared by both apps, then a Mac plan and a Windows/Linux plan in parallel worktrees (the way H ran).

- **G1, shelf and send.** Useful on its own, and it touches the shipping drop path, so it lands and settles first.
- **G2, between your machines.** A different risk class: a network listener, new crypto, new dependencies, new entitlements. It has its own contract and a security review. It needs G1's shelf and Send menu, so it comes second.

| Round | Plan | Content |
|---|---|---|
| G1 | **G1-0 shelf contract** (4 tasks) | `tests/fixtures/shelf/` (`shelf-cases.json`, `zone-cases.json`), `reference.py` and its test, `docs/SHELF-CONTRACT.md` and the CI hook, final checks. |
| G1 | **G1-mac** (about 13 tasks) | Rules and storage; `FileDropNSView` (more types, location, self-drag guard); drop zones and the Shelf drop path; the Shelf half and the "Ask unchanged" render check; `.shelf` view and entry points (owner checkpoint 1); drag out; Ask; Send (picker spike, AirDrop); badge; Debug shelf panel and wiring tests; docs and CI; owner checkpoint 2. |
| G1 | **G1-tauri** (about 12 tasks) | **Task 1 is the drag-out spike: Windows OLE, then Linux GTK, with the stated Linux fallback.** Then the TS and Rust rules; zones from the cursor poll and the Shelf drop path; the Shelf half and check; the shelf view, tray item and `?dev` panel (owner checkpoint 1); Ask; Send (Windows Share, Show in folder); badge; docs and CI; owner checkpoint 2. |
| G2 | **G2-0 link contract** (about 8 tasks) | `tests/fixtures/link/`, `reference.py`, the `transferOffer` alert flag in `cat-core.js`, docs. |
| G2 | **G2-mac** (about 14 tasks) | Noise on CryptoKit, frames and sanitizer, `LinkKeychain`, discovery, pairing and Settings → Devices, the Accept card, streaming, entitlements and Info.plist, Send-menu integration, Debug fake peer, cross-app check. |
| G2 | **G2-tauri** (about 13 tasks) | `snow` and `mdns-sd`, frames and sanitizer, secrets allowlist, discovery, pairing and Settings → Devices, the Accept card, streaming, mark-of-the-web, Send-menu integration, `?dev` fake peer. |

Models follow `CLAUDE.md`: contract plans on Haiku 5.5 (medium); app plans with platform APIs on a Sonnet 5.5 controller, with pure-rule tasks on Haiku 5.5 (high); whole-branch and security reviews on Sonnet 5.5.

## Plans and order

| Plan | When | Stages |
|---|---|---|
| G1-0 shelf contract | First. Touches only `tests/fixtures/shelf/` and the docs. | fixtures, reference, docs |
| G1-mac, G1-tauri | After G1-0, in parallel worktree sessions. They land on the drop path as it is after `fixes/after-h`, and coordinate on `FileDropView.swift`, `UploadCanvasView.swift`, `DesktopCatController.swift`, `IslandWindowController.swift`, `windows/src/island/island.ts` and `windows/src/upload/*`. | Mac: 1. rules and storage; 2. drop zones and the Shelf half; 3. the shelf view and its entry points; 4. drag out; 5. Ask and Send; 6. badge, tray and polish. Windows/Linux: the same, with the drag-out spike first. |
| G2-0 link contract | After G1 ships. It touches only fixtures, `cat-core.js` and the docs. | vectors, cases, reference, the alert flag |
| G2-mac, G2-tauri | After G2-0, in parallel worktree sessions | 1. discovery; 2. pairing and Settings → Devices; 3. transfer and the Accept card; 4. Send-menu integration with G1; 5. cross-app check (last, needs both apps) |

Whole-branch review of each app plan: Sonnet 5.5, including the bookmark and copy handling in G1 and a dedicated security pass in G2.

## Risks
- **Hand-written Noise on macOS.** Subtle crypto bugs are possible. Mitigated by the official vectors, the cross-app test and the security review pass.
- **Local-network permissions.** A user who declines the macOS or Windows prompt sees guidance in Settings → Devices.
- **Networks that block mDNS** (corporate or guest Wi-Fi). Devices shows "no machines found". There is no relay or workaround, by design.
- **The shared drop path** (`FileDropView`, `UploadCanvasView`, the desktop cat's catch and the wing). The Ask half must not change. Mitigated by the render check, the wiring tests and a Shelf-drop test with the desktop cat out.
- **Drag-out on Windows and Linux.** No supported way from the page. A spike decides; if Linux fails, Linux ships without drag-out.
- **Share sheet from a non-key panel or a click-through window.** A spike decides, with the AirDrop button and Show in folder as fallbacks.
- **New dependencies** (`snow`, `mdns-sd`, approved) and a Windows firewall prompt for an unsigned binary. The note goes in the Windows QA brief and in Settings → Devices help.

## Done means
- Files can be shelved, dragged out (Mac and Windows; Linux if the spike passes), asked about and sent on all three platforms, with Show in folder on Linux.
- A Mac and a PC pair with matching codes and exchange files both ways after an explicit Accept.
- Every contract test and the cross-app test pass.
- The Ask half is unchanged, and the desktop cat behaves with both drop zones.
- CPU is 0 % when hidden.
- The owner signs off on the manual checks.
