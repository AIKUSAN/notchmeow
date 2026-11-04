# The shelf contract

Sub-project G1 (`docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md`, "G1-0") parks files in the notch. Three rules are the same on both apps and are written once, here and in `tests/fixtures/shelf/`. The macOS app (Swift) and the Windows/Linux app (TypeScript, with a Rust twin for the file on disk) each reimplement them natively and test themselves against the fixtures, the same way both apps test the AI layer (`tests/fixtures/ai/`).

**`tests/fixtures/shelf/reference.py` is the tie-breaker.** It is a small Python program (standard library only) with the three rules written as plainly as possible. The two JSON files are written by `build_cases.py`, with every expected answer typed out by hand and none computed by the reference, so the fixtures and the reference check each other. If an app and a fixture disagree, the app is wrong.

The look, the drag, the bookmark itself and the share sheet are not tested here. This contract is only the arithmetic and the clean-up that both apps must agree on.

## Run it

```
bash scripts/test-shelf-contract.sh                       # the reference against both fixtures, then the no-drift check
python3 tests/fixtures/shelf/build_cases.py               # rewrite the two JSON files after an intended change
python3 tests/fixtures/shelf/build_cases.py --check
```

Python 3, nothing to install. CI runs the script next to the AI contract. Both app plans add their own replay of the two files (`shelf-cases.json`, `zone-cases.json`) to their tests. Windows/Linux: `windows/scripts/cat-tests/shelf-rules.test.mjs` (`npm run check:cat`) replays both through `windows/src/shelf/rules.ts`, and `cargo test -p notchmeow shelf::` replays `shelf-cases.json` through `windows/src-tauri/src/shelf.rs` (the Rust twin leaves `zoneAt` to the page, which decides the half). The Mac's is `scripts/test-shelf-rules.sh` (`NotchBuddy/Sources/App/ShelfRules.swift`, with a strict JSON reader of its own: Foundation's `JSONSerialization` repairs a lone surrogate, may strip a byte order mark and has its own idea of big numbers, so the fixtures could not be replayed through it).

## The files

| File | Pins |
|---|---|
| `zone-cases.json` | `cases[]` of `{name, x?, width?, out}`: `zoneAt(x, width)`. A missing key stands for a value JSON cannot hold; the cases with text, `null` or `true` in its place pin the refusal. `out` is `"ask"`, `"shelf"` or `null`. |
| `shelf-cases.json` | The constants (`max`, `idPattern`, `nameMax`, `linkMax`, `numberMax`), `cleanCases[]` of `{name, raw, out}` (`shelfClean`), `addCases[]` of `{name, items, incoming, out: {items, results}}` (`shelfAdd`) and `parseCases[]` of `{name, text | hex, out}`: the bytes of a file (`text` when they are UTF-8, else `hex`) to the items it holds (`readShelf`). |
| `reference.py` | The three rules, the replay of both files, and a seeded fuzz (3000 hostile shelves, 1500 drops). |
| `build_cases.py` | Writes the two JSON files (`--check` fails on drift). |

## The rules

### `zoneAt(x, width)`: which half the pointer is in

The pointer's horizontal position `x`, measured from the island's left edge, and the island's `width`, both in points. The island is split at its centre line.

| Input | Answer |
|---|---|
| `0 <= x <= width / 2` | `ask` (the centre line itself is Ask: the drop that exists today) |
| `width / 2 < x <= width` | `shelf` |
| `x < 0` or `x > width` | `null`: outside the island, so no half |
| `width <= 0`, or either is not a finite number (text, `null`, a boolean, a list), or either is beyond 9007199254740991 (`numberMax`, so a 400-digit integer is outside too) | `null` |

On the Mac `x` comes from the drag's own location; on Windows and Linux from the last polled cursor position, because the drop event carries paths only. The vertical position is not part of the rule: each app already knows whether the pointer is over the island.

### `shelfClean(raw)`: how `shelf.json` is read

`shelf.json` is `{"version": 1, "items": [ ... ]}`. An app reads the file as plain JSON values, runs this rule and uses only the result. Anything else (not an object, `items` not a list, text, `null`) is an empty shelf. The file's `version` and any unknown field are ignored and not written back.

**An unreadable file is an empty shelf.** The bytes are read as strict UTF-8 (a byte order mark is not stripped), and the JSON must parse with no `NaN`, `Infinity` or text after the value. An empty file, a file of only a byte order mark or white space, a truncated file, invalid UTF-8, a top-level value that is not an object (a list included) all give an empty shelf. A repeated key keeps its last value, as `JSON.parse` does. The `parseCases` pin these outcomes. An app that finds an unreadable `shelf.json` must keep a backup copy of the unreadable file before writing a new one (for example `shelf.json.bad-<time>`).

One stored item is **dropped** unless all of this holds, and otherwise **cleaned** to exactly these fields, in this order:

| Field | Rule |
|---|---|
| `id` | A string matching `[A-Za-z0-9_-]{1,64}` as a **whole** string (a trailing newline does not match), and not a Windows device name (see `name`). It is also the name of the item's folder under `shelf/`. Ids compare case-insensitively (step 2). |
| `name` | A string of 1 to 255 **code points** (not UTF-16 units, bytes or grapheme clusters). Refused, and the item dropped, when it holds a control (Unicode category Cc), a format character (Cf: the bidi controls such as U+202E, the zero-width space U+200B, the BOM U+FEFF), a line or paragraph separator (U+2028, U+2029) or a lone surrogate (Cs); or a `/` or `\`; or it is made only of dots (`.`, `..`, `...`); or it ends in a dot or a space; or the part before its first dot, with trailing spaces trimmed, is a Windows device name: `CON`, `PRN`, `AUX`, `NUL`, `COM1` to `COM9` or `LPT1` to `LPT9`, and the superscript forms `COM¹`, `COM²`, `COM³`, `LPT¹`, `LPT²`, `LPT³`, ASCII case-insensitively (`con.txt`, `CON .txt`, `NUL.tar.gz`, `COM¹` and `lpt³.log` are refused; `CONSOLE` and `COM0` are not). |
| `size` | A whole number from 0 to 9007199254740991 (`5` and `5.0` are the same number). Anything else becomes `0`. It is for display only. |
| `folder` | `true` only for the boolean `true`, else `false`. |
| `copy` | `true` only for the boolean `true`, else `false`. A copy lives in `shelf/<id>/<name>`; it has no `link`. A copy that is also a folder is **dropped** (a folder is only ever a link). |
| `link` | Present only when `copy` is `false`, and then required: a string of 1 to 8192 code points with no control character (U+0000 to U+001F and U+007F to U+009F) and no lone surrogate (Cs); the other name rules do not apply to a link. Format characters (Cf, such as U+202E) are allowed, because real paths can hold them. A link is never shown to the user; the name is. The Mac stores the base64 of a security-scoped bookmark here, Windows and Linux the path. This rule is structural only; each app checks the rest (a bookmark that resolves, an absolute path). |
| `addedAt` | The time the item was shelved, milliseconds since 1970: a whole number from 0 to 9007199254740991, else `0`. |

Then, on the items that survived:

1. **Newest first:** a stable sort by `addedAt`, largest first (equal times keep the file's order).
2. **Duplicates:** the first of each `id` stays (ids compare ASCII case-insensitively: `Abc` and `abc` are one id; the folding is ASCII lower-case only, because the id alphabet is `[A-Za-z0-9_-]`), and the first of each `link` (compared exactly, by code point sequence, case and all, not by Unicode normalisation: NFC `é` and NFD `e` + combining accent are two different links; a copy has no link so never clashes). Because of step 1, the newer duplicate wins. This is **one pass in sorted order**: an item skipped for a repeated link reserves nothing, so its `id` is not reserved and a later item with that `id` can stay. (The example `A(id a, link /x, t3)`, `B(id b, link /x, t2)`, `C(id b, link /y, t1)` keeps `[A, C]`.)
3. **Cap:** the first 30. A hostile file with 300 items keeps the 30 newest.

The result is the shelf. Cleaning a clean shelf changes nothing.

**Ports.** Swift's `sort` does not promise to be stable, so the Swift port sorts by `addedAt`, largest first, and then by the item's index in the file. The fixtures check the order of the items, not the order of the keys inside an item: key order is not enforced by the fixtures.

**File names.** `name` is limited to 255 code points, and 255 code points can be up to 1020 UTF-8 bytes (4 bytes each), more than many filesystems allow for one name. The contract does not limit bytes, so the app that creates a copy's folder must handle a name its filesystem refuses. The character classes are Unicode's general categories; each port uses its own Unicode tables, and the fixtures pin the characters listed here.

### `shelfAdd(items, incoming)`: files dropped on the Shelf half

`items` is the shelf as stored (it is cleaned first). `incoming` is the list of items for the files of one drop, in the order the app wants them shown, each built by the app with `addedAt` set to now. The answer is `{items, results}` with one word per incoming item, in order:

| Word | When (checked in this order) |
|---|---|
| `invalid` | `incoming[i]` is not a list item `shelfClean` would keep (this includes a non-object). |
| `duplicate` | Its `id` or `link` is already on the shelf, or was added earlier in the same drop. A re-dropped file on a full shelf says `duplicate`, not `full`. |
| `full` | The shelf already holds 30, counting what this drop has added. Nothing already on the shelf is ever removed; the app shows a short note when any word is `full`. |
| `added` | Otherwise. |

The new shelf is `shelfClean` of the added items followed by the old ones, so the added ones are first (newest) and everything is in `shelfClean`'s order. If `incoming` is not a list it is empty. Add never removes an item, so a case-variant id is `duplicate` even when newer.

### The exception to "nothing old is removed silently"

The spec says that nothing old is removed silently. This contract keeps that rule with one **exception**, approved by the owner at the checkpoint (2026-10-14):

- **Reading** `shelf.json` keeps the **30 newest** items. Only a hand-edited or corrupted file can hold more than 30, so this cap is the one place an old item leaves the shelf without a drop.
- **A drop on a full shelf never evicts.** It refuses the extra files with `full`, and the app shows the short note. Nothing already on the shelf is removed to make room.

## Decisions and open questions

These are choices the spec did not make. Each has the answer the plan assumed and the fixture pins it; a different answer is one edit in `reference.py` and `build_cases.py` (see the plan's "Open questions for the owner").

- The centre line belongs to **Ask**, the half whose behaviour already ships.
- An item is `{id, name, size, folder, copy, link?, addedAt}`; the spec names no fields.
- A **bad `size` or `addedAt` becomes 0** and the item stays (they are display and order only); a bad `id`, `name` or `link` drops the item (they are file system names and the way back to the original).
- Names and links are limited in **code points**, 255 and 8192, so all three languages count the same.
- A **duplicate** is the same id or the same `link`; the newer one stays. A cleaned file with more than 30 items keeps the 30 newest, but a **drop never evicts**: it refuses the extras (`full`).
- Windows' reserved names, a trailing dot or space, names made only of dots and format or separator characters are **refused** here, so every platform keeps the same items. The app that creates a copy's folder still handles what its filesystem refuses (see *File names*).
- An id that differs from another only in ASCII case is the same id: the newer item stays, as with any duplicate.
