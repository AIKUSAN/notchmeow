// Settings → Devices (sub-project G2): whether this machine is visible on the network, the name it shows, the machines it can see or has paired, and where received files go. Restyled
// (Settings restyle, Task 8) into three cards of the layout kit: This computer, Machines and Received files. Every closure, the snapshot handling and every word stay. The section keeps
// no state of its own: it draws the link's last snapshot (Rust's) and every change goes to Rust, which answers with the next snapshot. Tests: windows/scripts/settings-tests/pages.test.mjs
// (check:settings) and windows/scripts/link-tests/wiring.test.mjs (check:link).
//
// "Devices is open" matters to Rust twice: another machine may start a pairing with this one only while it is, and the machines are looked for only while it is. So the section says when
// it is on screen (visible in the window, in a window that is shown) and when it is not, as a state and not as a count: saying it twice changes nothing, and Rust puts it right to "not
// open" whenever the window hides.

import { h, clear } from "../views/dom";
import { permissionHelp, stateWords } from "../link/text.ts";
import type { LinkBackend, LinkRow, LinkSnapshot } from "../link/model.ts";
import { LINK_EMPTY } from "../link/model.ts";
import { button, card, chip, help as hint, row, wrapRow } from "./kit.ts";

export type Platform = "windows" | "linux" | "other";

export function platformOf(navigatorPlatform: string): Platform {
  return /^win/i.test(navigatorPlatform) ? "windows" : /linux|x11/i.test(navigatorPlatform) ? "linux" : "other";
}

export interface DevicesHost {
  backend: LinkBackend;
  platform: Platform;
}

const NAME_REFUSED = "That name cannot be shown on another machine's card: use 1 to 63 characters, no control or invisible characters, no space at either end.";

function setSwitch(el: HTMLElement, on: boolean): void {
  el.classList.toggle("on", on);
  el.setAttribute("aria-pressed", String(on));
}

const DOT: Record<LinkRow["state"], string> = { pairedOnline: "#22c55e", pairedOffline: "var(--dim-2)", available: "#60a5fa" };
/** A column of blocks with the gap between them (the list of machines). */
const STACK = "display:flex;flex-direction:column;gap:10px";

export function devicesSection(host: DevicesHost): { el: HTMLElement; sync(s: LinkSnapshot): void; reset(): void; dispose(): void } {
  const { backend } = host;
  let snap: LinkSnapshot = LINK_EMPTY;
  let forgetting: string | null = null;
  let nameRefused = false;
  let rowsKey = "";

  // Built once: a press changes its switch in place, so keyboard focus stays on it.
  const visible = h("button", { class: "switch", "aria-label": "Visible on this network" });
  visible.addEventListener("click", () => backend.setVisible(!visible.classList.contains("on")));
  const name = h("input", { type: "text", "aria-label": "Name shown to other machines", maxlength: "200", placeholder: "Name shown to other machines" });
  const commitName = async () => {
    let ok: boolean;
    try { ok = await backend.setName(name.value); } catch { return; } // a rejected call changes nothing: the field keeps what was typed
    nameRefused = !ok;
    if (!ok) name.value = snap.name;
    paintName();
  };
  name.addEventListener("keydown", (e) => { if (e.key === "Enter") void commitName(); });
  name.addEventListener("blur", () => { if (name.value !== snap.name) void commitName(); });
  const nameWarn = h("div", { class: "hint warn", text: NAME_REFUSED });
  const status = h("div", { class: "hint" });
  const list = h("div", { style: STACK });
  const note = h("div", { class: "hint warn" });
  const folder = h("div", { class: "hint" });
  const help = h("div", { class: "hint", id: "devices-help", text: permissionHelp(host.platform) });

  // The first card is the one the "on screen" check watches: it fits the window, so a fifth of it in view means the section is on screen.
  const computerCard = card("This computer", null,
    row("Visible on this network", visible),
    hint("Other Macs and PCs running NotchMeow can see this one and offer to pair. Until you turn this on, nothing listens and nothing is announced. Only machines you have paired can ever send a file."),
    row("Name", name),
    hint("Machines on this network see this name."),
    nameWarn,
    status,
  );
  const machinesCard = card("Machines", null, list, note, help);
  const filesCard = card("Received files", null,
    hint("Files you accept are saved in Downloads/NotchMeow. On Windows they are marked as downloaded from the Internet, and they are never opened for you."),
    folder,
    wrapRow(button("Show folder", () => backend.revealFolder())),
  );

  const el = h("div", { id: "devices-section", "data-link": "devices", style: STACK }, computerCard, machinesCard, filesCard);

  function paintName() {
    nameWarn.style.display = nameRefused ? "" : "none";
  }

  /** The window was hidden: the Name goes back to the stored name and a refusal is forgotten, so typed text that was not committed is not kept. */
  function reset(): void {
    name.value = snap.name;
    nameRefused = false;
    paintName();
  }

  function paintRows() {
    const key = JSON.stringify([snap.visible, snap.rows, forgetting]);
    if (key === rowsKey) return;
    rowsKey = key;
    clear(list);
    if (!snap.visible && snap.rows.length === 0) {
      list.append(hint("Turn on Visible on this network to find machines and pair with them."));
    } else if (snap.rows.length === 0) {
      list.append(
        hint("No machines found"),
        hint("Both machines need NotchMeow running, Visible on this network turned on, and to be on the same network. Some office and guest networks block this."),
      );
    }
    for (const r of snap.rows) {
      // Pair is a plain button: a card has one primary button at most, and a list of machines can hold many Pair buttons.
      const actions =
        r.state === "available"
          ? [button("Pair", () => backend.pair(r.id))]
          : forgetting === r.id
            ? [
                h("button", { class: "danger st-wrapbtn", text: `Forget ${r.name}?`, onclick: () => { forgetting = null; backend.forget(r.id); } }),
                h("button", { class: "st-wrapbtn", text: "Keep", onclick: () => { forgetting = null; paintRows(); } }),
              ]
            : [button("Forget", () => { forgetting = r.id; rowsKey = ""; paintRows(); })];
      // The kit's short-row rule (settings.css, .st-row.st-short): the name wraps by word inside its column beside the chip and the buttons, and those keep their own widths.
      // The layout check reads each machine row by data-machine (devpanel.ts).
      list.append(
        h("div", { class: "st-row st-short", "data-machine": "" },
          h("div", { class: "st-label" },
            h("span", { class: "st-labeltext st-dotlabel" }, h("i", { class: "dot", style: `background:${DOT[r.state]}` }), r.name),
          ),
          h("div", { class: "st-control" }, chip(stateWords(r.state)), wrapRow(...actions)),
        ),
      );
    }
  }

  function sync(next: LinkSnapshot) {
    snap = next;
    setSwitch(visible, snap.visible);
    if (document.activeElement !== name) name.value = snap.name;
    paintName();
    help.style.display = snap.visible ? "" : "none";
    status.style.display = snap.visible || snap.problem ? "" : "none";
    status.className = snap.problem ? "hint warn" : "hint";
    status.textContent = snap.problem ?? (snap.listening ? "Listening on your network." : "Starting…");
    note.style.display = snap.note ? "" : "none";
    note.textContent = snap.note ?? "";
    folder.textContent = snap.folder ? `Folder: ${snap.folder}` : "";
    folder.style.display = snap.folder ? "" : "none";
    paintRows();
  }

  // ── "Devices is open" ──
  // On screen means: the section is in view in the window and the page is visible. A window that hides is put right by Rust (it says "not open" itself); one that is shown
  // again says so with the focus event. A window never shown (the stored page at launch, with no focus yet) does not say "open": `shown` becomes true at the first focus, or
  // at a visible page that has focus, and from then on a later blur keeps the gate open (a person may look at the other machine while this window stays visible).
  let inView = false;
  let said: boolean | null = null;
  let shown = false;
  const report = () => {
    const open = inView && !document.hidden && (shown || document.hasFocus());
    // A page that is open because of focus counts as shown from now on, so a later blur (with the observer still in view) keeps the gate open.
    if (open && document.hasFocus()) shown = true;
    if (open === said) return;
    said = open;
    backend.setDevicesOpen(open);
  };
  const observer = new IntersectionObserver((entries) => {
    inView = entries.some((e) => e.isIntersecting);
    report();
  }, { threshold: 0.2 });
  observer.observe(computerCard);
  const onVisibility = () => {
    if (document.visibilityState === "visible" && document.hasFocus()) shown = true;
    report();
  };
  const onFocus = () => { shown = true; said = null; report(); };
  // A named listener, so dispose can take it back when another page is chosen while this window stays shown.
  const onHide = () => backend.setDevicesOpen(false);
  document.addEventListener("visibilitychange", onVisibility);
  window.addEventListener("focus", onFocus);
  window.addEventListener("pagehide", onHide);

  // The reply to state() travels another way than the pushes and can arrive after a newer push: once one push has come, the reply is older than what is shown and is dropped.
  let pushed = false;
  const off = backend.onSnapshot((s) => {
    pushed = true;
    sync(s);
  });
  void backend.state().then((s) => { if (!pushed) sync(s); }).catch(() => {});
  sync(LINK_EMPTY);

  return {
    el,
    sync,
    reset,
    dispose() {
      off();
      observer.disconnect();
      document.removeEventListener("visibilitychange", onVisibility);
      window.removeEventListener("focus", onFocus);
      window.removeEventListener("pagehide", onHide);
      backend.setDevicesOpen(false);
    },
  };
}
