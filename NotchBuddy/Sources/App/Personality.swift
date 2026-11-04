import Foundation

// Personality: six traits, 0…1, that bend the behaviour a cat already has. 0.5 is neutral, so the Balanced preset is exactly
// the approved motion (and Classic stays 1:1 with upstream). Any coat can wear any personality. Port of the "Personality"
// section of design/prototype/cat-core.js; tests/fixtures/cat/personality-cases.json pins it.

/// A cat's personality as it is stored: a preset name plus the six traits. Moving a slider makes the preset "custom".
/// Encodable only, on purpose: a stored personality is read by `Personality.clean` and never decoded, because Codable's decoding throws on a value
/// that is bad JSON or has the wrong types, and a settings file can hold anything.
struct CatPersonality: Encodable, Equatable, Sendable {
    var preset = "balanced"
    var energy = 0.5
    var curiosity = 0.5
    var chatty = 0.5
    var affection = 0.5
    var sass = 0.5
    var mischief = 0.5

    /// The personality as the fixtures hold it, a JSON-shaped dictionary.
    var json: [String: Any] {
        ["preset": preset, "energy": energy, "curiosity": curiosity, "chatty": chatty, "affection": affection, "sass": sass, "mischief": mischief]
    }

    /// A trait by its key; nil for a name that is not a trait.
    subscript(_ trait: String) -> Double? {
        get {
            switch trait {
            case "energy": return energy
            case "curiosity": return curiosity
            case "chatty": return chatty
            case "affection": return affection
            case "sass": return sass
            case "mischief": return mischief
            default: return nil
            }
        }
        set {
            guard let v = newValue else { return }
            switch trait {
            case "energy": energy = v
            case "curiosity": curiosity = v
            case "chatty": chatty = v
            case "affection": affection = v
            case "sass": sass = v
            case "mischief": mischief = v
            default: break
            }
        }
    }
}

/// What a personality changes, as numbers. The engine reads only these.
/// `speed`, `hop`, `blinkEvery`, `gaze`, `earFlickEvery`, `chatter` and `slowBlinkEvery` are multipliers (1 at neutral);
/// `pupil`, `smile`, `skew`, `blush`, `lid` and `earBack` are added to the resting pose (0 at neutral);
/// `idle` says which idle habits are on; `poke` is the reaction to a poke and `pokeHiss` adds a hiss to it.
struct CatMultipliers: Encodable, Equatable, Sendable {
    struct Idle: Encodable, Equatable, Sendable {
        var yawn: Bool, zoomies: Bool, mew: Bool, purr: Bool, hmph: Bool, wink: Bool
    }
    var speed: Double, hop: Double, blinkEvery: Double, pupil: Double, lid: Double, gaze: Double, earFlickEvery: Double
    var chatter: Double, smile: Double, blush: Double, slowBlinkEvery: Double, skew: Double, earBack: Double
    var idle: Idle
    /// "love" or "annoyed".
    var poke: String
    var pokeHiss: Bool
}

enum Personality {
    /// The six traits, in the order Settings shows them: key, label, low end, high end.
    static let traits: [(key: String, label: String, low: String, high: String)] = [
        ("energy", "Energy", "sleepy", "bouncy"), ("curiosity", "Curiosity", "aloof", "nosy"), ("chatty", "Chattiness", "quiet", "talkative"),
        ("affection", "Affection", "independent", "cuddly"), ("sass", "Sass", "easy-going", "grumpy"), ("mischief", "Mischief", "well-behaved", "troublemaker"),
    ]

    /// The presets, in the order Settings shows them.
    static let presets: [(key: String, label: String, traits: CatPersonality)] = [
        ("balanced", "Balanced", make("balanced", 0.5, 0.5, 0.5, 0.5, 0.5, 0.5)),
        ("chill", "Chill", make("chill", 0.12, 0.35, 0.3, 0.65, 0.3, 0.2)),
        ("grumpy", "Grumpy", make("grumpy", 0.4, 0.3, 0.45, 0.15, 0.95, 0.3)),
        ("sweet", "Sweet", make("sweet", 0.5, 0.55, 0.55, 1, 0.1, 0.3)),
        ("hyper", "Hyper", make("hyper", 1, 0.9, 0.75, 0.5, 0.3, 1)),
        ("chatty", "Chatty", make("chatty", 0.6, 0.7, 1, 0.6, 0.35, 0.5)),
    ]

    private static func make(_ preset: String, _ e: Double, _ cu: Double, _ ch: Double, _ af: Double, _ sa: Double, _ mi: Double) -> CatPersonality {
        CatPersonality(preset: preset, energy: e, curiosity: cu, chatty: ch, affection: af, sass: sa, mischief: mi)
    }

    /// A preset as a cat stores it: its name plus the six traits. An unknown name gives Balanced.
    static func named(_ name: String) -> CatPersonality {
        presets.first { $0.key == name }?.traits ?? presets[0].traits
    }

    /// Moving a slider: the new value (held to 0…1) and the preset becomes "custom". An unknown trait, or a value that is not a
    /// finite number, changes nothing.
    static func slide(_ p: CatPersonality, trait: String, value: Double) -> CatPersonality {
        var q = p
        guard p[trait] != nil, value.isFinite else { return q }
        q[trait] = clamp(value, 0, 1)
        q.preset = "custom"
        return q
    }

    /// Traits as a settings file can hold them (anything at all): a missing, non-numeric, NaN or infinite trait becomes 0.5, anything else is
    /// held to 0…1. The preset name is kept only when it names one of the six presets and the traits are still that preset's (within 1e-9);
    /// anything else, a missing or unknown name included, is "custom". This is the contract's `cleanPersonality`
    /// (tests/fixtures/cat/settings-cases.json pins it).
    static func sanitized(_ raw: [String: Any]) -> CatPersonality {
        var p = CatPersonality()
        for t in traits {
            var v = 0.5
            if let n = raw[t.key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite { v = n.doubleValue }
            p[t.key] = clamp(v, 0, 1) + 0   // + 0 turns a minus zero into 0
        }
        if let name = raw["preset"] as? String, let preset = presets.first(where: { $0.key == name }),
           traits.allSatisfy({ abs((p[$0.key] ?? 0.5) - (preset.traits[$0.key] ?? 0.5)) <= 1e-9 }) {
            p.preset = name
        } else {
            p.preset = "custom"
        }
        return p
    }

    /// A stored personality, whatever it is: an object, or the JSON text (or the bytes) of one. Text that is not JSON, and JSON that is not an
    /// object, give Balanced; an object goes through `sanitized`. Never throws. Every personality read from a settings file comes through here.
    static func clean(_ raw: Any?) -> CatPersonality {
        var v = raw
        if let text = v as? String { v = Data(text.utf8) }
        if let data = v as? Data { v = isStrictJSON(data) ? try? JSONSerialization.jsonObject(with: data) : nil }
        guard let object = v as? [String: Any] else { return named("balanced") }
        return sanitized(object)
    }

    /// The contract says text that is not strict JSON is not JSON. Foundation's parser also takes a comma before a closing brace or bracket and a
    /// byte-order mark, which `JSON.parse` and every other strict parser refuse, so those two are refused here before it runs.
    static func isStrictJSON(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return false }
        var inString = false, escaped = false, comma = false
        for c in bytes {
            if inString {
                if escaped { escaped = false } else if c == 0x5C { escaped = true } else if c == 0x22 { inString = false }
                continue
            }
            switch c {
            case 0x22: inString = true; comma = false
            case 0x2C: comma = true
            case 0x20, 0x09, 0x0A, 0x0D: break
            case 0x7D, 0x5D: if comma { return false }
            default: comma = false
            }
        }
        return true
    }

    /// The text a personality is stored as: its JSON, keys sorted so the same personality is always the same text.
    static func jsonText(_ p: CatPersonality) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? String(data: encoder.encode(p), encoding: .utf8)) ?? "{}"
    }

    static func multipliers(_ raw: [String: Any]) -> CatMultipliers { multipliers(sanitized(raw)) }

    static func multipliers(_ p0: CatPersonality) -> CatMultipliers {
        let energy = clamp(p0.energy, 0, 1), sass = clamp(p0.sass, 0, 1), aff = clamp(p0.affection, 0, 1)
        let curiosity = clamp(p0.curiosity, 0, 1), chatty = clamp(p0.chatty, 0, 1), mischief = clamp(p0.mischief, 0, 1)
        return CatMultipliers(
            speed: tm(energy, 0.55, 1.5), hop: tm(energy, 0.45, 1.4), blinkEvery: tm(energy, 1.4, 0.75), pupil: (energy - 0.5) * 0.3,
            lid: max(max(0, 0.5 - energy), max(0, sass - 0.55) * 0.55),
            gaze: tm(curiosity, 0.35, 1.2), earFlickEvery: tm(curiosity, 1.6, 0.6), chatter: tm(chatty, 0.3, 1.4),
            smile: (aff - 0.5) * 0.5 - max(0, sass - 0.5) * 1.1, blush: max(0, aff - 0.6) * 0.9, slowBlinkEvery: tm(aff, 1.6, 0.5),
            skew: max(0, sass - 0.5) * 0.9, earBack: max(0, sass - 0.55) * 0.45,
            idle: .init(yawn: energy < 0.3, zoomies: mischief > 0.75 && energy > 0.7, mew: chatty > 0.7, purr: aff > 0.75, hmph: sass > 0.75, wink: mischief > 0.65),
            poke: aff > 0.75 && sass < 0.4 ? "love" : "annoyed", pokeHiss: sass > 0.7)
    }
}
