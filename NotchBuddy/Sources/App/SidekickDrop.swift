import Foundation

// Drop a file on an agent's own cat: the pure rules. Only a cat that stands for ONE agent and is not the big cat is a target: in "A cat for each agent" mode an agent's cat in the compact
// island's grid, and in "Two cats" mode cat 2. The big cat's drop is not touched here (it stays the chat or Ask drop, and after sub-project G1 the Ask and Shelf halves), and nothing here
// opens a file or sends anything to another app: a drop on an agent's cat copies the file's ORIGINAL path to the clipboard and brings that agent's terminal or editor forward, and the line
// says exactly that. The hit test runs before every other drop rule and only for an agent that has a live session in the ledger; anywhere else the drop is what it always was. Foundation only.

enum SidekickDrop {
    /// A circle a drop can land in, in the island panel's own coordinates (points, x from the panel's left, y down from its top), for the agent it stands for.
    struct Cat: Equatable, Sendable {
        var pill: String
        var x: Double
        var y: Double
        var r: Double
    }

    /// The cats of the compact island's 2x2 grid (`CompactMiniGrid`): cells 16 pt between centres, the grid's centre 40 pt in from the island's right edge and half the strip's height down, all
    /// shrunk like `IslandRestingLayout.miniGridScale` on a strip shorter than 32 pt. `pills` is the grid's pills in the grid's order (top left, top right, bottom left, bottom right; at most four),
    /// each with whether it wears its own agent's coat (A cat for each agent mode): only those are targets. `panelWidth` is the island panel's width and `islandWidth` the compact island's.
    static func gridCats(pills: [(pill: String, agent: Bool)], panelWidth: Double, islandWidth: Double, islandHeight: Double) -> [Cat] {
        let k = min(1, max(0, islandHeight - 4) / 28), left = (panelWidth - islandWidth) / 2
        let gx = left + islandWidth - 40, gy = islandHeight / 2, s = 8 * k
        return pills.prefix(4).enumerated().compactMap { i, p in
            p.agent ? Cat(pill: p.pill, x: gx + (i % 2 == 1 ? s : -s), y: gy + (i < 2 ? -s : s), r: s) : nil
        }
    }

    /// The agent whose cat is under the point, and only when that agent has a live session. The nearest centre wins, a tie goes to the first. nil: the drop is what it always was.
    static func agentCatAt(x: Double, y: Double, cats: [Cat], live: Set<String>) -> String? {
        var best: (pill: String, d: Double)?
        for c in cats where live.contains(c.pill) {
            let d = (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y)
            if d <= c.r * c.r, best == nil || d < best!.d { best = (c.pill, d) }
        }
        return best?.pill
    }

    /// A scalar no path may hold, by Unicode property and not by a list of ranges (a list misses some: tag characters, variation selectors, U+00AD, U+034F, U+3164 and more): a control, a format
    /// character (bidi controls, zero-width, joiners), a line or paragraph separator, or any default-ignorable code point (invisible: it shows a name other than the one a shell reads). Also a
    /// backslash and a `!`: fish reads a backslash inside single quotes, csh and tcsh expand a `!` even there, so no quoting is enough for them. This refuses names with an emoji variation selector
    /// (U+FE0F) or a joiner (U+200D) too: such a file takes the chat drop instead, which sends nothing through a shell.
    private static func isRefused(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator: return true
        default: return s.properties.isDefaultIgnorableCodePoint || s == "\\" || s == "!"
        }
    }

    /// A scalar a POSIX shell reads as itself in a path that starts with `/` (that is what `shellSafe` requires; a leading `=`, `%` or `-` would not be plain): ASCII letters and digits and `_ . / + @ % , : = -`, or a non-ASCII letter, number or mark (L*, N*, M*).
    private static let safeASCII = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./+@%,:=-".unicodeScalars)
    private static func isPlain(_ s: Unicode.Scalar) -> Bool {
        if s.isASCII { return safeASCII.contains(s) }
        switch s.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber, .letterNumber, .otherNumber, .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    /// One path as the clipboard gets it: as it is when it starts with `/` (a file URL's path always does) and holds only plain scalars, else in POSIX single quotes, which sh, bash and zsh expand
    /// nothing inside, with each `'` written `'\''` (the quote closes, an escaped quote, it reopens). Built scalar by scalar: a Foundation search for `'` is not literal, it skips a quote that a
    /// combining mark follows (the raw quote then closes the quoting) and can reorder combining marks, so `replacingOccurrences` is never used here.
    private static func shellSafe(_ path: String) -> String {
        let u = path.unicodeScalars
        if u.first == "/" && u.allSatisfy(isPlain) { return path }
        var q = String.UnicodeScalarView()
        q.append("'")
        for c in u {
            if c == "'" { for e in "'\\''".unicodeScalars { q.append(e) } } else { q.append(c) }
        }
        q.append("'")
        return String(q)
    }

    /// What goes on the clipboard: one path is its path (see `shellSafe`: as it is when its name is plain, otherwise POSIX single-quoted). Several paths are ONE line, space-separated, each handled
    /// on its own by the same rule (no line break anywhere in the text; a plain name has no space and a name with a space is quoted, so the words come back as
    /// separate arguments in a POSIX shell). nil, nothing copied, when any path holds a refused scalar (`isRefused`): one refused name refuses the whole drop. The text never has a line break; pasted
    /// bare into a shell and followed by Enter it would still run a file that is executable, which is why it is meant for an agent's prompt and the line the island shows says to paste it there.
    static func clipboardText(paths: [String]) -> String? {
        guard !paths.isEmpty, !paths.contains(where: { $0.unicodeScalars.contains(where: isRefused) }) else { return nil }
        return paths.map(shellSafe).joined(separator: " ")
    }

    /// The one line the island shows. It never says sent, delivered or attached: NotchMeow has no channel into a running agent.
    static func line(agentName: String, count: Int) -> String {
        count == 1 ? "Copied the path \u{2014} paste it into \(agentName)" : "Copied \(count) paths \u{2014} paste them into \(agentName)"
    }

    /// The line when a path could not be copied (a line break, a control or invisible character, a backslash or a `!`).
    static func refusedLine() -> String { "Not copied: that file\u{2019}s name has a character a terminal would act on. Drop it on the chat instead." }
}
