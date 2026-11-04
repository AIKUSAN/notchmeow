// The link's island view (sub-project G2): the card for a pairing (the six digits to compare), for an offer from another machine (Accept and Decline), for a file coming in (progress and
// Cancel) and for the end of any of them. A new view in the island's own style (the same card, wash, buttons and type as the approval card); no existing view changes. The card comes from
// `State.link`, Rust's last snapshot; every button hands back the card it was drawn on, so Rust does nothing for a click that was meant for a card that has since been replaced, or that
// came in the first 700 ms after the card changed kind. Nothing here accepts for the user: Accept is a button, and a button is a click.

import { h, clear } from "./dom";
import { State } from "../core/state";
import { washRGBA, type Wash } from "../core/layout";
import { percent, readCode, sizeLabel, spaced } from "../link/text.ts";
import { shownOf } from "../link/model.ts";
import type { LinkCard } from "../link/model.ts";
import type { ViewHost } from "./views";

function card(wash: Wash, ...children: (Node | string)[]): HTMLElement {
  const el = h("div", { class: wash ? "card wash" : "card" }, ...children);
  if (wash) el.style.setProperty("--wash", washRGBA(wash));
  return el;
}

function btn(label: string, kind: "primary" | "secondary", onClick: () => void, disabled = false): HTMLElement {
  return h("button", { class: `btn ${kind}`, onclick: onClick, disabled }, h("span", { text: label }));
}

function stack(...children: Node[]): HTMLElement {
  const el = h("div", { class: "stack" }, ...children);
  el.style.padding = "4px 16px 4px 116px";
  return el;
}

export function buildLink(): ViewHost {
  const body = h("div", { class: "lk-body" });
  const el = h("div", { class: "view" }, body);
  let drawn = "";
  /** The progress bar and its words, kept so that a tick of progress changes them and does not rebuild the card (a button under the pointer is not replaced). */
  let bar: HTMLElement | null = null;
  let words: HTMLElement | null = null;

  const backend = () => State.link.backend;

  function pair(c: LinkCard): HTMLElement {
    const peer = c.peer ?? "that machine";
    const answered = c.answered === true;
    const code = h("span", { class: "lk-code", text: spaced(c.code ?? ""), "aria-label": `Pairing code ${readCode(c.code ?? "")}` });
    return card(
      "indigo",
      stack(
        h("div", { class: "title lk-title", text: `Pair with ${peer}?` }),
        h("div", { class: "lk-pairrow" }, code, h("span", { class: "sub", text: `Check that ${peer} shows the same six digits.` })),
        h("div", { class: "actions" },
          btn("No", "secondary", () => backend()?.answerPair(false, shownOf(c)), answered),
          btn(answered ? `Waiting for ${peer}` : "They match", "primary", () => backend()?.answerPair(true, shownOf(c)), answered),
        ),
      ),
    );
  }

  function offer(c: LinkCard): HTMLElement {
    return card(
      "cyan",
      stack(
        h("div", { class: "title lk-title", text: `${c.peer ?? "A machine"} wants to send you a file` }),
        // The name is the sanitized one: the one that would be saved.
        h("div", { class: "code lk-name", text: `${c.name ?? ""}  ${sizeLabel(c.size ?? 0)}` }),
        h("div", { class: "sub", text: "Saved in Downloads/NotchMeow, never opened. Declined after 2 minutes." }),
        h("div", { class: "actions" }, btn("Decline", "secondary", () => backend()?.respondOffer(false, shownOf(c))), btn("Accept", "primary", () => backend()?.respondOffer(true, shownOf(c)))),
      ),
    );
  }

  function receiving(c: LinkCard): HTMLElement {
    bar = h("div", { class: "lk-fill" });
    words = h("span", { class: "sub lk-words" });
    return card(
      "cyan",
      stack(
        h("div", { class: "title lk-title lk-name", text: `Receiving ${c.name ?? ""} from ${c.peer ?? "a machine"}` }),
        h("div", { class: "lk-bar", role: "progressbar", "aria-label": "Receiving" }, bar),
        h("div", { class: "lk-progressrow" }, words, h("span", { class: "lk-spacer" }), btn("Cancel", "secondary", () => backend()?.cancelReceiving(shownOf(c)))),
      ),
    );
  }

  function result(c: LinkCard): HTMLElement {
    return card(
      c.canReveal ? "green" : "soft",
      stack(
        h("div", { class: "title lk-title", text: c.title ?? "" }),
        h("div", { class: "lk-detail", text: c.detail ?? "" }),
        h("div", { class: "actions" }, c.canReveal ? btn("Show in folder", "secondary", () => backend()?.revealResult()) : null, btn("OK", "primary", () => backend()?.dismiss(shownOf(c)))),
      ),
    );
  }

  function progress(c: LinkCard) {
    if (!bar || !words) return;
    const done = c.received ?? 0, total = c.size ?? 0, pct = percent(done, total);
    bar.style.width = `${pct}%`;
    words.textContent = `${sizeLabel(done)} of ${sizeLabel(total)}, ${pct} %`;
  }

  return {
    el,
    sync() {
      const c = State.link.snapshot.card;
      // Rebuilt only when the card is another one (its kind, what it is about, whether it was answered), never for a tick of progress.
      const key = c ? JSON.stringify([c.kind, c.key, c.answered === true, c.title, c.detail, c.canReveal === true, c.peer, c.name, c.size]) : "none";
      if (key !== drawn) {
        drawn = key;
        bar = words = null;
        clear(body);
        if (c) body.append(c.kind === "pair" ? pair(c) : c.kind === "offer" ? offer(c) : c.kind === "receiving" ? receiving(c) : result(c));
      }
      if (c?.kind === "receiving") progress(c);
    },
  };
}
