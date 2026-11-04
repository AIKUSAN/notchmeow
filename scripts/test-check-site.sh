#!/usr/bin/env bash
# Proves that scripts/check-site.sh bites: a clean site passes, and each way a page could reach outside, set something on the visitor, lose its alt text or name the wrong project
# makes it fail with the right reason. It runs the pages check on small sites it builds in a temporary folder, so it needs no node_modules.
#   bash scripts/test-check-site.sh
set -uo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-test-site.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; failed=0

# A clean site: two pages, a style sheet and a bundle.
clean() {
  local d="$1"
  mkdir -p "$d/assets"
  cat > "$d/index.html" <<'HTML'
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>NotchMeow</title>
<link rel="stylesheet" href="assets/cats.css"><link rel="stylesheet" href="site.css"><script src="assets/cats.js" defer></script></head>
<body><main><img src="a.png" alt="A cat">
<canvas aria-hidden="true"></canvas><canvas aria-label="A cat"></canvas>
<p><a href="https://github.com/AIKUSAN/notchmeow">GitHub</a> <a href="testers.html">Testers</a></p>
<section id="credits"><p>Fork of Coucou by Louis Raillé. <a href="https://louisraille.fr">His site</a></p></section></main></body></html>
HTML
  cat > "$d/testers.html" <<'HTML'
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Testers</title><link rel="stylesheet" href="site.css"></head><body><p>Hello</p></body></html>
HTML
  echo 'body{color:red;background:url(assets/img/a.png)}' > "$d/site.css"
  echo ':root{--a:#fff}' > "$d/assets/cats.css"
  echo '(function(){var a=1;console.log(a)})()' > "$d/assets/cats.js"
  # Two pictures that name outside addresses only as namespaces: an SVG with xmlns, and a PNG with an XMP block (the real site's coats.png and plan-card.png have one).
  mkdir -p "$d/assets/img"
  echo '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 10 10"><defs><circle id="c" r="3"/></defs><use xlink:href="#c"/><rect width="10" height="10"/></svg>' > "$d/assets/img/a.svg"
  printf '\211PNG\r\n\032\n<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"></rdf:RDF></x:xmpmeta>\n' > "$d/assets/img/b.png"
}

# expect NAME EXIT-CODE WORD-IN-OUTPUT DIR
expect() {
  local name="$1" want="$2" word="$3" dir="$4" out code
  out="$(SITE_DIR="$dir" bash scripts/check-site.sh --pages-only 2>&1)"; code=$?
  if [ "$code" = "$want" ] && { [ -z "$word" ] || grep -qF -- "$word" <<< "$out"; }; then pass=$((pass + 1)); echo "ok   $name"
  else failed=$((failed + 1)); echo "FAIL $name (exit $code, wanted $want, looking for [$word])"; echo "$out" | sed 's/^/     /'; fi
}

# mutate NAME FILE 'text appended to the file' WORD
mutate() {
  local d="$TMP/$1"
  clean "$d"
  case "$3" in
    REPLACE:*) printf '%s' "${3#REPLACE:}" > "$d/$2" ;;
    *) printf '%s\n' "$3" >> "$d/$2" ;;
  esac
  expect "$1" 1 "$4" "$d"
}

clean "$TMP/clean"
expect "a clean site passes" 0 "✓" "$TMP/clean"

mutate "an image from another host"        index.html '<img src="https://cdn.example.com/a.png" alt="x">' "loads from outside"
mutate "a style sheet from another host"   index.html '<link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Inter">' "loads from outside"
mutate "a script with a protocol-relative address" index.html '<script src="//cdn.example.com/a.js"></script>' "loads from outside"
mutate "a data URI"                        index.html '<img src="data:image/png;base64,AAAA" alt="x">' "loads from outside"
mutate "a tag split over two lines"        index.html '<img
   src="https://cdn.example.com/a.png" alt="x">' "loads from outside"
mutate "an @import"                        site.css '@import url(more.css);' "@import"
mutate "a url() of another host"           site.css 'a{background:url("https://example.com/a.png")}' "url() of another host"
mutate "a fetch in the bundle"             assets/cats.js 'fetch("/data.json");' "network call"
mutate "an XMLHttpRequest in a page"       index.html '<script>new XMLHttpRequest()</script>' "network call"
mutate "a beacon"                          assets/cats.js 'navigator.sendBeacon("/x")' "network call"
mutate "a cookie"                          assets/cats.js 'document.cookie="a=1"' "cookie or browser storage"
mutate "local storage"                     assets/cats.js 'localStorage.setItem("a","1")' "cookie or browser storage"
mutate "an address in the bundle"          assets/cats.js 'var u="https://example.com/"' "an address"
mutate "a link to another host"            index.html '<a href="https://example.com/x">x</a>' "a link to example.com"
mutate "a link to another host, in capitals" index.html '<A HREF="HTTPS://EXAMPLE.COM/x">x</A>' "a link to example.com"
mutate "a link that looks like github"     index.html '<a href="https://github.com.evil.example/x">x</a>' "a link to github.com.evil.example"
mutate "a javascript link"                 index.html '<a href="javascript:alert(1)">x</a>' "a link that runs"
mutate "an iframe"                         index.html '<iframe src="x.html"></iframe>' "embeds or collects"
mutate "a form"                            index.html '<form action="x.html"></form>' "embeds or collects"
mutate "a picture without alt text"        index.html '<img src="b.png">' "without alt text"
mutate "a picture with empty alt text"     index.html '<img src="b.png" alt="">' "without alt text"
mutate "a canvas without a label"          index.html '<canvas></canvas>' "canvas without a label"
mutate "the old character's name"          testers.html '<p>Mo'"chi</p>" "the old character's name"
mutate "Coucou outside the credits"        testers.html '<p>A fork of Coucou</p>' "outside the credits"
mutate "Coucou in the bundle"              assets/cats.js 'var n="coucou"' "Coucou's name"
mutate "no viewport"                       testers.html 'REPLACE:<!doctype html><html lang="en"><head><meta charset="utf-8"><title>T</title></head><body><p>Hello</p></body></html>' "no viewport"

# Media a script loads or plays, a ping, a refresh, and every candidate of a srcset (the second one is the easy one to miss).
mutate "an AudioContext in the bundle"     assets/cats.js 'var a=new AudioContext();' "AudioContext, new Audio or new Image"
mutate "new Audio in a page"               index.html '<script>new Audio("a.mp3").play()</script>' "AudioContext, new Audio or new Image"
mutate "new Image in the bundle"           assets/cats.js 'var i=new Image();i.src="a.png";' "AudioContext, new Audio or new Image"
mutate "a ping on a link"                  index.html '<a href="testers.html" ping="/track">x</a>' "a ping attribute"
mutate "a ping to another host"            index.html '<A HREF="testers.html" PING="https://example.com/t">x</A>' "a ping attribute"
mutate "a meta refresh"                    index.html '<meta http-equiv="refresh" content="0;url=testers.html">' "a meta refresh"
mutate "a meta refresh, in capitals"       index.html '<META HTTP-EQUIV="Refresh" CONTENT="5">' "a meta refresh"
mutate "a second srcset candidate from another host" index.html '<img src="a.png" srcset="a.png 1x, https://cdn.example.com/b.png 2x" alt="x">' "a srcset candidate"
mutate "a second srcset candidate, protocol-relative" index.html '<img src="a.png" srcset="a.png 1x,//cdn.example.com/b.png 2x" alt="x">' "a srcset candidate"
mutate "a second srcset candidate, a data URI" index.html '<img src="a.png" srcset="a.png 1x, data:image/png;base64,AAAA 2x" alt="x">' "a srcset candidate"
mutate "an imagesrcset candidate"          index.html '<link rel="preload" as="image" imagesrcset="a.png 1x, https://cdn.example.com/b.png 2x">' "a srcset candidate"

# The pictures themselves, and their metadata.
mutate "an SVG that loads from another host" assets/img/a.svg '<image href="https://example.com/a.png"/>' "outside address in the picture"
mutate "an SVG with a protocol-relative address" assets/img/a.svg '<image href="//cdn.example.com/a.png"/>' "an SVG with an outside address"
mutate "an SVG with a script"              assets/img/a.svg '<script>1</script>' "runs or embeds"
mutate "an SVG with a foreignObject"       assets/img/a.svg '<foreignObject><p>x</p></foreignObject>' "runs or embeds"
mutate "an SVG with an event handler"      assets/img/a.svg '<rect onclick="x()"/>' "runs or embeds"
mutate "an SVG with an external href"      assets/img/a.svg '<use href="other.svg#a"/>' "an external href"
mutate "a PNG whose metadata names a host" assets/img/b.png 'Comment https://example.com/track' "outside address in the picture"
mutate "a PNG whose metadata uses an outside xmlns" assets/img/b.png '<x xmlns="https://tracker.example.com/t"/>' "outside address in the picture"
mutate "a PNG whose W3C xmlns carries an outside host" assets/img/b.png '<x xmlns="http://www.w3.org/https://tracker.example.com/t"/>' "outside address in the picture"
mutate "an unquoted second srcset candidate from another host" index.html '<img src="a.png" srcset=a.png,https://cdn.example.com/b.png 2x alt="x">' "a srcset candidate"
mutate "new window.Audio in a page"         index.html '<script>new window.Audio("a.mp3").play()</script>' "AudioContext, new Audio or new Image"
mutate "new self.Image in the bundle"      assets/cats.js 'var i=new self.Image();' "AudioContext, new Audio or new Image"

rm -rf "$TMP/one"; mkdir -p "$TMP/one"; echo '<html></html>' > "$TMP/one/index.html"
expect "a site with one page and no style sheet" 1 "is missing" "$TMP/one"

echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
