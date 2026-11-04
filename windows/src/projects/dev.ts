// The dev server's Projects scenarios (`window.__nm.projects` in main.ts): a scenario's steps go through the same hook path as the relay's events, all at once;
// `age` moves the clock. Dev only: the import is behind import.meta.env.DEV in main.ts, so a release build never holds it.

import { PROJECT_SCENARIOS } from "./scenarios.ts";

export interface ProjectScenarios {
  run(name: string): void;
  age(minutes: number): void;
  names: string[];
}

/** `hook` takes one hook payload (the island's handleHook); `age` takes milliseconds and moves the clock. */
export function projectScenarios(hook: (p: Record<string, unknown>) => void, age: (ms: number) => void): ProjectScenarios {
  return {
    names: Object.keys(PROJECT_SCENARIOS),
    run(name) {
      const s = PROJECT_SCENARIOS[name];
      if (!s) throw new Error(`no Projects scenario named ${name}`);
      for (const step of s.steps) hook({ ...step.payload });
    },
    age(minutes) {
      age(minutes * 60_000);
    },
  };
}
