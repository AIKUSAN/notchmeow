# Changelog

## 1.0.0 (relaunch) — 2026-11-13

Mac: open the `.dmg` disk image, drag NotchMeow to Applications, then open it. macOS refuses it once, because it isn't notarized: open System Settings → Privacy & Security, click **Open Anyway** next to the NotchMeow message and confirm.

- Projects: the island groups your Claude Code sessions by project, with a pill and a cat for each, and shows how many are waiting on you.
- One chat: a rebuilt chat in the island and in a window of its own, with your conversations kept on this computer and a Companion tab in Settings. Quick actions (Fix, Rewrite, Explain) run with every tool off.
- Settings in six pages: General, Agents, AI and chat, Services, Cat and Devices. On Windows and Linux, Settings follows the system's light or dark mode.
- Focus awareness: a request from the app you are already in stays in that app, with an amber dot on the pill and no card over your work (Mac and Windows; Linux under X11 only).
- On the Mac, the music pill follows Spotify as well as Apple Music (GitHub build).
- Saved keys: on the Mac, a save now writes in place, so a failed save can no longer lose a key from the Keychain.
- The compact island no longer vanishes on its own a minute after the pointer leaves while a task runs. It stays up by default (Settings → General → Behavior → Tuck the island away: Never, or after 1, 5, 15 or 30 minutes with no agent working, waiting or open, and no hook event or alert in that time). Mac, Windows and Linux.
- Claude Code chats from the Claude desktop app now show under the Claude Code pill (their permission prompts stay in the Claude app).
- The hover glow stops at the island's top edge (the screen's edge) instead of running across the top.
- Settings → Agents: after Install hooks → Confirm & write, the result now shows right under the buttons (✓ with the backup's file name, or the error in red) instead of only in the small bar at the window's bottom. NotchMeow also refuses to touch a `~/.claude/settings.json` it cannot read as JSON (it used to rebuild it from nothing and keep your other settings only in the backup), and a failed backup now stops the write.
- Settings → Agents → Plan usage: Install relay now turns "Show in the notch" on once confirmed, the switch no longer looks on before anything is installed, and a line under the buttons says what the relay has heard ("Waiting for Claude Code…" or "Last update 14:02: 5-hour 43 %, weekly 10 %").
- On the Mac, "Use my OpenAI plan" runs your own Codex for chats, at Chat only, with the shell, browser, apps and web search off.
- The site and the README show how the cats react, with a picture of each state.

## 1.0.0 preview — 2026-10-16

The first public release. The Mac app is not notarized by Apple, so macOS refuses it the first time: open System Settings → Privacy & Security, click **Open Anyway** next to the NotchMeow message and confirm. Control-click → Open no longer gets past that on recent macOS.

- Mac downloads come as a `.dmg` disk image as well as the `.zip`. Both are signed ad hoc, not with a Developer ID
- Windows and Linux catch up with the Mac's island: a click outside the open island folds it, both wings step aside so the menu-bar icons can be clicked (Windows, and Linux under X11), and the Claude App pill has an Open button on Windows
- Send a file to another computer on Windows and Linux too: turn on Settings → Devices → Visible, pair the two machines once by checking that both show the same six digits, then send from the shelf's "To a device". Off by default: nothing listens or announces until Visible is on. Files land in Downloads/NotchMeow, marked as downloaded and never opened for you
- Sending between machines is sturdier: if the network service that finds your machines stops, it starts again on its own (Mac, Windows and Linux), and Windows removes a declined or failed file through the file it holds, never by name

## 0.9.3 — tester build

The fourth NotchMeow build for testers, still unsigned. See the testers page for how to install it.

- Windows and Linux catch up with the Mac: the shelf (drag a file to the right half of the island to keep it, drag it out again, ask about it, show it in its folder or send it with the Windows Share window), the wardrobe (Settings → Cat → Wardrobe and the cat's right-click menu, with Auto's dates) and the sidekick (the risk line under a permission request, the recap when you come back, stuck notes, and a file dropped on an agent's cat copies its path). See `windows/README.md` for what differs
- Send a file to your other Mac (macOS, off by default): turn on Settings → Devices → Visible on this network, pair the two Macs once by checking that both show the same six digits, then pick a file on the shelf and the laptop button. The other Mac shows a card and nothing is received until someone clicks Accept; files land in Downloads/NotchMeow, marked as downloaded and never opened for you. Until you turn it on, nothing listens and nothing is announced. Windows and Linux get it in a later build
- Open on hover (Settings → General, off by default): rest the pointer on the island for a moment and it opens; Close after folds it again
- On the Mac, a click outside the open island folds it, and a soft rainbow glow follows the island's edge while the pointer is on it (Settings → General → Hover glow; Windows and Linux have the glow too)
- On the Mac, both wings step aside: point at the cats on either side of the notch and the whole island slides into the notch, so the menu-bar icons under it can be clicked; it comes back a second after the pointer leaves
- A question with option descriptions shows each option with its description under it, and the island grows to fit
- A new permission card ignores clicks for its first 0.6 s, so a click meant for something else can't answer it (Mac, Windows and Linux)
- The Claude Code pill is labelled "Claude Code", and Claude Code sessions run from the Claude desktop app get a pill of their own, "Claude App"; their permission prompts stay in the Claude app
- The open island uses about half the CPU it did, and on ProMotion screens the cats in the island draw at 60 frames a second
- Fixes from Coucou: Antigravity's permission requests are left to Antigravity, the diff check no longer runs off the main thread, and on Windows a stale idle timer, the island's zoom on scaled screens and the pill padding are fixed

## 0.9.2 — tester build

The third NotchMeow build for testers, still unsigned. The new features in this build are on the Mac; Windows and Linux get them in a later build. See the testers page for how to install it.

- Claude Code started from any terminal (Terminal, iTerm, Ghostty, Warp, kitty, Alacritty and others) now shows up on the Claude Code pill, as it did from VS Code. A tap brings the right app forward, and the "Handled in …" notes name it
- A shelf in the notch: drag a file to the right half of the notch to keep it on the shelf, then drag it out again, ask about it, show it in Finder or send it with the share menu or AirDrop. It holds up to 30 items, and the compact island shows a small count while the shelf has items. Open it from the menu bar, the count or ⌃⌥S (off by default)
- A wardrobe for the cats: 16 outfits, from a party hat and a crown to a scarf, a bell and the cats' own shrimp and peach-blossom clips, in Settings → Cat → Wardrobe, the cat's right-click menu or ⌃⌥G (off by default). Auto, the default, follows the calendar: a party hat at New Year, a Santa hat in December, a witch hat in October, bunny ears at Easter and sunglasses in summer, and no outfit the rest of the year. The big cat wears it at every size; the small cats and the kittens stay bare
- A sidekick: the cats now say something useful at the end of a task, never over your work. A grey line under a permission request says what the command does, with an orange "High risk" badge for dangerous ones. A recap waits for you when you come back to your Mac. A note appears when an agent seems stuck or is still waiting for your OK. "What's Claude doing?" in the chat is answered on your Mac, and no cloud model sees it. Dropping a file on an agent's own cat copies its path for that agent. Turn it off or unmute notes in Settings → Sidekick. It keeps no prompt, no command and no full path, and it never allows or denies anything for you

## 0.9.1 — tester build

The second NotchMeow build for testers, still unsigned. See the testers page for how to install it.

- The cat on the desktop now runs on Windows and Linux too, as on the Mac: drag the big cat out of the notch or turn it on in Settings → Cat, and it floats above your windows with its badge, collar and kittens. It is off by default, and on GNOME's Wayland session the system chooses where it lands. See `windows/README.md` for what differs
- On the Mac, the island's right wing steps aside when you point at the grid of cats: it fades, so clicks reach the menu-bar icons under it, and it comes back a second after the pointer leaves
- When you drag a file to the notch while the cat is on the desktop, the cat flies to the notch to catch it, and only one cat shows while it does
- In Two cats mode, a press on the part of cat 2 that overlaps cat 1 no longer pulls cat 1 out of the notch

## 0.9.0 — tester build

The first NotchMeow build for testers: unsigned, checked on the owner's machines first. See the testers page for how to install it.

- Forked from Coucou 0.1.4 as NotchMeow: new name, bundle identifiers, Keychain service, support folders, hook relay names (`nm-hook`, `notchmeow-hook`) and payload fields (`nm_kind`, `nm_agent`), so NotchMeow can run next to Coucou without touching its hooks
- Removed Coucou's reserved assets (sounds, media, captures and prototypes)
- Shrimpy and Momo, two cats drawn entirely in code, replace Coucou's character on macOS, Windows and Linux, with NotchMeow's own app, menu bar and tray icons. Their eyes follow your cursor and each agent state has its own reaction. Settings → Cat picks the cat among 16 coats, a Playful or Classic motion style, a personality (six sliders and six presets), an optional collar in the agent's colour and fur lines. An idle cat falls asleep after ten minutes, bobs to Apple Music (macOS) and coughs up a file it can't read as a hairball
- Settings → Cat → Display: One cat, A cat for each agent (each agent keeps its own coat, with a dice and Reset to defaults) or Two cats side by side (the focused agent and the busiest other one). A Claude Code subagent shows up as a small kitten beside its parent's cat and leaves with a happy blink when it stops (Codex's too, on macOS). Every cat below Ø28 has small coloured eyes
- NotchMeow's own sounds: one short WAV for each moment, built from CC0 clips and credited in `docs/SOUND-CREDITS.md`, on macOS, Windows and Linux
- Gemini CLI and Antigravity (agy) hook support on Windows and Linux, as on the Mac: install them from Settings → Gemini CLI and Settings → Antigravity, and their sessions show up in the island. Ported by hand from upstream's `n22-gemini` branch, by @corefusiion
- Local models everywhere (macOS): Ollama, LM Studio, llama.cpp and Jan are found on their own, Apple's on-device model answers on macOS 26+, and you can add a model server on your network. Settings → Chat is now Settings → AI: choose Auto or a model for Chat and for File questions, and which cloud Auto tries first
- Claude, OpenAI (now through the Responses API, never stored) and Gemini stream their answers; Claude and OpenAI show their web sources as links. Each answer says where it came from (local, network or cloud), and when the cloud is busy or unreachable Auto answers once with a local model
- Dropped files reach every model: text, PDFs, scans and images (read on the Mac for models that can't see images), Word, RTF and HTML, cut to fit small models; the drop card says who will read the file, and follow-up questions stay with the model chosen for File questions
- Keyboard shortcuts (macOS), ported from Coucou 0.1.7: ⌃⌥A jumps to a waiting permission or question, ⌃⌥W attaches the front window to the chat (GitHub build), ⌃⌥] and ⌃⌥[ switch pills and ⌃⌥M mutes. ⌃⌥Space (open the chat) and ⌃⌥T (bring your terminal forward) are there too but off at first, because macOS and Rectangle already use those combinations. Settings → Shortcuts turns each on or off, changes its keys, flags a combination another app already uses, and has a "Turn all on" button
- In the open island: ⌘→ ⌘← and ⌘1 to ⌘9 switch pills, ⌘↓ ⌘↑ and ⌘O move through a GitHub list, ⌘E opens the diff, ⌘↩ sends and ⌘K starts a new conversation in the chat, ⌘, opens Settings, ⌘P pins the island, and ⎋ closes it
- The island shortcut (⌘⇧N, off by default) now opens and closes the island and needs no permission. A shortcut needs ⌘ or ⌃ plus another modifier, so it can't take plain typing from other apps
- A cat on your desktop (macOS, off by default): drag the big cat out of the notch, or turn it on in Settings → Cat, from the menu bar or with ⌃⌥D. It watches the pointer, dances and sleeps, flies back to the notch when an approval or a question needs you and returns to its spot after. Small, Medium or Large from its own menu; double-click to send it home
- The island's step words (Runs, Reads, Edits, Searches…) and the macOS permission prompts are in English
- A site for NotchMeow, with live Shrimpy and Momo and a page for testers

---

*Everything below is the history of upstream [Coucou](https://github.com/louis-cfm/coucou), kept for reference.*

## 0.1.4 — October 3, 2026

- See what Claude is editing, live: each file edit shows up in the session ticker with its +N −M lines, and a click opens the diff right in the notch (#177)
- When Claude finishes, the session card shows its final message instead of the last step, without the shimmer (#177, #179)
- GitHub pill: your open pull requests with their CI status, the pull requests waiting for your review, and the CI of the default branch of your recent repos. Click a row for the list, then an item to open it on github.com (#181)
- GitHub alerts: a badge and a sound when the CI of one of your pull requests turns red or green, when a default branch breaks, or when someone requests your review. Fast CI runs are caught too, and the card refreshes when you open it (#181, #185)
- Your GitHub contribution grid: the last 7 days in the GitHub card header, click it for the past 23 weeks, and click a day for its count (#187)
- The GitHub token needs read access to pull requests and CI: a classic token with the repo scope, or a fine-grained token with read access to Pull requests, Commit statuses and Actions (#181)
- The finished view no longer overflows the card (#179)

## 0.1.3 — October 3, 2026

- Answer Claude's questions from the notch: when Claude Code asks a multiple-choice question, pick an option or type your own answer right in the island, and Reply in terminal hands it back. Update your hooks in Settings to turn it on (#165) — thanks @Vega8991 for the idea (#94)
- Claude plan usage (GitHub build): turn on Settings → Agents → Plan usage to see your 5-hour and weekly limits in a small pill in the notch header, and click it for the details and reset times. Pro and Max plans; your current status line keeps working (#159)
- Chat with local models through Ollama or LM Studio, no API key needed: connect them in Settings → Chat → Local models. Answers stream in, and thinking blocks stay hidden (#156)
- Markdown in chat answers: bold, lists, headings, quotes, and code blocks with a copy button. Links open only when they are web links (#156)
- Apple Music (GitHub build): see what is playing in the notch, play, pause and skip on hover, and Mochi dances along (#144, #153)
- Settings are now organized in a sidebar (#153)
- The chat greets you by your own first name (#154)

## 0.1.2 — October 2, 2026

- Codex support (GitHub build): sessions show up live on the Codex pill, and permission requests get Allow and Deny in the notch. Install from Settings → Codex Hooks, then trust the hooks once with /hooks in Codex (#130) — thanks @lacatu5
- Cursor: Claude Code started in Cursor's terminal shows up on the Cursor pill, and you can answer its permission requests from the notch (#120).
- Pick your main coding tool in Settings → Active pills: VS Code, Cursor, Codex or Antigravity (Codex and Antigravity: GitHub build). It stays on and no longer takes one of the 4 slots (#120).
- The permission card stays in the notch until you answer it: the mouse no longer folds it, and reopening the island shows the request again (#117).
- The permission card also shows when the island is already open, and the pill you were on comes back once you answer (#120).

## 0.1.1 — October 2, 2026

- Declare the tools you use in Settings: Gemini CLI, Antigravity, Anthropic, Google AI and OpenAI pills join the existing ones (Cursor and Codex pills are coming soon), and you pick the main pill.
- Chat now supports Google AI (Gemini) and OpenAI in addition to Anthropic; switch provider and model by clicking the model name in the chat view, on macOS.
- Linux version: the Tauri app now builds for Linux too (AppImage, .deb, .rpm), with the island as a layer-shell overlay on Wayland and Claude Code hooks over a private Unix socket (#21) — thanks @Davy133
- Compact island on screens without a notch (#22) — thanks @Kamasoutra
- Only web links (http/https) open from the notch; other kinds of links from Claude or integrations are ignored (#16) — thanks @Cris1670
- Hook socket limited to your own user account, with size and time limits; logs no longer keep commands, n8n data or full URLs, and stay under 1 MB (#16) — thanks @Cris1670 and @Vignesh-Thangamariappan
- The island always reopens after folding, and Settings opens below it, resizable — thanks @rouderz
- Choose the Claude model for the chat in Settings; the list comes from your Anthropic account, and Claude Sonnet 4.6 stays the default — thanks @rouderz
- Windows build artifacts are now downloadable from a manual CI run — thanks @MysJofR
- Any agent can talk to Mochi: tag a hook payload with `coucou_agent` (e.g. `nb-hook --agent my-agent`) and it gets its own pill in the island (#7, #9) — thanks @lacatu5
- Gemini CLI and Antigravity (agy) hook support on macOS: install from Settings and their sessions show up in the island — thanks @corefusiion
