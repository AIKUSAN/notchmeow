// The General page of Settings (Settings restyle, Task 8): four cards and the closing line. Today's General section of main.ts, moved with the same words and the same saved fields:
// Sound, Island, On the island (which pills are on, with a link to each one's page) and Startup. Each change saves the whole settings with its one field. A write into a control
// the user may be in (the volume slider, the number field, the selects) goes through setValue, so a value that is being dragged or typed is never reset by a sync. Tests:
// windows/scripts/settings-tests/pages.test.mjs (check:settings).

import { AGENT_SWITCHES, type Settings } from "../core/state.ts";
import type { TuckChoice } from "../island/tuckaway.ts";
import { h } from "../views/dom";
import { button, card, help, row, select, setValue, switchRow, wrapRow } from "./kit.ts";
import { pillCatalog } from "./services.ts";
import { slots } from "./status.ts";
import { closeAfter } from "./layout.ts";
import type { PageView, SettingsCtx } from "./ctx.ts";

/** A column of blocks with the gap between them. */
const STACK = "display:flex;flex-direction:column;gap:12px";
/** The volume's top, and what the percentage is of. */
const VOLUME_MAX = 0.2;

export function generalPage(ctx: SettingsCtx): PageView {
  const s0 = ctx.settings();

  // ── Sound ──
  const sound = switchRow("Enable sounds", {
    on: s0.soundEnabled,
    onChange: (v) => void ctx.save({ ...ctx.settings(), soundEnabled: v }),
  });
  const volume = h("input", { type: "range", min: "0", max: String(VOLUME_MAX), step: "0.005" }) as HTMLInputElement;
  const percent = h("span", { class: "hint" });
  const paintVolume = (v: number): void => {
    percent.textContent = `${Math.round((v / VOLUME_MAX) * 100)} %`;
  };
  volume.addEventListener("input", () => {
    paintVolume(Number(volume.value));
    void ctx.save({ ...ctx.settings(), soundVolume: Number(volume.value) });
  });
  const volumeRow = row("Volume", [volume, percent]);
  const sounds = card("Sound", null, sound.el, volumeRow);

  // ── Island ──
  const hover = switchRow("Open on hover", {
    on: s0.openOnHover,
    help: "Hovering the island opens it; it folds again shortly after the pointer leaves. Click inside to keep it open.",
    onChange: (v) => void ctx.save({ ...ctx.settings(), openOnHover: v }),
  });
  const stepBack = switchRow("Step back when I'm already in the app", {
    on: s0.focusAware !== false,
    help: "When an agent asks for permission or a question while its app is in front, it asks there: the island stays closed and quiet, and an amber dot on its pill shows it is waiting.",
    onChange: (v) => void ctx.save({ ...ctx.settings(), focusAware: v }),
  });
  const glow = switchRow("Hover glow", {
    on: s0.hoverGlow,
    help: "A soft rainbow glow along the island's edge while the pointer is over it.",
    onChange: (v) => void ctx.save({ ...ctx.settings(), hoverGlow: v }),
  });
  const tuck = select(
    [["never", "Never"], ["1", "After 1 min"], ["5", "After 5 min"], ["15", "After 15 min"], ["30", "After 30 min"]],
    s0.tuckAway,
    (v) => void ctx.save({ ...ctx.settings(), tuckAway: v as TuckChoice }),
  );
  const tuckRow = row("Tuck the island away", tuck, "The compact island hides by itself only when no agent is working or waiting, and this long has passed since the last hook event, alert or click on the island.");
  const closeInput = h("input", { type: "number", min: "5", max: "120", step: "1", value: String(Math.round(s0.autoCloseInterval)) }) as HTMLInputElement;
  closeInput.addEventListener("change", () => {
    const v = closeAfter(closeInput.value);
    closeInput.value = String(v);
    void ctx.save({ ...ctx.settings(), autoCloseInterval: v });
  });
  const closeRow = row("Close after", [closeInput, h("span", { class: "hint", text: "seconds" })], "After you leave the island.");
  const screen = select(
    [["primary", "Main display"], ["cursor", "Display under the cursor"]],
    s0.screen,
    (v) => void ctx.save({ ...ctx.settings(), screen: v as Settings["screen"] }),
  );
  const screenRow = row("Island lives on", screen);
  const island = card("Island", null, hover.el, stepBack.el, glow.el, tuckRow, closeRow, screenRow);

  // ── On the island: the slots line, and a link to each pill that is on ──
  // The catalog is read once. The line is updated in place; the link buttons are rebuilt only when the set of pills that are on changes, so a button with keyboard focus survives a sync.
  const catalog = pillCatalog();
  const link = (id: string, name: string) => {
    const page = AGENT_SWITCHES.some((a) => a.id === id) ? "agents" : "services";
    const b = button(name, () => ctx.open({ page, tab: null }));
    b.classList.add("st-linkbtn");
    return b;
  };
  const line = h("div", { class: "hint" });
  const linkHost = h("div");
  const slotBox = h("div", { style: STACK }, line, linkHost);
  let linksKey = "";
  const paintSlots = (): void => {
    const active = ctx.settings().activeIntegrations;
    const s = slots(active, catalog);
    line.textContent = s.text;
    line.className = s.full ? "hint warn" : "hint";
    const on = catalog.filter((p) => active.includes(p.id));
    const key = on.map((p) => p.id).join(",");
    if (key === linksKey) return;
    linksKey = key;
    linkHost.replaceChildren(wrapRow(...on.map((p) => link(p.id, p.name))));
  };
  const onIsland = card("On the island", null, slotBox, help("Each pill's switch is on the Agents or Services page."));

  // ── Startup ──
  const startup = switchRow("Launch at startup", {
    on: s0.autostart,
    onChange: (v) => void ctx.save({ ...ctx.settings(), autostart: v }),
  });
  const startupCard = card("Startup", null, startup.el);

  const root = h("div", { style: STACK }, sounds, island, onIsland, startupCard, help("No telemetry. Network requests only go to the services you configure yourself."));

  /** Draws the page from the settings the window holds. The switches change in place; the fields go through setValue. */
  function sync(): void {
    const s = ctx.settings();
    sound.set(s.soundEnabled);
    setValue(volume, String(s.soundVolume));
    volume.disabled = !s.soundEnabled;
    volumeRow.classList.toggle("st-disabled", !s.soundEnabled);
    paintVolume(Number(volume.value));
    hover.set(s.openOnHover);
    glow.set(s.hoverGlow);
    stepBack.set(s.focusAware !== false);
    setValue(tuck, s.tuckAway);
    setValue(closeInput, String(Math.round(s.autoCloseInterval)));
    setValue(screen, s.screen);
    startup.set(s.autostart);
    paintSlots();
  }

  sync();
  return { el: root, sync };
}
