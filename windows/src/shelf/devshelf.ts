// The `?dev` page's "Shelf" panel (sub-project G1), the Windows/Linux counterpart of the Mac's Debug shelf panel: the real shelf view inside an island frame, fed by a shelf in memory that
// runs the contract's own rules, with buttons for every state worth looking at (a few files, a full shelf and its note, a folder, a missing original, ticks, the system's abilities
// switched on and off), the half-of-the-island probe, and the compact badge. Open http://127.0.0.1:1420/?dev with `npx vite` (no Tauri window needed). Only the dev server serves it:
// main.ts loads dev.ts behind `import.meta.env.DEV`, so a release build does not contain it.

import { BotEngine } from "../cat/engine.ts";
import { PRESETS } from "../cat/presets.ts";
import { State } from "../core/state.ts";
import { buildShelf } from "../views/shelf.ts";
import { COMPACT_W, NOTCH_H } from "../core/layout.ts";
import type { IslandMode } from "../core/layout.ts";
import { badgeLabel, badgePlace, badgeShown, badgeTitle } from "./badge.ts";
import { mockBackend } from "./backend.ts";
import { zoneAt } from "./rules.ts";
import { THEME } from "../theme.generated.ts";

const B = THEME.brand;
const BTN = `font:inherit;font-size:12px;color:${B.ink};background:${B.button};border:1px solid ${B.line};border-radius:8px;padding:4px 10px;cursor:pointer`;

const NAMES = ["report.pdf", "photo.png", "notes.md", "build.zip", "main.rs", "Screenshot 2026-10-14 at 09.41.png", "budget.xlsx", "talk.key", "logo.svg", "todo.txt", "invoice-0042.pdf", "recording.m4a"];

function button(label: string, onclick: () => void): HTMLButtonElement {
  const b = document.createElement("button");
  b.style.cssText = BTN; b.textContent = label; b.onclick = onclick;
  return b;
}

export function mountShelfDev(root: HTMLElement, before: Node | null): void {
  const mock = mockBackend();
  State.shelf.attach(mock);
  State.shelfCaps = { dragOut: true, send: true };
  const log: string[] = [];
  const said = (line: string) => { log.push(line); refresh(); };
  const act = {
    ask: (id: string) => said(`ask ${id}`),
    send: (ids: string[]) => said(`send ${ids.join(",")}`),
    reveal: (id: string) => said(`reveal ${id}`),
    dragOut: (ids: string[]) => said(`dragOut ${ids.join(",")}`),
  };
  const view = buildShelf(act);
  view.el.classList.add("on");

  const box = document.createElement("section");
  box.id = "shelf-dev";
  box.style.cssText = `background:${B.panel};border:1px solid ${B.line};border-radius:16px;padding:16px;margin-bottom:20px`;
  box.innerHTML = `<h2 style="font-size:17px;font-weight:600;margin:0 0 2px">Shelf</h2>
    <p style="color:${B.dim};margin:0 0 12px;font-size:13px">The shelf view in its island, fed by a shelf in memory that follows the contract (at most 30, newest first, an overflow is refused, a re-dropped file is a duplicate). Hover a tile for its buttons, click one to tick it. The buttons below fill the shelf; "Sent to" shows what the tiles asked for.</p>`;

  // The island frame: 640 x 176, the card 620 x 124 where the island puts it, the cat at the view's place.
  const stage = document.createElement("div");
  stage.style.cssText = "position:relative;width:640px;height:176px;background:#000;border-radius:0 0 22px 22px;overflow:hidden;margin:6px 0 12px";
  const slot = document.createElement("div");
  slot.style.cssText = "position:absolute;left:10px;right:10px;top:42px;bottom:10px";
  slot.append(view.el);
  const cat = document.createElement("canvas");
  const D = 44 / 0.6, dpr = Math.min(2, devicePixelRatio || 1);
  cat.width = Math.round(D * dpr); cat.height = Math.round(D * dpr);
  cat.style.cssText = `position:absolute;left:${46 - D / 2}px;top:${108 - D / 2}px;width:${D}px;height:${D}px;pointer-events:none`;
  const engine = new BotEngine(PRESETS.shrimpy, { quiet: true, now: () => 0, rand: () => 0.5 });
  const paintCat = () => {
    const c = cat.getContext("2d")!;
    c.setTransform(dpr, 0, 0, dpr, 0, 0); c.clearRect(0, 0, D, D);
    engine.update(1 / 60); engine.draw(c, D, D);
  };
  stage.append(slot, cat);
  box.append(stage);

  const bar = document.createElement("div");
  bar.style.cssText = "display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px";
  let n = 0;
  const paths = (count: number) => Array.from({ length: count }, () => `C:/Users/me/${NAMES[n++ % NAMES.length].replace(/(\.\w+)?$/, (m) => (n > NAMES.length ? ` ${Math.floor(n / NAMES.length)}${m}` : m))}`);
  const refresh = () => { view.sync(); sent.textContent = log.slice(-4).join("  |  ") || "nothing yet"; };
  const add = (count: number) => () => void State.shelf.add(paths(count)).then(refresh);
  bar.append(
    button("Drop 3 files", add(3)),
    button("Drop 12", add(12)),
    button("Fill to 30", () => void State.shelf.add(paths(30)).then(refresh)),
    button("Drop 5 more", add(5)),
    button("Drop a folder", () => void State.shelf.add(["C:/Users/me/Projects/notes"]).then(refresh)),
    button("Re-drop the first", () => void State.shelf.add([`C:/Users/me/${State.shelf.entries.at(-1)?.name ?? "x"}`]).then(refresh)),
    button("First one missing", () => { const id = State.shelf.entries[0]?.id; if (id) mock.gone.add(id); void State.shelf.refresh().then(refresh); }),
    button("Tick two", () => { for (const e of State.shelf.entries.slice(0, 2)) State.shelf.toggle(e.id); refresh(); }),
    button("Clear", () => void State.shelf.clear().then(refresh)),
  );
  box.append(bar);

  const caps = document.createElement("div");
  caps.style.cssText = "display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px;align-items:center";
  const toggle = (label: string, key: "dragOut" | "send") => {
    const b = button("", () => { State.shelfCaps = { ...State.shelfCaps, [key]: !State.shelfCaps[key] }; sync(); refresh(); });
    const sync = () => { b.textContent = `${label}: ${State.shelfCaps[key] ? "on" : "off"}`; b.style.borderColor = State.shelfCaps[key] ? B.accent : B.line; };
    sync();
    caps.append(b);
  };
  toggle("Drag out", "dragOut");
  toggle("Send (Windows share)", "send");
  box.append(caps);

  const sent = document.createElement("pre");
  sent.id = "shelf-dev-sent";
  sent.style.cssText = `color:${B.dim};font-size:12px;margin:0 0 10px;white-space:pre-wrap`;
  const sentRow = document.createElement("div");
  sentRow.style.cssText = `font-size:12px;color:${B.dim}`;
  sentRow.append("Sent to: ", sent);
  box.append(sentRow);

  // The compact island's badge: the same rule and place the island uses, on a compact island drawn here, with the island's mode to choose (it shows only while compact).
  let mode: IslandMode = "compact";
  const compact = document.createElement("div");
  compact.style.cssText = `position:relative;width:${COMPACT_W}px;height:${NOTCH_H}px;background:#000;border-radius:0 0 14px 14px;margin:10px 0 6px`;
  const badge = document.createElement("button");
  badge.id = "shelf-badge";
  compact.append(badge);
  const paintBadge = () => {
    const place = badgePlace(COMPACT_W, NOTCH_H), shown = badgeShown(mode, State.shelf.count, false);
    badge.style.left = `${place.left}px`; badge.style.top = `${place.top}px`;
    badge.textContent = badgeLabel(State.shelf.count); badge.title = badgeTitle(State.shelf.count);
    badge.style.opacity = shown ? "1" : "0"; badge.style.pointerEvents = shown ? "auto" : "none";
  };
  const modes = document.createElement("div");
  modes.style.cssText = "display:flex;gap:6px;align-items:center;font-size:12px;margin-bottom:8px";
  const modeButtons = (["compact", "hidden", "expanded"] as const).map((m) => {
    const b = button(m, () => { mode = m; modeButtons.forEach((x) => (x.style.borderColor = x === b ? B.accent : B.line)); paintBadge(); });
    return b;
  });
  modeButtons[0].style.borderColor = B.accent;
  modes.append("Island:", ...modeButtons);
  box.append(compact, modes);
  State.subscribe(paintBadge);
  paintBadge();

  // Which half a pointer is in: the contract's zoneAt on a 640 px island.
  const probe = document.createElement("div");
  probe.style.cssText = "display:flex;gap:10px;align-items:center;font-size:12px";
  const slider = document.createElement("input");
  slider.type = "range"; slider.min = "-20"; slider.max = "660"; slider.value = "100"; slider.style.width = "320px"; slider.id = "shelf-dev-x";
  const readout = document.createElement("span");
  readout.id = "shelf-dev-zone";
  const probeZone = () => { const x = Number(slider.value), z = zoneAt(x, 640); readout.textContent = `x = ${x}: ${z ?? "outside the island"}`; };
  slider.oninput = probeZone;
  probeZone();
  probe.append("Pointer x on a 640 px island", slider, readout);
  box.append(probe);

  root.insertBefore(box, before);
  // What the island does for every State change: draw the view again (it redraws only when what it shows changed).
  State.subscribe(refresh);
  State.shelf.attach(mock);
  void State.shelf.refresh().then(refresh);
  // The cat is drawn a few frames and then left: the panel is a still picture of the view, not an animation.
  let frames = 0;
  const tick = () => { paintCat(); if (++frames < 30) requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
}
