import Foundation

// The project cats as they are stored (P-mac, Task 4): one key per project folder, `cat.projectCat.<folder name>`, holding a cat ID. It is the only thing the
// Projects feature ever stores. Every value read goes through `ProjectsRules.cleanProjectCats`, so a hand-edited or half-written key is dropped on load and
// never used. The rules are in `ProjectsRules` (the port of shared/projects-core.js); this file only reads and writes the keys, through the same backing the
// Cat settings use (UserDefaults in the app, a dictionary in the tests).

enum ProjectCatSettings {
    static let prefix = "cat.projectCat."

    static func key(_ catKey: String) -> String { prefix + catKey }

    /// What is stored, cleaned: `[folder name: cat ID]`. Reading never writes.
    static func load(from store: any CatSettingsBacking) -> [String: String] {
        var raw: [String: Any] = [:]
        for key in store.allKeys() where key.hasPrefix(prefix) {
            if let v = store.object(forKey: key) { raw[String(key.dropFirst(prefix.count))] = v }
        }
        return ProjectsRules.cleanProjectCats(raw)
    }

    /// Writes the keys whose cat changed from `old`, in key order, and removes every stored project-cat key that `cats` no longer holds (a project
    /// "Reset" dropped, a key the clean-up refused). `cats` is cleaned by the caller, so nothing that did not go through the clean-up is stored.
    static func save(_ cats: [String: String], to store: any CatSettingsBacking, replacing old: [String: String]) {
        for k in ProjectsRules.sortedCatKeys(cats) where old[k] != cats[k] {
            store.set(cats[k], forKey: key(k))
        }
        for key in store.allKeys() where key.hasPrefix(prefix) && cats[String(key.dropFirst(prefix.count))] == nil {
            store.removeObject(forKey: key)
        }
    }
}

enum ProjectCatList {
    /// A project that is live now, in pill order, with its folder name (the name the notch shows).
    struct Live: Equatable, Sendable {
        var catKey: String
        var name: String
    }

    /// One row of Settings' "Project cats": the folder name, its name for display, the cat it shows, whether that cat is stored and whether a live project has it.
    struct Row: Equatable, Sendable {
        var catKey: String
        var name: String
        var cat: String
        var stored: Bool
        var live: Bool
    }

    /// The live projects first, in their order, one row per folder name (two live projects with one name make one row, under the first name); then each
    /// stored folder name that no live project has, in UTF-16 order, named by itself. A row's cat is the stored one, else the one the project gets with the
    /// Main cat taken (`ProjectsRules.projectCatOf`). Nothing is stored here.
    static func rows(live: [Live], stored: [String: String], main: String) -> [Row] {
        let held = ProjectsRules.cleanProjectCats(stored)
        var seen: Set<String> = []
        var out: [Row] = []
        for project in live where !seen.contains(project.catKey) {
            seen.insert(project.catKey)
            let shown = ProjectsRules.projectCatOf(project.catKey, projectCats: held, mainCat: main)
            out.append(Row(catKey: project.catKey, name: project.name, cat: shown.cat, stored: shown.stored, live: true))
        }
        for key in ProjectsRules.sortedCatKeys(held) where !seen.contains(key) {
            out.append(Row(catKey: key, name: key, cat: held[key] ?? "", stored: true, live: false))
        }
        return out
    }
}
