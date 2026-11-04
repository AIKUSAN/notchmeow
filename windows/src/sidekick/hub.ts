// The one place the island's other modules find the Sidekick (hooks.ts feeds it, the chat asks it, the cards read it). Set once by main.ts. Null while it is not set, and
// every caller treats null as "no sidekick": the island works the same without it. No imports of the island, so nothing here can be a cycle.

import type { Sidekick } from "./controller.ts";

export const Hub: { sk: Sidekick | null } = { sk: null };
