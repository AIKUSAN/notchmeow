// The link's file-name rules (docs/LINK-CONTRACT.md, "File names"): the name a received file is saved under, and the name to use when that one is taken. A port of `sanitize_name` and
// `unique_name` of tests/fixtures/link/reference.py, replayed against filename-cases.json. The invisible and whitespace sets are written out by hand, as the contract says: they do not
// follow a Unicode table. NFC and NFKC come from the `unicode-normalization` crate; the categories Cc, Cf, Zl and Zp are `char::is_control` and the table below (a Rust `&str` cannot hold a lone
// surrogate, Cs). Pure: no file, no clock.

use std::collections::HashSet;

use unicode_normalization::UnicodeNormalization;

pub const NAME_BYTES_MAX: usize = 200;
pub const EXT_BYTES_MAX: usize = 16;
pub const COLLISION_MAX: u32 = 9999;

/// Every Default_Ignorable code point of Unicode, and U+2800 (BRAILLE PATTERN BLANK). The same table as `INVISIBLE_RANGES` in the reference.
const INVISIBLE_RANGES: &[(u32, u32)] = &[
    (0x00AD, 0x00AD), (0x034F, 0x034F), (0x061C, 0x061C), (0x115F, 0x1160), (0x17B4, 0x17B5), (0x180B, 0x180F), (0x200B, 0x200F), (0x202A, 0x202E),
    (0x2060, 0x206F), (0x2800, 0x2800), (0x3164, 0x3164), (0xFE00, 0xFE0F), (0xFEFF, 0xFEFF), (0xFFA0, 0xFFA0), (0xFFF0, 0xFFF8), (0x1BCA0, 0x1BCA3),
    (0x1D173, 0x1D17A), (0xE0000, 0xE0FFF),
];

/// Unicode category Cf. Rust's standard library has no table for it.
const FORMAT_RANGES: &[(u32, u32)] = &[
    (0x00AD, 0x00AD), (0x0600, 0x0605), (0x061C, 0x061C), (0x06DD, 0x06DD), (0x070F, 0x070F), (0x0890, 0x0891), (0x08E2, 0x08E2), (0x180E, 0x180E),
    (0x200B, 0x200F), (0x202A, 0x202E), (0x2060, 0x2064), (0x2066, 0x206F), (0xFEFF, 0xFEFF), (0xFFF9, 0xFFFB), (0x110BD, 0x110BD), (0x110CD, 0x110CD),
    (0x13430, 0x1343F), (0x1BCA0, 0x1BCA3), (0x1D173, 0x1D17A), (0xE0001, 0xE0001), (0xE0020, 0xE007F),
];

fn in_ranges(c: char, ranges: &[(u32, u32)]) -> bool {
    let n = c as u32;
    ranges.iter().any(|&(lo, hi)| n >= lo && n <= hi)
}

/// A character that shows nothing: a code point of the invisible table. The file-name and the device-name rules both use it.
pub fn is_invisible(c: char) -> bool {
    in_ranges(c, INVISIBLE_RANGES)
}

/// Cc, Cf, Zl or Zp: a control, a format character, a line or a paragraph separator.
pub fn is_bad_category(c: char) -> bool {
    c.is_control() || in_ranges(c, FORMAT_RANGES) || c == '\u{2028}' || c == '\u{2029}'
}

/// U+0020 or a Zs character.
pub fn is_space(c: char) -> bool {
    matches!(c as u32, 0x20 | 0xA0 | 0x1680 | 0x2000..=0x200A | 0x202F | 0x205F | 0x3000)
}

/// The owner's whitespace set for file names (answer 2b): a run of these becomes one U+0020.
fn in_space_run(c: char) -> bool {
    matches!(c as u32, 0x09..=0x0D | 0x20 | 0x85 | 0xA0 | 0x1680 | 0x2000..=0x200A | 0x2028 | 0x2029 | 0x202F | 0x205F | 0x3000)
}

fn collapse(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut in_run = false;
    for c in s.chars() {
        if in_space_run(c) {
            if !in_run {
                out.push(' ');
            }
            in_run = true;
        } else {
            out.push(c);
            in_run = false;
        }
    }
    out
}

/// Spaces off the start; spaces and dots off the end.
fn trim(s: &str) -> String {
    let start = s.trim_start_matches(is_space);
    start.trim_end_matches(|c: char| c == '.' || is_space(c)).to_string()
}

const RESERVED: &[&str] = &[
    "CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$", "COM0", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT0", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6",
    "LPT7", "LPT8", "LPT9", "COM\u{b9}", "COM\u{b2}", "COM\u{b3}", "LPT\u{b9}", "LPT\u{b2}", "LPT\u{b3}",
];

/// A Windows device name as the part before the first dot, trailing spaces off, ASCII case-insensitively.
fn reserved(s: &str) -> bool {
    let stem = s.split('.').next().unwrap_or("").trim_end_matches(' ').to_ascii_uppercase();
    RESERVED.contains(&stem.as_str())
}

/// (stem, extension): the extension is the part from the last dot, only when it is at most 16 bytes and the dot is not the first character.
fn split_ext(name: &str) -> (&str, &str) {
    match name.rfind('.') {
        Some(i) if i > 0 && name.len() - i <= EXT_BYTES_MAX => (&name[..i], &name[i..]),
        _ => (name, ""),
    }
}

/// `name`, cut to 200 bytes at a code point, keeping an extension of up to 16 bytes; the spaces and dots the cut leaves at the end go.
fn cut(name: &str) -> String {
    if name.len() <= NAME_BYTES_MAX {
        return name.to_string();
    }
    let (stem, ext) = split_ext(name);
    let room = NAME_BYTES_MAX - ext.len();
    let mut out = String::new();
    for c in stem.chars() {
        if out.len() + c.len_utf8() > room {
            break;
        }
        out.push(c);
    }
    trim(&out) + ext
}

fn nfkc(s: &str) -> String {
    s.nfkc().collect()
}

fn illegal(c: char) -> char {
    if "<>:\"|?*".contains(c) { '_' } else { c }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Reject {
    NotText,
    Invisible,
    Separator,
    Empty,
}

impl Reject {
    pub fn as_str(self) -> &'static str {
        match self {
            Reject::NotText => "not-text",
            Reject::Invisible => "invisible",
            Reject::Separator => "separator",
            Reject::Empty => "empty",
        }
    }
}

/// The name a received file is saved under, or why it is refused. The checks run on the NFC and the NFKC form, the name that is kept is the NFC form.
pub fn sanitize_name(raw: &str) -> Result<String, Reject> {
    let nfc = collapse(&raw.nfc().collect::<String>());
    let kc = collapse(&nfkc(raw));
    if [&nfc, &kc].iter().any(|form| form.chars().any(|c| is_bad_category(c) || is_invisible(c))) {
        return Err(Reject::Invisible);
    }
    if [&nfc, &kc].iter().any(|form| form.chars().any(|c| c == '/' || c == '\\')) {
        return Err(Reject::Separator);
    }
    if trim(&nfc).is_empty() || trim(&kc).is_empty() {
        return Err(Reject::Empty);
    }
    let mut name = trim(&nfc.chars().map(illegal).collect::<String>());
    let probe = trim(&kc.chars().map(illegal).collect::<String>());
    if name.is_empty() {
        return Err(Reject::Empty);
    }
    if reserved(&name) || reserved(&probe) {
        name = format!("_{name}");
    }
    name = cut(&name);
    // The cut can leave a device name too ("CON" and spaces, the spaces cut away): the same test runs again on the cut name, NFC and NFKC.
    if reserved(&name) || reserved(&trim(&nfkc(&name))) {
        name = cut(&format!("_{name}"));
    }
    if name.starts_with('.') {
        name = cut(&format!("_{name}"));
    }
    if trim(&name).is_empty() || trim(&nfkc(&name)).is_empty() {
        return Err(Reject::Empty);
    }
    Ok(name)
}

fn key(name: &str) -> String {
    name.nfc().collect::<String>().to_lowercase()
}

/// `name` itself when no taken name equals it, else "stem (n)ext" for the smallest n from 1 that is free; None after 9999 tries. Names are compared in NFC and without regard to case.
/// (The reference folds case with Python's `casefold`, which turns a sharp s into "ss"; `to_lowercase` does not, and the two differ for about 296 code points in all (the final sigma, the long s, the micro sign, the sharp s ...). The volume decides which names are the same file, the file is created
/// exclusively whatever this says, and the contract lists the fold as a known limit.)
pub fn unique_name(name: &str, taken: &[String]) -> Option<String> {
    let used: HashSet<String> = taken.iter().map(|t| key(t)).collect();
    if !used.contains(&key(name)) {
        return Some(name.to_string());
    }
    let (stem, ext) = split_ext(name);
    (1..=COLLISION_MAX).map(|n| format!("{stem} ({n}){ext}")).find(|cand| !used.contains(&key(cand)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link::testutil::{arr, fixture, name};
    use serde_json::Value;

    fn sanitize_value(raw: &Value) -> Value {
        match raw.as_str() {
            None => serde_json::json!({"reject": "not-text"}),
            Some(s) => match sanitize_name(s) {
                Ok(n) => serde_json::json!({"ok": n}),
                Err(r) => serde_json::json!({"reject": r.as_str()}),
            },
        }
    }

    #[test]
    fn the_constants_are_the_fixtures() {
        let f = fixture("filename-cases.json");
        assert_eq!(f["bytesMax"], NAME_BYTES_MAX);
        assert_eq!(f["extBytesMax"], EXT_BYTES_MAX);
        assert_eq!(f["collisionMax"], COLLISION_MAX);
    }

    #[test]
    fn every_name_case_of_the_fixture() {
        let f = fixture("filename-cases.json");
        let cases = arr(&f, "cases");
        assert!(cases.len() >= 160, "{} cases", cases.len());
        for c in cases {
            assert_eq!(sanitize_value(&c["raw"]), c["out"], "{}", name(c));
        }
    }

    #[test]
    fn every_collision_case_of_the_fixture() {
        let f = fixture("filename-cases.json");
        for c in arr(&f, "uniqueCases") {
            let mut taken: Vec<String> = c["taken"].as_array().unwrap().iter().map(|v| v.as_str().unwrap().to_string()).collect();
            if let Some(n) = c.get("takenNumbered") {
                let (stem, ext) = (n["stem"].as_str().unwrap(), n["ext"].as_str().unwrap());
                for i in n["from"].as_u64().unwrap()..=n["to"].as_u64().unwrap() {
                    taken.push(format!("{stem} ({i}){ext}"));
                }
            }
            let got = unique_name(c["wanted"].as_str().unwrap(), &taken);
            let want = c["out"].as_str();
            assert_eq!(got.as_deref(), want, "{}", name(c));
        }
    }

    #[test]
    fn a_saved_name_is_never_longer_than_200_bytes_never_a_path_and_never_empty() {
        // A seeded walk over awkward pieces: no input may panic, and what is accepted obeys the three rules.
        let pieces = ["a", "é", "e\u{301}", " ", ".", "..", "/", "\\", "CON", ":", "\u{202e}", "\u{1f408}", "\t", "\u{a0}", "x".repeat(150).leak() as &str, "\0", "ﬁ", "\u{ff0f}"];
        let mut seed: u64 = 20261015;
        let mut next = |n: usize| {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            ((seed >> 33) as usize) % n
        };
        for _ in 0..4000 {
            let raw: String = (0..1 + next(8)).map(|_| pieces[next(pieces.len())]).collect();
            if let Ok(saved) = sanitize_name(&raw) {
                assert!(saved.len() <= NAME_BYTES_MAX, "{raw:?} -> {saved:?}");
                assert!(!saved.contains('/') && !saved.contains('\\') && !saved.is_empty(), "{raw:?} -> {saved:?}");
                assert_eq!(sanitize_name(&saved).as_deref(), Ok(saved.as_str()), "a saved name is its own sanitized form: {raw:?} -> {saved:?}");
            }
        }
    }
}
