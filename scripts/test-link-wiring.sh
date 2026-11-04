#!/usr/bin/env bash
# Pins the call sites and the absences of the link (sub-project G2) in the app files no test program can compile: nothing listens until the user turns "Visible on this network" on, nothing polls,
# nothing accepts an offer but a click, no name reaches a log, the secrets live only in the Keychain, the Accept card is an alert like an approval, and the entitlements and Info.plist keys the
# App Store build needs are there. Plain greps on the sources and on the generated plists; a failing line says what moved.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=NotchBuddy/Sources/App
fail=0
pin() {   # pin "what it means" expected_count file... -- pattern
    local label="$1" want="$2"; shift 2
    local files=() pattern
    while [ "$1" != "--" ]; do files+=("$1"); shift; done
    shift; pattern="$1"
    local got
    got=$( (grep -h -E -- "$pattern" "${files[@]}" 2>/dev/null || true) | wc -l | tr -d ' ')
    if [ "$got" = "$want" ]; then echo "  ✓ $label"; else echo "  ✗ $label (found $got, expected $want of: $pattern)"; fail=$((fail + 1)); fi
}
order() {   # order "what it means" file -- first_pattern -- second_pattern: the first line that matches the first pattern comes before the first line that matches the second
    local label="$1" file="$2" first second a b
    first="$4"; second="$6"
    a=$(grep -n -E -- "$first" "$file" | head -1 | cut -d: -f1)
    b=$(grep -n -E -- "$second" "$file" | head -1 | cut -d: -f1)
    if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then echo "  ✓ $label"; else echo "  ✗ $label (lines ${a:-none} and ${b:-none}: $first, then $second)"; fail=$((fail + 1)); fi
}
LINK=($(ls $APP/Link*.swift | grep -v LinkDevPeer))     # every link file that is in a Release build
ALL=($(ls $APP/Link*.swift))

echo "off until the user turns it on"
pin "the stored default of Visible on this network is false" 1 $APP/LinkSettings.swift -- 'var visible = false'
pin "startListening is defined once and called from five places only, each guarded: start(), setVisible(true), the rename (through restartAdvert) and devicesOpened() and the relaunch after a failure; comments excluded" 6 $APP/LinkService.swift -- '^[^/]*startListening\(\)'
pin "start() starts it only if settings.visible" 1 $APP/LinkService.swift -- 'if settings.visible \{ startListening\(\) \}'
pin "devicesOpened() starts it again only if visible and nothing listens" 1 $APP/LinkService.swift -- 'if settings\.visible && !listening \{ startListening\(\) \}'
pin "a rename restarts the advert only if visible (restartAdvert has no other caller)" 2 $APP/LinkService.swift -- 'if settings\.visible \{ restartAdvert\(\) \}|restartAdvert\(\)'
pin "the advert is made in one place (the listener's start), with the machine's id and name only" 1 $APP/LinkNetwork.swift -- 'NWTXTRecord\(\["v":'
pin "the browser starts only when visible (the guard is in startBrowser itself)" 1 $APP/LinkService.swift -- 'guard browser == nil, browsers > 0, settings\.visible'
pin "startBrowser has two callers: beginBrowsing and setVisible(true) while Devices is open (both reached only when visible)" 2 $APP/LinkService.swift -- '(\{ |^ *)startBrowser\(\)'
pin "the app starts the service once, at launch" 1 $APP/AppDelegate.swift -- 'LinkService\.shared\.start\(\)'

echo "who may start a pairing with this Mac"
pin "an incoming pairing goes through the one gated function" 1 $APP/LinkService.swift -- 'LinkIncomingPairing\.run\('
pin "the service checks the gate before it does anything for an incoming pairing (also: no run, no other pairing, no card with buttons)" 1 $APP/LinkService.swift -- 'guard pairRun == nil, !outbound, !pairingIncoming, !rules\.interactive, pairGate\.allows\(now: Self\.nowMs\(\)\) else \{ slot\.finish\(\); await t\.close\(\); return \}'
pin "the gate is checked first in the function, before a run exists" 1 $APP/LinkPairRun.swift -- 'guard gate\.allows\(now: clock\(\)\) else \{ await transport\.close\(\); return nil \}'
pin "the service never starts a responder run itself" 0 $APP/LinkService.swift -- 'runResponder\('
pin "a responder run exists in three places only: its definition, the gated function and the fake peer's own side" 3 $APP/LinkPairRun.swift $APP/LinkDevPeer.swift $APP/LinkTransferRun.swift $APP/LinkNetwork.swift -- 'runResponder\('
pin "Devices tells the service when it is on screen" 1 $APP/LinkViews.swift -- 'link\.devicesOpened\(\)'
pin "and when it is not" 1 $APP/LinkViews.swift -- 'link\.devicesClosed\(\)'
pin "a click on Pair here opens the 2-minute window" 1 $APP/LinkService.swift -- 'pairGate\.pairClicked\(now: Self\.nowMs\(\)\)'

echo "nothing polls"
pin "no Timer, display link, dispatch timer, asyncAfter or event monitor in the link" 0 "${ALL[@]}" -- 'Timer|CADisplayLink|DispatchSourceTimer|asyncAfter|NSEvent\.add|scheduledTimer'
pin "the only sleeps are the pairing window, the offer's 2 minutes, the connect timeout, the handshake watchdog (armed on both sides: the listener's accept and the outbound pairing) and LinkIdleWatch's one (the first-frame and stall limits of a receive, the handshake, accept-wait, stall and cancel-grace limits of a send; it sleeps for the time that is left, once, and exists only while its phase lasts; and the one-shot wait before a failed listener or browser is started again, in LinkRestart.swift)" 7 "${LINK[@]}" -- 'Task\.sleep'
pin "the handshake watchdog is the 10 seconds of the handshake on both sides" 2 "${LINK[@]}" -- 'Task\.sleep\(for: \.seconds\((Self|LinkListener)\.handshakeSeconds\)\)'
pin "LinkIdleWatch has the one sleep that every other deadline of a conversation uses, and it is in LinkChannel.swift only" 1 $APP/LinkChannel.swift -- 'Task\.sleep'
pin "LinkService has one sleep of its own: the outbound handshake watchdog" 1 $APP/LinkService.swift -- 'Task\.sleep|sleep\('
pin "and it is the handshake watchdog, cancelled when the pairing ends" 1 $APP/LinkService.swift -- 'let deadline = Task \{ try\? await Task\.sleep\(for: \.seconds\(LinkListener\.handshakeSeconds\)\)'

echo "a failed listener or browser comes back, slowly, and only while it is wanted"
pin "the wait table is in one place, and the Rust twin reads it (1 s, 5 s, 30 s, then every minute)" 1 $APP/LinkRestart.swift -- 'static let delaysMs = \[1_000, 5_000, 30_000\]'
pin "the one sleep of a restart is in LinkRestart.swift and is a single wait (no loop around it)" 1 $APP/LinkRestart.swift -- 'Task\.sleep'
pin "a restart is armed in three places: the listener's loss, its relaunch that could not start, and the browser's loss" 3 $APP/LinkService.swift -- 'Wait\.arm\(ms: ms\)'
pin "Visible off ends the listener's restart, and the end of browsing the browser's (the wish goes and the wait is cancelled)" 2 $APP/LinkService.swift -- 'Restarter\.setWanted\(false\)'
pin "a restart is wanted only while the Mac is visible (the listener's loss, its relaunch, the browser's loss and its relaunch each check it: four lines, and the one that was already there)" 5 $APP/LinkService.swift -- 'settings\.visible else \{ return \}'
pin "a browser that failed is told to the service only when it failed on its own, not when stop() ended it" 1 $APP/LinkNetwork.swift -- 'if self\?\.clearIfCurrent\(b\) == true \{ self\?\.onFailed\(\) \}'

echo "a connection holds nothing until it has earned it"
pin "a run becomes the receive run in one place only, when its offer is waiting for a click (not when its connection is accepted)" 1 $APP/LinkService.swift -- '^        receiveRun = run$'
pin "no run is 'primary' by being first to connect" 0 $APP/LinkService.swift -- 'primary'
pin "established connections are counted by the caps, asked once from the run after its handshake" 1 $APP/LinkService.swift -- 'caps\.admit\('
pin "and the caps place is given back whatever way the connection ends" 1 $APP/LinkService.swift -- 'defer \{ active\[key\] = nil; caps\.release\(key\) \}'
pin "the Keychain is read in the service in these lines only: the identity and the device id (kept in memory), the paired map (reloadPeers, the one read of it), a store and a forget" 7 $APP/LinkService.swift -- 'keychain\.'
pin "no per-item re-read of the paired map and no second copy of it in the service" 0 $APP/LinkService.swift -- 'keychain\.peer\(|pairedKeys\(\)'
pin "a transfer's sender is looked up in the paired map in memory (and, on a miss, read again at most once in 5 s), after the first record was read" 1 $APP/LinkService.swift -- 'guard let peer = pairedPeer\(pre\.id\), let me = identity\(\) else'
pin "the map is read again on a miss only when the 5 s limit says so, and every read (Devices opening, Visible on, a store, a forget, a miss) is noted by it" 2 $APP/LinkService.swift -- 'readLimit\.(due|read)\(now: Self\.nowMs\(\)\)'
pin "the paired map is assigned in one place (reloadPeers), by the read that keeps the last good map when it cannot be trusted" 1 $APP/LinkService.swift -- '^ *peers = try keychain\.pairedMachines\('
pin "a failed read of the map says so in Devices, and the line goes when a read works" 2 $APP/LinkService.swift -- 'report\(Self\.peersProblem, failed: (false|true)\)'
pin "a later good read of the key clears its line" 1 $APP/LinkService.swift -- 'report\(Self\.keyProblem, failed: false\)'
pin "the listener becoming ready does not wipe a Keychain line (it goes through listenerFine, once for the start and once for the report)" 2 $APP/LinkService.swift -- 'listenerFine\(\)(;| \})'
pin "a Devices line is cleared in two places only: report (its own line, once a read worked) and listenerFine (the listener's lines, never a Keychain line)" 2 $APP/LinkService.swift -- 'problem = nil'
pin "a run and its handle let go of each other when the run is over (the run holds its hooks, the hooks hold the handle)" 1 $APP/LinkService.swift -- '^            handle\.run = nil'
pin "the run keeps its transfer place for the service (releaseAtEnd: false) and the service gives it back after receiveRun is cleared, once" 2 $APP/LinkService.swift -- 'admit: \{ caps\.admit\(key, peer: peer\.id\) \}, releaseAtEnd: false\)|if held \{ busy\.release\(peer\.id\) \}'
pin "the service reads whether the run held the place only after it ended" 1 $APP/LinkService.swift -- 'let held = await run\.holdsClaim'
order "the receive run is cleared, then the island is told, and only then is the transfer place read (a suspension) and given back: no click is accepted in the gap" $APP/LinkService.swift -- '^                if receiveRun === run \{ receiveRun = nil; gate\.endReceive\(\) \}' -- 'let held = await run\.holdsClaim'
order "the island's end comes before the read of the claim" $APP/LinkService.swift -- '^                receiveEnded\(outcome\)' -- 'let held = await run\.holdsClaim'
order "and the place is given back last" $APP/LinkService.swift -- 'let held = await run\.holdsClaim' -- 'if held \{ busy\.release\(peer\.id\) \}'
pin "Visible off cuts the outbound connection, and so does Cancel, but only while it is connecting (a run that exists is asked to cancel and cuts nothing from the service)" 2 $APP/LinkService.swift -- 'pendingConnection\?\.cancel\(\)'
pin "Cancel asks a run that exists to cancel, and cuts the connection only in the branch where there is no run yet" 1 $APP/LinkService.swift -- 'if let run = sendRun \{ run\.cancel\(\) \} else \{ pendingConnection\?\.cancel\(\); sendStatus = "Cancelled" \}'
pin "the run's own cancel is the one that sends the frame and cuts, after the grace (a cancel during the handshake is waited for graceMs, then the connection is cut; ended when the offer is out and when the run ends)" 1 $APP/LinkTransferRun.swift -- 'handshakeCut\.arm\(ms: graceMs\) \{ \[transport\] in transport\.abort\(\) \}'
pin "the handshake cut is ended in two places: when the offer is out, and when the run ends" 2 $APP/LinkTransferRun.swift -- 'handshakeCut\.end\(\)'
order "the offer goes out, then the handshake cut is ended" $APP/LinkTransferRun.swift -- 'try await channel\.sendFrame\(\.offer\(id: id' -- '^        handshakeCut\.end\(\)'
pin "forgetting a machine declines its waiting offer and cancels the file that comes in from it, and clears the card" 1 $APP/LinkService.swift -- '^        refuseTransfer\(from: id\)'
pin "the offer is declined and the file cancelled by the run (never accepted), for that machine only" 2 $APP/LinkService.swift -- 'where o\.peerId == id: run\.(respond\(accept: false\)|cancel\(\))'
order "the forgotten machine's flow is cleared (its end then touches nothing), and only then its card is taken away" $APP/LinkService.swift -- '^        receiveFlow = nil$' -- '^        present\(nil, owner: flow\)$'
pin "the card is taken away in that one place (the card's owner, from the flow the run showed)" 1 $APP/LinkService.swift -- '^        present\(nil, owner: flow\)$'
pin "a close on a connection that was cut returns at once: abort() notes it, close() looks first" 2 $APP/LinkNetwork.swift -- 'guard !closed, !aborted\.isSet else \{ return \}|nonisolated func abort\(\) \{ _ = aborted\.take\(\); connection\.cancel\(\) \}'
pin "a connection that Cancel cut is not reported as unreachable" 1 $APP/LinkService.swift -- 'self\.sendQueueCancelled \? "Cancelled" : "Could not reach'
pin "the shelf's Cancel calls the one cancelSending, and that is the only caller" 1 $APP/ShelfView.swift -- 'link\.cancelSending\(\)'

echo "nothing waits for ever (receiving)"
pin "the first frame of a connection is waited for 10 s" 1 $APP/LinkTransferRun.swift -- 'static let firstFrameMs = 10_000'
pin "only a chunk of the file coming in pushes a limit back: the receiver touches its watch in one place, while receiving and for a chunk (a stream of other frames does not keep it alive)" 1 $APP/LinkTransferRun.swift -- 'if case \.receiving = state, case \.chunk = f \{ idleWatch\?\.touch\(\) \}'
pin "and that is the only touch" 1 $APP/LinkTransferRun.swift -- 'idleWatch\?\.touch\(\)'
pin "both receiver limits cut the connection themselves before they post, so a conversation stuck in a send is freed" 2 $APP/LinkTransferRun.swift -- '\[transport\] in transport\.abort\(\); post\.yield\(\.(silent|stalled)\)'
pin "every frame the receiver sends goes through the cut (LinkChannel.sendBestEffort): the plain channel.sendFrame is the sender's own, three in all (its offer, a chunk, the end marker)" 3 $APP/LinkTransferRun.swift -- 'channel\.sendFrame\('
pin "the receiver has three sends, each through the cut: the machine's and the user's answers, and the two cancels for a file that cannot be written" 3 $APP/LinkTransferRun.swift -- 'await channel\.sendBestEffort\((f,|\.cancel\(id: currentId)'
pin "and the sender's own best-effort send is that same one" 1 $APP/LinkTransferRun.swift -- '^        await channel\.sendBestEffort\(frame, graceMs: graceMs\)'
pin "a close is given the grace too: the cut is armed with the grace and calls abort, and is stopped when the close returns" 2 $APP/LinkTransferRun.swift -- 'let cut = LinkIdleWatch\(ms: graceMs\) \{ \[transport\] in transport\.abort\(\) \}|^            cut\.stop\(\)'
order "the cut is armed before the close it guards" $APP/LinkTransferRun.swift -- 'let cut = LinkIdleWatch\(ms: graceMs\) \{ \[transport\] in transport\.abort\(\) \}' -- 'await transport\.close\(\)'
order "and stopped after it" $APP/LinkTransferRun.swift -- 'await transport\.close\(\)' -- '^            cut\.stop\(\)'
pin "a peer gets one decline per connection: the second ends it" 1 $APP/LinkTransferRun.swift -- 'if declines > 1 \{ transport\.abort\(\); return await finish'
pin "the run gives its claim back at its end unless its caller said it will" 1 $APP/LinkTransferRun.swift -- 'if holdsClaim, hooks\.releaseAtEnd \{'

echo "nothing accepts for the user"
pin "no literal accept in the service, the run or the network" 0 $APP/LinkService.swift $APP/LinkTransferRun.swift $APP/LinkNetwork.swift -- 'respond\(accept: true\)|respondOffer\(accept: true\)'
pin "the only call that accepts is the service's respondOffer, which the Accept button calls (the run is the receive run, from receiveRun)" 1 $APP/LinkService.swift -- 'run\.respond\(accept: accept\)'
pin "the Accept button is the only caller of respondOffer(true) (it passes the card it was meant for)" 1 $APP/LinkViews.swift -- 'actions\.respondOffer\(true, card\?\.shown\)'
pin "only the receive run turns a click into an accept event" 1 $APP/LinkTransferRun.swift -- 'nonisolated func respond\(accept: Bool\)'
pin "and it does so from that one function" 1 $APP/LinkTransferRun.swift -- 'post\.yield\(\.flow\(\.user\(accept \? \.accept : \.decline\)\)\)'

echo "no name in a log"
pin "every line the link logs is a fixed sentence" 0 "${ALL[@]}" -- 'appendAppLog\("link\.log", .*\\\('
other_logs=$( (grep -h 'appendAppLog(' "${ALL[@]}" || true) | (grep -v 'appendAppLog("link\.log"' || true) | wc -l | tr -d ' ')
if [ "$other_logs" = 0 ]; then echo "  ✓ the link logs through link.log only"; else echo "  ✗ the link logs somewhere else ($other_logs lines)"; fail=$((fail + 1)); fi
pin "no print or NSLog in the link" 0 "${LINK[@]}" -- '(^|[^a-zA-Z.])(print|NSLog|debugPrint)\('

echo "secrets only in the Keychain"
pin "the app's Keychain service name is the same text in both places" 1 $APP/ClaudeService.swift -- 'static let service = "io\.github\.aikusan\.notchmeow"$'
pin "and in the link, for Release and App Store builds" 1 $APP/LinkKeychain.swift -- 'static let appService = "io\.github\.aikusan\.notchmeow"$'
pin "a Debug build has a Keychain service of its own for the link, chosen at compile time" 1 $APP/LinkKeychain.swift -- 'static let appService = "io\.github\.aikusan\.notchmeow\.debug"$'
pin "that choice is under DEBUG and not APPSTORE" 1 $APP/LinkKeychain.swift -- '^    #if DEBUG && !APPSTORE$'
pin "no other link file names a Keychain service or reads the app's own Keychain wrapper" 0 $APP/LinkService.swift $APP/LinkViews.swift $APP/LinkSettings.swift $APP/LinkFiles.swift $APP/LinkNetwork.swift $APP/LinkChannel.swift $APP/LinkPairRun.swift $APP/LinkTransferRun.swift -- 'SystemSecretStore\(service|Keychain\.(save|load|service)|aikusan\.notchmeow'
pin "the fake peer keeps its keys in memory only" 1 $APP/LinkDevPeer.swift -- 'LinkKeychain\(store: MemorySecretStore\(\)\)'
pin "nothing of the link writes a file but the received file's sink" 0 "${LINK[@]}" -- '\.write\(to:|createFile\(|\.write\(contentsOf'
pin "the link stores nothing in UserDefaults but its two settings" 2 $APP/LinkSettings.swift -- 'store\.set\('
pin "no private key is turned into text or data outside the Keychain and the handshake" 0 $APP/LinkService.swift $APP/LinkViews.swift $APP/LinkFiles.swift -- 'rawRepresentation'

echo "files"
pin "a received file is created exclusively, never through a link, private" 1 $APP/LinkFiles.swift -- 'O_WRONLY \| O_CREAT \| O_EXCL \| O_NOFOLLOW \| O_CLOEXEC, 0o600'
pin "quarantine is set by hand on the GitHub build only" 1 $APP/LinkFiles.swift -- 'static let quarantineByHand = true'
pin "a failed transfer removes its partial file in one place only (LinkFiles' removePartial, unlink of the file the sink made), and nothing else deletes a file" 1 "${LINK[@]}" -- 'unlink\(|removeItem|trashItem'
pin "the folder is Downloads/NotchMeow" 1 $APP/LinkFiles.swift -- 'appendingPathComponent\("NotchMeow", isDirectory: true\)'
pin "no network fetch anywhere in the link but the sockets" 0 "${ALL[@]}" -- 'URLSession|URLRequest|Data\(contentsOf: URL\(string'

echo "the Accept card is an alert like an approval"
pin "it holds the island open (both build variants)" 2 $APP/IslandWindowController.swift -- 'AppState\.shared\.linkHoldsIsland'
pin "it is an alert to the desktop cat" 1 $APP/DesktopCatController.swift -- 'transferOffer: state\.linkOfferPending'
pin "it opens the island even when hidden" 1 $APP/LinkService.swift -- 'name: \.hookExpand, object: IslandView\.link'
pin "the island knows the .link view" 1 $APP/IslandViewContent.swift -- 'case \.link:'
pin "Settings has a Devices page" 1 $APP/SettingsView.swift -- 'DevicesSettingsSection\(\)'

echo "the build"
pin "the App Store entitlements ask for the server and Downloads" 2 NotchBuddy/Resources/NotchMeowAppStore.entitlements -- 'network\.server|files\.downloads\.read-write'
pin "the GitHub entitlements stay as they were (apple events only)" 1 NotchBuddy/Resources/NotchMeow.entitlements -- '<key>com\.apple\.security'
pin "both Info.plists announce _notchmeow._tcp" 2 NotchBuddy/Resources/Info.plist NotchBuddy/Resources/InfoAppStore.plist -- '<string>_notchmeow\._tcp</string>'
pin "both explain the local network use" 2 NotchBuddy/Resources/Info.plist NotchBuddy/Resources/InfoAppStore.plist -- 'Visible on this network'
pin "the project spec says the same for both targets" 2 NotchBuddy/project.yml -- '- _notchmeow\._tcp'
pin "the Debug fake peer is Debug-only" 1 $APP/LinkDevPeer.swift -- '^#if DEBUG && !APPSTORE'
pin "and its menu item too" 1 $APP/AppDelegate.swift -- 'Link \(Debug\)'

if [ "$fail" = 0 ]; then echo; echo "All tests passed."; else echo; echo "$fail test(s) failed."; exit 1; fi
