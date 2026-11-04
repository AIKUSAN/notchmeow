// Files to the AI (spec §3): classify a dropped file, pull its text out, and
// shape it for the model that will read it. Classification follows the rules in
// tests/fixtures/ai/attachment-cases.json; `attachment_cases` runs every case.
//
// No file content is ever logged here or anywhere else.

use std::io::Read;
use std::path::Path;

use serde::Serialize;

use crate::ai::budget;
use crate::ai::catalog;
use crate::ai::provider::{Part, Placement};

pub const REJECT_EXTENSIONS: &[&str] = &[
    "zip", "gz", "tar", "7z", "rar", "dmg", "iso", "pkg", "msi", "exe", "app", "mov", "mp4", "mkv", "avi",
];

pub const IMAGE_EXTENSIONS: &[(&str, &str)] = &[
    ("png", "image/png"),
    ("jpg", "image/jpeg"),
    ("jpeg", "image/jpeg"),
    ("gif", "image/gif"),
    ("webp", "image/webp"),
    ("heic", "image/heic"),
];

/// Per-page decompressed content `lopdf` may produce: guards against decompression bombs,
/// which `catch_unwind` cannot stop.
const PDF_PAGE_CONTENT_LIMIT: usize = 16 * 1024 * 1024;
/// How much of a file is sniffed to tell text from binary.
const SNIFF_BYTES: usize = 8192;
/// A docx's document.xml is read up to this size: guards against zip bombs.
const MAX_XML_BYTES: u64 = 64 * 1024 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Kind {
    Text,
    PdfText,
    PdfScanned,
    Image,
    Docx,
    Rtf,
    Html,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum RejectReason {
    Size,
    Type,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Classified {
    Accepted(Kind),
    Rejected(RejectReason),
}

/// The cheap part of classification: size, extension and a sniff of the first
/// 8 KB. PDFs come back as `PdfText` until `classify` looks inside them. Safe to
/// call on the UI thread.
pub fn screen(path: &Path) -> std::io::Result<Classified> {
    let meta = std::fs::metadata(path)?;
    if meta.len() > catalog::MAX_FILE_BYTES {
        return Ok(Classified::Rejected(RejectReason::Size));
    }
    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_ascii_lowercase();
    let kind = match ext.as_str() {
        "pdf" => Kind::PdfText,
        e if image_mime(e).is_some() => Kind::Image,
        "docx" => Kind::Docx,
        "rtf" => Kind::Rtf,
        "html" | "htm" => Kind::Html,
        e if REJECT_EXTENSIONS.contains(&e) => return Ok(Classified::Rejected(RejectReason::Type)),
        _ => {
            let mut head = Vec::with_capacity(SNIFF_BYTES);
            std::fs::File::open(path)?.take(SNIFF_BYTES as u64).read_to_end(&mut head)?;
            if head.contains(&0) {
                return Ok(Classified::Rejected(RejectReason::Type));
            }
            if let Err(e) = std::str::from_utf8(&head) {
                // Only a multi-byte character cut by the 8 KB limit is allowed.
                if e.valid_up_to() + 3 < head.len() {
                    return Ok(Classified::Rejected(RejectReason::Type));
                }
            }
            Kind::Text
        }
    };
    Ok(Classified::Accepted(kind))
}

/// Full classification: `screen`, then a PDF is opened to see whether it has a text layer.
pub fn classify(path: &Path) -> std::io::Result<Classified> {
    match screen(path)? {
        Classified::Accepted(Kind::PdfText) if pdf_text(path).is_none() => Ok(Classified::Accepted(Kind::PdfScanned)),
        other => Ok(other),
    }
}

/// What the island says when the cat refuses a file at drop time.
pub fn reject_message(reason: RejectReason) -> &'static str {
    match reason {
        RejectReason::Size => "Files over 25 MB are too big for me.",
        RejectReason::Type => "I can't read this kind of file.",
    }
}

pub fn image_mime(ext: &str) -> Option<&'static str> {
    IMAGE_EXTENSIONS.iter().find(|(e, _)| *e == ext).map(|(_, m)| *m)
}

/// The PDF's text layer, or `None` for a scanned, encrypted or unreadable PDF.
///
/// A malformed PDF can make `lopdf` panic. The release profile unwinds (see the
/// `windows/Cargo.toml` step), so `catch_unwind` turns such a panic into "unreadable"
/// instead of killing the app.
pub fn pdf_text(path: &Path) -> Option<String> {
    let path = path.to_path_buf();
    std::panic::catch_unwind(move || {
        let doc = lopdf::Document::load(&path).ok()?;
        if doc.is_encrypted() {
            return None;
        }
        let pages: Vec<u32> = doc.get_pages().keys().copied().collect();
        let text = doc.extract_text_with_limit(&pages, PDF_PAGE_CONTENT_LIMIT).ok()?;
        (!text.trim().is_empty()).then_some(text)
    })
    .ok()
    .flatten()
}

/// A file's text, for every kind that has one.
pub fn extract_text(path: &Path, kind: Kind) -> Result<String, String> {
    let read = || std::fs::read(path).map(|b| String::from_utf8_lossy(&b).trim_start_matches('\u{feff}').to_string());
    match kind {
        Kind::Text => read().map_err(|e| e.to_string()),
        Kind::PdfText => pdf_text(path).ok_or_else(|| "no text layer".to_string()),
        Kind::Docx => docx_text(path),
        Kind::Rtf => read().map(|s| rtf_to_text(&s)).map_err(|e| e.to_string()),
        Kind::Html => read().map(|s| html_to_text(&s)).map_err(|e| e.to_string()),
        Kind::Image | Kind::PdfScanned => Err("no text layer".to_string()),
    }
}

fn docx_text(path: &Path) -> Result<String, String> {
    let file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let mut zip = zip::ZipArchive::new(file).map_err(|e| e.to_string())?;
    let entry = zip.by_name("word/document.xml").map_err(|e| e.to_string())?;
    let mut xml = String::new();
    entry.take(MAX_XML_BYTES).read_to_string(&mut xml).map_err(|e| e.to_string())?;
    Ok(word_xml_to_text(&xml))
}

/// The text of `<w:t>` runs; paragraphs end in a newline, tabs and breaks are kept.
pub fn word_xml_to_text(xml: &str) -> String {
    let mut out = String::new();
    let mut rest = xml;
    while let Some(lt) = rest.find('<') {
        let after = &rest[lt + 1..];
        let Some(gt) = after.find('>') else { break };
        let tag = &after[..gt];
        rest = &after[gt + 1..];
        let closing = tag.starts_with('/');
        let name = tag.trim_start_matches('/').split(|c: char| c.is_whitespace() || c == '/').next().unwrap_or("");
        match (closing, name) {
            (true, "w:p") => out.push('\n'),
            (false, "w:t") if !tag.ends_with('/') => {
                let end = rest.find("</w:t>").unwrap_or(rest.len());
                out.push_str(&decode_entities(&rest[..end]));
                rest = &rest[end..];
            }
            (false, "w:tab") => out.push('\t'),
            (false, "w:br") | (false, "w:cr") => out.push('\n'),
            _ => {}
        }
    }
    out.trim().to_string()
}

/// Plain text out of RTF: groups like the font table are skipped, `\par` is a
/// newline, `\'hh` and `\uN` escapes are decoded.
pub fn rtf_to_text(rtf: &str) -> String {
    const SKIP: &[&str] = &[
        "fonttbl", "colortbl", "stylesheet", "info", "pict", "header", "headerl", "headerr", "footer",
        "footerl", "footerr", "themedata", "colorschememapping", "latentstyles", "datastore", "xmlnstbl",
        "listtable", "listoverridetable", "rsidtbl", "generator", "object", "fldinst",
    ];
    let chars: Vec<char> = rtf.chars().collect();
    let mut out = String::new();
    let mut stack: Vec<bool> = Vec::new();
    let mut skip = false;
    let mut i = 0;
    while i < chars.len() {
        match chars[i] {
            '{' => {
                stack.push(skip);
                i += 1;
            }
            '}' => {
                skip = stack.pop().unwrap_or(false);
                i += 1;
            }
            '\\' if i + 1 < chars.len() => {
                let next = chars[i + 1];
                i += 2;
                if next.is_ascii_alphabetic() {
                    let mut word = String::from(next);
                    while i < chars.len() && chars[i].is_ascii_alphabetic() {
                        word.push(chars[i]);
                        i += 1;
                    }
                    let mut num = String::new();
                    if i < chars.len() && (chars[i] == '-' || chars[i].is_ascii_digit()) {
                        num.push(chars[i]);
                        i += 1;
                        while i < chars.len() && chars[i].is_ascii_digit() {
                            num.push(chars[i]);
                            i += 1;
                        }
                    }
                    if i < chars.len() && chars[i] == ' ' {
                        i += 1;
                    }
                    if SKIP.contains(&word.as_str()) {
                        skip = true;
                        continue;
                    }
                    if skip {
                        continue;
                    }
                    match word.as_str() {
                        "par" | "line" | "sect" | "page" | "row" => out.push('\n'),
                        "tab" | "cell" => out.push('\t'),
                        "u" => {
                            if let Ok(v) = num.parse::<i32>() {
                                let v = if v < 0 { v + 65536 } else { v };
                                if let Some(ch) = char::from_u32(v as u32) {
                                    out.push(ch);
                                }
                                // \uN is followed by one fallback character for old readers.
                                if i < chars.len() && !matches!(chars[i], '\\' | '{' | '}') {
                                    i += 1;
                                }
                            }
                        }
                        _ => {}
                    }
                } else if next == '*' {
                    skip = true;
                } else if next == '\'' {
                    let hex: String = chars[i..(i + 2).min(chars.len())].iter().collect();
                    if let Ok(b) = u8::from_str_radix(&hex, 16) {
                        if !skip {
                            out.push(cp1252(b));
                        }
                    }
                    i = (i + 2).min(chars.len());
                } else if !skip {
                    match next {
                        '\\' | '{' | '}' => out.push(next),
                        '~' => out.push('\u{a0}'),
                        '_' => out.push('-'),
                        _ => {}
                    }
                }
            }
            '\r' | '\n' => i += 1,
            c => {
                if !skip {
                    out.push(c);
                }
                i += 1;
            }
        }
    }
    out.trim().to_string()
}

/// Windows-1252, the code page RTF's `\'hh` escapes almost always use.
fn cp1252(b: u8) -> char {
    const HIGH: [char; 32] = [
        '€', '\u{81}', '‚', 'ƒ', '„', '…', '†', '‡', 'ˆ', '‰', 'Š', '‹', 'Œ', '\u{8d}', 'Ž', '\u{8f}',
        '\u{90}', '‘', '’', '“', '”', '•', '–', '—', '˜', '™', 'š', '›', 'œ', '\u{9d}', 'ž', 'Ÿ',
    ];
    match b {
        0x80..=0x9f => HIGH[(b - 0x80) as usize],
        _ => b as char,
    }
}

/// Visible text of an HTML page: `<script>`/`<style>` dropped, block tags become
/// spaces, entities decoded, whitespace runs collapsed to single spaces.
pub fn html_to_text(html: &str) -> String {
    const BLOCK: &[&str] = &[
        "p", "div", "br", "li", "ul", "ol", "tr", "td", "th", "table", "h1", "h2", "h3", "h4", "h5", "h6",
        "section", "article", "header", "footer", "blockquote", "pre", "hr", "title", "head", "body", "html",
    ];
    // ASCII lowercasing keeps every byte offset, so `lower` and `html` index alike.
    let lower = html.to_ascii_lowercase();
    let mut out = String::new();
    let mut i = 0;
    while i < html.len() {
        if html.as_bytes()[i] != b'<' {
            let next = html[i..].find('<').map_or(html.len(), |e| i + e);
            out.push_str(&decode_entities(&html[i..next]));
            i = next;
            continue;
        }
        if lower[i..].starts_with("<!--") {
            i = lower[i..].find("-->").map_or(html.len(), |e| i + e + 3);
            out.push(' ');
            continue;
        }
        let (tag, end) = match html[i..].find('>') {
            Some(e) => (&lower[i + 1..i + e], i + e + 1),
            None => (&lower[i + 1..], html.len()),
        };
        let name: String = tag.trim_start_matches('/').chars().take_while(|c| c.is_ascii_alphanumeric()).collect();
        if !tag.starts_with('/') && (name == "script" || name == "style") {
            let close = format!("</{name}");
            i = match lower[end..].find(&close) {
                Some(e) => lower[end + e..].find('>').map_or(html.len(), |g| end + e + g + 1),
                None => html.len(),
            };
            out.push(' ');
            continue;
        }
        if BLOCK.contains(&name.as_str()) {
            out.push(' ');
        }
        i = end;
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&#39;`, `&nbsp;`, `&#NNN;`, `&#xHH;`.
pub fn decode_entities(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(amp) = rest.find('&') {
        out.push_str(&rest[..amp]);
        let after = &rest[amp + 1..];
        let semi = after.find(';').filter(|n| *n <= 10);
        let decoded = semi.and_then(|n| {
            let name = &after[..n];
            match name {
                "amp" => Some('&'),
                "lt" => Some('<'),
                "gt" => Some('>'),
                "quot" => Some('"'),
                "apos" => Some('\''),
                "nbsp" => Some('\u{a0}'),
                _ if name.starts_with("#x") || name.starts_with("#X") => {
                    u32::from_str_radix(&name[2..], 16).ok().and_then(char::from_u32)
                }
                _ if name.starts_with('#') => name[1..].parse().ok().and_then(char::from_u32),
                _ => None,
            }
        });
        match (decoded, semi) {
            (Some(c), Some(n)) => {
                out.push(c);
                rest = &after[n + 1..];
            }
            _ => {
                out.push('&');
                rest = after;
            }
        }
    }
    out.push_str(rest);
    out
}

/// Standard base64 (RFC 4648), for PDFs and images sent natively and for Stripe's basic auth.
pub fn base64(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b = [chunk[0], *chunk.get(1).unwrap_or(&0), *chunk.get(2).unwrap_or(&0)];
        let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
        out.push(TABLE[(n >> 18) as usize & 63] as char);
        out.push(TABLE[(n >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 { TABLE[(n >> 6) as usize & 63] as char } else { '=' });
        out.push(if chunk.len() > 2 { TABLE[n as usize & 63] as char } else { '=' });
    }
    out
}

/// Who will read the file.
#[derive(Debug, Clone, PartialEq)]
pub struct Reader {
    pub provider: String,
    pub placement: Placement,
    pub vision: bool,
    pub context_tokens: Option<u64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Prepared {
    pub parts: Vec<Part>,
    /// "I read the first 600 lines." when the text was cut.
    pub notice: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PrepareError {
    Rejected(RejectReason),
    /// The model can't see images and nothing here can read them for it.
    CantSee,
    /// A scanned PDF this platform can neither render for a model that sees nor read with OCR.
    /// Not "can't see": a model that sees fine still can't be shown it.
    ScannedPdf,
    /// A HEIC photo. Anthropic and OpenAI reject `image/heic` and local servers can't decode
    /// it, so it is never sent; JPEG and PNG are.
    Heic,
    Unreadable,
}

fn is_heic(ext: &str) -> bool {
    ext == "heic"
}

fn text_part(name: &str, text: &str, reader: &Reader) -> Prepared {
    let b = budget::budget(reader.placement, reader.context_tokens, text);
    Prepared { parts: vec![Part::FileText { name: name.to_string(), text: budget::cut(text, &b) }], notice: b.notice }
}

/// Shapes one dropped file for one model (spec §3's table).
pub fn prepare(path: &Path, name: &str, reader: &Reader) -> Result<Prepared, PrepareError> {
    let kind = match classify(path).map_err(|_| PrepareError::Unreadable)? {
        Classified::Rejected(r) => return Err(PrepareError::Rejected(r)),
        Classified::Accepted(k) => k,
    };
    let bytes = || std::fs::read(path).map_err(|_| PrepareError::Unreadable);
    let name_s = name.to_string();
    match kind {
        Kind::PdfText | Kind::PdfScanned if catalog::reads_pdf_natively(&reader.provider) => {
            Ok(Prepared { parts: vec![Part::Pdf { name: name_s, base64: base64(&bytes()?) }], notice: None })
        }
        Kind::Image if reader.vision => {
            let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_ascii_lowercase();
            if is_heic(&ext) {
                return Err(PrepareError::Heic);
            }
            let mime = image_mime(&ext).unwrap_or("image/png").to_string();
            Ok(Prepared { parts: vec![Part::Image { name: name_s, mime, base64: base64(&bytes()?) }], notice: None })
        }
        Kind::Image => {
            let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_ascii_lowercase();
            ocr::image_text(path)
                .filter(|t| !t.trim().is_empty())
                .map(|t| text_part(name, &t, reader))
                .ok_or(if is_heic(&ext) { PrepareError::Heic } else { PrepareError::CantSee })
        }
        Kind::PdfScanned if reader.vision => {
            let pages = ocr::pdf_pages_png(path).filter(|p| !p.is_empty()).ok_or(PrepareError::ScannedPdf)?;
            let parts = pages
                .iter()
                .enumerate()
                .map(|(i, png)| Part::Image {
                    name: format!("{name}, page {}", i + 1),
                    mime: "image/png".into(),
                    base64: base64(png),
                })
                .collect();
            Ok(Prepared { parts, notice: None })
        }
        Kind::PdfScanned => ocr::pdf_text(path)
            .filter(|t| !t.trim().is_empty())
            .map(|t| text_part(name, &t, reader))
            .ok_or(PrepareError::ScannedPdf),
        _ => {
            let text = extract_text(path, kind).map_err(|_| PrepareError::Unreadable)?;
            Ok(text_part(name, &text, reader))
        }
    }
}

/// Linux has no built-in OCR or PDF renderer: images reach only models that can see.
#[cfg(not(windows))]
mod ocr {
    use std::path::Path;

    pub fn image_text(_path: &Path) -> Option<String> {
        None
    }

    pub fn pdf_text(_path: &Path) -> Option<String> {
        None
    }

    pub fn pdf_pages_png(_path: &Path) -> Option<Vec<Vec<u8>>> {
        None
    }
}

/// Windows' own OCR (Windows.Media.Ocr) and PDF renderer (Windows.Data.Pdf): no
/// extra dependency. Called from a blocking thread, because the WinRT `.get()`
/// calls wait. windows-rs joins the multithreaded apartment on first use.
#[cfg(windows)]
mod ocr {
    use std::path::Path;

    use windows::core::{Param, HSTRING};
    use windows::Data::Pdf::PdfDocument;
    use windows::Graphics::Imaging::{BitmapDecoder, BitmapPixelFormat, SoftwareBitmap};
    use windows::Media::Ocr::OcrEngine;
    use windows::Storage::Streams::{Buffer, DataReader, IRandomAccessStream, InMemoryRandomAccessStream, InputStreamOptions};
    use windows::Storage::{FileAccessMode, StorageFile};

    /// The first pages are enough for a question, and keep a request small.
    const MAX_PDF_PAGES: u32 = 3;

    type R<T> = windows::core::Result<T>;

    /// `None` when no OCR language is installed for the user's languages.
    fn engine() -> Option<OcrEngine> {
        OcrEngine::TryCreateFromUserProfileLanguages().ok()
    }

    #[cfg(test)]
    pub fn available() -> bool {
        engine().is_some()
    }

    fn open(path: &Path) -> R<StorageFile> {
        // WinRT refuses the `\\?\` paths that std::fs::canonicalize returns.
        let text = path.to_string_lossy();
        let plain = text.strip_prefix(r"\\?\").unwrap_or(&text);
        StorageFile::GetFileFromPathAsync(&HSTRING::from(plain))?.get()
    }

    fn bitmap<P: Param<IRandomAccessStream>>(stream: P) -> R<SoftwareBitmap> {
        let decoder = BitmapDecoder::CreateAsync(stream)?.get()?;
        let bitmap = decoder.GetSoftwareBitmapAsync()?.get()?;
        SoftwareBitmap::Convert(&bitmap, BitmapPixelFormat::Bgra8)
    }

    fn recognize<P: Param<IRandomAccessStream>>(engine: &OcrEngine, stream: P) -> R<String> {
        let result = engine.RecognizeAsync(&bitmap(stream)?)?.get()?;
        Ok(result.Text()?.to_string_lossy())
    }

    /// The first pages, each rendered to a PNG in memory.
    fn pages(path: &Path) -> R<Vec<InMemoryRandomAccessStream>> {
        let doc = PdfDocument::LoadFromFileAsync(&open(path)?)?.get()?;
        let mut out = Vec::new();
        for i in 0..doc.PageCount()?.min(MAX_PDF_PAGES) {
            let stream = InMemoryRandomAccessStream::new()?;
            doc.GetPage(i)?.RenderToStreamAsync(&stream)?.get()?;
            stream.Seek(0)?;
            out.push(stream);
        }
        Ok(out)
    }

    fn png_bytes(stream: &InMemoryRandomAccessStream) -> R<Vec<u8>> {
        stream.Seek(0)?;
        let size = stream.Size()? as u32;
        let buffer = Buffer::Create(size)?;
        let read = stream.ReadAsync(&buffer, size, InputStreamOptions::None)?.get()?;
        let mut bytes = vec![0u8; read.Length()? as usize];
        DataReader::FromBuffer(&read)?.ReadBytes(&mut bytes)?;
        Ok(bytes)
    }

    pub fn image_text(path: &Path) -> Option<String> {
        let engine = engine()?;
        let stream = open(path).ok()?.OpenAsync(FileAccessMode::Read).ok()?.get().ok()?;
        recognize(&engine, &stream).ok()
    }

    pub fn pdf_text(path: &Path) -> Option<String> {
        let engine = engine()?;
        let mut text = Vec::new();
        for page in pages(path).ok()? {
            text.push(recognize(&engine, &page).ok()?);
        }
        Some(text.join("\n\n"))
    }

    pub fn pdf_pages_png(path: &Path) -> Option<Vec<Vec<u8>>> {
        let mut out = Vec::new();
        for page in pages(path).ok()? {
            out.push(png_bytes(&page).ok()?);
        }
        Some(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::testkit;
    use serde_json::Value;

    fn local(vision: bool) -> Reader {
        Reader { provider: "ollama".into(), placement: Placement::Local, vision, context_tokens: None }
    }

    fn cloud(provider: &str) -> Reader {
        Reader { provider: provider.into(), placement: Placement::Cloud, vision: true, context_tokens: None }
    }

    #[test]
    fn rule_lists_match_attachment_cases_json() {
        let rules = testkit::load_json("attachment-cases.json");
        assert_eq!(rules["maxFileBytes"], catalog::MAX_FILE_BYTES);
        let rejects: Vec<&str> = rules["rejectExtensions"].as_array().unwrap().iter().map(|v| v.as_str().unwrap()).collect();
        assert_eq!(rejects, REJECT_EXTENSIONS);
        let images = rules["imageExtensions"].as_object().unwrap();
        assert_eq!(images.len(), IMAGE_EXTENSIONS.len());
        for (ext, mime) in IMAGE_EXTENSIONS {
            assert_eq!(images[*ext], *mime, "{ext}");
        }
    }

    #[test]
    fn attachment_cases() {
        let rules = testkit::load_json("attachment-cases.json");
        let dir = testkit::make_attachments();
        let cases = rules["cases"].as_array().unwrap();
        assert_eq!(cases.len(), 15, "attachment-cases.json changed: update this count on purpose");
        for case in cases {
            let file = case["file"].as_str().unwrap();
            let path = dir.path().join(file);
            let got = classify(&path).unwrap();
            match got {
                Classified::Rejected(r) => {
                    assert_eq!(case["kind"], "rejected", "{file}");
                    assert_eq!(serde_json::to_value(r).unwrap(), case["reason"], "{file} reason");
                }
                Classified::Accepted(kind) => {
                    assert_eq!(serde_json::to_value(kind).unwrap(), case["kind"], "{file}");
                    if let Some(mime) = case.get("mime").and_then(Value::as_str) {
                        let ext = path.extension().unwrap().to_str().unwrap().to_ascii_lowercase();
                        assert_eq!(image_mime(&ext), Some(mime), "{file} mime");
                    }
                    let text = extract_text(&path, kind).unwrap_or_default();
                    for want in case.get("contains").and_then(Value::as_array).into_iter().flatten() {
                        assert!(text.contains(want.as_str().unwrap()), "{file} should contain {want}: {text:?}");
                    }
                    for bad in case.get("notContains").and_then(Value::as_array).into_iter().flatten() {
                        assert!(!text.contains(bad.as_str().unwrap()), "{file} must not contain {bad}: {text:?}");
                    }
                }
            }
        }
    }

    #[test]
    fn broken_pdfs_never_panic() {
        let dir = testkit::make_attachments();
        let whole = std::fs::read(dir.path().join("text.pdf")).unwrap();
        let cut = dir.path().join("cut.pdf");
        std::fs::write(&cut, &whole[..whole.len() / 2]).unwrap();
        let junk = dir.path().join("junk.pdf");
        std::fs::write(&junk, b"%PDF-1.4\nnot really").unwrap();
        for p in [&cut, &junk] {
            assert_eq!(classify(p).unwrap(), Classified::Accepted(Kind::PdfScanned), "{}", p.display());
        }
    }

    #[test]
    fn prepare_follows_the_spec_table() {
        let dir = testkit::make_attachments();
        let p = |f: &str| dir.path().join(f);

        // A text PDF: native to Anthropic and OpenAI, extracted text for everyone else.
        let native = prepare(&p("text.pdf"), "text.pdf", &cloud("anthropic")).unwrap();
        assert!(matches!(&native.parts[0], Part::Pdf { name, .. } if name == "text.pdf"));
        assert!(matches!(&prepare(&p("text.pdf"), "text.pdf", &cloud("openai")).unwrap().parts[0], Part::Pdf { .. }));
        let local_pdf = prepare(&p("text.pdf"), "text.pdf", &local(false)).unwrap();
        assert!(matches!(&local_pdf.parts[0], Part::FileText { text, .. } if text.contains("Hello from NotchMeow")));
        let google_pdf = prepare(&p("text.pdf"), "text.pdf", &cloud("google")).unwrap();
        assert!(matches!(&google_pdf.parts[0], Part::FileText { .. }));

        // Images go to models that can see them.
        let img = prepare(&p("photo.png"), "photo.png", &local(true)).unwrap();
        assert!(matches!(&img.parts[0], Part::Image { mime, .. } if mime == "image/png"));

        // Rejects.
        assert_eq!(prepare(&p("big.txt"), "big.txt", &local(false)), Err(PrepareError::Rejected(RejectReason::Size)));
        assert_eq!(prepare(&p("archive.zip"), "archive.zip", &local(false)), Err(PrepareError::Rejected(RejectReason::Type)));

        // Office formats become text.
        let docx = prepare(&p("letter.docx"), "letter.docx", &cloud("anthropic")).unwrap();
        assert!(matches!(&docx.parts[0], Part::FileText { text, .. } if text.contains("live in the notch.")));
    }

    #[cfg(not(windows))]
    #[test]
    fn linux_cannot_read_images_or_scanned_pdfs_for_models_that_need_help() {
        let dir = testkit::make_attachments();
        let scan = dir.path().join("scan.pdf");
        assert_eq!(prepare(&dir.path().join("photo.png"), "photo.png", &local(false)), Err(PrepareError::CantSee));
        // A scanned PDF is not "this model can't see images": a model that sees fine still can't
        // be shown it here, because Linux has no PDF renderer and no OCR.
        assert_eq!(prepare(&scan, "scan.pdf", &local(false)), Err(PrepareError::ScannedPdf));
        assert_eq!(prepare(&scan, "scan.pdf", &local(true)), Err(PrepareError::ScannedPdf));
        assert_eq!(prepare(&scan, "scan.pdf", &cloud("google")), Err(PrepareError::ScannedPdf));
        // Claude and OpenAI take the PDF as it is.
        assert!(matches!(&prepare(&scan, "scan.pdf", &cloud("anthropic")).unwrap().parts[0], Part::Pdf { .. }));
        assert!(matches!(&prepare(&scan, "scan.pdf", &cloud("openai")).unwrap().parts[0], Part::Pdf { .. }));
    }

    #[test]
    fn heic_photos_are_never_sent() {
        let dir = testkit::TempDir::new("heic");
        let heic = dir.path().join("IMG_0001.HEIC");
        std::fs::write(&heic, b"\0\0\0\x18ftypheic\0\0\0\0mif1heic").unwrap();
        assert_eq!(classify(&heic).unwrap(), Classified::Accepted(Kind::Image));
        for reader in [cloud("anthropic"), cloud("openai"), cloud("google"), local(true)] {
            assert_eq!(prepare(&heic, "IMG_0001.HEIC", &reader), Err(PrepareError::Heic), "{}", reader.provider);
        }
        // A model that can't see goes to OCR, which can't read it either: say HEIC, not "can't see".
        assert_eq!(prepare(&heic, "IMG_0001.HEIC", &local(false)), Err(PrepareError::Heic));
        // JPEG and PNG still go out.
        let png = testkit::make_attachments();
        let sent = prepare(&png.path().join("photo.png"), "photo.png", &cloud("anthropic")).unwrap();
        assert!(matches!(&sent.parts[0], Part::Image { mime, .. } if mime == "image/png"));
    }

    #[test]
    fn long_text_is_cut_and_announced() {
        let dir = testkit::TempDir::new("long");
        let path = dir.path().join("long.txt");
        std::fs::write(&path, "aaaaaaaaa\n".repeat(1000)).unwrap();
        let got = prepare(&path, "long.txt", &local(false)).unwrap();
        assert_eq!(got.notice.as_deref(), Some("I read the first 716 lines."));
        assert!(matches!(&got.parts[0], Part::FileText { text, .. } if text.ends_with("[I read the first 716 lines.]")));
    }

    #[test]
    fn entities_and_odd_markup() {
        assert_eq!(decode_entities("a &amp; b &lt;c&gt; &#233;&#x41; &bogus; &"), "a & b <c> éA &bogus; &");
        assert_eq!(html_to_text("<P>One</P><DIV>Two<SCRIPT>x()</script></div>"), "One Two");
        assert_eq!(html_to_text("unclosed <b"), "unclosed");
        assert_eq!(rtf_to_text(r"{\rtf1 caf\'e9 \u233? ok\par}"), "café é ok");
    }

    #[test]
    fn base64_matches_rfc4648_vectors() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foo"), "Zm9v");
        assert_eq!(base64(b"foob"), "Zm9vYg==");
        assert_eq!(base64(b"fooba"), "Zm9vYmE=");
        assert_eq!(base64(b"foobar"), "Zm9vYmFy");
    }

    #[cfg(windows)]
    #[test]
    fn windows_renders_a_scanned_pdf_for_models_that_see() {
        let dir = testkit::make_attachments();
        let got = prepare(&dir.path().join("scan.pdf"), "scan.pdf", &local(true)).unwrap();
        assert!(
            matches!(&got.parts[0], Part::Image { name, mime, base64 }
                if name == "scan.pdf, page 1" && mime == "image/png" && base64.starts_with("iVBOR")),
            "expected the first page rendered as a PNG"
        );
    }

    #[cfg(windows)]
    #[test]
    fn windows_reads_text_out_of_a_rendered_pdf() {
        if !ocr::available() {
            eprintln!("skipped: no OCR language is installed for this user");
            return;
        }
        let dir = testkit::make_attachments();
        let text = ocr::pdf_text(&dir.path().join("text.pdf")).expect("OCR of a rendered page");
        assert!(text.contains("Hello"), "{text:?}");
    }

    #[cfg(windows)]
    #[test]
    fn windows_ocr_survives_unicode_and_verbatim_paths() {
        let src = testkit::make_attachments();
        let dir = testkit::TempDir::new("zoé");
        let pdf = dir.path().join("Zoé scan.pdf");
        std::fs::copy(src.path().join("text.pdf"), &pdf).unwrap();
        let verbatim = std::fs::canonicalize(&pdf).unwrap();
        assert!(verbatim.to_string_lossy().starts_with(r"\\?\"));
        assert_eq!(ocr::pdf_pages_png(&pdf).map(|p| p.len()), Some(1));
        assert_eq!(ocr::pdf_pages_png(&verbatim).map(|p| p.len()), Some(1));
    }
}
