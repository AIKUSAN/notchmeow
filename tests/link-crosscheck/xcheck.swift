import Foundation
import CryptoKit

func hex(_ s: String) -> Data { var d = Data(); var i = s.startIndex; while i < s.endIndex { let j = s.index(i, offsetBy: 2); d.append(UInt8(s[i..<j], radix: 16)!); i = j }; return d }
func hx(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
func hmac(_ k: Data, _ m: Data) -> Data { Data(HMAC<SHA256>.authenticationCode(for: m, using: SymmetricKey(data: k))) }
func hkdf(_ ck: Data, _ ikm: Data) -> (Data, Data) { let t = hmac(ck, ikm); let o1 = hmac(t, Data([1])); let o2 = hmac(t, o1 + Data([2])); return (o1, o2) }
struct CS { var k: Data?; var n: UInt64 = 0
  func nonce() -> ChaChaPoly.Nonce { var d = Data(count: 4); var n = self.n.littleEndian; d.append(Data(bytes: &n, count: 8)); return try! ChaChaPoly.Nonce(data: d) }
  mutating func enc(_ ad: Data, _ pt: Data) -> Data { guard let k = k else { return pt }; let b = try! ChaChaPoly.seal(pt, using: SymmetricKey(data: k), nonce: nonce(), authenticating: ad); n += 1; return b.ciphertext + b.tag }
  mutating func dec(_ ad: Data, _ ct: Data) -> Data { guard let k = k else { return ct }; let box = try! ChaChaPoly.SealedBox(nonce: nonce(), ciphertext: ct.dropLast(16), tag: ct.suffix(16)); n += 1; return try! ChaChaPoly.open(box, using: SymmetricKey(data: k), authenticating: ad) }
}
struct SS { var h: Data; var ck: Data; var cs = CS(k: nil)
  init(_ name: String) { var b = Data(name.utf8); if b.count <= 32 { b.append(Data(count: 32 - b.count)); h = b } else { h = Data(SHA256.hash(data: b)) }; ck = h }
  mutating func mixHash(_ d: Data) { h = Data(SHA256.hash(data: h + d)) }
  mutating func mixKey(_ d: Data) { let (a, b) = hkdf(ck, d); ck = a; cs = CS(k: b) }
  mutating func encHash(_ p: Data) -> Data { let c = cs.enc(h, p); mixHash(c); return c }
  mutating func decHash(_ c: Data) -> Data { let p = cs.dec(h, c); mixHash(c); return p }
}
func dh(_ priv: Data, _ pub: Data) -> Data { let k = try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: priv); let p = try! Curve25519.KeyAgreement.PublicKey(rawRepresentation: pub); return try! k.sharedSecretFromKeyAgreement(with: p).withUnsafeBytes { Data($0) } }
func pub(_ priv: Data) -> Data { try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: priv).publicKey.rawRepresentation }

struct HS {
  var ss: SS; let initiator: Bool; let s: Data; var rs: Data?; let e: Data; var re: Data?; let msgs: [[String]]
  init(pattern: String, initiator: Bool, prologue: Data, s: Data, rs: Data?, e: Data) {
    ss = SS("Noise_\(pattern)_25519_ChaChaPoly_SHA256"); self.initiator = initiator; self.s = s; self.rs = rs; self.e = e
    msgs = pattern == "XX" ? [["e"], ["e","ee","s","es"], ["s","se"]] : [["e","es","ss"], ["e","ee","se"]]
    ss.mixHash(prologue)
    if pattern == "KK" { let ip = initiator ? pub(s) : rs!; let rp = initiator ? rs! : pub(s); ss.mixHash(ip); ss.mixHash(rp) }
  }
  mutating func doDH(_ t: String) {
    let a = String(t.first!), b = String(t.last!)
    let (mine, theirs) = initiator ? (a, b) : (b, a)
    let priv = mine == "e" ? e : s; let p = theirs == "e" ? re! : rs!
    ss.mixKey(dh(priv, p))
  }
  mutating func write(_ i: Int, _ payload: Data) -> Data {
    var buf = Data()
    for t in msgs[i] { if t == "e" { buf += pub(e); ss.mixHash(pub(e)) } else if t == "s" { buf += ss.encHash(pub(s)) } else { doDH(t) } }
    return buf + ss.encHash(payload)
  }
  mutating func read(_ i: Int, _ m: Data) -> Data {
    var pos = 0
    for t in msgs[i] {
      if t == "e" { re = m.subdata(in: pos..<pos+32); pos += 32; ss.mixHash(re!) }
      else if t == "s" { let n = 32 + (ss.cs.k != nil ? 16 : 0); rs = ss.decHash(m.subdata(in: pos..<pos+n)); pos += n }
      else { doDH(t) }
    }
    return ss.decHash(m.subdata(in: pos..<m.count))
  }
}
let vectors = (try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any])["vectors"] as! [[String: Any]]
var bad = 0
for v in vectors {
  let name = v["name"] as! String
  let pattern = (v["protocol_name"] as! String).split(separator: "_")[1].description
  let pro = hex(v["init_prologue"] as! String)
  var i = HS(pattern: pattern, initiator: true, prologue: pro, s: hex(v["init_static"] as! String), rs: (v["init_remote_static"] as? String).map(hex), e: hex(v["init_ephemeral"] as! String))
  var r = HS(pattern: pattern, initiator: false, prologue: pro, s: hex(v["resp_static"] as! String), rs: (v["resp_remote_static"] as? String).map(hex), e: hex(v["resp_ephemeral"] as! String))
  let msgs = v["messages"] as! [[String: String]]
  let nhs = pattern == "XX" ? 3 : 2
  var ok = true
  for n in 0..<nhs {
    let pl = hex(msgs[n]["payload"]!), want = hex(msgs[n]["ciphertext"]!)
    let c = n % 2 == 0 ? i.write(n, pl) : r.write(n, pl)
    let back = n % 2 == 0 ? r.read(n, c) : i.read(n, c)
    if c != want || back != pl { ok = false; print("  mismatch at handshake message \(n)") }
  }
  if hx(i.ss.h) != v["handshake_hash"] as! String || i.ss.h != r.ss.h { ok = false; print("  handshake hash differs") }
  let (k1, k2) = hkdf(i.ss.ck, Data())
  var ci = CS(k: k1), cr = CS(k: k2)   // ci: initiator->responder, cr: responder->initiator
  for n in nhs..<msgs.count {
    let pl = hex(msgs[n]["payload"]!), want = hex(msgs[n]["ciphertext"]!)
    let c = (n % 2 == 0) ? ci.enc(Data(), pl) : cr.enc(Data(), pl)
    if c != want { ok = false; print("  mismatch at transport message \(n)") }
  }
  print(ok ? "✓" : "✗", name); if !ok { bad += 1 }
}
exit(bad == 0 ? 0 : 1)
