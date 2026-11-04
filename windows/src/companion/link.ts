// The island's side of the chat (sub-project F3a-tauri, Task 5): what the chat asks of the island, behind one interface, so views/chat.ts does not reach
// into island/hooks. The approval card of Claude Code's steps (E3, Agent level) is the island's own queue: only a click answers it.

import { State } from "../core/state.ts";
import type { WaitingApproval } from "../core/claude.ts";
import { decideChatApproval, releaseChatApprovals } from "../island/hooks.ts";
import type { TurnContext } from "./turn.ts";

export { windowLink } from "./windowlink.ts";

export interface ChatLink {
  context(): TurnContext;
  approval(): WaitingApproval | null;
  decide(d: "allow" | "deny", requestId: string): void;
  release(sessionId?: string): void;
  session(id: string, retired: string | null): void;
  /** Drops a Claude Code session from the chat's sessions (a quick action's, once it is over). */
  forget(id: string): void;
}

/** The link of the running island: its State and its hooks. */
export function islandLink(): ChatLink {
  return {
    context: () => State.contextNow(),
    approval: () => State.chatApprovals.front,
    decide: (d, requestId) => decideChatApproval(d, requestId),
    release: (sessionId) => releaseChatApprovals(sessionId),
    // The chat learns its Claude Code session before anything runs: its hook events are the chat's. A retired id is let go with its approvals.
    session: (id, retired) => {
      State.claudeSessions.add(id);
      if (retired) {
        State.claudeSessions.delete(retired);
        releaseChatApprovals(retired);
      }
    },
    forget: (id) => {
      State.claudeSessions.delete(id);
    },
  };
}
