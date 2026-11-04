// The shelf as the island's page holds it (sub-project G1): the list Rust last gave, which items are selected, and the short note after a drop. The files themselves are Rust's
// (src-tauri/src/shelf.rs); the page holds ids and never a path. Pure and DOM-free: the backend is handed in, so the plain-Node checks fake it.

import type { AddWord } from "./rules.ts";

/** What Rust says about one item. No path: the page never needs one. `missing`: its original is gone (looked at when the shelf is listed, never in the background). */
export interface ShelfEntry {
  id: string;
  name: string;
  size: number;
  folder: boolean;
  copy: boolean;
  addedAt: number;
  missing: boolean;
}

export interface ShelfBackend {
  list(): Promise<ShelfEntry[]>;
  add(paths: string[]): Promise<{ entries: ShelfEntry[]; results: AddWord[] }>;
  remove(id: string): Promise<ShelfEntry[]>;
  clear(): Promise<ShelfEntry[]>;
}

/** The short note under the tray after a drop, or null when every file went on. */
export function shelfNote(results: readonly AddWord[]): string | null {
  const full = results.filter((w) => w === "full").length, invalid = results.filter((w) => w === "invalid").length;
  if (full > 0) return full === 1 ? "The shelf is full (30). One file was left off." : `The shelf is full (30). ${full} files were left off.`;
  if (invalid > 0) return invalid === 1 ? "One file can't go on the shelf." : `${invalid} files can't go on the shelf.`;
  return null;
}

/** "12 KB", "3.4 MB": the size under a name. Folders have none. */
export function sizeLabel(bytes: number): string {
  if (bytes < 1000) return `${bytes} B`;
  const units = ["KB", "MB", "GB", "TB"];
  let v = bytes / 1000, u = 0;
  while (v >= 1000 && u < units.length - 1) { v /= 1000; u++; }
  return `${v >= 100 || Number.isInteger(v) ? Math.round(v) : v.toFixed(1)} ${units[u]}`;
}

/** The notes a failed read or change shows. The list stays as it was: an empty shelf would hide the files. */
const READ_NOTE = "Couldn't read the shelf.";
const CHANGE_NOTE = "Couldn't change the shelf.";

export class ShelfStore {
  entries: ShelfEntry[] = [];
  /** The ids ticked for Send. Ask is off while more than one is ticked. */
  selected = new Set<string>();
  /** Shown under the tray after a drop that left something off; cleared by the next change. */
  note: string | null = null;
  private backend: ShelfBackend | null = null;
  /** Counts the changes that have settled, so a list read that started before one can tell it is stale when it finishes. */
  private ver = 0;

  private readonly changed: () => void;

  constructor(changed: () => void = () => {}) { this.changed = changed; }

  /** Hand in the backend (Rust in the app, an in-memory one in the browser). Nothing is read until `refresh`. */
  attach(backend: ShelfBackend) { this.backend = backend; }

  get count(): number { return this.entries.length; }

  private set(entries: ShelfEntry[]) {
    this.entries = entries;
    const ids = new Set(entries.map((e) => e.id));
    for (const id of [...this.selected]) if (!ids.has(id)) this.selected.delete(id);
    this.changed();
  }

  /** Reads the shelf, and looks at whether the originals are still there (called when the shelf opens and at launch). A failed read keeps the list it had. */
  async refresh(): Promise<void> {
    if (!this.backend) return;
    const v = this.ver;
    let list: ShelfEntry[];
    try {
      list = await this.backend.list();
    } catch {
      if (v === this.ver) { this.note = READ_NOTE; this.changed(); }
      return;
    }
    if (v !== this.ver) return; // a change started meanwhile: its answer is the newer one
    if (this.note === READ_NOTE) this.note = null;
    this.set(list);
  }

  /** The files of a drop on the Shelf half, in the order dropped. Returns the words, one per path. */
  async add(paths: string[]): Promise<AddWord[]> {
    if (!this.backend || paths.length === 0) return [];
    try {
      const { entries, results } = await this.backend.add(paths);
      this.note = shelfNote(results);
      this.set(entries);
      return results;
    } catch {
      this.note = CHANGE_NOTE;
      this.changed();
      return [];
    } finally {
      this.ver++;
    }
  }

  async remove(id: string): Promise<void> {
    if (!this.backend) return;
    this.note = null;
    try {
      this.set(await this.backend.remove(id));
    } catch {
      this.note = CHANGE_NOTE;
      this.changed();
    } finally {
      this.ver++;
    }
  }

  async clear(): Promise<void> {
    if (!this.backend) return;
    this.note = null;
    try {
      this.set(await this.backend.clear());
    } catch {
      this.note = CHANGE_NOTE;
      this.changed();
    } finally {
      this.ver++;
    }
  }

  toggle(id: string) {
    if (!this.entries.some((e) => e.id === id)) return;
    if (!this.selected.delete(id)) this.selected.add(id);
    this.changed();
  }

  /** Who a Send or Show on this tile is for: the ticked items when this one is among several ticked, else just this one. */
  targets(id: string): string[] {
    return this.selected.has(id) && this.selected.size > 1 ? this.entries.filter((e) => this.selected.has(e.id)).map((e) => e.id) : [id];
  }

  /** Ask hands one file to the chat: off while several are ticked, for a folder (the chat reads files) and for an item whose original is gone. */
  canAsk(id: string): boolean {
    const e = this.entries.find((x) => x.id === id);
    return !!e && !e.folder && !e.missing && this.selected.size <= 1;
  }
}
