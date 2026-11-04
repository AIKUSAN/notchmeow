import Foundation

// A probe for scripts/test-render-home-guard.sh: it asks Foundation for the home folder the way the app's own code does (`homeDirectoryForCurrentUser`, which asks the user database
// and ignores $HOME), and says what it found.
//   HomeProbe          prints the home folder
//   HomeProbe read     prints the text of <home>/.claude/settings.json, or "unreadable"
// Compiled alone with swiftc, so it is top-level code and not an @main type.
let home = FileManager.default.homeDirectoryForCurrentUser
if CommandLine.arguments.dropFirst().first == "read" {
    let file = home.appendingPathComponent(".claude/settings.json").path
    print((try? String(contentsOfFile: file, encoding: .utf8)) ?? "unreadable")
} else {
    print(home.path)
}
