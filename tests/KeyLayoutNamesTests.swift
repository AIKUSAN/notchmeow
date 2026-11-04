import AppKit
import Carbon.HIToolbox

/// `KeyLayoutNames` against real keyboard layouts, which macOS ships whether or not they are enabled. Needs a
/// logged-in macOS session (the Text Input Sources service).
@main
enum KeyLayoutNamesTests {
    nonisolated(unsafe) static var cases = 0
    nonisolated(unsafe) static var skipped: [String] = []

    static func check(_ ok: Bool, _ message: @autoclosure () -> String,
                      file: StaticString = #file, line: UInt = #line) {
        cases += 1
        precondition(ok, message(), file: file, line: line)
    }

    /// Keys of `layout` and the character each should print.
    @MainActor static func expect(_ id: String, _ keys: [UInt16: String?]) {
        guard let source = KeyLayoutNames.layout(id: id) else { skipped.append(id); return }
        for (code, expected) in keys.sorted(by: { $0.key < $1.key }) {
            let got = KeyLayoutNames.name(for: code, in: source)
            check(got == expected, "\(id): key code \(code) should print \(expected ?? "nothing"), got \(got ?? "nothing")")
        }
    }

    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        // US: the names ShortcutLogic.keyCodeToString uses.
        expect("com.apple.keylayout.US", [0: "A", 12: "Q", 13: "W", 6: "Z", 16: "Y", 30: "]", 33: "[", 45: "N", 46: "M",
                                          18: "1", 29: "0", 43: ",", 49: nil, 36: nil, 123: nil, 53: nil, 122: nil])
        // French AZERTY: the key at the US A position is labelled Q, and the other way round.
        expect("com.apple.keylayout.French", [0: "Q", 12: "A", 13: "Z", 6: "W", 41: "M", 46: ",", 49: nil, 123: nil])
        // German QWERTZ: Y and Z swap.
        expect("com.apple.keylayout.German", [6: "Y", 16: "Z", 0: "A", 49: nil])
        // The layout in use answers too (whatever it is, the key at a letter position prints a letter).
        check(KeyLayoutNames.name(for: 0) != nil, "the layout in use names the key at position 0")
        check(KeyLayoutNames.name(for: 49) == nil, "and prints nothing for Space")
        check(KeyLayoutNames.layout(id: "com.apple.keylayout.NoSuchLayout") == nil, "an unknown layout is nil, not a crash")
        check(skipped.count < 3, "at least one of the three layouts must be installed to test anything")
        print("Key layout names: \(cases) cases passed" + (skipped.isEmpty ? "" : " (layouts not installed, skipped: \(skipped.joined(separator: ", ")))"))
    }
}
