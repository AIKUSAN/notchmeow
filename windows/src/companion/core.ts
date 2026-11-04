// The companion's rules, typed (docs/COMPANION-CONTRACT.md). The rules themselves are shared/companion-core.js, copied by scripts/gen-companion-ts.mjs into
// core.generated.ts; this file gives them their types and nothing else. Pure: no clock, no network, no files. Every rule is given the time it needs.
// Loaded by the plain-Node checks (npm run check:companion): erasable TypeScript only, relative imports with the `.ts` extension.

import { CompanionCore } from "./core.generated.ts";

export type Humor = "off" | "little" | "more";
export type QuickKind = "fix" | "rewrite" | "explain" | "explainImage";

export interface CompanionSettings {
  humor: Humor; useMemory: boolean; seeSessions: boolean; polishRecap: boolean; recapDismissals: number; lastRecapDay: string; cloudNoticeShown: string[];
}
export interface StoredMessage { role: "user" | "assistant"; text: string; caption: string; files: string[] }
export interface Conversation { version: 1; id: string; title: string; pinned: boolean; createdAt: number; updatedAt: number; messages: StoredMessage[] }
export interface QuickRequest { system: string; user: string; cut: boolean }
export interface PromptInput {
  catName?: string; userName?: string; personality?: Record<string, number>; humor?: Humor; quiet?: boolean; mood?: string; useMemory?: boolean; memory?: unknown;
  seeSessions?: boolean; rightNow?: string; today?: string; placement?: string; contextTokens?: number | null; device?: "mac" | "pc";
}

export const HUMOR_LEVELS = CompanionCore.HUMOR_LEVELS as readonly Humor[];
export const CONVERSATIONS_MAX = CompanionCore.CONVERSATIONS_MAX as number;
export const TITLE_MAX = CompanionCore.TITLE_MAX as number;
export const QUICK_KINDS = CompanionCore.QUICK_KINDS as readonly QuickKind[];
export const QUICK_TEXT_MAX = CompanionCore.QUICK_TEXT_MAX as number;
export const QUICK_NO_VISION = CompanionCore.QUICK_NO_VISION as string;
export const QUICK_TOOLS_REFUSED = CompanionCore.QUICK_TOOLS_REFUSED as string;
export const RIGHT_NOW_MAX = CompanionCore.RIGHT_NOW_MAX as number;

export const promptOf = CompanionCore.promptOf as (i: PromptInput) => string;
export const companionQuiet = CompanionCore.companionQuiet as (i: { waiting: number; card: boolean }) => boolean;
export const moodHint = CompanionCore.moodHint as (state: string) => string;
export const memoryTokensFor = CompanionCore.memoryTokensFor as (placement: string | null, contextTokens: number | null) => number;
export const rightNowOf = CompanionCore.rightNowOf as (view: unknown) => string;
export const cloudNotice = CompanionCore.cloudNotice as (provider: string) => string;
export const needsCloudNotice = CompanionCore.needsCloudNotice as (i: { placement: string | null; seeSessions: boolean; provider: string | null; shown: readonly string[] }) => boolean;
export const titleOf = CompanionCore.titleOf as (text: unknown) => string;
export const conversationClean = CompanionCore.conversationClean as (raw: unknown) => Conversation | null;
export const conversationsKeep = CompanionCore.conversationsKeep as (entries: readonly { id: string; pinned: boolean; updatedAt: number }[]) => { keep: string[]; evict: string[] };
export const cleanCompanionSettings = CompanionCore.cleanCompanionSettings as (raw: unknown) => CompanionSettings;
export const quickRequest = CompanionCore.quickRequest as (kind: string, text: string, device?: "mac" | "pc") => QuickRequest | null;
export const quickResultClean = CompanionCore.quickResultClean as (kind: string, reply: unknown) => string;
