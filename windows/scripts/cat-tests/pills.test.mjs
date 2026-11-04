import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { AGENT_PILL_COLORS, agentColor, agentLabel, agentPillName } from "../../src/core/pills.ts";

const read = (rel) => fs.readFileSync(new URL(rel, import.meta.url), "utf8");
const swift = read("../../../NotchBuddy/Sources/App/PillCatalog.swift");
const relay = read("../../hook/src/agents.rs");

test("the agent pills have the Mac's colours, as PillCatalog.swift declares them", () => {
  assert.deepEqual(Object.keys(AGENT_PILL_COLORS), ["agent_gemini", "agent_antigravity", "agent_claude-desktop"]);
  for (const [id, color] of Object.entries(AGENT_PILL_COLORS)) {
    const m = swift.match(new RegExp(`id:\\s*"${id}",[^\\n]*?color:\\s*"(#[0-9A-Fa-f]{6})"`));
    assert.ok(m, `${id} is in PillCatalog.swift`);
    assert.equal(color, m[1].toUpperCase(), id);
  }
});

test("the pill IDs are the relay's agent tags behind agent_, and they are frozen", () => {
  const tags = [...relay.matchAll(/pub const (?:GEMINI|ANTIGRAVITY|CLAUDE_DESKTOP): &str = "([a-z-]+)";/g)].map((m) => m[1]);
  assert.deepEqual(tags, ["gemini", "antigravity", "claude-desktop"]);
  assert.deepEqual(Object.keys(AGENT_PILL_COLORS), tags.map((t) => `agent_${t}`));
});

test("agentColor: a known agent wears its pill's colour, any other keeps the stable colour it always had, odd names are just names", () => {
  assert.equal(agentColor("gemini"), "#8AB4F8");
  assert.equal(agentColor("antigravity"), "#E879F9");
  assert.equal(agentColor("my-agent"), "#22C55E", "the hashed colours of other agents are what they were");
  assert.equal(agentColor("codex"), "#E879F9");
  assert.equal(agentColor("cursor"), "#60A5FA");
  for (const odd of ["constructor", "__proto__", "toString", "hasOwnProperty", "agent_gemini", ""]) assert.match(agentColor(odd), /^#[0-9A-F]{6}$/, odd);
  assert.equal(agentColor("gemini"), agentColor("gemini"), "stable");
});

test("the frozen Claude App pill keeps the Mac's name and colour (no session reaches it: its sessions are Claude Code's), and every other agent's name is still its tag", () => {
  assert.equal(agentPillName("claude-desktop"), "Claude App");
  assert.equal(agentLabel("agent_claude-desktop"), "Claude App");
  assert.equal(agentColor("claude-desktop"), "#E3A857");
  for (const tag of ["gemini", "antigravity", "codex", "my-agent", "claude"]) assert.equal(agentPillName(tag), tag, tag);
});

test("hooks.ts gives the pill it creates that colour, and no longer hashes by itself", () => {
  const hooks = read("../../src/island/hooks.ts");
  assert.match(hooks, /import \{ agentColor, agentPillName \} from "\.\.\/core\/pills\.ts";/);
  assert.match(hooks, /State\.upsertExternalAgent\(agentId, agentPillName\(validAgent!\), agentColor\(validAgent!\)\)/);
  assert.doesNotMatch(hooks, /FALLBACK_COLORS/, "the hash lives in pills.ts only");
});
