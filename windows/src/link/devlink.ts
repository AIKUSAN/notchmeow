// The `?dev` page's "Link" panel (sub-project G2), the Windows/Linux counterpart of the Mac's Debug fake peer panel: the real link card inside an island frame, fed by a stand-in link
// (mock.ts) that this panel moves through every state worth looking at, with the island's decision for each change (island/link.ts) and the calls the buttons made. Settings → Devices is
// looked at on `settings.html?linkdev=on` (its style sheet cannot share a page with this one). The shelf's "To a device" bar shows in the Shelf panel: tick two files there, then pick
// "Two machines online" here. Open http://127.0.0.1:1420/?dev with `npx vite` (no Tauri window needed). Only the dev server serves it (cat/dev.ts is loaded behind `import.meta.env.DEV`).

import { BotEngine } from "../cat/engine.ts";
import { PRESETS } from "../cat/presets.ts";
import { State } from "../core/state.ts";
import { VIEW_LAYOUTS } from "../core/layout.ts";
import { buildLink } from "../views/link.ts";
import { THEME } from "../theme.generated.ts";
import { holdsIsland, cardTransition } from "./model.ts";
import { CARDS, ROWS } from "./devseed.ts";
import { mockLinkBackend } from "./mock.ts";

const B = THEME.brand;
const BTN = `font:inherit;font-size:12px;color:${B.ink};background:${B.button};border:1px solid ${B.line};border-radius:8px;padding:4px 10px;cursor:pointer`;

function button(label: string, onclick: () => void): HTMLButtonElement {
  const b = document.createElement("button");
  b.style.cssText = BTN; b.textContent = label; b.onclick = onclick;
  return b;
}

export function mountLinkDev(root: HTMLElement, before: Node | null): void {
  const mock = mockLinkBackend({ visible: true, listening: true, rows: ROWS.two });
  const decisions: string[] = [];
  State.link.attach(mock, (prev, next) => {
    const t = cardTransition(prev.card, next.card, true);
    decisions.push(`${prev.card?.kind ?? "none"} -> ${next.card?.kind ?? "none"}: ${["alert", "hold", "release", "collapse"].filter((k) => t[k as keyof typeof t]).join(" + ") || "nothing"}`);
    paint();
  });
  const view = buildLink();
  view.el.classList.add("on");

  const box = document.createElement("section");
  box.id = "link-dev";
  box.style.cssText = `background:${B.panel};border:1px solid ${B.line};border-radius:16px;padding:16px;margin-bottom:20px`;
  box.innerHTML = `<h2 style="font-size:17px;font-weight:600;margin:0 0 2px">Link (between your machines)</h2>
    <p style="color:${B.dim};margin:0 0 12px;font-size:13px">The link's card in its island, fed by a stand-in service. Each button puts the card in a state; the buttons on the card call the stand-in, which records them below. "The island does" is what island/link.ts decides for each change. Nothing here is the real link: it never opens a socket.</p>`;

  const stage = document.createElement("div");
  stage.style.cssText = "position:relative;width:640px;height:160px;background:#000;border-radius:0 0 22px 22px;overflow:hidden;margin:6px 0 12px";
  const slot = document.createElement("div");
  slot.style.cssText = "position:absolute;left:10px;right:10px;top:42px;bottom:8px";
  slot.append(view.el);
  const cat = document.createElement("canvas");
  const L = VIEW_LAYOUTS.link, D = L.botDiameter / 0.6, dpr = Math.min(2, devicePixelRatio || 1);
  cat.width = Math.round(D * dpr); cat.height = Math.round(D * dpr);
  cat.style.cssText = `position:absolute;left:${L.botX - D / 2}px;top:${88 - D / 2}px;width:${D}px;height:${D}px;pointer-events:none`;
  const engine = new BotEngine(PRESETS.shrimpy, { quiet: true, now: () => 0, rand: () => 0.5 });
  const paintCat = () => {
    const c = cat.getContext("2d")!;
    c.setTransform(dpr, 0, 0, dpr, 0, 0); c.clearRect(0, 0, D, D);
    engine.update(1 / 60); engine.draw(c, D, D);
  };
  stage.append(slot, cat);
  box.append(stage);

  const row = (label: string, ...buttons: HTMLButtonElement[]) => {
    const r = document.createElement("div");
    r.style.cssText = "display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px;align-items:center;font-size:12px";
    r.append(label, ...buttons);
    box.append(r);
  };
  const show = (name: keyof typeof CARDS) => () => mock.set({ card: CARDS[name] });
  row("Pairing:", button("Code", show("pair")), button("Answered", show("pairAnswered")), button("Paired", show("paired")), button("Not paired", show("notPaired")));
  row("Offer:", button("An offer", show("offer")), button("A long name", show("offerLong")), button("Expired", show("expired")));
  row("Receiving:", button("0 %", show("receiving0")), button("45 %", show("receiving45")), button("100 %", show("receiving100")), button("Received", show("received")), button("Cancelled", show("cancelled")), button("Stopped", show("stopped")));
  row("Card:", button("None", () => mock.set({ card: null })));
  row("Machines:", button("Two machines online", () => mock.set({ rows: ROWS.two, visible: true })), button("One offline", () => mock.set({ rows: ROWS.offline })), button("None", () => mock.set({ rows: ROWS.none })));
  row("Sending:", button("Waiting", () => mock.set({ sending: true, sendStatus: "Waiting for Desk PC to accept report.pdf" })), button("45 %", () => mock.set({ sending: true, sendStatus: "Sending report.pdf to Desk PC, 45 %" })), button("Done", () => mock.set({ sending: false, sendStatus: "Finished sending report.pdf to Desk PC" })), button("Clear", () => mock.set({ sending: false, sendStatus: null })));

  const out = document.createElement("pre");
  out.id = "link-dev-out";
  out.style.cssText = `color:${B.dim};font-size:12px;margin:0;white-space:pre-wrap`;
  box.append(out);

  function paint() {
    view.sync();
    const card = State.link.snapshot.card;
    out.textContent = `Card: ${card ? `${card.kind} (holds the island: ${holdsIsland(card)})` : "none"}\nThe island does: ${decisions.slice(-3).join("  |  ") || "nothing yet"}\nCalls: ${mock.calls.slice(-4).join("  |  ") || "none yet"}`;
  }
  State.subscribe(paint);
  paint();
  root.insertBefore(box, before);
  let frames = 0;
  const tick = () => { paintCat(); if (++frames < 30) requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
}
