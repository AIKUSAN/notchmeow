import Foundation

// Small byte helpers of the link (sub-project G2), shared by the frames, the pairing and the session. Foundation only.
// Hex on the wire and in the contract is lower-case: `isCanonicalHex` refuses a capital, and nothing here lower-cases a value to make it fit (docs/LINK-CONTRACT.md, "Notes for ports").

enum LinkBytes {
    static func hex(_ data: some Sequence<UInt8>) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var out: [UInt8] = []
        for b in data { out.append(digits[Int(b >> 4)]); out.append(digits[Int(b & 15)]) }
        return String(decoding: out, as: UTF8.self)
    }

    /// The bytes of a hex string of either case, nil when it is not hex or has an odd length.
    static func data(hex: String) -> Data? {
        let u = Array(hex.utf8)
        guard u.count % 2 == 0 else { return nil }
        var out = Data(capacity: u.count / 2)
        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case 48...57: return c - 48
            case 97...102: return c - 87
            case 65...70: return c - 55
            default: return nil
            }
        }
        var i = 0
        while i < u.count {
            guard let hi = nibble(u[i]), let lo = nibble(u[i + 1]) else { return nil }
            out.append(hi << 4 | lo)
            i += 2
        }
        return out
    }

    /// `bytes` bytes as exactly `2 * bytes` lower-case hex digits.
    static func isCanonicalHex(_ s: String?, bytes: Int) -> Bool {
        guard let s else { return false }
        let u = s.utf8
        return u.count == 2 * bytes && u.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
    }

    /// A 32-byte value (a nonce, a key, a commitment) as 64 lower-case hex digits.
    static func isHex32(_ s: String?) -> Bool { isCanonicalHex(s, bytes: 32) }
    /// A device id on the wire: 16 bytes, 32 lower-case hex digits.
    static func isIdHex(_ s: String?) -> Bool { isCanonicalHex(s, bytes: 16) }
    static let zeroId = String(repeating: "0", count: 32)

    static func beUInt64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8((v >> UInt64(56 - 8 * $0)) & 0xFF) } }
    static func beUInt16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
    static func readUInt64(_ b: ArraySlice<UInt8>) -> UInt64 { b.reduce(0) { $0 << 8 | UInt64($1) } }
    static func readUInt16(_ b: ArraySlice<UInt8>) -> UInt16 { b.reduce(0) { $0 << 8 | UInt16($1) } }
}

/// A machine's own device id as the pairing and the advert rules see it. `absent` is a machine that has no id yet (the unconfigured case); `null` is an id that is present and is
/// not an id, which the contract refuses fail-closed (a port never passes null: it omits the id when it has none).
enum LinkOwnId: Equatable, Sendable {
    case absent
    case null
    case value(String)
}
