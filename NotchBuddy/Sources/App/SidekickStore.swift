import Combine
import Foundation

// The app's sidekick settings: loaded from the store (UserDefaults in the app) when the app starts and saved on every change. Every value goes through `SidekickSettings.clean` on the way in,
// so nothing that did not is stored or used. The pure part (the clean-up, the keys, load and save, the dismissal rules) is `SidekickSettings`; this is the app's single holder of the result.
// Tests build their own store on a dictionary and never touch `UserDefaults.standard`.

@MainActor
final class SidekickStore: ObservableObject {
    /// The app's settings, on `UserDefaults.standard`.
    static let shared = SidekickStore()

    @Published private(set) var settings: SidekickSettings
    private let backing: any CatSettingsBacking

    init(backing: any CatSettingsBacking = UserDefaults.standard) {
        self.backing = backing
        settings = SidekickSettings.load(from: backing)
    }

    /// Changes the settings. The closure edits a copy; the copy is cleaned, and when it differs from what is held it is published and saved (only the keys that changed).
    func update(_ change: (inout SidekickSettings) -> Void) {
        var next = settings
        change(&next)
        next = SidekickSettings.clean(next.json)
        guard next != settings else { return }
        next.save(to: backing, replacing: settings)
        settings = next
    }

    /// "Recaps and nudges". Off means no recap and no stuck nudge; the permission line and the risk badge have no switch.
    func setOn(_ on: Bool) { update { $0 = $0.withOn(on) } }
    /// "Nicer wording from a local model". Off means only the templates.
    func setLocal(_ local: Bool) { update { $0 = $0.withLocal(local) } }
    /// A click on Not now, OK or ×.
    func dismiss(_ kind: String) { update { $0 = $0.dismissed(kind) } }
    /// Settings → AI and chat → Sidekick → Unmute.
    func unmute(_ kind: String) { update { $0 = $0.unmuted(kind) } }
    /// Settings → AI and chat → Sidekick: a kind's switch turned off.
    func mute(_ kind: String) { update { $0 = $0.muting(kind) } }
}
