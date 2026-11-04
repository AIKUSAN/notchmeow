import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { fileURLToPath } from "node:url";
import { code } from "../projects-tests/util.mjs";
import { lineWaits } from "../../src/core/focusaware.ts";

// The page side of focus awareness (Task 3): the hook path that asks the frontmost app, the marks in State, the Projects feed, the stored setting and the Rust
// commands it calls. Pinned as source text; the pure rules are tested in focusaware.test.mjs.
const hooks = code("island/hooks.ts"), main = code("main.ts"), state = code("core/state.ts"), bridge = code("core/bridge.ts");
const rust = (rel) => fs.readFileSync(new URL(`../../src-tauri/src/${rel}`, import.meta.url), "utf8");
const lib = rust("lib.rs"), winRs = rust("platform/windows.rs"), linuxRs = rust("platform/linux.rs");

const takeAt = hooks.indexOf("export function takeHook(");
const handleAt = hooks.indexOf("export function handleHook(");
const takeBody = takeAt > 0 && handleAt > takeAt ? hooks.slice(takeAt, handleAt) : "";
// The gates, the read's race and the mark are stepBackFor's (core/focusaware.ts), a pure function the behaviour tests replay (focusaware.test.mjs).
const focusCore = code("core/focusaware.ts");
const stepAt = focusCore.indexOf("export function stepBackFor(");
const stepBody = stepAt > 0 ? focusCore.slice(stepAt, focusCore.indexOf("\n}\n", stepAt)) : "";

test("registerHookHandlers hands each hook event to takeHook, which decides whether to ask the frontmost app", () => {
  assert.match(hooks, /void onEvent<HookPayload>\("hook", \(payload\) => takeHook\(island, payload\)\);/);
  assert.ok(takeAt > 0 && handleAt > takeAt, "takeHook is declared before handleHook");
});

test("stepBackFor asks for the frontmost app only inside raceForeground, with the wait, after the gates", () => {
  assert.ok(stepBody.length > 0, "stepBackFor is in focusaware.ts");
  const race = stepBody.indexOf("raceForeground(i.read, i.waitMs, i.setTimer, i.clearTimer)");
  assert.ok(race > 0, "the read is raced through raceForeground, with the injected wait and timers");
  assert.doesNotMatch(stepBody, /Bridge|IS_TAURI|window\.|setInterval/, "the page's own read and timers are not named in the pure function");
  const checks = [
    'i.kind === "none"', "!i.enabled", "i.paused", 'p.hook_event_name !== "PermissionRequest"', 'i.route === "chat"',
  ];
  const host = stepBody.indexOf("focusHost(p, i.kind)");
  assert.ok(host > 0, "the session's host is named on this OS");
  for (const c of checks) {
    const at = stepBody.indexOf(c);
    assert.ok(at >= 0 && at < host, `${c} is checked before the host is named`);
    assert.ok(at < race, `${c} is checked before the app is asked`);
  }
});

test("takeHook hands its inputs to stepBackFor (the real read and wait, the pill rule) and calls handleHook once, whatever the outcome", () => {
  assert.match(takeBody, /void stepBackOrNone\(\{/);
  assert.match(takeBody, /kind: State\.foregroundKind,/);
  assert.match(takeBody, /enabled: focusEnabled\(State\.settings\.focusAware\),/);
  assert.match(takeBody, /paused: State\.paused,/);
  assert.match(takeBody, /route: routeHook\(payload, State\.claudeSessions\),/);
  assert.match(takeBody, /read: IS_TAURI \? \(\) => Bridge\.foregroundApp\(\) : \(\) => Promise\.resolve\(devForeground\),/);
  assert.match(takeBody, /waitMs: FOREGROUND_WAIT_MS,/);
  assert.match(takeBody, /now: Date\.now\(\),/);
  assert.match(takeBody, /pillIdOf: pillIdForAgent,/);
  assert.match(takeBody, /\.then\(\(mark\) => \{/);
  assert.equal(takeBody.split("handleHook(").length - 1, 1, "one handleHook call in takeHook");
  assert.match(takeBody, /handleHook\(island, payload, mark \?\? undefined\);/);
  assert.doesNotMatch(takeBody, /setInterval|approvalDecision|\blog\b/);
  assert.doesNotMatch(takeBody, /island\./, "no function of the island is called here");
});

test("the matched call sits in try/catch: a failed step-back is declined by its non-empty request id, with one fixed sentence and nothing else", () => {
  assert.match(takeBody, /try \{\s*handleHook\(island, payload, mark \?\? undefined\);\s*\} catch \(err\) \{/);
  assert.match(takeBody, /if \(mark === null\) throw err;/, "an error of a request that was not stepped back goes on as it did");
  assert.match(takeBody, /if \(typeof payload\.request_id === "string" && payload\.request_id !== ""\) void Bridge\.approvalDecline\(payload\.request_id\);/);
  assert.match(takeBody, /console\.error\("\[notchmeow\] step-back handler failed"\);/);
  const catchAt = takeBody.indexOf("} catch (err) {");
  const catchBody = catchAt > 0 ? takeBody.slice(catchAt, takeBody.indexOf("\n  });", catchAt)) : "";
  assert.ok(catchBody.length > 0 && catchBody.split("\n").length <= 9, "the catch is short");
  assert.doesNotMatch(catchBody, /String\(|message|stack|\bmark\.|foreground|console\.(log|warn|info)/, "no value, error object or foreground name is logged");
});

test("stepBackOrNone turns a rejection or a synchronous throw into no mark, so takeHook's one handleHook still runs with none", () => {
  const at = focusCore.indexOf("export function stepBackOrNone(");
  assert.ok(at > 0, "stepBackOrNone is in focusaware.ts");
  const body = focusCore.slice(at, focusCore.indexOf("\n}\n", at));
  assert.match(body, /try \{\s*return stepBackFor\(i\)\.then\(\(m\) => m, \(\) => null\);\s*\} catch \{\s*return Promise\.resolve\(null\);\s*\}/);
  assert.match(takeBody, /void stepBackOrNone\(\{[\s\S]*?\}\)\.then\(\(mark\) => \{/, "takeHook decides through stepBackOrNone, then one handleHook");
});

test("the mark is built by stepBackFor from the session, the pill rule, the step's words and the clock's now", () => {
  assert.match(stepBody, /return \{\s*sessionId: focusSessionKey\(p\),\s*pillId: i\.pillIdOf\(p\.nm_agent\),\s*host: words,/);
  assert.match(stepBody, /const question = tool === "AskUserQuestion";/);
  assert.match(stepBody, /kind: question \? "question" : "permission",/);
  assert.match(stepBody, /words: question \? null : stepVerb\(tool\),/);
  assert.match(stepBody, /at: i\.now,/);
  assert.match(hooks, /function pillIdForAgent\(nmAgent: unknown\): string \{[\s\S]*?return isClaudeDesktopTag\(raw\) \|\| agent === null \? CLAUDE_ID : `agent_\$\{agent\}`;/);
  assert.doesNotMatch(stepBody, /setInterval|approvalDecision|\blog\b|island\./);
});

test("setDevForeground is the dev server's only foreground branch: it stores the name and sets the kind", () => {
  assert.match(hooks, /export function setDevForeground\(name: string \| null\): void \{\s*devForeground = name;\s*State\.foregroundKind = name === null \? "none" : "windows";\s*\}/);
});

test("handleHook takes the stepBack mark, ends the session's marks before the feed, records the mark, and feeds Projects with its host", () => {
  assert.match(hooks, /export function handleHook\(island: Island, payload: HookPayload, stepBack\?: FocusMark\) \{/);
  assert.match(hooks, /State\.endFocusMarks\(focusSessionKey\(payload\), payload\.hook_event_name \?\? "", payload\.tool_name \?\? ""\);\s*if \(stepBack\) State\.recordFocusMark\(stepBack\);\s*Hub\.sk\?\.hook\(payload\);/);
  const chat = hooks.indexOf("handleChatHook(island, payload);");
  const end = hooks.indexOf("State.endFocusMarks(");
  assert.ok(chat > 0 && chat < end && end < hooks.indexOf("Hub.sk?.hook(payload);"), "after the chat's route, before the Sidekick's feed");
  assert.equal(hooks.split("State.projects.hook(payload, stepBack?.host);").length - 1, 1, "the Projects feed, once, with the step-back's host");
  assert.equal(hooks.split("  State.projects.hook(").length - 1, 1, "and no other spelling of the feed");
  assert.ok(hooks.indexOf("  State.projects.hook(payload, stepBack?.host);") > hooks.indexOf("  Hub.sk?.hook(payload);"), "after the Sidekick's feed");
});

test("the PermissionRequest case declines a stepped-back request first, with nothing shown, played, badged, pinned or stored", () => {
  const at = hooks.indexOf('case "PermissionRequest": {');
  assert.ok(at > 0, "the case is in handleHook");
  const stepAt = hooks.indexOf("if (stepBack) {", at);
  const externalAt = hooks.indexOf("if (isExternalAgent || fromClaudeApp) {", at);
  assert.ok(stepAt > at && stepAt < externalAt, "the step-back block comes before the external-agent decline");
  const block = hooks.slice(stepAt, externalAt);
  assert.match(block, /if \(payload\.request_id\) void Bridge\.approvalDecline\(payload\.request_id\);/);
  assert.match(block, /break;/);
  assert.doesNotMatch(block, /alert\(|reveal\(|Sound\.play|setPillBadge|updateTask|isPinned|upsert\(|ensurePill\(|pendingApproval =/);
});

test("the Settings field is focusAware, on by default, and the page's save keeps it (DEFAULT_SETTINGS spread into State)", () => {
  assert.match(state, /hoverGlow: boolean;\s*(?:\/\*\*[^*]*\*\/\s*)?focusAware: boolean;/);
  assert.match(state, /hoverGlow: true,\s*focusAware: true,/);
  assert.match(state, /settings: Settings = \{ \.\.\.DEFAULT_SETTINGS \};/);
});

test("State holds the boot's foreground kind, the marks, and the dot rule for a pill", () => {
  assert.match(state, /foregroundKind: ForegroundKind = "none";/);
  assert.match(state, /focusMarks: FocusMark\[\] = \[\];/);
  assert.match(state, /recordFocusMark\(mark: FocusMark\): void \{\s*this\.focusMarks = recordMark\(this\.focusMarks, mark\);\s*\}/);
  assert.match(state, /endFocusMarks\(sessionId: string, event: string, tool: string\): void \{\s*this\.focusMarks = endMarks\(this\.focusMarks, sessionId, event, tool\);\s*\}/);
  assert.match(state, /focusDot\(pillId: string, now = Date\.now\(\)\): boolean \{[\s\S]*?showsDot\(markForPill\(this\.focusMarks, pillId, now\) !== null, task\?\.pillBadge != null, this\.pendingApproval\?\.pillId === pillId\)/);
  assert.doesNotMatch(state.slice(state.indexOf("recordFocusMark(mark"), state.indexOf("focusDot(pillId")), /notify\(\)/, "recording a mark does not notify: handleHook does");
});

test("main.ts takes the boot's foreground kind, the import gains takeHook and setDevForeground, and the dev hook is added beside the old one", () => {
  assert.match(main, /if \(boot\) State\.foregroundKind = boot\.foreground;/);
  assert.match(main, /if \(boot\) State\.claudeApp = boot\.claudeApp;\s*if \(boot\) State\.foregroundKind = boot\.foreground;/);
  assert.match(main, /import \{ handleHook, registerHookHandlers, takeHook, setDevForeground, type HookPayload \} from "\.\/island\/hooks";/);
  assert.match(main, /hook: \(payload: HookPayload\) => handleHook\(island, payload\) \};/, "the DEV hook is unchanged");
  assert.match(main, /__nm\.sk = Hub\.sk;\s*if \(import\.meta\.env\.DEV\) Object\.assign\(\(window as unknown as \{ __nm: Record<string, unknown> \}\)\.__nm, \{ take: \(payload: HookPayload\) => takeHook\(island, payload\), foreground: setDevForeground \}\);/);
});

test("bridge.ts: BootInfo carries the foreground kind, and foregroundApp calls foreground_app", () => {
  assert.match(bridge, /claudeApp: boolean;[\s\S]*?foreground: ForegroundKind;/);
  assert.match(bridge, /foregroundApp: \(\) => call<string \| null>\("foreground_app"\),/);
  assert.match(bridge, /import type \{ ForegroundKind \} from "\.\.\/core\/focusaware\.ts";|import type \{ ForegroundKind \} from "\.\/focusaware\.ts";/);
});

test("Rust: foreground_app is registered and logs nothing; Windows compares with the app's own pid; Linux reads with a 40 ms wait; neither watches for focus changes", () => {
  assert.match(lib, /\n\s*foreground_app,\n/);
  const body = /async fn foreground_app\(app: AppHandle\) -> Option<String> \{[\s\S]*?\n\}/.exec(lib)?.[0] ?? "";
  assert.ok(body.length > 0, "the command is in lib.rs");
  assert.doesNotMatch(body, /log::line/);
  assert.match(winRs, /pid == std::process::id\(\)/);
  assert.match(linuxRs, /recv_timeout\(std::time::Duration::from_millis\(40\)\)/);
  for (const src of [winRs, linuxRs]) assert.doesNotMatch(src, /SetWinEventHook|EVENT_SYSTEM_FOREGROUND|XSelectInput/);
});

test("the Sidekick's stuck rules read the ledger with its stepped-back holds: this.ruleView() where a rule is asked, the real snapshot elsewhere", () => {
  const ctl = code("sidekick/controller.ts");
  assert.doesNotMatch(ctl, /stuckStep\(this\.ledger\.snapshot/);
  assert.doesNotMatch(ctl, /nudgeText\(n, this\.ledger\.snapshot|nudgeText\(nudge, this\.ledger\.snapshot/);
  assert.equal(ctl.split("this.ruleView()").length - 1, 6, "six places: dropDueWhileAway, evaluate's loop, its nudgeText, its clock arm, rewordWaiting and stillTrue");
});

test("appenv.ts gives the Sidekick its three focus hooks: a session's mark end, the earliest live end, and the app's redraw at the lapse", () => {
  const env = code("sidekick/appenv.ts");
  assert.match(env, /import \{[^}]*\bmarkForSession\b[^}]*\} from "\.\.\/core\/focusaware\.ts";/);
  assert.match(env, /import \{[^}]*\bliveMarks\b[^}]*\} from "\.\.\/core\/focusaware\.ts";/);
  assert.match(env, /import \{[^}]*\blapseMs\b[^}]*\} from "\.\.\/core\/focusaware\.ts";/);
  assert.match(env, /stepBackEnd: \(id\) => \{ const now = Date\.now\(\); const m = markForSession\(State\.focusMarks, id, now\); return m \? lapseMs\(m\.at, now, now \+ Skew\.ms\) : null; \}/, "one clock read for the mark and its end");
  assert.match(env, /focusLapseAt: \(\) => \{ const now = Date\.now\(\); const ends = liveMarks\(State\.focusMarks, now\)\.map\(\(m\) => lapseMs\(m\.at, now, now \+ Skew\.ms\)\); return ends\.length \? Math\.min\(\.\.\.ends\) : null; \}/);
  assert.match(env, /focusLapsed: \(\) => State\.notify\(\),/);
});

// Task 5: the waiting dot, the compact dots, the note and the Settings row. The Mac's FocusWaitDot, FocusWaitNote and FocusWaitCompactDots are the reference.
const views = code("views/views.ts"), islandSrc = code("island/island.ts"), generalSrc = code("settings/general.ts");
const cssSrc = fs.readFileSync(new URL("../../src/style.css", import.meta.url), "utf8");

test("the pill's key carries the dot, and buildAgentPill draws the dot where the badge is not shown", () => {
  assert.ok(views.includes("`${t.id}:${t.pillBadge ?? \"\"}:${State.focusDot(t.id) ? 1 : 0}`"), "the pill key names the dot");
  assert.ok(views.includes('} else if (State.focusDot(task.id)) pill.append(h("div", { class: "fa-dot" }));'), "the dot after the badge block");
  assert.match(views, /if \(task\.pillBadge\) \{[\s\S]*?pill\.append\(badge\);\s*\} else if \(State\.focusDot\(task\.id\)\)/);
  assert.match(views, /import \{[^}]*\bmarkForPill\b[^}]*\} from "\.\.\/core\/focusaware\.ts";/);
});

test("the ticker card holds the note between the ticker and the second line, and sync shows the note or the second line", () => {
  assert.ok(views.includes('const faNote = h("div", { class: "fa-note" });'));
  assert.ok(views.includes('h("div", { class: "card-body" }, who, ticker.el, faNote, second)'));
  const sec = views.indexOf("second.textContent = two ?"), mk = views.indexOf("const mark = State.focusTask ? markForPill(State.focusMarks, State.focusTask.id, Date.now()) : null;");
  assert.ok(sec > 0 && mk > sec, "the mark is read right after the second line's text");
  assert.ok(views.includes("const showNote = showsNoteOverSecondLine(mark !== null, secondWaiting);"));
  assert.ok(views.includes("faNote.textContent = showNote && mark ? noteText(mark.host, mark.words) : \"\";"));
  assert.ok(views.includes('faNote.style.display = showNote ? "block" : "none";'));
  assert.ok(views.includes('second.style.display = showNote ? "none" : "";'));
  assert.match(views, /import \{[^}]*\bnoteText\b[^}]*\bshowsNoteOverSecondLine\b[^}]*\} from "\.\.\/core\/focusaware\.ts";|import \{[^}]*\bshowsNoteOverSecondLine\b[^}]*\bnoteText\b[^}]*\} from "\.\.\/core\/focusaware\.ts";/);
});

test("the compact grid keys its cells by the dot, and a dotted cell carries a mini dot", () => {
  assert.ok(islandSrc.includes('const key = row.map(({ task }) => `${task.id}:${State.focusDot(task.id) ? 1 : 0}`).join("|");'));
  assert.ok(islandSrc.includes('if (State.focusDot(task.id)) slot.append(h("i", { class: "fa-mini-dot" }));'));
  assert.ok(islandSrc.includes("const slot = createMiniBot(task, 13, cat);"));
});

test("two compact dots are made once beside the grid, placed from the big springs in compact mode only, and shown while the grid shows and their pill waits", () => {
  assert.equal(islandSrc.split('h("span", { class: "fa-compact-dot" })').length - 1, 2, "two dots, made once");
  assert.ok(islandSrc.includes("this.focusDotBig,") && islandSrc.includes("this.focusDotSecond,"), "both appended to the island element");
  assert.ok(islandSrc.includes("this.focusDotBig.style.left = `${this.botCx.value + this.botSize.value * 0.42 - 2.5}px`;"));
  assert.ok(islandSrc.includes("this.focusDotBig.style.top = `${this.botCy.value - this.botSize.value * 0.42 - 2.5}px`;"));
  assert.ok(islandSrc.includes("this.focusDotSecond.style.left = `${this.bot2Cx.value + this.bot2Size.value * 0.42 - 2.5}px`;"));
  assert.ok(islandSrc.includes("this.focusDotSecond.style.top = `${this.bot2Cy.value - this.bot2Size.value * 0.42 - 2.5}px`;"));
  const at = islandSrc.indexOf("private placeFocusDots()");
  assert.ok(at > 0, "the placement is one method");
  const body = islandSrc.slice(at, islandSrc.indexOf("\n  }\n", at));
  assert.ok(body.includes('if (State.mode !== "compact") return;'), "placed only in compact mode");
  assert.ok(islandSrc.includes("this.placeFocusDots();"), "the frame places them as the springs move");
  assert.ok(islandSrc.includes('this.focusDotBig.style.opacity = showGrid && State.cast.big.pill && !State.desktopNotchEmpty && State.focusDot(State.cast.big.pill) ? "1" : "0";'));
  assert.ok(islandSrc.includes('this.focusDotSecond.style.opacity = showGrid && this.pairShown && State.cast.second?.pill && State.focusDot(State.cast.second.pill) ? "1" : "0";'));
});

test("style.css has the focus block at its end: the dot, the mini dot, the compact dot and the note, with no animation", () => {
  const at = cssSrc.indexOf("/* ── Focus awareness: the waiting dot and note ── */");
  assert.ok(at > 0, "the block's title");
  const block = cssSrc.slice(at);
  const rule = (sel) => {
    const m = new RegExp(`${sel.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")} \\{([^}]*)\\}`).exec(block);
    assert.ok(m, `${sel} has a rule in the block`);
    return m[1];
  };
  const dot = rule(".fa-dot"), mini = rule(".fa-mini-dot"), compact = rule(".fa-compact-dot"), note = rule(".fa-note");
  assert.match(dot, /position: absolute;/);
  assert.match(dot, /top: -3px;/);
  assert.match(dot, /right: 3px;/);
  assert.match(dot, /#0b0c0e/);
  assert.match(dot, /var\(--amber\)/);
  assert.match(dot, /pointer-events: none;/);
  assert.match(mini, /top: -2px;/);
  assert.match(mini, /right: -2px;/);
  assert.match(compact, /position: absolute;/);
  assert.match(compact, /opacity: 0;/);
  assert.match(compact, /transition: opacity 0\.25s ease-in-out;/);
  assert.match(compact, /pointer-events: none;/);
  assert.match(block, /#island\.wing-on \.fa-compact-dot \{\s*filter: opacity\(var\(--nm-wing, 1\)\);\s*\}/);
  assert.match(note, /display: none;/);
  assert.match(note, /margin: 0 12px 0 108px;/);
  assert.match(note, /font: 500 11px var\(--font\);/);
  assert.match(note, /color: var\(--amber\);/);
  assert.match(note, /white-space: nowrap;/);
  assert.match(note, /overflow: hidden;/);
  assert.match(note, /text-overflow: ellipsis;/);
  assert.match(block, /\.overview\.two \.fa-note \{\s*margin-left: 147px;\s*\}/);
  assert.doesNotMatch(block, /animation|box-shadow/, "nothing animates and the dot has no shadow");
  assert.doesNotMatch(block, /--nm-state-color/, "the island page has no such token: the block reads --amber");
  const rootAt = cssSrc.indexOf(":root {");
  assert.ok(rootAt >= 0, "style.css has a :root block");
  assert.match(cssSrc.slice(rootAt, cssSrc.indexOf("}", rootAt)), /--amber: #f5a524;/, "--amber is defined on :root, so a missing token cannot pass silently");
});

// Fix round 3: the full wording of cat 2's second line, pinned table by table against views.ts SECOND_LINE. A changed or new phrase fails here until EXPECTED and lineWaits are both updated on purpose.
const EXPECTED = {
  idle: { line: "idle", waits: false }, working: { line: "working", waits: false }, thinking: { line: "thinking", waits: false },
  searching: { line: "searching", waits: false }, approval: { line: "waiting for you", waits: true }, question: { line: "has a question", waits: true },
  error: { line: "hit an error", waits: false }, finished: { line: "finished", waits: false }, ratelimit: { line: "rate limited", waits: false },
  sleeping: { line: "asleep", waits: false }, dizzy: { line: "dizzy", waits: false },
};
test("cat 2's second line: its keys, its full wording and lineWaits agree with the table", () => {
  const body = /const SECOND_LINE: Record<BotStateName, string> = \{([\s\S]*?)\};/.exec(views)?.[1] ?? "";
  const lines = Object.fromEntries([...body.matchAll(/(\w+):\s*"([^"]*)"/g)].map((m) => [m[1], m[2]]));
  assert.deepEqual(Object.keys(lines).sort(), Object.keys(EXPECTED).sort(), "the key set of SECOND_LINE");
  for (const key of Object.keys(EXPECTED)) {
    assert.equal(lines[key], EXPECTED[key].line, `${key}: the wording of its second line`);
    assert.equal(lineWaits(key), EXPECTED[key].waits, `${key}: lineWaits`);
  }
});

test("views.ts sync() computes cat 2's waiting through lineWaits on the state its second line shows, and the note yields to that", () => {
  assert.match(views, /import \{[^}]*\blineWaits\b[^}]*\} from "\.\.\/core\/focusaware\.ts";/);
  const at = views.indexOf("const secondWaiting = Boolean(two?.pill && (State.pendingApproval?.pillId === two.pill || lineWaits(other ? State.shownState(other.state) : undefined)));");
  assert.ok(at > 0, "secondWaiting is the approval pin or the line's own waiting");
  assert.ok(at > views.indexOf("const other = two?.pill"), "after other is read");
  assert.ok(views.includes("const showNote = showsNoteOverSecondLine(mark !== null, secondWaiting);"), "the note's rule takes secondWaiting");
});

// Privacy (focus awareness): the foreground read keeps no record. The name is compared and dropped, so no print, no log and no store on any path it takes.
const rustFn = (src, head) => {
  const at = src.indexOf(head);
  return at >= 0 ? src.slice(at, src.indexOf("\n}\n", at) + 3) : "";
};
const LOGGING = /\blog::|println!|eprintln!|print!|eprint!|dbg!|appendAppLog|tracing::|console\./;
test("privacy: the foreground read prints, logs and keeps nothing: Windows, Linux, the X11 helper it calls, and the Bridge wrapper", () => {
  const winFn = rustFn(winRs, "pub fn foreground_app(");
  const linuxFn = rustFn(linuxRs, "pub fn foreground_app(");
  const x11Fn = rustFn(linuxRs, "fn active_window_class()");
  assert.ok(winFn.length > 0 && linuxFn.length > 0 && x11Fn.length > 0, "the three functions are found");
  assert.match(winFn, /GetWindowThreadProcessId/, "the body is the Windows read, not an empty stub");
  assert.match(x11Fn, /_NET_ACTIVE_WINDOW/, "the body is the X11 read, not an empty stub");
  for (const [name, body] of [["platform/windows.rs foreground_app", winFn], ["platform/linux.rs foreground_app", linuxFn], ["platform/linux.rs active_window_class", x11Fn], ["lib.rs foreground_app", rustFn(lib, "async fn foreground_app(")]]) {
    assert.doesNotMatch(body, /\blog::|println!|eprintln!|dbg!/, `${name} writes nothing`);
  }
  const wrapper = bridge.split("\n").find((l) => l.includes("foregroundApp:")) ?? "";
  assert.ok(wrapper.includes('call<string | null>("foreground_app")'), "the Bridge wrapper is one call");
  assert.doesNotMatch(wrapper, LOGGING, "the Bridge wrapper writes nothing");
});

test("privacy: focusMarks is never written to the settings save, to localStorage or to the console: no line that names it reaches a store", () => {
  const files = [];
  const walk = (dir) => {
    for (const name of fs.readdirSync(dir)) {
      const path = `${dir}/${name}`;
      if (fs.statSync(path).isDirectory()) walk(path);
      else if (name.endsWith(".ts")) files.push(path);
    }
  };
  walk(fileURLToPath(new URL("../../src", import.meta.url)));
  const named = files.flatMap((f) => fs.readFileSync(f, "utf8").split("\n").filter((l) => l.includes("focusMarks")).map((l) => `${f}: ${l.trim()}`));
  assert.ok(named.length >= 3, "the marks are read where the rules need them");
  const sink = /localStorage|sessionStorage|saveSettings|save_settings|persistSettings|JSON\.stringify|console\.|\bfetch\(|invoke\(/;
  for (const line of named) assert.doesNotMatch(line, sink, `no store or log: ${line}`);
});
