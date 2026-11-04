// The companion's text for one turn (sub-project F3a-tauri, Task 5): the page builds it with promptOf (companion/core.ts) from the Projects view, the
// settings and the state, and Rust cuts it and sends it as the system text. Pure: the day and the clock are passed in. Nothing of the machine goes in but
// what the Projects view and the settings hold; the account name is never read on Windows and Linux (no `userName`).
// Loaded by the plain-Node checks (npm run check:companion): erasable TypeScript only, relative imports with the `.ts` extension.

import { PRESETS } from "../cat/presets.ts";
import { TRAIT_KEYS } from "../cat/personality.ts";
import type { Settings } from "../core/state.ts";
import type { ProjectsView } from "../projects/core.ts";
import { cloudNotice, companionQuiet, needsCloudNotice, promptOf, rightNowOf } from "./core.ts";
import type { CompanionSettings } from "./core.ts";

/** What a turn knows of the machine right now: the "Right now" block, whether the chat is quiet, and the Main cat's mood. */
export interface TurnContext {
  rightNow: string;
  quiet: boolean;
  mood: string;
}

/** The context of a turn: the Projects view (its waiting count counts a wait stepped back into its app), whether an approval or question card is up, and the mood. */
export function contextOf(i: { view: ProjectsView; attention: boolean; mood: string }): TurnContext {
  return {
    rightNow: rightNowOf(i.view),
    quiet: companionQuiet({ waiting: i.view.waiting, card: i.attention }),
    mood: i.mood,
  };
}

/** The local calendar day as YYYY-MM-DD. */
export function localDay(d: Date): string {
  const two = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${two(d.getMonth() + 1)}-${two(d.getDate())}`;
}

/** The companion's text for a turn: promptOf with the Windows words, no memory, no account name, the Main cat's label and personality. */
export function systemFor(ctx: TurnContext, settings: Settings, today: string): string {
  const character = settings.cat.character;
  const entry = settings.cat.cats[character];
  const personality = entry ? Object.fromEntries(TRAIT_KEYS.map((k) => [k, entry.personality[k]])) : undefined;
  return promptOf({
    catName: PRESETS[character]?.label,
    personality,
    humor: settings.companion.humor,
    quiet: ctx.quiet,
    mood: ctx.mood,
    useMemory: false,
    seeSessions: settings.companion.seeSessions,
    rightNow: ctx.rightNow,
    today,
    device: "pc",
  });
}

/** The name in the cloud line: the Claude plan is Anthropic's, a custom server is "your custom server" (never its id or host), any other provider is named by its id. */
export function brandOf(provider: string): string {
  if (provider === "anthropic" || provider === "claudeCode") return "Anthropic";
  if (provider === "openai") return "OpenAI";
  if (provider === "google") return "Google";
  if (provider === "custom") return "your custom server";
  return provider;
}

/**
 * The one-time cloud line for the brain a turn goes to: the line, and the providers already shown once (sorted), or null when none is due. A "network" brain
 * (a custom server whose host is not this computer) counts as cloud: the contract's rule fires for `cloud` only, so the app maps it here.
 */
export function cloudLine(r: { provider: string | null; placement: string | null } | null, s: CompanionSettings): { line: string; shown: string[] } | null {
  if (r === null || r.provider === null) return null;
  if (!needsCloudNotice({ placement: r.placement === "network" ? "cloud" : r.placement, seeSessions: s.seeSessions, provider: r.provider, shown: s.cloudNoticeShown })) return null;
  return { line: cloudNotice(brandOf(r.provider)), shown: [...s.cloudNoticeShown, r.provider].sort() };
}
