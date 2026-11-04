import Foundation

// Source pins for the music pill (GitHub build only): the controller listens to both apps and sends every script through one guarded path; the view, the catalog, the purpose line, the Settings help and the binary check say what the spec says.
// No test program can compile the app's files (the controller and the views need the whole app), so each pin says where a call or a word must be. Run from the repository root through scripts/test-music-wiring.sh.

@main
enum MusicWiringTests {
    static func file(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }
    static func source(_ name: String) -> String { file("NotchBuddy/Sources/App/\(name)") }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }

    static func main() {
        let c = source("MusicController.swift"), r = source("MusicFollow.swift"), v = source("IslandViewContent.swift")
        let catalog = source("PillCatalog.swift"), settings = source("SettingsSections.swift")
        let renderSettings = file("scripts/render-settings.swift")
        let yml = file("NotchBuddy/project.yml"), plist = file("NotchBuddy/Resources/Info.plist"), binary = file("scripts/check-app-binary.sh")

        CT.section("the files were read")
        CT.checkTrue("the controller, the rules, the view and the catalog are there", c.contains("final class MusicController") && r.contains("struct MusicFollow") && v.contains("struct MusicCardView") && catalog.contains("integration_music"))

        CT.section("both files are GitHub-only, and neither logs, polls or keeps time of its own")
        CT.checkTrue("MusicFollow.swift starts with #if !APPSTORE and ends with #endif", r.hasPrefix("#if !APPSTORE") && r.hasSuffix("#endif\n"))
        CT.checkTrue("MusicController.swift starts with #if !APPSTORE and ends with #endif", c.hasPrefix("#if !APPSTORE") && c.hasSuffix("#endif\n"))
        let banned = ["appendAppLog", "print(", "NSLog", "Logger(", "os_log", "Timer", "asyncAfter", "DispatchSource"]
        CT.check("no log call, timer or dispatch source in either file", banned.filter { c.contains($0) || r.contains($0) }, [])

        CT.section("the rules are pure: Foundation only")
        CT.checkTrue("MusicFollow.swift imports Foundation and no UI framework", r.contains("import Foundation") && !r.contains("import AppKit") && !r.contains("import SwiftUI"))

        CT.section("the controller: both apps, one holder of the rules, one guarded path to AppleScript")
        let needles = [
            "MusicApp.allCases", "app.notificationName", "static let marker = \"NM_MUSIC_FOLLOWS_SPOTIFY\"",
            "guard isRunning(app) else { return .error }", "follow.remove(app)", "MusicPlayback.fromNotification(",
        ]
        CT.check("the controller has every wiring needle", needles.filter { !c.contains($0) }, [])
        CT.check("runAppleScript( is the definition and the one call inside send", count("runAppleScript(", in: c), 2)
        CT.check("NSAppleScript( is built only in runAppleScript", count("NSAppleScript(", in: c), 1)
        CT.check("NSWorkspace.shared.open( is Open Music's and the Automation settings' only", count("NSWorkspace.shared.open(", in: c), 2)
        let forbidden = ["tell application", "com.apple.Music.playerInfo", "com.spotify.client", "openApplication", "launchApplication", "func shortTitle"]
        CT.check("no script text, no hard-coded notification name, no launch call, no track clean-up left in the controller", forbidden.filter { c.contains($0) }, [])

        CT.section("Open: the shown app by its bundle ID, never Music for Spotify, no launch call")
        CT.checkTrue("openMusic asks MusicFollow.openApp for the app", c.contains("MusicFollow.openApp(shown: shownApp)"))
        CT.checkTrue("it finds a running app by bundle ID and otherwise opens it by its URL", c.contains("urlForApplication(withBundleIdentifier: app.bundleId)") && c.contains("if let url = NSWorkspace.shared.urlForApplication"))
        CT.checkTrue("the hard-coded Music path is gone", !c.contains("/System/Applications/Music.app"))

        CT.section("the grant: recorded only when the app was running before and after the script")
        CT.checkTrue("the success path asks grantRecorded with both facts", c.contains("if MusicFollow.grantRecorded(runningBefore: runningBefore, runningAfter: runningAfter) {"))
        CT.checkTrue("runningAfter is read on the app's queue by bundle ID", c.contains("let runningAfter = !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleId).isEmpty"))
        CT.checkTrue("send passes runningBefore from its guard", c.contains("return await runAppleScript(source, app: app, runningBefore: true, generation: gen)"))
        CT.check("noteDenied is called from the runner only, and is generation-guarded", count("noteDenied(", in: c), 2)
        CT.checkTrue("a refusal is recorded only if its generation is current and the pill is on", c.contains("func noteDenied(_ app: MusicApp, generation gen: Int) {\n        guard MusicFollow.acceptsResult(resultGeneration: gen, currentGeneration: generation, pillOn: isPillActive) else { return }"))
        CT.checkTrue("the control captures the generation before it sends", c.contains("let gen = generation\n        Task { await send(app, MusicFollow.script(command, for: app), generation: gen) }"))
        CT.checkTrue("the pill going off keeps both refusals: the refusal is macOS's answer, so it survives the toggle", c.contains("private func clearState() {\n        follow.clear()\n        publish()"))
        CT.check("no refusal is cleared on the pill's off (count of the reset lines)", count("denied = []", in: c) + count("lastDenied = nil", in: c), 0)

        CT.section("the refusal check: once per expansion, never a prompt, no timer")
        CT.check("the C check is called once, in the controller", count("AEDeterminePermissionToAutomateTarget(", in: c), 1)
        CT.checkTrue("it is called with askUserIfNeeded false (never prompts)", c.contains("AEDeterminePermissionToAutomateTarget(desc.aeDesc, typeWildCard, typeWildCard, false)"))
        CT.check("askUserIfNeeded true appears in no music file", count("askUserIfNeeded: true", in: c) + count("askUserIfNeeded: true", in: r) + count("typeWildCard, typeWildCard, true)", in: c), 0)
        CT.checkTrue("the target is the app's bundle ID, kept alive around the call", c.contains("NSAppleEventDescriptor(bundleIdentifier: app.bundleId)") && c.contains("withExtendedLifetime(desc)"))
        CT.checkTrue("the check runs on the app's queue and hops back to the main actor", c.contains("(app == .spotify ? spotifyQueue : appleMusicQueue).async") && c.contains("MusicController.shared.applyRecheck(app, allowed: allowed, generation: gen)"))
        CT.checkTrue("the rules decide: the status and the set to check", c.contains("MusicFollow.permissionAfterCheck(status: status)") && c.contains("MusicFollow.shouldRecheck(denied: denied, running: running, pillOn: isPillActive)"))
        CT.checkTrue("the trigger is the island's expansion, from AppState's mode", c.contains("AppState.shared.$mode") && c.contains("recheckRefusals()"))

        CT.section("paused apps: a quit removes the app (the terminate observer)")
        CT.checkTrue("the terminate observer is there", c.contains("NSWorkspace.didTerminateApplicationNotification") && c.contains("self.follow.remove(app)"))

        CT.section("in-flight reads: a generation, bumped on every integrations emission, checked before a result is applied; a quit drops only its own app's late read")
        CT.checkTrue("the generation is a counter on the controller", c.contains("private var generation = 0"))
        CT.check("the generation is bumped by the integrations sink only", count("self.generation += 1", in: c), 1)
        CT.checkTrue("fetch drops a result from an app that is no longer running", c.contains("pillOn: isPillActive),\n                  isRunning(app),"))
        CT.checkTrue("an allowed recheck re-reads the app when the pill is on", c.contains("noteGranted(app)\n        if isPillActive { fetch(app) }"))
        CT.checkTrue("fetch captures it before its send", c.contains("let gen = generation"))
        CT.checkTrue("and applies the result only through the rule", c.contains("MusicFollow.acceptsResult(resultGeneration: gen, currentGeneration: generation, pillOn: isPillActive)"))

        CT.section("the view: words and the marker only")
        let viewNeedles = [
            "MusicCardView()\n                .accessibilityIdentifier(MusicController.marker)",
            "MusicFollow.statusLine(",
            "MusicFollow.secondLine(artist: controller.artist, app: controller.shownApp)",
            "Text(controller.deniedLabel)",
            "Text(\"Allow NotchMeow to control \\(controller.deniedLabel)\")",
            "Button(\"Open \\(MusicController.shared.openLabel)\")",
        ]
        CT.check("the card and the status line read the rules", viewNeedles.filter { !v.contains($0) }, [])
        CT.checkTrue("the old Apple Music words are gone from the view", !v.contains("Text(\"Apple Music\")") && !v.contains("\"Automation not allowed\""))

        CT.section("the catalog: the idle name is Music, the pill is still githubOnly and still the same red")
        let lines = catalog.components(separatedBy: "\n")
        let musicAt = lines.firstIndex { $0.contains(".init(id: \"integration_music\",   name: \"Music\", color: \"#FA2D48\",") } ?? -1
        CT.checkTrue("the entry is named Music", musicAt >= 0)
        CT.checkTrue("and its next line ends githubOnly: true),", musicAt >= 0 && musicAt + 1 < lines.count && lines[musicAt + 1].hasSuffix("githubOnly: true),"))

        CT.section("the Settings words")
        let help = "help: \"Shows what Apple Music or Spotify is playing. Nothing to enter.\""
        CT.checkTrue("Settings → Services → Music says Apple Music or Spotify", settings.contains(help))
        CT.checkTrue("and the Settings sample says the same", renderSettings.contains(help))

        CT.section("the Automation purpose line, in the project and the plist")
        CT.checkTrue("project.yml names Music or Spotify", yml.contains("send mail and control Music or Spotify."))
        CT.checkTrue("Info.plist names Music or Spotify", plist.contains("send mail and control Music or Spotify.</string>"))

        CT.section("the binary check: the marker and Spotify's name are in the GitHub build and not in the App Store build")
        CT.checkTrue("it looks for the marker and for Spotify's bundle ID", binary.contains("has NM_MUSIC_FOLLOWS_SPOTIFY && music=1") && binary.contains("has com.spotify.client && spotify=1"))
        CT.checkTrue("release and debug require both", binary.contains("[ \"$music\" = 1 ] && [ \"$spotify\" = 1 ]") && count("[ \"$music\" = 1 ] && [ \"$spotify\" = 1 ]", in: binary) == 2)
        CT.checkTrue("the App Store build requires neither", binary.contains("[ \"$music\" = 0 ] && [ \"$spotify\" = 0 ]"))

        CT.finish()
    }
}
