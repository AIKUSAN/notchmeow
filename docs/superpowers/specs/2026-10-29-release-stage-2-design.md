# Sub-project D, stage 2: the 1.0.0 relaunch (Friday 2026-11-13)

**Status:** draft for the owner's review, written 2026-10-29 on `main` at `34ccb799`. **Parent:** `docs/superpowers/specs/2026-10-08-release-prep-design.md` (stage 1: "stage 2 gets its own short design; `release.sh`'s signed mode stays ready for it"). **Date source:** the vault decision "NotchMeow relaunch target 2026-11-13" (owner, 2026-10-22).
Each point below is marked **Decided** (with its source), **Proposed** (my recommendation) or **Owner's question**. Anything I could not check is marked **unverified**. This spec only plans: no one pushes, tags, publishes or changes a setting until the owner says so (`CLAUDE.md`: "Never push").

## 0. A conflict to settle first
- Local facts: tag `v1.0.0` exists at `10046ea0`, which is inside the pushed history (`fda7645b`, the stale `origin/main`). `CHANGELOG.md` already has a `## 1.0.0` section ("The first public release"). Every version field already says 1.0.0 (`scripts/check-versions.sh` passes). `.claude/archive/owner-manual-checks.md` says "1.0.0 published (2026-10-16)": a release with a DMG and zip, Pages live. The vault decision "Public release ships an unnotarized DMG" (2026-10-16) agrees.
- But the 2026-10-22 decision says "the version stays 1.0.0 until then and the repo stays private". These cannot both hold.
- **Unverified:** whether the repo is public today, and whether the 2026-10-16 release is still up. (My one `git ls-remote --heads origin` read answered, which does not tell visibility. I did nothing else on the network.)
- `release.sh` signed mode stops with "tag v1.0.0 already exists here". A second 1.0.0 means deleting a tag people may have downloaded; users with 1.0.0 would see no update.
- **Proposed:** the relaunch is **1.1.0** (build number 11) unless the owner confirms the old release was withdrawn and nobody has it. Everything below says `<V>` for the version. If the answer is "1.0.0 is still public", section 4 changes from "make public" to "check what is already public".

## 1. Mac: signing, notarization, the DMG
- **Decided (vault, 2026-10-16):** no Apple Developer account for now; the public DMG is ad hoc signed, not notarized; D2 is "shelved, not dropped". Users install through Privacy & Security → Open Anyway.
- **Proposed:** keep that for the relaunch. Reasons: two weeks is too short to enroll, buy a certificate and debug a signed pipeline that has never run here (**unverified**: Apple's enrollment time; the signed mode of `release.sh` has no end-to-end run in this repo's history that I could find). Ad hoc has one known cost: each build has a new identity, so the Keychain asks "Always Allow" again after an update. Say so in the release notes.
- **How the files are made (ad hoc):** `bash scripts/release.sh <V> --tester --dmg` on `main` builds the zip, the DMG, their `.sha256` files and `NOTES.txt` in `/tmp/notchmeow-release-<V>/`, and never tags or publishes. The owner publishes by hand with `gh release create` from those files. The notes text built into `release.sh`'s signed mode says "Signed with a Developer ID and notarized by Apple": **do not reuse it** for an ad hoc release.
- **If the owner wants Developer ID anyway (D2).** Needs, none of it in the repo:
  - a paid Apple Developer Program membership and a "Developer ID Application" certificate in the login Keychain (`release.sh` finds it with `security find-identity`; it never reads a name from a file);
  - a notary profile named `notchmeow-notary`, created once by the owner with `xcrun notarytool store-credentials notchmeow-notary` (the app-specific password or API key goes into the Keychain, never into a script, a file or a chat);
  - the DMG step: `make-dmg.sh` refuses any identity but `-` today (`dmg_seal`); D2 adds the Developer ID signature, notarization and `stapler staple` of the image, and `release.sh` drops its `--dmg` refusal for the signed mode.
- **Owner's question:** do you have, or want, a paid Apple Developer account for the relaunch? (Proposed answer: no, stay ad hoc.)

## 2. Windows and Linux artifacts
- **Decided (stage 1 spec, section 3):** built by the existing workflows, run by hand, publishing off. `windows.yml` has `PUBLISH` paused because Defender flags the unsigned NSIS installer; `linux.yml` has a publish gate on `PUBLISH` and `linux-v*` tags; `windows-tests.yml` is read-only and has `workflow_dispatch`; `build.yml` and `release.yml` only build.
- **Proposed:**
  - No Windows signing for the relaunch. The cost of a certificate or a signing service is **unverified**; an unsigned build shows the SmartScreen "unknown publisher" screen (More info → Run anyway), and the installer may trip Defender. Ship the portable build, name the warning in the notes and on the site.
  - Run **Windows** and **Linux** (Actions → Run workflow, on `main`) on 11-11, download the artifacts, check them by hand on the owner's PC (section 5), then attach them to the one GitHub release with `gh release upload`. Keep `PUBLISH` off, so the workflows never write to the repo.
  - Do not push `windows-v*` or `linux-v*` tags (they would also fire the publish paths). One tag, `v<V>`, for everything.
  - Artifacts of a public repo can be downloaded by any signed-in GitHub user, as the workflow comments note: delete the workflow artifacts after the release has its files.
- **Owner's question:** ship Windows unsigned with the SmartScreen warning, or hold Windows until it is signed?

## 3. Version, tags, release notes
- `bash scripts/set-version.sh <V>` then `bash scripts/check-versions.sh <V>`; commit the regenerated `Info.plist`. The App Store variant keeps its own `1.0`. Raise `CFBundleVersion` (set-version does it).
- `CHANGELOG.md`: turn the "Unreleased" list into `## <V>` (release.sh reads that section for the notes). The existing `## 1.0.0` stays as history.
- **Tags.** The repo has 32 tags, most inherited from Coucou (`v0.1.0` to `v0.4.0`, `windows-v0.1.0` to `windows-v0.5.0`, `linux-v0.1.1` to `linux-v0.5.0`, `android-*`, `windows-latest`, `linux-latest`) plus `appstore-1.0-build4` and our `v1.0.0`. Never reuse or move one of those names. Push only by name: `git push origin v<V>`. Never `--tags`, never `--mirror`, never `--all`.
- **Release notes** (written by me, approved by the owner, before the push): what is new (from the changelog), the Mac Open Anyway steps, the Windows SmartScreen step, the Keychain "Always Allow" note, checksums, "no telemetry", and the licence lines (MIT code with Louis Raillé's notice; name, cats, icons and sounds under `LICENSE-ASSETS.md`).

## 4. Making the repo public safely (checklist)
The first push of this work is also its first public exposure. Run in order from the repo root; every command is read-only. A hit stops the line until the owner decides.
1. **Visibility and remotes.** Two remotes exist: `origin` (`AIKUSAN/notchmeow`) and `upstream` (`louis-cfm/coucou`, Coucou's repo). Never push to `upstream`; remove it before the push with `git remote remove upstream` (owner's yes) so a typo cannot reach it. `origin/main` is stale at `fda7645b`; `main` is 372 commits ahead and contains it, so the push is a fast-forward and needs no force. **Unverified:** the repo's current visibility and whether it is still marked as a fork of Coucou. A fork cannot be made private, and "detach fork" is a GitHub support request. The fork link is public attribution and harmless; keep it unless the owner wants it gone.
2. **The two branches with Cloudflare challenge tokens** (`claude/recursing-swartz-574574`, 12 commits not in `main`; `f3a2-0/plan-brains-contract`, 3 commits not in `main`; origin has no copies of them in the list I saw). Check they are not in `main`: `git log --oneline main..claude/recursing-swartz-574574` lists them; `git merge-base --is-ancestor <commit> main` must say no for each. Then, **only with the owner's yes**: `git branch -D claude/recursing-swartz-574574 f3a2-0/plan-brains-contract`, then `git reflog expire --expire=now --all && git gc --prune=now` so the objects are gone from this clone too. A push of `main` and one tag cannot carry them, so the deletion is belt and braces against a later `--all`.
3. **What gets pushed:** `main` and `v<V>`. Nothing else. 145 local branches (all `claude/*`, `a-*`, `b-*`, `d1/*` and so on) and 8 old origin branches (`hold-windows-downloads`, `linux-0.1.2`, `n22-gemini`, `windows`, `windows-0.1.1`, `windows-downloads`, …) stay out; decide separately whether to delete the old origin branches (they are Coucou-era; **unverified** what they hold). Dry run first: `git push --dry-run origin main v<V>`, then read the object count.
4. **Secrets, whole history of `main`:**
   - file names: `git log main --name-only --format= | sort -u | grep -i -E '\.(env|p12|pem|key|keychain|keychain-db|mobileprovision|cer|jks)$|id_rsa|credentials|secrets?\.'`. Known hit: `android/app/src/test/resources/test-desktop.p12`, from Coucou's Android app (commit `e0767fbc`, not in the current tree). Treat as an upstream test fixture; **unverified** that it holds no real key. Confirm with `git show e0767fbc:android/app/src/test/resources/test-desktop.p12 | openssl pkcs12 -info -nokeys -passin pass: 2>&1 | head`.
   - key-like strings: `git log main -p --format='commit %h' | grep -n -E 'AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36}|github_pat_|sk-ant-|sk-[A-Za-z0-9]{32,}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-|-----BEGIN [A-Z ]*PRIVATE KEY|cf_clearance|__cf_chl|Bearer [A-Za-z0-9._-]{20,}'`. Test fixtures with fake keys will show; each hit is read, not trusted.
   - Keychain dumps and logs: `git log main --name-only --format= | sort -u | grep -i -E 'dump-keychain|\.keychain|\.log$|\.sqlite$|\.har$'`.
   - A scanner is better than grep: `command -v gitleaks trufflehog` printed nothing here, so neither is installed (**unverified** elsewhere). Installing one needs the owner's yes; then `gitleaks detect --log-opts=main --redact`.
5. **Personal names and paths:** `git log main -p --format= | grep -n -E '/Users/[A-Za-z0-9._-]+' | grep -v -E '/Users/(Shared|Sam|you|runner|user)'` and the same for `C:\\Users\\`. Add the owner's Mac name and home-folder name by hand to the pattern (I do not write them here). **Known and owed:** commit `e8c28e9` (the G2-mac plan) carries the owner's Mac name in seven lines. It is after `fda7645b`, so it is unpushed, and a history rewrite of the unpushed commits (as was done for G2-0) needs **no force-push**. Do the rewrite on a copy first, check `git range-diff`, keep a mirror backup in the Trash-able scratch folder, then repeat the grep.
   - Authors: `git log main --format='%an <%ae>' | sort | uniq -c | sort -rn` shows the owner under a GitHub noreply address and four upstream contributors (Louis Raillé, Louis, Salomão Davy, Alberto Ruiz) whose addresses are already public in Coucou's history. Keep them: they are the MIT attribution.
6. **Coucou's reserved assets in history.** The current tree is clean by `scripts/check-no-leftovers.sh`, but history is not: `git log main --name-only --format= | sort -u | grep -i -E 'mochi|coucou'` finds `docs/media/coucou.png`, `NotchBuddy/Resources/Coucou*.entitlements`, `windows/src/mochi/*`, and old commits of `NotchBuddy/Resources/sounds/*.wav` from before NotchMeow's own sound pack. `CLAUDE.md` forbids reintroducing these; old commits still publish them. **Unverified:** how the first history rewrite treated this.
   - Options: (a) keep the inherited history (MIT code, attribution intact, reserved art stays in old blobs); (b) `git filter-repo --invert-paths` on those paths and the old sound blobs, which rewrites every hash (including `v1.0.0`) and needs a force-push; (c) a fresh root commit with the MIT notice kept, losing per-commit attribution.
   - **Proposed:** (b) if the repo is not yet public; if it is public, the damage is done and (a) plus a note to the owner. Needs the owner's call, and Coucou's licence terms for the reserved assets (**unverified**; read `LICENSE-ASSETS.md` and upstream's licence file first).
7. **Tree check at the release commit:** `bash scripts/check-no-leftovers.sh`, `bash scripts/check-app-binary.sh <app> release`, `bash scripts/check-site.sh`, and `git ls-files | grep -E '^\.claude|graphify-out'` must print nothing (both are git-ignored locally: `git check-ignore .claude` confirmed).
8. **Switch:** only after steps 1 to 7 are clean and the release files exist: owner pushes (`main`, `v<V>`), creates the release, then flips visibility in Settings → General → Danger Zone. Order matters: GitHub Pages and release downloads from a private repo are not public.

## 5. Real-machine checks, 2026-11-10 (ordered, deduplicated)
Source: `.claude/archive/owner-manual-checks.md` (812 lines; the file is local only). Items already run by the main session with computer use are left out. Sections from 2026-10-04 to 2026-10-16 (E1, cats, G, I, F1, G2, U1) are not re-listed: **Proposed:** the 1.0.0 pass covered them and only the cross-cutting ones below are repeated; the owner may cut or add. Build: the exact artifacts of 11-11 are what get checked, so run this list on them, not on a Debug build. If 11-10 comes first, use a Debug build of `main` for the morning and repeat items 1 to 3 and 22 on the artifacts.

**Mac (morning, about 2 hours):**
1. Open the DMG on a Mac that never had NotchMeow: Open Anyway flow works; app opens; first launch greeting is smooth (60 fps cap).
2. Update over the previous build: the Keychain "Always Allow" prompt appears once and keys still work.
3. Settings: save, change and clear a real key in Keys and in Services (chip turns Saved; a refusal shows "Couldn't save to the Keychain"; old key stays on refusal; cleared key is gone after relaunch).
4. Agents → Install hooks → Confirm & write: dated backup, merge, diff shown, nothing written before the click.
5. Island: "Tuck the island away" (Never, 1 min, restart on click); a card or shelf send keeps it up.
6. Projects: the compact amber waiting count (click behaviour), right-click Pin on a row pill, ⌃⌥P after enabling it, a session row brings its app forward, long session name shows alone (no "Claude C…").
7. Focus awareness with a real Claude Code session in Terminal and in VS Code in front (steps back, dot, note; cleared by the next tool or Stop). Cursor is not installed here: skip.
8. Chat (F3a-mac): Pop out takes keyboard focus, ⌘K, Esc does nothing, ⌘W returns; right-click a conversation (rename, pin, delete), Delete all with Cancel; Explain a copied screenshot; Settings → AI and chat → "What the AI saw last"; Agent level on the Claude plan, asked to edit.
9. No-tools level: select "fetch https://example.com and summarise it" and run Fix: it rewrites and fetches nothing.
10. Claude plan: Stop using it, then chat and File questions show Auto, no row shows both Off and Main.
11. Music/Spotify: real Spotify plays (title on the pill, "artist · Spotify" on the card), the first play/pause click shows the macOS Automation prompt, Allow pauses it; with Automation off the pill shows "Allow NotchMeow to control Spotify". Apple Music wins while it plays.
12. Make main on a running local model (Ollama or LM Studio) moves Chat to it. Release matrix leftovers, if you have time: real Ollama with no keys, going offline mid-session, VoiceOver pass.
13. App Store build is out of scope for the relaunch; skip its card checks.

**Windows PC (afternoon, about 2 hours):**
14. Run the portable build from a user folder with non-ASCII characters (like `C:\Users\Zoé`); SmartScreen and Defender behaviour noted for the release notes.
15. Segoe UI Settings window at 415 px wide: wardrobe tile labels and the "Coming with the new chat" chip fit; tile grid at least 104 px.
16. Launch with Devices stored and Visible on: no incoming pairing until the Settings window is shown; launch with AI and chat stored: no `claude` spawn until shown.
17. Chat: Pop out opens under WebView2 with the conversation, takes focus, closes back; paste a real PNG into the field attaches; Delete all in Settings with the pop-out open clears it too.
18. Focus awareness with VS Code's terminal and Windows Terminal in front (step back, dot, "Waiting in VS Code"); File Explorer in front gives the normal card. Projects: Windows Terminal and the Claude desktop app each make a project.
19. "Launch at startup" off: the save succeeds. Keys: save, change, clear; a refused save keeps the old key.
20. No-tools level: Fix on the fetch sentence rewrites and fetches nothing; a refused run stops the `claude` process promptly (compile-checked only so far).
21. Windows CI is already green at `fda7645b`; re-run `windows-tests.yml` by hand on the release commit.
22. Send a file to the Mac (Devices → Visible, pair, Accept): quick end-to-end.

**Linux:** I found no record of an owner Linux machine (**unverified**). **Proposed:** ship the AppImage/deb/rpm from CI with "tested in CI and in Docker only" in the notes; items for X11 (WM_CLASS hosts), no-Secret-Service ("Couldn't read", Save off) and Wayland (card always shows) stay on a "known untested" line.

## 6. Day by day
- **Mon 11-09 (outside this spec):** cat-reactions pictures for the site and README.
- **Tue 11-10:** feature freeze on `main` (only fixes). Morning Mac checks, afternoon Windows checks. In parallel, the main session runs section 4 steps 3 to 7 (read-only) and reports. Evening: fix list.
- **Wed 11-11:** fixes only. Then, from a clean `main`: `set-version.sh <V>`, changelog section, commit (owner's yes to commit); `release.sh <V> --tester --dmg`; run Windows and Linux workflows by hand; download artifacts; repeat checks 1, 2 and 14 on the real artifacts; verify checksums (`shasum -a 256 -c`).
- **Thu 11-12:** owner reads the release notes, the site and the README; section 4 final run; owner answers the history and branch questions; rewrite or deletion done, grep repeated; `git push --dry-run`. **Go/no-go at the end of the day** by the owner.
- **Fri 11-13:** the owner pushes `main` and `v<V>`, creates the release with the files (`gh release create`), checks Pages, flips visibility if still private, downloads the public files and compares checksums. Delete the workflow artifacts. Update the vault and `owner-manual-checks.md`.
- **Fallbacks (Proposed):**
  - A Mac check fails and is a crash, lost data, broken hooks or a Keychain loss: stop; the date slips day by day (ship Monday 11-16 at the latest) rather than ship it.
  - A Mac check fails on polish only: ship, list it as a known issue, fix in the next point release.
  - The Windows check fails: ship Mac and Linux, mark Windows "coming" on the site and in the notes.
  - Section 4 finds a secret or a reserved asset: the repo stays private, the release waits; the Mac files can go to testers as 0.9.x-style private files meanwhile.
  - The chat slipped earlier: the vault's fallback stands (merged chat only; memory and the rest are 1.1).

## 7. Site (`docs/`, Pages) and README at the relaunch
- `docs/index.html` today says "Tester builds by invitation" and "The public release: Coming: 1.0.0". Change to: a Download section with three buttons (Mac `.dmg` and `.zip`, Windows, Linux), the Open Anyway steps for the Mac, the SmartScreen steps for Windows, the Keychain note, the checksums, and "no telemetry, no account". Link the exact asset URLs of `v<V>` (the windows workflow comment warns that `releases/latest` can point at another release).
- `docs/testers.html`: Proposed: keep it as "Older builds" or replace its content with a redirect to the Download section; do not delete the page while old links exist.
- The 11-09 pictures: `bash scripts/render-site.sh`; if the cat engine or `shared/theme.json` changed, `npx --no-install vite build --config vite.site.config.ts` in `windows/` (never `npm run build`) and commit `docs/assets/cats.js` and `cats.css`. Then `bash scripts/check-site.sh` (stale bundle, any outside request).
- `README.md`: remove the "Work in progress... tester builds are by invitation" banner; add the download links and the same install notes; keep the fork credit to Coucou and the MIT notice; its "Features (inherited from Coucou)" heading should say what is NotchMeow's now (**Proposed**, owner's wording).
- Metadata and accessibility audit of the site only (`fixing-metadata`, `fixing-accessibility`, audit not restyle); the never-restyle rule holds.
- `CHANGELOG.md` and the release notes carry the same install text, so the three places do not drift.

## Owner's questions
1. Is the 2026-10-16 `v1.0.0` release still up, and is the repo public today? It decides between "1.1.0 and a normal update", "delete and redo 1.0.0" and "nothing to make public".
2. Keep the inherited history (it holds Coucou-era `coucou.png`, `mochi/`, old sounds and entitlements) or rewrite it before the repo goes public? A rewrite changes every hash and needs a force-push; leaving it risks Coucou's reserved assets staying public.
3. Do you have, or want, a paid Apple Developer account before 11-13? Without it the Mac stays ad hoc with Open Anyway and a Keychain prompt on each update.
4. May I delete the two Cloudflare-token branches, and rewrite `e8c28e9` (your Mac name) in the unpushed commits? Both must happen before any push; the rewrite is local and needs no force-push.
5. Windows: ship unsigned with the SmartScreen and possible Defender warning, or hold Windows if its check or Defender fails on 11-10?
6. If a Mac check fails on 11-10, do you prefer slipping the date to 11-16 or shipping the other platforms first?

## Owner's answers, 2026-10-29

- **History: rewrite it** before going public. Purge the Coucou-era files (`coucou.png`, `windows/src/mochi/*`, the old sounds and entitlements), the owner's Mac name (`e8c28e9`) and the Cloudflare-token branches' content from every commit. Every hash changes, so the rewrite is done once, last, after every 1.0 branch has merged (main session, about 11-11), and the owner runs the force-push. Open item: GitHub's fork network can keep old commits reachable by SHA after a force-push; a full purge may need the repository detached from the fork network (or GitHub Support) — checked before 11-11.
- **Mac signing: ad hoc, as the 10-16 build.** No Apple Developer account for the relaunch; the testers page and release notes keep the Open Anyway and Keychain steps.
- **Fallback: ship the rest, hold the failing one.** A platform whose 11-10 check fails is held and follows when fixed; unsigned Windows ships with its SmartScreen and Defender warning explained.
- **Version: redo 1.0.0** (owner, 2026-10-29), on four conditions:
  1. The owner deletes the 2026-10-16 v1.0.0 release and tag on GitHub before the new one is published; after the rewrite the old tag would point at commits that no longer exist.
  2. The build number goes above the 10-16 DMG's build 10, so an installed 1.0.0 is replaced cleanly.
  3. Only if the old release's download count shows a handful of testers at most; otherwise the relaunch ships as 1.1.0.
  4. The release notes say "1.0.0 (relaunch), replaces the 2026-10-16 preview".
  This supersedes section 0's 1.1.0 proposal.
