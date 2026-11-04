# Mac QA session: the brief

The main session sends this brief to a fresh worktree chat session after each Mac tester build (`scripts/release.sh <version> --tester`) and before the owner's own check. The session drives the tester build with scripted events, takes screenshots and CPU readings, and reports. It judges what a script and a screenshot can show; it cannot judge sounds or feel, and the owner's own check of the same zip is the last word. Design: `docs/superpowers/specs/2026-10-08-release-prep-design.md`, section 6.

## How the main session starts it

1. **Setup and stop.** Start a worktree chat session on `notchmeow/rebrand` (or the branch the zip was built from). Its first prompt only sets up:

   > Read `CLAUDE.md`, `ARCHITECT.md` and `docs/QA-MAC.md`. Reply "ready" and stop. Do not start any step.

2. **Model.** Once the owner starts it, set that session to Haiku 5.5 at high effort (`set_session_model`, `set_session_effort`): driving the app and judging screenshots is visual checking, not a Sonnet trigger.
3. **Go.** Send the next message:

   > Run `docs/QA-MAC.md` for NotchMeow VERSION. The zip is `/tmp/notchmeow-release-VERSION/NotchMeow-VERSION-mac.zip`, with its `.sha256` and `NOTES.txt` beside it. The owner has approved your screen control for NotchMeow and System Settings. Report in the format the brief gives.

   Replace VERSION with the version (for example 0.9.0). The owner approves the session's access to NotchMeow and System Settings when it asks for it.

## The rules

These are the spec's, section 6, plus the rules every session here follows.

- **The one exception.** The owner lifted "never launch NotchMeow" for this session only, on 2026-10-08. You may launch, drive and quit **the tester build you install in step 2**, and nothing else. Every other rule stays.
- **Scripted events only.** You drive the app with the payloads below, piped into the `nm-hook` relay the way Claude Code pipes them, and with `scripts/fake-subagent-events.py` and `scripts/fake-sidekick-events.py`. You never install hooks, you never write to `~/.claude`, `~/.gemini` or `~/.codex`, and you never run the real `claude`, `gemini` or `codex`.
- **Real permissions are never touched.** You click Allow, Deny or an answer only on a request **you sent yourself**. Every payload below is marked as yours: its `session_id` starts with `qa-` (the demo script's is `S1`), its `cwd` is under `/tmp/notchmeow-qa` (the demo script's is `/tmp/notchmeow-demo`), and its command or question text starts with `NM-QA` (the demo script's is `echo kittens`). The sidekick's payloads (`scripts/fake-sidekick-events.py`) are marked differently: the session id starts with `fake-sidekick`, the cwd is `/tmp/notchmeow-fake-sidekick` (the project the sidekick names is `notchmeow-fake-sidekick`), and the prompt, the loop commands and the stop message carry `NM-FAKE`; its risk request is marked only by its command, `rm -rf ~/NM-FAKE-build`. Before you click, read the card: if it does not show your marker, do not click. Take a screenshot and report it. The QA session never clicks Allow or Always on any of its cards.
- **macOS prompts are never answered.** If macOS shows a permission prompt (Keychain, Automation, Accessibility, Local Network) take a screenshot, do not click it and do not type a password, and report it with the words it shows. A Keychain prompt is expected after an update: an ad hoc build's identity changes with every build.
- **Never click anything in Settings that installs, removes or writes hooks or keys.** The only Settings you touch are Settings → Cat (a coat, the display mode), and you put both back, and Settings → Sidekick → Unmute on a note your own dismissals muted (step 14). The Desktop switch in that section you only read (step 12 and step 14), never click: the desktop cat goes out and home from its menu-bar item and from ⌃⌥D, which you start yourself.
- No pushes, no commits, no downloads, no installs. Nothing leaves the Mac. Use `trash`, never `rm -rf`, for anything you remove. Put your files in `/tmp/notchmeow-qa-VERSION/`.
- If a command is refused by a permission prompt, stop and report it. Do not look for a way round.

## Step 0: set up

This step only reads the machine and writes files under `/tmp/notchmeow-qa-VERSION/`; it touches no app and no configuration, so the hooks check of step 1 is still the first thing that looks at anything of NotchMeow's.

```bash
VERSION=0.9.0   # the version you were given
ZIPDIR=/tmp/notchmeow-release-$VERSION
QA=/tmp/notchmeow-qa-$VERSION
mkdir -p "$QA/shots" "$QA/payloads"
RELAY="$HOME/Library/Application Support/NotchMeow/nm-hook"
shot() { screencapture -x -m "$QA/shots/$1.png" && echo "$QA/shots/$1.png"; }   # the main display, to a file
sw_vers; uname -m; xcode-select -p
cat "$ZIPDIR/NOTES.txt"
git rev-parse HEAD   # from the root of your worktree
```

Note the macOS version, the chip, and the branch and commit that `NOTES.txt` records against this worktree's `HEAD`. `xcode-select -p` must print a path: without it the relay does nothing (it never blocks Claude Code, so it stays silent). Take every screenshot with `shot`: screen-control screenshots can leave out the island, a borderless panel of a menu-bar app, so the 0.9.0 run first reported a missing island that `shot` showed was there. Use screen control only for clicks and keys. If `screencapture` is refused, stop and report it.

Write the payloads once. Every one carries your marker.

```bash
cat > "$QA/payloads/session-start.json" <<'JSON'
{"hook_event_name":"SessionStart","session_id":"qa-1","cwd":"/tmp/notchmeow-qa","term_program":"vscode","source":"startup"}
JSON
cat > "$QA/payloads/prompt.json" <<'JSON'
{"hook_event_name":"UserPromptSubmit","session_id":"qa-1","cwd":"/tmp/notchmeow-qa","term_program":"vscode","prompt":"NM-QA: say hello"}
JSON
cat > "$QA/payloads/tool-pre.json" <<'JSON'
{"hook_event_name":"PreToolUse","session_id":"qa-1","cwd":"/tmp/notchmeow-qa","term_program":"vscode","tool_name":"Bash","tool_input":{"command":"echo NM-QA step"}}
JSON
cat > "$QA/payloads/tool-post.json" <<'JSON'
{"hook_event_name":"PostToolUse","session_id":"qa-1","cwd":"/tmp/notchmeow-qa","term_program":"vscode","tool_name":"Bash","tool_input":{"command":"echo NM-QA step"}}
JSON
cat > "$QA/payloads/approval.json" <<'JSON'
{"hook_event_name":"PermissionRequest","session_id":"qa-1","cwd":"/tmp/notchmeow-qa","term_program":"vscode","tool_name":"Bash","tool_input":{"command":"echo NM-QA-APPROVAL"}}
JSON
cat > "$QA/payloads/question.json" <<'JSON'
{"hook_event_name":"PreToolUse","session_id":"qa-1","cwd":"/tmp/notchmeow-qa","term_program":"vscode","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"NM-QA: which cat is the cutest?","header":"NM-QA","multiSelect":false,"options":[{"label":"Shrimpy","description":"the white one"},{"label":"Momo","description":"the dark one"}]}]}}
JSON
cat > "$QA/payloads/stop.json" <<'JSON'
{"hook_event_name":"Stop","session_id":"qa-1","cwd":"/tmp/notchmeow-qa","term_program":"vscode","last_assistant_message":"NM-QA done."}
JSON
cat > "$QA/payloads/session-end.json" <<'JSON'
{"hook_event_name":"SessionEnd","session_id":"qa-1","cwd":"/tmp/notchmeow-qa","term_program":"vscode"}
JSON
cat > "$QA/payloads/agent-start.json" <<'JSON'
{"hook_event_name":"SessionStart","session_id":"qa-2","cwd":"/tmp/notchmeow-qa-agent","nm_agent":"qa-agent"}
JSON
cat > "$QA/payloads/agent-work.json" <<'JSON'
{"hook_event_name":"PreToolUse","session_id":"qa-2","cwd":"/tmp/notchmeow-qa-agent","nm_agent":"qa-agent","tool_name":"Bash","tool_input":{"command":"echo NM-QA agent"}}
JSON
cat > "$QA/payloads/agent-stop.json" <<'JSON'
{"hook_event_name":"Stop","session_id":"qa-2","cwd":"/tmp/notchmeow-qa-agent","nm_agent":"qa-agent","last_assistant_message":"NM-QA agent done."}
JSON
cat > "$QA/payloads/terminal-start.json" <<'JSON'
{"hook_event_name":"SessionStart","session_id":"qa-3","cwd":"/tmp/notchmeow-qa-terminal","term_program":"Apple_Terminal","bundle_id":"com.apple.Terminal","source":"startup"}
JSON
cat > "$QA/payloads/terminal-work.json" <<'JSON'
{"hook_event_name":"PreToolUse","session_id":"qa-3","cwd":"/tmp/notchmeow-qa-terminal","term_program":"Apple_Terminal","bundle_id":"com.apple.Terminal","tool_name":"Bash","tool_input":{"command":"echo NM-QA terminal"}}
JSON
cat > "$QA/payloads/terminal-stop.json" <<'JSON'
{"hook_event_name":"Stop","session_id":"qa-3","cwd":"/tmp/notchmeow-qa-terminal","term_program":"Apple_Terminal","bundle_id":"com.apple.Terminal","last_assistant_message":"NM-QA terminal done."}
JSON
ls "$QA/payloads"
```

A fire-and-forget event is `"$RELAY" < "$QA/payloads/<name>.json"`. The approval and the question are different: the relay holds the connection open until you answer in the island, then prints the answer. **Start those two with the Bash tool's `run_in_background` option**, so they keep waiting while you take screenshots, and read their output file afterwards.

## Step 1: hooks first

Before anything else, check that no NotchMeow hooks are installed. Count lines, never print the file (it may hold other settings).

```bash
n=$(grep -ciE 'nm-hook|notchmeow' "$HOME/.claude/settings.json" 2>/dev/null || true)
echo "NotchMeow hook lines in ~/.claude/settings.json: ${n:-0}"
```

`0` is expected: no hooks are installed on the owner's Mac today. **If it is not 0, stop here and report. Change nothing.** Also stop if a NotchMeow is already running: `pgrep -lx NotchMeow` must print nothing. It would be the owner's own, and you must not quit it.

## Step 2: install

```bash
cd "$ZIPDIR" && shasum -a 256 -c "NotchMeow-$VERSION-mac.zip.sha256"
ls -d /Applications/NotchMeow.app 2>/dev/null && /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Applications/NotchMeow.app/Contents/Info.plist
```

The checksum must say `OK`. If an app is already in `/Applications`, note its version and move it to the Trash (`trash /Applications/NotchMeow.app`); none is installed today. Then:

```bash
ditto -x -k "$ZIPDIR/NotchMeow-$VERSION-mac.zip" /Applications
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Applications/NotchMeow.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" /Applications/NotchMeow.app/Contents/Info.plist
codesign --verify --deep --strict /Applications/NotchMeow.app && echo "signature ok"
lipo -archs /Applications/NotchMeow.app/Contents/MacOS/NotchMeow
```

The version must be `VERSION`, the signature must verify, and the chips must list `arm64` and `x86_64`. `ditto` leaves no quarantine mark, so macOS will not show its "Open Anyway" step here: that step is the owner's own check.

## Step 3: launch, and the greeting

Take a first screenshot, then launch and photograph the first seconds: the island opens by itself on the greeting.

```bash
shot 01-before
open /Applications/NotchMeow.app
for i in 1 2 3 4 5 6; do shot "02-greeting-$i"; sleep 0.4; done
sleep 4
pgrep -nx NotchMeow | tee "$QA/pid"
ls -l "$RELAY"
```

`pid` is the process you started. **Quit it later by this process ID only.** The app writes its relay (`nm-hook`) and its socket into `~/Library/Application Support/NotchMeow/` when it starts, so `ls` must show the file. Note the screen: the pointer must stay away from the notch for the rest of the session unless a step says otherwise.

Check: the greeting plays (the island opens, a cat greets, it folds), nothing is cut off, no error dialog. Screenshots `02-greeting-1` to `-6`.

## Step 4: a session in the island

```bash
"$RELAY" < "$QA/payloads/session-start.json"; sleep 1
"$RELAY" < "$QA/payloads/prompt.json"; sleep 1
"$RELAY" < "$QA/payloads/tool-pre.json"; sleep 2
shot 03-session-compact
```

Check: the compact island shows the cat at work, not idle (with several agents the others sit in the grid on its right). Click once on the island's black body, away from any cat or button (a hover never opens the compact island: it only keeps it from hiding), wait 2 s for the overview, then `shot 04-session-open`: the session is listed under the project name `notchmeow-qa`. Move the pointer away. Check: the step row reads `Runs · echo NM-QA step`; copy what you see into the report.

**The same from a terminal.** Claude Code in Terminal, iTerm, Ghostty or Warp reaches the island just as it does from VS Code (the payload says `term_program` `Apple_Terminal`, not `vscode`):

```bash
"$RELAY" < "$QA/payloads/terminal-start.json"; sleep 1
"$RELAY" < "$QA/payloads/terminal-work.json"; sleep 2
```

Click once on the island's black body, away from any cat or button, as in step 4, and wait 2 s for the overview. Then:

```bash
shot 04b-terminal-session
"$RELAY" < "$QA/payloads/terminal-stop.json"; sleep 1
```

Check: the compact notch shows the cat at work again, and the open overview lists `notchmeow-qa-terminal` with the step row `Runs · echo NM-QA terminal`. The two sessions share the Claude Code pill (labelled "VS Code"), so the project name is the last session's. If nothing shows, the terminal session was ignored: that is a FAIL, not a note.

## Step 5: an approval, which you answer

```bash
"$RELAY" < "$QA/payloads/approval.json" > "$QA/approval.out" 2>&1
```

Run that with `run_in_background`. The island opens by itself on the permission card. `shot 05-approval`, and read the card: it must say "needs permission" and show `echo NM-QA-APPROVAL`. **Only then** click **Allow** with screen control, `shot 06-approval-answered`, and read the answer:

```bash
cat "$QA/approval.out"
```

Expected: `{"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}}`. Check that the island goes back to where it was.

## Step 6: a question, which you answer

```bash
"$RELAY" --ask < "$QA/payloads/question.json" > "$QA/question.out" 2>&1
```

Run that with `run_in_background`. The island opens on "Claude Code is asking" with the question `NM-QA: which cat is the cutest?` and two choices. `shot 07-question`, then click **Shrimpy**, `shot 08-question-answered`, and read the answer:

```bash
cat "$QA/question.out"
```

Expected: a `permissionDecision` of `allow` and an `answers` object with `Shrimpy` for the question. Do not click "Reply in terminal".

## Step 7: kittens arriving and leaving

The demo script sends a subagent's whole life (`tests/fixtures/mac/subagent-scenarios.json`, scenario `life`: two subagents start, one searches, one waits on an approval, one stops, then the parent stops). `--speed 0.5` makes it twice as slow, so you can photograph it. Its approval is a request of its own, marked by the project `notchmeow-demo` and the command `echo kittens`: answer it with **Allow** when it appears.

```bash
python3 scripts/fake-subagent-events.py --scenario life --speed 0.5 > "$QA/life.out" 2>&1
```

Run that with `run_in_background` from the worktree's root, and watch `"$QA/life.out"` for the step that is running. Take `shot 09-kittens-start` after the second subagent starts (two kittens under the cat), `shot 10-kittens-approval` while the second one waits on the approval (read the card first: `echo kittens`, then Allow), `shot 11-kittens-one-left` after the first one stops, and `shot 12-kittens-gone` after the parent's stop. Check: the kittens arrive one at a time, the waiting one shows it waits, a stopped one blinks and leaves, and none stays after the parent's stop. `cat "$QA/life.out"` ends without an error line (`could not reach` means the app is not listening: report it).

## Step 8: the three display modes

Two agents make the modes differ. Start a second one, then open Settings from the NotchMeow item in the menu bar (Settings…) and go to the Cat section.

```bash
"$RELAY" < "$QA/payloads/session-start.json"; "$RELAY" < "$QA/payloads/tool-pre.json"
"$RELAY" < "$QA/payloads/agent-start.json"; sleep 1; "$RELAY" < "$QA/payloads/agent-work.json"
```

Write down the settings you find before you change any (`shot 13-settings-cat-start`): the Display mode, the Main cat's coat and the motion style. In Settings → Cat → Display pick **One cat**, **A cat for each agent**, then **Two cats**. For each, look at the small live picture in Settings and at the island's compact notch (move the Settings window if it covers the notch), and take `shot 14-mode-one`, `shot 15-mode-per-agent`, `shot 16-mode-two`. Check: the picture and the real notch agree; in A cat for each agent the second agent has a cat of its own (the list "Cats for your agents" names `qa-agent`); in Two cats a second cat appears beside the first; nothing overlaps or is cut off.

## Step 9: a coat change

In Settings → Cat → Main cat pick a different coat from the one you wrote down (for example Ginger) and `shot 17-coat-changed`. Check that the notch cat wears it at once. Pick the original coat back and `shot 18-coat-restored`.

## Step 10: Settings → Cat

Scroll through the whole Cat section once, `shot 19-settings-cat-top` and `shot 20-settings-cat-bottom` (more if it is long). Check by screenshot that every control draws, no text is cut off or in French, and the section looks like the rest of Settings. Click only the Main cat's coat and the Display mode controls, and put both back. Read every other control by screenshot only, and do not click it. Put the Display mode back to what it was at the start of step 8, and close Settings.

## Step 11: the ten-minute sleep

Only if Settings → Cat offers a shorter sleep delay for testing; the build offers none today (the cat sleeps after a fixed ten minutes with no agent event). Write `skipped: this build has no shortened sleep timer` in the report and go on.

## Step 12: the desktop cat

The big cat can leave the notch and live on the desktop. It is off by default. This step turns it on and back off, with the menu-bar item and ⌃⌥D only. Keep the pointer where a point says and nowhere else. If a point does not do what it says, take its shot, report it and go on to the next point.

Before point 1, open Settings from the menu bar, go to Cat and read the switch "Cat on the desktop" in the Desktop group, under the Display picker. It must be off. If it is on, report that and skip this step: step 13 checks that the cat is home before it measures.

1. **Out.** Click the NotchMeow item in the menu bar. Its title reads "Cat on the desktop": click it. The cat leaves the notch and lands on the desktop at its spot. Wait 4 s, `shot 21-desktop-out`. Check: the cat sits on the desktop and has left the notch. Open the menu again and read the item: it now reads "Bring the cat home". Close the menu.
2. **Watching.** Move the pointer to the far left of the screen, away from the cat and the notch. Wait 2 s, `shot 22-desktop-watch-left`. Move it to the far right, wait 2 s, `shot 23-desktop-watch-right`. Check: in each the cat's eyes look toward the pointer.
3. **Dragged.** Drag the cat by its head to another empty spot on the desktop. Keep the drop away from the notch (a drop there sends the cat home), away from every window and away from the Dock (a drop on a window attaches it, and this session never attaches anything). Wait 2 s, `shot 24-desktop-dragged`. Check: the cat stays where it was dropped. It does not fly back to point 1's spot and it is not in the notch.
4. **An alert.** Send the approval exactly as in step 5, in the background, with its own output file:

```bash
"$RELAY" < "$QA/payloads/approval.json" > "$QA/desktop-approval.out" 2>&1
```

Run that with `run_in_background`. The cat gives the surprised face, flies into the notch and the island opens on the permission card. Wait 3 s, `shot 25-desktop-alert`. Read the card: it must say "needs permission" and show `echo NM-QA-APPROVAL`. **Only then** click **Allow**, wait 3 s, `shot 26-desktop-alert-answered`. Check: the island goes back as it was, and the cat has flown back to its spot from point 3 (the same place as in `24-desktop-dragged`). Read the answer: `cat "$QA/desktop-approval.out"` must match the expected output of step 5.
5. **Home by double-click.** Double-click the cat by its head. It flies home into the notch. Wait 3 s, `shot 27-desktop-home`. Check: the cat is in the notch, and the island did not open (a double-click never opens it).
6. **Out again with ⌃⌥D.** Press Control, Option and D together. The cat flies out to the spot it had at point 3. Wait 3 s, `shot 28-desktop-out-key`. Check: the cat is at the spot of `24-desktop-dragged`, and the menu-bar item reads "Bring the cat home".
7. **Home from the menu bar.** Click the NotchMeow item and read it: "Bring the cat home". Click it. Wait 3 s, `shot 29-desktop-home-menu`. Check: the cat is in the notch, and the item reads "Cat on the desktop" again.
8. **The switch, at each point.** After points 1, 5, 6 and 7, open Settings from the menu bar, go to Cat and read the Desktop switch by screenshot (move the Settings window if it covers the cat). Close Settings. Never click the switch. Expected: on after point 1 (`30-switch-on-1`), off after point 5 (`31-switch-off-5`), on after point 6 (`32-switch-on-6`), off after point 7 (`33-switch-off-7`). Each one must match whether the cat is out.

Pass: every check above holds and the switch matches at each point.

## Step 13: idle CPU with the island hidden

End your sessions, wait for the island to fold, and measure. The cat is measured twice, out and home.

```bash
"$RELAY" < "$QA/payloads/stop.json"; "$RELAY" < "$QA/payloads/session-end.json"
"$RELAY" < "$QA/payloads/agent-stop.json"
sleep 75
```

Check first that the cat is home: the notch has it and the Desktop switch is off. If it is out, send it home from the menu-bar item (Bring the cat home). Then take it out with ⌃⌥D, leave the pointer where it is, and run:

```bash
sleep 75
shot 34-desktop-idle-out
for i in 1 2 3; do top -l 4 -s 2 -pid "$(cat "$QA/pid")" -stats pid,command,cpu | tail -1; sleep 20; done
```

Then send the cat home from the menu-bar item (Bring the cat home), and measure again with the island hidden and the cat home:

```bash
sleep 75
shot 35-hidden
for i in 1 2 3; do top -l 4 -s 2 -pid "$(cat "$QA/pid")" -stats pid,command,cpu | tail -1; sleep 20; done
```

`top`'s first sample is an average since the process started; the last of its four is the reading. Pass: the island is hidden in `34-desktop-idle-out` and in `35-hidden` (nothing at the notch); the cat is out in `34` and home in `35`; the three readings with the cat out are below 1.0 (under 1 % of a core); and the three with the cat home are below 0.5, which rounds to 0 %. Otherwise report the six readings and what the notch showed.

## Step 15: the sidekick

The sidekick says something useful at task boundaries: a grey line and a High risk badge on a permission card, and a nudge when an agent looks stuck. The lock and the recap, "What's Claude doing?" in the chat and the drop on an agent's own cat need a person at the keyboard (the owner checks those by hand), so this step covers what the relay can send. It uses the owner's script, which never runs `claude`:

```bash
python3 scripts/fake-sidekick-events.py --scenario risk --permission-timeout 60 > "$QA/sidekick-risk.out" 2>&1 &
```

1. **A high-risk request.** The island opens on the permission card for `rm -rf ~/NM-FAKE-build`. Wait 3 s, `shot 36-sidekick-risk`. Check: under the command one grey line (`Deletes NM-FAKE-build and everything inside it.`), an orange `High risk` capsule at the right end of the first row, and Deny, Allow and Always as in step 5. **Click Deny only if the card shows `rm -rf ~/NM-FAKE-build`**, the marker of this request (the card shows the command and the sidekick's line, not the folder or the project). The command is only text on a card and nothing in this script runs it; Deny is the only click. Never click Allow or Always on any card in this session. Wait 3 s.
2. **A loop.** Run `python3 scripts/fake-sidekick-events.py --scenario loop --speed 4`. The fourth identical step opens the island on a note. `shot 37-sidekick-loop`. Check: `Going in circles`, `Claude Code has run the same step 4 times.`, `Not now` and `Show me`. Click `Not now`. The island folds. That is one dismissal of Repeated steps; step 14 unmutes it.
3. **Clean up.** Run `python3 scripts/fake-sidekick-events.py --scenario end`: it ends the fake session.

Pass: every check above holds.

## Step 14: leave it as you found it

Bring the cat home if it is out (the menu-bar item), and check by screenshot in Settings → Cat that the Desktop switch is off. Then quit:

```bash
kill "$(cat "$QA/pid")"; sleep 2; pgrep -lx NotchMeow || echo "NotchMeow has quit"
```

You started that process, and only that one is yours to quit. Leave the tester build installed in `/Applications` for the owner's check. Check that Settings are back as you found them (Display mode, Main cat, and the Desktop switch off). In Settings → Sidekick, under Muted notes, click Unmute for each note your dismissals muted in step 15 (two dismissals mute a kind), and check that the list reads Nothing is muted. List what you left behind: the installed app, and `/tmp/notchmeow-qa-VERSION/` with your files.

## Screenshots

Take them with `shot` (a PNG of the main display in `/tmp/notchmeow-qa-VERSION/shots/`) and look at each with screen control or the file reader before you write it in the report.

| File | It must show |
|---|---|
| `01-before` | the desktop before launch, no NotchMeow |
| `02-greeting-1` to `-6` | the launch greeting, from the first frame on |
| `03-session-compact` | the compact notch with a working session |
| `04-session-open` | the open overview listing `notchmeow-qa` |
| `04b-terminal-session` | the notch with a working session from a terminal (`notchmeow-qa-terminal`) |
| `05-approval`, `06-approval-answered` | the permission card with `echo NM-QA-APPROVAL`, then the island after Allow |
| `07-question`, `08-question-answered` | the question card, then the island after the answer |
| `09-kittens-start` to `12-kittens-gone` | the kittens arriving, waiting, one leaving, and none left |
| `13-settings-cat-start` | the settings you found, before any change |
| `14-mode-one`, `15-mode-per-agent`, `16-mode-two` | the notch and Settings' picture in each display mode |
| `17-coat-changed`, `18-coat-restored` | another coat, then the original |
| `19-settings-cat-top`, `20-settings-cat-bottom` | the Cat section from top to bottom |
| `21-desktop-out` | the cat on the desktop, out of the notch |
| `22-desktop-watch-left`, `23-desktop-watch-right` | the cat's eyes looking toward the pointer at each side |
| `24-desktop-dragged` | the cat where it was dropped, not in the notch |
| `25-desktop-alert`, `26-desktop-alert-answered` | the permission card with `echo NM-QA-APPROVAL`, then the cat back at its spot |
| `27-desktop-home` | the cat in the notch after a double-click, the island not open |
| `28-desktop-out-key` | the cat at its spot after ⌃⌥D |
| `29-desktop-home-menu` | the cat in the notch after Bring the cat home, the item reading Cat on the desktop |
| `30-switch-on-1`, `31-switch-off-5`, `32-switch-on-6`, `33-switch-off-7` | the Desktop switch in Settings → Cat, on while the cat is out and off while it is home |
| `34-desktop-idle-out` | the cat on the desktop and no island at the notch |
| `35-hidden` | no island at the notch, the cat home |
| `36-sidekick-risk`, `37-sidekick-loop` | the permission card with its grey line and badge, and the loop note |

## The report

Your final message is the report. Use this shape.

```text
# Mac QA report: NotchMeow VERSION
Result: PASS | FAIL | BLOCKED (one line: why)
Machine: macOS version, chip. Zip: checksum OK or not. NOTES.txt: branch and commit; this worktree's HEAD. App: version, build number, archs, signature.

| Step | Check | Result | Evidence |
|---|---|---|---|
| 1 | no NotchMeow hooks in ~/.claude/settings.json | PASS or STOPPED | the count |
| 2 | install | | checksum, version, archs, signature |
| 3 | greeting | | screenshots |
| 4 | a session in the island, from VS Code and from a terminal | | the step rows, `04b-terminal-session` |
| 5 | approval answered | | the card text, the contents of approval.out |
| 6 | question answered | | the card text, the contents of question.out |
| 7 | kittens arrive and leave | | |
| 8 | the three display modes | | |
| 9 | a coat change | | |
| 10 | Settings → Cat | | |
| 11 | ten-minute sleep | SKIPPED | no shortened timer |
| 12 | the desktop cat: out, watching, dragged, alert, home, ⌃⌥D, menu, the switch at each point | | the shots 21–33, the card text, the contents of desktop-approval.out |
| 13 | idle CPU, cat out and cat home, island hidden | | the six readings |
| 15 | the sidekick: the risk line and badge, a loop note | | the shots 36 and 37 |
| 14 | quit, settings restored | | |

Anything wrong: a numbered list, worst first. For each: what you did, what you saw, what you expected, and the screenshot file.
Prompts macOS showed: each, with its words, and that you did not answer it.
Not judged: sounds, feel, motion smoothness (the owner's check).
Left behind: the installed app (path, version), the quit state, the files in /tmp/notchmeow-qa-VERSION/.
```

A check you could not run is `BLOCKED`, with the reason. Do not turn a doubt into a `PASS`.
