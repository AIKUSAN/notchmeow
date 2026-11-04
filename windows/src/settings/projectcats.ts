// Settings → Cat → Agents' cats → Project cats (sub-project P, Task 9): each live project's folder name and a cat picker, a live preview and Reset for a stored one, and
// the stored names that no live project has. The island says the live names (`projects-live`, app.ts); nothing else crosses windows: a folder name and the cat, never a path.
// The rows look like "Cats for your agents" (.row.cat-agent, .cat-agent-cv). The previews draw only through the Cat section's loop (`draw`); nothing here runs a timer.

import { BotEngine } from "../cat/engine";
import { CAT_IDS, PRESETS } from "../cat/presets";
import { cleanCatBlock, withProjectCat, withoutProjectCat } from "../cat/display";
import type { CatBlock } from "../cat/display";
import { CATS_HELP, EMPTY_SETTINGS, projectCatRows, type CatRow, type LiveProject } from "../projects/present.ts";
import { h } from "../views/dom";
import { button, card, forceValues, help, row, setValue } from "./kit.ts";
import type { UiKit } from "./display";

/** What the card needs from the Cat section: the `cat` block as it is now, a place to put the new one, and the live projects. */
export interface ProjectCatsHost {
  block(): CatBlock;
  put(next: CatBlock, final: boolean): void;
  live(): readonly LiveProject[];
}

const CELL = 40;
const catOptions = CAT_IDS.map((id) => [id, PRESETS[id].label] as const);

export function projectCatsCard(host: ProjectCatsHost, ui: Pick<UiKit, "menu" | "sized">): { el: HTMLElement; sync(): void; draw(dt: number): void } {
  const now = (): CatBlock => cleanCatBlock(host.block());
  const slot = h("div", { class: "cat-agents" });
  // One engine per row, drawn by `draw`. A row whose cat changes is rebuilt, so an engine never changes its coat.
  let rows: { r: CatRow; pick: HTMLSelectElement; e: BotEngine; cv: HTMLCanvasElement }[] = [];
  let key = "";

  /** The rows as the stored names and the live projects give them; none at all shows the Mac's empty words. */
  function build(list: readonly CatRow[]): void {
    slot.replaceChildren();
    rows = [];
    if (list.length === 0) {
      slot.append(help(EMPTY_SETTINGS));
      return;
    }
    for (const r of list) {
      const cv = h("canvas", { "aria-label": `${r.name}'s cat` });
      ui.sized(cv, CELL, CELL);
      const e = new BotEngine(PRESETS[r.cat], { mini: true });
      const pick = ui.menu(catOptions, (v) => {
        host.put(withProjectCat(now(), r.catKey, v), true);
        // A refused pick (the 256 cap) gives the block back unchanged, and sync skips a control in use: the picker shows the cat the block holds now, even while it has focus.
        forceValues(() => setValue(pick, catNow(r.catKey, r.cat)), pick);
      });
      pick.setAttribute("aria-label", `Cat for ${r.name}`);
      const reset = r.stored ? button("Reset", () => host.put(withoutProjectCat(now(), r.catKey), true)) : null;
      reset?.setAttribute("aria-label", `Reset the cat for ${r.name}`);
      rows.push({ r, pick, e, cv });
      slot.append(row(r.name, [h("span", { class: "cat-agent-cv" }, cv), pick, ...(reset ? [reset] : [])]));
    }
  }

  /** Everything that follows the stored block and the live names. A picker in use keeps its value (setValue). */
  function sync(): void {
    const b = now();
    const list = projectCatRows(host.live(), b.projectCats, b.character);
    const next = JSON.stringify(list);
    if (next !== key) { key = next; build(list); }
    for (const row of rows) setValue(row.pick, row.r.cat);
  }

  /** The cat the block holds for a folder now (its stored cat, else the one the project gets); `fallback` when the folder is not listed. Read fresh, never from the last build. */
  function catNow(catKey: string, fallback: string): string {
    const b = now();
    return projectCatRows(host.live(), b.projectCats, b.character).find((x) => x.catKey === catKey)?.cat ?? fallback;
  }

  /** One frame of every preview, `dt` seconds after the last. */
  function draw(dt: number): void {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    for (const row of rows) {
      const ctx = row.cv.getContext("2d");
      if (!ctx) continue;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, CELL, CELL);
      row.e.update(dt);
      row.e.draw(ctx, CELL, CELL);
    }
  }

  // The 256 help line sits below the rows (CatSettingsView.swift), as the Mac puts it.
  const el = card("Project cats", null, slot, help(CATS_HELP));
  sync();
  return { el, sync, draw };
}
