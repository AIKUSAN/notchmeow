import test from "node:test";
import assert from "node:assert/strict";
import { State } from "../../src/core/state.ts";

// State's Projects frame (State.projectsNow, sub-project P): the cat block, the layout and the counted-but-not-alerting rule, read through the app's own State.
// The state is the module's one singleton, so each test sets what it reads and nothing else.

test("State.projectsNow: a stored project cat shows, an unstored project wears a cat that is not the Main cat", () => {
  State.settings.cat = { ...State.settings.cat, character: "momo", projectCats: { app: "oreo" } };
  State.settings.activeIntegrations = [];
  State.tasks = [];
  State.projects.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:/dev/app" });
  State.projects.hook({ hook_event_name: "UserPromptSubmit", session_id: "b", cwd: "C:/dev/other" });
  const f = State.projectsNow();
  assert.equal(f.layout, "projects", "Claude only: the projects layout");
  assert.equal(f.usesProjects, true, "a live project, the Claude pill focused, no Two cats");
  const app = f.view.projects.find((p) => p.catKey === "app");
  const other = f.view.projects.find((p) => p.catKey === "other");
  assert.equal(app.cat, "oreo", "the stored cat shows");
  assert.notEqual(other.cat, "momo", "an unstored project does not wear the Main cat");
});

test("State.projectsNow: a feed counts a waiting session and never alerts (attentionNeeded, the pending card and the tasks do not move)", () => {
  State.settings.cat = { ...State.settings.cat, character: "momo", projectCats: {} };
  State.tasks = [];
  State.pendingApproval = null;
  const before = JSON.stringify(State.tasks);
  State.projects.hook({ hook_event_name: "PermissionRequest", session_id: "s", cwd: "C:/dev/app", nm_agent: "claude-desktop", tool_name: "Bash" });
  assert.equal(State.attentionNeeded, false, "a counted wait is no alert");
  assert.equal(State.pendingApproval, null, "the notch's approval card is not opened");
  assert.equal(JSON.stringify(State.tasks), before, "the pills are not touched");
  assert.equal(State.projectsNow().view.waiting, 1, "the count shows the wait");
});
