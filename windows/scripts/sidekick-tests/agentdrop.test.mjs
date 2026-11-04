import test from "node:test";
import assert from "node:assert/strict";
import { DROP_SLACK, MAX_CHIPS, NOT_COPIED_LINE, agentCatAt, copiedLine, dropAgents, dropPoint, pathsText } from "../../src/sidekick/agentdrop.ts";
import { castOf } from "../../src/cat/cast.ts";

const tasks = [
  { id: "integration_claude", state: "working", last: 5 },
  { id: "agent_gemini", state: "working", last: 4 },
  { id: "agent_antigravity", state: "idle", last: 3 },
  { id: "integration_github", state: "idle", last: 2 },
];
const castIn = (mode, focusId = "integration_claude") => castOf(mode, { tasks, focusId, mainCat: "shrimpy", pair: ["shrimpy", "momo"], agentCats: { integration_claude: "leo", agent_gemini: "oreo", agent_antigravity: "snow" } });
const live = ["integration_claude", "agent_gemini", "agent_antigravity", "integration_github"];

test("a chip for each running agent, in every display mode: Claude Code, Gemini CLI, Antigravity and any other tagged agent; never an integration, never an agent that is not running", () => {
  for (const mode of ["one", "perAgent", "two"]) {
    assert.deepEqual(dropAgents(tasks, castIn(mode), live).map((a) => a.agentId), ["integration_claude", "agent_gemini", "agent_antigravity"], mode);
    assert.deepEqual(dropAgents(tasks, castIn(mode), ["agent_gemini"]).map((a) => a.agentId), ["agent_gemini"], `${mode}: only the running one`);
    assert.deepEqual(dropAgents(tasks, castIn(mode), []), [], mode);
  }
  assert.deepEqual(dropAgents(tasks, castIn("one"), live).map((a) => a.cat), ["shrimpy", "shrimpy", "shrimpy"], "One cat: every cat wears the Main cat");
  assert.deepEqual(dropAgents(tasks, castIn("perAgent"), live).map((a) => a.cat), ["leo", "oreo", "snow"], "A cat for each agent: the agent's own coat, the focused agent's too");
  assert.deepEqual(dropAgents(tasks, castIn("two"), live).map((a) => a.agentId), ["integration_claude", "agent_gemini", "agent_antigravity"], "Two cats: cat 2's agent is one of them");
  assert.deepEqual(dropAgents(tasks, castIn("perAgent", "agent_gemini"), live).map((a) => a.agentId), ["integration_claude", "agent_gemini", "agent_antigravity"], "the focused agent is a chip too: the big cat is not drawn in the drop view");
});

test("at most four chips, an agent with no pill gets none, and a live ledger agent with no pill is not a chip", () => {
  const many = ["a", "b", "c", "d", "e"].map((t) => ({ id: `agent_${t}` }));
  assert.equal(dropAgents(many, castIn("one"), many.map((t) => t.id)).length, MAX_CHIPS);
  assert.deepEqual(dropAgents(tasks, castIn("one"), ["agent_codex"]), [], "live in the ledger, no pill on the island");
});

test("the cat under the point: inside, on the edge, a little outside, and nowhere; the first of two overlapping cats wins; a point that is not a point hits nothing", () => {
  const targets = [{ agentId: "a", rect: { x: 100, y: 50, w: 20, h: 20 } }, { agentId: "b", rect: { x: 110, y: 50, w: 20, h: 20 } }];
  assert.equal(agentCatAt(105, 60, targets), "a");
  assert.equal(agentCatAt(125, 60, targets), "b");
  assert.equal(agentCatAt(115, 60, targets), "a", "where they overlap, the first");
  assert.equal(agentCatAt(100, 50, targets), "a");
  assert.equal(agentCatAt(100 - DROP_SLACK, 50, targets), "a", "a little off is still the cat's");
  assert.equal(agentCatAt(100 - DROP_SLACK - 1, 50, targets), null);
  assert.equal(agentCatAt(300, 300, targets), null);
  for (const [x, y] of [[Number.NaN, 1], [1, Number.POSITIVE_INFINITY], [undefined, 1]]) assert.equal(agentCatAt(x, y, targets), null);
  assert.equal(agentCatAt(1, 1, []), null);
});

test("where a drop happened: physical pixels over the pixel ratio, or the last cursor position where the system gives none", () => {
  assert.deepEqual(dropPoint({ x: 300, y: 150 }, 1.5, { x: 9, y: 9 }), { x: 200, y: 100 });
  assert.deepEqual(dropPoint(undefined, 2, { x: 9, y: 9 }), { x: 9, y: 9 });
  assert.deepEqual(dropPoint({ x: Number.NaN, y: 1 }, 2, { x: 9, y: 9 }), { x: 9, y: 9 });
  assert.deepEqual(dropPoint({ x: 10, y: 10 }, 0, { x: 9, y: 9 }), { x: 9, y: 9 });
});

// The clipboard text follows the Mac's rule (commit 66c4804, SidekickDrop.swift): a plain path as it is, any other path POSIX single-quoted, several paths on ONE line, and one refused name refuses the drop.
test("a plain path is copied as it is: it starts with / and holds only ASCII letters, digits, _ . / + @ % , : = -, or non-ASCII letters, marks and numbers", () => {
  assert.equal(pathsText(["/home/me/a.txt"]), "/home/me/a.txt");
  assert.equal(pathsText(["/a/B_c.d+e@f%g,h:i=j-k/9"]), "/a/B_c.d+e@f%g,h:i=j-k/9");
  assert.equal(pathsText(["/home/\u00e9l\u00e8ve/\u65e5\u672c\u8a9e.txt"]), "/home/\u00e9l\u00e8ve/\u65e5\u672c\u8a9e.txt", "non-ASCII letters");
  assert.equal(pathsText(["/home/e\u0301/\u0663.txt"]), "/home/e\u0301/\u0663.txt", "a combining mark and a non-ASCII digit");
});

test("any other path is POSIX single-quoted, and each ' is written '\\''", () => {
  assert.equal(pathsText(["/home/me/a b.txt"]), "'/home/me/a b.txt'", "a path with a space is quoted");
  assert.equal(pathsText(["/home/me/$HOME;rm.txt"]), "'/home/me/$HOME;rm.txt'");
  assert.equal(pathsText(["/home/me/it's.txt"]), "'/home/me/it'\\''s.txt'");
  assert.equal(pathsText(["relative/a.txt"]), "'relative/a.txt'", "it does not start with /");
  assert.equal(pathsText(["/a/\u00a0b"]), "'/a/\u00a0b'", "a no-break space is not plain");
  assert.equal(pathsText(["/a/e\u0301'x"]), "'/a/e\u0301'\\''x'", "a quote after a combining mark is still replaced");
});

test("several paths are ONE line, space-separated, each handled on its own; there is no line break anywhere", () => {
  const text = pathsText(["/home/me/a.txt", "/home/me/b c.txt", "/home/me/it's"]);
  assert.equal(text, "/home/me/a.txt '/home/me/b c.txt' '/home/me/it'\\''s'");
  assert.doesNotMatch(text, /[\n\r]/);
  assert.doesNotMatch(pathsText(["/a b", "/c d", "/e"]), /[\n\r]/);
});

test("one refused scalar refuses the whole drop: a control, a format character, a line or paragraph separator, a default-ignorable code point, a backslash, a !", () => {
  const refused = {
    "line feed": "/b\n/evil", "carriage return": "/b\r", "NUL": "/c\0d", "tab": "/a\tb", "DEL": "/a\u007fb", "C1 control": "/a\u0085b",
    "zero-width space (Cf)": "/a\u200bb", "right-to-left override (Cf)": "/a\u202eb", "zero-width joiner (Cf)": "/a\u200db", "soft hyphen (Cf)": "/a\u00adb",
    "line separator (Zl)": "/a\u2028b", "paragraph separator (Zp)": "/a\u2029b",
    "combining grapheme joiner (default-ignorable)": "/a\u034fb", "hangul filler (default-ignorable)": "/a\u3164b", "variation selector 16": "/a\ufe0fb", "tag character": "/a\u{e0041}b",
    "Arabic number sign (Cf, not default-ignorable)": "/a\u0600b", "lone surrogate": "/a\ud800b",
    "backslash": "/a\\b", "exclamation mark": "/a!b", "a Windows path": "C:\\Users\\me\\a.txt",
  };
  for (const [what, bad] of Object.entries(refused)) {
    assert.equal(pathsText([bad]), null, what);
    assert.equal(pathsText(["/ok.txt", bad, "/also ok"]), null, `${what}: with good paths around it`);
  }
});

test("a multi-path result has no \\n and no \\r; none left is null", () => {
  for (const paths of [["/a", "/b c", "/d'e"], ["/a b"], ["/\u00e9", "x y", "/z"]]) assert.doesNotMatch(pathsText(paths), /[\n\r]/);
  for (const none of [[], [""], "x", undefined, null, 7, {}, [7, null, ""]]) assert.equal(pathsText(none), null, String(none));
});

// On Windows the text goes into an agent's prompt, not a shell: every copied path is in double quotes (no Windows name holds a `"`), so `&`, `|`, `<`, `>`, `^`, `;` and `(`, `)` stay as they are. A `!` is refused (see the bang test).
test("on Windows a drive-letter or UNC path is double-quoted, backslashes kept", () => {
  assert.equal(pathsText(["C:\\Users\\a\\b.txt"], "windows"), "\"C:\\Users\\a\\b.txt\"");
  assert.equal(pathsText(["\\\\server\\share\\a.txt"], "windows"), "\"\\\\server\\share\\a.txt\"", "UNC");
});

test("on Windows every copied path is double-quoted, even one with no space: C:\\a&b\\c.txt is \"C:\\a&b\\c.txt\"", () => {
  assert.equal(pathsText(["C:\\a&b\\c.txt"], "windows"), "\"C:\\a&b\\c.txt\"");
});

test("on Windows a path with a space is wrapped in double quotes", () => {
  assert.equal(pathsText(["C:\\My Docs\\a b.txt"], "windows"), "\"C:\\My Docs\\a b.txt\"");
});

test("on Windows several paths are ONE line, each double-quoted, one space between, with no line break", () => {
  const text = pathsText(["C:\\a.txt", "C:\\b.txt"], "windows");
  assert.equal(text, "\"C:\\a.txt\" \"C:\\b.txt\"");
  assert.doesNotMatch(text, /[\n\r]/);
});

test("on Windows a name with $, a backtick or % is refused: those still expand inside double quotes in PowerShell or cmd", () => {
  for (const bad of ["C:\\$Recycle\\a.txt", "C:\\a`b.txt", "C:\\100%\\a.txt"]) {
    assert.equal(pathsText([bad], "windows"), null, bad);
    assert.equal(pathsText(["C:\\ok.txt", bad], "windows"), null, `${bad}: with a good path next to it`);
  }
});

test("on Windows a space that is not U+0020 is refused: NBSP, en space, ideographic space", () => {
  for (const bad of ["C:\\a\u00a0b.txt", "C:\\a\u2002b.txt", "C:\\a\u3000b.txt"]) assert.equal(pathsText([bad], "windows"), null, JSON.stringify(bad));
});

test("on Windows the refusal list still holds: a zero-width or bidi character refuses the drop", () => {
  for (const bad of ["C:\\a\u200bb.txt", "C:\\a\u202eb.txt"]) assert.equal(pathsText([bad], "windows"), null, JSON.stringify(bad));
});

test("on Windows a bang is refused, as on the Mac and Linux: bash, zsh and Git Bash history expansion can run earlier commands from a pasted !", () => {
  assert.equal(pathsText(["C:\\Users\\a\\Hello!.txt"], "windows"), null);
  assert.equal(pathsText(["C:\\ok.txt", "C:\\Users\\a\\Hello!.txt"], "windows"), null, "with a good path next to it");
});

test("on Windows an empty entry refuses the whole drop: the pasted text is never shorter than the drop", () => {
  assert.equal(pathsText(["C:\\ok.txt", ""], "windows"), null);
  assert.equal(pathsText(["", "C:\\ok.txt"], "windows"), null);
});

test("on Windows a non-string entry refuses the whole drop: it is not skipped", () => {
  assert.equal(pathsText(["C:\\ok.txt", 42], "windows"), null);
  assert.equal(pathsText([null, "C:\\ok.txt"], "windows"), null);
});

test("on Windows a name with a straight double quote is refused: it ends our quoting in every shell", () => {
  assert.equal(pathsText(["C:\\a\"b.txt"], "windows"), null);
  assert.equal(pathsText(["C:\\ok.txt", "C:\\a\"b.txt"], "windows"), null, "with a good path next to it");
});

test("on Windows a name with a curly or full-width double quote is refused: PowerShell reads U+201C, U+201D, U+201E, U+201F and U+FF02 as quotes", () => {
  for (const q of ["\u201c", "\u201d", "\u201e", "\u201f", "\uff02"]) {
    const bad = `C:\\a${q}b.txt`;
    assert.equal(pathsText([bad], "windows"), null, JSON.stringify(bad));
    assert.equal(pathsText(["C:\\ok.txt", bad], "windows"), null, `${JSON.stringify(bad)}: with a good path next to it`);
  }
});

test("on Windows a path ending in a backslash is refused: Git Bash reads \\\" as an escaped quote, so the next path would run unquoted", () => {
  assert.equal(pathsText(["C:\\"], "windows"), null);
  assert.equal(pathsText(["C:\\ok.txt", "C:\\"], "windows"), null, "with a good path next to it");
});

test("on Windows a folder path without the trailing backslash is copied: C:\\Users\\a is \"C:\\Users\\a\"", () => {
  assert.equal(pathsText(["C:\\Users\\a"], "windows"), "\"C:\\Users\\a\"");
});

test("on Linux a backslash is still refused: the POSIX rule is unchanged", () => {
  assert.equal(pathsText(["/home/a\\b"], "linux"), null);
});

test("the lines are honest: copied, never sent, delivered or attached", () => {
  assert.equal(copiedLine("integration_claude"), "Copied the path \u2014 paste it into Claude Code");
  assert.equal(copiedLine("agent_gemini"), "Copied the path \u2014 paste it into Gemini CLI");
  assert.equal(copiedLine("agent_antigravity"), "Copied the path \u2014 paste it into Antigravity");
  for (const line of [copiedLine("agent_gemini"), NOT_COPIED_LINE]) assert.doesNotMatch(line, /sent|delivered|attached|pasted/i);
});

// ── The wiring: where the island and Rust call these rules ────────────────────────────────────────────────────────────────────────────────

import fs from "node:fs";
import { source } from "./util.mjs";
const rust = (rel) => fs.readFileSync(new URL(`../../src-tauri/src/${rel}`, import.meta.url), "utf8");

test("the island tests the agent cats first on a drop, the big drop area is never a chip, and a drop anywhere else is the old drop", () => {
  const island = source("island/island.ts");
  const drop = island.slice(island.indexOf('      case "drop": {'), island.indexOf("this.whenCatIsHere(() => this.swallow(path));"));
  assert.ok(drop.includes("const agent = this.agentUnder(e.position);"), "the agent cat's test is there");
  // A shelf item dropped back on the island is not a new drop: the shelf's dragOut guard, before the switch, returns first, so it neither hands off nor lands.
  assert.ok(island.indexOf("this.dragOut.blocks(") < island.indexOf('      case "drop": {'), "the shelf's dragOut guard comes before the drop case");
  assert.ok(drop.indexOf("const agent = this.agentUnder(e.position);") < drop.indexOf("const plan = planDrop("), "the agent cat's test comes first in the drop case, before the shelf's rule");
  assert.ok(drop.indexOf("if (agent !== null) {") < drop.indexOf("const plan = planDrop("));
  assert.match(drop, /this\.handoff\(agent, e\.paths\);\s*break;/, "a drop on an agent's cat ends there: no ingest, no chat, no upload sequence");
  assert.doesNotMatch(drop.slice(drop.indexOf("if (agent !== null) {"), drop.indexOf("State.fileDragOver = false;\n        const path")), /swallow|ingestFile|whenCatIsHere/);
  assert.match(island, /this\.agentDrops\.show\(dropAgents\(State\.tasks, State\.cast, Hub\.sk\?\.ledger\.live\.map\(\(s\) => s\.agentId\) \?\? \[\]\)\);/);
  assert.doesNotMatch(source("sidekick/agentdrop.ts"), /bigCat|botCircle|upload/i, "the big drop area is not in the rules");
});

test("the handoff copies a path and, on Windows only, uses the existing Open terminal action; it never pastes, types or sends", () => {
  const island = source("island/island.ts");
  const handoff = island.slice(island.indexOf("  private handoff("), island.indexOf("  private onDragDrop("));
  assert.match(handoff, /Bridge\.copyText\(text\)/);
  assert.match(handoff, /const text = pathsText\(paths, platformName\(\)\);/, "the rule knows the platform");
  assert.match(handoff, /if \(platformName\(\) === "windows"\) \{\s*if \(openRoute\(agentId, State\.claudeApp, State\.claudeAppHost\) === "claude-app"\) void Bridge\.openClaudeApp\(\);\s*else void Bridge\.openInVSCode\(State\.tasks\.find\(\(t\) => t\.id === agentId\)\?\.sessionCwd \?\? null\);\s*\}/);
  assert.match(handoff, /emoteMiniBots\(agentId, "happy"\);/);
  assert.match(handoff, /show\(copiedLine\(agentId\)\)/);
  for (const bad of [/chatReset|aiChat|ingestFile|resume/, /keybd|SendInput|xdotool|wtype|enigo|paste/i]) assert.doesNotMatch(handoff, bad);
  const rs = ["lib.rs", "platform/windows.rs", "platform/linux.rs", "sidekick.rs"].map(rust).join("\n");
  assert.doesNotMatch(rs, /SendInput|keybd_event|xdotool|wtype|enigo|SetForegroundWindow.*claude/i, "no keystroke, no paste, no other program's window is touched by this feature");
  assert.match(rust("lib.rs"), /fn copy_text\(app: AppHandle, text: String\) -> bool \{\s*sidekick_presence::clipboard_text_ok\(&text\) && platform::copy_text\(&app, &text\)/);
  assert.match(rust("platform/windows.rs"), /pub fn copy_text\(_app: &AppHandle, text: &str\) -> bool/);
  assert.match(rust("platform/linux.rs"), /pub fn copy_text\(app: &AppHandle, text: &str\) -> bool/);
  assert.match(rust("../Cargo.toml"), /"Win32_System_DataExchange",\s*"Win32_System_Memory",/);
  assert.match(source("core/bridge.ts"), /copyText: \(text: string\) => call<boolean>\("copy_text", \{ text \}\)/);
});

test("an external agent's pill keeps its project folder for Open terminal, in memory and nowhere else", () => {
  const hooks = source("island/hooks.ts");
  assert.match(hooks, /const pill = State\.tasks\.find\(\(x\) => x\.id === agentId\);\s*if \(pill && cwd\) pill\.sessionCwd = cwd;/);
});

test("the strip is additive: the shipping drop view is not changed, the strip floats over it, takes no mouse of its own and shows only while a file is dragged", () => {
  assert.doesNotMatch(source("views/upload.ts"), /agent|chip|ad-/i, "the drop view's own file is untouched by this feature");
  const css = source("style.css");
  const rule = css.slice(css.indexOf("#agent-drops {"), css.indexOf("#agent-drops.on"));
  assert.match(rule, /position: absolute;/);
  assert.match(rule, /pointer-events: none;/);
  assert.match(rule, /display: none;/);
  const island = source("island/island.ts");
  assert.ok(island.indexOf("this.agentDrops.hide();") > 0);
  assert.match(island, /case "leave": \{[\s\S]*this\.agentDrops\.hide\(\);/);
});
