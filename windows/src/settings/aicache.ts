// The AI section's cache on Windows and Linux: the Claude status, the model servers, and each cloud provider's live model list, refreshed when the Settings window opens.
// Moved from main.ts's aiSection (refresh, loadCloud, refreshOnOpen). Pure of the DOM: it talks to the backend through AiBackend and reads the clock through `now`.
// Tests: windows/scripts/settings-tests/aicache.test.mjs (check:settings).

import type { AiServer, ModelInfo } from "../core/bridge.ts";
import type { ClaudeStatus } from "../core/claude.ts";

/** The note a failed server look-up leaves in the Local models card (a discovery that rejects or answers nothing); a list, even an empty one, leaves none. */
const DISCOVERY_FAILED = "Couldn't look for servers.";
/** The text the Local models card shows after a server look-up: the failure's note when the look-up gave no answer; otherwise the card's `shown` text, kept, unless it is
 * that same failure note (a later answer takes it away). Any other message the card shows stays. */
export function discoveryMsg(found: readonly AiServer[] | undefined, shown: string | null): string | null {
  if (found === undefined) return DISCOVERY_FAILED;
  return shown === DISCOVERY_FAILED ? null : shown;
}

/** A cloud model list older than this is fetched again when the window opens. */
export const MODEL_LIST_MAX_AGE_MS = 10 * 60 * 1000;
/** No refresh starts within this long of the last one's end (the window's focus and visibility events arrive together). */
export const REFRESH_GAP_MS = 1000;

export interface AiBackend {
  aiDiscover(): Promise<AiServer[] | undefined>;
  /** A provider's live models. For a cloud provider it is also the key check: it throws when the check fails. */
  aiListModels(provider: string): Promise<ModelInfo[]>;
  claudeStatus(): Promise<ClaudeStatus | undefined>;
}

export class AiCache {
  servers: AiServer[] = [];
  models: Record<string, ModelInfo[]> = {};
  claude: ClaudeStatus | null = null;
  /** True once a Claude status read has finished, whatever it said: a null `claude` after that is "couldn't check", before it is "checking". */
  claudeRead = false;
  /** The last check's result per cloud provider: "✓" when it worked, else the error's text. */
  works: Record<string, { ok: boolean; text: string } | undefined> = {};
  private loadedAt: Record<string, number> = {};
  /** Bumped by `forget`: a load that started under an older number is superseded. */
  private gen: Record<string, number> = {};
  private running = false;
  private lastEnd = Number.NEGATIVE_INFINITY;
  private readonly backend: AiBackend;
  private readonly providers: readonly { id: string; key: string }[];
  private readonly present: (key: string) => boolean;
  private readonly now: () => number;

  constructor(backend: AiBackend, providers: readonly { id: string; key: string }[], present: (key: string) => boolean, now: () => number = () => Date.now()) {
    this.backend = backend;
    this.providers = providers;
    this.present = present;
    this.now = now;
  }

  /** The provider's live models. A failure keeps the list held (a failed read is not an empty one) and records the failure in `works`; the list stays stale, so the next open tries
   * again. A check that was in flight when `forget` ran lands nowhere (its generation is old): it returns false. */
  async loadCloud(id: string): Promise<boolean> {
    const gen = this.gen[id] ?? 0;
    const current = (): boolean => (this.gen[id] ?? 0) === gen;
    try {
      const list = await this.backend.aiListModels(id);
      if (!current()) return false;
      this.models[id] = list;
      this.loadedAt[id] = this.now();
      this.works[id] = { ok: true, text: "✓" };
      return true;
    } catch (err) {
      if (!current()) return false;
      this.works[id] = { ok: false, text: String(err).replace(/^Error:\s*/, "") };
      return false;
    }
  }

  /** Forgets a provider's list and check, and any load still in flight for it. */
  forget(id: string): void {
    this.gen[id] = (this.gen[id] ?? 0) + 1;
    delete this.models[id];
    delete this.works[id];
  }

  /** Claude Code's status, then the servers, then each provider whose key is saved and whose list is missing or older than ten minutes. False when skipped. */
  async refreshOnOpen(): Promise<boolean> {
    if (this.running || this.now() - this.lastEnd < REFRESH_GAP_MS) return false;
    this.running = true;
    try {
      // A rejected read is no status, and it still counts as read: the row then says it could not check, and the rest of the refresh runs.
      try {
        this.claude = (await this.backend.claudeStatus()) ?? null;
      } catch {
        this.claude = null;
      }
      this.claudeRead = true;
      // A discovery that rejects or answers nothing keeps the list held: a failed read is not an empty one.
      let found: AiServer[] | undefined;
      try {
        found = await this.backend.aiDiscover();
      } catch {
        found = undefined;
      }
      if (found !== undefined) this.servers = found;
      const stale = (id: string) => !this.models[id] || this.now() - (this.loadedAt[id] ?? 0) > MODEL_LIST_MAX_AGE_MS;
      await Promise.all(this.providers.filter((p) => this.present(p.key) && stale(p.id)).map((p) => this.loadCloud(p.id)));
      return true;
    } finally {
      this.running = false;
      this.lastEnd = this.now();
    }
  }

  /** The servers the backend sent again: true when they differ from the ones held (a list equal to them changes nothing). */
  setServers(next: AiServer[]): boolean {
    if (JSON.stringify(next) === JSON.stringify(this.servers)) return false;
    this.servers = next;
    return true;
  }
}
