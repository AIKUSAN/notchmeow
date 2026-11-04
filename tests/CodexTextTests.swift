import Foundation

// The chips, the words and the note buttons of the OpenAI plan, against tests/fixtures/ai/codex/labels.json and copy.json.
// Pure: no codex is run and nothing here opens ~/.codex.

@main
@MainActor
enum CodexTextTests {
    static func main() {
        chips()
        copyCases()
        notes()
        routing()
        T.finish()
    }

    // MARK: - labels.json

    static func chips() {
        T.section("The chips (labels.json)")
        let labels = T.fixture("codex/labels.json")
        for c in labels["modelChip"] as! [[String: Any]] {
            let name = c["name"] as! String
            T.check("model chip: \(name)", CodexText.modelChip(mode: c["mode"] as? String), c["expect"] as! String)
        }
        for c in labels["levelChip"] as! [[String: Any]] {
            let name = c["name"] as! String
            let level = CodexLevel(rawValue: c["level"] as! String)!
            T.check("level chip: \(name)", CodexText.levelChip(level, folder: c["folder"] as? String), c["expect"] as! String)
        }
        T.check("the row's label never says Codex", (labels["rowLabel"] as! String).contains("Codex"), false)
    }

    // MARK: - copy.json

    static func copyCases() {
        T.section("Every copy.json case")
        let data = T.fixture("codex/copy.json")
        for (index, c) in (data["cases"] as! [[String: Any]]).enumerated() {
            let code = c["code"] as! String
            let label = "copy #\(index) \(code)"
            let resetsAt = (c["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
            let timeZone = TimeZone(identifier: c["timeZone"] as? String ?? "UTC")!
            let locale = Locale(identifier: c["locale"] as? String ?? "en_US")
            let got = CodexText.copy(code: code, resetsAt: resetsAt, timeZone: timeZone, locale: locale)
            T.check("\(label): text", got?.text, c["text"] as? String)
            T.check("\(label): action", got?.action, c["action"] as? String)
        }
    }

    // MARK: - The notes

    static func notes() {
        T.section("The notes and their buttons")
        let signedOut = CodexText.message(for: AIError(kind: .auth, code: "nm_codex_signed_out"))
        T.check("signed out: the note is the copy plus the sign-in line",
                signedOut?.text, "Codex is signed out. Open your terminal and run `codex login`. NotchMeow opens nothing.")
        T.check("signed out: no button", signedOut?.action == nil, true)
        T.check("missing: the install guide",
                CodexText.message(for: AIError(kind: .unreachable, code: "nm_codex_missing"))?.action, .installCodex)
        T.check("old: the update guide",
                CodexText.message(for: AIError(kind: .badRequest, code: "nm_codex_old"))?.action, .updateCodex)
        T.check("crashed: try again",
                CodexText.message(for: AIError(kind: .interrupted, code: "nm_codex_crashed"))?.action, .tryAgain)
        let exceeded = CodexText.message(for: AIError(kind: .badRequest, code: "nm_level_exceeded"))
        T.check("level exceeded: its text",
                exceeded?.text, "Codex tried to do more than this level allows, so NotchMeow stopped it.")
        T.check("level exceeded: no button", exceeded?.action == nil, true)
        T.check("a Claude Code code is not Codex's",
                CodexText.message(for: AIError(kind: .unreachable, code: "nm_claude_missing")) == nil, true)
    }

    // MARK: - AIMessages routing

    static func routing() {
        T.section("The chat's own notes (AIMessages.error)")
        let target = ChatTarget(provider: .codexPlan, model: "", placement: .cloud)
        T.check("plan limit: the plan's words",
                AIMessages.error(AIError(kind: .billing, code: "nm_plan_limit"), target: target).text,
                "Your OpenAI plan's limit was reached.")
        T.check("busy: the shared words under the OpenAI name",
                AIMessages.error(AIError(kind: .overloaded), target: target).text,
                "OpenAI is still busy. Try again in a moment.")
    }
}
