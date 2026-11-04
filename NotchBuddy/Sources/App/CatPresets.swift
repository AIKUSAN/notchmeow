import Foundation

// The cats, as numbers. Every value is in units of R, the head radius, and is the same as in
// design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/presets.json pins them.
// The 16 IDs are frozen contract values: they are stored in settings.

struct CatPreset: Encodable, Sendable {
    struct Ruff: Encodable, Sendable { var rx: Double; var ry: Double; var dy: Double; var col: [String] }
    struct FurOpts: Encodable, Sendable {
        var n: Int; var l0: Double; var l1: Double; var w: Double; var dark: String; var light: String
        var wDark: String?; var wLight: String?
    }
    struct Ear: Encodable, Sendable {
        var h: Double; var bw: Double; var rot: Double; var tip: Double; var tuft: Double
        /// Absent means the default 0.95 (Shrimpy has none).
        var cx: Double?
        /// A folded ear (Button): the tip folds forward and down over the head.
        var fold: Double?
    }
    struct Eye: Encodable, Sendable { var th: Double; var ph: Double; var w: Double; var h: Double; var round: Double }
    struct Whisk: Encodable, Sendable {
        var rows: Int; var cols: Int; var x0: Double; var dx: Double; var y0: Double; var dy: Double; var slope: Double
        var dot: Double; var wcols: [Int]; var a0: Double; var da: Double; var len: Double; var dl: Double
        var droop: Double; var w: Double; var alpha: Double; var brow: Int
    }
    /// A coat patch: x, y, half width, half height, rotation (all R), colour, wobble seed. Stored as a JSON array like the contract.
    struct Patch: Encodable, Sendable {
        var x: Double; var y: Double; var a: Double; var b: Double; var rot: Double; var color: String; var seed: Int
        init(_ x: Double, _ y: Double, _ a: Double, _ b: Double, _ rot: Double, _ color: String, _ seed: Int) {
            self.x = x; self.y = y; self.a = a; self.b = b; self.rot = rot; self.color = color; self.seed = seed
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.unkeyedContainer()
            try c.encode(x); try c.encode(y); try c.encode(a); try c.encode(b); try c.encode(rot); try c.encode(color); try c.encode(seed)
        }
    }

    var name: String
    var label: String
    var desc: String?
    /// A pitch offset in semitones for sub-project C: Shrimpy -1, Momo +1, the extra coats 0, kittens +3.
    var voice: Int
    /// "tuxedo", "tabby", "point", "calico" or "solid".
    var coat: String
    var rx: Double
    var ry: Double
    var n: Double
    var fluff: Double
    var ruff: Ruff?
    var bib: String?
    var furOpts: FurOpts?
    var earSpread: Double
    var ear: Ear
    var top: String
    var bot: String
    var light: String?
    var chinCol: String?
    var stripe: String?
    var rimLight: Int?
    var white: String?
    var point: String?
    var earCols: [String]?
    var muzzle: String?
    var patches: [Patch]?
    var hairless: Int?
    var wrinkles: Int?
    var inner: String
    var nose: String
    var noseLine: String
    var noseW: Double
    var noseH: Double
    var nosePh: Double
    var iris: [String]
    var irisR: [String]?
    var lidTint: String?
    var liner: String
    var ink: String
    var mouthLine: String
    var whisk: String
    var padDot: String
    var whisk2: Whisk
    var eye: Eye
    var pupil0: Double
    var blushAt: [Double]
    var paw: String
    var bean: String
    var hair: String
    var hairDark: String
    var hairLight: String
    var kitten: Bool?
    /// A kitten's parent: the cat ID its personality and motion settings come from.
    var base: String?
}

enum CatPresets {
    typealias Ruff = CatPreset.Ruff
    typealias FurOpts = CatPreset.FurOpts
    typealias Ear = CatPreset.Ear
    typealias Eye = CatPreset.Eye
    typealias Whisk = CatPreset.Whisk
    typealias Patch = CatPreset.Patch

    /// The frozen cat IDs, Shrimpy first and Momo second.
    static let ids = ["shrimpy", "momo", "ginger", "midnight", "latte", "patches", "blue", "snow", "oreo", "mocha", "silver", "cloud", "leo", "button", "puff", "noodle"]

    /// Every coat by ID.
    static let all: [String: CatPreset] = [
        "shrimpy": shrimpy, "momo": momo, "ginger": ginger, "midnight": midnight, "latte": latte, "patches": patches,
        "blue": blue, "snow": snow, "oreo": oreo, "mocha": mocha, "silver": silver, "cloud": cloud, "leo": leo,
        "button": button, "puff": puff, "noodle": noodle,
    ]

    /// A stored cat ID to its preset. An unknown ID (or none) falls back to Shrimpy.
    static func byID(_ id: String?) -> CatPreset {
        guard let id, let p = all[id] else { return shrimpy }
        return p
    }

    /// Kittens keep the parent's coat; rounder head, bigger eyes and ears, shorter muzzle.
    static func kitten(of p: CatPreset) -> CatPreset {
        var k = p
        k.kitten = true; k.base = p.name; k.label = p.label + " kitten"; k.voice = 3
        k.rx = p.rx * 0.97; k.ry = p.ry * 1.02; k.n = 2.05
        k.ear.h *= 1.12; k.ear.bw *= 1.06; k.ear.tuft = 0
        k.eye.w *= 1.2; k.eye.h *= 1.32; k.eye.round = 1; k.eye.th += 0.02
        k.pupil0 = max(p.pupil0, 0.18)
        k.nosePh = p.nosePh + 0.08; k.noseW *= 0.85; k.noseH *= 0.85
        k.whisk2.len *= 0.7; k.whisk2.brow = 1
        if var r = k.ruff { r.rx *= 0.94; r.ry *= 0.92; k.ruff = r }
        return k
    }

    /// The shorthair template for the extra coats; each cat only overrides what differs.
    private static func coat(_ name: String, _ label: String, _ desc: String, _ change: (inout CatPreset) -> Void) -> CatPreset {
        var p = template
        p.name = name; p.label = label; p.desc = desc
        change(&p)
        return p
    }

    private static let template = CatPreset(
        name: "", label: "", voice: 0, coat: "solid", rx: 1.12, ry: 0.9, n: 2.2, fluff: 0,
        earSpread: 0.8, ear: Ear(h: 0.8, bw: 0.5, rot: 0.46, tip: 0.09, tuft: 0, cx: 0.7),
        top: "", bot: "", inner: "", nose: "", noseLine: "", noseW: 0.2, noseH: 0.13, nosePh: -0.42, iris: ["", ""],
        liner: "", ink: "", mouthLine: "", whisk: "", padDot: "",
        whisk2: Whisk(rows: 3, cols: 2, x0: 0.16, dx: 0.065, y0: -0.01, dy: 0.06, slope: 0.02, dot: 0.014, wcols: [0, 1], a0: -0.1, da: 0.2, len: 1.32, dl: 0.1, droop: 0.1, w: 0.021, alpha: 0.95, brow: 2),
        eye: Eye(th: 0.43, ph: -0.02, w: 0.19, h: 0.17, round: 1), pupil0: 0.2, blushAt: [0.55, 0.25],
        paw: "", bean: "", hair: "", hairDark: "", hairLight: "")

    // MARK: - Shrimpy and Momo (full values)

    static let shrimpy = CatPreset(
        name: "shrimpy",
        label: "Shrimpy",
        voice: -1,
        coat: "tabby",
        rx: 1.16,
        ry: 0.92,
        n: 2.2,
        fluff: 1.0,
        ruff: Ruff(rx: 1.3, ry: 0.97, dy: 0.2, col: ["#B49C7A", "#7E6750"]),
        bib: "#F3EEE6",
        furOpts: FurOpts(n: 420, l0: 0.04, l1: 0.05, w: 0.01, dark: "rgba(60,46,36,.28)", light: "rgba(214,190,150,.32)"),
        earSpread: 0.8,
        ear: Ear(h: 0.8, bw: 0.4, rot: 0.44, tip: 0.1, tuft: 1.0),
        top: "#A08A70",
        bot: "#6E5B49",
        light: "#D9B68A",
        chinCol: "#E6D0AD",
        stripe: "#2E241D",
        inner: "#DCC39A",
        nose: "#C07A62",
        noseLine: "#5E3526",
        noseW: 0.19,
        noseH: 0.12,
        nosePh: -0.36,
        iris: ["#C9D18A", "#6F8445"],
        liner: "#231A14",
        ink: "#231A14",
        mouthLine: "#5E3526",
        whisk: "#F7F3EC",
        padDot: "#2E241D",
        whisk2: Whisk(rows: 3, cols: 3, x0: 0.14, dx: 0.065, y0: -0.01, dy: 0.065, slope: 0.022, dot: 0.017, wcols: [1, 2], a0: -0.14, da: 0.2, len: 1.45, dl: 0.12, droop: 0.12, w: 0.022, alpha: 0.95, brow: 3),
        eye: Eye(th: 0.42, ph: -0.02, w: 0.21, h: 0.16, round: 0.0),
        pupil0: 0.08,
        blushAt: [0.6, 0.22],
        paw: "#B89C78",
        bean: "#6B3B2C",
        hair: "#9A8064",
        hairDark: "#5A4634",
        hairLight: "#D2B791")

    static let momo = CatPreset(
        name: "momo",
        label: "Momo",
        voice: 1,
        coat: "tuxedo",
        rx: 1.12,
        ry: 0.9,
        n: 2.2,
        fluff: 0.0,
        furOpts: FurOpts(n: 700, l0: 0.025, l1: 0.03, w: 0.008, dark: "rgba(24,24,27,.45)", light: "rgba(112,114,122,.42)", wDark: "rgba(196,190,184,.55)", wLight: "rgba(255,255,255,.5)"),
        earSpread: 0.8,
        ear: Ear(h: 0.8, bw: 0.56, rot: 0.5, tip: 0.09, tuft: 0.0, cx: 0.62),
        top: "#3D3D41",
        bot: "#3D3D41",
        rimLight: 1,
        white: "#F6F4F1",
        inner: "#B98288",
        nose: "#E89AA6",
        noseLine: "#B86F7C",
        noseW: 0.25,
        noseH: 0.15,
        nosePh: -0.48,
        iris: ["#7E8A45", "#D1B85F"],
        lidTint: "#D9BE62",
        liner: "#16171A",
        ink: "#E4D592",
        mouthLine: "#9A8C88",
        whisk: "#F6F4F1",
        padDot: "rgba(150,142,138,.6)",
        whisk2: Whisk(rows: 3, cols: 2, x0: 0.17, dx: 0.065, y0: -0.01, dy: 0.06, slope: 0.02, dot: 0.014, wcols: [0, 1], a0: -0.1, da: 0.2, len: 1.32, dl: 0.1, droop: 0.1, w: 0.021, alpha: 0.95, brow: 2),
        eye: Eye(th: 0.43, ph: -0.02, w: 0.19, h: 0.17, round: 1.0),
        pupil0: 0.235,
        blushAt: [0.5, 0.32],
        paw: "#F6F4F1",
        bean: "#E89AA6",
        hair: "#56575E",
        hairDark: "#2E2F33",
        hairLight: "#9A9BA2")

    // MARK: - The fourteen extra coats (the shorthair template with overrides)

    static let ginger = coat("ginger", "Ginger", "orange tabby") {
        $0.coat = "tabby"
        $0.top = "#E39B52"
        $0.bot = "#C46F2E"
        $0.light = "#F7DDB8"
        $0.chinCol = "#FCEFDD"
        $0.stripe = "#A9541C"
        $0.inner = "#F2B8A8"
        $0.nose = "#E88E80"
        $0.noseLine = "#A85A4E"
        $0.iris = ["#E9D27A", "#C99A2E"]
        $0.liner = "#3A2416"
        $0.ink = "#3A2416"
        $0.mouthLine = "#A0624A"
        $0.whisk = "#FFF6EA"
        $0.padDot = "#B7682F"
        $0.eye.w = 0.2
        $0.eye.h = 0.16
        $0.eye.round = 0.0
        $0.pupil0 = 0.1
        $0.blushAt = [0.58, 0.22]
        $0.paw = "#F3C894"
        $0.bean = "#E88E80"
        $0.hair = "#D98B45"
        $0.hairDark = "#9C5524"
        $0.hairLight = "#F6CF9E"
    }

    static let midnight = coat("midnight", "Midnight", "black shorthair") {
        $0.top = "#2C2C31"
        $0.bot = "#1F1F23"
        $0.rimLight = 1
        $0.inner = "#6E5A5E"
        $0.nose = "#56474D"
        $0.noseLine = "#2A2024"
        $0.iris = ["#F7D45C", "#D9921C"]
        $0.liner = "#0E0E10"
        $0.ink = "#F2D06A"
        $0.mouthLine = "#77696E"
        $0.whisk = "#D8D8DD"
        $0.padDot = "rgba(140,140,150,.5)"
        $0.eye.w = 0.2
        $0.eye.h = 0.18
        $0.paw = "#2E2E33"
        $0.bean = "#56474D"
        $0.hair = "#38383E"
        $0.hairDark = "#1A1A1D"
        $0.hairLight = "#6A6A72"
    }

    static let latte = coat("latte", "Latte", "Siamese seal point") {
        $0.coat = "point"
        $0.rx = 1.04
        $0.ry = 0.92
        $0.n = 2.0
        $0.top = "#F1E6D4"
        $0.bot = "#DCCBB2"
        $0.point = "#4A3528"
        $0.earCols = ["#4A3528", "#4A3528"]
        $0.ear.h = 0.95
        $0.ear.bw = 0.55
        $0.ear.rot = 0.5
        $0.ear.tip = 0.08
        $0.inner = "#7A5A4E"
        $0.nose = "#3E2C24"
        $0.noseLine = "#2A1C16"
        $0.iris = ["#B9E3FA", "#3F86CF"]
        $0.liner = "#2A1C16"
        $0.ink = "#CFE6F5"
        $0.mouthLine = "#8A7266"
        $0.whisk = "#F5EFE6"
        $0.padDot = "rgba(30,20,15,.5)"
        $0.eye.w = 0.21
        $0.eye.h = 0.15
        $0.eye.round = 0.0
        $0.pupil0 = 0.1
        $0.paw = "#4A3528"
        $0.bean = "#7A5A50"
        $0.hair = "#D8C6AC"
        $0.hairDark = "#8A7058"
        $0.hairLight = "#F4EADA"
    }

    static let patches = coat("patches", "Patches", "calico") {
        $0.coat = "calico"
        $0.top = "#F7F3EE"
        $0.bot = "#E6DFD6"
        $0.earCols = ["#E3994E", "#2C2B2F"]
        $0.patches = [
            Patch(-0.48, -0.36, 0.5, 0.4, 0.3, "#E3994E", 1),
            Patch(0.52, -0.56, 0.55, 0.36, -0.4, "#2C2B2F", 2),
            Patch(0.66, 0.3, 0.22, 0.15, 0.2, "#E3994E", 3),
            Patch(-0.78, 0.36, 0.16, 0.12, -0.3, "#2C2B2F", 4)
        ]
        $0.inner = "#F2B6B8"
        $0.nose = "#F0A0AE"
        $0.noseLine = "#C07884"
        $0.iris = ["#C9DA7A", "#6F9A3A"]
        $0.liner = "#2A2420"
        $0.ink = "#2A2420"
        $0.mouthLine = "#B09A94"
        $0.whisk = "#CFC8C0"
        $0.padDot = "rgba(170,150,140,.55)"
        $0.paw = "#F7F3EE"
        $0.bean = "#F0A0AE"
        $0.hair = "#D9B48C"
        $0.hairDark = "#8A6A4A"
        $0.hairLight = "#F4E6D4"
    }

    static let blue = coat("blue", "Blue", "British shorthair") {
        $0.rx = 1.22
        $0.ry = 0.92
        $0.n = 2.5
        $0.top = "#9AA4B2"
        $0.bot = "#7A8494"
        $0.muzzle = "#A9B2BF"
        $0.ear.h = 0.62
        $0.ear.bw = 0.5
        $0.ear.rot = 0.55
        $0.ear.tip = 0.12
        $0.ear.cx = 0.8
        $0.inner = "#B8A0A8"
        $0.nose = "#6E6C7A"
        $0.noseLine = "#4C4A56"
        $0.noseW = 0.17
        $0.nosePh = -0.4
        $0.iris = ["#F6B44A", "#D2741E"]
        $0.liner = "#2E3038"
        $0.ink = "#2E3038"
        $0.mouthLine = "#5A5C68"
        $0.whisk = "#EEF0F4"
        $0.padDot = "rgba(70,76,90,.45)"
        $0.eye.w = 0.21
        $0.eye.h = 0.19
        $0.pupil0 = 0.22
        $0.paw = "#9AA4B2"
        $0.bean = "#6E6C7A"
        $0.hair = "#8E98A6"
        $0.hairDark = "#5E6878"
        $0.hairLight = "#C2CAD4"
    }

    static let snow = coat("snow", "Snow", "white longhair, odd-eyed") {
        $0.fluff = 1.0
        $0.ruff = Ruff(rx: 1.24, ry: 0.92, dy: 0.16, col: ["#F2EFEA", "#D9D3CA"])
        $0.bib = "#FFFFFF"
        $0.top = "#F5F3EF"
        $0.bot = "#E2DED7"
        $0.ear.h = 0.82
        $0.ear.bw = 0.48
        $0.ear.tuft = 1.0
        $0.inner = "#F4B8BE"
        $0.nose = "#F2A6B0"
        $0.noseLine = "#C9808C"
        $0.iris = ["#BCE4FA", "#4A90D6"]
        $0.irisR = ["#F4DC7A", "#D49A2A"]
        $0.liner = "#3A3433"
        $0.ink = "#3A3433"
        $0.mouthLine = "#C0B4B0"
        $0.whisk = "#D8D2CC"
        $0.padDot = "rgba(180,165,160,.55)"
        $0.paw = "#F5F3EF"
        $0.bean = "#F2A6B0"
        $0.hair = "#EDE8E0"
        $0.hairDark = "#B8B0A6"
        $0.hairLight = "#FFFFFF"
    }

    static let oreo = coat("oreo", "Oreo", "black-and-white tuxedo") {
        $0.coat = "tuxedo"
        $0.top = "#1C1C1F"
        $0.bot = "#131315"
        $0.rimLight = 1
        $0.white = "#F6F4F1"
        $0.furOpts = FurOpts(n: 700, l0: 0.025, l1: 0.03, w: 0.008, dark: "rgba(0,0,0,.5)", light: "rgba(96,98,108,.42)", wDark: "rgba(196,190,184,.55)", wLight: "rgba(255,255,255,.5)")
        $0.ear.h = 0.86
        $0.ear.bw = 0.54
        $0.ear.rot = 0.46
        $0.ear.tip = 0.08
        $0.ear.cx = 0.66
        $0.inner = "#8A646C"
        $0.nose = "#F2A4B2"
        $0.noseLine = "#C27886"
        $0.noseW = 0.22
        $0.noseH = 0.14
        $0.nosePh = -0.46
        $0.iris = ["#7FA82A", "#DDEB5A"]
        $0.liner = "#0B0B0D"
        $0.ink = "#D8EE5E"
        $0.mouthLine = "#A39A98"
        $0.whisk = "#FFFFFF"
        $0.padDot = "rgba(150,142,138,.6)"
        $0.whisk2.x0 = 0.17
        $0.whisk2.len = 1.4
        $0.eye.w = 0.2
        $0.eye.h = 0.18
        $0.pupil0 = 0.22
        $0.paw = "#F6F4F1"
        $0.bean = "#F2A4B2"
        $0.hair = "#2A2A2E"
        $0.hairDark = "#101012"
        $0.hairLight = "#F2F0EC"
    }

    static let mocha = coat("mocha", "Mocha", "tortoiseshell") {
        $0.coat = "calico"
        $0.top = "#30241F"
        $0.bot = "#1F1713"
        $0.rimLight = 1
        $0.earCols = ["#C9772F", "#30241F"]
        $0.patches = [
            Patch(-0.52, -0.5, 0.17, 0.11, 0.6, "#C9772F", 1),
            Patch(-0.4, -0.62, 0.07, 0.05, 0.2, "#E2A866", 2),
            Patch(0.06, -0.62, 0.06, 0.2, 0.1, "#C9772F", 3),
            Patch(0.56, -0.3, 0.15, 0.09, -0.5, "#C9772F", 4),
            Patch(0.84, 0.12, 0.11, 0.08, 0.4, "#E2A866", 5),
            Patch(-0.82, 0.16, 0.14, 0.1, -0.5, "#C9772F", 6),
            Patch(-0.32, 0.6, 0.13, 0.07, 0.25, "#E2A866", 7),
            Patch(0.4, 0.58, 0.11, 0.07, -0.3, "#C9772F", 8),
            Patch(0.36, -0.74, 0.09, 0.05, 0.3, "#E2A866", 9),
            Patch(-0.66, 0.42, 0.07, 0.05, 0.0, "#E2A866", 10)
        ]
        $0.inner = "#7A5A54"
        $0.nose = "#6E4A42"
        $0.noseLine = "#3A2420"
        $0.iris = ["#F6C44C", "#C2761A"]
        $0.liner = "#120C0A"
        $0.ink = "#F2C45C"
        $0.mouthLine = "#8A6E64"
        $0.whisk = "#EADFD0"
        $0.padDot = "rgba(150,120,100,.5)"
        $0.eye.w = 0.2
        $0.eye.h = 0.17
        $0.paw = "#6A4630"
        $0.bean = "#2A1C18"
        $0.hair = "#6A4A34"
        $0.hairDark = "#2A1F1A"
        $0.hairLight = "#D89A58"
    }

    static let silver = coat("silver", "Silver", "silver tabby") {
        $0.coat = "tabby"
        $0.top = "#D6DADF"
        $0.bot = "#A8AEB6"
        $0.light = "#EEF0F2"
        $0.chinCol = "#FFFFFF"
        $0.stripe = "#1D1F23"
        $0.inner = "#E6BDB8"
        $0.nose = "#C2655C"
        $0.noseLine = "#7C3832"
        $0.iris = ["#CBE27A", "#4C983C"]
        $0.liner = "#16171A"
        $0.ink = "#1D1F23"
        $0.mouthLine = "#6E6A6C"
        $0.whisk = "#FFFFFF"
        $0.padDot = "#2A2C30"
        $0.eye.w = 0.2
        $0.eye.h = 0.16
        $0.eye.round = 0.0
        $0.pupil0 = 0.1
        $0.blushAt = [0.58, 0.22]
        $0.paw = "#D6DADF"
        $0.bean = "#C2655C"
        $0.hair = "#BCC1C8"
        $0.hairDark = "#3A3C42"
        $0.hairLight = "#F2F4F6"
    }

    static let cloud = coat("cloud", "Cloud", "Ragdoll") {
        $0.coat = "point"
        $0.fluff = 1.0
        $0.ruff = Ruff(rx: 1.3, ry: 0.98, dy: 0.2, col: ["#F7F2E9", "#DED4C4"])
        $0.bib = "#FFFFFF"
        $0.rx = 1.14
        $0.ry = 0.92
        $0.n = 2.3
        $0.top = "#F4EFE6"
        $0.bot = "#DCD3C6"
        $0.point = "#7D8796"
        $0.earCols = ["#7D8796", "#7D8796"]
        $0.muzzle = "#FBF9F6"
        $0.ear.h = 0.84
        $0.ear.bw = 0.5
        $0.ear.tuft = 1.0
        $0.inner = "#C4A8AE"
        $0.nose = "#D49AA4"
        $0.noseLine = "#A0707A"
        $0.iris = ["#6FA8F2", "#2C64D6"]
        $0.liner = "#232A36"
        $0.ink = "#8FC0F8"
        $0.mouthLine = "#A89CA0"
        $0.whisk = "#FFFFFF"
        $0.padDot = "rgba(110,116,130,.45)"
        $0.eye.w = 0.22
        $0.eye.h = 0.2
        $0.pupil0 = 0.22
        $0.paw = "#FFFFFF"
        $0.bean = "#D49AA4"
        $0.hair = "#E8E2D8"
        $0.hairDark = "#8A92A0"
        $0.hairLight = "#FFFFFF"
    }

    static let leo = coat("leo", "Leo", "Bengal") {
        $0.coat = "calico"
        $0.top = "#D9A050"
        $0.bot = "#B97A30"
        $0.muzzle = "#F4E2C0"
        $0.ear.h = 0.74
        $0.ear.bw = 0.5
        $0.ear.rot = 0.5
        $0.ear.tip = 0.1
        $0.ear.cx = 0.75
        $0.patches = [
            Patch(-0.1, -0.6, 0.024, 0.17, 0.14, "#3E2412", 11),
            Patch(0.1, -0.6, 0.024, 0.17, -0.14, "#3E2412", 12),
            Patch(0.0, -0.7, 0.022, 0.12, 0.0, "#3E2412", 13),
            Patch(-0.84, 0.1, 0.15, 0.022, -0.3, "#3E2412", 14),
            Patch(0.84, 0.1, 0.15, 0.022, 0.3, "#3E2412", 15),
            Patch(-0.6, -0.42, 0.12, 0.095, 0.4, "#4A2A14", 1),
            Patch(-0.6, -0.42, 0.06, 0.045, 0.4, "#9C5E24", 1),
            Patch(0.62, -0.4, 0.12, 0.095, -0.3, "#4A2A14", 2),
            Patch(0.62, -0.4, 0.06, 0.045, -0.3, "#9C5E24", 2),
            Patch(-0.34, -0.76, 0.12, 0.095, 0.2, "#4A2A14", 3),
            Patch(-0.34, -0.76, 0.06, 0.045, 0.2, "#9C5E24", 3),
            Patch(0.36, -0.76, 0.12, 0.095, -0.2, "#4A2A14", 4),
            Patch(0.36, -0.76, 0.06, 0.045, -0.2, "#9C5E24", 4),
            Patch(-0.84, 0.36, 0.12, 0.095, 0.3, "#4A2A14", 5),
            Patch(-0.84, 0.36, 0.06, 0.045, 0.3, "#9C5E24", 5),
            Patch(0.86, 0.36, 0.12, 0.095, -0.3, "#4A2A14", 6),
            Patch(0.86, 0.36, 0.06, 0.045, -0.3, "#9C5E24", 6),
            Patch(-0.55, 0.6, 0.12, 0.095, 0.2, "#4A2A14", 7),
            Patch(-0.55, 0.6, 0.06, 0.045, 0.2, "#9C5E24", 7),
            Patch(0.57, 0.6, 0.12, 0.095, -0.2, "#4A2A14", 8),
            Patch(0.57, 0.6, 0.06, 0.045, -0.2, "#9C5E24", 8)
        ]
        $0.inner = "#E2B49A"
        $0.nose = "#C66E58"
        $0.noseLine = "#7A3A28"
        $0.iris = ["#DADC62", "#6C9A32"]
        $0.liner = "#24160C"
        $0.ink = "#24160C"
        $0.mouthLine = "#7A5034"
        $0.whisk = "#FFF6E6"
        $0.padDot = "#3A2412"
        $0.eye.w = 0.2
        $0.eye.h = 0.15
        $0.eye.round = 0.0
        $0.pupil0 = 0.1
        $0.blushAt = [0.58, 0.24]
        $0.paw = "#E2B470"
        $0.bean = "#4A2C18"
        $0.hair = "#D09048"
        $0.hairDark = "#4A2C16"
        $0.hairLight = "#F2D29A"
    }

    static let button = coat("button", "Button", "Scottish Fold") {
        $0.rx = 1.2
        $0.ry = 0.94
        $0.n = 2.5
        $0.top = "#BCA9B3"
        $0.bot = "#988592"
        $0.ear.h = 0.58
        $0.ear.bw = 0.46
        $0.ear.rot = 0.62
        $0.ear.tip = 0.2
        $0.ear.cx = 0.9
        $0.ear.fold = 1.0
        $0.inner = "#C9A4AC"
        $0.nose = "#B88A96"
        $0.noseLine = "#7E5A66"
        $0.noseW = 0.17
        $0.iris = ["#F8A642", "#C2561A"]
        $0.liner = "#2E2630"
        $0.ink = "#2E2630"
        $0.mouthLine = "#6E6068"
        $0.whisk = "#F4EEF0"
        $0.padDot = "rgba(90,70,80,.4)"
        $0.eye.w = 0.22
        $0.eye.h = 0.21
        $0.pupil0 = 0.24
        $0.paw = "#BCA9B3"
        $0.bean = "#B88A96"
        $0.hair = "#ADA0A6"
        $0.hairDark = "#7A6C74"
        $0.hairLight = "#D8CED2"
    }

    static let puff = coat("puff", "Puff", "Persian") {
        $0.fluff = 1.0
        $0.ruff = Ruff(rx: 1.46, ry: 1.08, dy: 0.2, col: ["#F3E4C8", "#D8C09A"])
        $0.bib = "#FFFFFF"
        $0.rx = 1.24
        $0.ry = 0.94
        $0.n = 2.6
        $0.top = "#EED8B4"
        $0.bot = "#D4B488"
        $0.earSpread = 0.86
        $0.ear.h = 0.5
        $0.ear.bw = 0.42
        $0.ear.rot = 0.62
        $0.ear.tip = 0.12
        $0.ear.cx = 0.8
        $0.ear.tuft = 1.0
        $0.nosePh = -0.3
        $0.noseW = 0.15
        $0.noseH = 0.1
        $0.inner = "#F0B8B0"
        $0.nose = "#E89A94"
        $0.noseLine = "#B06A64"
        $0.iris = ["#F8B04A", "#C8601A"]
        $0.liner = "#3A2A20"
        $0.ink = "#3A2A20"
        $0.mouthLine = "#A88A78"
        $0.whisk = "#FFF8EE"
        $0.padDot = "rgba(170,140,110,.5)"
        $0.whisk2.len = 1.2
        $0.eye.th = 0.45
        $0.eye.w = 0.22
        $0.eye.h = 0.21
        $0.pupil0 = 0.24
        $0.paw = "#F3E4C8"
        $0.bean = "#E89A94"
        $0.hair = "#EAD6B4"
        $0.hairDark = "#B89A70"
        $0.hairLight = "#FFF6E6"
    }

    static let noodle = coat("noodle", "Noodle", "Sphynx") {
        $0.hairless = 1
        $0.wrinkles = 1
        $0.rx = 1.04
        $0.ry = 0.94
        $0.n = 2.0
        $0.top = "#E8C1AE"
        $0.bot = "#CF9F8C"
        $0.earSpread = 0.86
        $0.ear.h = 1.1
        $0.ear.bw = 0.62
        $0.ear.rot = 0.58
        $0.ear.tip = 0.1
        $0.ear.cx = 0.75
        $0.inner = "#EBA898"
        $0.nose = "#D88A7C"
        $0.noseLine = "#A45E50"
        $0.iris = ["#F6F07A", "#C9C42E"]
        $0.liner = "#3A2620"
        $0.ink = "#3A2620"
        $0.mouthLine = "#A87464"
        $0.whisk = "#F4E2D8"
        $0.padDot = "rgba(170,110,95,.4)"
        $0.whisk2.wcols = [1]
        $0.whisk2.len = 0.85
        $0.whisk2.alpha = 0.5
        $0.whisk2.brow = 1
        $0.eye.w = 0.21
        $0.eye.h = 0.15
        $0.eye.round = 0.0
        $0.pupil0 = 0.1
        $0.paw = "#E8C1AE"
        $0.bean = "#D88A7C"
        $0.hair = "#E0B6A2"
        $0.hairDark = "#A87A66"
        $0.hairLight = "#F6DED2"
    }
}
