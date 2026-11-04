import Foundation

// What the renderer draws: the eye shapes, the badge, the particles and hairballs, the paws, and `CatLook`, the one value that holds
// everything it needs to draw a cat. The engine fills them in; the renderer only reads them. They hold no logic.

/// An eye shape. The first four are drawn as the realistic almond eye at full detail; the rest are the expression eyes in the cat's ink colour.
enum CatEye: String, CaseIterable, Sendable {
    case pill, wide, dot, line, flat, happy, closed, spiral, heart, star, tired, wink

    /// Shapes drawn as the realistic almond eye (with iris and pupil) at full detail.
    var isRealistic: Bool { self == .pill || self == .wide || self == .dot || self == .tired }
}

/// The small badge beside the ear.
enum CatBadge: String, Sendable { case dots, bang, question, dot }

enum CatParticleKind: String, Sendable { case heart, star, spark, sweat, dust, hair, z }

/// A particle, in units of R from the cat's resting centre, drawn at `x + vx * age`, `y + vy * age`. A negative age waits to start.
struct CatParticle {
    var kind: CatParticleKind
    var x: Double, y: Double, vx: Double, vy: Double, age: Double, life: Double, size: Double, rot: Double
}

/// A hairball, or a refused file wrapped in fur, in units of R from the cat's resting centre.
struct CatBall {
    var x: Double, y: Double, vx: Double, vy: Double, rot: Double, age: Double, life: Double
    var file: String?
    var seed: Int
    var floor: Double
}


/// Everything the renderer needs to draw one cat besides where and how big: the coat, the pose and what the engine decided about the face.
struct CatLook {
    var preset: CatPreset
    var pose = CatPose()
    var eye: CatEye = .pill
    /// How open the mouth is, 0 (closed) to 1.3 (the engine adds the state's mouth, its motion and the file-catch spring).
    var mouthOpen = 0.0
    /// Draws the compact detail level's resting eyes as the old flat ink shapes. Only the contact sheet that shows today's look beside the coloured
    /// small eyes sets it; every cat in the app has the coloured ones.
    var inkEyes = false
    /// The state colour, 0...255, for the tint on the lower head.
    var color: [Double] = [230, 233, 238]
    /// The resting blush a personality adds, on top of the pose's.
    var blushBase = 0.0
    /// Seconds, for the motion inside a shape (the spiral eyes, the star eyes, the wavy mouth).
    var time = 0.0
    /// The badge beside the ear, and its colour (a hex string; the state colour).
    var badge: CatBadge?
    var badgeColor = "#FFFFFF"
    /// The soft light behind the cat (0...255 colour and an alpha); drawn only when the options ask for a glow.
    var glowColor: [Double] = [255, 255, 255]
    var glowAlpha = 0.12
    var particles: [CatParticle] = []
    var balls: [CatBall] = []
    /// The cat's sideways speed in R per second, for the zoomies afterimages and speed lines.
    var zoomVelocity = 0.0
    /// Paws drawn behind the head by hand (the greeting); nil: the engine's wave, from `wave`.
    var paws: [CatPaw]?
    var wave: CatWave?
}

/// A paw in the head's frame, in px. `k` is how far it is out (0 hidden, 1 full size).
struct CatPaw { var x: Double, y: Double, k: Double, rot: Double, beans: Bool }

/// The paw wave of `CatEngine.greet`: the clock and the wave window, in ms, plus how far the paws are out (the pose's `paws`).
struct CatWave { var now: Double, start: Double, until: Double }

/// A collar to wear: its style ("tag", "band" or "kerchief"; "off" and anything else draws none), the agent's colour ("#RRGGBB"; the coat is never
/// recoloured) and the device pixel ratio, which the readability floors of the contract are in (a band 3 px thick, a tag 6 across, a neckerchief
/// 7 wide and 5 deep).
struct CatCollarPaint {
    var style: String
    var color: String
    var dpr = 2.0
}

/// An outfit to wear on this draw (sub-project I). `role` is who the cat is (`big`, `small` or `kitten`): only `big` wears it, at every size (`Wardrobe.worn`). `CatOutfitDraw.big` makes
/// the paint of a big cat. Plain values, so every file that draws a cat can take it without the wardrobe.
struct CatOutfitPaint {
    /// One of the 16 drawn IDs.
    var id: String
    var role = "small"
    /// Pixels per point, which the readability floors are in (as the collar's).
    var dpr = 2.0
    /// 0 to 1: how much of it shows (the launch greeting puts it on once the cat has settled).
    var fade = 1.0
    /// The y (in the drawing's coordinates, those of `CatDrawOptions.earCeiling`) of the top of the canvas this cat is drawn into, when that is tighter than the compact notch's strip: a
    /// hat or a pair of bunny ears is shortened to the room under it, never below the floor, as in the strip. It is the outfit's own: the ears are fitted by `earCeiling` alone. nil: the
    /// outfit uses `earCeiling`, as it always did.
    var ceiling: Double?
}

struct CatDrawOptions {
    /// The state tint on the lower head.
    var tint = true
    /// +1 puts the badge beside the right ear, -1 beside the left (the compact notch).
    var badgeSide = 1.0
    /// The x (in the drawing's coordinates) the badge may not reach left of: it is nudged right until its whole shape is inside. nil: no limit (every cat but cat 1 of the pair).
    var badgeLeftLimit: Double?
    /// The y of the top of the strip the cat lives in (the compact notch). The ears are fitted under it. nil: no limit.
    var earCeiling: Double?
    /// nil: full detail from a head width of Ø28. true or false forces it.
    var full: Bool?
    /// A soft light behind the cat. The island draws its own glow, so the app leaves this off; the contact sheets turn it on.
    var glow = false
    /// The badge, when the cat has one.
    var badge = true
    /// Optional fur strands (Settings → Cat → Fur lines), drawn on a full-detail cat from a head radius of 30 px (`CatFur.shows`). Flat colour is the default.
    var fur = false
    /// The collar, drawn in the front pass from Ø12 up. nil: none (the default).
    var collar: CatCollarPaint?
    /// The wardrobe (sub-project I): the outfit this cat wears, in the three slots of the passes. nil: bare, which every small cat and every kitten is (`Wardrobe.worn`): the role in the
    /// paint decides, never the diameter.
    var outfit: CatOutfitPaint?
}
