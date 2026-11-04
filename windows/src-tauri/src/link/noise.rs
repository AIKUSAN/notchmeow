// The link's Noise layer (docs/LINK-CONTRACT.md, "On the wire" and "Notes for ports"): `Noise_XX_25519_ChaChaPoly_SHA256` pairs two machines and `Noise_KK_25519_ChaChaPoly_SHA256`
// carries a transfer, both with the prologue `notchmeow-link/1`. The cryptography is the `snow` crate's (vetted, the owner approved it on 2026-10-14); this file is the thin wrapper that
// gives the rest of the link what the contract asks for and `snow` does not promise:
//   * a low-order public key (a Diffie-Hellman result of 32 zero bytes) is refused, in our own words ("low-order point"), at the message where the contract says it must stop;
//   * the XX responder's refusal of a low-order first message is deferred to its next `write` and is then sticky: every later `write` and `read` fails the same way and `finish` refuses;
//   * only a test build can pin an ephemeral key: a release build returns an error when `Handshake::new` is given one, whatever the caller passes.
// What it does not do: the KK handshake payloads must be empty (docs/LINK-CONTRACT.md, "Transfer"), but that rule belongs to the callers, the wrapper does not enforce it. A transport message
// that fails to open leaves the receiving counter where it was: that is `snow`'s own behaviour (it decrypts before it counts), and a test pins it; the one thing the wrapper adds is a length precheck in `decrypt` (a message shorter than the 16-byte tag is refused before `snow` sees it). The secrets are
// plain byte arrays in the caller's hands and in `snow`'s state: this module does not wipe them (nothing here zeroizes), they live in the credential store and in memory only while a conversation runs.
// It is replayed against tests/fixtures/link/noise-vectors.json (all four vectors, byte for byte, and the twenty damaged-message cases).

use snow::resolvers::{CryptoResolver, DefaultResolver};
use snow::params::DHChoice;
use snow::{Builder, HandshakeState, TransportState};

pub const PROLOGUE: &[u8] = b"notchmeow-link/1";
const XX: &str = "Noise_XX_25519_ChaChaPoly_SHA256";
const KK: &str = "Noise_KK_25519_ChaChaPoly_SHA256";
/// A Noise message is at most 65535 bytes (docs/LINK-CONTRACT.md).
const MAX: usize = 65535;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoiseError(pub String);

impl NoiseError {
    fn new(s: impl Into<String>) -> NoiseError {
        NoiseError(s.into())
    }
    pub fn low_order() -> NoiseError {
        NoiseError::new("low-order point")
    }
}

impl std::fmt::Display for NoiseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for NoiseError {}

impl From<snow::Error> for NoiseError {
    fn from(e: snow::Error) -> NoiseError {
        NoiseError(format!("noise: {e}"))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Pattern {
    Xx,
    Kk,
}

/// The points of order dividing 8 on Curve25519, as 32-byte little-endian encodings with the unused top bit cleared. A DH with any of them gives all zeros.
const LOW_ORDER: [[u8; 32]; 7] = [
    [0; 32],
    {
        let mut a = [0u8; 32];
        a[0] = 1;
        a
    },
    [0xe0, 0xeb, 0x7a, 0x7c, 0x3b, 0x41, 0xb8, 0xae, 0x16, 0x56, 0xe3, 0xfa, 0xf1, 0x9f, 0xc4, 0x6a, 0xda, 0x09, 0x8d, 0xeb, 0x9c, 0x32, 0xb1, 0xfd, 0x86, 0x62, 0x05, 0x16, 0x5f, 0x49, 0xb8, 0x00],
    [0x5f, 0x9c, 0x95, 0xbc, 0xa3, 0x50, 0x8c, 0x24, 0xb1, 0xd0, 0xb1, 0x55, 0x9c, 0x83, 0xef, 0x5b, 0x04, 0x44, 0x5c, 0xc4, 0x58, 0x1c, 0x8e, 0x86, 0xd8, 0x22, 0x4e, 0xdd, 0xd0, 0x9f, 0x11, 0x57],
    {
        let mut a = [0xffu8; 32];
        a[0] = 0xec;
        a[31] = 0x7f;
        a
    },
    {
        let mut a = [0xffu8; 32];
        a[0] = 0xed;
        a[31] = 0x7f;
        a
    },
    {
        let mut a = [0xffu8; 32];
        a[0] = 0xee;
        a[31] = 0x7f;
        a
    },
];

pub fn is_low_order(public: &[u8]) -> bool {
    let Ok(mut k) = <[u8; 32]>::try_from(public) else { return false };
    k[31] &= 0x7f;
    LOW_ORDER.contains(&k)
}

/// The public key of a static private key.
pub fn public_of(private: &[u8; 32]) -> Result<[u8; 32], NoiseError> {
    let mut dh = DefaultResolver.resolve_dh(&DHChoice::Curve25519).ok_or_else(|| NoiseError::new("no curve25519"))?;
    dh.set(private);
    dh.pubkey().try_into().map_err(|_| NoiseError::new("key length"))
}

/// A fresh static key pair (private, public).
pub fn generate_static() -> Result<([u8; 32], [u8; 32]), NoiseError> {
    let pair = Builder::new(XX.parse().map_err(|_| NoiseError::new("params"))?).generate_keypair()?;
    let private: [u8; 32] = pair.private.try_into().map_err(|_| NoiseError::new("key length"))?;
    let public: [u8; 32] = pair.public.try_into().map_err(|_| NoiseError::new("key length"))?;
    Ok((private, public))
}

#[cfg(test)]
thread_local! {
    /// The ephemeral key that the handshakes made next on this thread start with, for the recorded-conversation checks. Test builds only.
    pub(crate) static FIXED_EPHEMERAL: std::cell::Cell<Option<[u8; 32]>> = const { std::cell::Cell::new(None) };
}

pub struct Handshake {
    state: HandshakeState,
    pattern: Pattern,
    initiator: bool,
    /// How many handshake messages have gone by (written or read).
    index: usize,
    /// A zero-point ephemeral key that arrived where no DH uses it yet (the XX responder's first message): the refusal comes at the next `write`, where the contract's tables put it, and stays: every
    /// later `write`, `read` and `finish` returns it too.
    deferred: Option<NoiseError>,
}

impl Handshake {
    /// `remote_static` is the other side's public key for KK (both sides know it before the first message) and None for XX. `ephemeral` pins the ephemeral key: the fixtures use it, and only
    /// a test build honours it (a release build returns an error for `Some`: a pinned key reused is a broken handshake).
    pub fn new(pattern: Pattern, initiator: bool, private: &[u8; 32], remote_static: Option<&[u8; 32]>, prologue: &[u8], ephemeral: Option<&[u8; 32]>) -> Result<Handshake, NoiseError> {
        let params = match pattern {
            Pattern::Xx => XX,
            Pattern::Kk => KK,
        }
        .parse()
        .map_err(|_| NoiseError::new("params"))?;
        // The fixtures pin the ephemeral key; in a test build the recorded-conversation checks (conformance.rs) pin it through `FIXED_EPHEMERAL` or the argument. A release build refuses a
        // pinned key outright: a reused ephemeral key breaks the handshake's secrecy, so no caller may choose one there.
        #[cfg(test)]
        let ephemeral = ephemeral.copied().or_else(|| FIXED_EPHEMERAL.with(|c| c.get()));
        #[cfg(not(test))]
        let ephemeral: Option<[u8; 32]> = if ephemeral.is_some() { return Err(NoiseError::new("a pinned ephemeral key is for tests only")) } else { None };
        let mut b = Builder::new(params).local_private_key(private).prologue(prologue);
        if let Some(rs) = remote_static {
            if is_low_order(rs) {
                return Err(NoiseError::low_order());
            }
            b = b.remote_public_key(rs);
        }
        if let Some(e) = ephemeral.as_ref() {
            b = b.fixed_ephemeral_key_for_testing_only(e);
        }
        let state = if initiator { b.build_initiator()? } else { b.build_responder()? };
        Ok(Handshake { state, pattern, initiator, index: 0, deferred: None })
    }

    /// The next handshake message to send, carrying `payload`.
    pub fn write(&mut self, payload: &[u8]) -> Result<Vec<u8>, NoiseError> {
        if let Some(e) = &self.deferred {
            return Err(e.clone());
        }
        let mut out = vec![0u8; MAX];
        let n = self.state.write_message(payload, &mut out)?;
        out.truncate(n);
        self.index += 1;
        Ok(out)
    }

    /// Opens the next handshake message and returns its payload. The ephemeral key at its front (every XX and KK message that starts with one: the first two) is refused when it is a
    /// low-order point: at once where the message's own DH uses it, at the next `write` where the first DH that uses it is in the reply (XX, responder, first message).
    pub fn read(&mut self, message: &[u8]) -> Result<Vec<u8>, NoiseError> {
        if let Some(e) = &self.deferred {
            return Err(e.clone());
        }
        if self.index < 2 && message.len() >= 32 && is_low_order(&message[..32]) {
            let err = NoiseError::low_order();
            if self.pattern == Pattern::Xx && !self.initiator && self.index == 0 {
                self.deferred = Some(err);
            } else {
                return Err(err);
            }
        }
        let mut out = vec![0u8; MAX];
        let n = self.state.read_message(message, &mut out)?;
        out.truncate(n);
        self.index += 1;
        Ok(out)
    }

    /// The other side's static public key, once the handshake has carried it (XX: after the second message for the initiator, the third for the responder; KK: known from the start).
    pub fn remote_static(&self) -> Option<[u8; 32]> {
        self.state.get_remote_static().and_then(|k| k.try_into().ok())
    }

    pub fn handshake_hash(&self) -> Vec<u8> {
        self.state.get_handshake_hash().to_vec()
    }

    /// The handshake is over: the transport state, and the other side's static key (refused when it is a low-order point).
    pub fn finish(self) -> Result<Transport, NoiseError> {
        if let Some(e) = self.deferred {
            return Err(e);
        }
        if let Some(rs) = self.remote_static() {
            if is_low_order(&rs) {
                return Err(NoiseError::low_order());
            }
        }
        Ok(Transport { state: self.state.into_transport_mode()? })
    }
}

/// The two cipher states of an established session in one value: `encrypt` uses the sending counter and `decrypt` the receiving one, as the nonce is the message count of each direction.
pub struct Transport {
    state: TransportState,
}

impl Transport {
    pub fn encrypt(&mut self, plaintext: &[u8]) -> Result<Vec<u8>, NoiseError> {
        let mut out = vec![0u8; plaintext.len() + 16];
        let n = self.state.write_message(plaintext, &mut out)?;
        out.truncate(n);
        Ok(out)
    }

    pub fn decrypt(&mut self, ciphertext: &[u8]) -> Result<Vec<u8>, NoiseError> {
        if ciphertext.len() < 16 {
            return Err(NoiseError::new("message too short"));
        }
        let mut out = vec![0u8; ciphertext.len()];
        let n = self.state.read_message(ciphertext, &mut out)?;
        out.truncate(n);
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link::bytes::{hex, key32, unhex};
    use crate::link::testutil::{arr, fixture, name};
    use serde_json::Value;

    enum Run {
        Ok { ciphertexts: Vec<String>, hash: String },
        Fail { at: usize, because: String },
    }

    fn h32(v: &Value, key: &str) -> [u8; 32] {
        key32(v[key].as_str().unwrap()).unwrap()
    }

    /// `noise_run` of reference.py: plays a vector's whole conversation, both sides, in this process. A mutation damages what is delivered, never what is sent.
    fn noise_run(v: &Value, mutation: Option<&Value>) -> Run {
        let kind = mutation.and_then(|m| m["kind"].as_str());
        let pattern = if v["protocol_name"].as_str().unwrap().contains("_KK_") { Pattern::Kk } else { Pattern::Xx };
        let (isk, rsk) = (h32(v, "init_static"), h32(v, "resp_static"));
        let (ipub, rpub) = (public_of(&isk).unwrap(), public_of(&rsk).unwrap());
        let kk = pattern == Pattern::Kk;
        let init_prologue = if kind == Some("prologue") { unhex(mutation.unwrap()["prologue"].as_str().unwrap()).unwrap() } else { unhex(v["init_prologue"].as_str().unwrap()).unwrap() };
        let resp_prologue = unhex(v["resp_prologue"].as_str().unwrap()).unwrap();
        let resp_knows = if kind == Some("static") { h32(mutation.unwrap(), "respRemoteStatic") } else { ipub };
        let mut i_hs = Some(Handshake::new(pattern, true, &isk, kk.then_some(&rpub), &init_prologue, Some(&h32(v, "init_ephemeral"))).unwrap());
        let mut r_hs = Some(Handshake::new(pattern, false, &rsk, kk.then_some(&resp_knows), &resp_prologue, Some(&h32(v, "resp_ephemeral"))).unwrap());
        let nhs = if kk { 2 } else { 3 };
        let (mut sent, mut hash) = (Vec::new(), String::new());
        let (mut ti, mut tr): (Option<Transport>, Option<Transport>) = (None, None);
        for (n, msg) in arr(v, "messages").iter().enumerate() {
            let payload = unhex(msg["payload"].as_str().unwrap()).unwrap();
            let to_resp = n % 2 == 0;
            let c = if n < nhs {
                let hs = if to_resp { i_hs.as_mut().unwrap() } else { r_hs.as_mut().unwrap() };
                hs.write(&payload)
            } else {
                let t = if to_resp { ti.as_mut().unwrap() } else { tr.as_mut().unwrap() };
                t.encrypt(&payload)
            };
            let c = match c {
                Ok(c) => c,
                Err(e) => return Run::Fail { at: n, because: e.0 },
            };
            sent.push(hex(&c));
            let mut delivered = vec![c.clone()];
            if mutation.is_some_and(|m| m["message"].as_u64() == Some(n as u64)) {
                let m = mutation.unwrap();
                match kind {
                    Some("flip") => {
                        let o = m["offset"].as_u64().unwrap() as usize;
                        delivered[0][o] ^= 1;
                    }
                    Some("truncate") => {
                        let by = m["by"].as_u64().unwrap() as usize;
                        delivered[0].truncate(c.len() - by);
                    }
                    Some("low-order") => delivered[0][..32].copy_from_slice(&[0u8; 32]),
                    Some("replay") => delivered.push(c.clone()),
                    _ => {}
                }
            }
            if kind == Some("skip") && mutation.unwrap()["message"].as_u64().unwrap() as i64 - 2 == n as i64 {
                delivered.clear(); // sent, never arrived
            }
            for d in delivered {
                let got = if n < nhs {
                    let hs = if to_resp { r_hs.as_mut().unwrap() } else { i_hs.as_mut().unwrap() };
                    hs.read(&d)
                } else {
                    let t = if to_resp { tr.as_mut().unwrap() } else { ti.as_mut().unwrap() };
                    t.decrypt(&d)
                };
                match got {
                    Err(e) => return Run::Fail { at: n, because: e.0 },
                    // A damaged message may legitimately open to another payload (message 0 is not encrypted).
                    Ok(p) if d == c && p != payload => return Run::Fail { at: n, because: "payload".into() },
                    Ok(_) => {}
                }
            }
            if n == nhs - 1 {
                let (hi, hr) = (i_hs.as_ref().unwrap().handshake_hash(), r_hs.as_ref().unwrap().handshake_hash());
                if hi != hr {
                    return Run::Fail { at: n, because: "hash".into() };
                }
                hash = hex(&hi);
                ti = Some(match i_hs.take().unwrap().finish() {
                    Ok(t) => t,
                    Err(e) => return Run::Fail { at: n, because: e.0 },
                });
                tr = Some(match r_hs.take().unwrap().finish() {
                    Ok(t) => t,
                    Err(e) => return Run::Fail { at: n, because: e.0 },
                });
            }
        }
        Run::Ok { ciphertexts: sent, hash }
    }

    #[test]
    fn the_prologue_is_the_contracts() {
        assert_eq!(hex(PROLOGUE), fixture("noise-vectors.json")["prologue"].as_str().unwrap());
    }

    #[test]
    fn every_vector_replays_byte_for_byte() {
        let f = fixture("noise-vectors.json");
        let vectors = arr(&f, "vectors");
        assert_eq!(vectors.len(), 4);
        for v in vectors {
            match noise_run(v, None) {
                Run::Ok { ciphertexts, hash } => {
                    let want: Vec<&str> = arr(v, "messages").iter().map(|m| m["ciphertext"].as_str().unwrap()).collect();
                    assert_eq!(ciphertexts, want, "{}: every ciphertext", name(v));
                    assert_eq!(hash, v["handshake_hash"].as_str().unwrap(), "{}: the handshake hash", name(v));
                }
                Run::Fail { at, because } => panic!("{}: failed at message {at}: {because}", name(v)),
            }
        }
    }

    #[test]
    fn every_damaged_conversation_stops_where_the_contract_says() {
        let f = fixture("noise-vectors.json");
        let cases = arr(&f, "rejectCases");
        assert_eq!(cases.len(), 20);
        for c in cases {
            let v = arr(&f, "vectors").iter().find(|v| v["id"] == c["vector"]).unwrap();
            match noise_run(v, Some(c)) {
                Run::Ok { .. } => panic!("{}: nothing failed", name(c)),
                Run::Fail { at, because } => {
                    assert_eq!(at as u64, c["failsAt"].as_u64().unwrap(), "{}: failed at {at} ({because})", name(c));
                    if let Some(why) = c["because"].as_str() {
                        assert_eq!(because, why, "{}: the zero point is refused as such", name(c));
                    }
                }
            }
        }
    }

    #[test]
    fn public_keys_come_from_private_ones() {
        let f = fixture("pairing-cases.json");
        let s = &f["session"];
        let v = arr(&fixture("noise-vectors.json"), "vectors").iter().find(|v| v["id"] == s["vector"]).unwrap().clone();
        assert_eq!(hex(&public_of(&h32(&v, "init_static")).unwrap()), s["staticI"].as_str().unwrap());
        assert_eq!(hex(&public_of(&h32(&v, "resp_static")).unwrap()), s["staticR"].as_str().unwrap());
        let (private, public) = generate_static().unwrap();
        assert_eq!(public_of(&private).unwrap(), public);
    }

    #[test]
    fn the_low_order_points_are_refused_with_or_without_the_top_bit() {
        for p in LOW_ORDER {
            assert!(is_low_order(&p));
            let mut hi = p;
            hi[31] |= 0x80;
            assert!(is_low_order(&hi), "the top bit is ignored by X25519");
        }
        let (_, public) = generate_static().unwrap();
        assert!(!is_low_order(&public) && !is_low_order(&[]) && !is_low_order(&[7u8; 31]));
    }

    #[test]
    fn a_message_that_does_not_open_does_not_move_the_counter() {
        // A real XX pairing with random ephemerals, then a transport message with a flipped bit, then the genuine one: the genuine one still opens.
        let (a, _) = generate_static().unwrap();
        let (b, _) = generate_static().unwrap();
        let mut i = Handshake::new(Pattern::Xx, true, &a, None, PROLOGUE, None).unwrap();
        let mut r = Handshake::new(Pattern::Xx, false, &b, None, PROLOGUE, None).unwrap();
        let m0 = i.write(&[]).unwrap();
        r.read(&m0).unwrap();
        let m1 = r.write(&[]).unwrap();
        i.read(&m1).unwrap();
        let m2 = i.write(&[]).unwrap();
        r.read(&m2).unwrap();
        let (mut ti, mut tr) = (i.finish().unwrap(), r.finish().unwrap());
        let sealed = ti.encrypt(b"hello").unwrap();
        let mut damaged = sealed.clone();
        damaged[0] ^= 1;
        assert!(tr.decrypt(&damaged).is_err());
        assert_eq!(tr.decrypt(&sealed).unwrap(), b"hello", "the failed open left the counter where it was");
        assert!(tr.decrypt(&sealed).is_err(), "and a replay does not open");
    }

    #[test]
    fn the_xx_responders_refusal_of_a_zero_first_message_is_sticky() {
        let (a, _) = generate_static().unwrap();
        let (b, _) = generate_static().unwrap();
        let mut i = Handshake::new(Pattern::Xx, true, &a, None, PROLOGUE, None).unwrap();
        let mut r = Handshake::new(Pattern::Xx, false, &b, None, PROLOGUE, None).unwrap();
        let mut m0 = i.write(&[]).unwrap();
        m0[..32].copy_from_slice(&[0u8; 32]);
        assert!(r.read(&m0).is_ok(), "no DH uses the key yet: the refusal waits for the reply");
        assert_eq!(r.write(&[]), Err(NoiseError::low_order()));
        assert_eq!(r.write(&[]), Err(NoiseError::low_order()), "a second write fails the same way and sends nothing");
        assert_eq!(r.read(&[0u8; 48]), Err(NoiseError::low_order()), "and so does a read");
        assert!(matches!(r.finish(), Err(e) if e == NoiseError::low_order()), "the handshake cannot be finished");
    }

    #[test]
    fn a_test_build_still_pins_the_ephemeral_key() {
        let (a, _) = generate_static().unwrap();
        let pin = [7u8; 32];
        let first = |e: Option<&[u8; 32]>| Handshake::new(Pattern::Xx, true, &a, None, PROLOGUE, e).unwrap().write(&[]).unwrap();
        assert_eq!(first(Some(&pin)), first(Some(&pin)), "the same pinned key gives the same first message");
        assert_eq!(&first(Some(&pin))[..32], &public_of(&pin).unwrap()[..], "and the message starts with that key's public half");
        assert_ne!(first(None), first(None), "unpinned handshakes draw fresh keys");
    }

    #[test]
    fn another_prologue_cannot_complete_a_handshake() {
        let (a, _) = generate_static().unwrap();
        let (b, _) = generate_static().unwrap();
        let mut i = Handshake::new(Pattern::Xx, true, &a, None, b"notchmeow-link/2", None).unwrap();
        let mut r = Handshake::new(Pattern::Xx, false, &b, None, PROLOGUE, None).unwrap();
        let m0 = i.write(&[]).unwrap();
        r.read(&m0).unwrap();
        let m1 = r.write(&[]).unwrap();
        assert!(i.read(&m1).is_err());
    }
}
