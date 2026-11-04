#!/usr/bin/env bash
# The site's checks (docs/, spec "D stage 1", section 5):
#   1. the committed bundle, docs/assets/cats.js and cats.css, is what a fresh build makes (windows/vite.site.config.ts, into a temporary folder);
#   2. the pages make no request to another host and set nothing on the visitor: no script, style, font or image from outside, no @import, no fetch, no cookie or storage;
#      a link (<a href>) may go to GitHub or to the credits' author; every picture has alt text; the old character's name is nowhere, and Coucou's only in the credits;
#      no AudioContext, `new Audio(`, `new Image(`, ping, meta refresh or srcset candidate reaches out, and no picture in assets/img, or its metadata, names an outside address.
#   bash scripts/check-site.sh                              both checks (needs windows/node_modules)
#   SITE_DIR=<folder> bash scripts/check-site.sh --pages-only   only the second, on another folder (scripts/test-check-site.sh does)
set -uo pipefail
cd "$(dirname "$0")/.."
SITE="${SITE_DIR:-docs}"
LINK_HOSTS='github.com|louisraille.fr'   # the hosts an <a href> may name
OLD="mo""chi"                            # the old character's name, in two halves so that no search for it finds this file
fail=0
bad() { echo "✗ $1"; fail=1; }

# A file as one line, so that a tag split over several lines is matched too.
flat() { tr '\r\n\t' '   ' < "$1"; }
# The page without its credits section (the one place the original project is named).
outside_credits() { flat "$1" | awk '{ s = index($0, "<section id=\"credits\""); if (s) { r = substr($0, s); e = index(r, "</section>"); $0 = substr($0, 1, s - 1) substr(r, e + 10) } print }'; }

# The first candidate of a srcset or imagesrcset attribute in <tag> that points away (http, https, //, data or javascript), printed; none: returns 1. The second candidate is the
# one a check on the attribute's start misses.
srcset_outside() {
  local attr c
  while IFS= read -r attr; do
    attr="${attr#*=}"; attr="${attr#"${attr%%[![:space:]]*}"}"; attr="${attr#[\"\']}"; attr="${attr%[\"\']}"
    while IFS= read -r c; do
      c="${c#"${c%%[![:space:]]*}"}"; c="${c%%[[:space:]]*}"
      case "$(printf '%s' "$c" | tr 'A-Z' 'a-z')" in
        http:*|https:*|//*|data:*|javascript:*) printf '%s\n' "$c"; return 0 ;;
      esac
    done < <(printf '%s\n' "$attr" | tr ',' '\n')
  done < <(grep -oiE '(image)?srcset[[:space:]]*=[[:space:]]*("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]>]+)' <<< "$1")
  return 1
}

# Pictures: nothing in a picture or in its metadata may point away. A PNG's XMP block and an SVG name W3C and Adobe namespaces in xmlns declarations, which are names and not
# requests, so those are taken out first; any other address fails, and in an SVG so does anything that runs or loads (a script, a foreignObject, an event handler, @import, an
# external href, javascript: or data:).
images() {
  local f t dir="$SITE/assets/img"
  [ -d "$dir" ] || return 0
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    t="$(LC_ALL=C tr -c '[:print:]' ' ' < "$f" | LC_ALL=C sed -E 's/xmlns(:[A-Za-z0-9_.-]+)?[[:space:]]*=[[:space:]]*("http:\/\/www\.w3\.org\/[A-Za-z0-9.\/_#-]*"|'"'"'http:\/\/www\.w3\.org\/[A-Za-z0-9.\/_#-]*'"'"'|"http:\/\/ns\.adobe\.com\/[A-Za-z0-9.\/_#-]*"|'"'"'http:\/\/ns\.adobe\.com\/[A-Za-z0-9.\/_#-]*'"'"'|"adobe:ns:meta\/")//g')"
    grep -qiE 'https?://' <<< "$t" && bad "$f: an outside address in the picture or its metadata"
    case "$f" in
      *.svg|*.SVG)
        grep -qE '(^|[^A-Za-z0-9_:])//[A-Za-z0-9-]+\.[A-Za-z]{2,}' <<< "$t" && bad "$f: an SVG with an outside address (//host)"
        grep -qiE '<script|<foreignObject|[[:space:]]on[a-z]+[[:space:]]*=|@import|javascript:|data:' <<< "$t" && bad "$f: an SVG that runs or embeds something (a script, foreignObject, event handler, @import, javascript: or data:)"
        grep -qiE 'href[[:space:]]*=[[:space:]]*["'"'"']?[[:space:]]*[^#"'"'"' >]' <<< "$t" && bad "$f: an SVG with an external href"
        ;;
    esac
  done
  [ "$fail" -eq 0 ] && echo "✓ $dir: no outside address in any picture or its metadata"
}

pages() {
  local f html=0
  for f in "$SITE"/*.html; do [ -f "$f" ] && html=$((html + 1)); done
  [ "$html" -ge 2 ] || bad "$SITE has fewer than two pages (index.html and testers.html)"
  for f in "$SITE"/*.html "$SITE/site.css" "$SITE/assets/cats.js" "$SITE/assets/cats.css"; do
    [ -f "$f" ] || { bad "$f is missing"; continue; }
    local t; t="$(flat "$f")"
    # Anything that loads or sends something from another place.
    grep -q '@import' <<< "$t" && bad "$f: @import"
    grep -qiE 'url\([[:space:]]*["'"'"']?[[:space:]]*(https?:|//)' <<< "$t" && bad "$f: url() of another host"
    grep -qE '(^|[^A-Za-z0-9_])(fetch|importScripts)[[:space:]]*\(|XMLHttpRequest|sendBeacon|WebSocket|EventSource' <<< "$t" && bad "$f: a network call (fetch, XMLHttpRequest, sendBeacon, WebSocket, EventSource or importScripts)"
    grep -qE 'document\.cookie|localStorage|sessionStorage|indexedDB' <<< "$t" && bad "$f: a cookie or browser storage"
    grep -qE 'AudioContext|new[[:space:]]+((window|self|globalThis)\.)?(Audio|Image)[[:space:]]*\(' <<< "$t" && bad "$f: media that a script loads or plays (AudioContext, new Audio or new Image)"
    # The old character's name is nowhere; Coucou's only in the credits section of a page.
    grep -qi "$OLD" <<< "$t" && bad "$f: the old character's name"
    case "$f" in
      *.html)
        grep -qi 'coucou' <<< "$(outside_credits "$f")" && bad "$f: Coucou's name outside the credits section"
        # Every tag but <a> may not point anywhere but into docs/: no http, https, //, data or javascript value.
        local tag href host cand
        while IFS= read -r tag; do
          case "$tag" in
            "<a "*) ;;
            *) grep -qiE '=[[:space:]]*["'"'"']?[[:space:]]*(https?:|//|data:|javascript:)' <<< "$tag" && bad "$f: a tag that loads from outside: ${tag:0:90}" ;;
          esac
          # On any tag, <a> included: a ping (the browser posts to it), a meta refresh (it redirects the visitor), and every candidate of a srcset.
          grep -qiE '(^|[[:space:]])ping[[:space:]]*=' <<< "$tag" && bad "$f: a ping attribute (the browser would post to it): ${tag:0:90}"
          grep -qiE 'http-equiv[[:space:]]*=[[:space:]]*["'"'"']?[[:space:]]*refresh' <<< "$tag" && bad "$f: a meta refresh (it redirects the visitor): ${tag:0:90}"
          cand="$(srcset_outside "$tag")" && bad "$f: a srcset candidate that loads from outside: $cand"
        done < <(grep -oiE '<[a-z][^>]*>' <<< "$t")
        # A link may name only the allowed hosts.
        while IFS= read -r href; do
          href="${href#*=}"; href="${href#[[:space:]]}"; href="${href#[\"\']}"; href="${href%%[\"\' >]*}"
          href="$(printf '%s' "$href" | tr 'A-Z' 'a-z')"
          case "$href" in
            http://*|https://*|//*)
              host="${href#*//}"; host="${host%%[/?#]*}"
              grep -qE "^(www\.)?($LINK_HOSTS)$" <<< "$host" || bad "$f: a link to $host" ;;
            javascript:*|data:*) bad "$f: a link that runs or embeds: ${href:0:40}" ;;
          esac
        done < <(grep -oiE '<a [^>]*>' <<< "$t" | grep -oiE 'href[[:space:]]*=[[:space:]]*("[^"]*"|'"'"'[^'"'"']*'"'"'|[^ >]+)')
        grep -qiE '<(iframe|embed|object|form|video|audio|source|track|frame)[ >]' <<< "$t" && bad "$f: an element that embeds or collects (iframe, embed, object, form, video, audio, source, track, frame)"
        # Pictures: an <img> has alt text, a <canvas> a label or is hidden from readers.
        while IFS= read -r tag; do
          grep -qiE 'alt[[:space:]]*=[[:space:]]*"[^"]+"' <<< "$tag" || bad "$f: a picture without alt text: ${tag:0:90}"
        done < <(grep -oiE '<img[ >][^>]*>?' <<< "$t")
        while IFS= read -r tag; do
          grep -qiE 'aria-label[[:space:]]*=[[:space:]]*"[^"]+"|aria-hidden[[:space:]]*=[[:space:]]*"true"' <<< "$tag" || bad "$f: a canvas without a label: ${tag:0:90}"
        done < <(grep -oiE '<canvas[ >][^>]*>?' <<< "$t")
        grep -qiE 'name="viewport"' <<< "$t" || bad "$f: no viewport meta (the page must work on a phone)"
        ;;
      *)
        grep -qi 'coucou' <<< "$t" && bad "$f: Coucou's name"
        # In a script or a style sheet no address at all: nothing is fetched, and nothing points away.
        grep -qiE 'https?://' <<< "$t" && bad "$f: an address (http:// or https://)"
        ;;
    esac
  done
  [ "$fail" -eq 0 ] && echo "✓ $SITE: no outside request, no cookie, alt text everywhere, the names as they should be"
}

bundle() {
  [ -d windows/node_modules ] || { bad "windows/node_modules is missing: run npm ci in windows/"; return; }
  local tmp out got f
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-site-bundle.XXXXXX")"
  mkdir "$tmp/out"
  out="$(cd "$tmp/out" && { pwd -W 2>/dev/null || pwd; })"   # a path the build understands on Windows too
  if ! (cd windows && npx --no-install vite build --config vite.site.config.ts --outDir "$out" > "$tmp/build.log" 2>&1); then
    cat "$tmp/build.log"; bad "the site's bundle does not build"; rm -rf "$tmp"; return
  fi
  got="$(cd "$tmp/out" && ls | tr '\n' ' ')"
  [ "$got" = "cats.css cats.js " ] || bad "the build makes [$got], expected [cats.css cats.js ]"
  for f in cats.js cats.css; do
    # Compared without carriage returns, so a Windows checkout's line endings do not matter.
    if [ -f "$tmp/out/$f" ] && [ -f "docs/assets/$f" ] && cmp -s <(tr -d '\r' < "$tmp/out/$f") <(tr -d '\r' < "docs/assets/$f"); then :
    else bad "docs/assets/$f is not what a fresh build makes: run  cd windows && npx --no-install vite build --config vite.site.config.ts  and commit it"; fi
  done
  rm -rf "$tmp"
  [ "$fail" -eq 0 ] && echo "✓ docs/assets/cats.js and cats.css are what a fresh build makes"
}

case "${1:-}" in
  --pages-only) pages; images ;;
  "") bundle; pages; images ;;
  *) echo "usage: bash scripts/check-site.sh [--pages-only]" >&2; exit 2 ;;
esac
exit "$fail"
