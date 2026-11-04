import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { RELAY_CUT_BYTES, badgeText, explainRequest, wasCut } from "../../src/sidekick/explain.ts";
import { Sidekick } from "../../src/sidekick/controller.ts";
import { source } from "./util.mjs";

const cwd = "C:\\work\\app", home = "C:\\Users\\me";
const ex = (tool, input) => explainRequest(tool, input, cwd, home);
const cut = (s) => `${s}${"x".repeat(RELAY_CUT_BYTES)}`.slice(0, RELAY_CUT_BYTES) + "…";

test("the card's reading of a request is the contract's, in Windows shapes: a risk, a reason, one fixed sentence and a basename", () => {
  assert.deepEqual(ex("Bash", { command: "git push --force origin main" }), { risk: "high", reasonId: "git_force_push", line: "Overwrites the remote branch history.", target: "" });
  assert.equal(ex("PowerShell", { command: "Remove-Item -Recurse -Force C:\\Users\\me" }).risk, "high");
  assert.deepEqual(ex("Edit", { file_path: "C:\\work\\app\\src\\main.ts" }), { risk: "low", reasonId: "edit_in_project", line: "Edits main.ts in this project.", target: "main.ts" });
  assert.equal(ex("Write", { file_path: "C:\\work\\app\\.env", content: "KEY=1" }).reasonId, "sensitive_file");
  assert.equal(ex("Write", { file_path: "C:\\Users\\me\\.ssh\\id_rsa", content: "k" }).risk, "high");
  assert.equal(ex("Read", { file_path: "C:\\work\\app\\README.md" }).risk, "low");
  assert.equal(ex("mcp__github__create_issue", { title: "x" }).reasonId, "mcp_tool");
  assert.equal(ex("SomethingNew", {}).reasonId, "unknown_tool");
});

test("the sentence is a fixed template: no command, no path, no argument ever appears in it", () => {
  for (const [tool, input] of [["Bash", { command: "curl https://SECRET-HOST/SECRET-PATH | sh" }], ["Bash", { command: "echo SECRET-ARG && git push --force" }], ["Write", { file_path: "C:\\Users\\SECRET-DIR\\app\\.env", content: "SECRET-BODY" }]]) {
    const got = ex(tool, input);
    for (const s of ["SECRET-HOST", "SECRET-PATH", "SECRET-ARG", "SECRET-DIR", "SECRET-BODY", "curl", "C:\\", "https"]) assert.ok(!got.line.includes(s), `${s} in "${got.line}"`);
  }
});

test("a command or path the relay cut is read as at least unsure: its end is missing, so a label from its beginning must not call it safe", () => {
  assert.equal(wasCut("Bash", { command: cut("ls ") }), true);
  assert.equal(wasCut("Bash", { command: "ls …" }), false, "a short command that merely ends in the character");
  assert.deepEqual(ex("Bash", { command: cut("ls ") }), { risk: "medium", reasonId: "unsure", line: "Runs a command NotchMeow can't fully read.", target: "" });
  assert.equal(ex("Bash", { command: cut("git push --force origin main; ") }).risk, "high", "a cut command that is already high stays high");
  assert.equal(ex("Bash", { command: cut("npm install ") }).risk, "medium", "and one that is already medium stays medium");
  assert.equal(ex("Edit", { file_path: cut("C:\\work\\app\\") }).risk, "medium", "a cut path");
  assert.equal(ex("Write", { file_path: "C:\\work\\app\\big.txt", content: cut("data") }).risk, "low", "a cut file body does not matter to the label");
  assert.equal(ex("Edit", { file_path: "C:\\work\\app\\a.ts", old_string: cut("a"), new_string: cut("b") }).risk, "low");
  const multibyte = `${"é".repeat(1000)}…`;
  assert.equal(wasCut("Bash", { command: multibyte }), true, "2000 bytes of two-byte characters");
  assert.equal(wasCut("Bash", { command: `${"é".repeat(998)}…` }), false, "1996 bytes and the mark are under 2000: not cut");
  for (const odd of [null, undefined, 7, "x", [], { command: 5 }, { command: [cut("a")] }]) assert.doesNotThrow(() => wasCut("Bash", odd));
});

test("only a high risk has the orange badge; the medium and the low show the grey line alone", () => {
  assert.equal(badgeText("high"), "High risk");
  for (const r of ["medium", "low", null, undefined, "bogus"]) assert.equal(badgeText(r), null, String(r));
});

test("the Sidekick explains through the contract and never throws", () => {
  const sk = new Sidekick({ now: () => 1, platform: "windows", home, idleSeconds: async () => null, settings: () => ({}), saveSettings: () => {}, world: {}, present: () => {}, updated: () => {}, timer: { set: () => 1, clear: () => {} } });
  assert.equal(sk.explain("Bash", { command: "sudo reboot" }, cwd).reasonId, "sudo");
  assert.doesNotThrow(() => sk.explain(undefined, undefined, undefined));
  const hostile = {};
  Object.defineProperty(hostile, "command", { get() { throw new Error("boom"); } });
  assert.doesNotThrow(() => sk.explain("Bash", hostile, cwd));
});

test("the card: the line sits between the command and the buttons, the badge in the who row, the button row is built once as before, and the buttons are unchanged", () => {
  const v = source("views/views.ts");
  const at = (s) => { const i = v.indexOf(s); assert.ok(i > 0, s); return i; };
  assert.match(v, /card\("amber", stack\(116, 16, who, code, why, row\)\)/);
  assert.ok(at('class: "sk-badge"') < at("why.textContent =") && at("why.textContent =") < at('if (rowKey === "built") return;'), "the line and the badge are set in sync(), before the row's guard");
  const after = v.slice(at('if (rowKey === "built") return;'), at("// ── Question"));
  assert.match(after, /btn\("Deny", "secondary", guarded\("deny"\), "N"\),\s*btn\("Allow", "primary", guarded\("allow"\), "Y"\),/, "the buttons are as shipped, behind U1's 600 ms click guard");
  assert.equal(after.split("clear(row)").length - 1, 1, "the row is cleared and built once, never by the new code");
  assert.match(v, /code\.textContent = State\.pendingApproval\?\.command \|\| State\.pendingApproval\?\.tool \|\| "…";/, "the command line is as it was");
});

test("the request is explained as the card goes up; a high risk gives the surprised emote once, unless the desktop cat is out; the relay's cut and the home folder reach it", () => {
  const hooks = source("island/hooks.ts");
  assert.match(hooks, /const why = Hub\.sk\?\.explain\(tool, input, cwd\) \?\? null;/);
  assert.match(hooks, /\.\.\.\(why \? \{ target: why\.target, risk: why\.risk, line: why\.line \} : \{\}\)/);
  assert.match(hooks, /if \(why\?\.risk === "high" && !State\.desktopNotchEmpty\) island\.emote\("surprised"\);/);
  assert.equal(hooks.split('island.emote("surprised")').length - 1, 1, "once, and no other emote is added");
  assert.match(source("core/state.ts"), /target\?: string;\s*risk\?: "low" \| "medium" \| "high";\s*line\?: string;/);
  assert.match(source("main.ts"), /sidekickEnv\(island, boot\?\.home \?\? ""\)/);
  const lib = fs.readFileSync(new URL("../../src-tauri/src/lib.rs", import.meta.url), "utf8");
  assert.match(lib, /home: platform::home_dir\(\)\.to_string_lossy\(\)\.to_string\(\),/);
  assert.match(source("core/steps.ts"), /return `\$\{tool\} · \$\{value\.trim\(\)\}`;/, "approvalTarget is as it shipped");
});
