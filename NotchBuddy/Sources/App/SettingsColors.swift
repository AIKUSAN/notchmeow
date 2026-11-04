import AppKit

// The Settings help text's colour and the contrast check that holds it to 4.5:1 (the restyle spec's help text rule). The one AppKit file of the Settings rules: colours resolve
// through an appearance, so the check runs under each one. Tests: tests/SettingsContrastTests.swift (scripts/test-settings-contrast.sh).

enum SettingsColors {
    /// Help text: the label colour at 72 % alpha. A dynamic colour, so it resolves per appearance; a plain `withAlphaComponent` of the label colour is frozen to the
    /// appearance it was made in (the process's, usually dark), which read as 1:1 on a light window.
    static let help = NSColor(name: "settings.help", dynamicProvider: { _ in NSColor.labelColor.withAlphaComponent(0.72) })

    /// The WCAG ratio of `fg` (its alpha blended over `bg`) against `bg`, both resolved in `appearance`.
    static func contrast(_ fg: NSColor, over bg: NSColor, appearance: NSAppearance.Name) -> Double {
        var f = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), a: CGFloat(1))
        var b = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), a: CGFloat(1))
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            let fc = fg.usingColorSpace(.sRGB) ?? fg
            let bc = bg.usingColorSpace(.sRGB) ?? bg
            fc.getRed(&f.r, green: &f.g, blue: &f.b, alpha: &f.a)
            bc.getRed(&b.r, green: &b.g, blue: &b.b, alpha: &b.a)
        }
        let a = Double(f.a)
        let br = Double(b.r), bgG = Double(b.g), bb = Double(b.b)
        let blended = (r: Double(f.r) * a + br * (1 - a), g: Double(f.g) * a + bgG * (1 - a), b: Double(f.b) * a + bb * (1 - a))
        let lf = luminance(blended.r, blended.g, blended.b)
        let lb = luminance(br, bgG, bb)
        return (max(lf, lb) + 0.05) / (min(lf, lb) + 0.05)
    }

    /// WCAG relative luminance of an sRGB colour.
    private static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
