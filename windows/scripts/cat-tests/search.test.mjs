import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { SEARCH_TOOLS, isSearchTool, toolState } from "../../src/cat/base.ts";
import { load } from "./util.mjs";

const fx = load("search-tools.json");

test("the tool names that mean searching are the fixture's, for Claude Code, Gemini CLI and Codex", () => {
  assert.deepEqual(JSON.parse(JSON.stringify(SEARCH_TOOLS)), fx.agents);
  assert.ok(fx.cases.length >= 25);
});

test("every case of the fixture: a search tool searches, any other tool works", () => {
  for (const c of fx.cases) {
    assert.equal(isSearchTool(c.tool), c.searching, c.tool);
    assert.equal(toolState(c.tool), c.state, c.tool);
  }
  for (const name of Object.values(fx.agents).flat()) assert.equal(toolState(name), "searching", name);
});

test("matching is exact and case-sensitive, and anything that is not a string is not a search", () => {
  for (const bad of ["websearch", "WEBSEARCH", "Web_Search", "web_search ", " Grep", "mcp__brave__web_search", "", "Task", "Bash"]) assert.equal(isSearchTool(bad), false, JSON.stringify(bad));
  for (const odd of [undefined, null, 7, true, {}, [], ["Grep"], Symbol.iterator]) {
    assert.equal(isSearchTool(odd), false, String(typeof odd));
    assert.equal(toolState(odd), "working");
  }
  for (const proto of ["__proto__", "constructor", "toString", "hasOwnProperty"]) assert.equal(isSearchTool(proto), false, proto);
});

test("hooks.ts: before and after a tool, the pill's state is the tool's state", () => {
  const hooks = fs.readFileSync(new URL("../../src/island/hooks.ts", import.meta.url), "utf8");
  assert.match(hooks, /import \{ toolState \} from "\.\.\/cat\/base\.ts";/);
  const pre = hooks.match(/case "PreToolUse": \{[\s\S]*?break;\s*\}/)[0], post = hooks.match(/case "PostToolUse":[\s\S]*?break;/)[0];
  assert.match(pre, /State\.updateTask\(agentId, toolState\(payload\.tool_name\)\);/);
  assert.match(post, /State\.updateTask\(agentId, toolState\(payload\.tool_name\)\);/);
  assert.doesNotMatch(pre + post, /updateTask\(agentId, "working"\)/);
});
