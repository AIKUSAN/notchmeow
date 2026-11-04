import CryptoKit
import Foundation

// The Noise layer of the link (sub-project G2, docs/LINK-CONTRACT.md "On the wire" and "Notes for ports"): `Noise_XX_25519_ChaChaPoly_SHA256` for a pairing and
// `Noise_KK_25519_ChaChaPoly_SHA256` for a transfer, revision 34, written on CryptoKit alone (Curve25519, ChaChaPoly, SHA256, HMAC). No third-party code. Foundation and CryptoKit only,
// so a test program can compile it. Replayed against tests/fixtures/link/noise-vectors.json by scripts/test-link-noise.sh; tests/fixtures/link/reference.py decides when they disagree.
//
// Value types only: a handshake and a cipher state are structs, so an actor or a connection owns its copy and nothing is shared. Nothing here logs, and no key leaves this file except
// through `LinkHandshake.remoteStatic` (the public key the peer proved) and the two cipher states `finish()` returns.

enum LinkNoiseError: Error, Equatable {
    case tooLong            // a Noise message is 65535 bytes at most, tag included
    case decrypt            // the tag failed (or the box was too short to hold one)
    case lowOrderPoint      // a DH output of 32 zero bytes (RFC 7748, section 6.1)
    case invalidKey         // a public key that is not 32 bytes, or a private key CryptoKit refuses
    case notMyTurn
    case short              // a handshake message too short for the tokens it must hold
    case notFinished
    case needsRemoteStatic  // KK before the first message needs the peer's static key
    case nonceExhausted
}

enum LinkNoise {
    static let prologue = Data("notchmeow-link/1".utf8)
    static let maxMessage = 65535
    static let tag = 16

    static func hmac(_ key: Data, _ message: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }

    /// The two-output HKDF of the Noise spec.
    static func hkdf2(_ chainingKey: Data, _ input: Data) -> (Data, Data) {
        let temp = hmac(chainingKey, input)
        let out1 = hmac(temp, Data([1]))
        let out2 = hmac(temp, out1 + Data([2]))
        return (out1, out2)
    }

    static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

    /// The public key of a private one (32 bytes each).
    static func publicKey(of privateKey: Curve25519.KeyAgreement.PrivateKey) -> Data { privateKey.publicKey.rawRepresentation }

    static func privateKey(raw: Data) throws -> Curve25519.KeyAgreement.PrivateKey {
        guard raw.count == 32, let k = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) else { throw LinkNoiseError.invalidKey }
        return k
    }

    /// X25519. A public key that is not 32 bytes is refused, and so is an all-zero output.
    static func dh(_ priv: Curve25519.KeyAgreement.PrivateKey, _ pub: Data) throws -> Data {
        guard pub.count == 32, let p = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: pub) else { throw LinkNoiseError.invalidKey }
        // CryptoKit may refuse a low-order point itself; either way it is the same refusal.
        guard let secret = try? priv.sharedSecretFromKeyAgreement(with: p) else { throw LinkNoiseError.lowOrderPoint }
        let out = secret.withUnsafeBytes { Data($0) }
        if out.allSatisfy({ $0 == 0 }) { throw LinkNoiseError.lowOrderPoint }
        return out
    }
}

/// ChaChaPoly with a 12-byte nonce of 32 zero bits and then the 64-bit message count, little-endian (not XChaCha).
struct LinkCipherState {
    private(set) var key: SymmetricKey?
    private(set) var n: UInt64 = 0

    init(key: Data? = nil) { self.key = key.map { SymmetricKey(data: $0) } }

    var hasKey: Bool { key != nil }

    private func nonce() throws -> ChaChaPoly.Nonce {
        var d = Data(count: 4)
        var le = n.littleEndian
        d.append(Data(bytes: &le, count: 8))
        return try ChaChaPoly.Nonce(data: d)
    }

    mutating func encrypt(ad: Data, _ plaintext: Data) throws -> Data {
        if plaintext.count + (key != nil ? LinkNoise.tag : 0) > LinkNoise.maxMessage { throw LinkNoiseError.tooLong }
        guard let key else { return plaintext }
        if n >= UInt64.max { throw LinkNoiseError.nonceExhausted }
        let box = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce(), authenticating: ad)
        n += 1
        var sealed = Data(capacity: plaintext.count + LinkNoise.tag)   // a fresh Data starts at index 0, whatever slices CryptoKit hands back
        sealed.append(box.ciphertext)
        sealed.append(box.tag)
        return sealed
    }

    /// A message whose tag fails does not move the counter, so the genuine next one still opens.
    mutating func decrypt(ad: Data, _ ciphertext: Data) throws -> Data {
        if ciphertext.count > LinkNoise.maxMessage { throw LinkNoiseError.tooLong }
        guard let key else { return ciphertext }
        if n >= UInt64.max { throw LinkNoiseError.nonceExhausted }
        guard ciphertext.count >= LinkNoise.tag else { throw LinkNoiseError.decrypt }
        let body = ciphertext.prefix(ciphertext.count - LinkNoise.tag), tagBytes = ciphertext.suffix(LinkNoise.tag)
        guard let box = try? ChaChaPoly.SealedBox(nonce: nonce(), ciphertext: body, tag: tagBytes),
              let plain = try? ChaChaPoly.open(box, using: key, authenticating: ad) else { throw LinkNoiseError.decrypt }
        n += 1
        return plain
    }
}

enum LinkPattern: String {
    case xx = "XX", kk = "KK"

    var protocolName: String { "Noise_\(rawValue)_25519_ChaChaPoly_SHA256" }

    /// Tokens: `e` and `s` send a public key; `ee`, `es`, `se` and `ss` mix in a DH. In `es` the first letter is the initiator's key and the second the responder's.
    var messages: [[String]] {
        switch self {
        case .xx: return [["e"], ["e", "ee", "s", "es"], ["s", "se"]]
        case .kk: return [["e", "es", "ss"], ["e", "ee", "se"]]
        }
    }
    var preMessages: Bool { self == .kk }
}

/// One side of a handshake. `s` is the static private key, `rs` the peer's static public key (KK needs it before the first message), `e` an ephemeral private key (only the tests inject one;
/// an app leaves it nil and gets a random one at the first message).
struct LinkHandshake {
    private var h: Data
    private var ck: Data
    private var cs = LinkCipherState()
    private let pattern: LinkPattern
    private let initiator: Bool
    private let s: Curve25519.KeyAgreement.PrivateKey
    private var e: Curve25519.KeyAgreement.PrivateKey?
    private var re: Data?
    private(set) var remoteStatic: Data?
    private var index = 0

    init(pattern: LinkPattern, initiator: Bool, prologue: Data = LinkNoise.prologue, s: Curve25519.KeyAgreement.PrivateKey, rs: Data? = nil, e: Curve25519.KeyAgreement.PrivateKey? = nil) throws {
        self.pattern = pattern
        self.initiator = initiator
        self.s = s
        self.e = e
        self.remoteStatic = rs
        let name = Data(pattern.protocolName.utf8)
        h = name.count <= 32 ? name + Data(count: 32 - name.count) : LinkNoise.sha256(name)
        ck = h
        mixHash(prologue)
        if pattern.preMessages {
            // The pre-messages "-> s" then "<- s": the initiator's static key first, then the responder's.
            guard let rs, rs.count == 32 else { throw LinkNoiseError.needsRemoteStatic }
            let mine = LinkNoise.publicKey(of: s)
            mixHash(initiator ? mine : rs)
            mixHash(initiator ? rs : mine)
        }
    }

    var staticPublic: Data { LinkNoise.publicKey(of: s) }
    private var count: Int { pattern.messages.count }
    var isDone: Bool { index == count }
    var isMyTurn: Bool { index < count && (index % 2 == 0) == initiator }

    private mutating func mixHash(_ data: Data) { h = LinkNoise.sha256(h + data) }
    private mutating func mixKey(_ input: Data) {
        let (next, k) = LinkNoise.hkdf2(ck, input)
        ck = next
        cs = LinkCipherState(key: k)
    }
    private mutating func encryptAndHash(_ plain: Data) throws -> Data {
        let c = try cs.encrypt(ad: h, plain)
        mixHash(c)
        return c
    }
    private mutating func decryptAndHash(_ cipher: Data) throws -> Data {
        let p = try cs.decrypt(ad: h, cipher)
        mixHash(cipher)
        return p
    }

    private mutating func doDH(_ token: String) throws {
        let chars = Array(token)
        let (mine, theirs) = initiator ? (chars[0], chars[1]) : (chars[1], chars[0])
        let priv = mine == "e" ? e : s
        guard let priv, let pub = theirs == "e" ? re : remoteStatic else { throw LinkNoiseError.invalidKey }
        mixKey(try LinkNoise.dh(priv, pub))
    }

    mutating func write(_ payload: Data = Data()) throws -> Data {
        guard isMyTurn else { throw LinkNoiseError.notMyTurn }
        var out = Data()
        for token in pattern.messages[index] {
            switch token {
            case "e":
                if e == nil { e = Curve25519.KeyAgreement.PrivateKey() }
                let pub = LinkNoise.publicKey(of: e!)
                out += pub
                mixHash(pub)
            case "s":
                out += try encryptAndHash(LinkNoise.publicKey(of: s))
            default:
                try doDH(token)
            }
        }
        out += try encryptAndHash(payload)
        if out.count > LinkNoise.maxMessage { throw LinkNoiseError.tooLong }
        index += 1
        return out
    }

    mutating func read(_ message: Data) throws -> Data {
        guard !isDone, !isMyTurn else { throw LinkNoiseError.notMyTurn }
        if message.count > LinkNoise.maxMessage { throw LinkNoiseError.tooLong }
        let m = Data(message)   // re-based at 0, whatever slice it came from
        var pos = 0
        for token in pattern.messages[index] {
            switch token {
            case "e":
                guard m.count - pos >= 32 else { throw LinkNoiseError.short }
                let key = m.subdata(in: pos..<pos + 32)
                pos += 32
                re = key
                mixHash(key)
            case "s":
                let n = 32 + (cs.hasKey ? LinkNoise.tag : 0)
                guard m.count - pos >= n else { throw LinkNoiseError.short }
                remoteStatic = try decryptAndHash(m.subdata(in: pos..<pos + n))
                pos += n
            default:
                try doDH(token)
            }
        }
        let payload = try decryptAndHash(m.subdata(in: pos..<m.count))
        index += 1
        return payload
    }

    /// After the last message: the handshake hash, and the cipher states for this side (send, receive).
    func finish() throws -> (hash: Data, send: LinkCipherState, receive: LinkCipherState) {
        guard isDone else { throw LinkNoiseError.notFinished }
        let (k1, k2) = LinkNoise.hkdf2(ck, Data())
        let c1 = LinkCipherState(key: k1), c2 = LinkCipherState(key: k2)
        return initiator ? (h, c1, c2) : (h, c2, c1)
    }
}
