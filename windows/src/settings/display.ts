// Settings → Cat → Display (sub-project B, spec §1): how the cats are shown. One cat (the Main cat everywhere, the default), A cat for each agent, or Two cats (a
// pair, side by side). The rows are built from the Settings window's own styles (.row, select, .hint, button); the new rules in settings.css are new class names only.
//   - the Display picker, with a small live preview of the compact island in the chosen mode (sample agents, the real cats);
//   - the pair's two pickers (Two cats mode only);
//   - "Cats for your agents" (A cat for each agent mode only): each agent's colour, a live preview, a cat picker, a dice and "Reset to defaults".
// The previews are live engines. They draw only while the Settings window can be seen and has focus: the Cat section's one loop (cat/loop.ts) calls `draw`, and nothing here runs a loop.
// Task 10: the Display card, the pair's card and the agents' card are built by cat.ts (which shows the last two only in their mode), so this file returns their rows.

import { BotEngine } from "../cat/engine";
import { assignAgentCats, rerollAgentCat } from "../cat/agentcat";
import { bigCatCollar } from "../cat/collar";
import { castOf } from "../cat/cast";
import type { Cast, CastTask } from "../cat/cast";
import { rng } from "../cat/base";
import { MINI_CELL, MINI_GRID } from "../cat/greeting";
import { CAT_IDS, PRESETS } from "../cat/presets";
import { cleanCatBlock, defaultAgentCat, isAgentPill, withAgentCat, withAgentCats, withDisplayMode, withPair } from "../cat/display";
import type { CatBlock, DisplayMode } from "../cat/display";
import { COMPACT_W, NOTCH_H, botPosition, pairPlacement } from "../core/layout";
import { agentLabel, pillColor } from "../core/pills";
import { h } from "../views/dom";
import { setValue } from "./kit.ts";

/** What the section needs from the Cat section: the `cat` block as it is now, and a place to put the new one. */
export interface DisplayHost {
  block(): CatBlock;
  put(next: CatBlock, final: boolean): void;
}

/** The Cat section's own helpers (cat.ts), so the rows here look the same and nothing is repeated. */
export interface UiKit {
  menu(options: readonly (readonly [string, string])[], onChange: (v: string) => void): HTMLSelectElement;
  row(label: string, ...controls: (Node | string)[]): HTMLElement;
  sized(cv: HTMLCanvasElement, w: number, ht: number): void;
}

const MODES: readonly (readonly [DisplayMode, string])[] = [["one", "One cat"], ["perAgent", "A cat for each agent"], ["two", "Two cats"]];
const MODE_HINT: Record<DisplayMode, string> = {
  one: "Your Main cat everywhere, as it has always been.",
  perAgent: "Every agent has its own cat. Claude Code is Shrimpy by default; any other agent gets a coat of its own the first time it appears, and keeps it.",
  two: "Your pair side by side: cat 1 shows the focused agent, cat 2 the busiest other agent. They sleep together.",
};

/** The compact island in the preview is drawn at this scale, so the cats can be judged: it is the real compact drawing magnified, never a bigger cat. */
const SCALE = 1.5;
const AGENT_PREVIEW = 40;
/** The agents of the preview, in the island's order; the first is focused. A coat that the user has not stored for one of them is a seeded sample and is never stored. */
const SAMPLE: readonly (CastTask & { color: string })[] = [
  { id: "integration_claude", state: "working", last: 5, color: pillColor("integration_claude") },
  { id: "agent_codex", state: "approval", last: 4, color: "#2DD4BF" },
  { id: "agent_gemini", state: "thinking", last: 3, color: pillColor("agent_gemini") },
  { id: "agent_antigravity", state: "idle", last: 2, color: pillColor("agent_antigravity") },
  { id: "integration_stripe", state: "idle", last: 1, color: "#0570DE" },
];

/** Claude Code first, then every other agent that has a stored coat. */
const agentIds = (b: CatBlock): string[] => ["integration_claude", ...Object.keys(b.agentCats).filter((id) => id !== "integration_claude" && isAgentPill(id))];

/** One cat of the preview: where it sits in the compact island (px), its collar colour, and whether it is a big cat (badge on the left, ears fitted under the top of the strip). */
interface PreviewCat { e: BotEngine; x: number; y: number; d: number; collar: string | null; big: boolean }

export function displayRows(host: DisplayHost, ui: UiKit) {
  const now = (): CatBlock => cleanCatBlock(host.block());
  const change = (next: CatBlock) => host.put(next, true);
  const catOptions = CAT_IDS.map((id) => [id, PRESETS[id].label] as const);

  // The Display row, with what the chosen mode does.
  const mode = ui.menu(MODES, (v) => change(withDisplayMode(now(), v)));
  const hint = h("span", { class: "hint" });
  const modeRow = ui.row("Display", mode, hint);

  // A small live preview of the compact island in the chosen mode: the big cat (or the pair) at the left, the grid of the other agents at the right.
  const notchCv = h("canvas", { "aria-label": "Preview of the compact island in this mode" });
  ui.sized(notchCv, COMPACT_W * SCALE, NOTCH_H * SCALE);
  const notch = h("div", { class: "cat-notch" }, notchCv);
  let cast: Cast = castOf("one", {});
  const engines = new Map<string, BotEngine>();
  let cats: PreviewCat[] = [];
  const engineFor = (key: string, coat: string, state: string): BotEngine => {
    let e = engines.get(key);
    if (!e) { e = new BotEngine(PRESETS[coat], { mini: true }); engines.set(key, e); }
    if (e.p.name !== coat) e.setCoat(coat);
    e.setState(state);
    return e;
  };

  // The pair's two pickers.
  const pair = [0, 1].map((i) => {
    const m = ui.menu(catOptions, (v) => change(withPair(now(), i as 0 | 1, v)));
    return { m, el: ui.row(`Pair, cat ${i + 1}`, m, h("span", { class: "hint", text: i === 0 ? "Shows the focused agent." : "Shows the busiest other agent." })) };
  });

  // Cats for your agents.
  const agentRows = h("div", { class: "cat-agents" });
  const reset = h("button", { text: "Reset to defaults", onclick: () => { const b = now(); change(withAgentCats(b, assignAgentCats(agentIds(b), {}, b.character, Math.random))); } });
  const agents = h("div", { class: "cat-agents-box" },
    h("div", { class: "hint", text: "Cats for your agents: Claude Code and every agent NotchMeow has seen. A dice rolls a new random cat." }), agentRows, reset);
  let agentsKey = "";
  let agentPreviews: { id: string; e: BotEngine; cv: HTMLCanvasElement }[] = [];
  const buildAgents = (b: CatBlock) => {
    agentRows.replaceChildren();
    agentPreviews = [];
    for (const id of agentIds(b)) {
      const coat = b.agentCats[id] ?? defaultAgentCat(id) ?? b.character, color = pillColor(id);
      const cv = h("canvas", { "aria-label": `${agentLabel(id)}'s cat` });
      ui.sized(cv, AGENT_PREVIEW, AGENT_PREVIEW);
      const e = new BotEngine(PRESETS[coat], { mini: true });
      e.collarColor = color;
      agentPreviews.push({ id, e, cv });
      const pick = ui.menu(catOptions, (v) => change(withAgentCat(now(), id, v)));
      pick.value = coat;
      pick.setAttribute("aria-label", `Cat for ${agentLabel(id)}`);
      const dice = h("button", { class: "dice", title: "Roll a new random cat", "aria-label": `A new random cat for ${agentLabel(id)}`, text: "\u{1F3B2}", onclick: () => {
        const b2 = now();
        change(withAgentCats(b2, rerollAgentCat(id, b2.agentCats, b2.character, Math.random).agentCats));
      } });
      agentRows.append(h("div", { class: "row cat-agent" }, h("span", { class: "cat-agent-cv" }, cv), h("i", { class: "dot", style: `background:${color}` }), h("label", { text: agentLabel(id) }), pick, dice));
    }
  };

  /** Everything that follows the stored block: the controls, the agents' list and the preview's cast. */
  function sync() {
    const b = now();
    setValue(mode, b.displayMode);
    hint.textContent = MODE_HINT[b.displayMode];
    pair.forEach((p, i) => setValue(p.m, b.pair[i]));
    const key = agentIds(b).map((id) => `${id}:${b.agentCats[id] ?? ""}`).join("|");
    if (key !== agentsKey) { agentsKey = key; buildAgents(b); }
    // The preview: the sample agents in the chosen mode, with the user's Main cat, pair and agents' coats. A sample agent with no coat of its own gets a seeded one, never stored.
    const coats = assignAgentCats(SAMPLE.map((s) => s.id), b.agentCats, b.character, rng(7));
    cast = castOf(b.displayMode, { tasks: SAMPLE, focusId: SAMPLE[0].id, mainCat: b.character, pair: b.pair, agentCats: coats });
    const sample = (id: string | null) => SAMPLE.find((s) => s.id === id);
    const two = pairPlacement("compact", "overview", NOTCH_H), one = botPosition("compact", "overview", NOTCH_H);
    const next: PreviewCat[] = [];
    const bigState = sample(cast.big.pill)?.state ?? "idle";
    next.push({ e: engineFor("big", cast.big.cat, bigState), x: cast.second && two ? two.first.cx : one.cx, y: one.cy, d: one.diameter, collar: bigCatCollar(bigState, sample(cast.big.pill)?.color), big: true });
    if (cast.second && two) {
      const st = sample(cast.second.pill)?.state ?? "idle";
      next.push({ e: engineFor("second", cast.second.cat, st), x: two.second.cx, y: two.second.cy, d: two.second.diameter, collar: bigCatCollar(st, sample(cast.second.pill)?.color), big: true });
    }
    const gx = COMPACT_W - MINI_CELL.inset, gy = NOTCH_H / 2, s = MINI_CELL.step / 2;
    cast.pills.slice(0, 4).forEach((p, i) => {
      const t = sample(p.pill);
      if (t) next.push({ e: engineFor(`grid${i}`, p.cat, t.state), x: gx + (i % 2 ? s : -s), y: gy + (i < 2 ? -s : s), d: MINI_GRID.d, collar: t.color, big: false });
    });
    cats = next;
  }

  /** One frame of every preview, `dt` seconds after the last (the Cat section's loop calls it only while the window can be seen and has focus). */
  function draw(dt: number) {
    const dpr = Math.min(2, window.devicePixelRatio || 1), ctx = notchCv.getContext("2d");
    if (ctx) {
      ctx.setTransform(dpr * SCALE, 0, 0, dpr * SCALE, 0, 0);
      ctx.clearRect(0, 0, COMPACT_W, NOTCH_H);
      ctx.fillStyle = "#000"; ctx.beginPath(); ctx.roundRect(0, 0, COMPACT_W, NOTCH_H, [0, 0, 14, 14]); ctx.fill();
      for (const c of cats) {
        const w = c.d / 0.6;
        c.e.collarColor = c.collar; c.e.badgeLeft = c.big; c.e.earRoom = c.big ? c.y : null;
        c.e.update(dt);
        ctx.save(); ctx.translate(c.x - w / 2, c.y - w / 2); c.e.draw(ctx, w, w); ctx.restore();
      }
    }
    for (const a of agentPreviews) {
      const actx = a.cv.getContext("2d");
      if (!actx) continue;
      actx.setTransform(dpr, 0, 0, dpr, 0, 0); actx.clearRect(0, 0, AGENT_PREVIEW, AGENT_PREVIEW);
      a.e.update(dt); a.e.draw(actx, AGENT_PREVIEW, AGENT_PREVIEW);
    }
  }

  return { before: [modeRow, notch], pair: pair.map((p) => p.el), agents, sync, draw };
}
