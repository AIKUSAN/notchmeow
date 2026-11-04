// The Agents page of Settings (Settings restyle, Task 7): "Where you code" (which agents show on the island) and one card of hooks for each of the three agents. The hook cards
// are today's Claude Code and agent sections of main.ts, moved with the same calls, words and flow: the exact diff is shown, a backup is taken and the file is written only on
// a click, and the card reads its state again 2.6 s after a write. Tests: windows/scripts/settings-tests/pages.test.mjs (check:settings).

import { AGENT_SWITCHES } from "../core/state.ts";
import { agentLabel } from "../core/pills.ts";
import type { HookAgent, HookPreview, HookStatus } from "../core/bridge.ts";
import { h, clear } from "../views/dom";
import { button, card, chip, help, notice, pathDisclosure, renderDiff, row, switchRow, wrapRow, type SwitchRow } from "./kit.ts";
import { displayPath, displayText } from "./layout.ts";
import { claudeBackupNote, hookCardChip, pillSwitch, unusableHelp } from "./status.ts";
import { setPillOn } from "./services.ts";
import type { PageView, SettingsCtx } from "./ctx.ts";

type HookKind = "claude" | HookAgent;
const KINDS: readonly HookKind[] = ["claude", "gemini", "antigravity"];
const TITLES: Record<HookKind, string> = { claude: "Claude Code hooks", gemini: "Gemini CLI hooks", antigravity: "Antigravity hooks" };
const NAMES: Record<HookKind, string> = { claude: "Claude Code", gemini: "Gemini CLI", antigravity: "Antigravity (agy)" };
const SESSIONS: Record<HookKind, string> = { claude: "a new Claude Code session", gemini: "a new Gemini CLI session", antigravity: "a new agy session" };
/** A column of blocks with the gap between them (the page's own children and a card's body). */
const STACK = "display:flex;flex-direction:column;gap:12px";

/** The hook card of one kind. `status` is null until a read lands: the card then says "Checking…" while the read is in flight, or, once a read has failed (`failed`),
 * "Couldn't read the hook status." with one Check again. Install is disabled in both cases, offers no notice, and the card's state is unknown.
 * `refreshLater` re-reads the card: it runs 2.6 s after a write, and from Check again. */
function hookCard(ctx: SettingsCtx, kind: HookKind, status: HookStatus | null, failed: boolean, refreshLater: () => void): HTMLElement {
  const body = h("div", { style: STACK });
  // A config file that is there but cannot be used (settings.json, or the agent's own file): the card says so, and nothing is offered as if it were fine.
  const broken = Boolean(status?.error);
  const el = card(TITLES[kind], { summary: hookCardChip(status, failed) }, body);
  const claude = kind === "claude";
  const name = NAMES[kind];

  const draw = (): void => {
    clear(body);
    if (status) {
      const relay = status.hookPath.split(/[\\/]/).pop() || "notchmeow-hook";
      body.append(
        help(broken ? unusableHelp(claude, status.reason) : status.installed
          ? (claude
            ? "NotchMeow is hooked into your Claude Code sessions. Tool calls, questions and permission requests show up in the island, and you can answer them there."
            : `NotchMeow is hooked into your ${name} sessions. They get a pill in the island.`)
          : (claude
            ? "Install the hooks to see your Claude Code sessions in the island and approve permissions without leaving what you are doing."
            : `Install the hooks to see your ${name} sessions in the island.`)),
        pathDisclosure([
          { label: claude ? "settings.json" : "Config file", path: status.settingsPath, shown: displayPath(status.settingsPath, ctx.home) },
          { label: "Relay", path: status.hookPath, shown: displayPath(status.hookPath, ctx.home) },
        ], (text) => ctx.backend.copyText(text)),
      );
      if (broken) body.append(wrapRow(button("Check again", refreshLater)));
      if (!status.hookReady) {
        const file = claude ? "notchmeow-hook.exe" : relay;
        body.append(notice("warn", `${file} is not in place yet. Restart NotchMeow; if it still fails, build it with \`cargo build -p notchmeow-hook\`.`));
      }
    } else if (failed) {
      body.append(
        help("Couldn't read the hook status."),
        wrapRow(button("Check again", refreshLater)),
      );
    } else {
      body.append(help("Checking…"));
    }
    // Hook commands that point at a relay which isn't there would break every session.
    const install = h("button", {
      type: "button",
      class: status?.installed ? "" : "primary",
      text: status?.installed ? "Reinstall hooks…" : "Install hooks…",
      onclick: () => void showPreview(true),
    });
    if (!status || !status.hookReady || broken) {
      install.disabled = true;
      install.title = broken ? (claude ? "settings.json couldn't be read." : "The config file couldn't be read.") : status ? "The relay isn't installed yet." : failed ? "The hook status couldn't be read." : "Checking the hooks first.";
    }
    const actions: HTMLElement[] = [install];
    if (status?.installed) actions.push(button("Uninstall hooks…", () => void showPreview(false), "danger"));
    body.append(wrapRow(...actions));
  };

  async function showPreview(install: boolean): Promise<void> {
    let preview: HookPreview;
    try {
      preview = kind === "claude"
        ? await ctx.backend.hooksPreview(install)
        : await ctx.backend.agentHooksPreview(kind, install);
    } catch (err) {
      // A file that cannot be edited safely stops here, with the reason, and nothing is written.
      clear(body);
      body.append(notice("err", String(err).replace(/^Error:\s*/, "")), wrapRow(button("Back", draw)));
      return;
    }
    clear(body);
    body.append(
      help(install
        ? `This is exactly what will change in ${claude ? "your settings.json" : "the config file"}. Your own hooks are left untouched.`
        : "This removes NotchMeow's entries only. Your own hooks are left untouched."),
      renderDiff(displayText(preview.diff, ctx.home)),
      // No file yet means nothing to back up: the backend sends an empty path.
      h("div", { class: "st-path", text: preview.backup ? `Backup → ${displayPath(preview.backup, ctx.home)}` : "The file doesn't exist yet, so it will be created." }),
    );
    const confirm = button(install ? "Back up and write" : "Back up and remove", async () => {
      confirm.disabled = true;
      try {
        // Only the reviewed diff is written: the fingerprint is the one the preview gave.
        const saved = kind === "claude"
          ? await ctx.backend.hooksApply(install, preview.fingerprint)
          : await ctx.backend.agentHooksApply(kind, install, preview.fingerprint);
        clear(body);
        body.append(notice("ok", claude
          ? `Done. ${claudeBackupNote(saved, (path) => displayPath(path, ctx.home))} Open a new Claude Code session to pick the hooks up.`
          : `Done. ${saved ? `Previous file saved as ${displayPath(saved, ctx.home)}.` : "The file was created."} Open ${SESSIONS[kind]} to pick the change up.`));
        window.setTimeout(refreshLater, 2600);
      } catch (err) {
        confirm.disabled = false;
        body.append(notice("err", `Could not write: ${String(err)}`));
      }
    }, install ? "primary" : "danger");
    body.append(wrapRow(confirm, button("Cancel", draw)));
  }

  draw();
  return el;
}

export function agentsPage(ctx: SettingsCtx): PageView {
  const hooks = new Map<HookKind, HookStatus>();
  // The kinds whose last read answered nothing and hold no status: their card says so, with Check again.
  const failed = new Set<HookKind>();
  const switches = new Map<string, SwitchRow>();
  const slots = new Map<HookKind, HTMLElement>();

  const readStatus = (kind: HookKind): Promise<HookStatus | undefined> =>
    kind === "claude" ? ctx.backend.hooksStatus() : ctx.backend.agentHooksStatus(kind);

  /** The hook kind of an agent's pill: `agent_gemini` is gemini's, `agent_antigravity` antigravity's. */
  const kindOf = (id: string): HookAgent | undefined => AGENT_SWITCHES.find((s) => s.id === id)?.tag as HookAgent | undefined;

  /** One agent's switch: on when its pill is in the settings, the chip says its hooks are missing (once the hooks have been read), and the cap disables an off switch. */
  const switchState = (id: string) => {
    const active = ctx.settings().activeIntegrations;
    const on = active.includes(id);
    const kind = kindOf(id);
    const checking = kind !== undefined && !hooks.has(kind);
    const installed = kind !== undefined && hooks.get(kind)?.installed === true;
    const p = pillSwitch(on, false, active.length, checking || installed ? null : "Hooks not installed");
    return { on, chip: p.chip, disabled: p.disabled };
  };
  const syncSwitches = (): void => {
    for (const [id, sw] of switches) {
      const st = switchState(id);
      sw.set(st.on, { chip: st.chip, disabled: st.disabled });
    }
  };

  const paintCard = (kind: HookKind): void => {
    slots.get(kind)?.replaceChildren(hookCard(ctx, kind, hooks.get(kind) ?? null, failed.has(kind), () => void refresh(kind)));
  };

  const refresh = async (kind: HookKind): Promise<void> => {
    // The card drops its failed mark and repaints while the read is in flight: a status already held stays on screen; a read that answers nothing (or fails) marks the card failed only when no status is held.
    failed.delete(kind);
    paintCard(kind);
    const fresh = await readStatus(kind).catch(() => undefined);
    if (fresh) hooks.set(kind, fresh);
    else if (!hooks.has(kind)) failed.add(kind);
    paintCard(kind);
    const pill = kind === "claude" ? undefined : `agent_${kind}`;
    const sw = pill ? switches.get(pill) : undefined;
    if (pill && sw) {
      const st = switchState(pill);
      sw.set(st.on, { chip: st.chip, disabled: st.disabled });
    }
  };

  const whereRows: Node[] = [
    row("Claude Code", chip("Main")),
    ...AGENT_SWITCHES.map(({ id }) => {
      const st = switchState(id);
      const sw = switchRow(agentLabel(id), {
        on: st.on, chip: st.chip, disabled: st.disabled,
        onChange: (on) => {
          setPillOn(ctx, id, on);
          syncSwitches();
        },
      });
      switches.set(id, sw);
      return sw.el;
    }),
  ];
  const where = card("Where you code", null,
    ...whereRows,
    help("On: the pill stays on the island and takes a slot. Off: it shows only while the agent is working."),
  );

  for (const kind of KINDS) {
    slots.set(kind, h("div"));
    paintCard(kind);
  }
  // The hook state is read on build; each card and its switch draw again when it arrives (until then the card says "Checking…").
  void Promise.all(KINDS.map((kind) => refresh(kind)));

  const root = h("div", { style: STACK }, where, ...KINDS.map((kind) => slots.get(kind)!));
  return { el: root, sync: syncSwitches };
}
