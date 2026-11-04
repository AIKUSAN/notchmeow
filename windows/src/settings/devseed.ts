// Dev server only (Settings restyle, Task 5): the Settings window's stand-in backend for `settings.html?sample=<state>`, with `stress` for long strings, so the pictures and the
// `?dev` panel can show every page without the app. The home folder is the sample C:\Users\sample; nothing here reads this computer. Only the dev server loads this file.
//   ready   Claude Code and Gemini CLI hooks installed, the relay ready; Resend, GitHub and Vercel saved; four pills on (Gemini CLI, Resend, n8n, Vercel); on General, two (Gemini CLI, GitHub)
//   empty   nothing saved, no hooks installed, the relay not ready, no pill on
//   error   the store cannot be read for Resend's key (Services) and the Anthropic key (Your AI, Keys): both show "Couldn't read", disabled; Claude Code's settings.json is not valid; Gemini CLI's config cannot be read (its card says so, Install is off); four pills on (both agents, Resend, GitHub) and Resend typed, not saved
// `?bootproblem=unreadable|unparseable` (any sample) makes the boot report the settings file as unreadable (saves refused, the store says so) or unparseable (a kept copy's name);
// Try again succeeds on the first click in the dev backend, as the file reads once it is retried. Task 3 of the Settings polish.
// `stress` adds the long strings: a 90-character config path and Gemini's relay not in place under a long file name (the agents' notice and their wrapping), a 120-character n8n URL typed into its field (the services) and, on Devices, a machine with a long name.
// Devices draws the link's seeds (link/devseed.ts): ready is `on`, empty is `off` and error is `problem`; `stress` is `on` with one more row. Every call still goes to the link backend it was given.
// Task 9 adds the chat samples (the AI settings, the cloud models, the servers, Claude Code and the resolution words). Task 10 adds the Sidekick samples (ready mutes two stuck kinds
// and finds a local model; error turns the master switch off and mutes all four stuck kinds; empty is the defaults) and the Cat sample (ready shows the cats in the per-agent mode;
// stress adds an agent with a long name). Task 12 adds the Companion's three answers (ready has three conversations and a last request; the others none).

import { DEFAULT_AI, DEFAULT_SETTINGS, type AiSettings } from "../core/state.ts";
import type { AiServer, BootInfo, Feature, HookAgent, HookPreview, HookStatus, ModelInfo, Resolution, SettingsProblem } from "../core/bridge.ts";
import type { ClaudeStatus } from "../core/claude.ts";
import type { SettingsBackend } from "./backend.ts";
import type { LinkBackend, LinkRow, LinkSnapshot } from "../link/model.ts";
import { LINK_EMPTY } from "../link/model.ts";
import { CUSTOM_KEY, CUSTOM_URL } from "./ai.ts";
import { UNREADABLE_CONFIG } from "./status.ts";
import { cleanSidekickSettings, type SidekickSettings } from "../sidekick/core.ts";
import { defaultCatBlock, withAgentCat, withDisplayMode, withProjectCat, type CatBlock } from "../cat/display.ts";
import type { LiveProject } from "../projects/present.ts";

const HOME = "C:\\Users\\sample";
const LONG = " (a long build label that has to wrap at every width without a sideways scroll)";
const RELAY = "c:\\users\\SAMPLE\\AppData\\Local\\NotchMeow\\bin\\notchmeow-hook.exe";
const CLAUDE_FILE = `${HOME}\\.claude\\settings.json`;
const GEMINI_FILE = `${HOME}\\.gemini\\settings.json`;
/** Stress's Gemini relay: a long file name with hyphens, so it wraps at the break points (not in the middle of a word). */
const GEMINI_RELAY_STRESS = `${HOME}\\AppData\\Local\\NotchMeow\\bin\\notchmeow-hook-gemini-with-a-long-build-label-for-the-stress-sample.exe`;
const LONG_FOLDER = `${HOME}\\AppData\\Roaming\\NotchMeow\\sample-profile-folder-2026`;
const LONG_CLAUDE = `${LONG_FOLDER}\\.claude\\settings.json`;
const LONG_GEMINI = `${LONG_FOLDER}\\.gemini\\settings.json`;
/** The relay path as the JSON of a settings file writes it, so the preview's `+` line carries the escaped form the page shortens. */
const ESCAPED_RELAY = "C:\\\\Users\\\\sample\\\\AppData\\\\Local\\\\NotchMeow\\\\notchmeow-hook.exe";
const LONG_URL = ("https://n8n.sample.example/webhook/" + "sample-workflow-".repeat(10)).slice(0, 120);

type State = "ready" | "empty" | "error";
const stateOf = (sample: string): State => (sample === "error" ? "error" : sample === "ready" ? "ready" : "empty");

/** Which hooks are installed in each sample. */
const INSTALLED: Record<State, Record<"claude" | HookAgent, boolean>> = {
  ready: { claude: true, gemini: true, antigravity: false },
  empty: { claude: false, gemini: false, antigravity: false },
  error: { claude: false, gemini: true, antigravity: false },
};
/** The keys saved in each sample. The error sample cannot say what is saved, so it lists none. */
const SAVED: Record<State, readonly string[]> = {
  ready: ["anthropic-api-key", "resend-api-key", "github-token", "vercel-token"],
  empty: [],
  error: [],
};
/** The General page's ready sample: two pills on (Gemini CLI and GitHub), with sounds at the default 0.12. Only the General page reads it; ACTIVE.ready (four pills) still feeds Services, Agents and the stress sample. */
const GENERAL_READY_ACTIVE = ["agent_gemini", "integration_github"] as const;

/** The pills on in each sample. */
const ACTIVE: Record<State, readonly string[]> = {
  ready: ["agent_gemini", "integration_resend", "integration_n8n", "integration_vercel"],
  empty: [],
  error: ["agent_gemini", "agent_antigravity", "integration_resend", "integration_github"],
};

// ── Task 9: the AI and chat samples. Only the ready sample has models, servers and Claude Code signed in; error refuses the OpenAI key and the server key on save.

const model = (id: string, displayName: string): ModelInfo => ({ id, displayName, contextTokens: null, capabilities: { tools: true, vision: false, json: true } });
const OLLAMA_MODELS = [model("qwen3.5:2b", "qwen3.5:2b"), model("gemma3:4b", "gemma3:4b")];
const STUDIO_MODEL = "qwen2.5-7b-instruct";
/** The stress sample's model id: 40 characters and one token, so it can only sit in a one-line field or a select. */
const LONG_MODEL = "lmstudio-community/sample-long-model-001";
const CLOUD_MODELS: Record<string, ModelInfo[]> = {
  anthropic: [model("claude-sonnet-5-5", "Claude Sonnet 5.5"), model("claude-haiku-5-5", "Claude Haiku 5.5")],
};
/** The keys the error sample cannot read: one Services key and one AI key. Every other key is not stored in that sample. */
const UNREADABLE: readonly string[] = ["resend-api-key", "anthropic-api-key"];
/** The saves the error sample refuses: the OpenAI key and the Add server key. */
const REFUSED: readonly string[] = ["openai-api-key", CUSTOM_KEY];

/** The four servers of the ready sample: Ollama running two models, a Studio PC on the network (unencrypted, one model), LM Studio off and Jan running with no model loaded. Stress renames the Studio PC and gives it the long model id. */
function sampleServers(stress: boolean): AiServer[] {
  return [
    { provider: "ollama", name: "Ollama", baseUrl: "http://127.0.0.1:11434", host: "127.0.0.1:11434", placement: "local", status: "running", models: OLLAMA_MODELS, unencrypted: false },
    {
      provider: "custom", name: stress ? "Studio PC in the back office (LM Studio)" : "Studio PC",
      baseUrl: "http://192.168.1.20:11434", host: "192.168.1.20:11434", placement: "network", status: "running",
      models: [model(stress ? LONG_MODEL : STUDIO_MODEL, stress ? LONG_MODEL : STUDIO_MODEL)], unencrypted: true,
    },
    { provider: "lmstudio", name: "LM Studio", baseUrl: "http://127.0.0.1:1234", host: "127.0.0.1:1234", placement: "local", status: "off", models: [], unencrypted: false },
    // Running with no models loaded: its chip is "Running, no models yet" (the Local models tab's measured row at 415).
    { provider: "jan", name: "Jan", baseUrl: "http://127.0.0.1:1337", host: "127.0.0.1:1337", placement: "local", status: "running", models: [], unencrypted: false },
  ];
}

/** Chat's and File questions' resolution words: Auto's line for chat, nothing for the file choice (the person picked it), no model for the empty sample. */
function resolutionFor(state: State, stress: boolean, feature: Feature): Resolution | undefined {
  const none = { provider: null, model: null, placement: null, modelName: null, reader: null, fallback: null };
  if (state === "empty") return { empty: true, auto: true, ...none };
  if (state !== "ready") return undefined;
  if (feature === "files") {
    return { empty: false, auto: false, provider: "ollama", model: "qwen3.5:2b", placement: "local", modelName: "qwen3.5:2b", reader: "Local · qwen3.5:2b", fallback: null };
  }
  const long = "Claude Sonnet 5.5 through your Claude plan, with a local retry on the Studio PC in the back office";
  return {
    empty: false, auto: true, provider: "anthropic", model: "claude-sonnet-5-5", placement: "cloud",
    modelName: stress ? long : "Claude Sonnet 5.5", reader: "Claude",
    fallback: stress ? "Local · Studio PC in the back office (LM Studio)" : "Local · qwen3.5:2b",
  };
}

/** The AI settings of each sample: only the ready sample keeps a choice (Auto for chat, Ollama for File questions; stress puts File questions on the long model, so its id shows in the select), a remembered model and the Studio PC address. */
function aiFor(state: State, stress: boolean): AiSettings {
  if (state !== "ready") return DEFAULT_AI;
  return {
    ...DEFAULT_AI,
    claudeCodeEnabled: true,
    preferredCloud: "anthropic",
    cloudModels: { anthropic: "claude-sonnet-5-5" },
    localModels: { ollama: "qwen3.5:2b" },
    files: stress ? { provider: "custom", model: LONG_MODEL } : { provider: "ollama", model: "qwen3.5:2b" },
    customServer: "http://192.168.1.20:11434",
  };
}

// ── Task 10: the Sidekick and Cat samples.

/** The Sidekick settings of each sample: ready mutes the errors and gone-quiet kinds; error turns the master off and mutes the four stuck kinds; empty is the defaults. */
function sidekickFor(state: State): SidekickSettings {
  if (state === "ready") return cleanSidekickSettings({ on: true, local: true, dismissals: { recap: 0, "stuck.loop": 0, "stuck.errors": 2, "stuck.waiting": 0, "stuck.silent": 2 } });
  if (state === "error") return cleanSidekickSettings({ on: false, local: true, dismissals: { recap: 0, "stuck.loop": 2, "stuck.errors": 2, "stuck.waiting": 2, "stuck.silent": 2 } });
  return cleanSidekickSettings(null);
}

/** The Cat settings of each sample: ready shows the cats for each agent; stress adds an agent with a long name. */
function catFor(state: State, stress: boolean): CatBlock {
  if (state !== "ready") return defaultCatBlock();
  // Project cats: the "site" project keeps an Oreo (its folder name is the key); "notchmeow" has none and gets the cat the Main cat leaves free.
  const perAgent = withProjectCat(withDisplayMode(defaultCatBlock(), "perAgent"), "site", "oreo");
  return stress ? withAgentCat(perAgent, "agent_a-rather-long-agent-name", "midnight") : perAgent;
}

/** A folder name of 60 characters, for the stress sample's long row. */
const LONG_PROJECT = "sample-project-folder-with-a-long-name-for-the-stress-checks";

/** The island's live projects the ready sample names (Settings → Cat → Project cats): two folders, and the long one under stress. Names only, as the island sends them. */
function liveFor(state: State, stress: boolean): LiveProject[] {
  if (state !== "ready") return [];
  const live = [{ catKey: "notchmeow", name: "notchmeow" }, { catKey: "site", name: "site" }];
  return stress ? [...live, { catKey: LONG_PROJECT, name: LONG_PROJECT }] : live;
}

/** The pills on at boot: the General override on the General page's ready sample, else ACTIVE. The page is read from the dev page's address, as the shell reads its place. */
function activeFor(sample: string, stress: boolean): readonly string[] {
  const page = typeof location === "undefined" ? null : new URLSearchParams(location.search).get("page");
  return sample === "ready" && !stress && page === "general" ? GENERAL_READY_ACTIVE : ACTIVE[stateOf(sample)];
}

/** The link seed each sample draws (link/devseed.ts's names). */
const LINK_SEED: Record<State, string> = { ready: "on", empty: "off", error: "problem" };
const STRESS_ROW: LinkRow = { id: "e5".repeat(16), name: "A machine with a rather long name for testing the column", state: "pairedOffline" };

/** The Devices snapshot of a sample. The seeds come in with a dynamic import, as main.ts loads the stand-in: only the dev server ever loads them. */
async function sampleSnapshot(sample: string, stress: boolean): Promise<LinkSnapshot> {
  const { SEEDS } = await import("../link/devseed.ts");
  const base: LinkSnapshot = { ...LINK_EMPTY, name: "Desk PC", folder: `${HOME}\\Downloads\\NotchMeow`, ...SEEDS[stress ? "on" : LINK_SEED[stateOf(sample)]] };
  return stress ? { ...base, rows: [...base.rows, STRESS_ROW] } : base;
}

/** The link the sample's Devices section reads: its snapshot is the sample's; every action goes to the link it was given. */
function sampleLink(link: LinkBackend, sample: string, stress: boolean): LinkBackend {
  return { ...link, state: () => sampleSnapshot(sample, stress), onSnapshot: () => () => {} };
}

/** Fields typed and not saved, for the sample that shows one (the dev page cannot type). */
export function devTyped(sample: string, stress: boolean): Record<string, string> {
  const typed: Record<string, string> = {};
  if (stateOf(sample) === "error") {
    typed["resend-api-key"] = "sample-key-0000";
    typed["openai-api-key"] = "sample-key-0000";
    typed[CUSTOM_KEY] = "sample-key-0000";
    typed[CUSTOM_URL] = "http://192.168.1.30:11434";
  }
  if (stress) typed["n8n-url"] = LONG_URL;
  return typed;
}

/** The boot's problem the dev route asks for (?bootproblem=). Anything else is no problem. */
export function bootProblemOf(v: string | null): SettingsProblem | null {
  if (v === "unreadable") return { kind: "unreadable" };
  if (v === "unparseable") return { kind: "unparseable", keptAs: "settings.json.bad-sample" };
  return null;
}

/** `failSave` (?failsave=1, error sample only) refuses the first save, so a picture shows the refused save's note and the revert. `bootProblem` (?bootproblem=) is what the boot reports. */
export function devSettingsBackend(sample: string, stress: boolean, link: LinkBackend, failSave = false, bootProblem: string | null = null): SettingsBackend {
  const state = stateOf(sample);
  let refuse = failSave && state === "error";
  let problem = bootProblemOf(bootProblem);
  const configPath = (agent: HookAgent | null): string => (stress ? (agent ? LONG_GEMINI : LONG_CLAUDE) : agent ? GEMINI_FILE : CLAUDE_FILE);
  const hook = (agent: HookAgent | null): HookStatus => {
    // Stress: Gemini's relay is not in place, under a long file name, so the card's warning notice (which names the relay's file) runs to two or more lines at 415.
    const longGemini = stress && agent === "gemini";
    // The error sample's Gemini config is there but cannot be read: not installed, and the card says so.
    const unreadable = state === "error" && agent === "gemini";
    return {
      installed: unreadable ? false : INSTALLED[state][agent ?? "claude"],
      error: unreadable ? UNREADABLE_CONFIG : null,
      reason: unreadable ? "not valid JSON" : null,
      settingsPath: configPath(agent),
      hookPath: longGemini ? GEMINI_RELAY_STRESS : `${RELAY}${stress ? "-with-a-very-long-name-that-goes-on-and-on-to-test-wrapping" : ""}`,
      hookReady: longGemini ? false : state !== "empty",
    };
  };
  const preview = (agent: HookAgent | null): HookPreview => ({
    diff: agent
      ? `+ "command": "${ESCAPED_RELAY} --agent ${agent}"`
      : "+ \"hooks\": { \"PreToolUse\": [ { \"command\": \"notchmeow-hook.exe\" } ] }",
    backup: `${configPath(agent)}.bak`,
    settingsPath: configPath(agent),
    fingerprint: "sample-fingerprint",
  });
  const info: BootInfo = {
    settings: { ...DEFAULT_SETTINGS, activeIntegrations: [...activeFor(sample, stress)], ai: aiFor(state, stress), sidekick: sidekickFor(state), cat: catFor(state, stress) },
    screen: { x: 0, y: 0, width: 1920, height: 1080, scale: 1 },
    version: stress ? `1.0.0${LONG}` : "1.0.0",
    hookPath: RELAY,
    cursorPoll: true,
    desktopPositioned: true,
    home: HOME,
    shelf: { dragOut: true, send: true },
    claudeApp: false,
    foreground: "none",
  };
  // The chat page reads Claude Code's status in every sample; error is signed out and Git is missing.
  const claude: ClaudeStatus = state === "ready"
    ? { state: "signedIn", version: "2.1.289", authMethod: "claude.ai", shimOnly: false, needsGit: false }
    : state === "error"
      ? { state: "signedOut", version: "2.1.289", authMethod: null, shimOnly: false, needsGit: true }
      : { state: "notInstalled", version: null, authMethod: null, shimOnly: false, needsGit: false };
  return {
    boot: async () => ({ ...info, settingsProblem: problem }),
    save: async () => {
      // While the file is unreadable the store refuses every write, as Rust does.
      if (problem?.kind === "unreadable") return false;
      const ok = !refuse;
      refuse = false;
      return ok;
    },
    settingsRetryLoad: async () => {
      problem = null;
      return { ok: true, value: info.settings };
    },
    settingsStartFresh: async () => {
      problem = null;
      return { ok: true, value: null };
    },
    hooksStatus: async () => hook(null),
    hooksPreview: async () => {
      if (state === "error") throw new Error("~/.claude/settings.json is not valid JSON: NotchMeow has not touched it.");
      return preview(null);
    },
    hooksApply: async () => "Hooks installed (sample).",
    agentHooksStatus: async (agent) => hook(agent),
    agentHooksPreview: async (agent) => preview(agent),
    agentHooksApply: async () => "Hooks installed (sample).",
    secretPresence: async (key) => (state === "error" && UNREADABLE.includes(key) ? "unreadable" : SAVED[state].includes(key) ? "present" : "absent"),
    secretSet: async (key) => {
      if (state === "error" && REFUSED.includes(key)) throw new Error("The credential store refused the write (sample).");
    },
    secretClear: async () => {},
    aiListModels: async (provider): Promise<ModelInfo[]> => (state === "ready" ? (CLOUD_MODELS[provider] ?? []) : []),
    aiDiscover: async (): Promise<AiServer[]> => (state === "ready" ? sampleServers(stress) : []),
    aiResolve: async (feature): Promise<Resolution | undefined> => resolutionFor(state, stress, feature),
    claudeStatus: async () => claude,
    claudeSignIn: async () => false,
    aiLocalModel: async () => (state === "ready" ? "qwen3.5:2b" : null),
    openUrl: () => {},
    copyText: async () => true,
    // The Companion tab (Task 12): ready has three saved conversations and a last request; the others have none. The sample lines name no one and no path.
    companionLastSent: async () => (state === "ready" ? ["[system] sample instructions", "[user] a sample question"] : []),
    companionCount: async () => (state === "ready" ? 3 : 0),
    companionDeleteAll: async () => true,
    link: sampleLink(link, sample, stress),
    on: <T>(event: string, handler: (payload: T) => void): void => {
      // The sample's live names arrive at once, as the island sends them when this window asks.
      if (event === "projects-live") (handler as (payload: unknown) => void)(liveFor(state, stress));
    },
    askProjectsLive: () => {},
  };
}
