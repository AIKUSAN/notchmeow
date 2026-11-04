// The shelf's two backends (sub-project G1): Rust's commands inside the app, and a small in-memory shelf in a plain browser, so that `npm run dev` and the `?dev` page show the
// shelf working with no app behind it. The in-memory one runs the contract's own rules (rules.ts), so it refuses and caps exactly as Rust does.

import { Bridge } from "../core/bridge";
import { shelfAdd, type AddWord, type ShelfItem } from "./rules.ts";
import type { ShelfBackend, ShelfEntry } from "./store.ts";

/** Rust's commands. */
export function bridgeBackend(): ShelfBackend {
  return {
    list: () => Bridge.shelfList(),
    add: (paths) => Bridge.shelfAdd(paths),
    remove: (id) => Bridge.shelfRemove(id),
    clear: () => Bridge.shelfClear(),
  };
}

/** A shelf in memory. `sizes` and `gone` let the `?dev` panel pick a size and mark an original as missing. */
export function mockBackend(seed: ShelfItem[] = [], gone: Set<string> = new Set()): ShelfBackend & { items: ShelfItem[]; gone: Set<string> } {
  let n = 0;
  const entries = (): ShelfEntry[] => self.items.map((i) => ({ id: i.id, name: i.name, size: i.size, folder: i.folder, copy: i.copy, addedAt: i.addedAt, missing: self.gone.has(i.id) }));
  const self = {
    items: [...seed],
    gone,
    list: async () => entries(),
    add: async (paths: string[]) => {
      const now = Date.now();
      const incoming = paths.map((p) => {
        const name = p.split(/[\\/]/).pop() ?? "";
        const folder = !name.includes(".");
        return { id: `m${now.toString(36)}${n++}`, name, size: folder ? 0 : (name.length * 7919) % 900000 + 1200, folder, copy: false, link: p, addedAt: now };
      });
      const res = shelfAdd(self.items, incoming);
      self.items = res.items;
      return { entries: entries(), results: res.results as AddWord[] };
    },
    remove: async (id: string) => { self.items = self.items.filter((i) => i.id !== id); return entries(); },
    clear: async () => { self.items = []; return entries(); },
  };
  return self;
}
