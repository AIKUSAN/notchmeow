// The Settings window's backend (Settings restyle, Task 5): the one file besides main.ts that talks to the Bridge. Every call goes through Bridge, which does nothing outside
// Tauri, so the page still draws in a plain browser; the values are the types the old page already used. The keys are only ever asked whether they exist, never read back.

import { Bridge, onEvent } from "../core/bridge.ts";
import type { AiServer, BootInfo, Checked, Feature, HookAgent, HookPreview, HookStatus, ModelInfo, Resolution } from "../core/bridge.ts";
import type { ClaudeStatus } from "../core/claude.ts";
import type { Settings } from "../core/state.ts";
import type { LinkBackend } from "../link/model.ts";
import type { Presence } from "./status.ts";

export interface SettingsBackend {
  boot(): Promise<BootInfo | undefined>;
  /** True when the store confirmed the write; false when it refused (the window then goes back to the stored value). */
  save(settings: Settings): Promise<boolean>;
  /** Reads the settings file once more (Try again): the settings it now holds, or the refusal's fixed sentence. */
  settingsRetryLoad(): Promise<Checked<Settings>>;
  /** Accepts the defaults so saves work again (Start fresh): the refusal's sentence when the file reads now. */
  settingsStartFresh(): Promise<Checked<void>>;
  hooksStatus(): Promise<HookStatus | undefined>;
  hooksPreview(install: boolean): Promise<HookPreview>;
  hooksApply(install: boolean, fingerprint: string): Promise<string>;
  agentHooksStatus(agent: HookAgent): Promise<HookStatus | undefined>;
  agentHooksPreview(agent: HookAgent, install: boolean): Promise<HookPreview>;
  agentHooksApply(agent: HookAgent, install: boolean, fingerprint: string): Promise<string>;
  /** Stored, not stored, or a store that cannot be read. Never absent because a read failed. */
  secretPresence(key: string): Promise<Presence>;
  secretSet(key: string, value: string): Promise<void>;       // throws on a refusal
  secretClear(key: string): Promise<void>;                    // throws on a refusal
  aiListModels(provider: string): Promise<ModelInfo[]>;
  aiDiscover(): Promise<AiServer[] | undefined>;
  aiResolve(feature: Feature): Promise<Resolution | undefined>;
  claudeStatus(): Promise<ClaudeStatus | undefined>;
  claudeSignIn(): Promise<boolean | undefined>;
  aiLocalModel(): Promise<string | null | undefined>;
  openUrl(url: string): void;
  copyText(text: string): Promise<boolean>;
  /** What the companion last sent a model, one line per message part (memory only). */
  companionLastSent(): Promise<string[]>;
  /** How many conversations are saved on this computer. */
  companionCount(): Promise<number>;
  /** Deletes every saved conversation; true when the store confirmed it. */
  companionDeleteAll(): Promise<boolean>;
  link: LinkBackend;
  /** Asks the island for its live project names (Settings → Cat → Project cats); they come back as "projects-live". */
  askProjectsLive(): void;
  on<T>(event: "settings-changed" | "ai-servers-changed" | "settings-place" | "settings-hidden" | "projects-live", handler: (payload: T) => void): void;
}

/** The Settings window's backend over Rust's commands and events. */
export function bridgeSettingsBackend(link: LinkBackend): SettingsBackend {
  return {
    boot: async () => (await Bridge.boot()) ?? undefined,
    save: (settings) => Bridge.saveSettingsChecked(settings),
    settingsRetryLoad: () => Bridge.settingsRetryLoad(),
    settingsStartFresh: () => Bridge.settingsStartFresh(),
    hooksStatus: async () => (await Bridge.hooksStatus()) ?? undefined,
    hooksPreview: (install) => Bridge.hooksPreview(install),
    hooksApply: (install, fingerprint) => Bridge.hooksApply(install, fingerprint),
    agentHooksStatus: async (agent) => (await Bridge.agentHooksStatus(agent)) ?? undefined,
    agentHooksPreview: (agent, install) => Bridge.agentHooksPreview(agent, install),
    agentHooksApply: (agent, install, fingerprint) => Bridge.agentHooksApply(agent, install, fingerprint),
    // A failed call is unreadable: the page never takes a failed read for a key that is not stored.
    secretPresence: async (key) => (await Bridge.secretPresence(key)) ?? "unreadable",
    secretSet: (key, value) => Bridge.secretSet(key, value),
    secretClear: (key) => Bridge.secretClear(key),
    aiListModels: (provider) => Bridge.aiListModels(provider),
    aiDiscover: async () => (await Bridge.aiDiscover()) ?? undefined,
    aiResolve: async (feature) => (await Bridge.aiResolve(feature)) ?? undefined,
    claudeStatus: async () => (await Bridge.claudeStatus().catch(() => undefined)) ?? undefined,
    claudeSignIn: async () => (await Bridge.claudeSignIn()) ?? undefined,
    aiLocalModel: () => Bridge.aiLocalModel(),
    openUrl: (url) => void Bridge.openUrl(url),
    copyText: async (text) => (await Bridge.copyText(text)) === true,
    companionLastSent: () => Bridge.companionLastSent(),
    companionCount: async () => (await Bridge.companionList()).length,
    companionDeleteAll: () => Bridge.companionDeleteAll(),
    link,
    askProjectsLive: () => void Bridge.askProjectsLive(),
    on<T>(event: "settings-changed" | "ai-servers-changed" | "settings-place" | "settings-hidden" | "projects-live", handler: (payload: T) => void): void {
      // A listener that cannot be registered is logged: the window then shows what it has, and the log says why a change did not arrive.
      onEvent<T>(event, handler).catch((err: unknown) => console.error(`[notchmeow] listen to ${event} failed`, err));
    },
  };
}
