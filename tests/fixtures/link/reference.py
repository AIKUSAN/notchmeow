#!/usr/bin/env python3
"""Reference implementation of NotchMeow's link contract (sub-project G2).

The rules both apps must agree on when two machines pair and send each other files: the two Noise
handshakes (Noise_XX_25519_ChaChaPoly_SHA256 to pair, Noise_KK_25519_ChaChaPoly_SHA256 to transfer),
the pairing code, the frames, the receiver's and the sender's rules, and the file-name sanitizer.
Runs every fixture in tests/fixtures/link/ against them, then a few self-checks and seeded fuzzes.
Standard library only: the X25519, ChaCha20 and Poly1305 below are written out so that the reference
needs no package, and they are checked against the RFC 7748 and RFC 8439 test vectors. Exit status 1
if anything fails. Both apps implement the same rules natively; this file is the tie-breaker when they
disagree. It is a reference, not production code: it is not constant-time and no app may use it.
"""
import hashlib
import hmac
import json
import os
import random
import re
import struct
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
FAILURES = 0


# ---- the primitives (RFC 7748 X25519, RFC 8439 ChaCha20-Poly1305) ----------------------------------
P25519 = 2**255 - 19
M32 = 0xFFFFFFFF
BASE_POINT = bytes([9]) + bytes(31)


def x25519(k, u):
    """X25519(k, u) of RFC 7748: the 32-byte shared value of private key k and public key u."""
    kl = bytearray(k)
    kl[0] &= 248
    kl[31] &= 127
    kl[31] |= 64
    kn = int.from_bytes(kl, "little")
    x1 = int.from_bytes(u, "little") & ((1 << 255) - 1)
    x2, z2, x3, z3, swap = 1, 0, x1, 1, 0
    for t in range(254, -1, -1):
        kt = (kn >> t) & 1
        swap ^= kt
        if swap:
            x2, x3, z2, z3 = x3, x2, z3, z2
        swap = kt
        a = (x2 + z2) % P25519
        aa = a * a % P25519
        b = (x2 - z2) % P25519
        bb = b * b % P25519
        e = (aa - bb) % P25519
        c = (x3 + z3) % P25519
        d = (x3 - z3) % P25519
        da = d * a % P25519
        cb = c * b % P25519
        x3 = (da + cb) ** 2 % P25519
        z3 = x1 * (da - cb) ** 2 % P25519
        x2 = aa * bb % P25519
        z2 = e * (aa + 121665 * e) % P25519
    if swap:
        x2, x3, z2, z3 = x3, x2, z3, z2
    return (x2 * pow(z2, P25519 - 2, P25519) % P25519).to_bytes(32, "little")


def x25519_pub(priv):
    return x25519(priv, BASE_POINT)


def _quarter(s, a, b, c, d):
    s[a] = (s[a] + s[b]) & M32
    s[d] ^= s[a]
    s[d] = ((s[d] << 16) | (s[d] >> 16)) & M32
    s[c] = (s[c] + s[d]) & M32
    s[b] ^= s[c]
    s[b] = ((s[b] << 12) | (s[b] >> 20)) & M32
    s[a] = (s[a] + s[b]) & M32
    s[d] ^= s[a]
    s[d] = ((s[d] << 8) | (s[d] >> 24)) & M32
    s[c] = (s[c] + s[d]) & M32
    s[b] ^= s[c]
    s[b] = ((s[b] << 7) | (s[b] >> 25)) & M32


def chacha20_block(key, counter, nonce):
    st = [0x61707865, 0x3320646E, 0x79622D32, 0x6B206574] + list(struct.unpack("<8I", key)) + [counter] + list(struct.unpack("<3I", nonce))
    w = st[:]
    for _ in range(10):
        _quarter(w, 0, 4, 8, 12)
        _quarter(w, 1, 5, 9, 13)
        _quarter(w, 2, 6, 10, 14)
        _quarter(w, 3, 7, 11, 15)
        _quarter(w, 0, 5, 10, 15)
        _quarter(w, 1, 6, 11, 12)
        _quarter(w, 2, 7, 8, 13)
        _quarter(w, 3, 4, 9, 14)
    return struct.pack("<16I", *[(w[i] + st[i]) & M32 for i in range(16)])


def chacha20_xor(key, counter, nonce, data):
    out = bytearray()
    for i in range(0, len(data), 64):
        ks = chacha20_block(key, counter + i // 64, nonce)
        out += bytes(a ^ b for a, b in zip(data[i:i + 64], ks))
    return bytes(out)


def poly1305(key, msg):
    r = int.from_bytes(key[:16], "little") & 0x0FFFFFFC0FFFFFFC0FFFFFFC0FFFFFFF
    s = int.from_bytes(key[16:], "little")
    acc, p = 0, (1 << 130) - 5
    for i in range(0, len(msg), 16):
        acc = (acc + int.from_bytes(msg[i:i + 16] + b"\x01", "little")) * r % p
    return ((acc + s) & ((1 << 128) - 1)).to_bytes(16, "little")


def _pad16(b):
    return bytes(-len(b) % 16)


def _aead_mac(key, nonce, aad, ct):
    otk = chacha20_block(key, 0, nonce)[:32]
    return poly1305(otk, aad + _pad16(aad) + ct + _pad16(ct) + struct.pack("<QQ", len(aad), len(ct)))


def aead_encrypt(key, nonce, aad, pt):
    """ChaCha20-Poly1305 (RFC 8439): ciphertext followed by the 16-byte tag."""
    ct = chacha20_xor(key, 1, nonce, pt)
    return ct + _aead_mac(key, nonce, aad, ct)


def aead_decrypt(key, nonce, aad, boxed):
    if len(boxed) < 16:
        raise ValueError("short")
    ct, tag = boxed[:-16], boxed[-16:]
    if not hmac.compare_digest(_aead_mac(key, nonce, aad, ct), tag):
        raise ValueError("tag")
    return chacha20_xor(key, 1, nonce, ct)
# ---- Noise (Task 2): the Noise Protocol Framework, revision 34, for exactly the two patterns the link uses ----------
PROTOCOL_VERSION = 1
PROLOGUE = b"notchmeow-link/1"          # bound into both handshakes, so a version mismatch fails them
NOISE_MAX = 65535                        # the most bytes of one Noise message, tag included
TAG = 16


class NoiseError(Exception):
    pass


def hkdf2(ck, ikm):
    temp = hmac.new(ck, ikm, hashlib.sha256).digest()
    out1 = hmac.new(temp, b"\x01", hashlib.sha256).digest()
    out2 = hmac.new(temp, out1 + b"\x02", hashlib.sha256).digest()
    return out1, out2


class CipherState:
    def __init__(self, k=None):
        self.k, self.n = k, 0

    def _nonce(self):
        return bytes(4) + self.n.to_bytes(8, "little")     # 32 zero bits, then the counter, little-endian

    def encrypt(self, ad, pt):
        if len(pt) + (TAG if self.k is not None else 0) > NOISE_MAX:      # the sealed output (tag included) is one Noise message: 65535 bytes at most
            raise NoiseError("message too long")
        if self.k is None:
            return pt
        if self.n >= 2**64 - 1:
            raise NoiseError("nonce exhausted")
        out = aead_encrypt(self.k, self._nonce(), ad, pt)
        self.n += 1
        return out

    def decrypt(self, ad, ct):
        if len(ct) > NOISE_MAX:                                             # the ciphertext, tag included, is one Noise message: 65535 bytes at most
            raise NoiseError("message too long")
        if self.k is None:
            return ct
        if self.n >= 2**64 - 1:
            raise NoiseError("nonce exhausted")
        try:
            out = aead_decrypt(self.k, self._nonce(), ad, ct)
        except ValueError:
            raise NoiseError("decrypt")
        self.n += 1                                         # only after a good tag: a refused message does not move the counter
        return out


class Symmetric:
    def __init__(self, name):
        nb = name.encode("ascii")
        self.h = nb + bytes(32 - len(nb)) if len(nb) <= 32 else hashlib.sha256(nb).digest()
        self.ck, self.cs = self.h, CipherState()

    def mix_hash(self, data):
        self.h = hashlib.sha256(self.h + data).digest()

    def mix_key(self, ikm):
        self.ck, k = hkdf2(self.ck, ikm)
        self.cs = CipherState(k)

    def encrypt_and_hash(self, pt):
        ct = self.cs.encrypt(self.h, pt)
        self.mix_hash(ct)
        return ct

    def decrypt_and_hash(self, ct):
        pt = self.cs.decrypt(self.h, ct)
        self.mix_hash(ct)
        return pt

    def split(self):
        k1, k2 = hkdf2(self.ck, b"")
        return CipherState(k1), CipherState(k2)


# Tokens: e, s send a public key; ee, es, se, ss mix in a DH. In "es" the first letter is the initiator's key and the second the responder's.
PATTERNS = {
    "XX": {"pre": [], "msgs": [["e"], ["e", "ee", "s", "es"], ["s", "se"]]},
    "KK": {"pre": ["i", "r"], "msgs": [["e", "es", "ss"], ["e", "ee", "se"]]},
}


def protocol_name(pattern):
    return "Noise_%s_25519_ChaChaPoly_SHA256" % pattern


class Handshake:
    """One side of a handshake. `s` is the static private key, `rs` the remote static public key (KK needs it before the first message),
    `e` the ephemeral private key: the fixtures inject it, an app leaves it None and gets a random one."""

    def __init__(self, pattern, initiator, prologue, s, rs=None, e=None):
        self.pat, self.initiator, self.s, self.rs, self.e = PATTERNS[pattern], initiator, s, rs, e
        self.s_pub, self.re, self.i = x25519_pub(s), None, 0
        self.sym = Symmetric(protocol_name(pattern))
        self.sym.mix_hash(prologue)
        for who in self.pat["pre"]:                          # the pre-messages "-> s" then "<- s"
            mine = (who == "i") == initiator
            if not mine and rs is None:
                raise NoiseError("the pattern needs the remote static key")
            self.sym.mix_hash(self.s_pub if mine else rs)

    def my_turn(self):
        return self.i < len(self.pat["msgs"]) and (self.i % 2 == 0) == self.initiator

    def done(self):
        return self.i == len(self.pat["msgs"])

    def _dh(self, tok):
        mine, theirs = (tok[0], tok[1]) if self.initiator else (tok[1], tok[0])
        out = x25519(self.e if mine == "e" else self.s, self.re if theirs == "e" else self.rs)
        if out == bytes(32):                                  # a low-order point: refuse (RFC 7748 section 6.1)
            raise NoiseError("low-order point")
        self.sym.mix_key(out)

    def write(self, payload=b""):
        if not self.my_turn():
            raise NoiseError("not my turn")
        buf = b""
        for tok in self.pat["msgs"][self.i]:
            if tok == "e":
                if self.e is None:
                    self.e = os.urandom(32)
                buf += x25519_pub(self.e)
                self.sym.mix_hash(x25519_pub(self.e))
            elif tok == "s":
                buf += self.sym.encrypt_and_hash(self.s_pub)
            else:
                self._dh(tok)
        buf += self.sym.encrypt_and_hash(payload)
        if len(buf) > NOISE_MAX:
            raise NoiseError("message too long")
        self.i += 1
        return buf

    def read(self, msg):
        if self.done() or self.my_turn():
            raise NoiseError("not my turn")
        if len(msg) > NOISE_MAX:
            raise NoiseError("message too long")
        pos = 0
        for tok in self.pat["msgs"][self.i]:
            if tok == "e":
                if len(msg) - pos < 32:
                    raise NoiseError("short")
                self.re = msg[pos:pos + 32]
                pos += 32
                self.sym.mix_hash(self.re)
            elif tok == "s":
                n = 32 + (TAG if self.sym.cs.k is not None else 0)
                if len(msg) - pos < n:
                    raise NoiseError("short")
                self.rs = self.sym.decrypt_and_hash(msg[pos:pos + n])
                pos += n
            else:
                self._dh(tok)
        payload = self.sym.decrypt_and_hash(msg[pos:])
        self.i += 1
        return payload

    def finish(self):
        """After the last message: the handshake hash, and (send, receive) cipher states for this side."""
        if not self.done():
            raise NoiseError("not finished")
        c1, c2 = self.sym.split()
        return self.sym.h, ((c1, c2) if self.initiator else (c2, c1))


def noise_run(v, mutation=None):
    """Plays a fixture vector's whole conversation, both sides, in this process. Returns ("ok", ciphertexts as hex, handshake hash as hex)
    or ("fail", the index of the message at which a side refused, the reference's own reason). A mutation damages what is delivered, never what is sent:
    {"kind": "flip", "message": i, "offset": o}   one bit of byte o of message i
    {"kind": "truncate", "message": i, "by": n}   the last n bytes of message i
    {"kind": "low-order", "message": 0}           message 0's ephemeral key becomes 32 zero bytes
    {"kind": "replay", "message": i}              message i arrives twice
    {"kind": "skip", "message": i}                message i-2 (the sender's previous one) is lost, then message i arrives
    {"kind": "prologue", "prologue": hex}         the initiator was started with another prologue
    {"kind": "static", "respRemoteStatic": hex}   the responder holds another key for the initiator (KK)"""
    m = mutation or {}
    kind = m.get("kind")
    pattern = v["protocol_name"].split("_")[1]
    isk, rsk = bytes.fromhex(v["init_static"]), bytes.fromhex(v["resp_static"])
    kk = pattern == "KK"
    i = Handshake(pattern, True, bytes.fromhex(m["prologue"] if kind == "prologue" else v["init_prologue"]), isk,
                  rs=x25519_pub(rsk) if kk else None, e=bytes.fromhex(v["init_ephemeral"]))
    r = Handshake(pattern, False, bytes.fromhex(v["resp_prologue"]), rsk,
                  rs=(bytes.fromhex(m["respRemoteStatic"]) if kind == "static" else x25519_pub(isk)) if kk else None, e=bytes.fromhex(v["resp_ephemeral"]))
    nhs, sent, h = len(PATTERNS[pattern]["msgs"]), [], None
    i_send = i_recv = r_send = r_recv = None
    for n, msg in enumerate(v["messages"]):
        payload = bytes.fromhex(msg["payload"])
        to_resp = n % 2 == 0                                   # messages alternate, the initiator first, transport messages included
        try:
            if n < nhs:
                c = (i if to_resp else r).write(payload)
            else:
                c = (i_send if to_resp else r_send).encrypt(b"", payload)
        except NoiseError as e:
            return ("fail", n, str(e))
        sent.append(c.hex())
        delivered = [c]
        if m.get("message") == n:
            if kind == "flip":
                delivered = [c[:m["offset"]] + bytes([c[m["offset"]] ^ 1]) + c[m["offset"] + 1:]]
            elif kind == "truncate":
                delivered = [c[:len(c) - m["by"]]]
            elif kind == "low-order":
                delivered = [bytes(32) + c[32:]]
            elif kind == "replay":
                delivered = [c, c]
        if kind == "skip" and m["message"] - 2 == n:
            delivered = []                                     # sent, never arrived
        for d in delivered:
            try:
                got = (r if to_resp else i).read(d) if n < nhs else (r_recv if to_resp else i_recv).decrypt(b"", d)
            except NoiseError as e:
                return ("fail", n, str(e))
            if d == c and got != payload:                      # a damaged message may legitimately open to another payload (message 0 is not encrypted)
                return ("fail", n, "payload")
        if n == nhs - 1:
            (hi, (i_send, i_recv)), (hr, (r_send, r_recv)) = i.finish(), r.finish()
            if hi != hr:
                return ("fail", n, "hash")
            h = hi
    return ("ok", sent, h.hex())
# ---- the pairing code: a commitment, two nonces and the two static keys (Task 3) ------------------------------------
# The construction is the short-authenticated-string pattern of Vaudenay (CRYPTO 2005), ZRTP (RFC 6189, the hash commitment) and Bluetooth's numeric
# comparison (Core Specification, Vol 3, Part H, 2.3.5.6.2: f4 and g2): one side commits to its nonce before it has seen the other's, the other side
# answers with a nonce of its own, the first side then reveals, and the short code is a hash of both nonces and both public keys. A man in the middle
# has to choose its keys and its nonce for each side before the honest side's nonce is known, so it gets one guess at the code per attempt.
CODE_DIGITS = 6                                   # the spec's 6; the commitment is what keeps it safe
COMMIT_LABEL = b"notchmeow-link pairing commit v1"
CODE_LABEL = b"notchmeow-link pairing code v1"
PAIR_GAP_MS = 30_000                              # at most one pairing attempt every 30 seconds
PAIR_WINDOW_MS = 120_000                          # the pairing window closes after 2 minutes
OFFER_TIMEOUT_MS = 120_000                        # an offer nobody answers is declined after 2 minutes


def _bytes32(*values):
    return all(isinstance(v, (bytes, bytearray)) and len(v) == 32 for v in values)


def commit_of(nonce, static_pub):
    """The initiator's commitment, sent in the clear as the payload of the first Noise message: SHA-256 over the label, its static public key and its
    fresh 32-byte nonce. Binding the key means a commitment cannot be moved to another key; the nonce stays secret until the reveal."""
    if not _bytes32(nonce, static_pub):
        raise ValueError("commit_of needs a 32-byte nonce and a 32-byte static public key")
    return hashlib.sha256(COMMIT_LABEL + bytes(static_pub) + bytes(nonce)).digest()


def pairing_code(nonce_i, nonce_r, static_i, static_r):
    """The six digits both screens show: SHA-256 over the label, the initiator's static key, the responder's static key, the initiator's nonce and the
    responder's nonce (always in that order); the first 8 bytes as a big-endian number; modulo 10**6; written with leading zeros.
    The handshake hash is deliberately not an input: the last sender's payload (its name, say) is in it and is free to vary after that sender has seen
    the other's nonce, which would let a man in the middle grind the code offline. The static keys are enough: the handshake authenticates them."""
    if not _bytes32(nonce_i, nonce_r, static_i, static_r):
        raise ValueError("pairing_code needs two 32-byte nonces and two 32-byte static public keys")
    d = hashlib.sha256(CODE_LABEL + bytes(static_i) + bytes(static_r) + bytes(nonce_i) + bytes(nonce_r)).digest()
    return str(int.from_bytes(d[:8], "big") % 10**CODE_DIGITS).zfill(CODE_DIGITS)


def _ms(v):
    return isinstance(v, int) and not isinstance(v, bool) and v >= 0


def pairing_attempt_allowed(last_ms, now_ms):
    """last_ms is None for the first attempt. Allowed when PAIR_GAP_MS have passed; a clock that went back, or a value that is not whole milliseconds, refuses."""
    if not _ms(now_ms) or not (last_ms is None or _ms(last_ms)):
        return False
    return last_ms is None or now_ms - last_ms >= PAIR_GAP_MS


def pairing_window_open(start_ms, now_ms):
    return _ms(start_ms) and _ms(now_ms) and 0 <= now_ms - start_ms < PAIR_WINDOW_MS


def offer_expired(offered_ms, now_ms):
    """Expired at exactly OFFER_TIMEOUT_MS. A clock that went back, or a bad value, counts as expired: declining is the safe side."""
    if not _ms(offered_ms) or not _ms(now_ms):
        return True
    return not 0 <= now_ms - offered_ms < OFFER_TIMEOUT_MS
# ---- the pairing in order: the two machines of commit, nonce, reveal and confirm (Task 4) ---------------------------------
# The initiator (the machine whose user started the pairing) sends commit_of(nonce, static) as the payload of the first Noise message; the responder answers
# with its own nonce in the payload of the second; the initiator reveals its nonce in the payload of the third; both then compute pairing_code and show it.
# Each user answers "They match" (yes) or no; a pair-yes or pair-no frame tells the other side; a key is stored only when both said yes.
# Events carry the clock ("now", whole milliseconds on a monotonic clock) and the random values an app would draw ("nonce"); the machines draw nothing.
def _hex32(v):
    return isinstance(v, str) and len(v) == 64 and all(c in "0123456789abcdef" for c in v)


def _id_hex(v):
    """A device id on the wire is 16 bytes: 32 lower-case hex digits."""
    return isinstance(v, str) and len(v) == 2 * ID_LEN and all(c in "0123456789abcdef" for c in v)


def _pout(state, send=(), notify=None, because=None):
    return {"state": state, "send": list(send), "notify": notify, "because": because}


def _ids(state):
    """The two pairing inputs a machine keeps from one step to the next: its own device id (own_id) and the devices it has paired (paired: device id -> the
    static public key stored for it, both lower-case hex). Absent when not given, so a machine without them behaves as before."""
    return {k: state[k] for k in ("own_id", "paired") if k in state}


def _ids_canonical(state):
    """False when the machine's own id, if it has one, is not 32 lower-case hex digits, or a paired id is not 32 lower-case hex digits, or a paired key is not 64.
    Fail closed: a capital letter is never lower-cased, so it cannot make a paired id look new. An absent own_id and an empty paired map are the unconfigured case."""
    if "own_id" in state and not _id_hex(state["own_id"]):
        return False
    return all(_id_hex(i) and _hex32(k) for i, k in state.get("paired", {}).items())


def _peer_refusal(state, peer_id, peer_static, length_reason):
    """Why a peer's hello is refused, given the machine's own id and its paired devices. Whatever the machine knows, a hello with no valid device id is refused as length_reason
    (the owner's rule, 2026-10-14: the check is unconditional), and an all-zero device id as "device-id", the reason the hello decoder uses. A machine whose own id or paired
    ids or keys are not canonical refuses every hello as "device-id" (see _ids_canonical). Then "own-id" when the peer's
    device id is this machine's own; "id-key-mismatch" when it is paired under another key (the user removes the device first to re-pair); None otherwise. The same id under
    the key stored for it is allowed. The static key compared is the one the Noise handshake authenticated, never a value in the hello (the hello has none)."""
    if not _id_hex(peer_id):
        return length_reason
    if peer_id == "00" * ID_LEN:
        return "device-id"
    if not _ids_canonical(state):
        return "device-id"
    if state.get("own_id") == peer_id:
        return "own-id"
    if state.get("paired", {}).get(peer_id, peer_static) != peer_static:
        return "id-key-mismatch"
    return None


def _answer(state, ev, idle):
    """The part both machines share: a click, or the other side's pair-yes or pair-no, after the code is shown. Anything but exactly "yes" is a no."""
    if state["s"] != "coded":
        return _pout(state)                                          # an answer before there is a code is ignored
    if not pairing_window_open(state["start"], ev.get("now")):
        return _pout(idle, notify="discard", because="window-closed")
    who, ans = ("mine", ev["user"]) if "user" in ev else ("theirs", ev["peer"])
    if ans != "yes":
        return _pout(idle, [{"pair": "no"}] if who == "mine" else [], "discard", because="said-no")
    new = {**state, who: "yes"}
    send = [{"pair": "yes"}] if who == "mine" else []
    if new["mine"] == "yes" and new["theirs"] == "yes":
        return _pout(idle, send, "store")
    return _pout(new, send)


def pair_responder_step(state, ev):
    """The machine of the machine that is asked to pair. state: {"s": "idle", seen, last} | {"s": "committed", commit, start, nonce, seen, last} |
    {"s": "coded", start, code, mine, theirs, seen, last}; seen is the list of {commit, at} the app keeps across connections, last the time of the last attempt (or None).
    Optional, carried unchanged: own_id (this machine's device id, hex) and paired (device id -> static key, hex), see _ids.
    ev: {"commit": hex, "nonce": hex, "now"} (the first message arrived; nonce is the app's fresh one) | {"reveal": {"nonce", "static", "own", "peerId"}, "now"} (the third
    message was opened: the initiator's nonce and static key, this machine's own static key, and the initiator's device id from its hello) | {"user": "yes"|"no", "now"} |
    {"peer": "yes"|"no", "now"}.
    Returns {state, send, notify, because}: send holds {"nonce": hex} or {"pair": "yes"|"no"}; notify is nonce-sent, show-code, store or discard;
    because names the refusal (the connection is then closed and the state is idle again): commit-length, commit-replayed, attempt-too-soon, no-commit,
    reveal-late, reveal-length, reveal-mismatch, device-id, own-id, id-key-mismatch, unexpected, window-closed, said-no."""
    keep = {"seen": state["seen"], "last": state["last"], **_ids(state)}
    idle = {"s": "idle", **keep}
    now = ev.get("now")
    if "commit" in ev:
        if state["s"] != "idle":
            return _pout(idle, because="unexpected")
        if not _hex32(ev["commit"]) or not _hex32(ev.get("nonce")):
            return _pout(idle, because="commit-length")
        if any(e["commit"] == ev["commit"] and pairing_window_open(e["at"], now) for e in state["seen"]):
            return _pout(idle, because="commit-replayed")              # checked before the gap, so a replay is named as one
        if not pairing_attempt_allowed(state["last"], now):
            return _pout(idle, because="attempt-too-soon")
        seen = [e for e in state["seen"] if pairing_window_open(e["at"], now)] + [{"commit": ev["commit"], "at": now}]
        return _pout({"s": "committed", "commit": ev["commit"], "start": now, "nonce": ev["nonce"], "seen": seen, "last": now, **_ids(state)}, [{"nonce": ev["nonce"]}], "nonce-sent")
    if "reveal" in ev:
        r = ev["reveal"]
        if state["s"] == "idle":
            return _pout(idle, because="no-commit")                    # a reveal with no commitment before it
        if state["s"] != "committed":
            return _pout(idle, because="unexpected")
        if not pairing_window_open(state["start"], now):
            return _pout(idle, because="reveal-late")
        if not (_hex32(r.get("nonce")) and _hex32(r.get("static")) and _hex32(r.get("own"))):
            return _pout(idle, because="reveal-length")
        if commit_of(bytes.fromhex(r["nonce"]), bytes.fromhex(r["static"])).hex() != state["commit"]:
            return _pout(idle, because="reveal-mismatch")              # a wrong nonce and a wrong key look the same, on purpose
        refused = _peer_refusal(state, r.get("peerId"), r["static"], "reveal-length")     # the key is proven by the commitment now: the device id can be checked
        if refused:
            return _pout(idle, because=refused)
        code = pairing_code(bytes.fromhex(r["nonce"]), bytes.fromhex(state["nonce"]), bytes.fromhex(r["static"]), bytes.fromhex(r["own"]))
        return _pout({"s": "coded", "start": state["start"], "code": code, "mine": None, "theirs": None, **keep}, [], "show-code")
    if "user" in ev or "peer" in ev:
        return _answer(state, ev, idle)
    return _pout(state)


def pair_initiator_step(state, ev):
    """The machine of the machine whose user started the pairing. state: {"s": "idle", last} | {"s": "started", nonce, static, start, last} |
    {"s": "coded", start, code, mine, theirs, last}. Optional, carried unchanged: own_id and paired, see _ids.
    ev: {"start": {"nonce", "static"}, "now"} (the user chose Pair a machine; the app's fresh nonce and its static public key) | {"nonce": hex, "peerStatic": hex, "peerId": hex, "now"}
    (the second message was opened: the responder's nonce and static key, and the responder's device id from its hello) | {"user": ...} | {"peer": ...}.
    send holds {"commit": hex}, {"reveal": hex} or {"pair": ...}; notify is commit-sent, show-code, store or discard; because is one of attempt-too-soon,
    start-length, no-commit, nonce-repeated, nonce-length, reveal-late, device-id, own-id, id-key-mismatch, unexpected, window-closed, said-no."""
    keep = {"last": state["last"], **_ids(state)}
    idle = {"s": "idle", **keep}
    now = ev.get("now")
    if "start" in ev:
        if state["s"] != "idle":
            return _pout(idle, because="unexpected")
        if not (_hex32(ev["start"].get("nonce")) and _hex32(ev["start"].get("static"))):
            return _pout(idle, because="start-length")
        if not pairing_attempt_allowed(state["last"], now):
            return _pout(idle, because="attempt-too-soon")
        n, s = ev["start"]["nonce"], ev["start"]["static"]
        return _pout({"s": "started", "nonce": n, "static": s, "start": now, "last": now, **_ids(state)}, [{"commit": commit_of(bytes.fromhex(n), bytes.fromhex(s)).hex()}], "commit-sent")
    if "nonce" in ev:
        if state["s"] == "idle":
            return _pout(idle, because="no-commit")                    # the other side's nonce with no commitment of ours before it
        if state["s"] != "started":
            return _pout(idle, because="nonce-repeated")
        if not pairing_window_open(state["start"], now):
            return _pout(idle, because="reveal-late")
        if not (_hex32(ev["nonce"]) and _hex32(ev.get("peerStatic"))):
            return _pout(idle, because="nonce-length")
        refused = _peer_refusal(state, ev.get("peerId"), ev["peerStatic"], "nonce-length")
        if refused:
            return _pout(idle, because=refused)
        code = pairing_code(bytes.fromhex(state["nonce"]), bytes.fromhex(ev["nonce"]), bytes.fromhex(state["static"]), bytes.fromhex(ev["peerStatic"]))
        return _pout({"s": "coded", "start": state["start"], "code": code, "mine": None, "theirs": None, **keep}, [{"reveal": state["nonce"]}], "show-code")
    if "user" in ev or "peer" in ev:
        return _answer(state, ev, idle)
    return _pout(state)
# ---- received file names (Task 5) -----------------------------------------------------------------------------------
NAME_BYTES_MAX = 200                              # UTF-8 bytes of a saved name: room under Windows' 260-character paths, and for " (9999)"
EXT_BYTES_MAX = 16                                # the part after the last dot counts as an extension only up to this long
COLLISION_MAX = 9999
BAD_CATEGORIES = {"Cc", "Cf", "Cs", "Zl", "Zp"}   # controls (NUL, C0, DEL, C1), format characters (bidi controls, zero-width, BOM, soft hyphen), lone surrogates, line and paragraph separators
# Every Default_Ignorable code point (Unicode DerivedCoreProperties.txt) as (low, high) code points, plus U+2800 (BRAILLE PATTERN BLANK: blank, but not
# default-ignorable). The owner's rule (2026-10-14): a file name or a device name with any of them is refused as invisible. The table is hand-written
# on purpose, so the set does not depend on unicodedata, whose Unicode version differs between Python builds (print it with
# python3 -B -c "import unicodedata; print(unicodedata.unidata_version)"). It includes U+115F, U+1160, U+3164, U+FFA0, U+FE00-U+FE0F and U+180B-U+180F.
INVISIBLE_RANGES = (
    (0x00AD, 0x00AD), (0x034F, 0x034F), (0x061C, 0x061C), (0x115F, 0x1160), (0x17B4, 0x17B5), (0x180B, 0x180F), (0x200B, 0x200F), (0x202A, 0x202E),
    (0x2060, 0x206F), (0x2800, 0x2800), (0x3164, 0x3164), (0xFE00, 0xFE0F), (0xFEFF, 0xFEFF), (0xFFA0, 0xFFA0), (0xFFF0, 0xFFF8), (0x1BCA0, 0x1BCA3),
    (0x1D173, 0x1D17A), (0xE0000, 0xE0FFF),
)


def _invisible(ch):
    """True for a character that shows nothing: a code point in INVISIBLE_RANGES (the Hangul fillers are in it). The file-name and the device-name rules both use it."""
    cp = ord(ch)
    return any(lo <= cp <= hi for lo, hi in INVISIBLE_RANGES)
WIN_ILLEGAL = '<>:"|?*'
RESERVED = ({"CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"} | {"COM%d" % n for n in range(0, 10)} | {"LPT%d" % n for n in range(0, 10)}
            | {"COM¹", "COM²", "COM³", "LPT¹", "LPT²", "LPT³"})
_ASCII_UPPER = {c: c - 32 for c in range(ord("a"), ord("z") + 1)}


# The owner's rule (2026-10-14, answer 2b), for file names only: a run of these code points becomes one U+0020, after the NFC step and before every other check.
# The table is written out by hand, not taken from unicodedata: U+0009 to U+000D (tab and the line breaks), U+0020, U+0085, U+00A0 (no-break space: whitespace
# here, by the owner's decision), U+1680, U+2000 to U+200A, U+2028, U+2029, U+202F, U+205F and U+3000.
NAME_SPACE_RUN = re.compile(r"[\t\n\x0b\x0c\r \x85\xa0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+")


def _space(ch):
    return ch == " " or unicodedata.category(ch) == "Zs"


def _trim(s):
    """Spaces off the start; spaces and dots off the end."""
    start = 0
    while start < len(s) and _space(s[start]):
        start += 1
    s = s[start:]
    while s and (s[-1] == "." or _space(s[-1])):
        s = s[:-1]
    return s


def _reserved(s):
    return s.split(".", 1)[0].rstrip(" ").translate(_ASCII_UPPER) in RESERVED


def _split_ext(name):
    i = name.rfind(".")
    if i > 0 and len(name[i:].encode("utf-8")) <= EXT_BYTES_MAX:
        return name[:i], name[i:]
    return name, ""


def _cut(name):
    """name, cut to NAME_BYTES_MAX bytes at a code point, keeping an extension of up to EXT_BYTES_MAX bytes; spaces and dots the cut leaves at the end go."""
    if len(name.encode("utf-8")) <= NAME_BYTES_MAX:
        return name
    stem, ext = _split_ext(name)
    room, out = NAME_BYTES_MAX - len(ext.encode("utf-8")), ""
    for ch in stem:
        if len((out + ch).encode("utf-8")) > room:
            break
        out += ch
    return _trim(out) + ext


def sanitize_name(raw):
    """The name a received file is saved under: ("ok", name) or ("reject", reason).
    First, each run of NAME_SPACE_RUN (whitespace, NBSP included, the line breaks included) becomes one space, so a tab or a line break is a space and not a control.
    Rejected, because a real sender never sends them: not text (not-text), a control, format, surrogate or line-separator character, or an invisible
    one, that is in INVISIBLE_RANGES (invisible), a / or \\ (separator), and a name that is nothing once spaces and dots are trimmed, also once the cut and the rules below are made (empty). The checks run on the NFC
    form and on the NFKC form, so a full-width solidus or full-width dots are caught too; the name that is kept is the NFC form.
    Rewritten, because they are platform differences and not attacks: < > : " | ? * become _, spaces at the start and spaces and dots at the end go,
    a Windows device name (CON, NUL, COM1, ... as the part before the first dot, also once the cut is made) gets a _ in front, a name over
    NAME_BYTES_MAX bytes is cut at a code point, keeping an extension of up to EXT_BYTES_MAX bytes, and a name that starts with a dot gets a _ in
    front so that it shows (".txt" is saved as "_.txt"), cut again if the _ makes it too long."""
    if not isinstance(raw, str):
        return ("reject", "not-text")
    nfc, nfkc = unicodedata.normalize("NFC", raw), unicodedata.normalize("NFKC", raw)
    nfc, nfkc = NAME_SPACE_RUN.sub(" ", nfc), NAME_SPACE_RUN.sub(" ", nfkc)
    if any(unicodedata.category(ch) in BAD_CATEGORIES or _invisible(ch) for form in (nfc, nfkc) for ch in form):
        return ("reject", "invisible")
    if any(ch in "/\\" for form in (nfc, nfkc) for ch in form):
        return ("reject", "separator")
    if not _trim(nfc) or not _trim(nfkc):
        return ("reject", "empty")
    name = _trim("".join("_" if ch in WIN_ILLEGAL else ch for ch in nfc))
    probe = _trim("".join("_" if ch in WIN_ILLEGAL else ch for ch in nfkc))
    if not name:
        return ("reject", "empty")
    if _reserved(name) or _reserved(probe):
        name = "_" + name
    name = _cut(name)
    # The cut can leave a device name too ("CON" and spaces, the spaces cut away): the same test runs again on the cut name, NFC and NFKC.
    if _reserved(name) or _reserved(_trim(unicodedata.normalize("NFKC", name))):
        name = _cut("_" + name)
    # A dot at the start gets a _ in front, so that the file shows. The _ is the first part, so no device name can come of it; the cut keeps the limit.
    if name.startswith("."):
        name = _cut("_" + name)
    # What is saved must not be empty or dot-only once trimmed, in the NFC form or the NFKC form (a full-width dot is a dot under NFKC): the cut can leave one.
    if not _trim(name) or not _trim(unicodedata.normalize("NFKC", name)):
        return ("reject", "empty")
    return ("ok", name)


def _key(name):
    return unicodedata.normalize("NFC", name).casefold()


def unique_name(name, taken):
    """name itself when no taken name equals it, else "stem (n)ext" for the smallest n from 1 that is free; None after COLLISION_MAX tries.
    Names are compared in NFC and case-insensitively, because the Mac's and Windows' usual volumes do."""
    used = {_key(t) for t in taken}
    if _key(name) not in used:
        return name
    stem, ext = _split_ext(name)
    for n in range(1, COLLISION_MAX + 1):
        cand = "%s (%d)%s" % (stem, n, ext)
        if _key(cand) not in used:
            return cand
    return None
# ---- records, the first record, hello, the advert and the six frames (Task 6) ----------------------------------------
MODE_PAIR, MODE_TRANSFER = 1, 2
ID_LEN = 16
T_OFFER, T_ACCEPT, T_DECLINE, T_CHUNK, T_DONE, T_CANCEL = 1, 2, 3, 4, 5, 6
T_PAIR_YES, T_PAIR_NO = 0x21, 0x22                  # the two pairing answers: a type byte and nothing else
TYPE_NAMES = {T_OFFER: "offer", T_ACCEPT: "accept", T_DECLINE: "decline", T_CHUNK: "chunk", T_DONE: "done", T_CANCEL: "cancel", T_PAIR_YES: "pair-yes", T_PAIR_NO: "pair-no"}
CHUNK_MAX = NOISE_MAX - TAG - 1 - ID_LEN - 8     # 65494: the data in one chunk frame, so that the frame plus the tag fills one Noise message
CHUNK_SIZE = 32768                               # what a sender cuts a file into
RAW_NAME_MAX = 1020                              # bytes of a name on the wire: 255 code points of up to 4 bytes (the sanitizer cuts it to 200)
KIND_MAX = 127                                   # bytes of the file type, printable ASCII, advisory
DEVICE_NAME_MAX = 63                             # bytes of a device name
SIZE_MAX = 4 * 2**30                             # 4 GiB per transfer
DECLINE_USER, DECLINE_TIMEOUT, DECLINE_BUSY, DECLINE_TOO_LARGE, DECLINE_BAD_OFFER = 0, 1, 2, 3, 4


class FrameError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


def encode_record(payload):
    """A record is a u16 big-endian length (1 to 65535) and that many bytes. Every Noise message, handshake or transport, travels in one."""
    if not 1 <= len(payload) <= NOISE_MAX:
        raise FrameError("record-length")
    return struct.pack(">H", len(payload)) + payload


def split_records(buf):
    """(records, rest): the whole records at the start of buf, and the bytes of a record that has not arrived completely. A length of 0 is an error."""
    out, pos = [], 0
    while len(buf) - pos >= 2:
        n = struct.unpack_from(">H", buf, pos)[0]
        if n == 0:
            raise FrameError("record-empty")
        if len(buf) - pos - 2 < n:
            break
        out.append(bytes(buf[pos + 2:pos + 2 + n]))
        pos += 2 + n
    return out, bytes(buf[pos:])


def encode_preamble(mode, device_id):
    """The first record of a connection, in the clear: version, mode (1 pair, 2 transfer), and the sender's device id (16 zero bytes when pairing)."""
    return bytes([PROTOCOL_VERSION, mode]) + device_id


def decode_preamble(b):
    if len(b) != 2 + ID_LEN:
        raise FrameError("length")
    if b[0] != PROTOCOL_VERSION:
        raise FrameError("version")
    if b[1] not in (MODE_PAIR, MODE_TRANSFER):
        raise FrameError("mode")
    if (b[1] == MODE_PAIR) != (b[2:] == bytes(ID_LEN)):
        raise FrameError("device-id")
    return {"mode": "pair" if b[1] == MODE_PAIR else "transfer", "id": b[2:].hex()}


def _device_name(raw):
    """A device name is shown on the pairing card: 1 to 63 bytes of strict UTF-8, no control, format or separator characters, no invisible character (the same table as a file name), no space at either end."""
    if not 1 <= len(raw) <= DEVICE_NAME_MAX:
        raise FrameError("name-length")
    try:
        s = raw.decode("utf-8")
    except UnicodeDecodeError:
        raise FrameError("utf8")
    if any(unicodedata.category(ch) in BAD_CATEGORIES or _invisible(ch) for ch in s) or s != s.strip():
        raise FrameError("name-chars")
    return s


def encode_hello(device_id, nonce, name):
    """The payload of the second and third pairing messages: version, device id, a 32-byte nonce, name length and name. It is encrypted, so the name on the card is the
    authenticated one. The nonce is the sender's half of the pairing code: the initiator's is its reveal, and it must match the commitment sent in the first message."""
    nb = name.encode("utf-8")
    return bytes([PROTOCOL_VERSION]) + device_id + nonce + bytes([len(nb)]) + nb


def decode_hello(b):
    if len(b) < 2 + ID_LEN + 32:
        raise FrameError("truncated")
    if b[0] != PROTOCOL_VERSION:
        raise FrameError("version")
    if b[1:1 + ID_LEN] == bytes(ID_LEN):
        raise FrameError("device-id")
    nonce, n, body = b[1 + ID_LEN:1 + ID_LEN + 32], b[1 + ID_LEN + 32], b[2 + ID_LEN + 32:]
    if len(body) < n:
        raise FrameError("truncated")
    if len(body) > n:
        raise FrameError("trailing")
    return {"id": b[1:1 + ID_LEN].hex(), "nonce": nonce.hex(), "name": _device_name(body)}


ABSENT = object()                                 # an own_id that was not given: the unconfigured case. A None own_id is given, and it is refused (fail closed)


def parse_txt(txt, own_id=ABSENT):
    """An advert's TXT record, as a dict of text: {id, name} or a rejection. Anyone on the network can send one, so it is checked like a name on a card.
    v must be the text "1", id 32 lower-case hex digits that are not all zero. Other keys are ignored. own_id (optional, this machine's device id): an advert
    with that id is refused as own-id; an own_id that is not 32 lower-case hex digits, None included, refuses every advert as device-id (fail closed, nothing is lower-cased).
    A port omits own_id when it has no id yet and never passes None. The advert carries no key, so a paired id under another key is decided at the hello, not here."""
    if not isinstance(txt, dict):
        raise FrameError("not-a-record")
    v, i, n = txt.get("v"), txt.get("id"), txt.get("name")
    if v != str(PROTOCOL_VERSION):
        raise FrameError("version")
    if not _id_hex(i) or i == "0" * (2 * ID_LEN):
        raise FrameError("device-id")
    if own_id is not ABSENT and not _id_hex(own_id):
        raise FrameError("device-id")
    if own_id is not ABSENT and i == own_id:
        raise FrameError("own-id")
    if not isinstance(n, str):
        raise FrameError("name-length")
    try:
        nb = n.encode("utf-8")
    except UnicodeEncodeError:
        raise FrameError("utf8")
    return {"id": i, "name": _device_name(nb)}


def encode_frame(f):
    """A frame is the plaintext of one Noise transport message: a type byte, the 16-byte transfer id, then the body (numbers big-endian); the two pairing answers, `pair-yes` and `pair-no`, are the type byte alone."""
    t = f["type"]
    if t == "pair-yes":
        return bytes([T_PAIR_YES])
    if t == "pair-no":
        return bytes([T_PAIR_NO])
    i = bytes.fromhex(f["id"])
    if len(i) != ID_LEN:
        raise FrameError("id")
    if t == "offer":
        nb, kb = f["name"].encode("utf-8"), f["kind"].encode("ascii")
        return bytes([T_OFFER]) + i + struct.pack(">QH", f["size"], len(nb)) + nb + bytes([len(kb)]) + kb
    if t == "accept":
        return bytes([T_ACCEPT]) + i
    if t == "decline":
        return bytes([T_DECLINE]) + i + bytes([f["reason"]])
    if t == "chunk":
        return bytes([T_CHUNK]) + i + struct.pack(">Q", f["offset"]) + bytes.fromhex(f["data"])
    if t == "done":
        return bytes([T_DONE]) + i
    if t == "cancel":
        return bytes([T_CANCEL]) + i
    raise FrameError("unknown-type")


def decode_frame(b):
    """The frame as a dict, or a FrameError whose code says why. Strict: nothing after the end, UTF-8 without surrogates or overlongs, ASCII for the type."""
    if len(b) == 0:
        raise FrameError("empty")
    t, body = b[0], b[1:]
    if t not in TYPE_NAMES:
        raise FrameError("unknown-type")
    if t in (T_PAIR_YES, T_PAIR_NO):
        if body:
            raise FrameError("trailing")
        return {"type": TYPE_NAMES[t]}
    if len(body) < ID_LEN:
        raise FrameError("truncated")
    f, rest = {"type": TYPE_NAMES[t], "id": body[:ID_LEN].hex()}, body[ID_LEN:]
    if t in (T_ACCEPT, T_DONE, T_CANCEL):
        if rest:
            raise FrameError("trailing")
    elif t == T_DECLINE:
        if len(rest) < 1:
            raise FrameError("truncated")
        if len(rest) > 1:
            raise FrameError("trailing")
        if rest[0] > DECLINE_BAD_OFFER:
            raise FrameError("reason")
        f["reason"] = rest[0]
    elif t == T_CHUNK:
        if len(rest) < 8:
            raise FrameError("truncated")
        data = rest[8:]
        if not data:
            raise FrameError("chunk-empty")
        if len(data) > CHUNK_MAX:
            raise FrameError("chunk-long")
        f["offset"], f["data"] = struct.unpack(">Q", rest[:8])[0], data.hex()
    else:
        if len(rest) < 10:
            raise FrameError("truncated")
        size, n = struct.unpack(">QH", rest[:10])
        if not 1 <= n <= RAW_NAME_MAX:
            raise FrameError("name-length")
        if len(rest) < 10 + n + 1:
            raise FrameError("truncated")
        nb, k, kb = rest[10:10 + n], rest[10 + n], rest[11 + n:]
        if len(kb) < k:
            raise FrameError("truncated")
        if len(kb) > k:
            raise FrameError("trailing")
        if k > KIND_MAX or any(not 0x20 <= c <= 0x7E for c in kb):
            raise FrameError("kind")
        try:
            name = nb.decode("utf-8")
        except UnicodeDecodeError:
            raise FrameError("utf8")
        f.update(size=size, name=name, kind=kb.decode("ascii"))
    return f
IDLE = {"s": "idle"}
ABORTS = ("unexpected", "id", "order", "overflow", "short")      # the reasons a connection is closed


def _out(state, send=(), notify=None, abort=None):
    return {"state": state, "send": list(send), "notify": notify, "abort": abort}


def receiver_step(state, ev):
    """The receiving side of one connection, one event at a time.
    state: {"s": "idle"} | {"s": "offered", id, size, name} | {"s": "receiving", id, size, got}  (name is the sanitized name, the one that is shown and saved).
    ev: {"frame": a decoded frame} | {"user": "accept" | "decline" | "cancel"} | {"timeout": true}.
    Returns {state, send: the frames to send, notify: what to tell the user (offer, expired, withdrawn, cancelled, complete) or None,
    abort: why the connection must close (one of ABORTS) or None; after an abort the state is idle}.
    Only a click moves offered to receiving. One transfer at a time. A chunk must start exactly where the last one ended and may not pass the size,
    and done is good only when every byte has come."""
    s = state["s"]
    if "user" in ev:
        u = ev["user"]
        if s == "offered" and u == "accept":
            return _out({"s": "receiving", "id": state["id"], "size": state["size"], "got": 0}, [{"type": "accept", "id": state["id"]}])
        if s == "offered" and u == "decline":
            return _out(IDLE, [{"type": "decline", "id": state["id"], "reason": DECLINE_USER}])
        if s == "receiving" and u in ("cancel", "decline"):
            return _out(IDLE, [{"type": "cancel", "id": state["id"]}], "cancelled")
        return _out(state)
    if ev.get("timeout"):
        if s == "offered":
            return _out(IDLE, [{"type": "decline", "id": state["id"], "reason": DECLINE_TIMEOUT}], "expired")
        return _out(state)
    f = ev["frame"]
    t = f["type"]
    if t.startswith("pair-"):
        return _out(IDLE, abort="unexpected")                       # a pairing answer has no place in a transfer
    if t == "offer":
        if s != "idle":
            return _out(state, [{"type": "decline", "id": f["id"], "reason": DECLINE_BUSY}])
        if f["size"] > SIZE_MAX:
            return _out(IDLE, [{"type": "decline", "id": f["id"], "reason": DECLINE_TOO_LARGE}])
        kind, name = sanitize_name(f["name"])
        if kind != "ok":
            return _out(IDLE, [{"type": "decline", "id": f["id"], "reason": DECLINE_BAD_OFFER}])
        return _out({"s": "offered", "id": f["id"], "size": f["size"], "name": name}, [], "offer")
    if t == "cancel":
        if s != "idle" and f["id"] == state["id"]:
            return _out(IDLE, [], "withdrawn" if s == "offered" else "cancelled")
        return _out(state)                                          # a cancel for a transfer we do not know is harmless
    if s == "receiving" and t in ("chunk", "done"):
        if f["id"] != state["id"]:
            return _out(IDLE, abort="id")
        if t == "chunk":
            if f["offset"] != state["got"]:
                return _out(IDLE, abort="order")                    # a replayed chunk or a skipped one
            if state["got"] + len(f["data"]) // 2 > state["size"]:
                return _out(IDLE, abort="overflow")
            return _out({**state, "got": state["got"] + len(f["data"]) // 2})
        if state["got"] != state["size"]:
            return _out(IDLE, abort="short")
        return _out(IDLE, [], "complete")
    return _out(IDLE, abort="unexpected")


def sender_step(state, ev):
    """The sending side. state: {"s": "idle"} | {"s": "offered", id} | {"s": "sending", id}. ev: {"frame": ...} | {"user": "cancel"}.
    Returns the same shape as receiver_step (notify: declined, cancelled)."""
    s = state["s"]
    if "user" in ev:
        if s in ("offered", "sending") and ev["user"] == "cancel":
            return _out(IDLE, [{"type": "cancel", "id": state["id"]}], "cancelled")
        return _out(state)
    f = ev["frame"]
    t = f["type"]
    if s == "idle" and t == "cancel":
        return _out(state)                                          # a cancel with no transfer running is ignored, as receiver_step ignores it
    if s == "idle" or t in ("offer", "chunk", "done") or t.startswith("pair-"):
        return _out(IDLE, abort="unexpected")
    if f["id"] != state["id"]:
        return _out(IDLE, abort="id")
    if s == "offered" and t == "accept":
        return _out({"s": "sending", "id": state["id"]})
    if s == "offered" and t == "decline":
        return _out(IDLE, [], "declined")
    if t == "cancel":
        return _out(IDLE, [], "cancelled")
    return _out(IDLE, abort="unexpected")


def plan_chunks(size, chunk_size=CHUNK_SIZE):
    """[(offset, length)] that cover size bytes; an empty file has none, and then the sender goes straight to done."""
    return [(o, min(chunk_size, size - o)) for o in range(0, size, chunk_size)]


# ---- the rules the app keeps around one connection (G2-0b): the machine's one transfer place, one decline per connection, the first-frame clock ----------
# receiver_step is one connection and knows nothing of the others. These rules are what the Mac adds around it (LinkBusy, LinkTransferReceive).
FIRST_FRAME_MS = 10_000                                              # a transfer connection whose handshake is done must have an offer in hand within this long (LinkTransferReceive.firstFrameMs)
DECLINES_PER_CONNECTION = 1                                          # the machine-made declines one connection may send; the next one closes it (LinkTransferReceive, `declines`)
MACHINE_DECLINES = (DECLINE_BUSY, DECLINE_TOO_LARGE, DECLINE_BAD_OFFER)   # the declines the machine makes itself; not the user's no (0) and not the timeout (1)


def first_frame_expired(handshake_ms, now_ms):
    """Expired at exactly FIRST_FRAME_MS after the handshake (the Mac's watch fires when that time has come). A clock that went back, or a value that is not whole milliseconds, counts as expired."""
    if not _ms(handshake_ms) or not _ms(now_ms):
        return True
    return not 0 <= now_ms - handshake_ms < FIRST_FRAME_MS


def place_step(place, ev):
    """The machine's one transfer place, for every peer (LinkBusy). place: {"holder": None or the id that holds it, "card": true while a card with buttons is on the island}.
    ev: {"claim": id}: an offer asks for the place; granted only when nobody holds it and no card is up, and then the claimant holds it. {"release": id}: the holder gives it back; another id changes nothing.
    {"card": bool}: a card with buttons goes up or comes down. Returns {"place", "granted"}; granted is None for a release or a card."""
    holder, card = place["holder"], place["card"]
    if "claim" in ev:
        if holder is None and not card:
            return {"place": {"holder": ev["claim"], "card": card}, "granted": True}
        return {"place": place, "granted": False}
    if "release" in ev:
        return {"place": {"holder": None if holder == ev["release"] else holder, "card": card}, "granted": None}
    return {"place": {"holder": holder, "card": ev["card"]}, "granted": None}


def _conn(state, declines, send=(), notify=None, abort=None):
    return {"state": state, "declines": declines, "send": list(send), "notify": notify, "abort": abort}


def receiver_connection_step(conn, ev):
    """One connection of the receiver as the app runs it: receiver_step plus the rules above.
    conn: {"state": a receiver state, "declines": the machine-made declines this connection has sent}.
    ev: a receiver_step event; or {"silent": true} when the first-frame clock has run out; an offer may carry "granted", the place's answer to its claim (True when absent).
    An offer that comes while the connection is idle asks the place: a refused one is declined as busy (2) and the state does not change. A machine-made decline sent for an offer counts;
    the second one is not sent, the connection is closed (abort "declines"). The user's no and a timeout do not count. A silent clock closes an idle connection (abort "idle"); in any
    other state its report is stale and does nothing. Returns {"state", "declines", "send", "notify", "abort"}."""
    state, declines = conn["state"], conn["declines"]
    if "silent" in ev:
        if state["s"] == "idle":
            return _conn(IDLE, declines, abort="idle")
        return _conn(state, declines)
    offer = "frame" in ev and ev["frame"]["type"] == "offer"
    if offer and state["s"] == "idle" and not ev.get("granted", True):
        res = _out(state, [{"type": "decline", "id": ev["frame"]["id"], "reason": DECLINE_BUSY}])
    else:
        res = receiver_step(state, {k: v for k, v in ev.items() if k != "granted"})
    if offer and any(f["type"] == "decline" and f["reason"] in MACHINE_DECLINES for f in res["send"]):
        if declines >= DECLINES_PER_CONNECTION:
            return _conn(IDLE, declines, abort="declines")
        declines += 1
    return _conn(res["state"], declines, res["send"], res["notify"], res["abort"])
# @@RULES


def load(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return json.load(f)


def check(label, got, expected):
    global FAILURES
    if got == expected:
        print(f"  ✓ {label}")
    else:
        print(f"  ✗ {label}\n    got:      {str(got)[:400]}\n    expected: {str(expected)[:400]}")
        FAILURES += 1


def check_primitives():
    print("primitives (RFC 7748 and RFC 8439 test vectors)")
    h = bytes.fromhex
    check("RFC 7748 5.2: X25519 of the first test vector",
          x25519(h("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4"),
                 h("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c")).hex(),
          "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552")
    alice = h("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
    bob = h("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
    check("RFC 7748 6.1: Alice's public key", x25519_pub(alice).hex(), "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")
    check("RFC 7748 6.1: Bob's public key", x25519_pub(bob).hex(), "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f")
    check("RFC 7748 6.1: the shared secret, both ways", (x25519(alice, x25519_pub(bob)) == x25519(bob, x25519_pub(alice)), x25519(alice, x25519_pub(bob)).hex()),
          (True, "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"))
    check("RFC 8439 2.3.2: a ChaCha20 block", chacha20_block(bytes(range(32)), 1, h("000000090000004a00000000")).hex()[:32], "10f1e7e4d13b5915500fdd1fa32071c4")
    check("RFC 8439 2.5.2: a Poly1305 tag",
          poly1305(h("85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b"), b"Cryptographic Forum Research Group").hex(),
          "a8061dc1305136c6c22b8baf0c0127a9")
    key, nonce, aad = bytes(range(0x80, 0xA0)), h("070000004041424344454647"), h("50515253c0c1c2c3c4c5c6c7")
    pt = b"Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
    boxed = aead_encrypt(key, nonce, aad, pt)
    check("RFC 8439 2.8.2: the AEAD's ciphertext starts and its tag ends as published", (boxed[:16].hex(), boxed[-16:].hex()),
          ("d31a8d34648e60db7b86afbc53ef7ec2", "1ae10b594f09e26a7e902ecbd0600691"))
    check("RFC 8439 2.8.2: it opens again, and a flipped bit does not", (aead_decrypt(key, nonce, aad, boxed) == pt, _opens(key, nonce, aad, boxed[:5] + bytes([boxed[5] ^ 1]) + boxed[6:])),
          (True, False))


def _opens(key, nonce, aad, boxed):
    try:
        aead_decrypt(key, nonce, aad, boxed)
        return True
    except ValueError:
        return False


def _refused(fn, *args):
    try:
        fn(*args)
        return False
    except NoiseError:
        return True


def check_noise():
    print("noise-vectors.json")
    f = load("noise-vectors.json")
    check("the prologue is the one the rules name", f["prologue"], PROLOGUE.hex())
    check("the note says the keys are plain byte patterns made for tests, never real keys",
          [s for s in ("plain byte patterns", "made for tests", "never real keys") if s not in f["note"]], [])
    vectors = {v["id"]: v for v in f["vectors"]}
    check("four vectors: both patterns, the link prologue and an empty one", sorted(vectors), ["kk-empty", "kk-link", "xx-empty", "xx-link"])
    for v in f["vectors"]:
        got = noise_run(v)
        check(f"{v['id']}: every message is the one the vector gives, and the handshake hash too", got,
              ("ok", [m["ciphertext"] for m in v["messages"]], v["handshake_hash"]))
        if v["protocol_name"] == protocol_name("KK"):
            check(f"{v['id']}: the remote static keys it names are the ones the private keys make",
                  (v["init_remote_static"], v["resp_remote_static"]),
                  (x25519_pub(bytes.fromhex(v["resp_static"])).hex(), x25519_pub(bytes.fromhex(v["init_static"])).hex()))
    for c in f["rejectCases"]:
        mutation = {k: val for k, val in c.items() if k not in ("name", "vector", "failsAt", "because")}
        got = noise_run(vectors[c["vector"]], mutation)
        check(c["name"], got[:2], ("fail", c["failsAt"]))
        if "because" in c:                       # the zero point must be refused as such, not only because the two sides' keys then disagree
            check(c["name"] + ": refused as " + c["because"], got[2:], (c["because"],))
    # The fixtures carry no person's name and no device model: the two hellos of xx-link name a test device, and no payload names a device model.
    hellos = [bytes.fromhex(vectors["xx-link"]["messages"][n]["payload"]) for n in (1, 2)]
    check("the two xx-link hellos name a test device", [h.endswith(bytes([11]) + b"test device") for h in hellos], [True, True])
    words = " ".join(bytes.fromhex(m["payload"]).decode("utf-8", "replace").lower() for v in f["vectors"] for m in v["messages"])
    check("no payload in the fixtures names a device model", [w for w in ("mac", "iphone", "ipad") if w in words], [])
    # The size limit: 65535 bytes in a Noise message, 65519 of data in a transport message; a refused message does not move the counter.
    a = Handshake("KK", True, PROLOGUE, bytes([1]) * 32, rs=x25519_pub(bytes([2]) * 32))
    b = Handshake("KK", False, PROLOGUE, bytes([2]) * 32, rs=x25519_pub(bytes([1]) * 32))
    b.read(a.write())
    a.read(b.write())
    (_, (a_send, _a_recv)), (_, (_b_send, b_recv)) = a.finish(), b.finish()
    big = a_send.encrypt(b"", bytes(NOISE_MAX - TAG))
    check("a transport message of 65535 bytes (65519 of data and the tag) opens", (len(big), len(b_recv.decrypt(b"", big))), (NOISE_MAX, NOISE_MAX - TAG))
    check("a transport message of 65536 bytes (65520 of data, sealed) is refused when it is sent, and the counter does not move",
          (_refused(a_send.encrypt, b"", bytes(NOISE_MAX - TAG + 1)), a_send.n), (True, 1))
    forged = aead_encrypt(b_recv.k, b_recv._nonce(), b"", bytes(NOISE_MAX - TAG + 1))         # a valid tag on 65536 bytes: only the size refuses it
    check("a transport message of 65536 bytes is refused when it is received, and the counter does not move",
          (_refused(b_recv.decrypt, b"", forged), b_recv.n), (True, 1))
    nxt = a_send.encrypt(b"", b"next")
    hurt = bytes([nxt[0] ^ 1]) + nxt[1:]
    check("a damaged message is refused and the counter does not move, so the genuine next one still opens",
          (_refused(b_recv.decrypt, b"", hurt), b_recv.n, b_recv.decrypt(b"", nxt), b_recv.n), (True, 1, b"next", 2))
    start = Handshake("XX", True, b"", bytes([1]) * 32, e=bytes([2]) * 32)
    check("a handshake message of 65535 bytes is written, one of 65536 is refused",
          (len(start.write(bytes(NOISE_MAX - 32))), _refused(Handshake("XX", True, b"", bytes([1]) * 32, e=bytes([2]) * 32).write, bytes(NOISE_MAX - 31))), (NOISE_MAX, True))
    # A seeded property test: random keys, prologues and payloads, both patterns.
    rnd = random.Random(20261014)
    ok = True
    for n in range(24):
        pattern = ("XX", "KK")[n % 2]
        isk, rsk = rnd.randbytes(32), rnd.randbytes(32)
        pro = rnd.randbytes(rnd.randrange(0, 20))
        i = Handshake(pattern, True, pro, isk, rs=x25519_pub(rsk) if pattern == "KK" else None)
        r = Handshake(pattern, False, pro, rsk, rs=x25519_pub(isk) if pattern == "KK" else None)
        while not i.done():
            w, rd = (i, r) if i.my_turn() else (r, i)
            p = rnd.randbytes(rnd.randrange(0, 80))
            ok &= rd.read(w.write(p)) == p
        (hi, (i_send, i_recv)), (hr, (r_send, r_recv)) = i.finish(), r.finish()
        ok &= hi == hr and len(hi) == 32
        p = rnd.randbytes(rnd.randrange(1, 300))
        c = i_send.encrypt(b"", p)
        j = rnd.randrange(len(c))
        ok &= _refused(r_recv.decrypt, b"", c[:j] + bytes([c[j] ^ (1 << rnd.randrange(8))]) + c[j + 1:])
        ok &= r_recv.decrypt(b"", c) == p
        ok &= i_recv.decrypt(b"", r_send.encrypt(b"", p)) == p
    check("24 random sessions, both patterns: the hashes agree, both directions open, any damaged bit is refused", ok, True)
def check_pairing():
    print("pairing-cases.json: the commitment, the code and the clocks")
    f = load("pairing-cases.json")
    check("the constants are the ones the rules name", (f["digits"], f["commitLabel"].encode(), f["codeLabel"].encode(), f["gapMs"], f["windowMs"], f["offerTimeoutMs"]),
          (CODE_DIGITS, COMMIT_LABEL, CODE_LABEL, PAIR_GAP_MS, PAIR_WINDOW_MS, OFFER_TIMEOUT_MS))
    for c in f["commits"]:
        check("commitment: " + c["name"], commit_of(bytes.fromhex(c["nonce"]), bytes.fromhex(c["static"])).hex(), c["commit"])
    for c in f["codes"]:
        check("code: " + c["name"], pairing_code(*[bytes.fromhex(c[k]) for k in ("nonceI", "nonceR", "staticI", "staticR")]), c["code"])
    for c in f["invalid"]:
        args = {"nonceI": bytes(32), "nonceR": bytes(32), "staticI": bytes(32), "staticR": bytes(32)}
        v = c["value"]
        try:
            args[c["field"]] = bytes.fromhex(v) if isinstance(v, str) else v
        except ValueError:
            args[c["field"]] = v                              # text that is not hex stays text
        try:
            pairing_code(*args.values())
            got = "a code"
        except ValueError:
            got = "refused"
        check("code: " + c["name"] + ": no code", got, "refused")
    for c in f["gapCases"]:
        check("a pairing attempt: " + c["name"], pairing_attempt_allowed(c["last"], c["now"]), c["out"])
    for c in f["windowCases"]:
        check("the pairing window: " + c["name"], pairing_window_open(c["start"], c["now"]), c["out"])
    for c in f["offerCases"]:
        check("an offer's 2 minutes: " + c["name"], offer_expired(c["offered"], c["now"]), c["out"])
    # Properties. Every input matters, the code is spread evenly, and a commitment says nothing about the nonce it hides.
    rnd = random.Random(20261014)
    ok = True
    for _ in range(300):
        a = [rnd.randbytes(32) for _ in range(4)]
        base = pairing_code(*a)
        for i in range(4):
            b = list(a)
            b[i] = bytes([b[i][0] ^ 1]) + b[i][1:]
            ok &= pairing_code(*b) != base
        ok &= commit_of(a[0], a[2]) != commit_of(a[1], a[2]) and commit_of(a[0], a[2]) != commit_of(a[0], a[3])
    check("300 random pairings: changing any one of the two nonces and the two keys changes the code, and the commitment depends on both of its inputs", ok, True)
    codes = [pairing_code(hashlib.sha256(b"n %d" % n).digest(), b"\xb1" * 32, b"\xc1" * 32, b"\xc2" * 32) for n in range(20000)]
    check("every code is exactly 6 digits, leading zeros kept", all(len(c) == 6 and c.isdigit() for c in codes), True)
    worst = max(sum((n - 2000) ** 2 / 2000 for n in (sum(1 for c in codes if c[p] == str(d)) for d in range(10))) for p in range(6))
    check("each digit position is spread evenly (chi-square over 10 values under 35 for every position)", worst < 35, True)
    check("a leading zero appears about one time in ten", 1700 < sum(1 for c in codes if c[0] == "0") < 2300, True)
    # What a man in the middle can do once the commitment is out: every choice it makes (its keys, its nonce) comes before the honest nonce, so over honest nonces
    # its fixed choices give a code that is as spread as any other: it cannot aim.
    fixed = [b"\xee" * 32, b"\xc1" * 32, b"\xc3" * 32]
    aimed = [pairing_code(hashlib.sha256(b"honest %d" % n).digest(), fixed[0], fixed[1], fixed[2]) for n in range(3000)]
    check("a man in the middle's fixed choices give a different code for almost every honest nonce (3000 nonces, over 2980 different codes)", len(set(aimed)) > 2980, True)
    print("  i with the commitment a man in the middle has one guess per attempt: 1 in 10**6 for 6 digits, and an attempt is allowed every 30 seconds")
def check_pairing_machines():
    print("pairing-cases.json: the two machines")
    f = load("pairing-cases.json")
    for c in f["responder"]:
        check("responder: " + c["name"], pair_responder_step(c["state"], c["event"]), c["out"])
    for c in f["initiator"]:
        check("initiator: " + c["name"], pair_initiator_step(c["state"], c["event"]), c["out"])
    for c in f["machineTrips"]:
        step = pair_responder_step if c["side"] == "responder" else pair_initiator_step
        state, got = c["from"], []
        for ev in c["events"]:
            res = step(state, ev)
            got.append(res)
            state = res["state"]
        check("trip: " + c["name"], got, c["out"])
    # Two machines talking to each other, with the nonces and keys drawn from a seeded generator: both reach the same code, both store only when both say yes, and a man in
    # the middle who passes the first message on but chooses its own nonce and key for the other side gets different codes on the two screens (1 in 10**6 would match).
    rnd = random.Random(20261014)
    agree, stored_ok, mitm_equal = True, True, 0
    for _ in range(400):
        ni, nr, si, sr = (rnd.randbytes(32).hex() for _ in range(4))
        ini = pair_initiator_step({"s": "idle", "last": None}, {"start": {"nonce": ni, "static": si}, "now": 1000})
        res = pair_responder_step({"s": "idle", "seen": [], "last": None}, {"commit": ini["send"][0]["commit"], "nonce": nr, "now": 1000})
        i2 = pair_initiator_step(ini["state"], {"nonce": res["send"][0]["nonce"], "peerStatic": sr, "peerId": "e2" * 16, "now": 2000})
        r2 = pair_responder_step(res["state"], {"reveal": {"nonce": i2["send"][0]["reveal"], "static": si, "own": sr, "peerId": "e2" * 16}, "now": 2000})
        agree &= i2["state"]["code"] == r2["state"]["code"]
        a, b = rnd.choice(["yes", "no"]), rnd.choice(["yes", "no"])
        si_, ri_ = i2["state"], r2["state"]
        ri = pair_responder_step(ri_, {"user": a, "now": 3000})
        ii = pair_initiator_step(si_, {"user": b, "now": 3000})
        ri = pair_responder_step(ri["state"], {"peer": b, "now": 3500}) if ri["state"]["s"] == "coded" else ri
        ii = pair_initiator_step(ii["state"], {"peer": a, "now": 3500}) if ii["state"]["s"] == "coded" else ii
        stored_ok &= (ri["notify"] == "store" and ii["notify"] == "store") == (a == "yes" and b == "yes")
        # the man in the middle: its own nonce and key towards the initiator, so the initiator's code is computed from them
        mn, ms = rnd.randbytes(32).hex(), rnd.randbytes(32).hex()
        mitm = pair_initiator_step(ini["state"], {"nonce": mn, "peerStatic": ms, "peerId": "e2" * 16, "now": 2000})
        mitm_equal += mitm["state"]["code"] == r2["state"]["code"]
    check("400 pairings: both machines compute the same code, and a key is stored exactly when both users say yes", (agree, stored_ok), (True, True))
    check("400 attempts by a man in the middle with its own nonce and key: the codes on the two screens almost never agree (at most 2 of 400, 1 in 10**6 each)", mitm_equal <= 2, True)
    # Random event scripts: nothing raises, a key is stored only after both users said yes, and a code is shown only after a good reveal.
    ok, last = True, None
    for _ in range(3000):
        for step, st in ((pair_responder_step, {"s": "idle", "seen": [], "last": None}), (pair_initiator_step, {"s": "idle", "last": None})):
            said = {"user": False, "peer": False}
            for _ in range(rnd.randrange(1, 14)):
                n, m, c = rnd.choice(["a1" * 32, "b1" * 32]), rnd.choice(["a1" * 32, "b1" * 32, "ab"]), rnd.choice(["4b8c8215defb279e6d2b65dc0653202357f9da0b3a0e4c661cec2a05f1a00c5d", "00" * 32])
                ev = rnd.choice([{"commit": c, "nonce": m, "now": rnd.choice([0, 1000, 31000, 130000])}, {"reveal": {"nonce": n, "static": "c1" * 32, "own": "c2" * 32, "peerId": "e2" * 16}, "now": rnd.choice([1000, 125000])},
                                 {"start": {"nonce": n, "static": "c1" * 32}, "now": rnd.choice([0, 1000, 31000])}, {"nonce": m, "peerStatic": "c2" * 32, "peerId": "e2" * 16, "now": rnd.choice([1000, 125000])},
                                 {"user": rnd.choice(["yes", "no", 1]), "now": rnd.choice([2000, 125000])}, {"peer": rnd.choice(["yes", "no", None]), "now": rnd.choice([2000, 125000])}, {}])
                before = st
                res = step(st, ev)
                st = res["state"]
                for who in ("user", "peer"):
                    if who in ev and before["s"] == "coded" and ev[who] == "yes" and res["because"] is None:
                        said[who] = True
                if res["notify"] == "store" and not (said["user"] and said["peer"]):
                    ok, last = False, (before, ev, res)
                if res["notify"] == "show-code" and before["s"] not in ("committed", "started"):
                    ok, last = False, (before, ev, res)
                if res["because"] is not None and st["s"] != "idle":
                    ok, last = False, (before, ev, res)
                if res["notify"] in ("store", "discard"):
                    said = {"user": False, "peer": False}
    check("6000 random event scripts: nothing raises, a key is stored only after both said yes, a code is shown only after a good reveal, a refusal ends in idle", (ok, last), (True, None))
def check_filenames():
    print("filename-cases.json")
    f = load("filename-cases.json")
    check("the constants are the ones the rules name", (f["bytesMax"], f["extBytesMax"], f["collisionMax"]), (NAME_BYTES_MAX, EXT_BYTES_MAX, COLLISION_MAX))
    for c in f["cases"]:
        kind, value = sanitize_name(c["raw"])
        check(c["name"], {"ok": value} if kind == "ok" else {"reject": value}, c["out"])
    for c in f["uniqueCases"]:
        taken = list(c["taken"])
        if "takenNumbered" in c:
            t = c["takenNumbered"]
            taken += ["%s (%d)%s" % (t["stem"], n, t["ext"]) for n in range(t["from"], t["to"] + 1)]
        check("a name collision: " + c["name"], unique_name(c["wanted"], taken), c["out"])
    # A seeded fuzz over a hostile alphabet: whatever comes out is a safe name, cleaning it again changes nothing, and a free name is made.
    rnd = random.Random(20261014)
    alphabet = list("ab.. /\\:*?\"<>|~%$") + ["\x00", "\x1f", "\x7f", "\x85", "\u200b", "\u200d", "\u202e", "\u2066", "\ufeff", "\u2028", "\u00a0", "\u3000",
                                              "．", "／", "＼", "e\u0301", "é", "\U0001F408", "日", "CON", "nul", "COM1", "¹", "ﬁ"]
    bad = None
    for _ in range(6000):
        raw = "".join(rnd.choice(alphabet) for _ in range(rnd.randrange(0, 40))) + rnd.choice(["", ".txt", ".", " ", ".tar.gz"])
        kind, name = sanitize_name(raw)
        if kind != "ok":
            if name not in ("invisible", "separator", "empty"):
                bad = (raw, name)
                break
            continue
        nfkc = unicodedata.normalize("NFKC", name)
        stem = name.split(".", 1)[0].rstrip(" ").upper()
        if (not name or len(name.encode("utf-8")) > NAME_BYTES_MAX or name != unicodedata.normalize("NFC", name)
                or any(ch in "/\\" for ch in name + nfkc) or any(ch in WIN_ILLEGAL for ch in name)
                or any(unicodedata.category(ch) in BAD_CATEGORIES for ch in name)
                or name[-1] in ". " or name.startswith(".") or _space(name[0]) or not _trim(nfkc) or stem in RESERVED or sanitize_name(name) != ("ok", name)
                or len(unique_name(name, [name]).encode("utf-8")) > NAME_BYTES_MAX + 7 or sanitize_name(unique_name(name, [name]))[0] != "ok"):
            bad = (raw, name)
            break
    check("6000 hostile names: what is accepted is NFC, short, free of separators, controls, Windows-illegal characters, trailing dots and device names, and cleaning it again changes nothing", bad, None)
    # A run of spaces is one space before the cut (the owner's rule, 2026-10-14), so these names are not cut: CON with x.txt after it is no device name.
    check("a run of 250 spaces is one space before the cut: CON, 250 spaces, x.txt is CON x.txt", sanitize_name("CON" + " " * 250 + "x.txt"), ("ok", "CON x.txt"))
    check("a run of 250 spaces is one space before the cut: nul, 250 spaces, q.bin is nul q.bin", sanitize_name("nul" + " " * 250 + "q.bin"), ("ok", "nul q.bin"))
    check("a run of 250 spaces is one space before the cut: COM1, 250 spaces, z.log is COM1 z.log", sanitize_name("COM1" + " " * 250 + "z.log"), ("ok", "COM1 z.log"))
    check("a run of 250 spaces after a dot is one space, and the leading-dot rule gives _. x", sanitize_name("." + " " * 250 + "x"), ("ok", "_. x"))
    check("a run of 250 spaces after a full-width dot is one space: the full-width dot is kept", sanitize_name("\uff0e" + " " * 250 + "x"), ("ok", "\uff0e x"))
    check("a run of 250 spaces after _ is one space: _ .txt", sanitize_name("_" + " " * 250 + ".txt"), ("ok", "_ .txt"))
    check("a run of 250 spaces after ._ is one space: _._ x", sanitize_name("._" + " " * 250 + "x"), ("ok", "_._ x"))
    # The cut can still leave dots and spaces only: a dot and a space 120 times, then 20 letters (no extension, 260 bytes), is cut to dots and spaces, which go.
    check("the cut leaves dots and spaces only: refused as empty, as an empty name is", sanitize_name(". " * 120 + "x" * 20), ("reject", "empty"))
    check("the cut leaves full-width dots and spaces only, which NFKC makes dots: refused as empty", sanitize_name("\uff0e " * 120 + "x" * 20), ("reject", "empty"))
    # A seeded fuzz over raw names of 300 bytes or more, so the cut is always reached: every output is at most 200 bytes, and an output whose stem is a
    # device name (before the first dot, upper-cased, also after NFKC) starts with _.
    rnd = random.Random(20261014)
    heads = ["CON", "nul", "COM1", "LPT9", "aux", "CONOUT$", "ＣＯＮ", "COM¹"]
    pieces = [" "] * 6 + ["a", "x", "Z", ".", "é", "\U0001F408", "日", "\u0301"]
    long_bad = None
    for _ in range(3000):
        raw = rnd.choice(heads) + " " * rnd.randrange(150, 300)  # a long run of spaces: the cut can end inside it
        while len(raw.encode("utf-8")) < 300 + rnd.randrange(0, 60):
            raw += rnd.choice(pieces)
        raw += rnd.choice(["", ".txt", ".tar.gz", ".bin", " .log"])
        kind, name = sanitize_name(raw)
        if kind != "ok":
            if name not in ("invisible", "separator", "empty"):
                long_bad = (raw, name)
                break
            continue
        stem = name.split(".", 1)[0].rstrip(" ").upper()
        nfkc_stem = unicodedata.normalize("NFKC", name).split(".", 1)[0].rstrip(" ").upper()
        if len(name.encode("utf-8")) > NAME_BYTES_MAX or ((stem in RESERVED or nfkc_stem in RESERVED) and not name.startswith("_")):
            long_bad = (raw, name)
            break
    check("3000 raw names of 300 bytes or more: every saved name is at most 200 bytes, and a device name is never saved without its _", long_bad, None)
def _err(fn, *args):
    try:
        return fn(*args)
    except FrameError as e:
        return {"error": e.code}


def check_frames():
    print("frames.json")
    f = load("frames.json")
    check("the constants are the ones the rules name", (f["noiseMax"], f["tag"], f["idLen"], f["protocolVersion"], f["chunkMax"], f["chunkSize"], f["rawNameMax"], f["kindMax"], f["deviceNameMax"], f["sizeMax"]),
          (NOISE_MAX, TAG, ID_LEN, PROTOCOL_VERSION, CHUNK_MAX, CHUNK_SIZE, RAW_NAME_MAX, KIND_MAX, DEVICE_NAME_MAX, SIZE_MAX))
    check("the type numbers and decline reasons", (f["types"], f["declineReasons"]),
          ({"offer": T_OFFER, "accept": T_ACCEPT, "decline": T_DECLINE, "chunk": T_CHUNK, "done": T_DONE, "cancel": T_CANCEL, "pairYes": T_PAIR_YES, "pairNo": T_PAIR_NO},
           {"user": DECLINE_USER, "timeout": DECLINE_TIMEOUT, "busy": DECLINE_BUSY, "tooLarge": DECLINE_TOO_LARGE, "badOffer": DECLINE_BAD_OFFER}))
    check("a chunk frame at its largest plus the tag fills one Noise message exactly", 1 + ID_LEN + 8 + CHUNK_MAX + TAG, NOISE_MAX)
    for c in f["frames"]:
        check(c["name"] + ": encode", encode_frame(c["frame"]).hex(), c["hex"])
        check(c["name"] + ": decode", decode_frame(bytes.fromhex(c["hex"])), c["frame"])
    for c in f["rejects"]:
        check(c["name"], _err(decode_frame, bytes.fromhex(c["hex"])), {"error": c["error"]})
    for c in f["limits"]:
        frame = bytes([T_CHUNK]) + bytes.fromhex(c["id"]) + struct.pack(">Q", c["offset"]) + bytes.fromhex(c["fill"]) * c["count"]
        got = _err(decode_frame, frame)
        check(c["name"], "ok" if "type" in got else got["error"], c["out"])
    for c in f["hello"]:
        got = _err(decode_hello, bytes.fromhex(c["hex"]))
        check("hello: " + c["name"], got, c["out"])
        if "error" not in c["out"]:
            check("hello: " + c["name"] + ", encoded again", encode_hello(bytes.fromhex(c["out"]["id"]), bytes.fromhex(c["out"]["nonce"]), c["out"]["name"]).hex(), c["hex"])
    for c in f["txt"]:
        args = (c["txt"], c["ownId"]) if "ownId" in c else (c["txt"],)      # an absent key is the unconfigured case; a null ownId is None, and refused
        check("advert: " + c["name"], _err(parse_txt, *args), c["out"])
    # A direct check, not a fixture row: a lone surrogate is not text, so the advert is refused as utf8. No fixture carries one (check_strict_json reads them all).
    check("advert, a direct check (not a fixture row): a name with a lone surrogate is refused as utf8", _err(parse_txt, {"v": "1", "id": "ab" * 16, "name": "\ud800x"}), {"error": "utf8"})
    for c in f["preamble"]:
        got = _err(decode_preamble, bytes.fromhex(c["hex"]))
        check("first record: " + c["name"], got, c["out"])
        if "error" not in c["out"]:
            check("first record: " + c["name"] + ", encoded again", encode_preamble(MODE_PAIR if got["mode"] == "pair" else MODE_TRANSFER, bytes.fromhex(got["id"])).hex(), c["hex"])
    for c in f["records"]:
        got = _err(split_records, bytes.fromhex(c["hex"]))
        check("records: " + c["name"], got if isinstance(got, dict) else {"records": [r.hex() for r in got[0]], "rest": got[1].hex()}, c["out"])
    for c in f["recordEncode"]:
        got = _err(encode_record, bytes.fromhex(c["payload"]))
        check("record: " + c["name"], {"hex": got.hex()} if isinstance(got, bytes) else got, c["out"])
    # The pairing of the xx-link Noise vector: its first message carries the commitment, its second and third the hellos with the nonces, and the code follows from them.
    p = load("pairing-cases.json")["session"]
    vec = {v["id"]: v for v in load("noise-vectors.json")["vectors"]}[p["vector"]]
    first, second, third = (bytes.fromhex(m["payload"]) for m in vec["messages"][:3])
    hr, hi = decode_hello(second), decode_hello(third)
    check("the xx-link vector's first payload is the initiator's commitment, and its hellos carry the nonces the pairing case names",
          (first.hex(), hi["nonce"], hr["nonce"]), (p["commit"], p["nonceI"], p["nonceR"]))
    check("the commitment is that of the initiator's nonce and of the static key its private key makes", commit_of(bytes.fromhex(hi["nonce"]), x25519_pub(bytes.fromhex(vec["init_static"]))).hex(), p["commit"])
    check("the code of that pairing is the one the case names, from the two nonces and the two static keys",
          pairing_code(bytes.fromhex(hi["nonce"]), bytes.fromhex(hr["nonce"]), x25519_pub(bytes.fromhex(vec["init_static"])), x25519_pub(bytes.fromhex(vec["resp_static"]))), p["code"])
    check("a record of 65535 bytes is made, one of 65536 is not", (len(encode_record(bytes(NOISE_MAX))), _err(encode_record, bytes(NOISE_MAX + 1))), (NOISE_MAX + 2, {"error": "record-length"}))
    # A seeded fuzz: damage valid frames in every way; the decoder raises only FrameError, and what it accepts encodes back to the same bytes.
    rnd = random.Random(20261014)
    seeds = [bytes.fromhex(c["hex"]) for c in f["frames"] if len(c["hex"]) < 400]
    ok, last = True, None
    for _ in range(8000):
        b = bytearray(rnd.choice(seeds))
        for _ in range(rnd.randrange(0, 4)):
            op = rnd.randrange(4)
            if op == 0 and b:
                b[rnd.randrange(len(b))] = rnd.randrange(256)
            elif op == 1 and b:
                del b[rnd.randrange(len(b)):]
            elif op == 2:
                b += bytes(rnd.randrange(256) for _ in range(rnd.randrange(1, 4)))
            elif b:
                b.insert(rnd.randrange(len(b)), rnd.randrange(256))
        try:
            got = decode_frame(bytes(b))
            if encode_frame(got) != bytes(b):
                ok, last = False, bytes(b).hex()
                break
        except FrameError:
            pass
        except Exception as e:                       # noqa: BLE001 - the point is that nothing else is raised
            ok, last = False, (bytes(b).hex(), repr(e))
            break
    check("8000 damaged frames: only FrameError is raised, and every accepted frame encodes back to the same bytes", (ok, last), (True, None))
def check_flow():
    print("flow-cases.json")
    f = load("flow-cases.json")
    check("the constants are the ones the rules name", (f["chunkSize"], f["sizeMax"], f["aborts"]), (CHUNK_SIZE, SIZE_MAX, list(ABORTS)))
    for c in f["receiver"]:
        check("receiver: " + c["name"], receiver_step(c["state"], c["event"]), c["out"])
    for c in f["sender"]:
        check("sender: " + c["name"], sender_step(c["state"], c["event"]), c["out"])
    for c in f["trips"]:
        step = receiver_step if c["side"] == "receiver" else sender_step
        state, got = c["from"], []
        for ev in c["events"]:
            res = step(state, ev)
            got.append(res)
            state = res["state"]
        check("trip: " + c["name"], got, c["out"])
    for c in f["chunkPlans"]:
        check("chunks: " + c["name"], [list(x) for x in plan_chunks(c["size"], c["chunkSize"])], c["out"])
    # The rules the app keeps around one connection: the machine's one transfer place, the one decline a connection may make, and the first-frame clock.
    check("the first-frame limit is the one the rules name", f["firstFrameMs"], FIRST_FRAME_MS)
    for c in f["places"]:
        place, got = c["from"], []
        for ev in c["events"]:
            res = place_step(place, ev)
            got.append(res)
            place = res["place"]
        check("place: " + c["name"], got, c["out"])
    for c in f["connections"]:
        conn, got = c["from"], []
        for ev in c["events"]:
            res = receiver_connection_step(conn, ev)
            got.append(res)
            conn = {"state": res["state"], "declines": res["declines"]}
        check("connection: " + c["name"], got, c["out"])
    for c in f["firstFrame"]:
        check("first frame: " + c["name"], first_frame_expired(c["handshake"], c["now"]), c["out"])
    # A seeded fuzz: random events from every state. Nothing raises, the received count never passes the size, an abort always lands in idle, only a click starts a transfer.
    rnd = random.Random(20261014)
    ids = ["01" * 16, "02" * 16]
    ok, last = True, None
    for _ in range(3000):
        state = {"s": "idle"}
        for _ in range(rnd.randrange(1, 30)):
            i = rnd.choice(ids)
            ev = rnd.choice([
                {"frame": {"type": "offer", "id": i, "size": rnd.choice([0, 5, 10, 2**32, 2**32 + 1]), "name": rnd.choice(["a.txt", "../x", "CON", "a\x00"]), "kind": ""}},
                {"frame": {"type": "chunk", "id": i, "offset": rnd.choice([0, 2, 4, 6, 8, 10]), "data": "ab" * rnd.randrange(1, 5)}},
                {"frame": {"type": rnd.choice(["done", "cancel", "accept"]), "id": i}},
                {"frame": {"type": "decline", "id": i, "reason": 0}},
                {"user": rnd.choice(["accept", "decline", "cancel"])}, {"timeout": True}])
            before = state
            res = receiver_step(state, ev)
            state = res["state"]
            if (res["abort"] is not None and (res["abort"] not in ABORTS or state != {"s": "idle"})
                    or (state["s"] == "receiving" and state["got"] > state["size"])
                    or (state["s"] == "receiving" and before["s"] != "receiving" and ev != {"user": "accept"})):
                ok, last = False, (before, ev, res)
                break
        if not ok:
            break
    check("3000 random event scripts: nothing raises, the count never passes the size, an abort lands in idle, only a click starts a transfer", (ok, last), (True, None))


def _no_constant(token):
    raise ValueError("NaN or Infinity is not JSON: " + token)


def _surrogate(s):
    return any("\ud800" <= c <= "\udfff" for c in s)


def _strict_pairs(pairs):
    """The strict object hook: a duplicate key (json would keep the last one) or a key with a lone surrogate is refused."""
    keys = [k for k, _ in pairs]
    if len(set(keys)) != len(keys):
        raise ValueError("a duplicate key")
    if any(_surrogate(k) for k in keys):
        raise ValueError("a lone surrogate in a key")
    return dict(pairs)


def _strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for v in value:
            yield from _strings(v)
    elif isinstance(value, dict):
        for v in value.values():
            yield from _strings(v)


def strict_problem(path):
    """None if the file is strict JSON: no NaN or Infinity, no duplicate key, no string (value or key) with a lone surrogate. Else why not."""
    try:
        with open(path, encoding="utf-8") as f:
            value = json.load(f, parse_constant=_no_constant, object_pairs_hook=_strict_pairs)
    except ValueError as e:  # a JSON error and a UTF-8 error are both ValueErrors
        return str(e)
    for s in _strings(value):
        if _surrogate(s):
            return "a string with a lone surrogate"
    return None


def check_strict_json():
    print("the JSON files, read by a strict parser")
    for name in sorted(n for n in os.listdir(HERE) if n.endswith(".json")):
        check(f"{name}: strict JSON (no NaN or Infinity, no duplicate key, no lone surrogate)", strict_problem(os.path.join(HERE, name)), None)
# @@CHECKS


def main():
    check_primitives()
    check_noise()
    check_pairing()
    check_pairing_machines()
    check_filenames()
    check_frames()
    check_flow()
    check_strict_json()
    # @@CALLS
    print(f"\n{'FAILED: ' + str(FAILURES) if FAILURES else 'all link contract checks passed'}")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
