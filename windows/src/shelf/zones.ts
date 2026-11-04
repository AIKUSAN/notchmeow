// The two halves of the drop view (sub-project G1): Ask on the left, Shelf on the right, split at the island's centre line. This is a layer ON TOP of the drop canvas
// (upload/canvas.ts), never a change to it: the canvas, the drop sequence and the views stay exactly as they were, and the layer only exists while files are dragged over the open
// island. It takes no mouse (the OS drag does). The half that is hot is the one the pointer is in (State.dropZone, from the contract's zoneAt).

import { h, svg } from "../views/dom";
import { SHELF_ICONS } from "./icons.ts";
import type { Zone } from "./rules.ts";

/** The drop canvas' card, in the island's px (upload/sequence.ts USC): the Shelf half is the right half of it. */
const CARD = { x: 10, y: 42, w: 620, h: 124 } as const;
export const CENTRE_X = 320;

export class ShelfZones {
  readonly el: HTMLElement;

  constructor() {
    const ask = h("div", { class: "sz-chip sz-ask", text: "Ask" });
    // The cat follows the pointer onto the tray, so the words sit at the edges and the icon in the middle is faint: the cat stays in sight.
    const shelf = h(
      "div",
      { class: "sz-shelf" },
      h("div", { class: "sz-chip sz-name", text: "Shelf" }),
      h("div", { class: "sz-icon" }, svg(SHELF_ICONS.tray, 30, { stroke: 1.4 })),
      h("div", { class: "sz-sub", text: "Keep it here, drag it out later" }),
    );
    this.el = h("div", { id: "shelf-zones" }, ask, shelf);
    this.el.style.setProperty("--sz-x", `${CENTRE_X}px`);
    this.el.style.setProperty("--sz-y", `${CARD.y}px`);
    this.el.style.setProperty("--sz-w", `${CARD.x + CARD.w - CENTRE_X}px`);
    this.el.style.setProperty("--sz-h", `${CARD.h}px`);
  }

  /** `on`: files are being dragged over the open drop view; `hot`: the half the pointer is in. */
  sync(on: boolean, hot: Zone | null) {
    this.el.classList.toggle("on", on);
    this.el.dataset.hot = hot ?? "";
  }
}
