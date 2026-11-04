# Settings, restyled: six pages, tabs, and a layout that survives any window width

Status: draft for the owner's review (2026-10-17). The owner approved the direction ("option B") in chat on 2026-10-17; this document writes it down. Part of the relaunch set; the version stays 1.0.0 until that ships (owner, 2026-10-17).

Builds on: the Settings code as it ships (`NotchBuddy/Sources/App/SettingsView.swift`, `AISettingsViews.swift`, `CatSettingsView.swift`, `CatSettingsSection.swift`, `WardrobeSettingsView.swift`, `SidekickSettingsView.swift`, `ShortcutsSettingsView.swift`, `LinkViews.swift`), the Windows/Linux twin (`windows/src/settings/`), and three specs in flight that add rows to Settings: the Projects spec (`2026-10-17-projects-view-design.md`), focus awareness (`2026-10-17-focus-awareness-design.md`) and the rebuilt chat (`2026-10-17-notchmeow-chat-design.md`, being amended in parallel, which gives the ChatGPT and Gemini engines).

## Why

The owner opened Settings at three window widths and named three problems: it is **too crowded**, things are **hard to find**, and **text breaks when the window is resized**. The pictures (the build he looked at predates today's merge of "Tuck the island away", which replaced "Hide after N min without movement") show exactly why:

- At 415 pt (the narrowest the window goes) the 200 pt sidebar keeps its width, the detail column is about 200 pt, and words break in the middle ("inacti/ve", "Anthro/pic", "configur/ed"); buttons truncate ("Install h…", "Sto…"); a shortcut list wraps one word per line.
- At 1100 pt text fields stretch to about 900 pt and the cards are not the same width from page to page.
- The AI page has two boxes for the same Anthropic key ("Paste an API key" under Connect Claude, and "Anthropic API"). The "Active pills" page repeats the AI providers that already have their own box. The General page has a "Hotkey" group that is the same stored shortcut as the first row of Shortcuts.
- Cat is one very long page (ten groups). Agents shows a full path with the user name in monospace. Help text is 11 pt grey on dark, hard to read.
- Nine sidebar rows, and the thing a person wants (for example "show Cursor on the island") lives on a different page from the thing it belongs to (Cursor's hooks).

## Goals

1. **Six pages instead of nine**, each named for what the person is trying to do: General, Agents, AI and chat, Services, Cat, Devices. The three pages that are really several things get tabs: General (General, Shortcuts), AI and chat (Your AI, Keys, Local models, Sidekick), Cat (Look, Outfits, Personality, Agents' cats). Agents, Services and Devices have no tabs.
2. **Each pill's switch lives beside what it belongs to.** The "Active pills" page goes away. The main pill and the "slots used" count move to General.
3. **AI and chat is provider-neutral.** "Your AI" shows every way NotchMeow can get an answer (Claude plan, ChatGPT plan, Gemini, an API key, a local model), each with a plain ready or not-ready state and a **Make main** button. NotchMeow never sees credentials.
4. **One place per provider for its API key** (the duplicate goes), in the Keys tab.
5. **Sidekick gets the controls its notes deserve:** one switch per kind of note, quiet times, an example per kind, the muted list, where its words come from, and a "Today so far" button, with the controls that need F3a clearly marked as coming.
6. **A layout that holds at any width**, on every page: one column with a maximum readable width that stops growing; labels that never break inside a word; buttons that never truncate; under a breakpoint the sidebar shows icons only and controls move below their labels; slightly larger, higher-contrast help text; a full path only behind "Show path".
7. **Nothing is lost.** Every control that exists today has a named home in the map below, and every stored setting keeps its key and its meaning. A test proves it.
8. **Mac first.** The Windows/Linux app gets the same structure in its own plan.

## Non-goals

- Any new setting that is not named here. The new controls are the ones the owner named (the per-kind Sidekick switches, quiet times, "Today so far", the AI rows for the ChatGPT and Gemini plans) and a few layout aids (Show path, the tab bar). Everything else is today's controls in new places.
- Building the OpenAI-plan and Gemini-plan engines, quiet-times detection, the daily recap or the "main AI" voice. Those are chat-rebuild work (F3, F3a). This spec lays out their rows and their states.
- Changing what any setting does, how a hook file is written, how a key is stored or checked, or what the island shows.
- New colours, a new icon set, a new component library. The cards, switches, buttons, sidebar icon tiles and semantic colours are today's.
- A search box. Six pages with at most four tabs do not need one (revisit if Settings grows).
- Redesigning the island, the chat or any card. Only the Settings window.

## Anti-goals (a failure even if it works)

- **A control or stored setting that disappears, changes its key or changes its meaning.** A person who set Close after to 30 s, a Cat coat, a shortcut or a Keychain key finds it exactly as they left it.
- **A word broken in the middle, or a button label cut with an ellipsis, at any window width the window allows** (415 pt up to full screen), on any page and tab, in light and dark, with the longest sample strings.
- **A hidden control.** A setting that now lives behind a tab or "Show path" must still be reachable in at most two clicks from the sidebar; nothing goes only in a menu or a tooltip.
- **A credential or secret shown, logged or sent.** Keys stay in the Keychain, stay masked, and are never put in a picture, a log or a fixture. The render script uses fake values only.
- **Any CPU while Settings is closed, or a new timer or poll while it is open.** Hidden tabs are not in the view tree (their previews do not animate).
- **The App Store build gaining a control that needs the Claude Code engine or any CLI.** Those rows are absent there, not greyed.
- **A Settings page that silently saves a half-typed key.** Saving stays an explicit click, as today.

## Constraints

- Swift 6, SwiftUI + AppKit, no new dependency. The shell stays a plain `HStack` of sidebar and detail (no `NavigationSplitView`: it adds its own collapse rules and animations that this spec specifies by hand).
- Existing style kept: `GroupBox` cards, the standard `Toggle`, `Picker`, `.bordered` and `.borderedProminent` buttons, the sidebar's coloured icon tiles (`SettingsSidebarRow`) and their colours, SF Pro with today's sizes except the help text, system semantic colours so light and dark both work.
- Frozen IDs and every stored key stay (full list in the map below). The sidebar's stored selection (`settingsSection`) keeps working: an old value is mapped to its new home (rule 9).
- The Windows/Linux page structure follows in its own plan; the Mac code must not wait for it.
- Pure rules (the routing, the breakpoints, the control map) are Foundation-only and tested without the app, as the other contracts are. Views take plain values and closures so a render script can draw them without the app (`scripts/render-cat-settings.sh` is the model).
- The App Store build (`#if APPSTORE`) keeps its differences: Claude Code hooks through the folder picker, no Gemini/Antigravity/Codex hooks, no Plan usage, no Claude plan, no CLI-based AI rows.
- Performance: Settings is a window the user opened. It adds no timer, observer or poll. The cat previews keep stopping when the window is not key (`WindowVisibility`).
- No telemetry. Network calls only to services the user configured (the key check and the model list, as today).

## What the owner decided (2026-10-17)

- **Option B**: six pages, tabs where a page is several things, a layout that adapts to the window.
- **Pages**: General (tabs: General, Shortcuts; sound, island behaviour including Tuck the island away, startup, the main pill and the slots-used count). Agents (no tabs: hooks for Claude Code, Gemini CLI, Antigravity and Codex; Plan usage; the "Where you code" and agent pill switches). AI and chat (tabs: Your AI, Keys, Local models, Sidekick). Services (no tabs: Resend, n8n, Vercel, GitHub, Stripe, Cal.com, Notion, Music, each with its key or link and its show-in-island switch in one row; Spotify later). Cat (tabs: Look, Outfits, Personality, Agents' cats). Devices (content unchanged).
- **Active pills is removed**; each pill's switch sits beside what it belongs to.
- **AI and chat is provider-neutral**: "Your AI" picks what answers (Claude plan, ChatGPT plan via the Codex CLI signed in with ChatGPT, Gemini via the Gemini CLI, an API key, or a local model), each with a ready or not-ready state and Make main. NotchMeow never sees credentials. The ChatGPT and Gemini plan engines are chat-rebuild work (F3); their rows read "Coming with the new chat" until the engine lands.
- **Keys tab**: one place per provider for its API key; the duplicate goes.
- **Sidekick tab**: one switch per kind of note (return recaps, stuck nudges, permission line, later jokes and moods); quiet times (full-screen apps, calls and screen sharing, chosen hours); "Show me an example" per kind; muted notes in plain words with Unmute; where its words come from (plain rules, a local model, the main AI; nothing leaves the Mac unless a cloud AI is chosen); a "Today so far" recap button. Grammar check, jokes and the daily recap are F3a; this tab controls them, with live-now and comes-with-F3a controls marked.
- **Layout rules on every page**: one column with a maximum readable width that stops growing; labels never wrap mid-word; under a breakpoint the sidebar collapses to icons and controls move below their labels; slightly larger, higher-contrast help text; full paths behind "Show path"; the existing style kept.
- **Mac first**; Windows and Linux get the same structure in their own plan.
- The "never restyle what already ships" rule is lifted for Settings only (owner, 2026-10-17). It stays for every other view.

## The design

### The window

- **Minimum size.** Content width 415 pt, height 420 pt: the narrowest the window goes today in the owner's build (the `AppDelegate` code says 640 x 420; the build he measured goes to 415, because `sizingOptions = [.minSize]` lets the content's own minimum win). The builder settles which of the two is real and sets `contentMinSize` to 415 x 420 explicitly, so the narrow layout is a promise and not an accident. Default size stays 720 x 560. There is no maximum.
- **Sidebar.** Six rows, in this order, with today's icon tiles and colours: General (`gearshape.fill`, #8E939C), Agents (`terminal.fill`, #3B9EFF), AI and chat (`bubble.left.and.bubble.right.fill`, #E07950), Services (`puzzlepiece.extension.fill`, #7C5CFF), Cat (`pawprint.fill`, #D9A066), Devices (`laptopcomputer.and.iphone`, #5B8DEF). The header (app icon, "NotchMeow", version) stays.
- **Collapsed sidebar.** When the window is narrower than the breakpoint (starting value 600 pt, a plan call after review; tuned at checkpoint 1) the sidebar is 56 pt wide and shows the icon tiles only, each with its name as an accessibility label and a tooltip, and the header shows only the app icon. At or above the breakpoint it is 200 pt, as today. Nothing else about the sidebar changes.
- **The column.** The detail area has the page title, then the tab bar (when the page has tabs), then one column of cards. The column is as wide as the detail area up to a maximum (starting value 640 pt) and is centred in the area beyond that, so at 1100 pt the cards sit in the middle at 640 pt instead of stretching. Every card in the column is the same width. Side padding is 20 pt, 16 pt when the window is collapsed.
- **Tabs.** A text tab bar under the title (the selected tab underlined, in the accent colour; the same row height on every page). It remembers the last tab per page in a new key `settingsTab.<page>` (additive; `<page>` is the new page tag). If the labels do not fit the column, the bar becomes a pop-up menu button showing the current tab (this is the only fallback; the labels are never shortened or wrapped).
- **The result banner.** Today the line that says what just happened ("Checking the key…", "Hooks installed", an error) is a strip at the very bottom of the window that is easy to miss (the code's own comment says so). It becomes a banner at the top of the column, under the tabs: wraps to as many lines as it needs, red for a failure, grey-on-card otherwise, with an x that dismisses it. It clears when the page or tab changes, as today. The message texts do not change.
- **No hidden state.** A typed but unsaved key is kept while the window is open when the person changes tab or page (rule 11) and dropped on Save or when the window closes, as today.

### The layout kit (shared views, one file each)

A small kit every page is built from, so the rules hold by construction and are tested once. All take plain values and closures.

- `SettingsShell`: the sidebar, the detail area, the breakpoint, the min size, the selection and its migration.
- `SettingsPage`: title, optional tab bar, the banner, the column (the maximum width).
- `SettingsCard`: a `GroupBox` with a title, an optional one-line summary on the right of the title (a status), optional footer help text. Same width in every page.
- `SettingRow`: a label, optional help text under it, and a control. It lays out as label left and control right when both fit on one line, otherwise the control goes under the label, full width. It uses `ViewThatFits`, and the label is never allowed to be narrower than its longest word.
- `SwitchRow`: a `SettingRow` whose control is a switch (the label can be clicked).
- `KeyRow`: a secure field, a Save button, the check mark, a Remove button once a key is saved. Fields never stretch past the column and never past 420 pt.
- `StatusChip`: a dot or icon and one short word or phrase: Ready, Not ready, Not installed, Needs update, Coming with the new chat. Always `fixedSize`, never wraps or truncates; wraps to its own line before it would.
- `WrapRow`: lays a group of buttons or chips on one line if they fit, else on as many lines as needed. Every button is `fixedSize`, so "Install hooks" is never "Install h…".
- `PathDisclosure`: a "Show path" button that reveals the path (rule 8).
- `HelpText`: 12 pt (today 11 pt), a colour that is at least 4.5:1 against the card in light and in dark (`.secondary` is not, on dark), wraps, never truncates.

### Page rules (apply everywhere)

1. **Labels never break inside a word.** A text that does not fit its line wraps between words. A row whose label would be squeezed narrower than its longest word switches to the stacked layout first.
2. **Buttons never truncate.** Button labels are `fixedSize`; a group of buttons wraps (`WrapRow`).
3. **Fields.** A secure or text field fills its row up to the column width and never more than 420 pt; a number field is 64 pt; a picker is 180 pt wide in the side-by-side layout and full width in the stacked one.
4. **Status words use chips,** not grey prose in a corner (today "Key not configured" is squeezed into a 40 pt column).
5. **Card titles say what the card is.** A card that holds one thing is not titled with a sentence.
6. **Help text** is `HelpText` (12 pt, readable). Long explanations that today are four lines of 11 pt grey are cut to what a person needs and the rest moves behind a "More" disclosure only if it would be lost otherwise.
7. **Confirm flows stay as they are.** "Install hooks" previews the JSON diff and needs "Confirm & write", as the CLAUDE.md rule says (the diff view is a disclosure inside the card; the buttons and the backup note do not change).
8. **Paths.** A full path is not on the page by default. A "Show path" button on a card reveals it in monospace, selectable, with the home folder shown as `~` (never the user name), with Copy and, where it is a folder or file, Show in Finder. In the App Store build the paths are the literal text it shows today.
9. **Stored selection.** `settingsSection` holds the page tag. New tags: `general`, `agents`, `chat` (kept for AI and chat so a stored value still works), `services`, `cat`, `devices`. Old values map: `activepills` to `general`, `integrations` to `services`, `shortcuts` to `general` with the Shortcuts tab, `sidekick` to `chat` with the Sidekick tab; anything else to `general`.
10. **Switch rows that need something first** (a hook not installed, a key not saved, a server not running) stay switchable, as today, and carry a chip that says what is missing. The one hard limit is the four-slot cap: at 4 of 4 a switch that is off is disabled and its chip says "4 of 4 slots used. Turn another off." (the same limit and the same wording as today's, with the full sentence).
11. **Drafts.** The text of a key or URL field that was typed and not saved is held in one object for the window's life (`SettingsDrafts`), so changing tab or page does not lose it. Save writes it; a field with unsaved text shows a small "Not saved" chip.
12. **Order inside a page** follows what a person does first: status and the main choice on top, then the things they change now and then.

### General (tabs: General, Shortcuts)

**General tab.** Four cards.

- **Sound**: Enable sounds; Volume.
- **Island** (today's "Behavior"): Open on hover; Hover glow; Tuck the island away (Never, After 1, 5, 15, 30 min); Close after (seconds of inactivity). When focus awareness lands: "Step back when I'm already in the app", next to Open on hover. The "Close after" row reads "Close after" with a 64 pt number field and "seconds" (today "Close after [15] s inactive", the row that breaks at 415 pt).
- **On the island** (the old Active pills, the part that is not per-pill): Main pill (the picker of the workspace pills, with today's side effects: the new main leaves the active set, loads its tasks, takes focus); a line "2 of 4 slots used" with the names of the pills using them ("Antigravity, Codex"), amber at 4 of 4. A short sentence says the switches are on the Agents, AI and chat and Services pages, and each name in the line is a link that opens its page.
- **Startup**: Launch at Mac startup.

**Shortcuts tab.** Today's page as it is: Global shortcuts (a switch and a recorder per action, Turn all on, Reset to defaults, the "Off at first" notes) and In the island (the read-only list). The row "Open or close the island" is the one that was also in General as "Hotkey"; it now has one home. Its stored keys are the same three (`hotkeyEnabled`, `hotkeyFlags`, `hotkeyCode`), so a shortcut already set keeps working. The island's own keys (the read-only list) stay a two-column table (keys left, action right) down to the collapsed width, then stack.

### Agents (no tabs)

Cards, in order:

1. **On the island** ("Where you code" and the agent switches, from the old Active pills): one row each for Claude Code (a "Main" chip when it is the main pill, otherwise a switch), Cursor, Antigravity, Codex and Gemini CLI, each a `SwitchRow` with a chip when a hook is missing ("Hooks not installed"). The App Store build lists only what `PillCatalog.available` offers there. The Claude App pill is not offered (its sessions are Claude Code's; unchanged).
2. **Claude Code hooks**, **Gemini CLI hooks**, **Antigravity hooks**, **Codex hooks** (the last three not in the App Store build): one card each: a chip (Installed, Not installed, or Needs update, which is today's "Hooks outdated" warning), one sentence of what to do next ("Restart Gemini CLI to activate"; for Codex "Open Codex, run /hooks or open Hooks in the app's settings, and trust them"), the Install hooks and Uninstall buttons (`WrapRow`), the result line (`HookNoteLine`), the JSON preview and Confirm & write / Cancel when pending, and **Show path** (the script path or the settings file). The App Store card keeps its folder picker and its alert.
3. **Plan usage** (not in the App Store build): the explanation (shortened, with "More"), the Show in the notch switch, the relay state as a chip (installed or not) with Install relay or Uninstall relay, the result line, the heard-from line, the diff and its Confirm. Show path for `~/.claude/settings.json`.

### AI and chat (tabs: Your AI, Keys, Local models, Sidekick)

**Your AI.** Two cards.

- **Which one answers** (today's "Which model answers", unchanged in meaning): Chat and File questions, each a picker (Auto, then the choices as today) and, under Auto, the resolution line ("Claude plan · Haiku, falls back to Apple on-device"); and "When Auto picks a cloud model, prefer" (the segmented Claude plan / Claude API / OpenAI, only when two or more are ready). Same stored values as today.
- **Choose your AI**: one row per way to get an answer, each with a name, a one-line what-it-is, a chip, and a button.
  - **Claude plan** (not in the App Store build): "Your Claude subscription, through the Claude Code you already have." Chip: Ready ("Claude Code 2.1.289, signed in with your Claude plan"), Not signed in, Not installed, Off. Buttons: Make main; Connect or Stop using it and Check again (today's Connect Claude controls, in a disclosure "Details" with the model choice Sonnet, Opus or Haiku). The card's own text says NotchMeow never signs in and never reads Claude Code's credentials.
  - **ChatGPT plan** (not in the App Store build): "Your ChatGPT subscription, through the Codex CLI signed in with ChatGPT." Chip: **Coming with the new chat.** Make main disabled. When the engine lands (F3) the chip becomes Ready, Not signed in ("run codex login in Terminal"), Not installed (with the Get link), and Make main works, exactly as the Claude plan row.
  - **Gemini** (not in the App Store build): "Your Google account, through the Gemini CLI signed in." Same: **Coming with the new chat**, then the same states. This is the chat brain; the Gemini CLI's hooks and pill are on Agents and are unrelated to it.
  - **API key**: one row per provider (Anthropic, Google AI, OpenAI). Chip: Ready when a key is saved (a green check once a check has passed), No key yet. Buttons: Make main, and "Add a key" (opens the Keys tab on that provider).
  - **Local models**: one row per server that is running (Ollama, LM Studio, Jan, llama.cpp, a custom server) and Apple on-device when it is ready: "Running, 4 models" or "Ready". Make main. Servers that are not running or installed are on the Local models tab, not here.
  - **Make main** sets the Chat picker above to that choice (an explicit model: the provider's remembered or default one; for a server with more than one model it opens a small menu of its models). The row that is main shows a "Main" chip instead of the button. It changes Chat only; File questions keeps its own choice. A choice that is not ready cannot be made main (its button is disabled with the reason).
  - **NotchMeow never sees credentials**: a plan row only asks the vendor's own tool whether it is installed and signed in, as the Claude row does today. No row reads a token, a cookie or a credentials file.

**Keys.** One card per provider: Anthropic, Google AI, OpenAI. Each card: the provider name with its accent dot, a `KeyRow` (secure field, Save, a green check or red cross after the check, Remove), the show-on-the-island switch for its pill (`ai_anthropic`, `ai_google`, `ai_openai`), and a one-line help ("From the Claude Console. Saved in the Keychain, checked when you save"). The Anthropic card also has the **Model** picker with Custom… and its text field (the list is fetched from the account, with the fallback list). The second Anthropic key box (under Connect Claude) is gone. Saving behaves like the old "Anthropic API" box: it saves, checks with a model-list call, shows the result in the banner. (The old Connect Claude box also set the preferred cloud to Anthropic when a non-empty key was saved; that side effect goes, because Make main is now the explicit way to choose.)

**Local models.** One card: the servers (Ollama, LM Studio, Jan, llama.cpp and any added), each a row with the status chip (Running, 4 models; Server off; Not installed; Update needed), a Get or Update link, Remove for a server the user added, and the show-on-the-island switch for the servers that have a pill (`ai_ollama`, `ai_lmstudio`); the Apple on-device row with its status; the "network, unencrypted on your network" note; and the buttons Rescan and Add server… (the sheet is unchanged).

**Sidekick.** See "The Sidekick tab" below.

### Services (no tabs)

One card per service: Resend, n8n, Vercel, GitHub, Stripe, Cal.com, Notion, Music. Each card has a header row with the colour dot, the name, a chip (Saved, or No key yet) and the **Show on the island** switch (the pill: `integration_resend`, `integration_n8n`, `integration_vercel`, `integration_github`, `integration_stripe`, `integration_calcom`, `integration_notion`, `integration_music`), then the fields, then a Save button that saves that card's fields (today one "Save integrations" button saves all of them; the keys and the GitHub side effects below are the same). A saved field shows masked. Per service:

- Resend: API key, From address.
- n8n: Instance URL, API key, and Workflows (Load list or Refresh, Clear, the checkbox list, "Watching 3 of 12"), the list behind a "Choose which to watch" disclosure.
- Vercel: Token, and Projects (same as Workflows).
- GitHub: Personal Access Token, and the scope hint as `HelpText`. Saving a changed token keeps its side effects (clear the pulse, activity and stats; refresh when a token is present).
- Stripe: Secret key. Cal.com: API key. Notion: Integration token.
- Music (Apple Music; not in the App Store build): no key. The switch, and one line: "Shows what the Music app is playing. Nothing to enter." Spotify gets its card when its pill exists; there is no placeholder for it now.

### Cat (tabs: Look, Outfits, Personality, Agents' cats)

Today's ten groups, split by what the person is doing. Each group keeps its contents and its stored keys.

- **Look**: Main cat (the 16 coats and the big preview), Look (collar, this cat's collar, fur lines), Desktop (Cat on the desktop and what is there today).
- **Outfits**: Wardrobe (the preview, the coat picker that stores nothing, Auto and None and the 16 outfits).
- **Personality**: Personality (the preset and the sliders, the preview), Motion (style, this cat's motion), Every cat (Apply to every cat).
- **Agents' cats**: Display (One cat, A cat for each agent, Two cats, with its preview strip), then the group that mode needs: Your two cats (Two cats mode) or Cats for your agents (A cat for each agent), and, when the Projects feature lands, Project cats.

Only the active tab's previews exist (a hidden tab draws nothing). The coat grids wrap their tiles (about six across at 720 pt and four at 415); the display preview scales down to the column; the personality sliders take the full column width, with the trait's name and value above and its two ends below.

### Devices (no tabs)

Content unchanged: This Mac (Visible on this network, Name), Machines (the list, Pair or Forget, the Local Network permission button), Received files (Show in Finder). It gets the page rules only: the card widths and the column, the help text, wrapping buttons, and "Forget Name?" with Keep wrapping instead of truncating.

### The Sidekick tab

The page title is "AI and chat"; the tab is "Sidekick". Cards:

1. **Notes**: the master switch ("Show notes from the sidekick": the stored `sidekick.on`) and, below it, one `SwitchRow` per kind of note, each with a one-line description and **Show me an example**:
   - **Away recaps** (kind `recap`): "A short recap when you come back and an agent did something."
   - **Stuck nudges**: "A nudge when an agent looks stuck." One switch for the four stored kinds (`stuck.loop`, `stuck.errors`, `stuck.waiting`, `stuck.silent`), with a "Choose which" disclosure that shows the four as switches named as today ("Repeated steps", "Repeated errors", "Waiting for your OK", "Gone quiet"). The switch shows on when none of the four is muted and off when all are; mixed shows as on with "3 of 4".
   - **Permission line** (the risk label under a permission request): see the owner's questions; today "Permission explanations are always on."
   - **Jokes and moods** (later): disabled, chip "Comes with F3a".
   - A switch for a kind is a view of the same state as the muted list: off means muted, on means unmuted (rule S1).
   - **Show me an example** draws a sample note inside the card, in the island note's look, using the plain template for that kind with a made-up agent ("Claude Code has run the same step 4 times."). It does not open the island, play a sound or touch the real ledger. It is live now.
2. **Quiet times** (comes with F3a): three rows, disabled and marked "Comes with F3a": "Full-screen apps" (hold notes while an app is full screen), "Calls and screen sharing" (hold notes while a call or a screen share is on), "Chosen hours" (a from and to time). F3a decides how a call or a share is detected (its privacy cost) before this tab shows them as live. Until then the card says what is coming, once, and the notes are only ever held by the gate that exists today (never over the user's work, never while they type).
3. **Where its words come from**: a choice of three. **Plain rules** (the stored `sidekick.local` is false). **A model on this Mac** (`sidekick.local` is true), with the existing line "Found: Apple on-device" or "No local model found". **My main AI** (comes with F3a; disabled, chip "Comes with F3a"). One sentence under the choice, always visible: "Nothing leaves this Mac unless you pick a cloud AI as your main AI." When F3a makes "My main AI" live, a cloud main AI adds "Notes would be written by <provider>, a cloud service" under it.
4. **Today so far**: a "Today so far" button (comes with F3a, disabled with a chip until the daily recap engine exists).
5. **Muted notes** (today's group, same data and rule): every muted kind in plain words with Unmute, "Nothing is muted" when none, and the line "A note you dismiss twice is muted until you unmute it here."

Rule S1: a kind's switch and the muted list both read `SidekickSettings.isMuted`; turning a switch off writes the kind as muted (a new pure `mute(kind)` in `sidekick-core.js` beside `unmute`, one fixture case; the stored `sidekick.dismissals` count for it is 2, the same as two dismissals), turning it on is `unmute`. The master switch keeps today's meaning (`sidekick.on` ends recaps and nudges). Live now: the master switch, the per-kind switches (if `mute` is accepted at review; if not, they come with F3a and the tab shows the master and the muted list until then), Show me an example, the local-model choice, the muted list. Comes with F3a: Jokes and moods, Quiet times, My main AI, Today so far.

### Control map: every control, its new home, its stored keys

"Keys" are UserDefaults keys on the Mac unless noted (K = Keychain item, F = a file the app writes outside preferences, none = a live action with nothing stored). Every key below stays exactly as it is.

| Today | New home | Stored |
|---|---|---|
| General: Enable sounds | General, General, Sound | `soundEnabled` |
| General: Volume | General, General, Sound | `soundVolume` |
| General: Open on hover | General, General, Island | `openOnHover` |
| General: Hover glow | General, General, Island | `island.hoverGlow` |
| General: Tuck the island away | General, General, Island | `island.tuckAway` |
| General: Close after N s inactive | General, General, Island | `autoCloseInterval` |
| General: Show island with shortcut, Shortcut recorder | General, Shortcuts, "Open or close the island" row (the same row Shortcuts already has) | `hotkeyEnabled`, `hotkeyFlags`, `hotkeyCode` |
| General: Launch at Mac startup | General, General, Startup | none (the system login item) |
| Active pills: Main | General, General, On the island | `mainPill` |
| Active pills: N/4 slots used | General, General, On the island | derived from `activeIntegrations` |
| Active pills: Claude Code, Cursor, Antigravity, Codex | Agents, On the island (and their hook cards) | `activeIntegrations` |
| Active pills: Gemini CLI | Agents, On the island (and its hook card) | `activeIntegrations` |
| Active pills: Anthropic, Google AI, OpenAI | AI and chat, Keys, each provider's card | `activeIntegrations` |
| Active pills: Ollama, LM Studio | AI and chat, Local models, each server's row | `activeIntegrations` |
| Active pills: Resend, n8n, Vercel, GitHub, Notion, Cal.com, Stripe, Apple Music | Services, each card's switch | `activeIntegrations` |
| Agents: Claude Code hooks (Install, Uninstall, Update, Confirm) | Agents, Claude Code hooks | F: `~/.claude/notchmeow/nm-hook`, `~/.claude/settings.json` (backup first) |
| Agents: Claude Code hooks, App Store install state | Agents, Claude Code hooks | `notchmeowHooksInstalled` (written by the App Store install and uninstall, read by the island's hooks check) |
| Agents: Gemini CLI, Antigravity, Codex hooks | Agents, each hook card | F: `~/.gemini/settings.json`, `~/.gemini/config/hooks.json`, `~/.codex/hooks.json` |
| Agents: Plan usage, Show in the notch, relay | Agents, Plan usage | `showPlanInNotch`; `claudePlanUsage` (runtime); F: `~/.claude/settings.json` |
| AI: Connect Claude (Use my Claude plan, Stop using it, Check again) | AI and chat, Your AI, Claude plan row (Details) | `aiClaudeCodeEnabled`, `aiClaudeCodeModel` |
| AI: Paste an API key (Anthropic) | merged into AI and chat, Keys, Anthropic | K: `anthropic-api-key` |
| AI: Which model answers: Chat, File questions | AI and chat, Your AI, Which one answers | `aiChoices` |
| AI: Preferred cloud | AI and chat, Your AI, Which one answers | `aiPreferredCloud` |
| AI: Anthropic API key, Save | AI and chat, Keys, Anthropic | K: `anthropic-api-key` |
| AI: Anthropic Model, Custom | AI and chat, Keys, Anthropic | `claudeModel` |
| AI: Google AI key | AI and chat, Keys, Google AI | K: `google-api-key` (`googleChatModel` unchanged, not shown) |
| AI: OpenAI key | AI and chat, Keys, OpenAI | K: `openai-api-key` (`openAIChatModel` unchanged, not shown) |
| AI: Local models list, Rescan, Add server | AI and chat, Local models | `aiCustomServers`; K: each server's key; `aiLastUsedLocal`, `localModelMemory` (runtime) |
| AI: Apple on-device status | AI and chat, Local models, and Your AI | none |
| (new) ChatGPT plan, Gemini rows, Make main | AI and chat, Your AI | writes `aiChoices` (Chat) |
| Integrations: Resend key, From | Services, Resend | K: `resend-api-key`, `resend-from` |
| Integrations: n8n URL, key, Workflows filter | Services, n8n | K: `n8n-url`, `n8n-api-key`; `n8nWorkflowFilter` |
| Integrations: Vercel token, Projects filter | Services, Vercel | K: `vercel-token`; `vercelProjectFilter` |
| Integrations: GitHub token | Services, GitHub | K: `github-token` |
| Integrations: Stripe, Cal.com, Notion | Services, each card | K: `stripe-api-key`, `calcom-api-key`, `notion-api-key` |
| Integrations: Save integrations | Services, each card's Save | (writes the keys above) |
| Shortcuts: Global shortcuts (11 actions), Turn all on, Reset to defaults | General, Shortcuts | `shortcut.<id>.enabled`, `.keyCode`, `.flags` (and the three `hotkey*` for `toggleIsland`) |
| Shortcuts: In the island | General, Shortcuts | none (read-only) |
| Cat: Display, Your two cats, Cats for your agents | Cat, Agents' cats | `cat.displayMode`, `cat.pair`, `cat.agentCat.<pillId>` |
| Cat: Desktop | Cat, Look | `cat.desktop.on`, `cat.desktop.size`, `cat.desktop.spots` |
| Cat: Wardrobe | Cat, Outfits | `cat.outfit` |
| Cat: Main cat | Cat, Look | `cat.character` |
| Cat: Look (collar, this cat's collar, fur lines) | Cat, Look | `cat.collar`, `cat.collar.<id>`, `cat.furLines` |
| Cat: Motion | Cat, Personality | `cat.motionStyle`, `cat.motion.<id>` |
| Cat: Personality | Cat, Personality | `cat.personality.<id>` |
| Cat: Every cat (Apply to every cat) | Cat, Personality | writes the keys above |
| Sidekick: Recaps and nudges | AI and chat, Sidekick, Notes (master switch) | `sidekick.on` |
| Sidekick: Nicer wording from a local model | AI and chat, Sidekick, Where its words come from | `sidekick.local` |
| Sidekick: Muted notes, Unmute | AI and chat, Sidekick, Muted notes | `sidekick.dismissals` |
| (new) per-kind switches, Show me an example | AI and chat, Sidekick, Notes | `sidekick.dismissals` (a switch off is a mute) |
| Devices: Visible on this network, Name | Devices, This Mac | `link.visible`, `link.deviceName` |
| Devices: Machines, Pair, Forget, Local Network permission | Devices, Machines | K: `link.peer.<id>`, `link.static-key`, `link.device-id` |
| Devices: Show in Finder | Devices, Received files | none |
| Sidebar selection | the shell | `settingsSection` (old values mapped); `settingsTab.<page>` (new) |

**Rows other plans add, and where they go** (whichever lands second ports the other's rows to the home below; both orders work):

| Row | Plan | New home |
|---|---|---|
| Step back when I'm already in the app (`island.focusAware`) | focus awareness | General, General, Island |
| Project cats (one row per project, a coat picker, Reset) | Projects | Cat, Agents' cats, after Cats for your agents |
| Companion settings (humor, memory, see my sessions, per-tool Ask first, computer use, allowed folders; `companion.*`) | F3a and F3b | a fifth tab "Companion" on AI and chat, reserved here (see the owner's questions); until a plan builds it, no tab is shown |
| Shortcut actions `companion`, `stopcomputer` | F3 | General, Shortcuts, in the list like the others |

Anything that today names "Settings → Active pills" or "Settings → Integrations" in a comment, a doc or the Projects contract's "Claude only" rule (rule 11) is updated to the new name in the same change that moves the page (the rule itself does not change: it reads `activeIntegrations`).

### Windows and Linux

The Windows/Linux Settings is one long scrolling page of sections (`windows/src/settings/main.ts`: Claude Code, Gemini CLI, Antigravity, AI, Integrations, Cat, Wardrobe, Sidekick, Devices, General), with no sidebar. It gets the same six pages, the same tabs and the same layout rules, in the Windows island's own style, in its own plan after the Mac's checkpoint 1 is signed off (the pictures settle the structure first). Its stored keys are the `settings.json` blocks it already has (kept at every save, with Rust twins where the file's schema needs one); no key is renamed. The control map's first two columns apply to it; the Windows plan adds a third column with its own keys. The Windows twin of the render script is a Vite page in `?dev`, in the style of the existing `?dev` panels.

## Tests, checkpoints and proof

Pure parts (Foundation only, no app):

- **`SettingsRoute.swift`**: the page and tab tags, the sidebar order, and `migrate(storedSection:)` (rule 9). Test: every old tag maps, an unknown tag falls back to General, a stored new tag is unchanged.
- **`SettingsLayout.swift`**: `sidebarMode(windowWidth:)` (expanded or icons), `columnWidth(detailWidth:)` (the maximum, centred beyond it), and the sizes. Test: the breakpoints at 415, 599, 600, 720, 1100, 3000.
- **`SettingsMap.swift`** and `tests/fixtures/settings/controls.json`: every control id with its page, tab and Mac stored keys, as in the table above. Test: every key in the frozen list of today's keys appears under exactly one control (nothing lost, nothing duplicated), no key is renamed (the list is compared with the keys the code reads, by a source scan like the other wiring pins), and every page has at most four tabs (five with Companion). The Windows plan adds its keys to the same file.
- **Contrast** (`scripts/test-settings-contrast.sh`, AppKit): the resolved colour of `HelpText` against the card is at least 4.5:1 in light and in dark.

Wiring pins to move, not delete (they read `SettingsView.swift` today): `tests/CatWiringTests.swift` (line 23), `tests/IslandTuckAwayWiringTests.swift` (line 13), `tests/HookInstallNoteTests.swift` (line 35), `tests/SidekickWiringTests.swift` (lines 140 and 141: it pins that Settings gained one sidebar row and no other line, which is no longer a rule), `scripts/test-link-wiring.sh` (line 148, the Devices tag), `scripts/test-u1-wiring.sh` (line 81, the Hover glow toggle). Each keeps asserting what it asserted (the control is wired to the same state) at its new file. `scripts/check-no-leftovers.sh` gains the old tags (`activepills`, `integrations` as a tag) so they cannot come back except in `SettingsRoute.migrate`.

**Owner checkpoints.**

1. **Pictures before any wiring.** `bash scripts/render-settings.sh` (a `render-settings.swift` in the style of `render-cat-settings.sh`: it compiles the pure kit and the page views, with sample values, no app and no `AppState`) draws the six pages at 415, 720 and 1100 pt wide as PNGs, plus every tab, in dark and light, and a contact sheet. Options: `--page`, `--tab`, `--width`, `--light`, `--appstore` (compiled with `-D APPSTORE`, to show the absences), `--stress` (the longest sample strings: a long project name, a long path, a long model name, a long error) and `--states empty|ready|error`. It uses made-up names and paths and never this Mac's name or user (`scripts/check-settings-render-private.sh`, in the style of `check-link-render-private.sh`). The owner sees these before the real Settings is rewritten and signs off the structure (the page map, the tabs, the breakpoint and the column width) or sends it back.
2. **The real window.** After wiring: the owner (or a computer-use pass he asks for) opens Settings in the built app, resizes from 415 pt to full screen on each page and tab, and checks the two things he named: nothing breaks and he can find things. The control map's test runs first.
3. **Sign-off, then a whole-branch review** (CLAUDE.md trigger 4, with a privacy pass: no key in a picture, a log or a fixture).

## Phasing

- **S-0 Pure rules and the map**: `SettingsRoute`, `SettingsLayout`, `SettingsMap` with `controls.json`, their tests, the contrast test. Plus `mute(kind)` in `sidekick-core.js` with its fixture, if accepted.
- **S-1 The kit and the pictures**: `SettingsShell`, `SettingsPage`, `SettingsCard`, `SettingRow` and the rest; `render-settings.sh` drawing the six pages from sample values. **Checkpoint 1 here.**
- **S-2 The pages**: port each page into the kit (General, Agents, AI and chat with Keys, Local models and Sidekick, Services, Cat, Devices), split `SettingsView.swift` (1,544 lines today) into a view per page, move the wiring pins, the docs and the names. **Checkpoint 2, then 3.**
- **S-3 Windows and Linux**: its own plan after Checkpoint 1 is signed.

Which model runs each part is the main session's call under CLAUDE.md (the pure rules and the pages are Haiku work; the shell's window and breakpoint behaviour is platform work).

## What is left to the builder

- The exact numbers: the breakpoint (starting 600 pt), the sidebar widths (200 and 56), the column maximum (starting 640), the padding, the tab bar's height and the field maximum (420). The builder starts from these and tunes them at checkpoint 1.
- The file split and names of the page views and the kit, as long as `SettingsView.swift` stops being one 1,500-line file and the pure parts stay Foundation-only.
- How `SettingsDrafts` is held and how the tab bar is drawn (a segmented control is not allowed: it truncates; a text tab bar or its menu fallback is).
- The wording of the new one-line descriptions, in the app's plain voice (no marketing words), reviewed in the pictures.
- How "Show me an example" composes a sample note from the existing text templates without touching the real ledger, and whether it needs a small pure helper.
- How the Claude plan row's state is read (it reuses what `ConnectClaudePlanView` and `state.claudeCodeStatus` already know).

## Calls made by the main session (2026-10-17; the owner may override any)

1. **The Hotkey group is removed from General.** It is the same shortcut (same three keys) as the first row of Shortcuts; it has one home.
2. **Per-card Save on Services** instead of one "Save integrations". Same keys and side effects; a card says "Not saved" until it is.
3. **The second Anthropic key box goes; its preferred-cloud side effect goes with it.** Make main replaces it.
4. **Make main sets Chat only.** File questions keeps its choice.
5. **A result banner at the top of the column** replaces the bottom strip.
6. **The sidebar collapses to icons below a breakpoint and the column is centred at a maximum width** (numbers tuned at checkpoint 1).
7. **The ChatGPT and Gemini rows are drawn now and disabled** with the chip "Coming with the new chat", so the page does not change shape when the engines land.
8. **Cursor is a switch only** (it has no hooks card), and the Claude App pill stays unlisted, as it is today.
9. **A "Companion" tab is reserved** on AI and chat for the rebuilt chat's settings; no tab is shown until a plan builds it.

## Calls made after the builder check (main session, 2026-10-17; the owner may override any)

The builder check (reading this as a builder with no one to ask) found these. Answered in the text above: what Make main writes, where the Hotkey goes, how Services saves, what happens to a half-typed key, how an old `settingsSection` is read, what the minimum window is and the mismatch in the code, which pills exist per page and why the Claude App is absent, what the App Store build shows, which Sidekick controls are live. Builder calls made:

1. **Builder call: the minimum window is 415 x 420.** The builder confirms which number is real today and sets it in `AppDelegate`.
2. **Builder call: a stored model for Make main on a local server** is `localModelMemory[serverID]` if it is set, else the first model; a menu appears when there is more than one.
3. **Builder call: Remove on a saved key** is the same path as saving an empty field (which removes it today); the button only makes it findable.
4. **Builder call: a switch with a missing prerequisite** stays switchable, as today, and shows a chip; only the four-slot cap disables.
5. **Builder call: tab memory** is per page (`settingsTab.<page>`), not global.
6. **Builder call: "Show me an example"** draws inside the card and never in the island.
7. **Builder call: no keyboard shortcut for pages** (for example command-1 to 6) in this pass.
8. **Builder call: the tab bar's overflow** is a pop-up menu button (never shortened labels, never a scroll).
9. **Builder call: a coat grid** wraps its tiles to the column width; the 16 coats are not scaled.

Left for the owner:

1. **The permission line switch.** The sidekick spec (F1) says the risk label under a permission request is "never muted" and "always on", because it is a safety label. The owner asked for "one switch per note kind ... permission line". Turning it off would hide the label that says what a permission is about to do. This spec lists it as a switch and, until the owner says, draws it **on and locked**, with the line "Always on: it tells you what a permission would do" (today's behaviour); if the owner wants a real switch, it is a stored `sidekick.explain` (default on), a change to `shouldShow` and a fixture in `sidekick-core.js`, and a short warning under the switch when it is off.
2. **Where the companion's settings live** (memory, see my sessions, per-tool Ask first, computer use, allowed folders). The chat spec says "Settings → Companion". The six pages have no such page. This spec reserves a fifth tab "Companion" on AI and chat (Call 9) and builds none now. The owner can instead put them on the Sidekick tab, or a seventh page.
3. **For the chat spec being amended:** it should say "Settings → AI and chat" where it says "Settings → AI" and "Settings → Companion", and the OpenAI-plan and Gemini rows named here ("Coming with the new chat") are what its F3 phase turns on. Using a ChatGPT subscription through the Codex CLI from another app should be checked against OpenAI's terms before that row goes live; the owner may want that in the chat spec.

## Owner's answers (2026-10-17)

1. **Permission line: always on, shown as a locked switch** with one line saying why (it is the safety label; F1's "never muted" rule holds). No `sidekick.explain` key is added.
2. **Companion settings: a fifth tab "Companion" on AI and chat** (call 9 stands); hidden until the rebuilt chat ships.
3. **Chat spec wording:** renamed to "Settings → AI and chat" (and "→ Companion" tab) there; the terms check was done (see the chat spec, call 10).
4. **Plan rows are named by provider:** "Use my Claude plan", "Use my OpenAI plan", "Use my Google plan" (not "ChatGPT plan"), each with the line "Runs your own installed app, signed in by you. NotchMeow never sees your login." and no company logos.

The owner approved this design on 2026-10-17 (option B and the answers above).
5. **No "Use my Google plan" row** (owner, after the terms check): Your AI lists the Claude plan, the OpenAI plan, API keys (Google included, on the Keys tab) and local models.

## Owner's answers for Windows and Linux (2026-10-18)

Asked when the Windows/Linux plan was reviewed; they widen "Windows and Linux" above for that platform only.

6. **Light mode on Windows and Linux: yes, now.** Windows/Linux Settings follows the system's light or dark appearance (`prefers-color-scheme`), like the Mac's Settings. The light colours mirror the Mac Settings' light look (the system colours `SettingsColors` resolves to, written as tokens), and every pair of text and background meets the same contrast floor the Mac's `test-settings-contrast.sh` checks. Only the Settings window changes: the island and the cats keep their own colours. Checkpoint pictures are drawn in dark and light, as on the Mac.
7. **Agent switches on Windows and Linux: yes, now.** Agents → "Where you code" gets an on/off switch per agent pill, as on the Mac, with the same four-slot rule shared with the AI and service pills and the same "N of 4 slots used" line on General. Claude Code stays always on (the main pill). The switch is stored as the agent's pill id in the existing `activeIntegrations` list, exactly as on the Mac (owner approved 2026-10-18), so no new key is added; the default list holds no agent, which keeps today's behaviour for existing users: an agent that already shows when used keeps showing. An agent switched off follows the Mac's rule for a hidden pill, and its hook requests are never blocked by the switch (the relay still answers at once).
