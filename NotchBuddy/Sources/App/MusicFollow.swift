#if !APPSTORE
import Foundation

// The music pill's rules (GitHub build only): it follows Apple Music and Spotify through their distributed notifications and shows whichever plays.
// Spec: docs/superpowers/specs/2026-10-22-spotify-design.md ("The rules"). Pure Foundation: MusicController listens, sends the scripts and publishes; every decision is here.

enum MusicApp: String, CaseIterable, Sendable {
    case appleMusic, spotify   // this order is the first-read order

    var bundleId: String {
        switch self {
        case .appleMusic: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }

    var notificationName: String {
        switch self {
        case .appleMusic: return "com.apple.Music.playerInfo"
        case .spotify: return "com.spotify.client.PlaybackStateChanged"
        }
    }

    var label: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }

    var grantedKey: String {
        switch self {
        case .appleMusic: return MusicFollow.appleMusicGrantedKey
        case .spotify: return MusicFollow.spotifyGrantedKey
        }
    }

    static func of(bundleId: String?) -> MusicApp? {
        guard let bundleId else { return nil }
        return allCases.first { $0.bundleId == bundleId }
    }
}

enum MusicPlayback: Equatable, Sendable {
    case playing, paused, stopped

    static func fromNotification(_ state: String?) -> MusicPlayback? {
        switch state ?? "" {
        case "Playing": return .playing
        case "Paused": return .paused
        case "Stopped": return .stopped
        default: return nil
        }
    }

    static func fromScript(_ state: String) -> MusicPlayback? {
        switch state {
        case "playing", "fast forwarding", "rewinding": return .playing
        case "paused": return .paused
        case "stopped": return .stopped
        default: return nil
        }
    }
}

struct MusicTrack: Equatable, Sendable {
    var title: String?
    var artist: String?
    var album: String?

    init(name: String?, artist: String?, album: String?) {
        self.title = Self.blank(name).map(Self.shortTitle)
        self.artist = Self.blank(artist).map(Self.shortArtist)
        self.album = Self.blank(album)
    }

    private static func blank(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return raw
    }

    // Moved unchanged from MusicController.
    static func shortTitle(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        var s = raw
        // Cut at first " - "
        if let r = s.range(of: " - ") {
            s = String(s[..<r.lowerBound])
        }
        // Strip trailing (...) or [...] groups repeatedly
        var changed = true
        while changed {
            changed = false
            let t = s.trimmingCharacters(in: .whitespaces)
            guard let last = t.last, (last == ")" || last == "]") else { break }
            let open: Character = last == ")" ? "(" : "["
            if let idx = t.lastIndex(of: open) {
                let candidate = String(t[..<idx]).trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty { s = candidate; changed = true }
            } else { break }
        }
        let result = s.trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? raw : result
    }

    // Moved unchanged from MusicController.
    static func shortArtist(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        let lower = raw.lowercased()
        for tag in [" feat.", " ft."] {
            if let r = lower.range(of: tag) {
                let result = String(raw[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                return result.isEmpty ? raw : result
            }
        }
        return raw
    }
}

enum MusicCommand: Sendable { case playPause, next, previous }

struct MusicFollow: Equatable, Sendable {
    static let appleMusicGrantedKey = "notchmeow.musicAutomationGranted"
    static let spotifyGrantedKey = "notchmeow.spotifyAutomationGranted"
    static let deniedCode = -1743

    struct Entry: Equatable, Sendable {
        var playback: MusicPlayback
        var track: MusicTrack
        var order: Int
    }

    private(set) var entries: [MusicApp: Entry] = [:]
    private var counter = 0

    init() {}

    /// A stop forgets the app; any other state is stamped with the next order (no clock).
    mutating func apply(_ app: MusicApp, _ playback: MusicPlayback, _ track: MusicTrack) {
        guard playback != .stopped else { entries[app] = nil; return }
        counter += 1
        entries[app] = Entry(playback: playback, track: track, order: counter)
    }

    mutating func remove(_ app: MusicApp) { entries[app] = nil }

    mutating func clear() { entries = [:] }

    /// Playing beats paused; between two playing (or two paused) apps, the newest order.
    var shown: MusicApp? {
        Self.newest(entries.filter { $0.value.playback == .playing })
            ?? Self.newest(entries.filter { $0.value.playback == .paused })
    }

    var shownTrack: MusicTrack? { shown.flatMap { entries[$0]?.track } }

    var isPlaying: Bool {
        guard let app = shown else { return false }
        return entries[app]?.playback == .playing
    }

    private static func newest(_ found: [MusicApp: Entry]) -> MusicApp? {
        found.max { $0.value.order < $1.value.order }?.key
    }

    // Every script is guarded: nothing is sent to an app that is not running, and the script checks again on its own.

    static func script(_ command: MusicCommand, for app: MusicApp) -> String {
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = app == .appleMusic ? "back track" : "previous track"
        }
        let id = app.bundleId
        return """
        if application id "\(id)" is running then
            tell application id "\(id)" to \(verb)
        end if
        """
    }

    static func readScript(for app: MusicApp) -> String {
        let id = app.bundleId
        return """
        if application id "\(id)" is not running then return {"stopped", "", "", ""}
        tell application id "\(id)"
            set ps to player state as string
            if ps is "stopped" then return {ps, "", "", ""}
            try
                set tr to current track
                set n to name of tr
            on error
                return {ps, "", "", ""}
            end try
            set ar to ""
            set al to ""
            try
                set ar to artist of tr
            end try
            try
                set al to album of tr
            end try
            return {ps, n, ar, al}
        end tell
        """
    }

    // The words.

    static func statusLine(shown: MusicApp?, playing: Bool, title: String?, denied: MusicApp?) -> String {
        if let denied { return "\(denied.label): automation not allowed" }
        guard let shown else { return "Not playing" }
        guard playing else { return "\(shown.label) · Paused" }
        let name = title.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
        return "\(shown.label) · Playing · \(name)"
    }

    static func secondLine(artist: String?, app: MusicApp?) -> String? {
        let name = artist.flatMap { $0.isEmpty ? nil : $0 }
        if let name, let app { return "\(name) · \(app.label)" }
        return name ?? app?.label
    }

    /// A refusal shows only for the app it concerns: the shown one, or with nothing shown the last refusal.
    static func deniedToShow(denied: Set<MusicApp>, shown: MusicApp?, lastDenied: MusicApp?) -> MusicApp? {
        if let shown { return denied.contains(shown) ? shown : nil }
        guard let lastDenied, denied.contains(lastDenied) else { return nil }
        return lastDenied
    }

    /// Open shows the shown app; with nothing shown, Apple Music as it always did.
    static func openApp(shown: MusicApp?) -> MusicApp { shown ?? .appleMusic }

    /// The Automation grant is recorded only for an app that was running before its script and still is after it.
    static func grantRecorded(runningBefore: Bool, runningAfter: Bool) -> Bool { runningBefore && runningAfter }

    /// macOS's answer to the check: allowed (true), still refused (false), undetermined or another error (nil: nothing changes).
    static func permissionAfterCheck(status: OSStatus) -> Bool? {
        if status == noErr { return true }
        if Int(status) == deniedCode { return false }
        return nil
    }

    /// The refusals to check when the island expands: only apps that are running (a check could launch a closed one), only with the pill on.
    static func shouldRecheck(denied: Set<MusicApp>, running: Set<MusicApp>, pillOn: Bool) -> Set<MusicApp> {
        pillOn ? denied.intersection(running) : []
    }

    /// A read or script result is applied only if it was asked for under the current generation and the pill is still on.
    static func acceptsResult(resultGeneration: Int, currentGeneration: Int, pillOn: Bool) -> Bool {
        resultGeneration == currentGeneration && pillOn
    }
}
#endif
