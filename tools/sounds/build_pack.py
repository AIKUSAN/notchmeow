#!/usr/bin/env python3
"""Build NotchMeow's sound sets from the recipes in design/sounds/sets/.

  build_pack.py --set studio --candidates DIR --out DIR   one set, 29 WAVs in --out
  build_pack.py --all [--report]                          the five sets (never mine) under .claude/sounds/build
  build_pack.py --check-recipes                           validate the recipes (and the clips, if found)
  build_pack.py --set mine [--report]                     Your mix: 29 WAVs from the owner's picks
  build_pack.py --round2 [--report]                       the round-two alternatives, one WAV each
  build_pack.py --set mine --originals [DIR] [--hq-previews DIR] [--out D]
                                                          Your mix from the pinned Freesound originals, or for a clip
                                                          with none its pinned Freesound HQ preview (stage 2); the only
                                                          build that may write NotchBuddy/Resources/sounds

--report also writes report.md next to the WAVs and exits 1 when any file misses its targets. Into the shipping
folder (NotchBuddy/Resources/sounds, which holds the WAVs and nothing else) it writes
.claude/sounds/build/ship-report.md instead.

Picking and locking in. Build the five sets (--all), open design/sounds/audition.html, pick a version
for each of the 15 cat moments (or "None of these") and Lock in. The page shows the exact text of
design/sounds/sets/mine.json: save it there and run --check-recipes. --set mine builds Your mix with
the same pipeline and report as a set, and refuses (exit 2, naming the moments) while any moment is
none. For the moments left at none, list alternatives in design/sounds/sets/round2.json (ids rate-1 to
rate-3 and so on), run --round2 and reload the page: Alt columns appear on those rows. Pick again and
lock in again.

The hairball is the 29th sound and the same in every set. It is a placed sound: the recipe in
design/sounds/sets/_shared.json lays three coughs of one recording on a timeline and mixes in a retch and
plop made in code (recipe.py, source "placed"). It rebuilds the owner's pick of 2026-10-05 (the audition
file B.wav) byte for byte, which tests/test_sound_build.py checks wherever the clip is found.

Needs Python 3 and, for decoding the candidate clips, macOS afconvert. Nothing else.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(os.path.dirname(HERE))

import originals  # noqa: E402
import pipeline  # noqa: E402
import recipe  # noqa: E402
import report  # noqa: E402
import sources  # noqa: E402
from audio_io import AfconvertLoader  # noqa: E402

SETS_DIR = os.path.join(ROOT, "design", "sounds", "sets")
BUILD_DIR = os.path.join(ROOT, ".claude", "sounds", "build")
ROUND2_DIR = os.path.join(BUILD_DIR, recipe.ROUND2_NAME)    # the folder the audition page probes
SHIP_DIR = os.path.join(ROOT, "NotchBuddy", "Resources", "sounds")    # what both apps play: one WAV per slot
SHIP_KEEPS = ("README.md", ".DS_Store")      # the only other things the folder may hold (Finder litter is git-ignored)


def real(path):
    return os.path.realpath(os.path.abspath(path))


def in_ship_dir(path):
    """True when `path` is the shipping folder or inside it."""
    ship = real(SHIP_DIR)
    return os.path.commonpath([real(path), ship]) == ship


def report_path(out):
    """Where report.md goes for a build into `out`: next to the WAVs, except in the shipping folder,
    which holds the WAVs and nothing else, so its report goes under .claude/sounds/build."""
    return os.path.join(BUILD_DIR, "ship-report.md") if in_ship_dir(out) else os.path.join(out, "report.md")


def ship_problems(folder):
    """What is wrong with a shipping folder, as short sentences: it holds one <slot>.wav per slot and
    README.md, and nothing else (no report.md, no leftovers). Empty means it is exactly that."""
    have = set(os.listdir(folder))
    want = {slot + ".wav" for slot in recipe.SLOTS}
    return (["missing %s" % n for n in sorted(want - have)]
            + ["unexpected %s" % n for n in sorted(have - want - set(SHIP_KEEPS))])


def refuse_shipping_folder(jobs, from_originals=False):
    """A message when a build would write into the shipping folder, else None. Only Your mix built
    from the originals may go there (stage 2); a build from the preview clips never ships."""
    for name, _rec, out in jobs:
        if in_ship_dir(out) and not (from_originals and name == recipe.MINE_NAME):
            return ("%s: %s only takes Your mix built from the Freesound originals (stage 2), never a build "
                    "from the preview clips; build into .claude/sounds/build instead" % (name, SHIP_DIR))
    return None


def find_folder(explicit, env, name, root=ROOT):
    """A git-ignored folder under .claude/sounds: the flag, $<env>, <root>/.claude/sounds/<name>, then the same
    folder in the main checkout (a git worktree does not carry git-ignored files). None when there is none."""
    wanted = [explicit] if explicit else [os.environ.get(env), os.path.join(root, ".claude", "sounds", name)]
    for path in wanted:
        if path and os.path.isdir(path):
            return os.path.abspath(path)
    if explicit:
        return None
    try:
        common = subprocess.run(["git", "-C", root, "rev-parse", "--path-format=absolute",
                                 "--git-common-dir"], check=True, capture_output=True,
                                text=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    path = os.path.join(os.path.dirname(common), ".claude", "sounds", name)
    return path if os.path.isdir(path) else None


def find_candidates(explicit=None, root=ROOT):
    """The candidates folder: --candidates, $NM_SOUND_CANDIDATES, <root>/.claude/sounds/candidates,
    then the same folder in the main checkout. None when there is none."""
    return find_folder(explicit, "NM_SOUND_CANDIDATES", "candidates", root)


def load_extras(recipes_dir, recipes):
    """round2.json and mine.json from the recipes folder, each only if it exists: (round2, mix or None)."""
    round2 = recipe.load_round2(os.path.join(recipes_dir, recipe.ROUND2_NAME + ".json"), recipes)
    path = os.path.join(recipes_dir, recipe.MINE_NAME + ".json")
    return round2, (recipe.read_mix(path, recipes, round2) if os.path.isfile(path) else None)


def remove_stale_round2(out, keep):
    """Round-two files in `out` that round2.json no longer lists: an earlier round's alternatives, which
    the page would show as Alt columns. Only names of the form <moment>-<n>.wav go; anything else stays."""
    for name in sorted(os.listdir(out)):
        stem, ext = os.path.splitext(name)
        if ext == ".wav" and recipe.ROUND2_ID.match(stem) and stem not in keep:
            os.remove(os.path.join(out, name))
            print("removed stale %s" % name)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    what = ap.add_mutually_exclusive_group(required=True)
    what.add_argument("--set", choices=recipe.SET_NAMES + (recipe.MINE_NAME,))
    what.add_argument("--all", action="store_true")
    what.add_argument("--round2", action="store_true", help="build the round-two alternatives (round2.json)")
    what.add_argument("--check-recipes", action="store_true")
    ap.add_argument("--candidates", help="folder of candidate clips (default: .claude/sounds/candidates)")
    ap.add_argument("--out", help="output folder: the WAVs of --set and --round2, or the build root of --all")
    ap.add_argument("--recipes", default=SETS_DIR, help="folder of set recipes (and mine.json, round2.json)")
    ap.add_argument("--report", action="store_true", help="write report.md and fail if targets are missed")
    ap.add_argument("--originals", nargs="?", const="", metavar="DIR",
                    help="with --set mine: build from the pinned Freesound originals in DIR (default "
                         ".claude/sounds/originals), the only build that may write NotchBuddy/Resources/sounds")
    ap.add_argument("--hq-previews", metavar="DIR",
                    help="with --originals: the Freesound HQ previews (default .claude/sounds/hq-previews), for the "
                         "clips pinned as an hq_preview instead of an original")
    ap.add_argument("--sources", default=originals.SOURCES_PATH, help="sources.json for --originals")
    args = ap.parse_args(argv)
    from_originals = args.originals is not None
    if from_originals and args.set != recipe.MINE_NAME:
        print("--originals builds Your mix only: use --set mine --originals", file=sys.stderr)
        return 2

    wants_extras = args.check_recipes or args.round2 or args.set == recipe.MINE_NAME
    try:
        recipes = recipe.load_recipes(args.recipes)
        round2, mix = load_extras(args.recipes, recipes) if wants_extras else (OrderedDict(), None)
    except (recipe.RecipeError, OSError) as e:
        print("recipe error: %s" % e, file=sys.stderr)
        return 2
    cands = find_candidates(args.candidates)
    loader = None                                  # set below when Your mix is built from the originals

    if args.check_recipes:
        print("recipes ok: %d sets x %d slots" % (len(recipes), len(recipe.SLOTS)))
        todo = list(recipes.values())
        if round2:
            todo.append(recipe.round2_recipe(round2))
            print("round2.json ok: %d alternatives for %s"
                  % (len(round2), ", ".join(sorted({e.slot for e in round2.values()}))))
        if mix is not None:
            none = recipe.none_moments(mix)
            print("mine.json ok: %d picks, %d none%s"
                  % (len(mix.picks), len(none), (" (%s)" % ", ".join(none)) if none else ""))
        if cands is None:
            print("candidates folder not found: the clip files were not checked")
            return 0
        gone = sorted({"%s: %s" % (r.name, s) for r in todo for s in recipe.missing_sources(r, cands)})
        for line in gone:
            print("missing clip - " + line, file=sys.stderr)
        print("clips ok in %s" % cands if not gone else "%d missing clip(s)" % len(gone))
        return 2 if gone else 0

    # what to build: (name, SetRecipe, output folder). The refusals come before anything is written.
    root_out = os.path.abspath(args.out or BUILD_DIR) if args.all else None
    if args.all:
        jobs = [(n, r, os.path.join(root_out, n)) for n, r in recipes.items()]
    elif args.set == recipe.MINE_NAME:
        if mix is None:
            print("mine: no %s.json in %s; pick on design/sounds/audition.html and lock in first"
                  % (recipe.MINE_NAME, args.recipes), file=sys.stderr)
            return 2
        try:
            mine = recipe.mix_recipe(mix, recipes, round2)
        except recipe.RecipeError as e:           # MixPending names the moments that are still none
            print("mine: %s" % e, file=sys.stderr)
            return 2
        name = recipe.MINE_NAME + ("-originals" if from_originals else "")
        if from_originals:
            try:
                doc = sources.load(args.sources)
            except (sources.SourcesError, OSError) as e:
                print("mine: %s" % e, file=sys.stderr)
                return 2
            not_ready = sources.gate(doc, mine)        # the licence gate, the pins and the checked windows
            if not_ready:
                print("mine: not built, the originals are not ready:\n  " + "\n  ".join(not_ready), file=sys.stderr)
                return 2
            folder = find_folder(args.originals or None, "NM_SOUND_ORIGINALS", "originals")
            hq_folder = find_folder(args.hq_previews, "NM_SOUND_HQ_PREVIEWS", "hq-previews")
            kinds = {sources.audio_kind(doc["sources"][s]) for s in sources.file_sources(mine)}
            if folder is None and "original" in kinds:
                print("mine: originals folder not found; pass --originals DIR or set NM_SOUND_ORIGINALS", file=sys.stderr)
                return 2
            if hq_folder is None and "hq-preview" in kinds:
                print("mine: HQ previews folder not found; pass --hq-previews DIR or set NM_SOUND_HQ_PREVIEWS", file=sys.stderr)
                return 2
            loader = originals.OriginalsLoader(folder or "", doc, hq_folder)
            mine = originals.pinned_recipe(mine, doc)
        jobs = [(recipe.MINE_NAME, mine, os.path.abspath(args.out or os.path.join(BUILD_DIR, name)))]
    elif args.round2:
        if not round2:
            print("round2: no alternatives in %s" % os.path.join(args.recipes, recipe.ROUND2_NAME + ".json"),
                  file=sys.stderr)
            return 2
        jobs = [(recipe.ROUND2_NAME, recipe.round2_recipe(round2), os.path.abspath(args.out or ROUND2_DIR))]
    else:
        jobs = [(args.set, recipes[args.set], os.path.abspath(args.out or os.path.join(BUILD_DIR, args.set)))]

    refusal = refuse_shipping_folder(jobs, from_originals)
    if refusal:
        print(refusal, file=sys.stderr)
        return 2
    if loader is None:
        if cands is None:
            print("candidates folder not found; pass --candidates or set NM_SOUND_CANDIDATES", file=sys.stderr)
            return 2
        loader = AfconvertLoader(cands)
    cache, results = {}, OrderedDict()
    for name, rec, out in jobs:
        gone = [] if from_originals else recipe.missing_sources(rec, cands)
        if gone:
            print("%s: missing clips in %s: %s" % (name, cands, ", ".join(gone)), file=sys.stderr)
            return 2
        try:
            built = pipeline.build_set(rec, loader, out, cache)
        except (pipeline.SourceError, subprocess.CalledProcessError, OSError) as e:
            print("%s: %s" % (name, e), file=sys.stderr)
            return 2
        print("built %s: %d files in %s" % (name, len(built), out))
        if args.round2:
            remove_stale_round2(out, rec.entries)
        if args.report:
            results[name] = report.measure_files(list(zip(rec.entries, built)), out)
    stray = ship_problems(jobs[0][2]) if from_originals and in_ship_dir(jobs[0][2]) else []
    for line in stray:
        print("SHIP " + line, file=sys.stderr)
    waiting = []
    if args.round2 and mix is not None:
        waiting = [m for m in recipe.none_moments(mix) if not any(e.slot == m for e in round2.values())]
        if waiting:
            print("no round-two alternative for: %s" % ", ".join(waiting))
    if args.report:
        target = os.path.join(root_out, "report.md") if args.all else report_path(jobs[0][2])
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "w", encoding="utf-8") as f:
            f.write(report.render(results) + report.render_waiting(waiting) + "\n")
        bad = report.failures(results)
        total = sum(len(r) for r in results.values())
        print("report: %s (%d of %d files meet their targets)" % (target, total - len(bad), total))
        for line in bad:
            print("FAIL " + line, file=sys.stderr)
        return 1 if bad or stray else 0
    return 1 if stray else 0


if __name__ == "__main__":
    sys.exit(main())
