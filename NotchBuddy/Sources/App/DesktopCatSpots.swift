import Foundation

// Where the desktop cat sits (sub-project H): the screens, the key an arrangement of them is remembered under, and the spot kept for each. Port of the "The desktop cat: size,
// frame rate and kittens" (sizes) and "spots on the screens" sections of design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/desktop-cases.json pins it.
// Coordinates are points, y down, the origin at the top left of the main screen. The Mac converts from AppKit's bottom-left origin (`DesktopCatScreens` in
// DesktopCatLayout.swift: `yTop = primaryHeight - frame.maxY`). A spot is the cat's head centre. Foundation only; nothing here knows about AppKit, UserDefaults or the app.

/// The desktop cat's three sizes. The raw values are frozen contract values, like the cat IDs: they are stored. `medium` is the default.
enum DesktopSize: String, CaseIterable, Sendable {
    case small, medium, large

    /// The head width in points (`DESKTOP_SIZES`).
    var d: Double {
        switch self {
        case .small: return 48
        case .medium: return 64
        case .large: return 96
        }
    }

    /// A stored size to one of the three; anything else (a wrong case, a number, a space) is `medium`.
    static func of(_ v: Any?) -> DesktopSize { (v as? String).flatMap { DesktopSize(rawValue: $0) } ?? .medium }
}

struct DesktopRect: Equatable, Sendable {
    var x: Double, y: Double, w: Double, h: Double
}

/// A screen: `frame` the whole screen, `visible` what the menu bar and the Dock leave, `main` the one with the menu bar.
struct DesktopScreen: Equatable, Sendable {
    var frame: DesktopRect
    var visible: DesktopRect
    var main = false
}

/// The cat's head centre.
struct DesktopSpot: Equatable, Sendable {
    var x: Double, y: Double
}

enum DesktopCatSpots {
    /// The cat keeps this many points between its head and the edge of the visible frame, so it never sits under the menu bar or the Dock.
    static let margin = 24.0
    /// The first spot ever: this fraction of the main screen's visible frame across (right of centre) and down (a third, below the notch).
    static let defaultAcross = 0.6, defaultDown = 1.0 / 3
    /// A stored map keeps the spots of at most this many screen arrangements (the first by code-point order of their keys).
    static let maxSpots = 32
    /// A spot's coordinates are no larger than this; a frame's no larger than `rectLimit`; at most `maxScreens` screens count.
    static let spotLimit = 1e5, rectLimit = 1e6, maxScreens = 16

    // MARK: Raw values (the fixtures and a hand-edited file hold anything)

    /// A JSON number: a boolean, text and null are not numbers, and neither are NaN and infinity.
    static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }

    static func isValid(_ s: DesktopSpot) -> Bool { s.x.isFinite && s.y.isFinite && abs(s.x) <= spotLimit && abs(s.y) <= spotLimit }

    /// `{x, y}` of two numbers no larger than 100000 in size, reduced to those two; anything else is not a spot.
    static func spot(_ raw: Any?) -> DesktopSpot? {
        guard let o = raw as? [String: Any], let x = number(o["x"]), let y = number(o["y"]) else { return nil }
        let s = DesktopSpot(x: x, y: y)
        return isValid(s) ? s : nil
    }

    static func isValid(_ r: DesktopRect) -> Bool {
        [r.x, r.y, r.w, r.h].allSatisfy { $0.isFinite && abs($0) <= rectLimit } && r.w >= 1 && r.h >= 1
    }

    static func rect(_ raw: Any?) -> DesktopRect? {
        guard let o = raw as? [String: Any], let x = number(o["x"]), let y = number(o["y"]), let w = number(o["w"]), let h = number(o["h"]) else { return nil }
        let r = DesktopRect(x: x, y: y, w: w, h: h)
        return isValid(r) ? r : nil
    }

    /// The screens that are screens, as `tidy` makes them, from a raw list of `{frame, visible, main}` (at most 256 entries are looked at).
    static func screens(_ raw: Any?) -> [DesktopScreen] {
        var out: [DesktopScreen] = []
        for entry in (raw as? [Any] ?? []).prefix(256) {
            guard let s = entry as? [String: Any], let f = rect(s["frame"]) else { continue }
            let main = (s["main"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false
            out.append(DesktopScreen(frame: f, visible: rect(s["visible"]) ?? f, main: main))
        }
        return tidy(out)
    }

    /// The screens that are usable, sorted by frame and at most 16: a screen without a usable frame is dropped, and a visible frame that is outside its frame
    /// is the frame (otherwise it is held inside it). Idempotent.
    static func tidy(_ list: [DesktopScreen]) -> [DesktopScreen] {
        var out: [(Int, DesktopScreen)] = []
        for (i, s) in list.enumerated() where isValid(s.frame) {
            let f = s.frame, v = s.visible
            let x0 = isValid(v) ? max(v.x, f.x) : 0, y0 = isValid(v) ? max(v.y, f.y) : 0
            let x1 = isValid(v) ? min(v.x + v.w, f.x + f.w) : 0, y1 = isValid(v) ? min(v.y + v.h, f.y + f.h) : 0
            let visible = isValid(v) && x1 > x0 && y1 > y0 ? DesktopRect(x: x0, y: y0, w: x1 - x0, h: y1 - y0) : f
            out.append((i, DesktopScreen(frame: f, visible: visible, main: s.main)))
        }
        // JavaScript's sort is stable; Swift's is not guaranteed to be, so ties keep their order by index.
        out.sort { a, b in
            let p = a.1.frame, q = b.1.frame
            if p.x != q.x { return p.x < q.x }
            if p.y != q.y { return p.y < q.y }
            if p.w != q.w { return p.w < q.w }
            if p.h != q.h { return p.h < q.h }
            return a.0 < b.0
        }
        return out.prefix(maxScreens).map(\.1)
    }

    // MARK: The key

    /// `floor(v + 0.5)`: half up, not Swift's `rounded()` (which rounds half away from zero and differs below zero).
    static func round(_ v: Double) -> Double { (v + 0.5).rounded(.down) }

    /// The key an arrangement is remembered under: the frames rounded to whole points, sorted, written `x,y,w,h` and joined with `|`. The order the screens come in, the
    /// visible frames and the main flag do not matter (moving the Dock must not forget the spot). No usable screen: "".
    static func screenKey(_ screens: [DesktopScreen]) -> String {
        tidy(screens).map { s in [s.frame.x, s.frame.y, s.frame.w, s.frame.h].map { Int(round($0)) } }
            .sorted { a, b in a.lexicographicallyPrecedes(b) }
            .map { $0.map(String.init).joined(separator: ",") }
            .joined(separator: "|")
    }

    /// True for exactly the strings `screenKey` writes: the whole string (a trailing newline is not a key), no leading zeros or -0, positive sizes, frames in sorted order,
    /// at most 16.
    static func isScreenKey(_ v: Any?) -> Bool {
        guard let key = v as? String else { return false }
        let parts = key.split(separator: "|", omittingEmptySubsequences: false)
        guard (1...maxScreens).contains(parts.count) else { return false }
        func digits(_ s: Substring, signed: Bool) -> Double? {
            var u = Array(s.utf8)
            let negative = signed && u.first == 0x2D
            if negative { u.removeFirst() }
            guard (1...7).contains(u.count), u.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
            let value = Double(String(decoding: u, as: UTF8.self))!
            return negative ? -value : value
        }
        var list: [DesktopScreen] = []
        for part in parts {
            let f = part.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count == 4, let x = digits(f[0], signed: true), let y = digits(f[1], signed: true), let w = digits(f[2], signed: false), let h = digits(f[3], signed: false) else { return false }
            let r = DesktopRect(x: x, y: y, w: w, h: h)
            list.append(DesktopScreen(frame: r, visible: r))
        }
        return screenKey(list) == key
    }

    // MARK: Where the cat may sit

    static func contains(_ r: DesktopRect, _ p: DesktopSpot) -> Bool { p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h }

    /// The screen with the menu bar: the one marked main, else the one holding the origin, else the first by frame. Nil with no screens.
    static func mainScreen(_ list: [DesktopScreen]) -> DesktopScreen? {
        let s = tidy(list)
        return s.first { $0.main } ?? s.first { contains($0.frame, DesktopSpot(x: 0, y: 0)) } ?? s.first
    }

    /// The point held inside a screen's visible frame, `d / 2` plus the margin from every edge; a frame too small for that holds the centre.
    private static func place(_ s: DesktopScreen, _ p: DesktopSpot, _ d: Double) -> DesktopSpot {
        let v = s.visible, m = margin + d / 2
        func at(_ lo: Double, _ len: Double, _ c: Double) -> Double { len <= 2 * m ? lo + len / 2 : min(max(c, lo + m), lo + len - m) }
        return DesktopSpot(x: at(v.x, v.w, p.x), y: at(v.y, v.h, p.y))
    }

    /// The first spot ever, on the main screen. Nil with no screens.
    static func defaultSpot(_ screens: [DesktopScreen], size: DesktopSize) -> DesktopSpot? {
        guard let s = mainScreen(screens) else { return nil }
        let v = s.visible
        return place(s, DesktopSpot(x: v.x + v.w * defaultAcross, y: v.y + v.h * defaultDown), size.d)
    }

    /// Keeps a spot where the cat may sit: on the screen whose frame holds it, inside that screen's visible frame. A spot on no screen (its screen was unplugged, or it is
    /// not a spot) goes to the main screen's default spot. Nil with no screens.
    static func clampSpot(_ spot: DesktopSpot?, _ screens: [DesktopScreen], size: DesktopSize) -> DesktopSpot? {
        let list = tidy(screens)
        guard !list.isEmpty else { return nil }
        if let p = spot, isValid(p), let s = list.first(where: { contains($0.frame, p) }) { return place(s, p, size.d) }
        return defaultSpot(list, size: size)
    }

    // MARK: The stored map

    /// A stored map from screen key to spot, cleaned. It may be a dictionary or the JSON text of one (the Mac stores text; text that is not strict JSON is `{}`). A key
    /// `isScreenKey` refuses is dropped, and so is a value that is not a spot. The result holds at most 32 spots, the first by code-point order of the keys.
    static func cleanSpots(_ raw: Any?) -> [String: DesktopSpot] {
        var v = raw
        if let text = v as? String {
            let data = Data(text.utf8)
            v = Personality.isStrictJSON(data) ? try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) : nil
        }
        guard let map = v as? [String: Any] else { return [:] }
        var out: [String: DesktopSpot] = [:]
        for key in map.keys.filter({ isScreenKey($0) }).sorted(by: { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes(Array($1.unicodeScalars.map(\.value))) }) {
            if out.count >= maxSpots { break }
            if let s = spot(map[key]) { out[key] = s }
        }
        return out
    }

    /// The spot to use now: the one remembered for this arrangement, held where the cat may sit, else the default spot. Nil with no screens.
    static func spotFor(_ spots: [String: DesktopSpot], _ screens: [DesktopScreen], size: DesktopSize) -> DesktopSpot? {
        let list = tidy(screens)
        guard !list.isEmpty else { return nil }
        if let s = spots[screenKey(list)] { return clampSpot(s, list, size: size) }
        return defaultSpot(list, size: size)
    }

    /// The map after the cat was released at `spot` on these screens: this arrangement's spot is the clamped one, the others stay. The map keeps at most 32 arrangements
    /// and always keeps the one just written. With no screens nothing changes.
    static func rememberSpot(_ spots: [String: DesktopSpot], _ screens: [DesktopScreen], _ spot: DesktopSpot, size: DesktopSize) -> [String: DesktopSpot] {
        let m = cleanSpots(spots.mapValues { ["x": $0.x, "y": $0.y] })
        guard let c = clampSpot(spot, screens, size: size) else { return m }
        let k = screenKey(screens)
        let others = m.keys.filter { $0 != k }.sorted { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes(Array($1.unicodeScalars.map(\.value))) }
        var out: [String: DesktopSpot] = [:]
        for q in others.prefix(maxSpots - 1) { out[q] = m[q] }
        out[k] = c
        return out
    }
}
