// Settings → AI and chat on Windows and Linux (Settings restyle, Task 9): Your AI (which model answers, and Choose your AI with Make main), Keys (one card per cloud provider)
// and Local models (the model servers and Add server). Today's AI section of main.ts, moved with the same calls, words and flow; the rows' words and rules are airows.ts,
// imported as Rows so its chip does not collide with the kit's. Every credential write is awaited and checked: a refusal shows an error and stops the step, and nothing is
// shown as saved. A key save never writes preferredCloud, and the page never reads a stored key back. app.ts passes the bridge's provider list in,
// so this file never names the list itself. Tests: windows/scripts/settings-tests/pages.test.mjs (check:settings).

import * as Rows from "./airows.ts";
import type { AiInput, Choice, KeyProvider, Row } from "./airows.ts";
import { keyCheckFailure } from "../core/feature.ts";
import { GIT_FOR_WINDOWS, INSTALL_GUIDE, signInWords, type ClaudeStatus } from "../core/claude.ts";
import type { AiServer, Feature, Resolution } from "../core/bridge.ts";
import type { AiSettings, ModelChoice } from "../core/state.ts";
import { h, clear, dot } from "../views/dom";
import { button, card, checkAgain, chip, details, help, keyField, notice, row, select, setValue, wrapRow } from "./kit.ts";
import { CREDENTIAL_REMOVE_FAILED, CREDENTIAL_SAVE_FAILED, presenceChip } from "./status.ts";
import { canStartWrite, saveDisabled } from "./drafts.ts";
import { discoveryMsg } from "./aicache.ts";
import type { PageView, SettingsCtx } from "./ctx.ts";

/** A cloud provider as the page reads it: the id, the brand, the credential store's key and the field's example. */
export interface CloudEntry { id: string; brand: string; key: string; placeholder: string }

/** The Add server form's key: the credential store's item for the one server this window offers (Rust's `custom-server-key.<id>`). */
export const CUSTOM_KEY = "custom-server-key.default";
/** The Add server form's address, a draft too, so a typed address survives a repaint. It is not a secret and is never kept apart from the settings. */
export const CUSTOM_URL = "custom-server-url.draft";

const STACK = "display:flex;flex-direction:column;gap:12px";
const STORED = "••••••••••••  (stored)";
const PREFER_LABEL = "When Auto picks a cloud model, prefer";
const DOT_OK = "#22c55e";
const DOT_OFF = "#f4505e";
const KEY_HELP: Record<KeyProvider, string> = {
  anthropic: "From the Claude Console. Saved in your system's credential store, checked when you save.",
  google: "From Google AI Studio. Saved in your system's credential store, checked when you save.",
  openai: "From the OpenAI dashboard. Saved in your system's credential store, checked when you save.",
};
const FEATURES: readonly { id: Feature; label: string }[] = [
  { id: "chat", label: "Chat" },
  { id: "files", label: "File questions" },
];

const choiceValue = (c: ModelChoice): string => (c === "auto" ? "auto" : JSON.stringify(c));

/** The rule Rust's `clean_server_url` applies: http(s) with a host. */
function isHttpUrl(url: string): boolean {
  try {
    const u = new URL(url);
    return (u.protocol === "http:" || u.protocol === "https:") && u.hostname !== "";
  } catch { return false; }
}

function originOf(url: string): string | null {
  try { return new URL(url).origin; } catch { return null; }
}

/** Draws a slot only when what it would draw has changed, so a sync that changes nothing leaves the focus where it is. */
function painter(slot: HTMLElement, draw: () => { sig: string; build: () => Node[] }): () => void {
  let last: string | null = null;
  return () => {
    const d = draw();
    if (d.sig === last) return;
    last = d.sig;
    slot.replaceChildren(...d.build());
  };
}

/** The words under a feature's choice: the empty and the Auto cases; a choice the person made says nothing. */
function resolutionLine(r: Resolution | undefined): string {
  if (!r) return "";
  if (r.empty) return "No model yet: add a cloud key or start a local model.";
  if (r.auto) return `${r.modelName ?? r.provider}${r.fallback ? ` · falls back to ${r.fallback}` : ""}`;
  return "";
}

/** Claude Code's status as one line: today's words, moved from drawConnect. */
function sayStatus(c: ClaudeStatus | null, read: boolean): string {
  // Not read yet: no claim either way (the install words wait for the answer). Read, and nothing came back: the row says so, and Check again stays.
  if (c === null) return read ? "Couldn't check Claude Code." : "Checking…";
  const version = c.version ? ` ${c.version}` : "";
  switch (c.state) {
    case "tooOld": return `Claude Code${version} is too old for this.`;
    case "signedOut": return `Claude Code${version} is signed out. Signing in opens a terminal, and finishes in your browser.`;
    case "signedIn": return `✓ Claude Code${version}, signed in with ${signInWords(c.authMethod)}.`;
    case "unknown": return "Couldn't ask Claude Code. Is it installed properly?";
    default:
      return c.shimOnly
        ? "Only a claude.cmd shim was found, which NotchMeow can't run. Install Claude Code with Anthropic's own installer."
        : "Claude Code isn't installed on this computer.";
  }
}

/** What the AI rows read: the Claude status, the settings, the keys saved, the cloud model each provider remembers, the servers and their models. */
export function aiInput(ctx: SettingsCtx, cloud: readonly CloudEntry[]): AiInput {
  const s = ctx.settings();
  const providersWhere = (test: (c: CloudEntry) => boolean): KeyProvider[] =>
    Rows.KEY_PROVIDERS.filter((p) => {
      const c = cloud.find((x) => x.id === p);
      return c !== undefined && test(c);
    });
  const keys = providersWhere((c) => ctx.drafts.isSaved(c.key));
  const unreadableKeys = providersWhere((c) => ctx.drafts.isUnreadable(c.key));
  const cloudModel: Record<string, string> = {};
  const cloudIds: Record<string, string[]> = {};
  for (const p of Rows.KEY_PROVIDERS) {
    cloudModel[p] = s.ai.cloudModels[p] ?? ctx.ai.models[p]?.[0]?.id ?? "";
    cloudIds[p] = (ctx.ai.models[p] ?? []).map((m) => m.id);
  }
  return {
    claudeState: ctx.ai.claude?.state ?? null,
    claudeEnabled: s.ai.claudeCodeEnabled,
    claudeModel: s.ai.claudeCodeModel,
    keys,
    unreadable: unreadableKeys,
    cloudModel,
    cloudIds,
    servers: ctx.ai.servers.map((x: AiServer) => ({
      id: x.provider, name: x.name, network: x.placement === "network", models: x.models.map((m) => m.id), status: x.status,
    })),
    memory: s.ai.localModels,
  };
}

interface Opt { group: string | null; value: string; label: string }

/** What a feature's select offers: Auto, the cloud models of the keys saved, Claude Code's three when Claude is ready, the running servers' models, and a choice kept when it is not available now. */
function featureOptions(ctx: SettingsCtx, cloud: readonly CloudEntry[], input: AiInput, claudeReady: boolean, current: ModelChoice): Opt[] {
  const out: Opt[] = [{ group: null, value: "auto", label: "Auto" }];
  for (const c of cloud) {
    if (!(input.keys as readonly string[]).includes(c.id)) continue;
    for (const m of ctx.ai.models[c.id] ?? []) {
      out.push({ group: "Cloud", value: choiceValue({ provider: c.id, model: m.id }), label: `${c.brand} · ${m.displayName}` });
    }
  }
  if (claudeReady) {
    for (const m of ["sonnet", "opus", "haiku"]) {
      out.push({ group: "Claude plan", value: choiceValue({ provider: "claudeCode", model: m }), label: `Claude plan · ${m[0].toUpperCase()}${m.slice(1)}` });
    }
  }
  for (const s of ctx.ai.servers) {
    if (s.status !== "running" || s.models.length === 0) continue;
    for (const m of s.models) out.push({ group: `Local · ${s.name}`, value: choiceValue({ provider: s.provider, model: m.id }), label: m.id });
  }
  if (current !== "auto" && !out.some((o) => o.value === choiceValue(current))) {
    out.push({ group: null, value: choiceValue(current), label: `${current.model} (not available now)` });
  }
  return out;
}

/** The options, each run of one group's options under its own optgroup (a run is broken by a plain option). */
function optionNodes(opts: readonly Opt[]): Node[] {
  const nodes: Node[] = [];
  for (const o of opts) {
    const opt = h("option", { value: o.value, text: o.label });
    const last = nodes[nodes.length - 1];
    if (o.group === null) nodes.push(opt);
    else if (last instanceof HTMLOptGroupElement && last.label === o.group) last.append(opt);
    else nodes.push(h("optgroup", { label: o.group }, opt));
  }
  return nodes;
}

/** Writes a select's options when they changed; the value goes through setValue, so a select being used keeps its place. */
function fillSelect(sel: HTMLSelectElement, opts: readonly Opt[], value: string): void {
  const sig = JSON.stringify(opts);
  if (sel.dataset.sig !== sig) {
    sel.replaceChildren(...optionNodes(opts));
    sel.dataset.sig = sig;
  }
  setValue(sel, value);
}

/** Which model answers, and Choose your AI. */
export function yourAiTab(ctx: SettingsCtx, cloud: readonly CloudEntry[]): PageView {
  const claudeReady = (): boolean => ctx.settings().ai.claudeCodeEnabled && ctx.ai.claude?.state === "signedIn";
  const keyOf = (id: string): string => cloud.find((c) => c.id === id)?.key ?? "";

  // ── Which one answers ──
  const features = FEATURES.map((f) => {
    // The full width of the row (capped as the key fields are): a long model id has to fit in the closed select.
    const sel = select([], "auto", (v) => void setChoice(f.id, v));
    sel.style.width = "100%";
    sel.style.maxWidth = "420px";
    const note = help("");
    let token = 0;
    return {
      f,
      sel,
      note,
      resolve: (): void => {
        const t = ++token;
        void ctx.backend.aiResolve(f.id).then((r) => {
          if (t === token) note.textContent = resolutionLine(r);
        });
      },
    };
  });
  const prefHost = h("div");
  const prefChoices = (): [string, string][] => {
    const out: [string, string][] = [];
    if (claudeReady()) out.push(["claudeCode", "Claude plan"]);
    if (ctx.drafts.isSaved(keyOf("anthropic"))) out.push(["anthropic", "Claude API"]);
    if (ctx.drafts.isSaved(keyOf("openai"))) out.push(["openai", "OpenAI"]);
    return out;
  };
  const paintPref = (): void => {
    const choices = prefChoices();
    const sig = choices.length < 2 ? "" : JSON.stringify(choices);
    if (prefHost.dataset.sig !== sig) {
      prefHost.dataset.sig = sig;
      const shown: Node[] = sig === ""
        ? []
        : [row(PREFER_LABEL, select(choices, ctx.settings().ai.preferredCloud, (v) => void setPreferred(v)))];
      prefHost.replaceChildren(...shown);
    }
    const sel = prefHost.querySelector("select");
    if (sel) setValue(sel, ctx.settings().ai.preferredCloud);
  };

  // ── Choose your AI: Claude's details keep their own persistent parts, so a repaint of the rows does not reset the model select ──
  const chooseBody = h("div", { style: STACK });
  const claudeBody = h("div", { style: STACK });
  const modelSel = select(
    [["sonnet", "Sonnet"], ["opus", "Opus"], ["haiku", "Haiku"]],
    ctx.settings().ai.claudeCodeModel,
    (v) => void setClaudeModel(v as AiSettings["claudeCodeModel"]),
  );
  const claudeDetails = details("Details", claudeBody,
    row("Model", modelSel),
    help("NotchMeow never signs in to Claude and never reads Claude Code's credentials."),
  );
  let signInNote: string | null = null;

  const claudeNodes = (c: ClaudeStatus | null, inUse: boolean, read: boolean): Node[] => {
    const actions: Node[] = [];
    if (c?.state === "signedIn") {
      if (inUse) {
        actions.push(h("span", { class: "check ok", text: "Claude is now your main AI." }), button("Stop using it", () => void stopClaude()));
      } else {
        actions.push(button("Use my Claude plan", () => void useClaude(), "primary"));
      }
    } else if (c?.state === "signedOut") {
      actions.push(button("Sign in", () => void signIn(), "primary"));
    } else if (c !== null) {
      actions.push(h("a", {
        href: INSTALL_GUIDE,
        text: c?.state === "tooOld" ? "How to update" : "How to install",
        onclick: (e: Event) => { e.preventDefault(); ctx.backend.openUrl(INSTALL_GUIDE); },
      }));
    }
    actions.push(button("Check again", () => void checkClaude()));
    const nodes: Node[] = [help(sayStatus(c, read)), wrapRow(...actions)];
    if (signInNote) nodes.push(notice("warn", signInNote));
    if (c?.needsGit) {
      nodes.push(h("div", { class: "notice err" },
        "Claude Code needs Git for Windows. ",
        h("a", { href: GIT_FOR_WINDOWS, text: "Get it", onclick: (e: Event) => { e.preventDefault(); ctx.backend.openUrl(GIT_FOR_WINDOWS); } }),
        ", then check again."));
    }
    return nodes;
  };
  const paintClaude = painter(claudeBody, () => {
    const s = ctx.settings();
    const c = ctx.ai.claude;
    const inUse = s.ai.claudeCodeEnabled && s.ai.preferredCloud === "claudeCode";
    return { sig: JSON.stringify([c, inUse, signInNote, ctx.ai.claudeRead]), build: () => claudeNodes(c, inUse, ctx.ai.claudeRead) };
  });

  function rowNodes(r: Row, input: AiInput, chat: ModelChoice): Node[] {
    const title = Rows.title(r, input);
    const nodes: Node[] = [row(title, chip(Rows.chip(r, input)))];
    const line = Rows.helpLine(r, input);
    if (line) nodes.push(help(line));
    if (Rows.isMain(r, chat)) {
      nodes.push(wrapRow(chip("Main")));
    } else {
      const m = Rows.makeMain(r, input);
      if (m.kind === "set") {
        nodes.push(wrapRow(button("Make main", () => void setMain(m.choice))));
      } else if (m.kind === "menu") {
        nodes.push(wrapRow(menu(title, m.choices)));
      } else {
        const off = button("Make main", () => undefined);
        off.disabled = true;
        nodes.push(wrapRow(off));
        const why = Rows.reasonLine(r, input);
        if (why) nodes.push(help(why));
      }
    }
    if (r.kind === "key" && !input.keys.includes(r.provider) && !Rows.isUnreadable(input, r)) {
      nodes.push(wrapRow(button("Add a key", () => ctx.open({ page: "chat", tab: "keys" }))));
    }
    if (r.kind === "claudePlan") nodes.push(claudeDetails);
    return nodes;
  }

  const paintChoose = painter(chooseBody, () => {
    const input = aiInput(ctx, cloud);
    const chat = ctx.settings().ai.chat;
    const list = Rows.rows(input);
    return {
      sig: JSON.stringify({ input, chat }),
      build: () => list.flatMap((r) => rowNodes(r, input, chat)),
    };
  });

  /** Make main on a server with several models: a select whose first line is the disabled "Make main…". */
  function menu(title: string, choices: readonly Choice[]): HTMLSelectElement {
    const sel = h("select", { "aria-label": `Model for ${title}` }) as HTMLSelectElement;
    sel.append(h("option", { value: "", text: "Make main…", disabled: true, selected: true }));
    for (const c of choices) sel.append(h("option", { value: JSON.stringify(c), text: c.model }));
    sel.addEventListener("change", () => {
      if (sel.value) void setMain(JSON.parse(sel.value) as Choice);
    });
    return sel;
  }

  async function setChoice(id: Feature, value: string): Promise<void> {
    const choice: ModelChoice = value === "auto" ? "auto" : (JSON.parse(value) as Choice);
    const s = ctx.settings();
    await ctx.save({ ...s, ai: { ...s.ai, [id]: choice } });
    sync();
  }

  async function setPreferred(v: string): Promise<void> {
    const s = ctx.settings();
    await ctx.save({ ...s, ai: { ...s.ai, preferredCloud: v as AiSettings["preferredCloud"] } });
    sync();
  }

  async function setClaudeModel(v: AiSettings["claudeCodeModel"]): Promise<void> {
    const s = ctx.settings();
    await ctx.save({ ...s, ai: { ...s.ai, claudeCodeModel: v } });
    sync();
  }

  /** Make main writes only the chat's choice. */
  async function setMain(choice: Choice): Promise<void> {
    const s = ctx.settings();
    await ctx.save({ ...s, ai: { ...s.ai, chat: choice } });
    sync();
  }

  async function useClaude(): Promise<void> {
    const s = ctx.settings();
    signInNote = null;
    await ctx.save({ ...s, ai: Rows.afterUseClaude(s.ai) });
    sync();
  }

  /** One save: the rules of afterStopClaude (airows.ts). */
  async function stopClaude(): Promise<void> {
    const s = ctx.settings();
    signInNote = null;
    await ctx.save({ ...s, ai: Rows.afterStopClaude(s.ai) });
    sync();
  }

  async function signIn(): Promise<void> {
    signInNote = (await ctx.backend.claudeSignIn()) ? null : "Open a terminal and run: claude auth login";
    paintClaude();
  }

  async function checkClaude(): Promise<void> {
    signInNote = null;
    // A rejected read is no status: the row then says it could not check.
    try {
      ctx.ai.claude = (await ctx.backend.claudeStatus()) ?? null;
    } catch {
      ctx.ai.claude = null;
    }
    ctx.ai.claudeRead = true;
    sync();
  }

  // The answer of each Your AI select is asked again only when what it depends on changed (resolveSignature): an echo that changes nothing asks nothing.
  let resolvedFor: string | null = null;
  function sync(): void {
    const s = ctx.settings();
    const input = aiInput(ctx, cloud);
    const sig = Rows.resolveSignature(s.ai, input);
    const resolve = sig !== resolvedFor;
    resolvedFor = sig;
    for (const x of features) {
      fillSelect(x.sel, featureOptions(ctx, cloud, input, claudeReady(), s.ai[x.f.id]), choiceValue(s.ai[x.f.id]));
      if (resolve) x.resolve();
    }
    paintPref();
    paintChoose();
    paintClaude();
    setValue(modelSel, s.ai.claudeCodeModel);
  }

  const page = h("div", { style: STACK },
    card("Which one answers", null, ...features.flatMap((x) => [row(x.f.label, x.sel), x.note]), prefHost),
    card("Choose your AI", null, chooseBody),
  );
  sync();
  return { el: page, sync };
}

/** The writes in flight, per provider. Module-level, so a tab switch within the window's life does not forget a save that is still running. */
const writing = new Set<KeyProvider>();

/** The keys, one card per cloud provider. */
export function keysTab(ctx: SettingsCtx, cloud: readonly CloudEntry[]): PageView {
  const root = h("div", { style: STACK });
  const slots = new Map<KeyProvider, HTMLElement>();
  const drawn = new Map<KeyProvider, string>();
  const entry = (p: KeyProvider): CloudEntry | undefined => cloud.find((c) => c.id === p);
  const sigOf = (p: KeyProvider, c: CloudEntry): string => JSON.stringify([ctx.drafts.presenceOf(c.key), ctx.ai.works[p] ?? null]);

  for (const p of Rows.KEY_PROVIDERS) {
    const slot = h("div");
    slots.set(p, slot);
    root.append(slot);
  }

  /** One provider's card, drawn whole. Typing changes only its "Not saved" chip and Save, in place. */
  function paintKey(p: KeyProvider, msg: HTMLElement | null = null): void {
    const c = entry(p);
    const slot = slots.get(p);
    if (!c || !slot) return;
    // A key the window always reads at boot; a key it never read is shown as unreadable, never as "No key yet".
    const presence = ctx.drafts.presenceOf(c.key) ?? "unreadable";
    const saved = presence === "present";
    const broken = presence === "unreadable";
    const mark = h("span", { class: "st-chipslot" });
    const save = h("button", { type: "button", text: "Save", onclick: () => void saveKey(p, save) }) as HTMLButtonElement;
    const update = (): void => {
      const dirty = ctx.drafts.isDirty(c.key) && !broken;
      clear(mark);
      if (dirty) mark.append(chip("Not saved"));
      save.disabled = saveDisabled(writing.has(p), dirty);
      save.classList.toggle("primary", dirty);
    };
    const input = keyField({
      id: c.key, drafts: ctx.drafts, disabled: broken, placeholder: broken ? "Can't read the credential store" : saved ? STORED : c.placeholder, onInput: update,
    });
    update();

    const w = ctx.ai.works[p];
    const kids: Node[] = [save];
    if (broken) kids.push(checkAgain(ctx, c.key, () => paintKey(p), () => ctx.ai.loadCloud(p), `${c.brand} key`));
    if (w?.ok) kids.push(h("span", { class: "check ok", text: "✓" }));
    else if (w) {
      const f = keyCheckFailure(w.text);
      kids.push(f.rejected ? h("span", { class: "check bad", text: `✗ ${f.text}` }) : h("span", { class: "check", text: f.text }));
    }
    if (saved) {
      const rm = button("Remove", () => void removeKey(p), "danger");
      rm.setAttribute("aria-label", `Remove ${c.brand} key`);
      kids.push(rm);
    }

    const children: Node[] = [row("API key", [input, mark]), help(KEY_HELP[p])];
    if (broken) children.push(help("Couldn't read the credential store."));
    children.push(wrapRow(...kids));
    if (msg) children.push(msg);
    const title = Rows.title({ kind: "key", provider: p }, aiInput(ctx, cloud));
    slot.replaceChildren(card(title, { summary: presenceChip(presence) }, ...children));
    drawn.set(p, sigOf(p, c));
  }

  // The write is awaited and checked; the check comes after the key is marked saved, and a refusal stops before either. Save is off while the write runs.
  async function saveKey(p: KeyProvider, save: HTMLButtonElement): Promise<void> {
    const c = entry(p);
    if (!c || !canStartWrite(writing.has(p)) || !ctx.drafts.canWrite(c.key)) return;
    const typed = ctx.drafts.text(c.key);
    const text = typed.trim();
    if (!text) return;
    writing.add(p);
    save.disabled = true;
    let failed = false;
    try {
      await ctx.backend.secretSet(c.key, text);
    } catch {
      failed = true;
    } finally {
      writing.delete(p);
    }
    if (failed) {
      paintKey(p, notice("err", CREDENTIAL_SAVE_FAILED));
      return;
    }
    ctx.drafts.markSaved(c.key, true, typed);
    paintKey(p, notice("ok", "Saved. It never touches disk."));
    await ctx.ai.loadCloud(p);
    paintKey(p, notice("ok", "Saved. It never touches disk."));
  }

  async function removeKey(p: KeyProvider): Promise<void> {
    const c = entry(p);
    // A save for this provider in flight comes first: a clear must not interleave with a set.
    if (!c || !canStartWrite(writing.has(p)) || !ctx.drafts.canWrite(c.key)) return;
    try {
      await ctx.backend.secretClear(c.key);
    } catch {
      paintKey(p, notice("err", CREDENTIAL_REMOVE_FAILED));
      return;
    }
    ctx.ai.forget(p);
    ctx.drafts.markSaved(c.key, false);
    paintKey(p, notice("ok", "Key removed."));
  }

  function sync(): void {
    for (const p of Rows.KEY_PROVIDERS) {
      const c = entry(p);
      const slot = slots.get(p);
      if (!c || !slot || slot.contains(document.activeElement)) continue;
      if (drawn.get(p) !== sigOf(p, c)) paintKey(p);
    }
  }

  sync();
  return { el: root, sync };
}

/** The model servers and Add server. */
export function localModelsTab(ctx: SettingsCtx): PageView {
  let addOpen = ctx.drafts.isDirty(CUSTOM_KEY) || ctx.drafts.isDirty(CUSTOM_URL);
  let msg: { kind: "ok" | "err" | "warn"; text: string } | null = null;
  const body = h("div", { style: STACK });

  function serverNodes(s: AiServer): Node[] {
    const where = s.placement === "network" ? ` · ${s.host}` : "";
    const head = row(`${s.name}${where}`, chip(Rows.serverChip(s.status, s.models.length)));
    head.querySelector(".st-labeltext")?.prepend(dot(s.status === "running" ? DOT_OK : DOT_OFF), " ");
    const out: Node[] = [head];
    if (s.unencrypted) out.push(help("unencrypted on your network", true));
    if (s.status === "off" || (s.status === "running" && s.models.length === 0)) {
      out.push(help("Start the server and load a model first."));
    }
    const link = Rows.getLink(s.provider);
    if (link && (s.status === "notInstalled" || s.status === "outdated")) {
      out.push(wrapRow(button(s.status === "outdated" ? "Update" : `Get ${s.name}`, () => ctx.backend.openUrl(link))));
    }
    return out;
  }

  function addForm(): HTMLElement {
    const url = keyField({ id: CUSTOM_URL, drafts: ctx.drafts, secure: false, placeholder: "http://192.168.1.20:11434", onInput: () => undefined });
    const key = keyField({ id: CUSTOM_KEY, drafts: ctx.drafts, placeholder: "API key (optional)", onInput: () => undefined });
    return h("div", { style: STACK },
      row("Server address", url),
      row("API key", key),
      wrapRow(button("Add", () => void addServer(), "primary")),
    );
  }

  const paint = painter(body, () => {
    const custom = ctx.settings().ai.customServer;
    return {
      sig: JSON.stringify({ servers: ctx.ai.servers, custom, addOpen, msg }),
      build: () => {
        const nodes: Node[] = ctx.ai.servers.flatMap((s) => serverNodes(s));
        const actions: Node[] = [
          button("Rescan", () => void refreshServers()),
          button("Add server…", () => {
            addOpen = true;
            paint();
            body.querySelector<HTMLInputElement>('input[type="text"]')?.focus();
          }),
        ];
        if (custom) actions.push(button("Remove server", () => void removeServer(), "danger"));
        nodes.push(wrapRow(...actions));
        if (addOpen) nodes.push(addForm());
        if (msg) nodes.push(notice(msg.kind, msg.text));
        return nodes;
      },
    };
  });

  // A rejected or empty-handed look-up keeps the list held and says so in the card; nothing is left unhandled.
  async function refreshServers(): Promise<void> {
    const found = await ctx.backend.aiDiscover().catch(() => undefined);
    if (found !== undefined) ctx.ai.setServers(found);
    const text = discoveryMsg(found, msg?.text ?? null);
    if (text !== msg?.text) msg = text ? { kind: "err", text } : null;
    paint();
  }

  // The URL is checked, then the key is written (a refusal stops: the URL is not saved), then a different server's old key is removed, then the settings are saved.
  // A settings save that is refused leaves the form, the typed address and key as they were (the saver says "Couldn't save."), and takes back the key just written,
  // so the credential store never holds a key for a server that was not saved.
  async function addServer(): Promise<void> {
    const url = ctx.drafts.text(CUSTOM_URL).trim();
    const key = ctx.drafts.text(CUSTOM_KEY).trim();
    if (!url) return;
    if (!isHttpUrl(url)) {
      msg = { kind: "err", text: "That doesn't look like a URL." };
      paint();
      return;
    }
    const before = ctx.settings();
    if (key) {
      try {
        // A key the store cannot be read for is never written: it is a refused write, as a failed one is.
        if (!ctx.drafts.canWrite(CUSTOM_KEY)) throw new Error("the store cannot be read");
        await ctx.backend.secretSet(CUSTOM_KEY, key);
      } catch {
        msg = { kind: "err", text: "Couldn't save the server's key to the credential store." };
        paint();
        return;
      }
    } else if (!before.ai.customServer || originOf(url) !== originOf(before.ai.customServer)) {
      // No key typed: a key still stored belongs to no server (none is set) or to another one, and must not be inherited: it would be sent to this one as a Bearer token.
      // It is cleared before the server is saved, and a clear that fails (or a store that cannot be read) refuses the add. The same server again keeps its key.
      try {
        if (!ctx.drafts.canWrite(CUSTOM_KEY)) throw new Error("the store cannot be read");
        await ctx.backend.secretClear(CUSTOM_KEY);
      } catch {
        msg = { kind: "err", text: "Couldn't remove the old server's key from the credential store." };
        paint();
        return;
      }
      ctx.drafts.markSaved(CUSTOM_KEY, false);
    }
    const cur = ctx.settings();
    if (!(await ctx.save({ ...cur, ai: { ...cur.ai, customServer: url } }))) {
      if (key) {
        try {
          await ctx.backend.secretClear(CUSTOM_KEY);
        } catch {
          msg = { kind: "err", text: "Couldn't remove the server's key from the credential store." };
          paint();
        }
      }
      return;
    }
    if (key) ctx.drafts.markSaved(CUSTOM_KEY, true);
    ctx.drafts.edit(CUSTOM_URL, "");
    addOpen = false;
    msg = null;
    await refreshServers();
  }

  // The settings are saved first and the key is cleared after: a refused save leaves the server and its key both in place (the saver says "Couldn't save.").
  async function removeServer(): Promise<void> {
    if (!ctx.drafts.canWrite(CUSTOM_KEY)) {
      msg = { kind: "err", text: "Couldn't remove the server's key from the credential store." };
      paint();
      return;
    }
    const cur = ctx.settings();
    if (!(await ctx.save({ ...cur, ai: { ...cur.ai, customServer: null } }))) return;
    try {
      await ctx.backend.secretClear(CUSTOM_KEY);
      ctx.drafts.markSaved(CUSTOM_KEY, false);
      msg = null;
    } catch {
      // The server is gone; its key is not, and says so.
      msg = { kind: "err", text: "Couldn't remove the server's key from the credential store." };
    }
    await refreshServers();
  }

  // A rebuild would take the focus out of the Add server form: while the focus is inside, the repaint waits for the blur (or the next sync).
  body.addEventListener("focusout", (e) => {
    if (!body.contains((e as FocusEvent).relatedTarget as Node | null)) paint();
  });
  // The page's own sync (from the shell and the app): while the focus is inside the form, the repaint waits for the blur or the next sync.
  function sync(): void {
    if (body.contains(document.activeElement)) return;
    paint();
  }

  paint();
  return {
    el: card("Local models", null,
      help("Models running on this computer, or on a server you add. Found automatically on this computer only."),
      body),
    sync,
  };
}
