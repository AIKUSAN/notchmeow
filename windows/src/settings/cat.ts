// Settings → Cat (spec §4; Settings restyle, Task 10): which cat lives in the notch, how it moves, its personality, its collar, the fur lines, the desktop switch, and the Display and
// Wardrobe cards. The Cat page has four tabs (CatTab): Look (Main cat, Look, Desktop), Outfits (Wardrobe), Personality (Personality, Motion, Every cat) and Agents' cats (Display,
// Your two cats, Cats for your agents, Project cats). A null tab gives every card in that order (the old long page in main.ts). Built from the window's own rows (.row, select, range, .switch);
// the new rules in settings.css are new class names only. The previews are live engines that draw only while this window can be seen: one VisibleLoop (cat/loop.ts) per tab,
// stopped by dispose, and it draws only the canvases this tab built. display.ts and wardrobe.ts draw through it too.

import { BotEngine, catCfg } from "../cat/engine";
import { VisibleLoop } from "../cat/loop";
import { PERSONAS, TRAITS, personaNamed, slide } from "../cat/personality";
import { CAT_IDS, PRESETS } from "../cat/presets";
import { cleanCatBlock, withCatSettings, withDesktopOn, type CatBlock } from "../cat/display";
import {
  COLLAR_STYLES, FOLLOW, MOTION_STYLES, applyCatSettings, applyToAllCats, cleanCatSettings, withCatCollar, withCatMotion, withCharacter, withCollar, withFurLines,
  withMotionStyle, withPersonality, type CatSettings,
} from "../cat/settings";
import type { LiveProject } from "../projects/present.ts";
import { h } from "../views/dom";
import { card, help, setValue } from "./kit.ts";
import { displayRows } from "./display";
import { wardrobeSection } from "./wardrobe";
import { projectCatsCard } from "./projectcats.ts";

/** The four tabs of Settings → Cat, in the sidebar's order. */
export type CatTab = "look" | "outfits" | "personality" | "agentcats";
const TABS: readonly CatTab[] = ["look", "outfits", "personality", "agentcats"];

/** What the section needs from the window: the `cat` block as it is now (the Cat settings and the Display settings), and a place to put the new one. */
export interface CatHost {
  cat(): CatBlock;
  /** `final` is false while a slider is still moving: update, but do not save yet. */
  put(next: CatBlock, final: boolean): void;
  /** A line under the desktop cat's switch where the system does not let the app place windows (GNOME); null or missing elsewhere. */
  desktopNote?: string | null;
  /** The live projects' folder names (the island's, sent to this window): Project cats lists them. */
  projects?: () => readonly LiveProject[];
}

const CELL = 48;
const PREVIEW_W = 140;
const PREVIEW_H = 150;
const STACK = "display:flex;flex-direction:column;gap:12px";
const WORDS: Record<string, string> = { playful: "Playful", classic: "Classic" };
const COLLARS: Record<string, string> = { tag: "Band and tag", band: "Band", kerchief: "Neckerchief", off: "Off" };
/** The big preview's collar colour: no agent is driving it, so it wears a sample, to show the style. */
const SAMPLE_COLLAR = "#F29B38";

function sized(cv: HTMLCanvasElement, w: number, ht: number) {
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  cv.width = Math.round(w * dpr);
  cv.height = Math.round(ht * dpr);
  cv.style.width = `${w}px`;
  cv.style.height = `${ht}px`;
}

function menu(options: readonly (readonly [string, string])[], onChange: (v: string) => void): HTMLSelectElement {
  const el = h("select", {});
  for (const [value, text] of options) el.append(h("option", { value, text }));
  el.addEventListener("change", () => onChange(el.value));
  return el;
}

const row = (label: string, ...controls: (Node | string)[]) => h("div", { class: "row" }, h("label", { text: label }), ...controls);

export function catSection(host: CatHost, tab: CatTab | null = null): { el: HTMLElement; sync(): void; dispose(): void } {
  const want = (t: CatTab): boolean => tab === null || tab === t;
  const now = (): CatSettings => cleanCatSettings(host.cat());
  // A row edits the Cat settings (the whole block keeps its Display settings) or, from the Display rows, the whole block.
  const change = (next: CatSettings | CatBlock, final = true) => {
    host.put(withCatSettings(host.cat(), next), final);
    paint();
  };
  // The cards of each tab, in the tab's order. A tab's engines and canvases are built only when that tab is shown.
  const groups: Record<CatTab, HTMLElement[]> = { look: [], outfits: [], personality: [], agentcats: [] };

  // Main cat: sixteen small live previews, and one big one of the chosen cat. It is the cat of One cat mode, of the integration pills and of the big cat when no agent is focused.
  const cells = new Map<string, { btn: HTMLButtonElement; cv: HTMLCanvasElement; e: BotEngine }>();
  const grid = h("div", { class: "cat-grid", role: "group", "aria-label": "Main cat" });
  const previewCv = h("canvas", {});
  sized(previewCv, PREVIEW_W, PREVIEW_H);
  let preview: BotEngine | null = null; // wears catCfg.character: the cat chosen above
  if (want("look")) {
    for (const id of CAT_IDS) {
      const cv = h("canvas", {});
      sized(cv, CELL, CELL);
      const btn = h("button", { class: "cat-cell", "aria-pressed": "false", title: PRESETS[id].desc ? `${PRESETS[id].label} · ${PRESETS[id].desc}` : PRESETS[id].label, onclick: () => change(withCharacter(now(), id)) },
        cv, h("span", { text: PRESETS[id].label }));
      cells.set(id, { btn, cv, e: new BotEngine(PRESETS[id], { mini: true }) });
      grid.append(btn);
    }
    preview = new BotEngine();
    preview.particleOverhang = 40;
    preview.collarColor = SAMPLE_COLLAR;
  }

  const whose = h("span", { class: "hint" });
  const motion = menu(MOTION_STYLES.map((m) => [m, WORDS[m]] as const), (v) => change(withMotionStyle(now(), v)));
  const catMotion = menu([[FOLLOW, "Follow the global style"], ...MOTION_STYLES.map((m) => [m, WORDS[m]] as const)], (v) => { const s = now(); change(withCatMotion(s, s.character, v)); });
  const catWhose = h("span", { class: "hint" });
  const collar = menu(COLLAR_STYLES.map((m) => [m, COLLARS[m]] as const), (v) => change(withCollar(now(), v)));
  const catCollar = menu([[FOLLOW, "Follow the global collar"], ...COLLAR_STYLES.map((m) => [m, COLLARS[m]] as const)], (v) => { const s = now(); change(withCatCollar(s, s.character, v)); });
  const collarWhose = h("span", { class: "hint" });

  // Personality: a preset menu (Custom shows once a slider has moved) and the six sliders.
  const custom = h("option", { value: "custom", text: "Custom", disabled: true });
  const preset = menu(Object.keys(PERSONAS).map((k) => [k, PERSONAS[k].label] as const), (v) => { const s = now(); change(withPersonality(s, s.character, personaNamed(v))); });
  preset.append(custom);
  const sliders = TRAITS.map(([key, label, low, high]) => {
    const input = h("input", { type: "range", min: "0", max: "1", step: "0.01", value: "0.5", "aria-label": label });
    const move = (final: boolean) => () => {
      const s = now();
      change(withPersonality(s, s.character, slide(s.cats[s.character].personality, key, Number(input.value))), final);
    };
    input.addEventListener("input", move(false));
    input.addEventListener("change", move(true));
    const el = row(label, h("span", { class: "hint cat-low", text: low }), input, h("span", { class: "hint cat-high", text: high }));
    el.classList.add("cat-trait");   // one line at every width the window can have (settings.css)
    return { key, input, el };
  });

  const applied = h("span", { class: "hint" });
  let timeoutId = 0;
  const apply = h("button", { text: "Apply to every cat", onclick: () => {
    const s = now();
    change(applyToAllCats(s, s.character));
    applied.textContent = `Done: all ${CAT_IDS.length} cats now share this cat's motion, personality and collar.`;
    window.clearTimeout(timeoutId);
    timeoutId = window.setTimeout(() => { applied.textContent = ""; }, 3000);
  } });

  const fur = h("button", { class: "switch", "aria-pressed": "false", onclick: () => change(withFurLines(now(), !now().furLines)) });
  // Cat on the desktop (sub-project H): the same switch as the tray's item and the cat's own menu. The island sees the stored "out" change and sends the cat on its trip.
  const desktop = h("button", { class: "switch", "aria-pressed": "false", "aria-label": "Cat on the desktop", onclick: () => change(withDesktopOn(host.cat(), !host.cat().desktop.on)) });

  // Look: Main cat, Look and Desktop.
  if (want("look")) {
    groups.look.push(
      card("Main cat", null,
        help("Pick the cat that lives in your notch. Each cat keeps its own motion, personality and collar."),
        help("Main cat: the cat of One cat mode, of the integration pills (Stripe, Vercel…) and of the big cat when no agent is focused or running."),
        h("div", { class: "cat-top" }, grid, h("div", { class: "cat-preview" }, previewCv)),
      ),
      card("Look", null,
        row("Collar", collar, h("span", { class: "hint", text: "The agent's colour, worn by every cat. Off by default." })),
        row("This cat's collar", catCollar, collarWhose),
        row("Fur lines", fur, h("span", { class: "hint", text: "Strands on a big cat. Flat colour is the default." })),
      ),
      card("Desktop", null,
        row("Cat on the desktop", desktop, h("span", { class: "hint", text: "Drag the big cat out of the notch, or switch it here. Double-click it to send it home." })),
        ...(host.desktopNote ? [h("div", { class: "hint", text: host.desktopNote })] : []),
      ),
    );
  }

  // Outfits: the Wardrobe card (sub-project I). It shares this section's loop and its edits go through the same `change`, so the block keeps every part.
  const wardrobe = want("outfits") ? wardrobeSection({ block: () => host.cat(), put: (next, final) => change(next, final) }, { menu, row, sized }) : null;
  if (wardrobe) groups.outfits.push(wardrobe.el);

  // Personality: the preset, the sliders, the motion and the apply-to-all.
  if (want("personality")) {
    groups.personality.push(
      card("Personality", null, row("Personality", preset, whose), ...sliders.map((sl) => sl.el)),
      card("Motion", null,
        row("Motion style", motion, h("span", { class: "hint", text: "Classic moves like the original character." })),
        row("This cat's motion", catMotion, catWhose),
      ),
      card("Every cat", null, row("Apply to every cat", apply, applied)),
    );
  }

  // Agents' cats: the Display card, and the pair and the agents' cards, shown only in their own mode.
  const display = want("agentcats") ? displayRows({ block: () => host.cat(), put: (next, final) => change(next, final) }, { menu, row, sized }) : null;
  const pairCard = display ? card("Your two cats", null, ...display.pair) : null;
  const agentsCard = display ? card("Cats for your agents", null, display.agents) : null;
  if (display && pairCard && agentsCard) groups.agentcats.push(card("Display", null, ...display.before), pairCard, agentsCard);
  // Project cats: after the agents' cards, in every display mode (the projects have their own cats whatever the mode).
  const projects = want("agentcats") ? projectCatsCard({ block: () => host.cat(), put: (next, final) => change(next, final), live: () => host.projects?.() ?? [] }, { menu, sized }) : null;
  if (projects) groups.agentcats.push(projects.el);

  const paint = () => {
    const s = now(), id = s.character, mine = s.cats[id];
    const block = cleanCatBlock(host.cat());
    applyCatSettings(catCfg, s);
    for (const [cid, c] of cells) c.btn.setAttribute("aria-pressed", String(cid === id));
    setValue(motion, s.motionStyle);
    setValue(catMotion, mine.motion);
    setValue(collar, s.collar);
    setValue(catCollar, mine.collar);
    setValue(preset, mine.personality.preset);
    for (const sl of sliders) setValue(sl.input, String(mine.personality[sl.key]));
    fur.classList.toggle("on", s.furLines);
    fur.setAttribute("aria-pressed", String(s.furLines));
    const out = host.cat().desktop.on;
    desktop.classList.toggle("on", out);
    desktop.setAttribute("aria-pressed", String(out));
    whose.textContent = catWhose.textContent = collarWhose.textContent = `for ${PRESETS[id].label}`;
    if (pairCard) pairCard.hidden = block.displayMode !== "two";
    if (agentsCard) agentsCard.hidden = block.displayMode !== "perAgent";
    display?.sync();
    projects?.sync();
    wardrobe?.sync();
  };

  const drawOne = (e: BotEngine, cv: HTMLCanvasElement, w: number, ht: number, dt: number) => {
    const ctx = cv.getContext("2d");
    if (!ctx) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, ht);
    e.update(dt);
    e.draw(ctx, w, ht);
  };
  let disposed = false;
  // A loop only when this tab built something to draw: Personality, Motion and Every cat draw nothing, so they start none.
  const drawing = cells.size > 0 || preview !== null || display !== null || wardrobe !== null;
  const loop = new VisibleLoop(
    (dt) => {
      for (const c of cells.values()) drawOne(c.e, c.cv, CELL, CELL, dt);
      if (preview) drawOne(preview, previewCv, PREVIEW_W, PREVIEW_H, dt);
      display?.draw(dt);
      projects?.draw(dt);
      wardrobe?.draw(dt);
    },
    // The dev sample's pictures set dataset.shot (settings main.ts, dev route only), so a headless shot draws too; no real window sets it.
    {
      raf: (cb) => requestAnimationFrame(cb),
      caf: (id) => cancelAnimationFrame(id),
      visible: () => drawing && !disposed && document.visibilityState === "visible" && (document.hasFocus() || document.documentElement.dataset.shot === "1"),
    },
  );
  const onVisibility = (): void => loop.sync();
  const onFocus = (): void => loop.sync();
  const onBlur = (): void => loop.sync();
  document.addEventListener("visibilitychange", onVisibility);
  window.addEventListener("focus", onFocus);
  window.addEventListener("blur", onBlur);

  const dispose = (): void => {
    disposed = true;
    document.removeEventListener("visibilitychange", onVisibility);
    window.removeEventListener("focus", onFocus);
    window.removeEventListener("blur", onBlur);
    loop.sync();
  };

  const el = h("div", { style: STACK }, ...(tab === null ? TABS : [tab]).flatMap((t) => groups[t]));
  paint();
  loop.sync();
  return { el, sync: paint, dispose };
}
