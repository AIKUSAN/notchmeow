import Foundation

// What Settings → Agents tells the user after "Confirm & write" (or Uninstall): one line, shown right under the buttons of the box the user clicked in. The words only; the view is HookNoteLine in SettingsView.swift.
// Foundation only, tested by scripts/test-hook-install-note.sh.

struct HookNote: Equatable {
    /// false → shown in red
    let ok: Bool
    let text: String
}

enum HookInstallNote {
    /// "✓ Hooks installed in ~/.claude/settings.json. Backup: settings.json.bak-20261017-123456" (the name `ConfigFileWrite.writeWithBackup` returned), or that the file was new.
    static func installed(_ what: String, file: String, backup: String?) -> HookNote {
        HookNote(ok: true, text: "✓ \(what) in \(file). " + (backup.map { "Backup: \($0)" } ?? "No backup: the file did not exist."))
    }

    static func removed(_ what: String, file: String) -> HookNote {
        HookNote(ok: true, text: "✓ \(what) removed from \(file).")
    }

    /// An uninstall that found nothing of NotchMeow's: said as it is, never reported as a removal.
    static func absent(_ what: String, file: String) -> HookNote {
        HookNote(ok: true, text: "No \(what) found in \(file): nothing changed.")
    }

    static func failure(_ error: Error) -> HookNote {
        HookNote(ok: false, text: "❌ \(error.localizedDescription)")
    }
}
