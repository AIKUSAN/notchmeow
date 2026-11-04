// The Services page of Settings (Settings restyle, Task 7): one card per service, each with its "Show on the island" switch and its key fields. Today's INTEGRATIONS of main.ts,
// moved in the spec's order with the same ids, colours, keys, labels and placeholders. A key is written to the credential store and only its presence is ever read back: a
// stored value shows as the placeholder "••••••••  (stored)", and a typed draft stays in the window until Save. The four-slot cap is shared with the agents' switches (agents.ts).
// Tests: windows/scripts/settings-tests/pages.test.mjs (check:settings).

import { AGENT_SWITCHES } from "../core/state.ts";
import { agentLabel } from "../core/pills.ts";
import { h, clear } from "../views/dom";
import { button, card, checkAgain, chip, help, keyField, notice, row, switchRow, wrapRow, type SwitchRow } from "./kit.ts";
import { CREDENTIAL_REMOVE_FAILED, CREDENTIAL_SAVE_FAILED, nextActive, pillSwitch, savedNote, serviceChip, UNREADABLE_CHIP } from "./status.ts";
import { canStartWrite, saveDisabled } from "./drafts.ts";
import type { PageView, SettingsCtx } from "./ctx.ts";

export interface ServiceField { key: string; label: string; placeholder: string; secret: boolean }
export interface ServiceDef { id: string; name: string; color: string; fields: ServiceField[] }

export const SERVICES: readonly ServiceDef[] = [
  { id: "integration_resend", name: "Resend", color: "#22C55E",
    fields: [{ key: "resend-api-key", label: "API key", placeholder: "re_…", secret: true }] },
  { id: "integration_n8n", name: "n8n", color: "#F29B38",
    fields: [
      { key: "n8n-url", label: "Instance URL", placeholder: "https://n8n.example.com", secret: false },
      { key: "n8n-api-key", label: "API key", placeholder: "…", secret: true },
    ] },
  { id: "integration_vercel", name: "Vercel", color: "#7C5CFF",
    fields: [{ key: "vercel-token", label: "Token", placeholder: "…", secret: true }] },
  { id: "integration_github", name: "GitHub", color: "#F4505E",
    fields: [{ key: "github-token", label: "Token", placeholder: "ghp_…", secret: true }] },
  { id: "integration_stripe", name: "Stripe", color: "#0570DE",
    fields: [{ key: "stripe-api-key", label: "Secret key", placeholder: "sk_live_…", secret: true }] },
  { id: "integration_calcom", name: "Cal.com", color: "#C9956A",
    fields: [{ key: "calcom-api-key", label: "API key", placeholder: "cal_…", secret: true }] },
  { id: "integration_notion", name: "Notion", color: "#8C8C8C",
    fields: [{ key: "notion-api-key", label: "Integration token", placeholder: "ntn_…", secret: true }] },
];

/** Turns a pill on the island on or off. An off switch at the cap does nothing; the settings change at once and Rust answers with `settings-changed`. */
export function setPillOn(ctx: SettingsCtx, id: string, on: boolean): void {
  const s = ctx.settings();
  const next = nextActive(s.activeIntegrations, id, on);
  if (next) void ctx.save({ ...s, activeIntegrations: next });
}

/** The pills a General page's slots and links name: the agent switches (by their names), then the services. */
export function pillCatalog(): { id: string; name: string }[] {
  return [
    ...AGENT_SWITCHES.map((s) => ({ id: s.id, name: agentLabel(s.id) })),
    ...SERVICES.map((s) => ({ id: s.id, name: s.name })),
  ];
}

/** The cards' writes in flight, per card. Module-level, so a tab switch within the window's life does not forget a save that is still running. */
const writing = new Set<string>();

export function servicesPage(ctx: SettingsCtx): PageView {
  const switches = new Map<string, SwitchRow>();
  const slots = new Map<string, HTMLElement>();
  const live = new Map<string, { dirty(): void }>();

  const stateOf = (id: string) => {
    const active = ctx.settings().activeIntegrations;
    const on = active.includes(id);
    const p = pillSwitch(on, false, active.length, null);
    return { on, chip: p.chip, disabled: p.disabled };
  };
  const syncSwitches = (): void => {
    for (const [id, sw] of switches) {
      const st = stateOf(id);
      sw.set(st.on, { chip: st.chip, disabled: st.disabled });
    }
  };

  function serviceCard(def: ServiceDef, message: HTMLElement | null): { el: HTMLElement; dirty(): void } {
    const keys = def.fields.map((f) => f.key);
    const saved = def.fields.every((f) => ctx.drafts.isSaved(f.key));
    const unreadable = def.fields.some((f) => ctx.drafts.isUnreadable(f.key));

    const sw = switchRow("Show on the island", {
      ...stateOf(def.id),
      onChange: (on) => {
        setPillOn(ctx, def.id, on);
        syncSwitches();
      },
    });
    switches.set(def.id, sw);

    const marks: (() => void)[] = [];
    const fieldRows: HTMLElement[] = [];
    const removes: HTMLButtonElement[] = [];

    /** A write (or a removal) that succeeded: the card is drawn again from the drafts, which hold what is typed and what is saved. */
    async function saveAll(): Promise<void> {
      if (!canStartWrite(writing.has(def.id))) return;
      writing.add(def.id);
      save.disabled = true;
      try {
        // Only the writable drafts are written: a field the store cannot read is skipped, and the others of the card still save.
        for (const id of ctx.drafts.writableDirty(keys)) {
          try {
            const typed = ctx.drafts.text(id);
            await ctx.backend.secretSet(id, typed.trim());
            ctx.drafts.markSaved(id, true, typed);
          } catch {
            // The field keeps its text; the fields before it stay saved.
            paint(def, notice("err", CREDENTIAL_SAVE_FAILED));
            return;
          }
        }
        paint(def, notice("ok", savedNote(ctx.drafts.anyDirty(keys.filter((id) => ctx.drafts.isUnreadable(id))))));
      } finally {
        writing.delete(def.id);
        // The latest card (a repaint may have replaced this one) takes the flag's new state.
        live.get(def.id)?.dirty();
      }
    }

    async function removeKey(f: ServiceField): Promise<void> {
      // A save for this card in flight comes first: a clear must not interleave with a set.
      if (!canStartWrite(writing.has(def.id)) || !ctx.drafts.canWrite(f.key)) return;
      try {
        await ctx.backend.secretClear(f.key);
      } catch {
        paint(def, notice("err", CREDENTIAL_REMOVE_FAILED));
        return;
      }
      ctx.drafts.markSaved(f.key, false);
      paint(def, notice("ok", "Key removed."));
    }

    for (const f of def.fields) {
      const present = ctx.drafts.isSaved(f.key);
      const broken = ctx.drafts.isUnreadable(f.key);
      const input = keyField({
        id: f.key, drafts: ctx.drafts, secure: f.secret, disabled: broken,
        placeholder: broken ? "Can't read the credential store" : present ? "••••••••  (stored)" : f.placeholder,
        onInput: () => live.get(def.id)?.dirty(),
      });
      const slot = h("span", { class: "st-chipslot" });
      const mark = (): void => {
        clear(slot);
        if (ctx.drafts.isDirty(f.key) && !ctx.drafts.isUnreadable(f.key)) slot.append(chip("Not saved"));
      };
      mark();
      marks.push(mark);
      fieldRows.push(row(f.label, [input, slot]));
      if (present) {
        const rm = button("Remove", () => void removeKey(f), "danger");
        rm.setAttribute("aria-label", `Remove ${def.name} ${f.label}`);
        removes.push(rm);
      }
    }

    const save = h("button", { type: "button", text: "Save", disabled: !ctx.drafts.anyDirty(keys), onclick: () => void saveAll() });
    const dirty = (): void => {
      for (const m of marks) m();
      const on = ctx.drafts.writableDirty(keys).length > 0;
      save.disabled = saveDisabled(writing.has(def.id), on);
      save.classList.toggle("primary", on);
    };
    dirty();

    // A store that cannot be read says so on the card and offers Check again for each such key; nothing is written to it.
    const checks = def.fields.filter((f) => ctx.drafts.isUnreadable(f.key)).map((f) => checkAgain(ctx, f.key, () => paint(def), undefined, `${def.name} ${f.label}`));
    const children: Node[] = [sw.el, ...fieldRows];
    if (unreadable) children.push(help("Couldn't read the credential store."));
    children.push(wrapRow(save, ...removes, ...checks));
    if (message) children.push(message);
    return { el: card(def.name, { dot: def.color, summary: unreadable ? UNREADABLE_CHIP : serviceChip(saved) }, ...children), dirty };
  }

  function paint(def: ServiceDef, message: HTMLElement | null = null): void {
    const c = serviceCard(def, message);
    live.set(def.id, c);
    slots.get(def.id)?.replaceChildren(c.el);
  }

  const root = h("div", { style: "display:flex;flex-direction:column;gap:12px" },
    help("Pick up to 4 pills to show next to your cat, counting the agents you turned on. Keys are stored in your system's credential store, never on disk."),
  );
  for (const def of SERVICES) {
    const slot = h("div");
    slots.set(def.id, slot);
    root.append(slot);
    paint(def);
  }
  return { el: root, sync: syncSwitches };
}
