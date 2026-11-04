import Foundation

// The small maths every cat file shares: helpers, the easing curves and the seeded PRNG. Port of the "Helpers" section of
// design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/motion-cases.json pins the easings and the PRNG.

/// The small maths helpers every cat file shares.
enum CatMath {
    static let tau = Double.pi * 2
}

func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double { max(a, min(b, v)) }
/// 0 up to 1 over a to b.
func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a), 0, 1) }
/// An angle wrapped to [-π, π).
func wrapA(_ a: Double) -> Double {
    let tau = CatMath.tau
    return (((a + Double.pi).truncatingRemainder(dividingBy: tau)) + tau).truncatingRemainder(dividingBy: tau) - Double.pi
}
/// Maps a trait to a multiplier: lo at 0, 1 at 0.5, hi at 1.
func tm(_ v: Double, _ lo: Double, _ hi: Double) -> Double { v < 0.5 ? lerp(lo, 1, v / 0.5) : lerp(1, hi, (v - 0.5) / 0.5) }
/// '#RRGGBB' to [r, g, b] in 0...255 (anything unreadable is black).
func hexRGB(_ h: String) -> [Double] {
    let s = h.hasPrefix("#") ? String(h.dropFirst()) : h
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return [0, 0, 0] }
    return [Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF)]
}

/// The easing curves, named like the prototype's `EZ`.
enum CatEase: String {
    case out, inOut, back, lin, `in`
    func at(_ t: Double) -> Double {
        switch self {
        case .out: return 1 - pow(1 - t, 3)
        case .inOut: return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        case .back: return 1 + 2.7 * pow(t - 1, 3) + 1.7 * pow(t - 1, 2)
        case .lin: return t
        case .in: return t * t * t
        }
    }
}

/// The seeded PRNG: a 32-bit LCG, the same sequence on every platform. The order of calls is part of the contract.
final class CatRNG {
    private var s: UInt32
    init(seed: UInt32) { s = seed }
    func next() -> Double {
        s = s &* 1103515245 &+ 12345
        return Double(s) / 4294967296
    }
}
