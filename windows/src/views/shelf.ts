// The shelf view (sub-project G1): what is parked in the notch. A new view in the island's own style; no existing view changes. Each tile is a file icon (or a folder), its name and
// its size; hovering it shows Ask, Send, Show in folder and Remove; a click ticks it (several ticked can be sent together); a press that moves 4 px starts a drag out of the island
// where the system can do it (State.shelfCaps.dragOut). The list is State.shelf, Rust's last answer: the page holds ids, never a path.

import { h, svg, clear } from "./dom";
import { State } from "../core/state";
import { PressDrag } from "../cat/pressdrag";
import { SHELF_ICONS } from "../shelf/icons";
import { sizeLabel } from "../shelf/store";
import type { ShelfEntry } from "../shelf/store";
import type { ViewHost } from "./views";
import { buildDeviceBar } from "./shelfdevice";

/** What the island does for a tile's buttons. Ids only: Rust finds the files. */
export interface ShelfActions {
  /** Hand the file to the chat, like a drop on Ask. One id. */
  ask(id: string): void;
  /** The system's share (Windows). */
  send(ids: string[]): void;
  /** Show in Explorer or the file manager, with this file selected. */
  reveal(id: string): void;
  /** Start dragging these files out of the island (the pointer is down). */
  dragOut(ids: string[]): void;
}

const icon = (path: string, size = 14) => svg(path, size, { stroke: 1.7 });

function button(label: string, path: string, onclick: () => void, off = false): HTMLElement {
  return h("button", { class: off ? "sh-act off" : "sh-act", title: label, "aria-label": label, disabled: off, onclick: (e: Event) => { e.stopPropagation(); if (!off) onclick(); } }, icon(path));
}

function tile(e: ShelfEntry, act: ShelfActions, press: PressDrag): HTMLElement {
  const sel = State.shelf.selected.has(e.id);
  const ids = () => State.shelf.targets(e.id);
  const acts = h(
    "div",
    { class: "sh-acts" },
    e.missing ? null : button("Ask about it", SHELF_ICONS.ask, () => act.ask(e.id), !State.shelf.canAsk(e.id)),
    e.missing || !State.shelfCaps.send ? null : button(ids().length > 1 ? `Send ${ids().length} files` : "Send", SHELF_ICONS.send, () => act.send(ids())),
    e.missing ? null : button("Show in folder", SHELF_ICONS.reveal, () => act.reveal(e.id)),
    button("Remove from the shelf", SHELF_ICONS.remove, () => void State.shelf.remove(e.id)),
  );
  const el = h(
    "div",
    { class: `sh-tile${sel ? " sel" : ""}${e.missing ? " missing" : ""}`, title: e.name },
    h("div", { class: "sh-pick" }, sel ? icon(SHELF_ICONS.check, 10) : null),
    h("div", { class: "sh-ico" }, icon(e.folder ? SHELF_ICONS.folder : SHELF_ICONS.file, 26)),
    h("div", { class: "sh-name", text: e.name }),
    h("div", { class: "sh-size", text: e.missing ? "Missing" : e.folder ? "Folder" : sizeLabel(e.size) }),
    acts,
  );
  // A press on the tile is a click (tick it) or, moved 4 px with the button down, the start of a drag out of the island. Missing files have nothing to drag.
  el.addEventListener("mousedown", (ev) => {
    if (ev.button !== 0 || (ev.target as HTMLElement).closest(".sh-acts")) return;
    press.press(ev.clientX, ev.clientY);
    const move = (m: MouseEvent) => {
      if (press.move(m.clientX, m.clientY) !== "start") return;
      cleanup();
      press.cancel();
      if (State.shelfCaps.dragOut && !e.missing) act.dragOut(ids());
    };
    const up = () => {
      cleanup();
      if (press.release() === "click") State.shelf.toggle(e.id);
    };
    const cleanup = () => {
      window.removeEventListener("mousemove", move);
      window.removeEventListener("mouseup", up);
    };
    window.addEventListener("mousemove", move);
    window.addEventListener("mouseup", up);
  });
  return el;
}

export function buildShelf(act: ShelfActions): ViewHost {
  const press = new PressDrag();
  const title = h("span", { class: "sh-title", text: "Shelf" });
  const count = h("span", { class: "sh-count" });
  const sendMany = h("button", { class: "btn secondary sh-small", onclick: () => act.send(State.shelf.targets([...State.shelf.selected][0] ?? "")) });
  const clearAll = h("button", { class: "btn secondary sh-small", text: "Clear all", onclick: () => void State.shelf.clear() });
  const device = buildDeviceBar();
  const tiles = h("div", { class: "sh-tiles" });
  tiles.addEventListener("wheel", (e) => { tiles.scrollLeft += e.deltaY + e.deltaX; e.preventDefault(); }, { passive: false });
  const empty = h("div", { class: "sh-empty" }, h("div", { class: "sh-empty-ico" }, svg(SHELF_ICONS.tray, 30, { stroke: 1.4 })), h("div", { text: "Nothing on the shelf." }), h("div", { class: "sh-empty-sub", text: "Drop files on the right half of the island to keep them here." }));
  const body = h("div", { class: "sh-body" }, h("div", { class: "sh-head" }, title, count, device.el, h("span", { class: "sh-spacer" }), sendMany, clearAll), tiles, empty);
  const el = h("div", { class: "view" }, h("div", { class: "card sh-card" }, body));
  let drawn = "";

  return {
    el,
    sync() {
      device.sync();
      const s = State.shelf, caps = State.shelfCaps;
      // Rebuilt only when what it shows changed, so a tile under the pointer is not replaced while it is pressed.
      const key = JSON.stringify([s.entries, [...s.selected], s.note, caps]);
      if (key === drawn) return;
      drawn = key;
      count.textContent = s.note ?? (s.count === 0 ? "" : s.count === 1 ? "1 file" : `${s.count} files`);
      count.classList.toggle("note", s.note !== null);
      const many = s.selected.size > 1 && caps.send;
      sendMany.style.display = many ? "" : "none";
      sendMany.textContent = `Send ${s.selected.size}`;
      clearAll.style.display = s.count > 0 ? "" : "none";
      tiles.style.display = s.count > 0 ? "" : "none";
      empty.style.display = s.count > 0 || s.note !== null ? "none" : "";
      clear(tiles);
      for (const e of s.entries) tiles.append(tile(e, act, press));
    },
  };
}
