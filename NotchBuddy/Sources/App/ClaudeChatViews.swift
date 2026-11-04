import SwiftUI
import AppKit

// The Claude Code engine's views: the level chip next to the model chip, the step rows and the approval card in the
// chat, and the "Use my Claude plan" half of Settings' Connect Claude box. They are built from the pieces the app
// already has (`TickerRowView`, `CodeBlock`, `PrimaryButton`, `SecondaryButton`, `AgentWho`) and follow the model
// chip's look. The App Store build compiles all of it out.

#if !APPSTORE

// MARK: - Steps in the chat

/// The steps Claude Code took for one reply: the session view's own step rows, one per step.
struct ClaudeStepsView: View {
    let steps: [ChatStep]

    private static let scale: CGFloat = 11.5 / 13   // the ticker's completed-row size

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(steps, id: \.id) { step in
                TickerRowView(text: Self.words(step), phase: step.state == .running ? 0 : 1, isActive: step.state == .running)
                    .scaleEffect(Self.scale, anchor: .leading)
                    .frame(height: 20)
            }
        }
    }

    /// "Reads · README.md", with a mark when it failed or was stopped.
    static func words(_ step: ChatStep) -> String {
        let line = SessionStepText.line(tool: step.tool, input: step.input)
        switch step.state {
        case .running, .done: return line
        case .failed: return line + " ⚠"
        case .stopped: return line + " · stopped"
        }
    }
}

// MARK: - The approval card in the chat

/// "Claude needs permission" for one step, with Allow and Deny. The island's own approval card, in the chat.
struct ChatApprovalCard: View {
    let approval: ChatApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AgentWho(task: nil, label: "Claude needs permission")
            CodeBlock(text: approval.target)
            HStack(spacing: 8) {
                SecondaryButton("Deny") { HookServer.shared.sendChatApprovalDecision("deny", id: approval.id) }
                PrimaryButton("Allow") { HookServer.shared.sendChatApprovalDecision("allow", id: approval.id) }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#F5B544").opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - The level chip

/// Chat only, Read-only or Agent, per chat. Next to the model chip, in its look. Every new chat starts at Chat only;
/// Read-only and Agent ask for a folder. It cannot change while a reply is streaming.
struct ClaudeLevelChip: View {
    @ObservedObject var state: AppState
    @State private var showMenu = false

    var body: some View {
        Button { showMenu.toggle() } label: {
            HStack(spacing: 5) {
                Text(CompanionChrome.folderLabel(levelKey: state.claudeQuickHold ? "none" : state.claudeLevel.key, folder: state.claudeLevel.folder))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Color(hex: "#7B8089"))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(Color(hex: "#5C6370"))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(state.chatStreaming)
        .opacity(state.chatStreaming ? 0.5 : 1)
        .accessibilityLabel(CompanionChrome.folderHelp)
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            ClaudeLevelMenu(state: state, isPresented: $showMenu).frame(width: 290)
        }
    }
}

struct ClaudeLevelMenu: View {
    @ObservedObject var state: AppState
    @Binding var isPresented: Bool

    // Looked up when the menu opens, never on a timer.
    @State private var hooksReady = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row(CompanionChrome.folderRows[0], "Answers, dropped files, web search and fetch.", isCurrent: state.claudeLevel == .chatOnly && !state.claudeQuickHold) {
                choose(.chatOnly)
            }
            row(CompanionChrome.folderRows[1], "Also reads and searches files in a folder you choose.", isCurrent: isReadOnly) {
                pickFolder { choose(.readOnly(folder: $0)) }
            }
            row(CompanionChrome.folderRows[2], "Also edits files and runs commands there, each step behind a card.", isCurrent: isAgent, enabled: hooksReady) {
                pickFolder { choose(.agent(folder: $0)) }
            }
            if !hooksReady {
                Text(ClaudeAgentReadiness.hooksNote)
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#8A8F98"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
        }
        .padding(10)
        .background(Color(hex: "#16171B"))
        .onAppear { hooksReady = ClaudeAgentReadiness.check(hooksInstalled: HookServer.claudeHooksInstalled()) == .ready }
    }

    // A held chat shows No tools (Folder), so no level row is lit while the hold is on; a pick still works and ends the hold.
    private var isReadOnly: Bool { if case .readOnly = state.claudeLevel { !state.claudeQuickHold } else { false } }
    private var isAgent: Bool { if case .agent = state.claudeLevel { !state.claudeQuickHold } else { false } }

    private func row(_ title: String, _ detail: String, isCurrent: Bool, enabled: Bool = true,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(title).font(.system(size: 12, weight: .medium))
                        .foregroundColor(isCurrent ? Color(hex: "#E07950") : Color(hex: "#C8CDD4"))
                    Spacer()
                    if isCurrent {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundColor(Color(hex: "#E07950"))
                    }
                }
                Text(detail).font(.system(size: 10.5)).foregroundColor(Color(hex: "#8A8F98"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrent ? Color(hex: "#E07950").opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func choose(_ level: ClaudeCodeLevel) {
        state.claudeLevel = level
        // A pick is the user's own choice: it ends the hold, and the next turn runs at the picked level.
        state.claudeQuickHold = false
        isPresented = false
        SoundEngine.shared.play("blip")
    }

    /// The chat's working folder. NotchMeow is an accessory app: it comes forward for the panel and gives the island
    /// back afterwards.
    private func pickFolder(then use: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.message = "Choose the folder Claude may work in"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { use(url.path) }
    }
}

#endif
