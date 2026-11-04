#!/usr/bin/env bash
# Where the app calls the pure rules of the "upstream fixes and island quality of life" plan (U1), pinned as source text: the crash fix, Open on hover and the wing, the permission card's click guard, the
# question card's descriptions, the outside click's monitor (only while expanded) and the hover glow (only while hovered). Each line is a check that fails, naming itself, when the text is gone.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=NotchBuddy/Sources/App
pass=0; fail=0
has()  { if grep -qF -- "$3" "$APP/$2"; then pass=$((pass + 1)); echo "✓ $1"; else fail=$((fail + 1)); echo "✗ $1: [$3] not found in $2"; fi; }
hasnt(){ if grep -qF -- "$3" "$APP/$2"; then fail=$((fail + 1)); echo "✗ $1: [$3] must not be in $2"; else pass=$((pass + 1)); echo "✓ $1"; fi; }

# The crash fix (upstream d05f22b): the one-hour diff timer runs on the main queue, never on a global queue.
has   "diff timer on the main queue"            AppState.swift "DispatchQueue.main.asyncAfter(deadline: .now() + 3600, execute: work)"
hasnt "no global-queue diff timer"              AppState.swift "DispatchQueue.global().asyncAfter(deadline: .now() + 3600"

# The permission card's click guard.
has   "the buttons take clicks only after the guard" IslandViewContent.swift ".allowsHitTesting(takesClicks)"
has   "one sleep per request"                   IslandViewContent.swift ".task(id: approval?.token)"
has   "the guard's own duration"                IslandViewContent.swift "Task.sleep(for: ApprovalClickGuard.duration)"
has   "a request carries its token"             IslandTypes.swift "var token = UUID()"

# The question card: descriptions, and the island's height.
has   "descriptions list the options"           IslandViewContent.swift "} else if item.hasDescriptions {"
has   "the island follows the question"         IslandWindowController.swift "if view == .question, let h = QuestionLayout.height"
has   "the height is written with the question" AppState.swift "QuestionLayout.height = pendingQuestion?.estimatedIslandHeight"
has   "the panel is tall enough"                IslandWindowController.swift "let panelH: CGFloat = 560"

# Open on hover: the state machine is fed by the poll, which already honours the wing and the 0 % rule.
has   "the setting reaches the state machine"   IslandWindowController.swift "fsm.openOnHover = state.openOnHover"
has   "…and follows the switch"                 IslandWindowController.swift "state.\$openOnHover.sink"
has   "Close after reaches the state machine"   IslandWindowController.swift "state.\$autoCloseInterval.sink"
# The poll's order is the shipped one (decided in review: the dwell's open is asynchronous, so nothing needs the pointer recorded earlier, and with the switch off nothing may change).
has   "the poll feeds the state machine first"  IslandWindowController.swift "if inIsland && !wasInIsland {"
has   "…and records the pointer after it"       IslandWindowController.swift "        wasInIsland = inIsland || wardrobeMenuOpen"
hasnt "no earlier copy of the pointer"          IslandWindowController.swift "previouslyInIsland"
has   "a click is an interaction"               IslandWindowController.swift "self.fsm.userInteracted()"
has   "the wing still takes the pointer away"   IslandWindowController.swift "let inIsland = hoverRect.contains(local) && !wing.passThrough || state.shelfHoldsIsland"
has   "the dwell is one one-shot work item"      IslandStateMachine.swift "armHoverOpen(hoverDwell, item)"
hasnt "no second timer or monitor for hover"    IslandStateMachine.swift "Timer.scheduledTimer"
has   "a question, a pin or the menu holds hover" IslandWindowController.swift "(self?.wardrobeMenuOpen ?? false) }"
# The poll's order is pinned by position: the state machine hears of the enter first, then the leave, and the pointer is recorded last. A presence check alone would pass if the record moved up.
inorder() {   # inorder <name> <file> <first> <second>: the first text's first line comes before the second's
    local a b
    a="$(grep -nF -- "$3" "$APP/$2" | head -1 | cut -d: -f1)"; b="$(grep -nF -- "$4" "$APP/$2" | head -1 | cut -d: -f1)"
    if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then pass=$((pass + 1)); echo "✓ $1"; else fail=$((fail + 1)); echo "✗ $1: [$3] ($a) must come before [$4] ($b) in $2"; fi
}
inorder "the enter reaches the machine before the record" IslandWindowController.swift "            fsm.mouseEntered()" "        wasInIsland = inIsland || wardrobeMenuOpen"
inorder "the leave reaches the machine before the record" IslandWindowController.swift "            fsm.mouseLeft()" "        wasInIsland = inIsland || wardrobeMenuOpen"

# The permission card's CPU: nothing the island keeps mounted but does not show asks for frames (measured with scripts/measure-island-cpu.sh: every tick is a pass of the island's whole graph).
has   "a ticker shimmer ticks only while shown"  IslandViewContent.swift "TimelineView(.animation(paused: !ticking && !visible))"
has   "…and keeps ticking through its fade-out"  IslandViewContent.swift "try await Task.sleep(for: .milliseconds(600))"
has   "…and the rows tell it when"               IslandViewContent.swift "TickerShimmerText(text: text, visible: shimmerOpacity > 0)"
has   "…and the file rows too"                   IslandViewContent.swift "TickerShimmerText(text: dp.filename, visible: shimmerOpacity > 0)"
has   "the upload bar ticks only during an upload" IslandViewContent.swift "TimelineView(.animation(paused: state.uploadStartTime == nil))"

# The outside click: one global monitor, installed only while the island is expanded.
has   "the monitor follows the mode"            IslandWindowController.swift "syncOutsideClickMonitor(expanded: mode == .expanded)"
has   "installed only when expanded"            IslandWindowController.swift "if expanded, outsideClickMonitor == nil {"
has   "removed when it leaves expanded"         IslandWindowController.swift "NSEvent.removeMonitor(monitor)"
has   "the rule decides"                        IslandWindowController.swift "IslandOutsideClick.shouldFold(context)"
has   "pinned is asked"                         IslandWindowController.swift "pinned: state.isPinned,"
has   "a waiting decision or hold is asked"     IslandWindowController.swift "held: decisionWaiting || fsm.isHeldOpen?() == true,"
has   "typing in the chat is asked"             IslandWindowController.swift "typing: state.view == .prompt && islandPanel.isKeyWindow && islandPanel.firstResponder is NSTextInputClient,"
if [ "$(grep -c 'addGlobalMonitorForEvents(matching: \[.leftMouseDown, .leftMouseUp, .rightMouseDown' "$APP/IslandWindowController.swift")" = 1 ]; then pass=$((pass + 1)); echo "✓ exactly one outside-click monitor"; else fail=$((fail + 1)); echo "✗ exactly one outside-click monitor"; fi

# The island's big cats redraw at most 60 times a second (owner's decision of 2026-10-15): one pacing constant, both canvases use it. The launch greeting joined them after a recording of it stuttered on a 120 Hz display (see below). The desktop cat's pacer, the file catch and the kittens are not touched.
has   "one pacing constant for the big cats"    BotCanvasView.swift "static let minimumInterval: TimeInterval = 0.016"
has   "the main big cat uses it"                BotCanvasView.swift "TimelineView(.animation(minimumInterval: BigCatPacing.minimumInterval, paused: state.mode == .hidden))"
has   "cat 2 (Two cats mode) uses it"           PairCatViews.swift "TimelineView(.animation(minimumInterval: BigCatPacing.minimumInterval, paused: state.mode == .hidden))"
# The launch greeting too: at the display's own 120 Hz its Canvas re-renders the island's whole layer twice as often, and the main thread blocks waiting for a free surface (RenderBox's image queue) as soon as the
# WindowServer is busy (a screen recording): late frames and doubled steps while the cat slides. Capped at 60 Hz it is steady. Its pose stays a function of the timeline's date.
has   "the launch greeting uses it"             GreetingCanvasView.swift "TimelineView(.animation(minimumInterval: BigCatPacing.minimumInterval)) { timeline in"

# The hover glow: in the tree only while shown; the poll writes the hover only when it changes; the switch is stored.
has   "the glow is in the tree only while shown" IslandRootView.swift "let glowShown = IslandGlow.isShown(enabled: state.hoverGlow"
has   "...inside an if on that value"            IslandRootView.swift "                if glowShown {"
has   "the glow is framed to the island, not the panel" IslandRootView.swift "IslandGlowView(shape: IslandShape(width: shownWidth, height: islandHeight, cornerRadius: cornerRadius, topRadius: islandTopRadius, openTop: true))"
has   "the glow's outline is left open at the top" IslandRootView.swift "if !openTop { p.closeSubpath() }"
has   "...at the island's own size"              IslandRootView.swift "                        .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)"
has   "...and follows the swooshed-in island (Task 14)" IslandRootView.swift "                        .offset(x: (islandWidth - shownWidth) / 2)"
has   "...and its shape follows the fold on the swoosh's spring" IslandRootView.swift "                        .animation(swoosh, value: state.wingYielded)"
has   "the poll writes the hover on change only" IslandWindowController.swift "if state.islandHovered != pointerOver { state.islandHovered = pointerOver }"
has   "the switch is stored"                     AppState.swift "UserDefaults.standard.set(hoverGlow, forKey: IslandGlow.defaultsKey)"
has   "the switch is in Settings"               SettingsGeneralPage.swift 'SwitchRow("Hover glow", help:'
has   "…and it is bound to the stored value"  SettingsSections.swift 'hoverGlow: $state.hoverGlow'
hasnt "the glow never runs a timer of its own"  IslandGlowView.swift "Timer."
has   "Reduce Motion pauses the clock"          IslandGlowView.swift "paused: reduceMotion"

# The Claude Code pill's label (the pill's ID stays integration_claude).
has   "the catalog names the pill Claude Code"  PillCatalog.swift 'id: "integration_claude",  name: "Claude Code"'
hasnt "no VS Code name in the catalog"          PillCatalog.swift 'name: "VS Code"'
hasnt "the pill never shows a fixed VS Code label" IslandViewContent.swift '? "VS Code" : task.name'
has   "the pill shows Claude Code"              IslandViewContent.swift 'task.id == "integration_claude" ? "Claude Code" : task.name'

# The Claude Desktop pill (agent_claude-desktop, a frozen ID).
has   "the catalog declares the pill"           PillCatalog.swift 'id: "agent_claude-desktop", name: "Claude App", color: "#E3A857"'
has   "its session subtitle"                    PillCatalog.swift 'case "agent_claude-desktop": return "Claude App"'
has   "the relays tag the entrypoint"           HookServer.swift "os.environ.get('CLAUDE_CODE_ENTRYPOINT') == 'claude-desktop'"
hasnt "no transient pill is named for the desktop app" HookServer.swift "HookOrigin.desktopPill ? PillCatalog"
has   "the pill's jump still knows the frozen ID" AgentTarget.swift "case HookOrigin.desktopPill:"
has   "the finished card offers Open Claude"    IslandViewContent.swift 'PrimaryButton("Open Claude")'
has   "the card's button follows the session's host" IslandViewContent.swift "if let pillId = state.focusTask?.id, state.pillRunsInClaudeApp(pillId) {"
has   "nothing to install"                      IslandViewContent.swift "return true   // nothing to install"
has   "the sidekick names it"                   SidekickText.swift 'case "agent_claude-desktop": return "Claude App"'

# A session from the Claude app is Claude Code's: its tag routes to the Claude Code pill, its host is the app, its requests are answered "ask" with no card, and its tap opens the app.
has   "a desktop session routes to Claude Code" HookOrigin.swift "if isDesktop(rawAgent: rawAgent) { return .claude }"
hasnt "no 'Claude Desktop' name left in the notes" HookOrigin.swift 'return "Claude Desktop"'
has   "its session's host is the Claude app"    HookServer.swift "state.noteHost(agentId, session: sessionId, HookOrigin.hostBundleId(rawAgent: rawAgent, termProgram: termProgram, bundleId: bundleId))"
has   "a desktop-tagged request is answered ask at once" HookServer.swift "if HookOrigin.answersAskAtOnce(route: route, rawAgent: rawAgent) {"
has   "its tap opens the Claude app by its bundle ID" AgentTarget.swift "if case .app(let id) = host, id == HookOrigin.desktopBundleId"
has   "Settings does not offer the Claude App pill" PillCatalog.swift "pills.filter { \$0.id != HookOrigin.desktopPill }"

# A wing never opens the island on hover (Task 14): the pointer on either wing is a hover-only hold, and coming off a wing into the notch zone re-arms the dwell. The click, the love emote and the cat's wake use `inIsland`, untouched.
has   "the controller keeps whether the pointer is on a wing" IslandWindowController.swift "private var pointerOnWing = false"
has   "...from the wing rules' own zone, only while they are active" IslandWindowController.swift "pointerOnWing = wingActive && wings.zone(of: local) != nil"
has   "the hover hold includes the wing"         IslandWindowController.swift "(self?.pointerOnWing ?? false) || (self?.wardrobeMenuOpen ?? false) }"
has   "coming off a wing re-arms the dwell"     IslandWindowController.swift "if inIsland && wasInIsland && wasOnWing && !pointerOnWing { fsm.hoverResume() }"
has   "the machine's resume is the dwell's own arming" IslandStateMachine.swift "func hoverResume() {"
inorder "the wing flag is written before the machine hears of the enter" IslandWindowController.swift "        pointerOnWing = wingActive && wings.zone(of: local) != nil" "            fsm.mouseEntered()"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
