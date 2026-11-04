# Sub-project B: display modes, subagent kittens and coloured small eyes

**Status:** design approved in chat on 2026-10-07 and 2026-10-08, section by section, with mockups drawn by the app's own renderer. This is the written spec for review.
**Parent spec:** `docs/superpowers/specs/2026-10-03-notchmeow-design.md` ("Display modes", "Subagents", sub-project B). **Builds on:** sub-project A (`docs/superpowers/specs/2026-10-04-cats-in-app-design.md`), merged on both apps (stages 1 to 7). The cats' look, motion, personality, collars, sleep and theme are defined there and in `design/prototype/notchmeow.html`; this document doesn't repeat them.

## Goal
Let each AI agent be recognised by its own cat, show the user's two cats together, and show an agent's subagents as kittens beside it. Also give every small cat its real eye colour. Sub-project A shipped display mode (2), one chosen cat everywhere; B adds modes (1) and (3) and the kittens on both apps.

## Decisions

| Topic | Decision |
|---|---|
| Purpose | The owner runs several agents at once and wants to tell them apart at a glance and see their subagents at work. |
| Modes | Three, picked in Settings: **One cat** (the default, as it ships), **A cat for each agent**, **Two cats**. |
| Agent cats (mode 1) | Claude Code is Shrimpy and Codex is Momo by default. Every other agent gets a **random coat not already in use the first time it appears, and keeps it**. Any agent's cat can be changed in Settings, and a 🎲 button rolls a new random one. |
| Two cats (mode 3) | A pair, **Shrimpy & Momo by default and both pickable**. Cat 1 shows the focused agent; cat 2 shows the busiest other agent, and idles beside cat 1 when no other agent is active. They sleep together. They sit **side by side**. |
| Kittens | A subagent is a kitten of its parent's cat that shows **its own state** (working, searching, waiting on an approval) and leaves with a happy blink. Kittens sit **beside their parent**, wherever the parent is drawn. |
| Small eyes | Below a head of Ø28 the cats' plain resting eyes become **simple coloured eyes** (the coat's iris colour, a slit pupil, one catchlight, a thin rim) instead of A's flat ink pills. |
| Approach | **Contract first, then both apps in parallel**, like A: B-0 adds the rules and fixtures to `cat-core.js` and the prototype, then a Mac plan and a Windows/Linux plan replay them. The Mac gets at least what Windows/Linux gets. |
| Never restyle | One cat mode keeps the shipping layout. Its only visible change is the small eyes, which the owner chose. Mode-specific layouts change only in the mode that needs them. |

## 1. Settings and persistence

Settings → Cat gets a **Display** picker at the top, built from the existing row styles, with a small live preview of the compact notch in the chosen mode (sample agents, the real cats; it animates only while Settings is visible, like A's previews).

| Mode | ID | What it does | Cats used |
|---|---|---|---|
| One cat | `one` | what ships today | the **Main cat** |
| A cat for each agent | `perAgent` | every agent has its own cat | per agent, below |
| Two cats | `two` | the focused agent's cat plus the busiest other agent's, side by side | the **pair** |

- **"Character" is renamed "Main cat".** It's the cat in One cat mode, and in the other modes it's the cat for integration pills (Stripe, Music, Vercel…) and for the big cat when no agent is focused or running.
- **Pair** (Two cats mode only): two cat pickers, Shrimpy and Momo by default. If both are set to the same coat, cat 2 falls back to the next coat in `CAT_IDS` order.
- **Cats for your agents** (A cat for each agent mode only): one row per agent NotchMeow has seen, most recent first. Each row has the agent's colour, a live preview, a cat picker and a 🎲. A **Reset to defaults** button sits under the list.
- **Giving an agent its cat** (pure, in the contract): `integration_claude` → `shrimpy`, `agent_codex` → `momo`; any other agent pill, the first time it is seen, gets a random coat from those used neither by another agent nor as the Main cat. When all 16 are taken, the least-used coat is reused (ties broken in `CAT_IDS` order). The choice is stored, so it never changes by itself. The random source is injected, so tests are repeatable.
- **Storage.** macOS UserDefaults: `cat.displayMode`, `cat.pair` (JSON, two cat IDs), `cat.agentCat.<pillId>`. Windows/Linux: `displayMode`, `pair` and `agentCats` (a map from pill ID to cat ID) in the `cat` block of `settings.json`. All of them go through a clean-up of their own, `cleanDisplaySettings` (B-0 keeps `cleanCatSettings` and `settings-cases.json` byte for byte, and an app cleans the same raw block with both): an unknown mode is `one`, a bad pair is Shrimpy & Momo, an unknown or bad agent coat is that agent's default (a new random one for an agent without a default), and an unknown pill ID is kept (agents come and go). Kittens are never stored.
- **Frozen values.** The mode IDs `one`, `perAgent` and `two` are contract values like the cat and collar IDs: an unknown stored mode falls back to `one`.
- Motion, personality and collar stay per cat, as in A: in A cat for each agent mode, Codex's Momo moves with Momo's settings.

## 2. Which cat appears where

A cat stands for an agent's pill. The big cat shows the focused pill, as today, and focus moves as it does now (a tap; an approval pulling it in on the Mac).

**Agent pills** are Claude Code's pill (`integration_claude`, despite its prefix) and every `agent_*` pill (Codex, Gemini CLI, Antigravity, Cursor and any other agent). **Integration pills** are the other declared integrations (Stripe, Music, Vercel and the rest).

| Place | One cat | A cat for each agent | Two cats |
|---|---|---|---|
| Big cat, compact and expanded | Main cat | the focused agent's cat; the Main cat when the focus is an integration or nothing runs | pair cat 1, showing the focused agent |
| Second spot beside it | none | none | pair cat 2, showing the busiest other agent |
| Agent pills and the 2×2 grid | Main cat | each agent's own cat | Main cat |
| Integration pills | Main cat | Main cat | Main cat |
| Launch greeting | Main cat, its 4 session cats too | Main cat; the 4 session cats are the agents' cats, so they hand over to the grid without a change | Main cat, with the pair arriving together |
| Drop view and drag ghost | Main cat | the big cat's cat | the big cat's cat |

- **The busiest other agent** (Two cats): among the agent pills other than the focused one, in order: a waiting approval or question, then an error, then working, thinking or searching, then the most recent event. That agent leaves the pill row and the grid, as the focused one already does, so nothing is shown twice. With no other active agent, cat 2 sits idle with no badge. Tapping cat 2 focuses its agent, like tapping a pill.
- **Sessions.** Pills stay per agent, as today: two Claude Code sessions share one cat, and both sessions' subagents are that cat's kittens.
- **Layout in Two cats mode.** Compact: two Ø20 cats share the left ear. Expanded: cat 1 at Ø58 and cat 2 at Ø46 side by side in the left card; the ticker text moves right and gains a second line for cat 2's agent ("Codex · waiting for you"). Both badges stay fully visible. One cat and A cat for each agent keep the shipping layout.

## 3. Kittens

**Data** (no hook changes: the events are already installed, and the relays already pass the payload through):
- `SubagentStart` (Claude Code; Codex on the Mac) carries `agent_id` and `agent_type`. It adds a kitten to the parent agent's pill, found the way every other event finds its pill.
- `PreToolUse`, `PostToolUse` and `PermissionRequest` events that carry an `agent_id` belong to that subagent. They set its kitten's state: searching for a tool in `search-tools.json`, working for any other tool, approval while its permission request waits. The parent cat behaves exactly as today.
- `SubagentStop` plays a happy blink of about 0.6 s, then removes the kitten.
- Gemini CLI and Antigravity send no subagent events, so they have no kittens. Codex has no hooks on Windows/Linux yet, so no Codex kittens there.
- **Fallback.** If a Claude Code version sends no `agent_id` on tool events, kittens still appear at start and leave at stop, in the working pose. This is a planned path, not a failure.

**Look.** A kitten is its parent's cat as a kitten (`kittenOf`), with the parent cat's motion, personality and collar (in the agent's colour), the coloured small eyes (section 4) and its own state badge.

**Placement** (beside the parent, wherever it is drawn):

| Parent drawn as | Kittens | Overflow |
|---|---|---|
| Big cat, expanded | a row of up to 3 under it | "+N" |
| Big cat, compact (One cat, A cat for each agent) | up to 2 tucked beside it | "+N" |
| Pair, compact (no room beside) | a tiny kitten count, "×3", by the pair | — |
| Pair, expanded | each pair cat's kittens under that cat | "+N" |
| An agent pill | up to 3 small kittens at the pill's trailing end | "+N" |

Order: a kitten waiting on an approval first, then the newest. The exact slots, sizes and offsets are pure functions in the contract.

**Clean-up.** No polling: a kitten whose stop never comes is removed when its parent stops or its session ends, or when the existing 10-minute sleep timer fires. At most 8 kittens are tracked per agent; the oldest is dropped first. The ticker's "+ subagent" and "subagent done" lines and the approval cards from subagents work as today.

## 4. Coloured eyes for small cats

- **Where.** Every cat drawn at the compact detail level (head under Ø28): the compact notch, pill cats, the 2×2 grid, kittens and the greeting's session cats, on both apps. Large cats keep their realistic eyes.
- **What changes.** The plain resting shapes (`pill`, `wide`, `dot`, `tired`) become the coloured small eye: a round iris in the coat's colours (`iris`, or `irisR` for odd-eyed coats) as a soft gradient, a slit pupil in `Theme.Cat.pupil` that follows the gaze a little, one catchlight upper left that never drops under half a point, and a thin dark rim. Kittens keep their rounder, larger eyes. Blinks and squints close the eye to a line, as the big eyes do.
- **What stays ink.** The expression shapes (happy arcs, closed, wink, spiral, hearts, stars, line, flat), so a happy squint still reads at Ø12.
- **Starting values** (from the brainstorm mockup; B-0 fixes the final ones in the contract against the prototype): iris 0.42 R wide and 0.46 R tall, pupil 0.18 R × 0.40 R, catchlight radius max(0.075 R, 0.45 pt) at (−0.11 R, −0.10 R), rim max(0.05 R, 0.5 px).
- **Contract.** The prototype gets the new small eye first. `cat-core.js` holds the pure geometry, pinned by a generated `small-eye-cases.json` that both apps replay.
- **Cost.** A few more fills per eye. The frame budget (twelve small cats plus the big one under 2 ms on the Mac; 1.71 ms measured on 2026-10-07) is re-measured before and after, in optimised builds.

## 5. Build order, testing and checkpoints

1. **B-0, the contract** (one worktree session):
   - pure rules in `cat-core.js`: giving agents their cats; the cast of each mode (which cat in which spot, the busiest-other rule); kitten slots and overflow; the small-eye geometry; the Display settings' clean-up, `cleanDisplaySettings`;
   - generated fixtures: `agent-cat-cases.json`, `cast-cases.json`, `kitten-cases.json`, `small-eye-cases.json`, and `display-cases.json` for the Display settings; every existing fixture stays byte-identical;
   - the prototype gets the Display switch, the small eyes and kittens beside their parent;
   - **owner checkpoint:** the prototype in a browser and the small-eye contact sheets (all 16 coats and kittens at Ø12–24, at 1× and 2×, next to today's look).
2. **B-mac and B-tauri, in parallel** (worktree sessions on Sonnet 5.5, high effort), each in this order: the small eyes; the settings, the Display picker with its live preview and the agent list; per-agent coats; the Two cats layout; kittens; docs.
   - **Mac:** each cat view takes its coat as a parameter, so the per-frame "follow the Main cat" no longer overwrites a per-agent coat, and `useCharacter` is never called on a kitten.
   - **Windows/Linux:** the collar style is looked up per coat, as the Mac already does.
   - **Owner checkpoints:** eyes and Settings; the modes and kittens (images drawn without launching the app); final.
3. **Testing:** every rule against the shared fixtures on both apps; fake hook events through the socket for kittens (start, tool calls with and without `agent_id`, an approval, a stop, a lost stop); the frame bench before and after; CPU at 0 % when hidden. Checks that need real agents become the owner's owed checks at merge.

## Out of scope
- Per-session pills (two sessions of one agent stay one pill).
- Codex hooks on Windows/Linux, and a first-run agent picker.
- Sounds for kittens and modes (sound Stage 3).
- The desktop cat (H) and the wardrobe (I).
- Names or labels for kittens (the ticker lines stay as they are).

## Risks
- **Subagent tool payloads.** That tool events inside a subagent carry `agent_id` comes from Claude Code's documentation, not a recorded run. The kitten state falls back to presence only if it doesn't (section 3), and the owner's real-agent checks confirm it.
- **Space.** The compact notch's left ear holds one Ø20 cat and about 30 pt beside it; two cats plus kittens don't fit there, which is why the pair shows a kitten count in compact.
- **Frame time.** More small cats (kittens, a second big cat) and richer eyes cost frame time; the bench guards it.
- **Coat overwrite.** Today every cat view re-reads the global coat each frame; a missed call site would silently show the Main cat instead of an agent's. The plans add a test per call site.

## Done means
- All three modes work on both apps, picked in Settings and kept across restarts, with the live preview.
- In A cat for each agent mode, Claude Code is Shrimpy, Codex is Momo, and every other agent keeps the random coat it first got, unless the user changes it.
- In Two cats mode the pair shows the focused and the busiest other agent side by side.
- Claude Code subagents appear as kittens beside their parent, show their own state, and leave when they stop.
- Every small cat has coloured eyes.
- One cat mode looks as it ships, except the small eyes.
- Fixtures pass on both platforms; the frame budget and 0 % CPU when hidden hold.
- The owner signs off at the checkpoints.
