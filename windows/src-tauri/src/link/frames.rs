// The link's wire shapes (docs/LINK-CONTRACT.md, "On the wire"): records, the first record, the hello, the advert's TXT record and the six frames with the two pairing answers. A port of the
// matching functions of tests/fixtures/link/reference.py, replayed against frames.json. Strict: a decoder that repairs bad bytes is wrong, and a frame may not have a byte left over.
// Pure: no socket, no clock.

use super::bytes::{self, ID_LEN};
use super::name::{is_bad_category, is_invisible};

pub const VERSION: u8 = 1;
pub const NOISE_MAX: usize = 65535;
pub const TAG: usize = 16;
/// The data in one chunk frame, so that the frame and the 16-byte tag fill one Noise message of 65535 bytes exactly.
pub const CHUNK_MAX: usize = NOISE_MAX - TAG - 1 - ID_LEN - 8;
/// What a sender cuts a file into.
pub const CHUNK_SIZE: usize = 32768;
pub const RAW_NAME_MAX: usize = 1020;
pub const KIND_MAX: usize = 127;
pub const DEVICE_NAME_MAX: usize = 63;
/// 4 GiB per transfer, inclusive.
pub const SIZE_MAX: u64 = 4 * 1024 * 1024 * 1024;

pub const DECLINE_USER: u8 = 0;
pub const DECLINE_TIMEOUT: u8 = 1;
pub const DECLINE_BUSY: u8 = 2;
pub const DECLINE_TOO_LARGE: u8 = 3;
pub const DECLINE_BAD_OFFER: u8 = 4;

const T_OFFER: u8 = 1;
const T_ACCEPT: u8 = 2;
const T_DECLINE: u8 = 3;
const T_CHUNK: u8 = 4;
const T_DONE: u8 = 5;
const T_CANCEL: u8 = 6;
const T_PAIR_YES: u8 = 0x21;
const T_PAIR_NO: u8 = 0x22;

/// Why bytes do not decode: the reference's own word for it (`code`), which a test compares.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FrameError(pub &'static str);

impl std::fmt::Display for FrameError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.0)
    }
}

impl std::error::Error for FrameError {}

type Id = [u8; ID_LEN];

#[derive(Clone, PartialEq, Eq)]
pub enum Frame {
    Offer { id: Id, size: u64, name: String, kind: String },
    Accept { id: Id },
    Decline { id: Id, reason: u8 },
    Chunk { id: Id, offset: u64, data: Vec<u8> },
    Done { id: Id },
    Cancel { id: Id },
    PairYes,
    PairNo,
}

/// The kind of frame and nothing else (a decline's reason is a code, not a secret): the transfer id, the name and the bytes of a file never reach a log or a test's failure text.
impl std::fmt::Debug for Frame {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Frame::Offer { .. } => f.debug_struct("Offer").finish_non_exhaustive(),
            Frame::Accept { .. } => f.debug_struct("Accept").finish_non_exhaustive(),
            Frame::Decline { reason, .. } => f.debug_struct("Decline").field("reason", reason).finish_non_exhaustive(),
            Frame::Chunk { .. } => f.debug_struct("Chunk").finish_non_exhaustive(),
            Frame::Done { .. } => f.debug_struct("Done").finish_non_exhaustive(),
            Frame::Cancel { .. } => f.debug_struct("Cancel").finish_non_exhaustive(),
            Frame::PairYes => f.write_str("PairYes"),
            Frame::PairNo => f.write_str("PairNo"),
        }
    }
}

impl Frame {
    /// The transfer id, for every frame that has one.
    pub fn id(&self) -> Option<Id> {
        match self {
            Frame::Offer { id, .. } | Frame::Accept { id } | Frame::Decline { id, .. } | Frame::Chunk { id, .. } | Frame::Done { id } | Frame::Cancel { id } => Some(*id),
            Frame::PairYes | Frame::PairNo => None,
        }
    }

    pub fn is_pairing_answer(&self) -> bool {
        matches!(self, Frame::PairYes | Frame::PairNo)
    }
}

// ── Records ──────────────────────────────────────────────────────────────────

/// A record is a u16 big-endian length (1 to 65535) and that many bytes.
pub fn encode_record(payload: &[u8]) -> Result<Vec<u8>, FrameError> {
    if payload.is_empty() || payload.len() > NOISE_MAX {
        return Err(FrameError("record-length"));
    }
    let mut out = Vec::with_capacity(2 + payload.len());
    out.extend_from_slice(&(payload.len() as u16).to_be_bytes());
    out.extend_from_slice(payload);
    Ok(out)
}

/// (the whole records at the start of `buf`, the rest): the rest is a record that has not arrived completely. A length of 0 is an error.
pub fn split_records(buf: &[u8]) -> Result<(Vec<Vec<u8>>, Vec<u8>), FrameError> {
    let (mut out, mut pos) = (Vec::new(), 0);
    while buf.len() - pos >= 2 {
        let n = u16::from_be_bytes([buf[pos], buf[pos + 1]]) as usize;
        if n == 0 {
            return Err(FrameError("record-empty"));
        }
        if buf.len() - pos - 2 < n {
            break;
        }
        out.push(buf[pos + 2..pos + 2 + n].to_vec());
        pos += 2 + n;
    }
    Ok((out, buf[pos..].to_vec()))
}

// ── The first record ─────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Pair,
    Transfer,
}

#[derive(Clone, PartialEq, Eq)]
pub struct Preamble {
    pub mode: Mode,
    pub id: Id,
}

impl std::fmt::Debug for Preamble {
    /// The mode only: the device id is never printed.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Preamble").field("mode", &self.mode).finish_non_exhaustive()
    }
}

pub fn encode_preamble(mode: Mode, id: &Id) -> Vec<u8> {
    let mut out = vec![VERSION, if mode == Mode::Pair { 1 } else { 2 }];
    out.extend_from_slice(id);
    out
}

pub fn decode_preamble(b: &[u8]) -> Result<Preamble, FrameError> {
    if b.len() != 2 + ID_LEN {
        return Err(FrameError("length"));
    }
    if b[0] != VERSION {
        return Err(FrameError("version"));
    }
    let mode = match b[1] {
        1 => Mode::Pair,
        2 => Mode::Transfer,
        _ => return Err(FrameError("mode")),
    };
    let id: Id = b[2..].try_into().unwrap();
    if (mode == Mode::Pair) != (id == [0; ID_LEN]) {
        return Err(FrameError("device-id"));
    }
    Ok(Preamble { mode, id })
}

// ── The hello and the advert ─────────────────────────────────────────────────

/// A device name is shown on the pairing card: 1 to 63 bytes of strict UTF-8, no control, format or separator character, no invisible character, no space at either end.
pub fn device_name(raw: &[u8]) -> Result<String, FrameError> {
    if raw.is_empty() || raw.len() > DEVICE_NAME_MAX {
        return Err(FrameError("name-length"));
    }
    let s = std::str::from_utf8(raw).map_err(|_| FrameError("utf8"))?;
    if s.chars().any(|c| is_bad_category(c) || is_invisible(c)) || s != s.trim() {
        return Err(FrameError("name-chars"));
    }
    Ok(s.to_string())
}

#[derive(Clone, PartialEq, Eq)]
pub struct Hello {
    pub id: Id,
    pub nonce: [u8; 32],
    pub name: String,
}

impl std::fmt::Debug for Hello {
    /// A fixed label: the device id, the nonce and the name are never printed.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Hello").finish_non_exhaustive()
    }
}

/// The payload of the second and third pairing messages: version, device id, a 32-byte nonce, name length and name.
pub fn encode_hello(id: &Id, nonce: &[u8; 32], name: &str) -> Result<Vec<u8>, FrameError> {
    let nb = device_name(name.as_bytes())?;
    let mut out = vec![VERSION];
    out.extend_from_slice(id);
    out.extend_from_slice(nonce);
    out.push(nb.len() as u8);
    out.extend_from_slice(nb.as_bytes());
    Ok(out)
}

pub fn decode_hello(b: &[u8]) -> Result<Hello, FrameError> {
    if b.len() < 2 + ID_LEN + 32 {
        return Err(FrameError("truncated"));
    }
    if b[0] != VERSION {
        return Err(FrameError("version"));
    }
    let id: Id = b[1..1 + ID_LEN].try_into().unwrap();
    if id == [0; ID_LEN] {
        return Err(FrameError("device-id"));
    }
    let nonce: [u8; 32] = b[1 + ID_LEN..1 + ID_LEN + 32].try_into().unwrap();
    let n = b[1 + ID_LEN + 32] as usize;
    let body = &b[2 + ID_LEN + 32..];
    if body.len() < n {
        return Err(FrameError("truncated"));
    }
    if body.len() > n {
        return Err(FrameError("trailing"));
    }
    Ok(Hello { id, nonce, name: device_name(body)? })
}

/// What the advert's own id must be compared with. `Null` exists for the fixtures (a null `own_id` is present and is not an id: fail closed); an app passes `Absent` or `Id`.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum OwnId<'a> {
    Absent,
    Null,
    Id(&'a str),
}

impl std::fmt::Debug for OwnId<'_> {
    /// Whether there is an id, never which.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            OwnId::Absent => f.write_str("Absent"),
            OwnId::Null => f.write_str("Null"),
            OwnId::Id(_) => f.write_str("Id(..)"),
        }
    }
}

/// The three TXT keys that matter. A key that is missing, or whose value is not text, is None.
#[derive(Clone, Copy, Default)]
pub struct Txt<'a> {
    pub v: Option<&'a str>,
    pub id: Option<&'a str>,
    pub name: Option<&'a str>,
}

impl std::fmt::Debug for Txt<'_> {
    /// A fixed label: the id and the name come off the network and are never printed.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Txt").finish_non_exhaustive()
    }
}

#[derive(Clone, PartialEq, Eq)]
pub struct Advert {
    pub id: String,
    pub name: String,
}

impl std::fmt::Debug for Advert {
    /// A fixed label: the id and the name are never printed.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Advert").finish_non_exhaustive()
    }
}

/// An advert's TXT record. Anyone on the network can send one, so it is checked like a name on a card. It carries no key: a paired id under another key is decided at the hello.
pub fn parse_txt(txt: &Txt<'_>, own: OwnId<'_>) -> Result<Advert, FrameError> {
    if txt.v != Some("1") {
        return Err(FrameError("version"));
    }
    let id = match txt.id {
        Some(i) if bytes::is_id_hex(i) && i != "0".repeat(2 * ID_LEN) => i,
        _ => return Err(FrameError("device-id")),
    };
    match own {
        OwnId::Absent => {}
        OwnId::Null => return Err(FrameError("device-id")),
        OwnId::Id(o) if !bytes::is_id_hex(o) => return Err(FrameError("device-id")),
        OwnId::Id(o) if o == id => return Err(FrameError("own-id")),
        OwnId::Id(_) => {}
    }
    let name = txt.name.ok_or(FrameError("name-length"))?;
    Ok(Advert { id: id.to_string(), name: device_name(name.as_bytes())? })
}

// ── The six frames ───────────────────────────────────────────────────────────

pub fn encode_frame(f: &Frame) -> Result<Vec<u8>, FrameError> {
    Ok(match f {
        Frame::PairYes => vec![T_PAIR_YES],
        Frame::PairNo => vec![T_PAIR_NO],
        Frame::Offer { id, size, name, kind } => {
            if name.is_empty() || name.len() > RAW_NAME_MAX {
                return Err(FrameError("name-length"));
            }
            if kind.len() > KIND_MAX || !kind.bytes().all(|c| (0x20..=0x7E).contains(&c)) {
                return Err(FrameError("kind"));
            }
            let mut out = vec![T_OFFER];
            out.extend_from_slice(id);
            out.extend_from_slice(&size.to_be_bytes());
            out.extend_from_slice(&(name.len() as u16).to_be_bytes());
            out.extend_from_slice(name.as_bytes());
            out.push(kind.len() as u8);
            out.extend_from_slice(kind.as_bytes());
            out
        }
        Frame::Accept { id } => with_id(T_ACCEPT, id),
        Frame::Decline { id, reason } => {
            let mut out = with_id(T_DECLINE, id);
            out.push(*reason);
            out
        }
        Frame::Chunk { id, offset, data } => {
            if data.is_empty() {
                return Err(FrameError("chunk-empty"));
            }
            if data.len() > CHUNK_MAX {
                return Err(FrameError("chunk-long"));
            }
            let mut out = with_id(T_CHUNK, id);
            out.extend_from_slice(&offset.to_be_bytes());
            out.extend_from_slice(data);
            out
        }
        Frame::Done { id } => with_id(T_DONE, id),
        Frame::Cancel { id } => with_id(T_CANCEL, id),
    })
}

fn with_id(t: u8, id: &Id) -> Vec<u8> {
    let mut out = vec![t];
    out.extend_from_slice(id);
    out
}

pub fn decode_frame(b: &[u8]) -> Result<Frame, FrameError> {
    let Some((&t, body)) = b.split_first() else { return Err(FrameError("empty")) };
    if !matches!(t, T_OFFER..=T_CANCEL | T_PAIR_YES | T_PAIR_NO) {
        return Err(FrameError("unknown-type"));
    }
    if t == T_PAIR_YES || t == T_PAIR_NO {
        if !body.is_empty() {
            return Err(FrameError("trailing"));
        }
        return Ok(if t == T_PAIR_YES { Frame::PairYes } else { Frame::PairNo });
    }
    if body.len() < ID_LEN {
        return Err(FrameError("truncated"));
    }
    let id: Id = body[..ID_LEN].try_into().unwrap();
    let rest = &body[ID_LEN..];
    match t {
        T_ACCEPT | T_DONE | T_CANCEL => {
            if !rest.is_empty() {
                return Err(FrameError("trailing"));
            }
            Ok(match t {
                T_ACCEPT => Frame::Accept { id },
                T_DONE => Frame::Done { id },
                _ => Frame::Cancel { id },
            })
        }
        T_DECLINE => {
            match rest.len() {
                0 => return Err(FrameError("truncated")),
                1 => {}
                _ => return Err(FrameError("trailing")),
            }
            if rest[0] > DECLINE_BAD_OFFER {
                return Err(FrameError("reason"));
            }
            Ok(Frame::Decline { id, reason: rest[0] })
        }
        T_CHUNK => {
            if rest.len() < 8 {
                return Err(FrameError("truncated"));
            }
            let data = &rest[8..];
            if data.is_empty() {
                return Err(FrameError("chunk-empty"));
            }
            if data.len() > CHUNK_MAX {
                return Err(FrameError("chunk-long"));
            }
            Ok(Frame::Chunk { id, offset: u64::from_be_bytes(rest[..8].try_into().unwrap()), data: data.to_vec() })
        }
        _ => {
            if rest.len() < 10 {
                return Err(FrameError("truncated"));
            }
            let size = u64::from_be_bytes(rest[..8].try_into().unwrap());
            let n = u16::from_be_bytes([rest[8], rest[9]]) as usize;
            if !(1..=RAW_NAME_MAX).contains(&n) {
                return Err(FrameError("name-length"));
            }
            if rest.len() < 10 + n + 1 {
                return Err(FrameError("truncated"));
            }
            let (nb, k, kb) = (&rest[10..10 + n], rest[10 + n] as usize, &rest[11 + n..]);
            if kb.len() < k {
                return Err(FrameError("truncated"));
            }
            if kb.len() > k {
                return Err(FrameError("trailing"));
            }
            if k > KIND_MAX || kb.iter().any(|c| !(0x20..=0x7E).contains(c)) {
                return Err(FrameError("kind"));
            }
            let name = std::str::from_utf8(nb).map_err(|_| FrameError("utf8"))?.to_string();
            Ok(Frame::Offer { id, size, name, kind: String::from_utf8(kb.to_vec()).unwrap() })
        }
    }
}

/// [(offset, length)] that cover `size` bytes; an empty file has none, and then the sender goes straight to `done`.
pub fn plan_chunks(size: u64, chunk_size: usize) -> Vec<(u64, usize)> {
    let mut out = Vec::new();
    let mut offset = 0u64;
    while offset < size {
        let len = (size - offset).min(chunk_size as u64) as usize;
        out.push((offset, len));
        offset += len as u64;
    }
    out
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::link::testutil::{arr, fixture, name};
    use serde_json::{json, Value};

    pub fn frame_of(v: &Value) -> Frame {
        let id = bytes::id16(v["id"].as_str().unwrap_or("")).unwrap_or([0; 16]);
        match v["type"].as_str().unwrap() {
            "offer" => Frame::Offer { id, size: v["size"].as_u64().unwrap(), name: v["name"].as_str().unwrap().to_string(), kind: v["kind"].as_str().unwrap().to_string() },
            "accept" => Frame::Accept { id },
            "decline" => Frame::Decline { id, reason: v["reason"].as_u64().unwrap() as u8 },
            "chunk" => Frame::Chunk { id, offset: v["offset"].as_u64().unwrap(), data: bytes::unhex(v["data"].as_str().unwrap()).unwrap() },
            "done" => Frame::Done { id },
            "cancel" => Frame::Cancel { id },
            "pair-yes" => Frame::PairYes,
            "pair-no" => Frame::PairNo,
            other => panic!("frame type {other}"),
        }
    }

    // Task 4's sender and receiver tests reuse it; until then nothing in this file calls it.
    #[allow(dead_code)]
    pub fn json_of(f: &Frame) -> Value {
        let hex = |id: &Id| bytes::hex(id);
        match f {
            Frame::Offer { id, size, name, kind } => json!({"type": "offer", "id": hex(id), "size": size, "name": name, "kind": kind}),
            Frame::Accept { id } => json!({"type": "accept", "id": hex(id)}),
            Frame::Decline { id, reason } => json!({"type": "decline", "id": hex(id), "reason": reason}),
            Frame::Chunk { id, offset, data } => json!({"type": "chunk", "id": hex(id), "offset": offset, "data": bytes::hex(data)}),
            Frame::Done { id } => json!({"type": "done", "id": hex(id)}),
            Frame::Cancel { id } => json!({"type": "cancel", "id": hex(id)}),
            Frame::PairYes => json!({"type": "pair-yes"}),
            Frame::PairNo => json!({"type": "pair-no"}),
        }
    }

    #[test]
    fn the_limits_and_numbers_are_the_fixtures() {
        let f = fixture("frames.json");
        assert_eq!(f["noiseMax"], NOISE_MAX);
        assert_eq!(f["tag"], TAG);
        assert_eq!(f["idLen"], ID_LEN);
        assert_eq!(f["protocolVersion"], VERSION);
        assert_eq!(f["chunkMax"], CHUNK_MAX);
        assert_eq!(f["chunkSize"], CHUNK_SIZE);
        assert_eq!(f["rawNameMax"], RAW_NAME_MAX);
        assert_eq!(f["kindMax"], KIND_MAX);
        assert_eq!(f["deviceNameMax"], DEVICE_NAME_MAX);
        assert_eq!(f["sizeMax"], SIZE_MAX);
        assert_eq!(f["types"], json!({"offer": 1, "accept": 2, "decline": 3, "chunk": 4, "done": 5, "cancel": 6, "pairYes": 33, "pairNo": 34}));
        assert_eq!(f["declineReasons"], json!({"user": 0, "timeout": 1, "busy": 2, "tooLarge": 3, "badOffer": 4}));
    }

    #[test]
    fn every_frame_encodes_and_decodes_to_its_bytes() {
        let f = fixture("frames.json");
        for c in arr(&f, "frames") {
            let frame = frame_of(&c["frame"]);
            let want = bytes::unhex(c["hex"].as_str().unwrap()).unwrap();
            assert_eq!(encode_frame(&frame).unwrap(), want, "encode: {}", name(c));
            assert_eq!(decode_frame(&want).unwrap(), frame, "decode: {}", name(c));
        }
    }

    #[test]
    fn every_reject_names_its_error() {
        let f = fixture("frames.json");
        let rows = arr(&f, "rejects");
        assert!(rows.len() >= 35);
        for c in rows {
            let got = decode_frame(&bytes::unhex(c["hex"].as_str().unwrap()).unwrap());
            assert_eq!(got.err().map(|e| e.0), c["error"].as_str(), "{}", name(c));
        }
    }

    #[test]
    fn a_chunk_of_65494_bytes_is_the_most_and_65495_is_refused() {
        let f = fixture("frames.json");
        for c in arr(&f, "limits") {
            let id = bytes::id16(c["id"].as_str().unwrap()).unwrap();
            let fill = bytes::unhex(c["fill"].as_str().unwrap()).unwrap()[0];
            let data = vec![fill; c["count"].as_u64().unwrap() as usize];
            let frame = Frame::Chunk { id, offset: c["offset"].as_u64().unwrap(), data };
            let got = encode_frame(&frame).and_then(|b| decode_frame(&b)).map(|_| "ok").unwrap_or_else(|e| e.0);
            assert_eq!(got, c["out"].as_str().unwrap(), "{}", name(c));
        }
    }

    #[test]
    fn every_hello_case() {
        let f = fixture("frames.json");
        for c in arr(&f, "hello") {
            let got = match decode_hello(&bytes::unhex(c["hex"].as_str().unwrap()).unwrap()) {
                Ok(h) => json!({"id": bytes::hex(&h.id), "nonce": bytes::hex(&h.nonce), "name": h.name}),
                Err(e) => json!({"error": e.0}),
            };
            assert_eq!(got, c["out"], "{}", name(c));
            if let Some(ok) = c["out"].get("id") {
                let again = encode_hello(&bytes::id16(ok.as_str().unwrap()).unwrap(), &bytes::key32(c["out"]["nonce"].as_str().unwrap()).unwrap(), c["out"]["name"].as_str().unwrap()).unwrap();
                assert_eq!(bytes::hex(&again), c["hex"].as_str().unwrap(), "encode: {}", name(c));
            }
        }
    }

    #[test]
    fn every_advert_case() {
        let f = fixture("frames.json");
        for c in arr(&f, "txt") {
            let t = &c["txt"];
            let own = match c.get("ownId") {
                None => OwnId::Absent,
                Some(Value::Null) => OwnId::Null,
                Some(v) => OwnId::Id(v.as_str().unwrap()),
            };
            let got = match t.as_object() {
                None => json!({"error": "not-a-record"}),
                Some(m) => {
                    let get = |k: &str| m.get(k).and_then(Value::as_str);
                    match parse_txt(&Txt { v: get("v"), id: get("id"), name: get("name") }, own) {
                        Ok(a) => json!({"id": a.id, "name": a.name}),
                        Err(e) => json!({"error": e.0}),
                    }
                }
            };
            assert_eq!(got, c["out"], "{}", name(c));
        }
    }

    #[test]
    fn every_preamble_case() {
        let f = fixture("frames.json");
        for c in arr(&f, "preamble") {
            let got = match decode_preamble(&bytes::unhex(c["hex"].as_str().unwrap()).unwrap()) {
                Ok(p) => json!({"mode": if p.mode == Mode::Pair { "pair" } else { "transfer" }, "id": bytes::hex(&p.id)}),
                Err(e) => json!({"error": e.0}),
            };
            assert_eq!(got, c["out"], "{}", name(c));
        }
    }

    #[test]
    fn every_record_case() {
        let f = fixture("frames.json");
        for c in arr(&f, "records") {
            let got = match split_records(&bytes::unhex(c["hex"].as_str().unwrap()).unwrap()) {
                Ok((records, rest)) => json!({"records": records.iter().map(|r| bytes::hex(r)).collect::<Vec<_>>(), "rest": bytes::hex(&rest)}),
                Err(e) => json!({"error": e.0}),
            };
            assert_eq!(got, c["out"], "{}", name(c));
        }
        for c in arr(&f, "recordEncode") {
            let got = match encode_record(&bytes::unhex(c["payload"].as_str().unwrap()).unwrap()) {
                Ok(r) => json!({"hex": bytes::hex(&r)}),
                Err(e) => json!({"error": e.0}),
            };
            assert_eq!(got, c["out"], "{}", name(c));
        }
        let max = vec![7u8; NOISE_MAX];
        assert!(encode_record(&max).is_ok());
        assert_eq!(encode_record(&vec![7u8; NOISE_MAX + 1]).unwrap_err().0, "record-length");
    }

    #[test]
    fn a_hello_name_is_never_trusted_on_the_encode_side_either() {
        let id = [1u8; 16];
        assert!(encode_hello(&id, &[2; 32], "Desk PC").is_ok());
        assert_eq!(encode_hello(&id, &[2; 32], "").unwrap_err().0, "name-length");
        assert_eq!(encode_hello(&id, &[2; 32], &"n".repeat(64)).unwrap_err().0, "name-length");
        assert_eq!(encode_hello(&id, &[2; 32], " Desk").unwrap_err().0, "name-chars");
    }

    #[test]
    fn no_input_makes_the_decoders_panic() {
        // Seeded random bytes, with a real frame type at the front half of the time.
        let mut seed: u64 = 20261015;
        let mut next = |n: usize| {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            ((seed >> 33) as usize) % n
        };
        for _ in 0..8000 {
            let len = next(80);
            let mut b: Vec<u8> = (0..len).map(|_| next(256) as u8).collect();
            if !b.is_empty() && next(2) == 0 {
                b[0] = [1, 2, 3, 4, 5, 6, 0x21, 0x22][next(8)];
            }
            let _ = decode_frame(&b);
            let _ = decode_hello(&b);
            let _ = decode_preamble(&b);
            let _ = split_records(&b);
        }
    }

    #[test]
    fn a_debug_print_names_no_id_name_nonce_or_file_byte() {
        let id = [0x5e; ID_LEN];
        let name = "Sam's MacBook Pro";
        let device = "5e".repeat(ID_LEN);
        let frames = [
            Frame::Offer { id, size: 4_242_424, name: "secret-plan.pdf".into(), kind: "pdf".into() },
            Frame::Accept { id },
            Frame::Decline { id, reason: 4 },
            Frame::Chunk { id, offset: 777_777, data: b"hush-hush-bytes".to_vec() },
            Frame::Done { id },
            Frame::Cancel { id },
            Frame::PairYes,
            Frame::PairNo,
        ];
        let mut text = format!("{frames:?} {:?}", Preamble { mode: Mode::Transfer, id });
        text += &format!(" {:?}", Hello { id, nonce: [0xc7; 32], name: name.into() });
        text += &format!(" {:?}", Advert { id: device.clone(), name: name.into() });
        text += &format!(" {:?} {:?}", OwnId::Id(&device), Txt { v: Some("1"), id: Some(&device), name: Some(name) });
        for secret in [device.as_str(), "5e5e", name, "secret-plan", "pdf", "4242424", "777777", "hush", "104, 117, 115, 104", "c7c7", "199", "94, 94"] {
            assert!(!text.contains(secret), "{secret} in {text}");
        }
        assert!(text.contains("Offer") && text.contains("Chunk") && text.contains("reason: 4"), "{text}");
    }

    #[test]
    fn chunk_plans() {
        let f = crate::link::testutil::fixture("flow-cases.json");
        for c in arr(&f, "chunkPlans") {
            let got: Vec<Value> = plan_chunks(c["size"].as_u64().unwrap(), c["chunkSize"].as_u64().unwrap() as usize).iter().map(|&(o, l)| json!([o, l])).collect();
            assert_eq!(Value::Array(got), c["out"], "{}", name(c));
        }
    }
}
