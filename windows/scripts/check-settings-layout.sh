#!/usr/bin/env bash
# Checks the Settings window's rows in a real browser (Settings restyle, the switch and chip rows). Source pins cannot see layout, so this is the check. Not part of CI (like
# render-settings.sh). It draws each place in the ?shot=415 frame, reads the measurement the page posts back (devpanel.ts, reportLayout: every .st-row.st-short row, the
# label's text lines and the control's box) from the page's <output id="layout-check"> with --dump-dom, and prints `layout ok` or each failure (exit 1).
#
# Criterion, per short row (a switch or a chip beside its label):
#   - the label's text is ONE line (no wrap at 415 px);
#   - the control's vertical CENTRE lies within the label's first line (the text box Range reports for its glyphs). The switch is taller than the line, so its top may sit a
#     little above it; its centre may not;
#   - no row overflows, and the page does not scroll sideways (scrollWidth <= 415).
# With --stress the first row's label is long and holds an unbreakable 46-character word: it must wrap onto two or more lines with its control still beside it, and nothing may
# overflow. --stress also measures a probe row (a normal label beside a group of nowrap buttons): its label keeps at least 6em (the floor is 9em), and nothing overflows.
# --stress also measures a STACKED probe (a label with a 46-character unbreakable word beside a select, so the row stacks): it must end inside 415 px and must not overflow.
# Devices: every machine row keeps its name, state chip and first button inside the row's right edge, and a name longer than 40 characters wraps (--stress has one).
# Pickers (the rows whose control is a pop-up menu): no picker overflows, and each picker sits inside its card, stacked or beside its label. Local models: a server that is
# running with no models shows its chip ("Running, no models yet") as a measured row.
# Help lines: each line of a row that is not short comes AFTER its control and below it (the Mac's order), inside its row. General's Tuck the island away is beside its label or
# stacked with its pop-up directly under the label (the widths print with --widths). With --stress, Devices also presses the long-named machine's Forget and measures its two buttons.
# --font wide is a stress run, not a Segoe UI check: a wide stack (Verdana, Trebuchet MS, Arial) with letter-spacing 0.04em on the root, set by the dev sample route, so the text is
# wider than Segoe UI would be whichever face is drawn (the face is not detected). The same assertions run. The real Segoe UI check stays owed on Windows.
# The normal run includes the Personality tab's "Apply to every cat" row and the Your AI tab's chip rows; --widths prints each measured row's label and control widths.
#
# Writes: a mktemp folder under ${TMPDIR:-/tmp} holding Chrome's profile, Vite's log and Chrome's stderr (chrome.log). The folder is moved to the Trash with `trash` at exit (it
# is left in place when `trash` is missing). Vite also writes its own dependency cache under windows/node_modules/.vite, which this script does not remove. It stops the Vite server
# it started.
#
# usage: check-settings-layout.sh [--stress] [--widths] [--font wide]
# (The keyboard check at the end runs in both modes: after a tab is chosen from the keyboard, the focus is on the tab menu at 415 px and on the selected tab at 720 px.)
set -euo pipefail

usage() {
  echo "usage: check-settings-layout.sh [--stress] [--widths] [--font wide]" >&2
  exit 2
}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
PORT="1422"
WIDTH="415"
HEIGHT="1700"
STRESS=""
FONT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --stress) STRESS="1"; shift ;;
    --widths) SHOW_WIDTHS="1"; shift ;;
    --font) [ "${2:-}" = "wide" ] || usage; FONT="wide"; shift 2 ;;
    *) usage ;;
  esac
done

[ -x "$CHROME" ] || { echo "Chrome not found: $CHROME" >&2; exit 1; }

# The places checked (page, or page/tab). Services and Agents carry the switch rows and the cap chips; Devices and General the single switch and short-control rows; the Sidekick tab the
# switches with their help lines and the Unmute buttons.
PLACES="services agents devices general chat/sidekick cat/personality cat/look chat/yourai chat/keys chat/localmodels"
THEMES="dark light"
if [ -n "$STRESS" ]; then
  PLACES="services devices"
  THEMES="dark"
fi
[ -z "$FONT" ] || echo "font: wide, a stress run (a wide stack, Verdana first, plus letter-spacing 0.04em; the face actually drawn is not detected; Verdana is wider than Segoe UI; the real Segoe UI check is still owed on Windows)" >&2

PROFILE="$(mktemp -d "${TMPDIR:-/tmp}/settings-layout.XXXXXX")"
LOG="$PROFILE/vite.log"
CHROME_LOG="$PROFILE/chrome.log"
SERVER=""

cleanup() {
  if [ -n "$SERVER" ]; then
    pkill -P "$SERVER" 2>/dev/null || true
    kill "$SERVER" 2>/dev/null || true
  fi
  if command -v trash >/dev/null 2>&1; then
    trash "$PROFILE" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if curl -s -o /dev/null "http://127.0.0.1:$PORT/settings.html"; then
  echo "port $PORT is already in use: stop the server on it first" >&2
  exit 1
fi

cd "$ROOT"
npx --no-install vite --port "$PORT" --strictPort --host 127.0.0.1 >"$LOG" 2>&1 &
SERVER=$!

ready=""
for _ in $(seq 1 60); do
  if curl -s -o /dev/null "http://127.0.0.1:$PORT/settings.html"; then
    ready="1"
    break
  fi
  sleep 0.5
done
if [ -z "$ready" ]; then
  echo "the Vite server did not start on port $PORT; its log:" >&2
  tail -20 "$LOG" >&2
  exit 1
fi

# The check itself: plain Node, reading the measurement from argv. Each row is held to the rule the brief states; the stress row must wrap and keep its control beside its text.
CHECK_JS='
const m = JSON.parse(process.argv[1]);
const page = process.argv[2];
const stress = process.argv[3] === "1";
const widths = process.argv[4] === "1";
const place = process.argv[5] || page;
const failures = [];
const fail = (msg) => failures.push(`${page}: ${msg}`);
if (m.width !== 415) fail(`the frame is ${m.width} px wide, not 415`);
if (m.scrollWidth > 415) fail(`the page scrolls sideways: ${m.scrollWidth} px wide`);
if (m.allRows.length === 0 && m.plain.length === 0) fail("no rows were measured");
// A place that has short rows (a switch or a chip beside its label) must measure at least that many, and one with pop-ups at least that many pickers: if `.st-short` stops
// being applied, or the selects leave the rows the picker rule reads, zero measured rows must fail rather than pass every assertion below for want of input.
const MIN_SHORT = {"services":7,"agents":3,"devices":1,"general":6,"chat/sidekick":14,"chat/yourai":7,"chat/localmodels":4};
const MIN_PICKERS = {"general":2,"chat/yourai":4};
if (place in MIN_SHORT) {
  if (m.rows.length === 0) fail("no rows were measured: the short rows of this place are missing");
  else if (m.rows.length < MIN_SHORT[place]) fail(`only ${m.rows.length} short rows were measured, at least ${MIN_SHORT[place]} are expected`);
}
if (place in MIN_PICKERS && m.pickers.length < MIN_PICKERS[place]) fail(`only ${m.pickers.length} pickers were measured, at least ${MIN_PICKERS[place]} are expected`);
m.allRows.forEach((x) => {
  if (x.overflow || x.right > 415.5) fail(`row "${x.label}" ends at ${Math.round(x.right)} px and overflows at 415`);
});
if (stress && m.stacked.length === 0) fail("the stacked probe is missing");
m.plain.forEach((p) => {
  if (p.overflow || p.right > 415) fail(`a plain row ends at ${Math.round(p.right)} px and overflows at 415`);
  if (widths) console.log(`${page} plain row: ${Math.round(p.width)} px wide, ends at ${Math.round(p.right)} px`);
});
m.stacked.forEach((s) => {
  if (s.overflow || s.right > 415) fail(`the stacked row with a 46-character word ends at ${Math.round(s.right)} px and overflows at 415`);
});
if (page === "devices" && m.machines.length === 0) fail("no machine row is measured on Devices");
if (stress && page === "devices" && !m.machines.some((x) => x.name.length > 40)) fail("the long-named machine is missing from the stress sample");
m.machines.forEach((x) => {
  const name = `machine "${x.name.slice(0, 24)}"`;
  if (x.overflow || x.nameRight > x.rowRight + 0.5) fail(`${name}: its name ends at ${Math.round(x.nameRight)} px, past its row`);
  if (x.chipRight > x.rowRight + 0.5 || x.buttonRight > x.rowRight + 0.5) fail(`${name}: its state chip or button ends past the right edge of the row`);
  if (x.name.length > 40 && x.lines < 2) fail(`${name}: its long name does not wrap (${x.lines} line)`);
  if (widths) console.log(`${page} ${name}: name ${x.lines} line(s) ending at ${Math.round(x.nameRight)} px, chip ${Math.round(x.chipWidth)} px, button ${Math.round(x.buttonWidth)} px`);
});
if (place === "devices forget") {
  const long = m.machines.find((x) => x.name.length > 40);
  if (!long) fail("the long-named machine is missing in the Forget run");
  else if (long.buttons !== 2) fail(`the long-named machine shows ${long.buttons} button(s) in its confirm state, not 2 (Forget and Keep)`);
}
m.helps.forEach((h) => {
  const name = `help line of "${h.label}"`;
  if (!h.after) fail(`${name} comes before its control in the document`);
  if (!h.below) fail(`${name} is not below its control`);
  if (h.overflow || h.helpRight > h.rowRight + 0.5) fail(`${name} ends at ${Math.round(h.helpRight)} px, past its row`);
});
if (page === "general") {
  // The help lines of the rows that are not short are measured: the rule needs them (a help line back inside its label leaves this list empty).
  if (m.helps.length < 1) fail("no help line of a row that is not short is measured on General: a help line must come after its control, not inside the label");
  const tuck = m.pickers.find((p) => p.label.indexOf("Tuck the island away") === 0);
  if (!tuck) fail("Tuck the island away is not measured");
  else {
    if (!tuck.underAfter) fail("Tuck the island away has no help line after its pop-up (the help must come after the control)");
    if (tuck.stacked && tuck.gap > 12) fail(`Tuck the island away stacks but its pop-up is ${Math.round(tuck.gap)} px under the label text, not directly under it`);
  }
}
m.pickers.forEach((p) => {
  const name = `picker "${p.label}"`;
  if (p.overflow || !p.insideCard) fail(`${name}: its select ends at ${Math.round(p.select.right)} px, outside its card or its row`);
  if (widths) console.log(`${page} ${name}: select ${Math.round(p.width)} px, label ${Math.round(p.natural)} px on one line, ${p.stacked ? "stacked under" : "beside"} its label (gap ${Math.round(p.gap)} px)`);
});
if (place === "chat/localmodels" && !m.rows.some((r) => r.chip === "Running, no models yet")) fail("no server running with no models is measured on Local models");
m.rows.forEach((r, i) => {
  const name = `row ${i} "${r.label}"`;
  if (!r.first || !r.control || !r.block) { fail(`${name}: a box is missing`); return; }
  if (r.overflow) fail(`${name} overflows its row`);
  if (widths) console.log(`${page} ${name}: label ${Math.round(r.labelWidth)} px, control ${Math.round(r.controlWidth)} px`);
  if (r.probe) {
    // The probe (stress only): its label is one line and keeps 6em beside the nowrap buttons; its group wraps inside its own control, so no centre rule applies.
    if (r.lines !== 1) fail(`${name} wraps: a normal label fits beside the nowrap buttons`);
    if (r.labelWidth < 6 * r.em) fail(`${name}: its label is ${Math.round(r.labelWidth)} px, under 6em (${Math.round(6 * r.em)} px) beside a wide control`);
    return;
  }
  if (stress && i === 0) {
    if (r.lines < 2) fail(`${name}: the long label does not wrap (${r.lines} line)`);
    if (r.control.top < r.block.top - 4 || r.control.bottom > r.block.bottom + 4) fail(`${name}: the control is not beside its label`);
    return;
  }
  if (r.lines !== 1) {
    // A label may wrap only when its text would not fit beside the control; then the control stays beside the wrapped label.
    if (r.natural <= r.labelWidth + 1) fail(`${name} wraps though its text (${Math.round(r.natural)} px) fits in ${Math.round(r.labelWidth)} px beside the control`);
    const mid = (r.control.top + r.control.bottom) / 2;
    if (mid < r.block.top || mid > r.block.bottom) fail(`${name}: its control is not beside its wrapped label`);
    return;
  }
  const centre = (r.control.top + r.control.bottom) / 2;
  if (centre < r.first.top || centre > r.first.bottom) fail(`${name}: its control centre is not on the label\x27s first line`);
});
if (failures.length) { for (const f of failures) console.error(f); process.exit(1); }
console.log(`${place}: ${m.rows.length} rows, ${m.pickers.length} pickers ok${stress ? " (stress: the long label wraps, no sideways scroll)" : ""}`);
'

# One headless Chrome run with the same flags as render-settings.sh. Its stderr goes to chrome.log, and the last lines of it are shown when a run gives no measurement.
chrome() {
  local win_w="$1"; shift
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --no-first-run --disable-extensions \
    --user-data-dir="$PROFILE" --window-size="$win_w,$HEIGHT" --virtual-time-budget=5000 "$@" 2>>"$CHROME_LOG"
}

# One measurement: draws $3 in a headless Chrome of the frame's width and checks it against the rules. $1 is the page, $2 the label for a message, $4 the place the rules read.
check_place() {
  local page="$1" label="$2" url="$3" place="$4" dom got json
  dom="$(chrome "$WIDTH" --dump-dom "$url" || true)"
  if ! grep -q 'id="layout-check"' <<<"$dom"; then
    dom="$(chrome "$WIDTH" --dump-dom "$url" || true)"
  fi
  got="$(grep -o 'id="frame-width">[0-9]*<' <<<"$dom" | grep -o '[0-9][0-9]*' | head -1 || true)"
  json="$(grep -o 'id="layout-check"[^>]*>[^<]*' <<<"$dom" | sed 's/^[^>]*>//' | head -1 || true)"
  if [ -z "$json" ] || [ -z "$got" ]; then
    echo "$label: Chrome produced no measurement ($url). The last lines of its log:" >&2
    tail -5 "$CHROME_LOG" >&2
    failed=1
    return 0
  fi
  if [ "$got" != "$WIDTH" ]; then
    echo "$label: the frame is $got px wide, not $WIDTH ($url)" >&2
    failed=1
    return 0
  fi
  if ! node -e "$CHECK_JS" "$json" "$page" "${STRESS:+1}" "${SHOW_WIDTHS:+1}" "$place"; then
    failed=1
  fi
}

failed=0
for place in $PLACES; do
  page="${place%%/*}"
  tab=""
  case "$place" in */*) tab="${place#*/}" ;; esac
  for theme in $THEMES; do
    url="http://127.0.0.1:$PORT/settings.html?shot=$WIDTH&h=$HEIGHT&sample=ready&page=$page&theme=$theme&measure=switchrows"
    [ -z "$tab" ] || url="$url&tab=$tab"
    [ -z "$STRESS" ] || url="$url&stress"
    [ -z "$FONT" ] || url="$url&font=$FONT"
    check_place "$page" "$place $theme${STRESS:+ stress}" "$url" "$place"
    # The Forget confirm (stress, Devices): the long-named machine's Forget is pressed (measure=switchrows&forget) and its two buttons are measured.
    if [ "$place" = "devices" ] && [ -n "$STRESS" ]; then
      check_place "$page" "devices $theme stress forget" "$url&forget" "devices forget"
    fi
  done
done

# The keyboard check (devpanel.ts reportTabFocus, `measure=tabfocus`): on the AI and chat page a tab chosen from the keyboard leaves the focus on the tab menu when the tab bar
# is narrow (the 415 frame: the buttons are hidden, the menu is the keyboard's control) and on the selected tab when it is wide (the 720 frame).
TAB_CHECK_JS='
const m = JSON.parse(process.argv[1]);
const want = process.argv[2];
const fails = [];
if (m.width !== Number(process.argv[4])) fails.push(`the frame is ${m.width} px wide, not ${process.argv[4]}`);
if (!m.chosen) fails.push("no tab was chosen to test");
if (want === "auto") {
  // The real minimum (415): whichever way the bar fits there (a wide face can turn it narrow), the focus follows the path that was taken.
  if (m.narrow && m.focusedTag !== "SELECT") fails.push(`the bar is narrow but the focus is on ${m.focusedTag || "nothing"}, not the tab menu`);
  if (!m.narrow && (m.focusedRole !== "tab" || m.focusedSelected !== "true")) fails.push(`the bar is wide but the focus is on ${m.focusedTag || "nothing"} (${m.focusedRole || "no role"}), not the selected tab`);
} else if (want === "narrow") {
  if (!m.narrow) fails.push("the tab bar is not narrow at this width, so the menu path was not tested");
  if (m.focusedTag !== "SELECT") fails.push(`after the choice the focus is on ${m.focusedTag || "nothing"}, not the tab menu`);
} else {
  if (m.narrow) fails.push("the tab bar is narrow at this width, so the button path was not tested");
  if (m.focusedRole !== "tab" || m.focusedSelected !== "true") fails.push(`after the choice the focus is on ${m.focusedTag || "nothing"} (${m.focusedRole || "no role"}), not the selected tab`);
}
if (fails.length) { for (const f of fails) console.error(`${process.argv[3]} tab focus at ${m.width} px: ${f}`); process.exit(1); }
console.log(`${process.argv[3]} tab focus at ${m.width} px: ${want === "narrow" || (want === "auto" && m.narrow) ? "the tab menu" : "the selected tab"} keeps the focus`);
'

# The narrow case is the Cat page at 360 px, below the window's 415 px minimum: at 415 the tab bars (the Cat's and the AI and chat's) fit their labels, so they never turn
# narrow there (measured), and the menu path would not run. 360 px is the narrowest frame at which the Cat page's bar turns narrow. The two "auto" cases run at the real 415 px
# minimum and hold whichever path the bar takes there (with --font wide it may turn narrow).
# The frame is measured the moment it loads, and a loaded machine can catch the shell before its tab bar has settled (the focus then reads as BODY): a failed tab-focus case is
# measured again, up to three times, and fails only when every attempt fails. A real regression fails all three.
for case in "360 cat look narrow" "415 cat look auto" "415 chat yourai auto" "720 chat yourai wide"; do
  set -- $case
  tabw="$1"; tabpage="$2"; tabtab="$3"; want="$4"
  url="http://127.0.0.1:$PORT/settings.html?shot=$tabw&h=$HEIGHT&sample=ready&page=$tabpage&theme=dark&tab=$tabtab&measure=tabfocus"
  [ -z "$FONT" ] || url="$url&font=$FONT"
  passed=""
  for attempt in 1 2 3; do
    dom="$(chrome "$tabw" --dump-dom "$url" || true)"
    if ! grep -q 'id="layout-check"' <<<"$dom"; then
      dom="$(chrome "$tabw" --dump-dom "$url" || true)"
    fi
    json="$(grep -o 'id="layout-check"[^>]*>[^<]*' <<<"$dom" | sed 's/^[^>]*>//' | head -1 || true)"
    if [ -z "$json" ]; then
      echo "$tabpage/$tabtab tab focus at $tabw px: Chrome produced no measurement ($url). The last lines of its log:" >&2
      tail -5 "$CHROME_LOG" >&2
      continue
    fi
    if node -e "$TAB_CHECK_JS" "$json" "$want" "$tabpage/$tabtab" "$tabw" 2>"$PROFILE/tab-attempt.txt"; then
      passed="1"
      break
    fi
    [ "$attempt" -lt 3 ] || cat "$PROFILE/tab-attempt.txt" >&2
  done
  [ -n "$passed" ] || failed=1
done

if [ "$failed" -ne 0 ]; then
  echo "layout FAILED" >&2
  exit 1
fi
echo "layout ok"
