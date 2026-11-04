// What the show gate asks of the island, read from the app's state (sub-project F1, spec "The show gate" and "Where it shows"). A note shows only in a quiet moment: no approval or
// question in front, nothing the user is in the middle of. The island is "in the middle of something" when it is open on any view but the overview, the empty one and the cards of a
// finished task (a note waits for the gate; it never opens over the user's other work). Pure: the parts of the state it reads are a parameter. Loaded by the plain-Node checks.

import type { World } from "./notes.ts";

/** The views a note may replace: the island is open on them only to be looked at, never to be worked in. */
export const QUIET_VIEWS: ReadonlySet<string> = new Set(["overview", "empty", "finished", "sidekick"]);

/** The part of the app's state that the gate reads. */
export interface WorldState {
  mode: string;
  view: string;
  pendingApproval: unknown | null;
  chatApprovals: { length: number };
  tasks: readonly { state: string }[];
  /** The ID of the note the Sidekick's view shows, or null. */
  sidekickNoteId: number | null;
}

/** The island's side of the gate. `away` is the Sidekick's own and is not here. The parts are read when asked, never kept. */
export function worldOf(read: () => WorldState): Omit<World, "away"> {
  return {
    ratelimit: () => read().tasks.some((t) => t.state === "ratelimit"),
    card: () => {
      const s = read();
      return s.pendingApproval !== null || s.chatApprovals.length > 0 ? "approval" : s.mode === "expanded" && s.view === "question" ? "question" : null;
    },
    ownCard: () => {
      const s = read();
      return s.mode === "expanded" && s.view === "approval" && s.pendingApproval !== null;
    },
    typing: () => {
      const s = read();
      return s.mode === "expanded" && !QUIET_VIEWS.has(s.view);
    },
    onScreen: (id) => {
      const s = read();
      return s.mode === "expanded" && s.view === "sidekick" && s.sidekickNoteId === id;
    },
  };
}
