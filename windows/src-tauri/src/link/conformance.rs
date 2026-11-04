// The recorded conversations (sub-project G2, the cross-check with the Mac): the conversation of `noise-vectors.json` is bytes that the Mac's CryptoKit code produced and an independent
// implementation (`tests/link-crosscheck/xcheck.swift`) confirmed. Here the **real runs** of this app (`run_responder`, `run_initiator`, `run_receive`, `run_send`) are started with the
// vector's keys, ephemeral keys, nonces and names, and the other side is the recording: what the run writes must be the recording's bytes, and what it reads is the recording's. So the
// pairing's payloads (the commitment, the two hellos), the preamble, the Noise messages and the code that comes out are the same on both apps, byte for byte, without the two apps ever
// running together. (The vector's transport messages hold test bytes and not frames, so the replay stops after the handshake.) The ephemeral key is pinned through
// `noise::FIXED_EPHEMERAL`, which exists in test builds only.

use std::sync::{Arc, Mutex};

use serde_json::Value;

use super::bytes::{hex, id16, key32, unhex};
use super::channel::{MemoryEnd, Transport};
use super::files::Source;
use super::frames::{decode_hello, decode_preamble, Mode};
use super::identity::{Identity, Peer};
use super::noise::{public_of, FIXED_EPHEMERAL};
use super::pair_run::{pair_channel, run_initiator, run_responder, Clock, PairHooks};
use super::pairing::{Ids, Initiator, Responder};
use super::testutil::{arr, fixture};
use super::transfer::{receive_channel, run_receive, run_send, send_channel, ReceiveHooks, ReceiveTimings, SendHooks, SendTimings};

fn vector(id: &str) -> Value {
    arr(&fixture("noise-vectors.json"), "vectors").iter().find(|v| v["id"] == id).unwrap_or_else(|| panic!("vector {id}")).clone()
}

fn bytes_of(v: &Value, i: usize, field: &str) -> Vec<u8> {
    unhex(arr(v, "messages")[i][field].as_str().unwrap()).unwrap()
}

fn key(v: &Value, name: &str) -> [u8; 32] {
    key32(v[name].as_str().unwrap()).unwrap()
}

fn clock() -> Clock {
    Arc::new(|| 1_000)
}

fn identity(private: [u8; 32], device_id: [u8; 16], name: &str) -> Identity {
    Identity { device_id: hex(&device_id), name: name.to_string(), key: private, public: public_of(&private).unwrap() }
}

fn hooks(shown: Arc<Mutex<Vec<(String, String)>>>) -> PairHooks {
    PairHooks { show_code: Arc::new(move |code, name| shown.lock().unwrap().push((code, name))), handshake_done: Arc::new(|| {}) }
}

async fn code_shown(shown: &Arc<Mutex<Vec<(String, String)>>>) -> (String, String) {
    for _ in 0..2000 {
        if let Some(x) = shown.lock().unwrap().first() {
            return x.clone();
        }
        tokio::time::sleep(std::time::Duration::from_millis(2)).await;
    }
    panic!("no code was shown");
}

#[tokio::test]
async fn the_responder_run_speaks_the_recorded_pairing_byte_for_byte_and_shows_the_recorded_code() {
    let v = vector("xx-link");
    let session = &fixture("pairing-cases.json")["session"];
    let my_hello = decode_hello(&bytes_of(&v, 1, "payload")).unwrap(); // the responder's hello: its id, its nonce, its name
    let their_hello = decode_hello(&bytes_of(&v, 2, "payload")).unwrap();
    let me = identity(key(&v, "resp_static"), my_hello.id, &my_hello.name);
    FIXED_EPHEMERAL.with(|c| c.set(Some(key(&v, "resp_ephemeral"))));
    let (recording, end) = MemoryEnd::pair();
    let shown = Arc::new(Mutex::new(Vec::new()));
    let (_handle, inbox) = pair_channel();
    let h = hooks(shown.clone());
    let nonce = my_hello.nonce;
    let run = tokio::spawn(async move {
        let pre = decode_preamble(&end.receive().await.unwrap()).unwrap(); // the listener reads the preamble first
        assert_eq!(pre.mode, Mode::Pair);
        run_responder(end, &me, nonce, clock(), Responder::new(Ids::default()), &h, inbox).await
    });
    recording.send(super::frames::encode_preamble(Mode::Pair, &[0; 16])).await.unwrap();
    recording.send(bytes_of(&v, 0, "ciphertext")).await.unwrap();
    assert_eq!(recording.receive().await.unwrap(), bytes_of(&v, 1, "ciphertext"), "the responder's reply is the recording's");
    recording.send(bytes_of(&v, 2, "ciphertext")).await.unwrap();
    let (code, peer_name) = code_shown(&shown).await;
    assert_eq!(code, session["code"].as_str().unwrap(), "the six digits are the recorded ones");
    assert_eq!(peer_name, their_hello.name);
    recording.close().await;
    assert!(run.await.is_ok(), "the run ended without a panic");
}

#[tokio::test]
async fn the_initiator_run_speaks_the_recorded_pairing_byte_for_byte_and_shows_the_recorded_code() {
    let v = vector("xx-link");
    let session = &fixture("pairing-cases.json")["session"];
    let their_hello = decode_hello(&bytes_of(&v, 1, "payload")).unwrap();
    let my_hello = decode_hello(&bytes_of(&v, 2, "payload")).unwrap(); // the initiator's reveal: its id, its nonce, its name
    let me = identity(key(&v, "init_static"), my_hello.id, &my_hello.name);
    FIXED_EPHEMERAL.with(|c| c.set(Some(key(&v, "init_ephemeral"))));
    let (end, recording) = MemoryEnd::pair();
    let shown = Arc::new(Mutex::new(Vec::new()));
    let (_handle, inbox) = pair_channel();
    let h = hooks(shown.clone());
    let nonce = my_hello.nonce;
    let run = tokio::spawn(async move { run_initiator(end, &me, nonce, clock(), Initiator::new(Ids::default()), &h, inbox).await });
    let pre = decode_preamble(&recording.receive().await.unwrap()).unwrap();
    assert_eq!((pre.mode, pre.id), (Mode::Pair, [0; 16]));
    assert_eq!(recording.receive().await.unwrap(), bytes_of(&v, 0, "ciphertext"), "the commitment goes out as recorded");
    recording.send(bytes_of(&v, 1, "ciphertext")).await.unwrap();
    assert_eq!(recording.receive().await.unwrap(), bytes_of(&v, 2, "ciphertext"), "and so does the reveal");
    let (code, peer_name) = code_shown(&shown).await;
    assert_eq!(code, session["code"].as_str().unwrap(), "the six digits are the recorded ones");
    assert_eq!(peer_name, their_hello.name);
    recording.close().await;
    assert!(run.await.is_ok(), "the run ended without a panic");
}

fn receive_hooks() -> ReceiveHooks {
    ReceiveHooks {
        offered: Arc::new(|_| {}),
        progress: Arc::new(|_, _| {}),
        claim: Arc::new(|_| true),
        release: Arc::new(|_| {}),
        handshake_done: Arc::new(|| {}),
        admit: Arc::new(|| true),
        release_at_end: true,
    }
}

#[tokio::test]
async fn the_receiving_run_answers_the_recorded_transfer_handshake_byte_for_byte() {
    let v = vector("kk-link");
    let sender = identity(key(&v, "init_static"), [0x11; 16], "Sender");
    let me = identity(key(&v, "resp_static"), [0x22; 16], "Receiver");
    let peer = Peer { id: sender.device_id.clone(), name: sender.name.clone(), key: hex(&sender.public), at: 0 };
    FIXED_EPHEMERAL.with(|c| c.set(Some(key(&v, "resp_ephemeral"))));
    let (recording, end) = MemoryEnd::pair();
    let (_handle, inbox) = receive_channel();
    let run = tokio::spawn(async move {
        decode_preamble(&end.receive().await.unwrap()).unwrap();
        run_receive(end, &me, &peer, std::env::temp_dir().join("notchmeow-conformance"), false, &receive_hooks(), ReceiveTimings::default(), inbox).await
    });
    recording.send(super::frames::encode_preamble(Mode::Transfer, &id16(&sender.device_id).unwrap())).await.unwrap();
    recording.send(bytes_of(&v, 0, "ciphertext")).await.unwrap();
    assert_eq!(recording.receive().await.unwrap(), bytes_of(&v, 1, "ciphertext"), "the receiver's reply is the recording's");
    recording.close().await;
    assert!(run.await.is_ok(), "the run ended without a panic");
}

#[tokio::test]
async fn the_sending_run_opens_the_recorded_transfer_handshake_byte_for_byte() {
    let v = vector("kk-link");
    let me = identity(key(&v, "init_static"), [0x11; 16], "Sender");
    let receiver = identity(key(&v, "resp_static"), [0x22; 16], "Receiver");
    let peer = Peer { id: receiver.device_id.clone(), name: receiver.name.clone(), key: hex(&receiver.public), at: 0 };
    FIXED_EPHEMERAL.with(|c| c.set(Some(key(&v, "init_ephemeral"))));
    let dir = std::env::temp_dir().join(format!("notchmeow-conformance-src-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join("a.txt");
    std::fs::write(&file, b"hello").unwrap();
    let (end, recording) = MemoryEnd::pair();
    let (_handle, inbox) = send_channel(&end, 2_000);
    let source = Source::open(&file).unwrap();
    let run = tokio::spawn(async move { run_send(end, &me, &peer, source, &SendHooks { progress: Arc::new(|_, _| {}) }, SendTimings::default(), inbox).await });
    let pre = decode_preamble(&recording.receive().await.unwrap()).unwrap();
    assert_eq!((pre.mode, hex(&pre.id)), (Mode::Transfer, hex(&[0x11; 16])));
    assert_eq!(recording.receive().await.unwrap(), bytes_of(&v, 0, "ciphertext"), "the sender's opening is the recording's");
    recording.send(bytes_of(&v, 1, "ciphertext")).await.unwrap();
    recording.close().await;
    assert!(run.await.is_ok(), "the run ended without a panic");
}
