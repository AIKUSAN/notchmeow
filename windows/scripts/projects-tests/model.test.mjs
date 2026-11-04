import test from "node:test";
import assert from "node:assert/strict";
import { ProjectsModel } from "../../src/projects/model.ts";

// The model: the registry, the steps, the pin, the click, the peek, the layout and the panel, as the island reads them (Task 3 of P-tauri).

const T = 1_700_000_000_000;

function rig(home = "/home/dev") {
  const w = { t: T };
  const m = new ProjectsModel({ home, now: () => w.t });
  return { w, m };
}

const IN = { projectCats: {}, mainCat: "shrimpy", activePills: ["integration_claude"], open: false, focusId: "integration_claude", twoCats: false };

test("Windows paths: a worktree under a backslash repo is its side session; nothing shown holds a separator", () => {
  const { m } = rig("C:\\Users\\dev");
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "c:\\dev\\Code\\app\\" });
  m.hook({ hook_event_name: "PreToolUse", session_id: "b", cwd: "C:\\dev\\Code\\app\\.claude\\worktrees\\p1", tool_name: "Read", tool_input: { file_path: "C:\\dev\\Code\\app\\src\\a.ts" } });
  const v = m.frame(IN).view;
  assert.equal(v.projects.length, 1);
  assert.equal(v.projects[0].name, "app");
  assert.deepEqual(v.projects[0].sessions.map((s) => [s.role, s.label, s.step]), [["main", "main", ""], ["side", "p1", "Reads · a.ts"]]);
  for (const s of [v.projects[0].name, ...v.projects[0].sessions.flatMap((x) => [x.label, x.step])]) assert.doesNotMatch(s, /[\/\\]/);
  assert.equal(m.cwdOf("b"), "C:/dev/Code/app/.claude/worktrees/p1");
});

test("a Claude App request answered ask is waiting, labelled, counted, and ends by itself after 10 min", () => {
  const { w, m } = rig();
  m.hook({ hook_event_name: "PermissionRequest", session_id: "d", cwd: "C:/dev/app", nm_agent: "claude-desktop", tool_name: "Bash", tool_input: { command: "ls" } });
  const v = m.frame(IN).view;
  assert.equal(v.waiting, 1);
  assert.deepEqual([v.projects[0].sessions[0].note, v.projects[0].sessions[0].host], ["Waiting in Claude App", "claude-app"]);
  w.t += 600_000;
  assert.equal(m.frame(IN).view.waiting, 0);
});

test("the step words never carry a command or a query; AskUserQuestion leaves none; a prompt clears it", () => {
  const { m } = rig();
  m.hook({ hook_event_name: "PreToolUse", session_id: "s", cwd: "C:/dev/app", tool_name: "Bash", tool_input: { command: "rm -rf SECRET" } });
  assert.equal(m.frame(IN).view.projects[0].step, "Runs");
  m.hook({ hook_event_name: "PreToolUse", session_id: "s", cwd: "C:/dev/app", tool_name: "WebSearch", tool_input: { query: "SECRET" } });
  assert.equal(m.frame(IN).view.projects[0].step, "Web search");
  m.hook({ hook_event_name: "PreToolUse", session_id: "s", cwd: "C:/dev/app", tool_name: "AskUserQuestion", tool_input: { questions: [] } });
  assert.equal(m.frame(IN).view.projects[0].step, "Web search");
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "s", cwd: "C:/dev/app", prompt: "x" });
  assert.equal(m.frame(IN).view.projects[0].step, "");
});

test("one pin at a time, a pin goes with its project, and a pin on a project that is not live is not taken", () => {
  const { w, m } = rig();
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:/dev/one" }); w.t += 1000;
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "b", cwd: "C:/dev/two" });
  const [two, one] = m.frame(IN).view.projects.map((p) => p.id);
  assert.equal(m.frame(IN).big.id, two, "the most recently active");
  m.togglePin(one); assert.equal(m.frame(IN).big.id, one);
  m.togglePin(two); assert.deepEqual([m.isPinned(one), m.isPinned(two)], [false, true]);
  assert.equal(m.frame({ ...IN, open: true }).big.id, two, "the pin holds through a fold and a reopen");
  m.hook({ hook_event_name: "SessionEnd", session_id: "b" });
  const f = m.frame(IN);
  assert.deepEqual([f.big.id, f.pinned, m.isPinned(two)], [one, null, false]);
  m.togglePin(two); assert.equal(m.isPinned(two), false, "the menu stayed open while its project ended");
});

test("the layout: projects while Claude only; another agent switches it only while folded; usesProjects needs a live project, the focus and no Two cats", () => {
  const { m } = rig();
  assert.deepEqual([m.frame(IN).layout, m.frame(IN).usesProjects], ["projects", false], "nothing live");
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:/dev/app" });
  assert.equal(m.frame(IN).usesProjects, true);
  assert.equal(m.frame({ ...IN, focusId: "integration_stripe" }).usesProjects, false);
  assert.equal(m.frame({ ...IN, twoCats: true }).usesProjects, false);
  assert.equal(m.frame({ ...IN, activePills: ["integration_claude", "agent_gemini"] }).layout, "agents", "a switched-on agent counts while idle");
  assert.equal(m.frame(IN).layout, "projects", "folded, Claude only again");
  m.hook({ hook_event_name: "PreToolUse", session_id: "g", cwd: "C:/dev/app", nm_agent: "gemini" });
  assert.equal(m.frame({ ...IN, open: true }).layout, "projects", "open: kept");
  assert.equal(m.frame(IN).layout, "agents", "folded: switched");
});

test("the chevron and the panel: agents layout, a live project, the Claude Code focus, no Two cats; the panel also needs the flag", () => {
  const { m } = rig();
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:/dev/app" });
  const A = { ...IN, activePills: ["agent_codex"] };
  assert.deepEqual([m.frame(A).chevron, m.frame(A).panelShown], [true, false]);
  m.toggleExpanded();
  assert.deepEqual([m.frame(A).panelShown, m.frame({ ...A, focusId: "agent_codex" }).panelShown, m.frame({ ...A, twoCats: true }).chevron, m.frame(IN).panelShown], [true, false, false, false]);
});

test("a peek is let go when its project leaves", () => {
  const { m } = rig();
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:/dev/app" });
  const id = m.frame(IN).view.projects[0].id;
  m.setPeeking(id); assert.equal(m.frame(IN).peeking, id);
  m.hook({ hook_event_name: "SessionEnd", session_id: "a" });
  assert.equal(m.frame(IN).peeking, null);
});

test("steps live only as long as their session; an unknown payload changes nothing and never throws", () => {
  const { m } = rig();
  m.hook({ hook_event_name: "PreToolUse", session_id: "s", cwd: "C:/dev/app", tool_name: "Edit", tool_input: { file_path: "C:/dev/app/x.ts" } });
  assert.equal(m.stepsSize, 1);
  m.hook({ hook_event_name: "SessionEnd", session_id: "s" });
  assert.equal(m.stepsSize, 0);
  for (const bad of [null, 5, "x", [], { hook_event_name: "Nope", session_id: "s" }]) assert.equal(m.hook(bad), false);
});

test("a chosen cat shows; liveProjects is one row per folder name, in pill order", () => {
  const { w, m } = rig();
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:/dev/notchbuddy" }); w.t += 1000;
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "b", cwd: "C:/dev/site" });
  const f = m.frame({ ...IN, projectCats: { "Notch Buddy": "oreo" } });
  assert.equal(f.view.projects.find((p) => p.catKey === "Notch Buddy").cat, "oreo");
  assert.deepEqual(m.liveProjects(f.view), [{ catKey: "site", name: "site" }, { catKey: "Notch Buddy", name: "Notch Buddy" }]);
});

test("the section's flag is kept when another pill takes the focus: the section is hidden, then reopens with the Claude card", () => {
  const { m } = rig();
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:/dev/app" });
  const A = { ...IN, activePills: ["agent_codex"] };
  m.toggleExpanded();
  assert.equal(m.frame(A).panelShown, true);
  const other = m.frame({ ...A, focusId: "agent_codex" });
  assert.deepEqual([other.chevron, other.panelShown, other.expanded], [false, false, true], "hidden, the flag kept");
  assert.equal(m.frame(A).panelShown, true, "the Claude card is back: the section reopens");
  assert.equal(m.expanded, true, "the model's flag is not changed by the focus");
});

test("a payload whose getter throws does not throw out of hook(): it returns false and logs one fixed sentence", () => {
  const { m } = rig();
  const bad = { get hook_event_name() { throw new Error("SECRET-PAYLOAD-TEXT"); } };
  const logged = [];
  const real = console.error;
  console.error = (...args) => logged.push(args.map(String).join(" "));
  try {
    assert.equal(m.hook(bad), false);
  } finally {
    console.error = real;
  }
  assert.deepEqual(logged, ["[notchmeow] projects feed failed"], "one fixed sentence, never the payload or the error's text");
});

test("steps follow the registry: 100 sessions keep at most 64 steps; a gemini PreToolUse adds no step", () => {
  const { m } = rig();
  for (let i = 0; i < 100; i++) {
    m.hook({ hook_event_name: "PreToolUse", session_id: `s${i}`, cwd: `C:/dev/p${i}`, tool_name: "Edit", tool_input: { file_path: `C:/dev/p${i}/a.ts` } });
  }
  assert.ok(m.stepsSize <= 64, `steps held: ${m.stepsSize}`);
  const before = m.stepsSize;
  m.hook({ hook_event_name: "PreToolUse", session_id: "gem", cwd: "C:/dev/gem", nm_agent: "gemini", tool_name: "Edit", tool_input: { file_path: "C:/dev/gem/a.ts" } });
  assert.equal(m.stepsSize, before, "a non-Claude session adds no step");
});

test("a hostile tool name (500 characters, a path) gives a bounded step with no separator", () => {
  const { m } = rig();
  const hostile = "a/b\\c ".repeat(84) + "/etc/passwd";
  m.hook({ hook_event_name: "PreToolUse", session_id: "h", cwd: "C:/dev/app", tool_name: hostile, tool_input: {} });
  const step = m.frame(IN).view.projects[0].step;
  assert.ok(step.length > 0 && Array.from(step).length <= 80, `step length ${Array.from(step).length}`);
  assert.doesNotMatch(step, /[\/\\]/);
});
