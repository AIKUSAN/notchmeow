// Plain-Node checks for the parts of the chat UI that hold logic: no DOM, no framework.
// Needs Node 22.6 or newer, which can read the TypeScript source directly:
//
//   cd windows && npm run check:ai
import assert from "node:assert/strict";
import { featureFor, forgetDrop, keyCheckFailure, stillBusy } from "../src/core/feature.ts";

const FILE = "C:\\Users\\Zoé\\AppData\\Local\\NotchMeow\\inbox\\notes.txt";
// A conversation as the chat view keeps it: a user message carries the files it was sent with.
const user = (attachments = []) => ({ role: "user", content: "…", attachments });
const reply = () => ({ role: "assistant", content: "…" });

// No file anywhere in the conversation: Chat.
assert.equal(featureFor([], []), "chat");
assert.equal(featureFor([], [user(), reply(), user(), reply()]), "chat");
console.log("✓ a conversation with no file uses Chat");

// The message that carries a file: File questions.
assert.equal(featureFor([FILE], []), "files");
assert.equal(featureFor([FILE], [user(), reply()]), "files");
console.log("✓ a message that carries a file uses File questions");

// Every later message too: the file's text is still in the history.
const afterTheFile = [user([FILE]), reply()];
assert.equal(featureFor([], afterTheFile), "files");
assert.equal(featureFor([], [...afterTheFile, user(), reply()]), "files");
console.log("✓ a file only on an earlier message still uses File questions");

// A drop or a new chat empties State.chatHistory, and the rule starts over. The decision reads only the
// messages it is given, never State.droppedFile, which is never cleared.
let history = [user([FILE]), reply()];
assert.equal(featureFor([], history), "files");
history = [];
assert.equal(featureFor([], history), "chat");
console.log("✓ after the conversation is reset, a message uses Chat again");

// A drop the file layer rejects leaves no chip behind: the chat row reads State.droppedFile.
const afterRejectedDrop = {
  droppedFile: { name: "notes.heic", path: "/x/notes.heic" },
  promptContext: { kind: "file", name: "notes.heic", path: "/x/notes.heic" },
  pendingAttachment: null,
  dropReader: "Claude",
  other: 1,
};
forgetDrop(afterRejectedDrop);
assert.equal(afterRejectedDrop.droppedFile, null);
assert.equal(afterRejectedDrop.promptContext, null);
assert.equal(afterRejectedDrop.pendingAttachment, null);
assert.equal(afterRejectedDrop.dropReader, null);
assert.equal(afterRejectedDrop.other, 1);
console.log("✓ a rejected drop clears its file chip");

// After the automatic retries run out, the countdown note becomes a plain "try again" with the same name.
assert.equal(stillBusy("Claude is busy. Trying again in 20 s."), "Claude is still busy. Try again in a moment.");
assert.equal(stillBusy("OpenAI is busy. Trying again in 2 s."), "OpenAI is still busy. Try again in a moment.");
assert.ok(!/\d+ s\b|Trying again/.test(stillBusy("Google is busy. Trying again in 5 s.")));
console.log("✓ a busy note that has run out of retries names the provider and has no countdown");

// The key check: only a refused key gets the red mark. Offline and unreachable show the offline line, plain.
assert.deepEqual(keyCheckFailure("Error: Your Claude key was rejected."), { text: "Your Claude key was rejected.", rejected: true });
// Google answers a bad key with HTTP 400; Rust words that like any refused key, so it gets the red mark.
assert.deepEqual(keyCheckFailure("Your Google key was rejected."), { text: "Your Google key was rejected.", rejected: true });
assert.deepEqual(keyCheckFailure("Your OpenAI key is missing."), { text: "Your OpenAI key is missing.", rejected: true });
assert.deepEqual(keyCheckFailure("Couldn't reach OpenAI. Check your connection."), {
  text: "Couldn't reach OpenAI. Check your connection.",
  rejected: false,
});
assert.equal(keyCheckFailure("OpenAI had a problem. Try again in a moment.").rejected, false);
assert.equal(keyCheckFailure("Your OpenAI credit ran out.").rejected, false);
console.log("✓ offline never shows the rejected mark; only a refused key does");

console.log("\nAll AI UI checks passed");
