import Foundation

// MARK: - Island Mode

enum IslandMode: String, CaseIterable {
    case hidden, compact, expanded
}

// MARK: - Island View

enum IslandView: String, CaseIterable {
    case overview, empty, approval, question, error, finished
    case confused, upload, uploading, choose, mail, prompt
    case searching, result, note, settings, greeting
    case shelf   // sub-project G1: the files parked in the notch
    case link    // sub-project G2: a pairing card, the Accept card for a file from another machine, its progress and the end of either
    /// A note from the sidekick (a recap, a nudge): `SidekickView`. It opens the way a finished task does and goes by itself.
    case sidekick
    /// The Projects screen (sub-project P-mac): every project and its sessions, in the island (`ProjectsScreen.swift`).
    case projects
}

// MARK: - Bot State

enum BotState: String, CaseIterable {
    case idle, working, thinking, searching
    case approval, question, error, finished
    case ratelimit, sleeping, dizzy
}

// MARK: - Bot Emote

enum BotEmote: String, CaseIterable {
    case love, surprised, proud, wink, yawn, happy, annoyed
}

// MARK: - Approval info (pending PermissionRequest from Claude Code)

struct ApprovalInfo: Sendable {
    var sessionId: String
    var tool: String
    var command: String
    /// tool_input serialized to JSON with sortedKeys, "" if absent — used to match PostToolUse.
    var inputKey: String
    /// Pill that owns this approval: "integration_claude", "agent_cursor", or "agent_codex".
    var pillId: String
    /// The subagent that asked (the request's `agent_id`), when one did: its kitten waits on this approval.
    var subagentId: String? = nil
    /// Where the user is, for the notes "Handled in …" and "Still waiting in …" (`HookOrigin.hostName`).
    var host: String = "VS Code"
    /// What the sidekick says about the request (`SidekickExplain`): the basename it names (or ""), how risky it is ("low", "medium" or "high"; "" while it has not been explained) and one
    /// fixed grey line under the command. It labels only: the card's buttons are the only way to answer.
    var target: String = ""
    var risk: String = ""
    var line: String = ""
    /// One per request (made when the request is built): the card's 600 ms click guard starts again for each new one (`ApprovalClickGuard`).
    var token = UUID()
}

// MARK: - Pill badge (shown on pill edge when non-focused task has an alert)

enum PillBadge { case approval, finished, error }

// MARK: - Agent Task

struct AgentTask: Identifiable, Equatable {
    var id: String
    var name: String
    var color: String          // hex
    var state: BotState
    var stepIndex: Int = 0
    var steps: [String]
    var source: AgentSource
    var isIntegration: Bool = false  // true for persistent integration pills
    var pillBadge: PillBadge? = nil  // alert badge shown on pill when not focused
    var sessionCwd: String?  = nil  // last known working directory (Claude Code sessions)
    var finalLine: String?   = nil  // last assistant message shown as static text after Stop
}

enum AgentSource: Equatable {
    case claudeCode
    case n8n
    case agent   // third-party agent via nm_agent field
}

// MARK: - Chat provider

/// Raw values are the shared provider IDs (`AIProviderID`). Existing raw values and pill IDs never change.
enum ChatProvider: String, CaseIterable, Codable {
    case anthropic = "anthropic"
    case google    = "google"
    case openai    = "openai"
    case ollama    = "ollama"
    case lmstudio  = "lmstudio"
    case llamacpp  = "llamacpp"
    case jan       = "jan"
    case apple     = "apple"
    case custom    = "custom"
    case claudeCode = "claudeCode"
    case codexPlan = "codexPlan"

    init(_ id: AIProviderID) { self.init(rawValue: id.rawValue)! }

    var providerID: AIProviderID { AIProviderID(rawValue: rawValue)! }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .google:    "Google"
        case .openai:    "OpenAI"
        case .ollama:    "Ollama"
        case .lmstudio:  "LM Studio"
        case .llamacpp:  "llama.cpp"
        case .jan:       "Jan"
        case .apple:     "Apple on-device"
        case .custom:    "Local server"
        case .claudeCode: "Claude plan"
        case .codexPlan: "OpenAI"
        }
    }

    var accentHex: String {
        switch self {
        case .anthropic: "#E07950"
        case .google:    "#4285F4"
        case .openai:    "#10A37F"
        case .ollama:    "#FACC15"
        case .lmstudio:  "#A3E635"
        case .llamacpp:  "#F59E0B"
        case .jan:       "#38BDF8"
        case .apple:     "#C8CDD4"
        case .custom:    "#94A3B8"
        case .claudeCode: "#E07950"
        case .codexPlan: "#10A37F"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: AICatalog.info(.anthropic).defaultModel!
        case .google:    "gemini-2.0-flash"
        case .openai:    AICatalog.info(.openai).defaultModel!
        case .ollama:    "llama3.2"
        case .lmstudio:  "local-model"
        case .apple:     "system"
        case .claudeCode: "sonnet"
        case .llamacpp, .jan, .custom, .codexPlan: ""
        }
    }

    var keychainKey: String {
        switch self {
        case .anthropic: "anthropic-api-key"
        case .google:    "google-api-key"
        case .openai:    "openai-api-key"
        default:         ""
        }
    }

    var isLocal: Bool { !providerID.isCloud }

    /// Pills exist for the five original providers only.
    var pillID: String? {
        switch self {
        case .anthropic: "ai_anthropic"
        case .google:    "ai_google"
        case .openai:    "ai_openai"
        case .ollama:    "ai_ollama"
        case .lmstudio:  "ai_lmstudio"
        default:         nil
        }
    }

    init?(pillID: String) {
        switch pillID {
        case "ai_anthropic": self = .anthropic
        case "ai_google":    self = .google
        case "ai_openai":    self = .openai
        case "ai_ollama":    self = .ollama
        case "ai_lmstudio":  self = .lmstudio
        default:             return nil
        }
    }
}

// MARK: - View dimensions (from VIEWS in prototype)

struct ViewLayout {
    let height: CGFloat
    let botX: CGFloat
    let botY: CGFloat?         // nil = auto-centered
    let botDiameter: CGFloat
    let agentMode: AgentLayoutMode
}

enum AgentLayoutMode {
    case none, grid, pills, column
}

// MARK: - Constants (from NW, NH, EW in prototype)

enum IslandConst {
    static let notchWidth: CGFloat  = IslandScreenGeometry.fallbackNotchWidth
    static let notchHeight: CGFloat = 32
    static let expandedWidth: CGFloat = 640
    static let earRadius: CGFloat   = 14
    static let roundedCorner: CGFloat = 14    // hidden/peek/compact
    static let expandedCorner: CGFloat = 22

    static let viewLayouts: [IslandView: ViewLayout] = [
        // Home is the reference: height 150
        .overview:  ViewLayout(height: 160, botX: 68,  botY: nil, botDiameter: 58, agentMode: .pills),
        // All non-chat views match home height (150) — law
        .empty:     ViewLayout(height: 160, botX: 70,  botY: nil, botDiameter: 62, agentMode: .none),
        .approval:  ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 56, agentMode: .column),
        .question:  ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 56, agentMode: .column),
        .error:     ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 58, agentMode: .column),
        .finished:  ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 58, agentMode: .column),
        .confused:  ViewLayout(height: 160, botX: 76,  botY: nil, botDiameter: 66, agentMode: .column),
        .upload:    ViewLayout(height: 176, botX: 140, botY: 104, botDiameter: 62, agentMode: .column),
        .uploading: ViewLayout(height: 176, botX: 46,  botY: 118, botDiameter: 20, agentMode: .none),
        .choose:    ViewLayout(height: 176, botX: 60,  botY: 101, botDiameter: 52, agentMode: .column),
        .mail:      ViewLayout(height: 240, botX: 56,  botY: nil, botDiameter: 46, agentMode: .column),
        .prompt:    ViewLayout(height: 160, botX: 52,  botY: nil, botDiameter: 44, agentMode: .column),
        .searching: ViewLayout(height: 160, botX: 52,  botY: nil, botDiameter: 44, agentMode: .column),
        .result:    ViewLayout(height: 160, botX: 52,  botY: nil, botDiameter: 44, agentMode: .column),
        .note:      ViewLayout(height: 160, botX: 60,  botY: nil, botDiameter: 50, agentMode: .column),
        .sidekick:  ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 56, agentMode: .column),
        // The Projects screen (P-mac): the cat keeps the left, the list of projects starts at the top
        .projects:  ViewLayout(height: 240, botX: 54,  botY: nil, botDiameter: 46, agentMode: .none),
        .settings:  ViewLayout(height: 160, botX: 54,  botY: nil, botDiameter: 46, agentMode: .none),
        // The shelf (G1): the cat keeps the left, the content starts at 90
        .shelf:     ViewLayout(height: 176, botX: 54,  botY: nil, botDiameter: 46, agentMode: .none),
        // The link card (G2): the same place for the cat as an approval, the content starts at 116 like the approval's
        .link:      ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 56, agentMode: .none),
        // Greeting: bot drawn by GreetingCanvasView; no BotPlacement needed
        .greeting:  ViewLayout(height: 150, botX: 320, botY: 90,  botDiameter: 0,  agentMode: .none),
    ]

    // Project colors — keyed by lowercase display name or slug
    static let projectColors: [String: String] = [:]

    static let fallbackColors = ["#22C55E", "#EAB308", "#60A5FA", "#E879F9"]

    /// Returns the fixed project color for a display name, or a stable fallback.
    static func colorForProject(_ name: String) -> String {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let c = projectColors[key] { return c }
        // partial match (e.g. "my-app-api" → "my-app")
        for (k, c) in projectColors where key.hasPrefix(k) || key.contains(k) { return c }
        return fallbackColors[abs(name.hashValue) % fallbackColors.count]
    }

    // State card wash colors (radial gradient from bottom)
    static let washColors: [IslandView: String] = [
        .approval:  "rgba(245,165,36,0.42)",
        .question:  "rgba(34,211,238,0.38)",
        .error:     "rgba(244,80,94,0.55)",
        .finished:  "rgba(52,211,153,0.5)",
        .confused:  "rgba(244,114,182,0.55)",
        .searching: "rgba(99,102,241,0.5)",
        .result:    "rgba(52,211,153,0.22)",
        .prompt:    "rgba(99,102,241,0.22)",
    ]
}
