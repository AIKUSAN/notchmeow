#if !APPSTORE
import Foundation
import AppKit
import Combine

// MARK: - Music Controller

/// Follows Apple Music and Spotify through their distributed notifications and sends the controls to the app shown.
/// Singleton, @MainActor, GitHub build only. The rules (which app is shown, the scripts, the words) are in MusicFollow.swift; this file listens, reads, sends and publishes.
@MainActor
final class MusicController: ObservableObject {
    static let shared = MusicController()
    /// scripts/check-app-binary.sh looks for this marker: the GitHub build has it, the App Store build does not.
    static let marker = "NM_MUSIC_FOLLOWS_SPOTIFY"

    @Published var trackTitle: String?
    @Published var artist: String?
    @Published var album: String?
    /// The app whose track is on screen (MusicFollow.shown).
    @Published private(set) var shownApp: MusicApp?
    /// The app whose refusal is on screen (MusicFollow.deniedToShow).
    @Published private(set) var deniedApp: MusicApp?

    private var follow = MusicFollow()
    private var denied: Set<MusicApp> = []
    private var lastDenied: MusicApp?
    /// Bumped on every emission of the pill's integrations: a read or script result from before it is dropped (MusicFollow.acceptsResult).
    private var generation = 0
    private var notifTokens: [Any] = []
    private var cancellables = Set<AnyCancellable>()
    // One queue per app: a Spotify prompt or a hung Spotify must not hold up Apple Music.
    private let appleMusicQueue = DispatchQueue(label: "io.github.aikusan.notchmeow.music.appleMusic")
    private let spotifyQueue = DispatchQueue(label: "io.github.aikusan.notchmeow.music.spotify")

    /// The Open button's app: Spotify while Spotify is shown, else Music.
    var openLabel: String { MusicFollow.openApp(shown: shownApp) == .spotify ? "Spotify" : "Music" }
    /// The refused app's name for the card (the card is only shown while something is refused).
    var deniedLabel: String { deniedApp == .spotify ? "Spotify" : "Music" }

    private var isPillActive: Bool {
        AppState.shared.activeIntegrations.contains("integration_music")
    }

    private init() {
        // One observer per app. Each extracts Sendable String? values before crossing into @MainActor.
        for app in MusicApp.allCases {
            let token = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(app.notificationName),
                object: nil,
                queue: .main
            ) { [weak self] notif in
                let info        = notif.userInfo
                let playerState = info?["Player State"] as? String
                let name        = info?["Name"]          as? String
                let artist      = info?["Artist"]        as? String
                let album       = info?["Album"]         as? String
                Task { @MainActor [weak self] in
                    self?.receive(app, playerState: playerState, name: name, artist: artist, album: album)
                }
            }
            notifTokens.append(token)
        }

        // An app launches: read its state only if the pill is on and macOS has granted Automation for it
        let launch = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            let bundleId = (notif.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.bundleIdentifier
            guard let app = MusicApp.of(bundleId: bundleId) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isPillActive, UserDefaults.standard.bool(forKey: app.grantedKey) else { return }
                self.fetch(app)
            }
        }
        notifTokens.append(launch)

        // An app quits: forget what it announced and show what is left
        let terminate = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            let bundleId = (notif.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.bundleIdentifier
            guard let app = MusicApp.of(bundleId: bundleId) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.follow.remove(app)
                self.publish()
            }
        }
        notifTokens.append(terminate)

        // The pill turned on: read every running, granted app; turned off: forget both
        AppState.shared.$activeIntegrations
            .sink { [weak self] integrations in
                guard let self else { return }
                self.generation += 1
                if integrations.contains("integration_music") {
                    for app in MusicApp.allCases where self.isRunning(app) && UserDefaults.standard.bool(forKey: app.grantedKey) {
                        self.fetch(app)
                    }
                } else {
                    self.clearState()
                }
            }
            .store(in: &cancellables)

        // The island expanded: each refused app that is running is asked once (no timer: the expansion is the only trigger)
        AppState.shared.$mode
            .removeDuplicates()
            .sink { [weak self] mode in
                guard mode == .expanded else { return }
                self?.recheckRefusals()
            }
            .store(in: &cancellables)
    }

    // MARK: - What the apps say

    /// What an app's notification says. Ignored while the pill is off, and for an unknown player state.
    func receive(_ app: MusicApp, playerState: String?, name: String?, artist: String?, album: String?) {
        guard isPillActive, let playback = MusicPlayback.fromNotification(playerState) else { return }
        follow.apply(app, playback, MusicTrack(name: name, artist: artist, album: album))
        publish()
    }

    /// macOS refused a script to this app (-1743). A refusal from an older generation, or while the pill is off, changes nothing.
    func noteDenied(_ app: MusicApp, generation gen: Int) {
        guard MusicFollow.acceptsResult(resultGeneration: gen, currentGeneration: generation, pillOn: isPillActive) else { return }
        denied.insert(app)
        lastDenied = app
        UserDefaults.standard.set(false, forKey: app.grantedKey)
        publish()
    }

    /// A script to this app ran: macOS has granted Automation for it, so an old refusal is cleared.
    private func noteGranted(_ app: MusicApp) {
        denied.remove(app)
        UserDefaults.standard.set(true, forKey: app.grantedKey)
        publish()
    }

    private func fetch(_ app: MusicApp) {
        let gen = generation
        Task {
            let result = await send(app, MusicFollow.readScript(for: app), generation: gen)
            guard MusicFollow.acceptsResult(resultGeneration: gen, currentGeneration: generation, pillOn: isPillActive),
                  isRunning(app),
                  case .success(let values) = result, values.count >= 4,
                  let playback = MusicPlayback.fromScript(values[0]) else { return }
            follow.apply(app, playback, MusicTrack(name: values[1], artist: values[2], album: values[3]))
            publish()
        }
    }

    /// Each refused app that is running is checked once, on its queue, with askUserIfNeeded false (it never prompts).
    private func recheckRefusals() {
        let running = Set(MusicApp.allCases.filter(isRunning))
        let gen = generation
        for app in MusicFollow.shouldRecheck(denied: denied, running: running, pillOn: isPillActive) {
            (app == .spotify ? spotifyQueue : appleMusicQueue).async {
                let desc = NSAppleEventDescriptor(bundleIdentifier: app.bundleId)
                let status = withExtendedLifetime(desc) {
                    AEDeterminePermissionToAutomateTarget(desc.aeDesc, typeWildCard, typeWildCard, false)
                }
                let allowed = MusicFollow.permissionAfterCheck(status: status)
                Task { @MainActor in MusicController.shared.applyRecheck(app, allowed: allowed, generation: gen) }
            }
        }
    }

    /// Allowed clears the app's refusal, as a script that ran would; denied or undetermined changes nothing.
    private func applyRecheck(_ app: MusicApp, allowed: Bool?, generation gen: Int) {
        guard MusicFollow.acceptsResult(resultGeneration: gen, currentGeneration: generation, pillOn: isPillActive), allowed == true else { return }
        noteGranted(app)
        if isPillActive { fetch(app) }
    }

    private func clearState() {
        follow.clear()
        publish()
    }

    /// Copies the rules' answer into the published state, the cat's dance, the reveal and the pill's name.
    private func publish() {
        let track = follow.shownTrack
        trackTitle = track?.title
        artist     = track?.artist
        album      = track?.album
        shownApp   = follow.shown
        deniedApp  = MusicFollow.deniedToShow(denied: denied, shown: follow.shown, lastDenied: lastDenied)
        AppState.shared.musicAutomationDenied = deniedApp != nil

        let wasPlaying = AppState.shared.musicPlaying
        let playing = follow.isPlaying
        AppState.shared.musicPlaying = playing
        syncTaskName()

        // Reveal only on the change from nothing playing to something playing, not when playback moves between the apps
        if playing && !wasPlaying {
            NotificationCenter.default.post(name: .musicReveal, object: nil)
        }
    }

    private func syncTaskName() {
        guard let idx = AppState.shared.tasks.firstIndex(where: { $0.id == "integration_music" }) else { return }
        let title = trackTitle ?? ""
        AppState.shared.tasks[idx].name = title.isEmpty
            ? (PillCatalog.definition(for: "integration_music")?.name ?? "Music")
            : title
    }

    private func isRunning(_ app: MusicApp) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == app.bundleId }
    }

    // MARK: - Playback controls: they go to the app shown

    func playPause() { control(.playPause) }
    func nextTrack() { control(.next) }
    func previousTrack() { control(.previous) }

    private func control(_ command: MusicCommand) {
        guard let app = follow.shown else { return }
        let gen = generation
        Task { await send(app, MusicFollow.script(command, for: app), generation: gen) }
    }

    /// Opens the shown app by its bundle ID: activates it if it runs, else opens it (Spotify is never replaced by Music).
    func openMusic() {
        let app = MusicFollow.openApp(shown: shownApp)
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == app.bundleId }) {
            running.activate(options: .activateIgnoringOtherApps)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) {
            NSWorkspace.shared.open(url)
        }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - AppleScript: the one guarded path to an app

    enum ScriptResult { case success([String]), error }

    /// Sends a script only to a running app: an app that is not running is never asked, so it is never launched.
    @discardableResult
    private func send(_ app: MusicApp, _ source: String, generation gen: Int) async -> ScriptResult {
        guard isRunning(app) else { return .error }
        return await runAppleScript(source, app: app, runningBefore: true, generation: gen)
    }

    @discardableResult
    private func runAppleScript(_ source: String, app: MusicApp, runningBefore: Bool, generation gen: Int) async -> ScriptResult {
        await withCheckedContinuation { cont in
            (app == .spotify ? spotifyQueue : appleMusicQueue).async {
                let script = NSAppleScript(source: source)!
                var errDict: NSDictionary?
                let desc = script.executeAndReturnError(&errDict)
                if let errDict {
                    let code = (errDict[NSAppleScript.errorNumber] as? Int) ?? 0
                    if code == MusicFollow.deniedCode {
                        Task { @MainActor in MusicController.shared.noteDenied(app, generation: gen) }
                        cont.resume(returning: .error)
                    } else {
                        cont.resume(returning: .error)
                    }
                    return
                }
                // The grant is recorded only if the app was running before the script and still is after it
                let runningAfter = !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleId).isEmpty
                if MusicFollow.grantRecorded(runningBefore: runningBefore, runningAfter: runningAfter) {
                    Task { @MainActor in MusicController.shared.noteGranted(app) }
                }
                // Extract values on this queue before resuming (avoids NSAppleEventDescriptor Sendable issues)
                var values: [String] = []
                let count = desc.numberOfItems
                if count > 0 {
                    for i in 1...count {
                        values.append(desc.atIndex(i)?.stringValue ?? "")
                    }
                } else {
                    values = [desc.stringValue ?? ""]
                }
                cont.resume(returning: .success(values))
            }
        }
    }
}
#endif
