// The owner's fake music events, for the owner's own check of the music pill (GitHub build). For the owner's check only.
// It posts the two apps' distributed notifications (Apple Music's playerInfo, Spotify's PlaybackStateChanged) with made-up tracks, so the pill follows them as it would a real app.
// It never talks to Music, Spotify or osascript and never launches anything. Run it as a script:
//   swift scripts/fake-music-events.swift <apple|spotify|both|stop> [--dry-run]
// --dry-run prints the steps and posts nothing and waits for nothing; the test (scripts/test-fake-music-events.sh) only ever runs --dry-run.
// Each post is printed first as "post <notification name> <state> <track>"; each pause as "wait 3".
//   apple    Apple Music Playing
//   spotify  Spotify Playing
//   stop     Apple Music Stopped, then Spotify Stopped (no pauses)
//   both     Apple Music Playing, Spotify Playing, Spotify Paused, Apple Music Paused, Spotify Stopped, Apple Music Stopped

import Foundation

enum FakeApp {
    case appleMusic, spotify

    var notification: String {
        switch self {
        case .appleMusic: return "com.apple.Music.playerInfo"
        case .spotify: return "com.spotify.client.PlaybackStateChanged"
        }
    }

    var track: String {
        switch self {
        case .appleMusic: return "Test Song (Apple Music)"
        case .spotify: return "Test Song (Spotify)"
        }
    }
}

enum Step {
    case post(FakeApp, String)   // the app and its Player State
    case wait
}

let usage = "usage: swift scripts/fake-music-events.swift <apple|spotify|both|stop> [--dry-run]"
let arguments = Array(CommandLine.arguments.dropFirst())
let dryRun = arguments.contains("--dry-run")
let scenarioName = arguments.first { $0 != "--dry-run" }

let scenarios: [String: [Step]] = [
    "apple": [.post(.appleMusic, "Playing")],
    "spotify": [.post(.spotify, "Playing")],
    "stop": [.post(.appleMusic, "Stopped"), .post(.spotify, "Stopped")],
    "both": [
        .post(.appleMusic, "Playing"), .wait,
        .post(.spotify, "Playing"), .wait,
        .post(.spotify, "Paused"), .wait,
        .post(.appleMusic, "Paused"), .wait,
        .post(.spotify, "Stopped"), .wait,
        .post(.appleMusic, "Stopped"),
    ],
]

guard arguments.count <= 2, let name = scenarioName, let steps = scenarios[name] else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}

for step in steps {
    switch step {
    case .post(let app, let state):
        print("post \(app.notification) \(state) \(app.track)")
        if !dryRun {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name(app.notification),
                object: nil,
                userInfo: ["Player State": state, "Name": app.track, "Artist": "NotchMeow Test", "Album": "Fake"],
                deliverImmediately: true)
        }
    case .wait:
        print("wait 3")
        if !dryRun { Thread.sleep(forTimeInterval: 3) }
    }
}
