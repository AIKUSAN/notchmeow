// Which failures of `ingest_file` are the app refusing a file, and which are not.
//
// Rust decides (files::ingest calls attachments::screen: an app, an archive, a disk image, a video, or anything over 25 MB is
// `Classified::Rejected`) and reports it as a text, `attachments::reject_message`. The island only receives that text, so it
// recognises the two. A test (scripts/cat-tests/refusal.test.mjs) pins them to the Rust source.
// Imports nothing, so the plain-Node checks (npm run check:cat) can load it as it is.

/** The two texts Rust gives for a refused file: too big, or a kind of file the cat can't read. */
export const REFUSAL_NOTES: readonly string[] = ["Files over 25 MB are too big for me.", "I can't read this kind of file."];

/**
 * The note to show for a failed ingest, and whether it is a refusal. A refusal is caught, gagged on and coughed back up as a hairball
 * before the note; any other failure (a folder, an unreadable file, a failed copy) shows the note at once.
 */
export function classifyIngestError(err: unknown): { message: string; refused: boolean } {
  const message = String(err).replace(/^Error:\s*/, "");
  return { message, refused: REFUSAL_NOTES.includes(message) };
}

/**
 * The sound that goes with the note of a failed ingest. The note of a refusal is silent: the cat has already played `annoyed` once,
 * as it started to gag (`BotEngine.catchReject`), and sound Stage 3 adds the `pop` at the cough in the engine, not here. Any other
 * failure keeps today's `error` with its note.
 */
export function noteSound(refused: boolean): "error" | null {
  return refused ? null : "error";
}
