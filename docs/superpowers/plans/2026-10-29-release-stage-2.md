# Release stage 2, the 1.0.0 relaunch: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to run this plan task by task. Steps use checkboxes (`- [ ]`) for tracking. Every task says **who** runs it. Nothing here pushes, tags, publishes or changes a GitHub setting unless the task's who is **owner**.

**Goal:** ship NotchMeow `<V>` (1.0.0 relaunch by default, 1.1.0 if condition 3 fails) on Friday 2026-11-13: Mac ad hoc DMG and zip, Windows portable, Linux AppImage/deb/rpm, one GitHub release, the site and README updated, after a single history rewrite that purges the Coucou-era files.

**Architecture:** freeze → the owner's checks on 11-10 → fixes, the version bump and the CHANGELOG land on `main` → one `git filter-branch` rewrite in a fresh clone, verified there → the owner force-pushes `main` from that clone → all three platforms are built from that one commit, which becomes the tag commit → re-checks, go/no-go → on 11-13 the owner deletes the old release, tags and branches, then publishes. The site and README Download commit goes on top, pushed last.

**Tech Stack:** git 2.54 built-ins only (`filter-branch`, `cat-file`, `rev-list`, `format-patch`, `bundle`), `scripts/set-version.sh`, `scripts/check-versions.sh`, `scripts/release.sh --tester --dmg`, `scripts/make-dmg.sh`, `scripts/check-app-binary.sh`, `scripts/check-site.sh`, `scripts/check-no-leftovers.sh`, GitHub Actions `windows.yml`, `linux.yml`, `windows-tests.yml` (run by hand), `gh` (owner only).

**Spec:** `docs/superpowers/specs/2026-10-29-release-stage-2-design.md`. Its "Owner's answers, 2026-10-29" override section 0 and the spec's schedule where they conflict. Parent: `docs/superpowers/specs/2026-10-08-release-prep-design.md`.

## Global Constraints

- The **owner** runs everything on GitHub: deleting the release, tags and branches, the force-push, every other push, the workflows, `gh release`, the visibility switch, and every read of GitHub (`gh`, `git ls-remote`, `git fetch origin`). The main session commits only after the owner says yes (`CLAUDE.md`).
- Push by name only: `main` and `v<V>`. Never `--tags`, `--mirror` or `--all`, and never push to `upstream`.
- The history is rewritten **once**, with `git filter-branch` (git's own tool; no `filter-repo`, BFG, gitleaks or other new installs). It runs after every 1.0 branch has merged. Fixes after it are ordinary fast-forward commits.
- The Mac is signed ad hoc and not notarized. There is no Developer ID, and `make-dmg.sh` keeps `NM_DMG_IDENTITY=-`.
- `PUBLISH` stays `'false'` in `windows.yml` and `linux.yml`. No `windows-v*` or `linux-v*` tag is pushed. The one tag is `v<V>`.
- If V = 1.0.0, the build number is **11 or more** (the 2026-10-16 DMG is build 10), and the notes say: "1.0.0 (relaunch), replaces the 2026-10-16 preview".
- No tracked file, commit message, release note or chat message may hold the owner's Mac name, host name, home path or a Cloudflare token. They live only in `$W/private-patterns.txt` (0600), and nothing prints them.
- Bundle IDs, pill IDs, cat IDs and the identity strings stay as they are. The MIT notice with Louis Raillé's name, and the Coucou credit, stay in README and LICENSE. The four upstream authors stay in history.
- Models: Haiku 5.5 first. `nm-implementer-light` (Haiku, medium) writes docs, `nm-reviewer` (Haiku, high) reviews them, and no Sonnet trigger applies. Never restyle the app. On the site only the Download content changes, and the audit (`fixing-metadata`, `fixing-accessibility`) reports problems and changes nothing.
- Shared variables, set once in every shell that runs a step:
  ```bash
  REPO="$(git rev-parse --show-toplevel)"     # run from the repo root
  W="$HOME/nm-rewrite"                         # outside the repo and outside any skills folder; kept until after the release
  V=1.0.0                                      # or 1.1.0 (Task 1)
  CF='__cf_chl_(f_)?tk=[A-Za-z0-9._-]{8,}|_cf_chl_opt *='   # token-shaped only: this line and the spec do not match it
  ```

## Rulings made while planning (the owner may overturn any)

1. **"A handful of downloads" means 10 or fewer across all v1.0.0 assets.** The main session's 2 downloads on 10-17 count. With 11 or more, V = 1.1.0.
2. **The old `v1.0.0` tag and release are deleted whatever V is.** They pin the history that the rewrite purges. They are deleted on 11-13 (Task 15, step 1), so a download stays up until then. The owner's rewrite answer overrides the spec's "never reuse or move one of those names" for deletion: every inherited tag and the six old origin branches are deleted, not rewritten (no `--tag-name-filter`).
3. **The force-push of `main` happens on 11-11, not 11-13.** `workflow_dispatch` only builds refs that exist on GitHub, and `origin/main` is 373 commits behind (`fda7645b`). The tag is pushed on 11-13.
4. **What gets purged**, from every commit of `main`:
   - these paths: `docs/media/`, `design/captures/`, `design/animations/`, `windows/screenshots/`, `windows/src/mochi/`, `NotchBuddy/Resources/Coucou.entitlements`, `NotchBuddy/Resources/CoucouAppStore.entitlements`, `design/prototype/notch-buddy.html`;
   - every art blob (`png icns ico gif mp4 mov wav mp3 aif aiff caf svg jpg jpeg webp`) in the ancestry of the rebrand commit `f96e7f31^`, unless that blob is in today's tree. This removes Coucou's sounds and icons at paths NotchMeow still uses.
   - `design/animations/` is my addition: it holds Mochi's animation prototypes. Coucou's MIT code and its `docs/*.html` legal pages stay.
5. **The Mac name and the tokens are already local-only.** Checked 2026-10-29: 0 hits in every object reachable from `main`, from every local branch except the two token branches, and from all 7 `origin/*` refs. `e8c28e9` survives only in reflogs, and the tokens only in `claude/recursing-swartz-574574` (6) and `f3a2-0/plan-brains-contract` (1). Their purge is: delete the branches, expire the reflog, gc, and push only from the fresh clone.
6. **Windows ships the portable pair**, re-zipped as `NotchMeow-<V>-windows-portable.zip` with a `.sha256`. Defender flags the setup `.exe`, so it is not attached.
7. **CHANGELOG headings:** the new section is `## <V> (relaunch) — 2026-11-13` (or `## 1.1.0 — 2026-11-13`), on top. The old one becomes `## 1.0.0 preview — 2026-10-16`. `release.sh` reads the first heading that starts with `## <V> `, which is the new one.

## Review Focus

1. **A ref left on GitHub pins the old history**, such as a branch, an inherited tag, the old release or `refs/pull/*`, and the purge silently fails. Pinned in Task 15, step 1: `git ls-remote origin` ends with only `HEAD` and `refs/heads/main` (plus `refs/pull/*`, see Task 2).
2. **The tag commit differs from the build commit**, so the checksums or the notes describe the wrong code. Pinned in Task 13, step 6: the tag commit, the `Commit:` line of `NOTES.txt` and the head SHA of both workflow runs are the same commit.
3. **The build number is not above 10**, so the relaunch DMG does not replace the 10-16 install cleanly. Pinned in Task 8, step 3 and Task 13, step 5: `CFBundleVersion` is at least 11 in `project.yml`, in `Info.plist` and in the DMG's app.
4. **A Download link returns 404**: the asset names on the site or README differ from the uploaded ones, or the site went live before the release existed. Pinned in Task 15, step 6: every URL returns 200 after the publish, and the site commit is pushed only after the release has its files.
5. **A private string reaches GitHub in a commit made after the rewrite**, through a fix, the notes, this plan or a fixture. Pinned in Task 10, step 2 and Task 15, step 2: the full object scan runs again right before each push.

---

### Task 1: GitHub facts and the version decision

**Who:** owner. **When:** by 11-02. **Waits for:** nothing.

- [ ] **Step 1: Read the repo's state.** Owner verifies every command here: none of them can be dry-run from the planning session.
  ```bash
  gh repo view AIKUSAN/notchmeow --json visibility,isFork,parent,defaultBranchRef
  gh api repos/AIKUSAN/notchmeow/pages --jq '{source: .source, status: .status}'   # 404 = Pages off
  git ls-remote origin > "$W/remote-refs-before.txt"; wc -l "$W/remote-refs-before.txt"
  gh release view v1.0.0 --repo AIKUSAN/notchmeow --json assets --jq '.assets[] | "\(.downloadCount) \(.name)"'
  ```
  Paste all four outputs to the main session (`mkdir -p "$W"` first). The last local copy of origin's branches is `main`, `hold-windows-downloads`, `linux-0.1.2`, `n22-gemini`, `windows`, `windows-0.1.1` and `windows-downloads`. The real list in `remote-refs-before.txt` decides.
- [ ] **Step 2: Decide V.** If the asset download counts add up to 10 or fewer (ruling 1), V = 1.0.0; otherwise V = 1.1.0. Record V and the counts in the vault (`02-Decisions/`). **Do not delete the old release yet.** Task 10 does it.
- [ ] **Step 3: Pages source.** If Pages deploys from `main` /docs (expected: the repo has no Pages workflow), the site commit is pushed last (Task 15). If Pages is off or the repo is private without Pages, note it: Task 15, step 6 checks only the release URLs then.

### Task 2: The fork-network decision point

**Who:** main session. **When:** right after Task 1. **Waits for:** Task 1's outputs and Task 3, step 1. **Run Task 3, step 1 first, before anything else in this plan:** the only copy of the private name is `e8c28e9`, which lives in the reflog alone, becomes prunable around 11-14 (30-day default) and goes at once with any `gc --prune=now`.

- [ ] **Step 1: Re-run the local proof that nothing of ours that is private was ever pushed** (dry-run 10-29: all zeros). The pattern file comes from Task 3, step 1.
  ```bash
  for r in $(git for-each-ref --format='%(refname)' refs/remotes/origin); do
    n=$(git rev-list --objects "$r" | cut -d' ' -f1 | git cat-file --batch | LC_ALL=C grep -a -c -F -f "$W/private-patterns.txt" || true)
    t=$(git rev-list --objects "$r" | cut -d' ' -f1 | git cat-file --batch | LC_ALL=C grep -a -c -E "$CF" || true)
    echo "$r private=$n tokens=$t"
  done
  ```
  Expected: `private=0 tokens=0` on every line. Any non-zero result stops the plan and goes to the owner.
- [ ] **Step 2: Apply the decision.**
  - `isFork` false, or step 1 all zero: **proceed, no detach.** After the force-push, old commits may still open by SHA through the fork network or GitHub's cache. Step 1 shows they hold only Coucou's own art, which upstream publishes itself. Write this in the vault decision.
  - `isFork` true **and** any non-zero result: the owner files a GitHub Support request (detach the fork, purge cached views) before Task 10. The lead time is unknown (owner verifies), and the release waits.
  - `refs/pull/*` lines in `remote-refs-before.txt`: the owner cannot delete them. Owner runs `git fetch origin '+refs/pull/*/head:refs/pr/*'` in a scratch clone, and the main session re-runs step 1 on `refs/pr/*`. Zeros: same as the first bullet.

### Task 3: The private-pattern file and the rewrite rehearsal

**Who:** main session. **When:** by 11-03, again after F3a2-mac merges. **Waits for:** nothing. The rehearsal proves the commands, and Task 9 repeats it on the final `main`.

**Files:** none tracked. Writes only under `$W`.

- [ ] **Step 1: Write the pattern file, before any reflog expire.** `e8c28e9` is only in the reflog, and after Task 7 nothing would be left to read the name from.
  ```bash
  mkdir -p "$W" && chmod 700 "$W" && umask 077
  N=$(git show e8c28e9:docs/superpowers/plans/2026-10-15-g2-mac-link.md | grep -o 'host: "[^"]*"' | head -1 | cut -d'"' -f2)
  { printf '%s\n' "$N"; printf '%s\n' "$N" | sed "s/'/’/g"; printf '%s\n' "$N" | tr -d "'’" | tr '[:upper:] ' '[:lower:]-'
    scutil --get ComputerName; scutil --get LocalHostName; printf '/Users/%s/\n' "$(id -un)"; } > "$W/private-patterns.txt"
  awk 'length($0) < 6 {s=1} END {print NR " lines, short=" s+0}' "$W/private-patterns.txt"
  ```
  Expected: `6 lines, short=0`. Never `cat` the file.
- [ ] **Step 2: Look for pinned commit SHAs** that a rewrite would break (dry-run 10-29: none; `check-ask-unchanged.sh` takes its base as an argument and is not in CI):
  ```bash
  grep -rn -E 'git [a-z-]+[^|;]*\b[0-9a-f]{8,40}\b' scripts tests .github windows/scripts | grep -v -i sha256
  ```
  Expected: only fixture timestamps. A real pinned SHA gets a fix task before Task 9.
- [ ] **Step 3: Save the rehearsal script** as `$W/rewrite.sh`. Task 9 runs the same file.
  ```bash
  #!/usr/bin/env bash
  # usage: bash rewrite.sh <repo> <workdir>   (workdir is emptied)
  set -euo pipefail
  REPO="$1"; D="$2"; rm -rf "$D"; mkdir -p "$D"
  git clone -q --no-local --no-tags --single-branch --branch main "$REPO" "$D/rw"
  cd "$D/rw"; git remote remove origin
  git rev-parse main > "$D/orig-main.txt"
  git rev-list f96e7f31^ | while read -r c; do git ls-tree -r --format='%(objectname) %(path)' "$c"; done \
    | grep -i -E '\.(png|icns|ico|gif|mp4|mov|wav|mp3|aif|aiff|caf|svg|jpe?g|webp)$' | cut -d' ' -f1 | sort -u > "$D/art-pre-rebrand.txt"
  git ls-tree -r --format='%(objectname)' main | sort -u > "$D/head-blobs.txt"
  comm -23 "$D/art-pre-rebrand.txt" "$D/head-blobs.txt" > "$D/bad-blobs.txt"
  TREE=$(git rev-parse 'main^{tree}'); COUNT=$(git rev-list --count main)
  export BAD="$D/bad-blobs.txt"
  FILTER_BRANCH_SQUELCH_WARNING=1 git -c core.quotepath=off filter-branch --index-filter '
    git rm -r --cached --ignore-unmatch -q -- docs/media design/captures design/animations windows/screenshots windows/src/mochi \
      NotchBuddy/Resources/Coucou.entitlements NotchBuddy/Resources/CoucouAppStore.entitlements design/prototype/notch-buddy.html
    git ls-files -s | grep -F -f "$BAD" | cut -f2- | git update-index --force-remove --stdin
  ' -- main
  git for-each-ref --format='%(refname)' refs/original | xargs -n1 git update-ref -d
  git reflog expire --expire=now --all && git gc -q --prune=now
  echo "bad blobs: $(wc -l < "$D/bad-blobs.txt")  tree same: $([ "$(git rev-parse 'main^{tree}')" = "$TREE" ] && echo yes || echo NO)  commits: $COUNT -> $(git rev-list --count main)"
  ```
- [ ] **Step 4: Run it on a throwaway workdir.**
  ```bash
  bash "$W/rewrite.sh" "$REPO" "$W/rehearsal" 2>&1 | tr '\r' '\n' | grep -v '^Rewrite '
  ```
  Expected (dry-run 10-29, without `design/animations`, which adds 2 paths): `bad blobs: 97  tree same: yes  commits: 1448 -> 1448`, and about 13 minutes.
- [ ] **Step 5: Check the purge on a fresh clone** of the rewritten repo. A fresh clone holds only objects reachable from `main`.
  ```bash
  D="$W/rehearsal"; git clone -q --no-local --no-tags --single-branch --branch main "$D/rw" "$D/verify"; cd "$D/verify"
  echo "1 coucou/mochi paths:  $(git rev-list --objects --all | cut -d' ' -s -f2- | grep -i -c -E 'mochi|coucou')"
  echo "2 purged paths:        $(git rev-list --objects --all | cut -d' ' -s -f2- | grep -c -E '^(docs/media|design/captures|design/animations|windows/screenshots|windows/src/mochi)(/|$)|notch-buddy\.html$|Coucou[A-Za-z]*\.entitlements$')"
  echo "3 bad blobs left:      $(git rev-list --objects --all | cut -d' ' -f1 | sort -u | comm -12 - "$D/bad-blobs.txt" | wc -l)"
  echo "4 private strings:     $(git cat-file --batch-all-objects --batch | LC_ALL=C grep -a -c -F -f "$W/private-patterns.txt")"
  echo "5 Cloudflare tokens:   $(git cat-file --batch-all-objects --batch | LC_ALL=C grep -a -c -E "$CF")"
  echo "6 tree = old main:     $([ "$(git rev-parse 'main^{tree}')" = "$(git -C "$REPO" rev-parse 'main^{tree}')" ] && echo yes || echo NO)"
  echo "7 the check bites:     $(git -C "$REPO" rev-list --objects main | cut -d' ' -s -f2- | grep -i -c -E 'mochi|coucou') paths before"
  ```
  Expected: lines 1 to 5 print `0`, line 6 `yes`, and line 7 a number above 0 (10-29: 9). Check 4 reads commit objects too, so authors, committers and messages are covered. `git log -p` is not used: it skips merge diffs and binaries.
- [ ] **Step 6: Sweep the rest of the spec's section 4** on the verify clone. Read each hit: fixtures with fake keys are expected, so record them rather than trust them.
  ```bash
  git cat-file --batch-all-objects --batch | LC_ALL=C grep -a -o -E 'AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY' | sort | uniq -c
  git rev-list --objects --all | cut -d' ' -s -f2- | sort -u | grep -i -E '\.(env|p12|pem|key|keychain|keychain-db|mobileprovision|cer|jks|har|sqlite)$|id_rsa|dump-keychain'
  ```
- [ ] **Step 7: Build and test the rewritten tip** in the verify clone. Tree equality (step 5, line 6) is the proof; this run confirms it.
  ```bash
  (cd NotchBuddy && xcodegen generate --quiet && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release -derivedDataPath build build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet)
  bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Release/NotchMeow.app release
  fails=0; for t in scripts/test-*.sh; do bash "$t" >/dev/null 2>&1 || { echo "FAIL $t"; fails=$((fails+1)); }; done; echo "failed: $fails"
  bash scripts/check-no-leftovers.sh
  git ls-files | grep -E '^\.claude|graphify-out'          # spec 4.7: prints nothing
  (cd windows && npm ci && npx tsc --noEmit && for c in cat claude sidekick projects companion link settings ai; do npm run -s check:$c >/dev/null || echo "FAIL check:$c"; done)
  bash scripts/check-site.sh
  windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/release-stage-2
  ```
  Expected: the build succeeds, `check-app-binary.sh` passes, and `failed: 0`. A failure in `test-release-tools.sh` or `test-link-session.sh` is known flake: re-run it once. No `FAIL check:`, and cargo passes. Docker Desktop must be running; if it is not, note it.
- [ ] **Step 8: Report** the step 4 line, the step 5 numbers, the step 6 hits and the step 7 result to the owner. Keep `$W/rehearsal` until Task 9 has passed.

### Task 4: CHANGELOG section and release-notes draft

**Who:** subagent `nm-implementer-light` (Haiku 5.5, medium), reviewed by `nm-reviewer`. **When:** 11-09. **Waits for:** F3a2-mac (`claude/cranky-allen-8e588e`, about 11-02) and the cat reactions showcase (`worktree-agent-a31d061d6c5e83e50`) merged into `main`, so the section lists them.

**Files:**
- Modify: `CHANGELOG.md` (lines 3 and 11).
- Create, untracked: `$W/RELEASE-NOTES-<V>.md`. Never commit it: `release.sh --tester` empties `/tmp/notchmeow-release-<V>/`, so the notes cannot live there.

- [ ] **Step 1:** On branch `release/changelog-<V>` from `main`, rename `## Unreleased` to `## 1.0.0 (relaunch) — 2026-11-13` (or `## 1.1.0 — 2026-11-13`), and rename the old `## 1.0.0` to `## 1.0.0 preview — 2026-10-16`. Add one line each for the F3a2-mac and showcase merges, worded from their merge commits (`git log --merges --format=%s main -10`). Add the install paragraph from step 2 at the top of the new section.
- [ ] **Step 2:** Write `$W/RELEASE-NOTES-<V>.md` in this order:
  1. The title line: `NotchMeow 1.0.0 (relaunch), replaces the 2026-10-16 preview` (or `NotchMeow 1.1.0`).
  2. "What's new": the new CHANGELOG section.
  3. Mac install: open the DMG, drag to Applications, then System Settings → Privacy & Security → **Open Anyway**.
  4. Updating: the Keychain asks once to **Always Allow**, because ad hoc builds change identity.
  5. Windows: the portable zip, then SmartScreen → More info → Run anyway, and a possible Defender flag.
  6. Linux: "tested in CI and in Docker only", and the known untested line (X11 WM_CLASS hosts, no Secret Service, Wayland).
  7. The checksum commands `shasum -a 256 -c <file>.sha256` and `sha256sum -c SHA256SUMS`.
  8. "No telemetry, no account."
  9. The licence lines: MIT code with Louis Raillé's notice; name, cats, icons and sounds under `LICENSE-ASSETS.md`.
  
  Reuse the wording of `release.sh`'s tester `NOTES.txt` block (lines 137 to 145). Do not reuse its signed-mode text, which says "Developer ID".
- [ ] **Step 3: Verify.**
  ```bash
  awk -v head="## $V" 'index($0, head " ") == 1 || $0 == head {print NR": "$0}' CHANGELOG.md | head -1   # the new heading comes first
  LC_ALL=C grep -c -F -f "$W/private-patterns.txt" CHANGELOG.md "$W/RELEASE-NOTES-$V.md"                # 0 and 0
  grep -c -i "developer id\|notarized by apple" "$W/RELEASE-NOTES-$V.md"                               # 0
  ```
- [ ] **Step 4:** Commit on the branch (`docs(changelog): <V> relaunch section`). The main session merges it in Task 7.

### Task 5: README and site Download section

**Who:** subagent `nm-implementer-light` (Haiku 5.5, medium), reviewed by `nm-reviewer`; the audit with `fixing-metadata` and `fixing-accessibility` reports only. **When:** 11-09. **Waits for:** the cat reactions showcase merged, because its pictures and section are on the same pages.

**Files:** modify `README.md` (lines 20 to 22 banner, 46 roadmap row D, 54 heading, 65 to 69 Install), `docs/index.html` (lines 99 and 100, the two release cards), `docs/testers.html` (keep the page; add an "Older builds" note and a link to `index.html#download`).

- [ ] **Step 1:** On branch `release/site-<V>` from `main`, make these changes:
  - `docs/index.html`: replace the two cards with an `id="download"` section that has
    - five links to exact asset URLs, `https://github.com/AIKUSAN/notchmeow/releases/download/v<V>/<name>`, for `NotchMeow-<V>-mac.dmg`, `NotchMeow-<V>-mac.zip`, `NotchMeow-<V>-windows-portable.zip`, and the Linux AppImage and deb names from Task 12, step 3 (never `releases/latest`);
    - the Open Anyway, SmartScreen and Keychain lines from Task 4;
    - a link to the checksums;
    - "no telemetry, no account".
  - `README.md`: drop the "Work in progress… by invitation" banner and the tester-build sentence on line 69. Install points at the same URLs. Roadmap row D becomes "1.0.0 relaunch shipped; Developer ID signing is D2 (shelved)". Rename "Features (inherited from Coucou)" to "Features"; the owner may reword. Keep the Coucou credit and the MIT notice.
  - The Linux file names are not known until Task 12: the main session fills them in Task 14, step 1.
- [ ] **Step 2: Verify.**
  ```bash
  bash scripts/check-site.sh                       # passes: GitHub links are allowed; Coucou only in the credits
  grep -c 'releases/latest' docs/index.html README.md   # 0 and 0
  LC_ALL=C grep -c -F -f "$W/private-patterns.txt" docs/index.html docs/testers.html README.md   # 0 0 0
  ```
- [ ] **Step 3:** Commit on the branch. This branch is **not** merged before the rewrite: the main session turns it into patches in Task 7, step 4, and applies them in Task 14.

### Task 6: The owner's 11-10 checks

**Who:** owner. **When:** 11-10, the Mac in the morning, the PC in the afternoon. **Waits for:** F3a2-mac merged (check M11). Freeze on `main` from 11-10 00:00: fixes only.

**Builds (main session prepares them on 11-09):**
- Mac: `bash scripts/release.sh 1.0.0 --tester --dmg` on a clean `main`. This is still build 10, so M2 is repeated in Task 14 on build 11.
- PC: `git bundle create "$W/nm-main.bundle" main`, copied to the PC. There: `git clone nm-main.bundle notchmeow && cd notchmeow/windows && npm ci && npm run pack`. Owner verifies that the PC has Node, Rust and the Tauri prerequisites. If it does not, W1 to W11 move to 11-11 afternoon on the CI artifacts (schedule, fallback B).

The list below is ordered and deduplicated from `.claude/archive/owner-manual-checks.md`, using spec section 5 plus four items it missed (M5, M8, W8, W9). Each line says what to do, then what passes.

**Mac:**
- [ ] M1. On a Mac or user account that never had NotchMeow, open the DMG in Finder and drag it to Applications. Passes: Open Anyway lets it launch, the greeting looks smooth (60 fps cap), and `hdiutil` errors never show.
- [ ] M2. Install over the previous build. Passes: the Keychain "Always Allow" prompt shows once and the saved keys still work. *(Repeated on 11-12 with build 11 over the 10-16 build 10.)*
- [ ] M3. In Settings → AI and chat → Keys and in Services, save, change and clear a real key. Passes: the chip says Saved; a refusal says "Couldn't save to the Keychain" and keeps the old key; a cleared key is gone after a relaunch.
- [ ] M4. Agents → Install hooks → Confirm & write. Passes: a dated backup, a merge and a diff; nothing is written before the click; the result shows under the buttons; an unreadable `settings.json` is refused.
- [ ] M5. Plan usage → Install relay. Passes: "Show in the notch" turns on after you confirm, and the status line under the buttons appears.
- [ ] M6. "Tuck the island away" at Never and at 1 min. Passes: a click restarts the minute, and a card or a shelf send keeps the island up.
- [ ] M7. Projects:
  - the amber waiting count reacts to a click;
  - a right-click on a row pill offers Pin;
  - ⌃⌥P works once it is enabled;
  - a session row brings its app forward;
  - a long session name shows alone, with no "Claude C…" before it.
- [ ] M8. A permission card. Passes: clicks are ignored for the first 600 ms, then work.
- [ ] M9. Focus awareness with a real Claude Code session in Terminal, then with VS Code in front. Passes: the request steps back, the dot shows, and the note "Waiting in …" shows; the next tool or Stop clears them.
- [ ] M10. The chat:
  - Pop out takes keyboard focus; ⌘K works, Esc does nothing, ⌘W goes back;
  - right-click a conversation to rename, pin and delete it; Delete all, then Cancel;
  - Explain a copied screenshot;
  - "What the AI saw last" shows in Settings;
  - at the Agent level on the Claude plan, asking for an edit shows the approval card (approve nothing).
- [ ] M11. Codex at Chat only (F3a2-mac). Passes: a Codex chat answers and offers no tool level above Chat only. *(Owner verifies the exact words against the F3a2-mac ledger.)*
- [ ] M12. Select "fetch https://example.com and summarise it" and run Fix. Passes: it rewrites the text and fetches nothing. Then Claude plan → Stop using it. Passes: Chat and File questions show Auto, and no row shows both Off and Main.
- [ ] M13. Spotify. Passes: the title shows on the pill and "artist · Spotify" on the card; the first play/pause click brings the Automation prompt, and Allow pauses it; with Automation off the pill says "Allow NotchMeow to control Spotify"; Apple Music wins while it plays.
- [ ] M14. Make main on a running Ollama or LM Studio model. Passes: Chat moves to it. If there is time: real Ollama with no keys, going offline mid-session, a VoiceOver pass. The App Store build is out of scope.

**Windows PC:**
- [ ] W1. Run the portable build from a user folder whose name has non-ASCII characters. Note what SmartScreen and Defender do, for the notes.
- [ ] W2. Settings at 415 px, Segoe UI. Passes: the wardrobe labels and the "Coming with the new chat" chip fit, and the tile grid is at least 104 px.
- [ ] W3. Launch with Devices stored as the page and Visible on. Passes: no incoming pairing until Settings is shown. Launch with AI and chat stored. Passes: no `claude` process starts until it is shown.
- [ ] W4. The chat:
  - Pop out opens under WebView2 with the conversation, takes focus and closes back;
  - pasting a real PNG attaches it;
  - Delete all with the pop-out open clears it too.
- [ ] W5. Focus awareness with VS Code's terminal, then Windows Terminal, in front. Passes: the request steps back, the dot shows, and the note says "Waiting in VS Code". With File Explorer in front, the normal card shows. Check the process names in Task Manager → Details.
- [ ] W6. Projects. Passes: a Windows Terminal session and a Claude desktop app session each make a project; the tray shows "Projects (N)"; Pin on a pill does not fold the island.
- [ ] W7. Turn "Launch at startup" off. Passes: the save succeeds. Keys: save, change and clear one; a refused save keeps the old key.
- [ ] W8. With the island open, click Settings, the desktop cat and the tray. Passes: the island stays open. A click outside folds it. Both wings step aside and pass clicks through.
- [ ] W9. Claude desktop app → Open. Passes: a running Claude comes forward; with Claude not installed, nothing visible happens.
- [ ] W10. Run Fix on the fetch sentence. Passes: it fetches nothing. A refused run stops `claude` promptly.
- [ ] W11. Devices → Visible, pair with the Mac, send a file both ways, Accept. Passes: the files arrive in Downloads/NotchMeow, and the Windows file has its Zone.Identifier.

**Linux:** none (no owner machine on record). The notes say "tested in CI and in Docker only".

- [ ] **Report:** list each failed item, with a crash, data loss, broken hooks or a Keychain loss marked **blocking**. The main session turns the list into fix tasks on the evening of 11-10.

### Task 7: The merge gate and the local clean-up

**Who:** main session, with the owner's yes before any delete. **When:** 11-11 morning, after the last fix merges. **Waits for:** F3a2-mac, the showcase, Task 4, and every 11-10 fix merged into `main`.

- [ ] **Step 1: Gate.** Every branch must be merged except the two token branches and `release/site-<V>`:
  ```bash
  git branch --no-merged main
  git worktree list
  git stash list | wc -l
  ```
  Expected: only `claude/recursing-swartz-574574`, `f3a2-0/plan-brains-contract` and `release/site-<V>`; the main worktree only (archive the others first: copy each ledger to `.claude/archive/sdd/<branch>/`, then `git worktree unlock <path>` where locked, then `git worktree remove <path>`); `0`. Anything else unmerged is saved with `git format-patch main..<branch> -o "$W/kept/<branch>"`, with the owner's yes.
- [ ] **Step 2: Re-scan `main`** for tokens and private strings (expected 0 and 0):
  ```bash
  git rev-list --objects main | cut -d' ' -f1 | git cat-file --batch | LC_ALL=C grep -a -c -E "$CF"
  git rev-list --objects main | cut -d' ' -f1 | git cat-file --batch | LC_ALL=C grep -a -c -F -f "$W/private-patterns.txt"
  ```
- [ ] **Step 3: Delete the token branches** (owner's yes): `git branch -D claude/recursing-swartz-574574 f3a2-0/plan-brains-contract`.
- [ ] **Step 4: Save the site branch as patches**, because its commits sit on the old history:
  ```bash
  git format-patch "$(git merge-base main release/site-$V)..release/site-$V" -o "$W/site-patches" && ls "$W/site-patches"
  ```

### Task 8: The version bump and the build-number check

**Who:** main session; the commit needs the owner's yes. **When:** 11-11, right after Task 7. **Waits for:** Task 7.

**Files:** `NotchBuddy/project.yml:66-67`, `NotchBuddy/Resources/Info.plist` (rewritten by xcodegen), `windows/package.json`, `windows/package-lock.json`, `windows/src-tauri/tauri.conf.json`, `windows/Cargo.toml`, `windows/Cargo.lock` (for 1.1.0), `CHANGELOG.md`.

- [ ] **Step 1:** `bash scripts/set-version.sh "$V"`. Expected: `✓ version <V>, build number 10 → 11` (dry-run 10-29 on a scratch clone: exactly this).
- [ ] **Step 2:** `bash scripts/check-versions.sh "$V"`. Expected: `✓ every version field is <V>`.
- [ ] **Step 3: Build-number check.**
  ```bash
  b=$(awk -v f=yml_build -f scripts/version-fields.awk NotchBuddy/project.yml); p=$(awk -v f=plist_build -f scripts/version-fields.awk NotchBuddy/Resources/Info.plist)
  [ "$b" = "$p" ] && [ "$b" -gt 10 ] && echo "build $b ok" || echo "BUILD NUMBER WRONG"
  ```
  If 11-10 fixes landed after Task 4, add their lines to the new CHANGELOG section.
- [ ] **Step 4:** Commit with the owner's yes: `git commit -am "chore(release): <V> relaunch, build 11"`. This commit, rewritten, becomes the tag commit.

### Task 9: The rewrite, for real

**Who:** main session. **When:** 11-11, after Task 8 (about 13 minutes of filter, then about an hour of builds). **Waits for:** Task 3 passed and Task 8 committed. Nothing may be committed to `main` from here until Task 11.

- [ ] **Step 1: Back up** to a mirror, kept until a week after the release: `git clone -q --mirror "$REPO" "$W/backup-$(date +%Y%m%d).git"`. It is local only: a local mirror carries the token commits and the reflog's objects, so **never push from it**.
- [ ] **Step 2: Rewrite.**
  ```bash
  bash "$W/rewrite.sh" "$REPO" "$W/final" 2>&1 | tr '\r' '\n' | grep -v '^Rewrite '
  ```
  Expected: `tree same: yes` and the same commit count before and after.
- [ ] **Step 3:** Run Task 3, steps 5 to 7, with `D="$W/final"`. Every expected value must match. If any check fails, push nothing: fix the path list in `rewrite.sh`, re-run Task 3 on `$W/rehearsal`, then repeat this task (fallback point B).
- [ ] **Step 4: Prove nothing landed meanwhile.** Expected: `same`.
  ```bash
  [ "$(git -C "$REPO" rev-parse main)" = "$(cat "$W/final/orig-main.txt")" ] && echo same
  ```

### Task 10: The force-push

**Who:** owner. **When:** 11-11, right after Task 9. **Waits for:** Task 9 clean and Task 2 decided. Owner verifies every command: none can be dry-run from the planning session. The old release, tags and branches stay up until Task 15, step 1, so users keep a download if the date slips.

- [ ] **Step 1:** Leave the GitHub refs alone today. Old branches and tags do not block the force-push or the CI runs.
- [ ] **Step 2: Last scan before the push.** The main session runs it in `$W/final/verify`: Task 3, step 5, lines 4 and 5. Expected: 0 and 0.
- [ ] **Step 3: Dry run, then push** from the rewritten clone, never from the working repo:
  ```bash
  cd "$W/final/rw" && git remote add origin https://github.com/AIKUSAN/notchmeow.git
  OLD=$(git -C "$REPO" rev-parse origin/main)    # the full 40-hex fda7645b…
  git push --dry-run --force-with-lease="main:$OLD" origin main
  git push --force-with-lease="main:$OLD" origin main
  ```
  If the lease is refused, someone pushed since `fda7645b`: stop and tell the main session.
- [ ] **Step 4:** If Task 1 found the repo private, it stays private until Task 15.
- [ ] **Step 5: Check.** `git ls-remote origin | grep -E 'HEAD|refs/heads/main$'`. Expected: both at the rewritten tip (`cat "$W/final/rw/.git/refs/heads/main"` or `git -C "$W/final/rw" rev-parse main`).

### Task 11: Bring the working repo onto the new history

**Who:** main session; each delete with the owner's yes. **When:** 11-11, after Task 10. **Waits for:** Task 10, step 5.

- [ ] **Step 1: Move `main`.** The tree is identical, so the reset changes no file.
  ```bash
  cd "$REPO" && [ -z "$(git status --porcelain)" ] && git fetch -q "$W/final/rw" main && git reset -q --hard FETCH_HEAD
  git rev-parse 'HEAD^{tree}'    # same as before
  ```
- [ ] **Step 2: Drop every old ref:**
  ```bash
  git for-each-ref --format='%(refname:short)' refs/heads | grep -v -x main | xargs -n 50 git branch -D
  git tag -l | xargs -n 50 git tag -d
  git remote remove upstream
  git for-each-ref --format='%(refname)' refs/remotes/origin | xargs -n1 git update-ref -d
  git update-ref refs/remotes/origin/main main
  git worktree prune
  git reflog expire --expire=now --all && git gc -q --prune=now
  ```
- [ ] **Step 3: Re-check the working repo.** Expected: 0, 0, 0, 0. `.claude/` and `graphify-out/` are untouched (git-ignored).
  ```bash
  git rev-list --objects --all | cut -d' ' -s -f2- | grep -i -c -E 'mochi|coucou'
  git rev-list --objects --all | cut -d' ' -f1 | sort -u | comm -12 - "$W/final/bad-blobs.txt" | wc -l
  git cat-file --batch-all-objects --batch | LC_ALL=C grep -a -c -F -f "$W/private-patterns.txt"
  git cat-file --batch-all-objects --batch | LC_ALL=C grep -a -c -E "$CF"
  ```
- [ ] **Step 4:** Note in the vault that every SHA in older ledgers and notes is pre-rewrite (the mirror backup maps them). Refresh graphify incrementally.

### Task 12: Build Windows and Linux in CI

**Who:** owner. **When:** 11-11, right after Task 10. **Waits for:** Task 10. The artifacts expire after 3 days, so download them the same day.

- [ ] **Step 1: Run the workflows** on `main`. Owner verifies every command in this task.
  ```bash
  gh workflow run windows.yml --repo AIKUSAN/notchmeow --ref main
  gh workflow run linux.yml --repo AIKUSAN/notchmeow --ref main
  gh workflow run windows-tests.yml --repo AIKUSAN/notchmeow --ref main
  gh run list --repo AIKUSAN/notchmeow --limit 6 --json databaseId,workflowName,headSha,conclusion
  ```
  Expected: all three succeed. `build.yml` also runs on the push. Every `headSha` is the rewritten tip. Paste the run list to the main session.
- [ ] **Step 2: Download.**
  ```bash
  gh run download <windows-run-id> --repo AIKUSAN/notchmeow -n NotchMeow-Windows-portable -D "$W/win/portable"
  gh run download <linux-run-id>   --repo AIKUSAN/notchmeow -n NotchMeow-Linux           -D "$W/linux"
  ```
- [ ] **Step 3:** Run `ls "$W/linux"` and send the exact Linux file names to the main session, for the site links.
- [ ] **Step 4: Delete the artifacts** once the files are local. Artifacts of a public repo are downloadable by any signed-in user.
  ```bash
  for r in <windows-run-id> <linux-run-id>; do gh api "repos/AIKUSAN/notchmeow/actions/runs/$r/artifacts" --jq '.artifacts[].id' | while read -r a; do gh api -X DELETE "repos/AIKUSAN/notchmeow/actions/artifacts/$a"; done; done
  ```

### Task 13: Build the Mac files, pack Windows, write the checksums

**Who:** main session. **When:** 11-11, in parallel with Task 12. **Waits for:** Task 11.

- [ ] **Step 1: The Mac files.** Expected: the zip, the DMG, both `.sha256` files and `NOTES.txt` in `/tmp/notchmeow-release-<V>/`. The script prints "Nothing was notarized, tagged, pushed or published."
  ```bash
  bash scripts/release.sh "$V" --tester --dmg
  ```
- [ ] **Step 2: The Windows zip**, once Task 12, step 2 is done:
  ```bash
  cd "$W/win/portable" && zip -j -X "$W/win/NotchMeow-$V-windows-portable.zip" notchmeow.exe notchmeow-hook.exe
  cd "$W/win" && shasum -a 256 "NotchMeow-$V-windows-portable.zip" > "NotchMeow-$V-windows-portable.zip.sha256"
  ```
- [ ] **Step 3: Verify every checksum.** Expected: every line ends `OK`.
  ```bash
  (cd "/tmp/notchmeow-release-$V" && shasum -a 256 -c "NotchMeow-$V-mac.zip.sha256" "NotchMeow-$V-mac.dmg.sha256")
  (cd "$W/win" && shasum -a 256 -c "NotchMeow-$V-windows-portable.zip.sha256")
  (cd "$W/linux" && shasum -a 256 -c SHA256SUMS)
  ```
- [ ] **Step 4: Scan the files people will download** for private strings. Expected: 0.
  ```bash
  for f in "/tmp/notchmeow-release-$V"/*.{zip,dmg} "$W/win"/*.zip "$W/linux"/NotchMeow-Linux-*; do LC_ALL=C grep -a -c -F -f "$W/private-patterns.txt" "$f"; done | sort -u
  ```
  The zip and DMG are compressed, so also scan the built app: `grep -r -a -c -F -f "$W/private-patterns.txt" "/tmp/notchmeow-release-$V/build/NotchMeow.app" | grep -v ':0$'`. Expected: no output.
- [ ] **Step 5: The DMG's build number.** Expected: `<V> 11` (or above) and `mounted ok`.
  ```bash
  M=$(mktemp -d); hdiutil attach -readonly -nobrowse -mountpoint "$M" "/tmp/notchmeow-release-$V/NotchMeow-$V-mac.dmg" -quiet
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' -c 'Print :CFBundleVersion' "$M/NotchMeow.app/Contents/Info.plist" | paste -sd' ' -
  hdiutil detach "$M" -quiet && echo "mounted ok"
  ```
- [ ] **Step 6: One commit for everything.** Expected: three `same`. Then hand the owner the file list for Task 14.
  ```bash
  T=$(git rev-parse main); grep -q "Commit:  $T" "/tmp/notchmeow-release-$V/NOTES.txt" && echo "mac same" && echo "$T" > "$W/build-commit.txt"
  # and in Task 12's run list: windows.yml and linux.yml headSha == $T
  ```

### Task 14: Re-checks on the real files, and go/no-go

**Who:** owner; the main session applies the site patches with the owner's yes. **When:** 11-12. **Waits for:** Tasks 12 and 13.

- [ ] **Step 1: The site and README.** The main session applies the patches on a branch and fills in the Linux names from Task 12, step 3:
  ```bash
  git switch -c release/site-$V && git am "$W/site-patches"/*.patch && bash scripts/check-site.sh
  ```
  Commit only with the owner's yes. The branch is fast-forwarded into `main` in Task 15, step 5.
- [ ] **Step 2:** On the real files, repeat M1, M2 (build 11 over the 10-16 build 10), W1 and W11.
- [ ] **Step 3:** The owner reads `$W/RELEASE-NOTES-<V>.md`, the site branch rendered locally (`open docs/index.html`) and README.md, and approves the wording.
- [ ] **Step 4: Go/no-go** at the end of the day, platform by platform (fallback point C). A platform that fails is held:
  - the site and the notes mark it "coming";
  - its files are not attached;
  - it follows as a point release.

### Task 15: Publish

**Who:** owner. **When:** Friday 11-13. **Waits for:** go in Task 14. Owner verifies every command.

- [ ] **Step 1: Delete the old release and every old ref** (spec condition 1: before the new release is published; ruling 2). The list is built fresh, minus `main` and minus the Pages source branch from Task 1, step 3:
  ```bash
  gh release delete v1.0.0 --repo AIKUSAN/notchmeow --cleanup-tag --yes
  for r in windows-latest linux-latest; do gh release view "$r" --repo AIKUSAN/notchmeow >/dev/null 2>&1 && gh release delete "$r" --repo AIKUSAN/notchmeow --cleanup-tag --yes; done
  KEEP='main'   # add the Pages branch here if Task 1 found one other than main
  git ls-remote --heads origin | sed 's#.*refs/heads/##' | grep -v -x -E "$KEEP" > "$W/delete-branches.txt"; cat "$W/delete-branches.txt"
  git ls-remote --tags origin | sed 's#.*refs/tags/##; s#\^{}##' | sort -u > "$W/delete-tags.txt"; cat "$W/delete-tags.txt"
  while read -r b; do git push origin --delete "refs/heads/$b"; done < "$W/delete-branches.txt"
  while read -r t; do git push origin --delete "refs/tags/$t"; done < "$W/delete-tags.txt"
  git ls-remote origin
  ```
  Read both lists before the two `while` lines run. Expected at the end: only `HEAD` and `refs/heads/main` (plus the Pages branch you kept, and `refs/pull/*` if Task 2 ruled on them).
- [ ] **Step 2: Last scan.** The main session runs it on the working repo (Task 11, step 3) after the site commit. Expected: 0, 0, 0, 0.
- [ ] **Step 3: Tag the build commit**, which is the parent of the site commit, and push it by name:
  ```bash
  T=$(cat "$W/build-commit.txt"); [ "$T" = "$(git rev-parse origin/main)" ] || { echo "build commit is not origin/main's tip: stop"; exit 1; }
  git tag -a "v$V" "$T" -m "NotchMeow $V"
  git push --dry-run origin "v$V" && git push origin "v$V"
  ```
  `release.yml` runs on the tag. It only checks the build.
- [ ] **Step 4: Create the release with every file.** The file list is the one Task 13 handed over. A held platform's files are left out.
  ```bash
  gh release create "v$V" --repo AIKUSAN/notchmeow --verify-tag --latest --title "NotchMeow $V" --notes-file "$W/RELEASE-NOTES-$V.md" \
    /tmp/notchmeow-release-$V/NotchMeow-$V-mac.dmg /tmp/notchmeow-release-$V/NotchMeow-$V-mac.dmg.sha256 \
    /tmp/notchmeow-release-$V/NotchMeow-$V-mac.zip /tmp/notchmeow-release-$V/NotchMeow-$V-mac.zip.sha256 \
    "$W/win/NotchMeow-$V-windows-portable.zip" "$W/win/NotchMeow-$V-windows-portable.zip.sha256" \
    "$W"/linux/NotchMeow-Linux-* "$W/linux/SHA256SUMS"
  ```
- [ ] **Step 5: Push the site.** First `git switch main && git merge --ff-only release/site-$V`, then `git push --dry-run origin main && git push origin main`. This is a fast-forward, with no force. If the repo is private, then switch it to public: Settings → General → Danger Zone, or `gh repo edit AIKUSAN/notchmeow --visibility public --accept-visibility-change-consequences`.
- [ ] **Step 6: Check from outside.** In a private window, open the release and the site. Then:
  ```bash
  for u in $(grep -h -o -E 'https://github.com/AIKUSAN/notchmeow/releases/download/[^")[:space:]]+' docs/index.html README.md | sort -u); do curl -s -o /dev/null -w "%{http_code} $u\n" -L "$u"; done
  ```
  Expected: every line starts with `200`. Download the DMG and the Windows zip again and run `shasum -a 256 -c` against the published `.sha256` files.
- [ ] **Step 7:** The main session writes the `03-Sessions/` handoff and the `02-Decisions/` note: V, the rewrite, deleted refs, the fork ruling. It adds a dated "Relaunch <V> published" section to `.claude/archive/owner-manual-checks.md`, with the checks still owed. After a week, the owner moves `$W` (backup mirror, rehearsal, pattern file) to the Trash.

---

## Schedule, 11-10 to 11-13, with the fallback points

| Day | Owner | Main session | Fallback point |
|---|---|---|---|
| by 11-02 | Task 1 | Tasks 2 and 3 (rehearsal) | Task 2 finds private content pushed in a fork → Support ticket, release waits |
| ~11-02 | — | F3a2-mac merges; Task 3 steps 4 and 5 re-run; Task 7 step 2 scan | — |
| 11-09 | — | Tasks 4 and 5 (subagents) after the showcase merges; Task 6's builds and bundle | — |
| Tue 11-10 | Task 6: Mac in the morning, PC in the afternoon | Evening: the fix list | **A.** A blocking failure on a platform → that platform is held (owner's answer: ship the rest). A polish failure → it ships, listed as a known issue. |
| Wed 11-11 | Tasks 10 and 12 | Fixes merged by noon, then Tasks 7, 8, 9, 11 and 13 | **B.** A rewrite check fails → nothing is pushed; fix `rewrite.sh`, rehearse, redo Task 9. Not clean by 11-12 noon → the release waits, and GitHub is untouched. PC builds missing on 11-10 → W1 to W11 run this afternoon on the CI files. |
| Thu 11-12 | Task 14: re-checks, notes, site, go/no-go | Task 14 step 1 (site patches) | **C.** A platform fails on its real files → it is held, the others go. Every platform fails → slip day by day, Monday 11-16 at the latest. |
| Fri 11-13 | Task 15 | Task 15 steps 2 and 7 | A 404 or a checksum mismatch in step 6 → `gh release upload --clobber` with the right file; fix the site link with a fast-forward commit. |

## Dry run (2026-10-29, `main` at `93253a6b`)

- **Checked:**
  - `filter-branch`, `update-index --force-remove --stdin` (with an empty list too) and `ls-tree --format` exist in git 2.54.
  - `rewrite.sh`'s logic, without `design/animations`, run on a scratch clone: 12 min 36 s; 97 bad blobs; 1448 commits kept; tree identical (`feb599a5…`).
  - On the fresh verify clone: checks 1 to 5 all 0; before the rewrite, check 1 found 9 paths and check 3 found 97 blobs; the token check found 2 objects on `claude/recursing-swartz-574574`. The clone shrank from 48 MB to 17 MB.
  - `set-version.sh 1.0.0` on a scratch clone: build 10 → 11, `Info.plist` 11.
  - The private-pattern file: 6 lines, 0 hits in every object of `main`, of the branches and of `origin/*`.
  - These exist: `release.sh --tester --dmg`, `check-versions.sh`, `version-fields.awk` fields `yml_build` and `plist_build`, `check-app-binary.sh … release`, `check-site.sh`, `check-no-leftovers.sh`, `windows/scripts/cargo-linux.sh`, `windows/package.json` scripts `check:{ai,claude,cat,link,sidekick,projects,companion,settings}`, and `workflow_dispatch` in `windows.yml`, `linux.yml` and `windows-tests.yml`, with artifact names `NotchMeow-Windows-portable` and `NotchMeow-Linux` (retention 3 days).
- **Owner verifies (needs GitHub or the PC):** every `gh` command, `git ls-remote`, `git push`, the Pages source, the fork status, the download counts, the PC toolchain, and the M11 wording.
- **Not run here:** Task 3, step 7 (about an hour). The identical tree makes the outcome very likely; the main session runs it in Tasks 3 and 9.
