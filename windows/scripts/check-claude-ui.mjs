// Plain-Node checks for the Claude Code parts of the chat that hold logic: no DOM, no framework. They run against the
// shared fixtures in tests/fixtures/ai/claude-code/, so the Windows/Linux app and the Mac app cannot drift apart.
// Needs Node 22.6 or newer, which can read the TypeScript source directly:
//
//   cd windows && npm run check:claude
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  ApprovalQueue, endUnfinished, folderName, levelChip, modelChip, planLimitNote, routeHook, signInWords, stepRow,
} from "../src/core/claude.ts";
import { approvalTarget, stepLabel } from "../src/core/steps.ts";

const fixture = (name) => JSON.parse(readFileSync(new URL(`../../tests/fixtures/ai/claude-code/${name}`, import.meta.url), "utf8"));

// Which hook payloads belong to a chat.
const routing = fixture("hook-routing.json");
for (const c of routing.cases) {
  assert.equal(routeHook(c.payload, new Set(c.live ?? routing.live)), c.expect, c.name);
}
console.log(`✓ ${routing.cases.length} hook payloads go to the right place`);
// A chat's payload never reaches a pill: the island asks the router before it looks at a session (a source pin, because
// no check here can run the island).
const hooks = readFileSync(new URL("../src/island/hooks.ts", import.meta.url), "utf8");
const handler = hooks.slice(hooks.indexOf("function handleHook("));
assert.ok(handler.includes("routeHook(") && handler.indexOf("routeHook(") < handler.indexOf("hook_event_name ?? \"\""), "handleHook asks the router first");
console.log("✓ the island asks the router before it makes or touches a pill");

// The two chips.
const labels = fixture("labels.json");
for (const c of labels.modelChip) assert.equal(modelChip(c.authMethod, c.paidBy), c.expect, c.name);
for (const c of labels.levelChip) assert.equal(levelChip(c.level, c.folder), c.expect, `${c.level} ${c.folder}`);
console.log("✓ the model chip never claims 'your plan' without being told, and the level chip names the folder");
assert.equal(folderName("C:\\Users\\José\\Mis Proyectos\\"), "Mis Proyectos");
assert.equal(signInWords("claude.ai"), "your Claude plan");
assert.equal(signInWords("something_new"), "its own sign-in");

// What the chat says for a plan limit, in the viewer's time zone and locale.
for (const c of fixture("copy.json").cases.filter((x) => x.resetsAt != null)) {
  const note = planLimitNote("Your Claude plan's limit was reached.", c.resetsAt, c.locale.replace("_", "-"), c.timeZone);
  assert.equal(note, c.text, c.locale);
}
assert.equal(planLimitNote("Your Claude plan's limit was reached.", null), "Your Claude plan's limit was reached.");
console.log("✓ a plan limit says when it resets, as the Mac does");

// The step rows read as the island's own do; a failed or stopped step says so.
assert.equal(stepLabel("Read", { file_path: "C:\\work\\README.md" }), "Reads · README.md");
assert.equal(stepLabel("Bash", { command: "npm test" }), "Runs · npm test");
assert.equal(stepLabel("Frobnicate", {}), "Frobnicate");
assert.equal(stepRow({ id: "1", tool: "Read", input: { file_path: "/work/a.md" }, state: "done" }), "Reads · a.md");
assert.equal(stepRow({ id: "1", tool: "Read", input: { file_path: "/work/a.md" }, state: "failed" }), "Reads · a.md ⚠");
assert.equal(stepRow({ id: "1", tool: "Bash", input: { command: "sleep 60" }, state: "stopped" }), "Runs · sleep 60 · stopped");
// Stop ends a step that never finished as stopped, and leaves the others alone.
const mixed = [{ id: "a", tool: "Read", input: {}, state: "done" }, { id: "b", tool: "Bash", input: {}, state: "running" }, { id: "c", tool: "Edit", input: {}, state: "failed" }];
assert.deepEqual(endUnfinished(mixed).map((s) => s.state), ["done", "stopped", "failed"]);
assert.equal(mixed[1].state, "running", "the input is not changed");
// What the card says is what Allow authorises.
assert.equal(approvalTarget("Write", { file_path: "C:\\work\\.env", content: "SECRET" }), "Write · C:\\work\\.env");
assert.equal(approvalTarget("Bash", { command: "  npm test " }), "Bash · npm test");
assert.equal(approvalTarget("Frob", { x: 1 }), "Frob");
console.log("✓ step rows and the approval card use the island's own words");

// Requests wait in order.
const q = new ApprovalQueue();
const req = (requestId, sessionId, tool) => ({ requestId, sessionId, tool, command: tool });
q.push(req("a", "s1", "Bash")); q.push(req("b", "s1", "Edit")); q.push(req("c", "s2", "Write"));
assert.equal(q.front?.tool, "Bash");
assert.equal(q.popFront()?.requestId, "a");
assert.equal(q.front?.tool, "Edit");
assert.equal(q.remove("c")?.requestId, "c");
assert.equal(q.remove("nope"), null);
q.push(req("c", "s2", "Write"));
assert.deepEqual(q.removeAll("s1").map((x) => x.requestId), ["b"]);
assert.equal(q.front?.sessionId, "s2");
assert.deepEqual(q.removeAll().map((x) => x.requestId), ["c"]);
assert.equal(q.length, 0);
console.log("✓ approvals wait in the order they came, and a session's go together");

console.log("\nAll Claude Code UI checks passed");
