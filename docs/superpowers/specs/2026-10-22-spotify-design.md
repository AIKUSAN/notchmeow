# Spotify and Apple Music: the music pill follows whichever plays (Mac)

Status: draft for the owner's review (2026-10-22). The owner asked for "Spotify instead of Apple Music" on 2026-10-17, then approved **follow both**, and on 2026-10-22 said to continue on the implementation (relaunch target 2026-11-13). The plan is `docs/superpowers/plans/2026-10-22-spotify-mac.md`.

## Where we are

`NotchBuddy/Sources/App/MusicController.swift` (GitHub build only, `#if !APPSTORE`) follows Apple Music alone: it listens to the distributed notification `com.apple.Music.playerInfo` (play, pause, stop, track change: title, artist and album come with it, no permission needed), reads the current state with AppleScript when the pill is turned on or Music launches (only once macOS has granted Automation, flag `notchmeow.musicAutomationGranted`), and sends play/pause, next and back with AppleScript. The pill is `integration_music` (frozen ID, catalog name "Apple Music", colour `#FA2D48`, `githubOnly: true`), with a hover pill (`MusicPill`: play/pause, next), a card (`MusicCardView`: title, artist, back/play/next, or "Allow NotchMeow to control Music" with Open Settings… when macOS refused), Settings → Services → Music (a switch and a help line), and the cat's dance (`AppState.musicPlaying` with the pill on).

Spotify posts `com.spotify.client.PlaybackStateChanged` with the same keys (`Player State` = `Playing` / `Paused` / `Stopped`, `Name`, `Artist`, `Album`) and has an AppleScript dictionary (`player state`, `current track`, `playpause`, `next track`, `previous track`). No key, no web API, no account.

## Goals

1. **Follow both apps.** The music pill shows whichever of Apple Music and Spotify is playing, and says which: "Apple Music" or "Spotify".
2. **The controls act on the app shown.** Play/pause, next and previous (the pill and the card) go to the app whose track is on screen.
3. **Nothing else changes for an Apple Music user:** same pill, card, dance, permission flag and prompt.

## Non-goals

- A Spotify pill of its own, a picker, a setting to choose the app, or a third player (VLC, browsers, Now Playing of other apps).
- Volume, seeking, artwork, playlists, liking a track, playing a named song (the chat's music tool is a later plan; see "Later").
- Windows and Linux (see below).
- Any change to the App Store build.

## Anti-goals (a failure even if it works)

- **Launching an app to ask it something.** A script is only sent to an app that is running, and the script itself checks again (`if application id "…" is running`), so an app that quits between the check and the send is not relaunched. A script is never even compiled for an app that is not running (for an app that is not installed, macOS would ask "Where is Spotify?").
- **A poll or a timer.** Both apps push notifications; NotchMeow only listens. 0 % CPU when the island is hidden holds.
- **A new prompt the user did not cause.** Spotify's Automation prompt appears only when the user clicks a control while Spotify is shown (below).
- **Logging, storing or sending what plays.** Title, artist and album stay in memory, are shown and nothing else.
- **Restyling the pill, the card or the Settings card.** Only words change.

## The rules

1. **Which app is shown.** NotchMeow keeps, in memory, the last state each app announced (playing or paused, with its track). The shown app is **the one playing; when both play, the one whose latest play or pause event is newest; when neither plays, the newest paused one.** A stopped app, or one that quit, is forgotten; the other one shows if it is still playing or paused. Nothing at all: the pill goes back to idle, as today. (This refines "the latest play or pause event wins" in one case: a pause in the app that is *not* shown does not take over from the one playing. Question 1.)
2. **The label.** The card's second line reads "<artist> · Spotify" or "<artist> · Apple Music" (the app's name alone when the track has no artist). The pill keeps showing the track title, as today; with nothing shown it shows its catalog name (Question 2). The generic card's status line reads "Spotify · Playing · <title>", "Spotify · Paused" or "Not playing". The Open button reads "Open Spotify" or "Open Music" (the latter also when nothing is shown, and it opens Music as today).
3. **The controls.** Play/pause, next and previous go to the shown app: Apple Music keeps `playpause`, `next track`, `back track`; Spotify gets `playpause`, `next track`, `previous track`. A control with no shown app, or whose app is not running, does nothing.
4. **The first read.** When the pill is turned on, and when either app launches, NotchMeow reads that app's state with AppleScript, only if the app is running and macOS has already granted Automation for it (its own flag). Otherwise the pill waits for the app's next notification, as Apple Music does today.
5. **The cat** dances while the shown app plays and the pill is on (unchanged: `AppState.musicPlaying` now means "the shown app plays"). The silent reveal when music starts fires on the change from nothing playing to something playing, not when playback moves from one app to the other.

## Not installed, not running, not allowed

| Case | Apple Music (today, unchanged) | Spotify (new) |
|---|---|---|
| Not installed | Always installed on macOS. | No notification ever comes; the pill works for Apple Music alone. Never compiled, never launched. |
| Installed, not running | Nothing shown from it; controls do nothing. Open Music opens it (an explicit click). | Same. Open Spotify only appears while Spotify is the shown app, so it is always running then. |
| Running, never asked | Track shown from the notifications; the first control click sends the first Apple event, so macOS asks then. | The same, separately. |
| Allowed | Controls work; the first read happens on pill-on and on launch. | The same, with the flag `notchmeow.spotifyAutomationGranted`. |
| Refused | The card shows "Allow NotchMeow to control Music" with Open Settings…; the dot is red. | The card shows "Allow NotchMeow to control Spotify". A refusal is per app: a refused Spotify never hides a playing Apple Music, and the card names the app that refused. The next successful script to that app clears it. |

## The macOS Automation prompt

Each app is its own Automation entry (System Settings → Privacy & Security → Automation → NotchMeow → Music / Spotify), so a second app means a second prompt. It appears **the first time the user clicks play/pause, next or previous while Spotify is the shown app**, never at launch, never on a notification, never for the first read (which waits for the flag). Its purpose line is the app's one `NSAppleEventsUsageDescription`, which today ends "…and control Music."; it becomes "…and control Music or Spotify." (Question 3). The existing `com.apple.security.automation.apple-events` entitlement covers any app; the GitHub build is not sandboxed, so no other entitlement changes.

## Builds

GitHub build only, as today: the controller and the new rules file are under `#if !APPSTORE`, the pill stays `githubOnly`. The App Store build is unchanged: no music pill, no Apple events, no `NSAppleEventsUsageDescription` (`scripts/test-release-tools.sh` already pins that). `scripts/check-app-binary.sh` gains a marker for the music controller (present in Release and Debug, absent from App Store) and checks that `com.spotify.client` is absent from the App Store binary.

## Privacy

Title, artist and album live in `MusicController`'s memory and the pill's name, and nothing else: no log line (`appendAppLog`, `print`, `NSLog`, `Logger`), no UserDefaults, no file, no network. The only stored values are the two grant flags (booleans). A distributed notification can be posted by any process, so a fake one can change what the pill shows, nothing more: it never triggers a script.

## Windows and Linux

Unchanged. They have no media reader today: the cat's bob exists (`windows/src/cat/dance.ts`) and `State.musicPlaying` is the seam, which nothing sets (`windows/README.md`), and there is no music pill. Following Spotify there would mean a new platform reader (Windows media session, MPRIS on Linux): a separate plan if the owner wants it. The Mac rule "Mac gets at least what Windows/Linux gets" holds.

## Testing

- **Pure rules** in one Foundation file (`MusicFollow.swift`): the app table, parsing a notification's and a script's player state, the track clean-up (moved unchanged from `MusicController`), the shown-app rule, the script texts, the words of the status line, the card's second line and the refusal shown. Tested by a `swiftc` program (`scripts/test-music-follow.sh`).
- **A wiring pin** (`scripts/test-music-wiring.sh`) on the sources: both notifications observed, one guarded path to AppleScript, no script text in the controller, no log call, the App Store fence, the catalog entry.
- **The binary check** above.
- **A picture** of the card and the pill in each state, drawn without the app, for the owner's checkpoint.
- **A fake notification sender** for the owner's own check (`swift scripts/fake-music-events.swift <scenario>`): it posts the two apps' notifications with made-up tracks and never talks to a real app. Tests never run Music, Spotify or `osascript`.

## Later

The chat's music tool (`2026-10-17-notchmeow-chat-design.md`, "music and now_playing") picks "the one that is playing" first, the same rule; it can reuse `MusicApp`, the script texts and the controller's guarded runner instead of its own.

## Questions for the owner

1. **A pause in the app that is not shown.** Apple Music and Spotify both play; Spotify is shown (it started last). You pause Apple Music. Strictly "the latest play or pause event wins" would switch the pill to a paused Apple Music while Spotify is still playing. **Recommended:** the one playing always wins (rule 1 as written); "latest event" decides only between two playing or two paused apps.
2. **The pill's idle name.** With nothing shown, the pill shows its catalog name, "Apple Music" today. **Recommended:** "Music" (the Settings card is already called "Music"; the ID `integration_music` does not change). Alternative: keep "Apple Music".
3. **The Automation purpose line.** **Recommended:** "NotchMeow uses this to jump to your terminal, send mail and control Music or Spotify." (shown in both prompts). Alternative: keep "…control Music." The release-tools test pins it in three places, which change with it.
4. **The pill's colour while Spotify shows.** **Recommended:** keep the pill's red (`#FA2D48`) for both apps, so nothing is restyled; the words say which app. Alternative: Spotify green (`#1DB954`) on the card's dot and the pill's hover while Spotify is shown.
5. **The Settings help line.** **Recommended:** "Shows what Apple Music or Spotify is playing. Nothing to enter." Alternative: keep "Shows what the Music app is playing."
