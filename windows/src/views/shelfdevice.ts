// "To a device" on the shelf's head row (sub-project G2): an icon-only button that shows when the link is on or a machine is paired and something is ticked, the machines to send to (chips)
// when it is pressed, and the one status line of a send in progress with its Cancel. A new file the shelf view includes; the shelf's own buttons and tiles are untouched. The shelf holds ids
// and never a path: pressing a chip hands Rust the ticked ids and the machine's id, and Rust finds the files. Sending always starts with a click.

import { h, svg, clear } from "./dom";
import { Bridge } from "../core/bridge";
import { State } from "../core/state";
import { SHELF_ICONS } from "../shelf/icons";
import { sendTargets, showDeviceButton } from "../link/model.ts";

/** Names this wide are cut short with an ellipsis (a chip can carry any name). */
const CHIP_MAX = "9em";

export function buildDeviceBar(): { el: HTMLElement; sync(): void } {
  let choosing = false;
  const status = h("span", { class: "lk-line" });
  const cancel = h("button", { class: "lk-cancel", title: "Stop sending", "aria-label": "Cancel sending", text: "Cancel", onclick: () => State.link.backend?.cancelSending() });
  const button = h("button", { class: "btn secondary sh-small lk-devbtn", title: "To a device", "aria-label": "Send to a device", onclick: () => { choosing = !choosing; sync(); } }, svg(SHELF_ICONS.device, 14, { stroke: 1.7 }));
  const chips = h("span", { class: "lk-chips" });
  const el = h("span", { class: "lk-devbar" }, status, cancel, button, chips);
  let key = "";

  function sync() {
    const snap = State.link.snapshot;
    const selected = [...State.shelf.selected];
    const canSend = showDeviceButton(snap) && selected.length > 0;
    // Nothing ticked, or no device button to open the machines from: the chips close, so a later selection shows the buttons and not the chips.
    if (!canSend) choosing = false;
    el.parentElement?.classList.toggle("sh-choosing", choosing);
    status.textContent = snap.sendStatus ?? "";
    status.style.display = snap.sendStatus && !choosing ? "" : "none";
    cancel.style.display = snap.sending && !choosing ? "" : "none";
    button.style.display = canSend && !choosing ? "" : "none";
    chips.style.display = choosing ? "" : "none";
    const next = JSON.stringify([choosing, snap.rows, selected.length]);
    if (next === key) return;
    key = next;
    clear(chips);
    if (!choosing) return;
    // The paired machines: the ones on the network first, then the others greyed out and disabled (a click on them sends nothing).
    const targets = [...sendTargets(snap.rows), ...snap.rows.filter((r) => r.state === "pairedOffline")];
    for (const r of targets) {
      const online = r.state === "pairedOnline";
      chips.append(
        h("button", {
          class: online ? "btn secondary sh-small lk-chip" : "btn secondary sh-small lk-chip off",
          title: online ? `Send to ${r.name}` : `${r.name} is not on the network`,
          disabled: !online,
          style: `max-width:${CHIP_MAX}`,
          text: r.name,
          onclick: () => {
            if (!online) return;
            choosing = false;
            State.link.backend?.send([...State.shelf.selected], r.id);
            sync();
          },
        }),
      );
    }
    if (sendTargets(snap.rows).length === 0) {
      chips.append(
        h("span", { class: "lk-none", text: targets.length ? "No paired machine is on the network." : "Pair a machine in Settings → Devices." }),
        h("button", { class: "btn secondary sh-small", text: "Open Devices", onclick: () => void Bridge.openSettingsWindow("devices") }),
      );
    }
    chips.append(h("button", { class: "btn secondary sh-small lk-close", title: "Back", "aria-label": "Close the list of machines", text: "×", onclick: () => { choosing = false; sync(); } }));
  }

  return { el, sync };
}
