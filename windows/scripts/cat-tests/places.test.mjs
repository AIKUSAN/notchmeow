import test from "node:test";
import assert from "node:assert/strict";
import { PAIR, VIEW_LAYOUTS, botPosition, pairPlacement } from "../../src/core/layout.ts";
import { AGENT_PILL_COLORS, agentColor, agentLabel, pillColor } from "../../src/core/pills.ts";

// The places of Two cats mode and the names and colours of the agents Settings lists.
test("compact: two Ø20 cats share the left ear, 24 px apart; the one cat is where it always was", () => {
  const p = pairPlacement("compact", "overview", 32);
  assert.deepEqual(p, { first: { cx: 30, cy: 16, diameter: 20, opacity: 1 }, second: { cx: 54, cy: 16, diameter: 20, opacity: 1 } });
  assert.deepEqual(botPosition("compact", "overview", 32), { cx: 40, cy: 16, diameter: 20, opacity: 1 }, "One cat mode keeps today's place");
  assert.equal(p.second.cx - p.first.cx, 24);
});

test("expanded, in the overview: cat 1 at Ø58 and cat 2 at Ø46 side by side around the card's middle; any other view or mode has no pair", () => {
  const h = VIEW_LAYOUTS.overview.height, mid = botPosition("expanded", "overview", h).cy, p = pairPlacement("expanded", "overview", h);
  assert.deepEqual(p.first, { cx: 56, cy: mid - 3, diameter: 58, opacity: 1 });
  assert.deepEqual(p.second, { cx: 114, cy: mid + 5, diameter: 46, opacity: 1 });
  assert.equal(p.second.cx - p.second.diameter / 2 - (p.first.cx + p.first.diameter / 2), 6); // the heads are side by side with a 6 px gap: the prototype's pair, cat 2 at 114
  assert.ok(p.first.cy + p.first.diameter / 2 <= h && p.second.cy + p.second.diameter / 2 <= h, "both heads inside the island");
  for (const view of Object.keys(VIEW_LAYOUTS)) if (view !== "overview") assert.equal(pairPlacement("expanded", view, VIEW_LAYOUTS[view].height), null, view);
  assert.equal(pairPlacement("hidden", "overview", 0), null);
  assert.deepEqual(PAIR.compact, { d: 20, x1: 30, x2: 54 });
});

test("agentLabel names an agent pill as the Mac does, and any other tag by itself; pillColor is the pill's colour", () => {
  for (const [id, name] of [["integration_claude", "Claude Code"], ["agent_gemini", "Gemini CLI"], ["agent_antigravity", "Antigravity"], ["agent_codex", "Codex"], ["agent_cursor", "Cursor"], ["agent_my-tool", "My-tool"], ["agent_x", "X"]]) assert.equal(agentLabel(id), name, id);
  for (const odd of ["agent_", "", "constructor", "__proto__", "integration_stripe"]) assert.equal(typeof agentLabel(odd), "string", odd);
  assert.equal(agentLabel("constructor"), "Constructor", "a prototype name is just a name");
  assert.equal(pillColor("integration_claude"), "#F5F6F8");
  assert.equal(pillColor("agent_gemini"), AGENT_PILL_COLORS.agent_gemini);
  assert.equal(pillColor("agent_my-agent"), agentColor("my-agent"));
  assert.match(pillColor("integration_stripe"), /^#[0-9A-F]{6}$/);
});
