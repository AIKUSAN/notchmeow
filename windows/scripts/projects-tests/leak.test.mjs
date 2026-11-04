import test from "node:test";
import assert from "node:assert/strict";
import { ProjectsModel } from "../../src/projects/model.ts";
import { badgeTitle, bigStepLine, hostWord, projectsWord, rowDetail } from "../../src/projects/present.ts";
import { defaultCatBlock, withProjectCat } from "../../src/cat/display.ts";

// The privacy pin of the Projects model (P-tauri, Task 4): a session's path, prompt, command, query, transcript, message, words and terminal never reach a view, a
// word, a settings value or a log. Each marker is in a field the model reads or ignores; none of them may come back out. The texts are taken after EACH feed, so a
// value a later event overwrites is still caught.

const T = 1_760_000_000_000;
const MARKERS = ["LEAK-DIR-p7", "LEAK-PROMPT-p7", "LEAK-CMD-p7", "LEAK-QUERY-p7", "LEAK-TRANSCRIPT-p7", "LEAK-MSG-p7", "LEAK-WORDS-p7", "LEAK-TERM-p7"];
const CWD = "C:\\LEAK-DIR-p7\\Code\\app";
const IN = { projectCats: {}, mainCat: "shrimpy", activePills: ["integration_claude"], open: false, focusId: "integration_claude", twoCats: false };

test("nothing a view, a word, a settings value or a log holds carries a session's path, prompt, command, query, transcript, message, words or terminal", () => {
  const logged = [];
  const names = ["log", "info", "warn", "error", "debug"];
  const saved = names.map((k) => [k, console[k]]);
  for (const k of names) console[k] = (...a) => logged.push(a.map(String).join(" "));
  try {
    const w = { t: T };
    const m = new ProjectsModel({ home: "/home/dev", now: () => w.t });
    const texts = [];
    const words = [];
    // Every text the island could draw from the registry at this moment, and the step and label words (which hold a basename, never a path).
    const take = () => {
      const view = m.frame(IN).view;
      texts.push(JSON.stringify(view), JSON.stringify(m.liveProjects(view)));
      for (const key of m.liveProjects(view)) texts.push(JSON.stringify(withProjectCat(defaultCatBlock(), key.catKey, "oreo")));
      texts.push(projectsWord(view.projects.length), badgeTitle(view.waiting));
      for (const p of view.projects) {
        texts.push(bigStepLine(p));
        words.push(p.name, p.step);
        for (const s of p.sessions) { texts.push(rowDetail(s.note, s.step), hostWord(s.host)); words.push(s.label, s.step); }
      }
      return view;
    };
    const feed = (payload, at) => { w.t = T + at; m.hook(payload); take(); };
    feed({ hook_event_name: "Stop", session_id: "p7-b", cwd: CWD, last_assistant_message: "LEAK-WORDS-p7" }, 0);
    feed({ hook_event_name: "SessionStart", session_id: "p7-a", cwd: CWD, term_program: "LEAK-TERM-p7", transcript_path: "C:\\LEAK-TRANSCRIPT-p7\\t.jsonl" }, 1000);
    feed({ hook_event_name: "UserPromptSubmit", session_id: "p7-a", cwd: CWD, prompt: "LEAK-PROMPT-p7" }, 2000);
    feed({ hook_event_name: "Notification", session_id: "p7-a", cwd: CWD, message: "LEAK-MSG-p7" }, 3000);
    feed({ hook_event_name: "PreToolUse", session_id: "p7-a", cwd: CWD, tool_name: "WebSearch", tool_input: { query: "LEAK-QUERY-p7" } }, 4000);
    feed({ hook_event_name: "PreToolUse", session_id: "p7-c", cwd: CWD, tool_name: "Read", tool_input: { file_path: "C:\\LEAK-DIR-p7\\Code\\app\\secret.ts" } }, 4500);
    feed({ hook_event_name: "PreToolUse", session_id: "p7-c", cwd: CWD, tool_name: "Grep", tool_input: { path: "C:\\LEAK-DIR-p7\\Code\\app\\src\\other.ts", pattern: "x" } }, 4600);
    feed({ hook_event_name: "PreToolUse", session_id: "p7-a", cwd: CWD, tool_name: "Bash", tool_input: { command: "LEAK-CMD-p7" } }, 5000);

    const view = take();
    assert.equal(view.projects.length, 1, "the markers' project is in the view");
    assert.equal(view.projects[0].name, "app");
    assert.equal(view.projects[0].step, "Runs");
    texts.push(logged.join("\n"));

    for (const text of texts) {
      for (const mk of MARKERS) assert.ok(!text.includes(mk), `${mk} leaked into ${text.slice(0, 80)}`);
      assert.ok(!text.includes("C:\\"), "no Windows path");
      assert.ok(!text.includes("C:/"), "no Windows path");
    }
    for (const word of words) {
      assert.doesNotMatch(word, /[\/\\]/, `a separator in a step or label: ${word}`);
      for (const mk of MARKERS) assert.ok(!word.includes(mk), `${mk} in a step or label`);
    }
  } finally {
    for (const [k, fn] of saved) console[k] = fn;
  }
});
