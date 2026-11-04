import AppKit
import Darwin
import SwiftUI

// How much CPU the island's own SwiftUI costs in a given state, without launching NotchMeow: the app's own root view (IslandRootView) on the app's own AppState, in a window of its own that is on screen
// but invisible (alpha 0.02, no mouse, no activation), so the display really ticks the TimelineViews as it does in the app. The process's CPU time is read before and after a few seconds and printed as
// a share of one core. A made-up state is put in AppState; nothing is saved, nothing is sent, no hook socket is opened.
//   bash scripts/measure-island-cpu.sh [--state compact|overview|approval|approval-high|question|all] [--seconds 8]
// Run it through the .sh: it compiles the whole app but NotchBuddyApp.swift, in a home folder of its own. A window the size of the island's panel flickers at the top of the main screen for the length of the run.

@main
struct MeasureIslandCPU {
    static func cpuSeconds() -> Double {
        var u = rusage(); getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_utime.tv_sec) + Double(u.ru_utime.tv_usec) / 1e6 + Double(u.ru_stime.tv_sec) + Double(u.ru_stime.tv_usec) / 1e6
    }

    @MainActor static func main() {
        var which = "approval", seconds = 8.0
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--state": which = it.next() ?? which
            case "--seconds": seconds = Double(it.next() ?? "") ?? seconds
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let state = AppState.shared
        let task = AgentTask(id: "integration_claude", name: "Claude Code", color: "#E07950", state: .approval, steps: [], source: .claudeCode)
        state.tasks = [task]
        state.focusId = task.id
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let host = NSHostingView(rootView: IslandRootView().environmentObject(state))
        let win = NSPanel(contentRect: NSRect(x: screen.frame.midX - 360, y: screen.frame.maxY - 320, width: 720, height: 320), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        win.isOpaque = false; win.backgroundColor = .clear; win.ignoresMouseEvents = true; win.level = .statusBar; win.alphaValue = 0.02
        win.contentView = host
        win.orderFrontRegardless()

        /// Puts the island in one made-up state.
        func configure(_ which: String) -> Bool {
            state.pendingApproval = nil; state.pendingQuestion = nil
            switch which {
            case "compact": state.mode = .compact
            case "overview": state.view = .overview; state.mode = .expanded
            case "approval", "approval-high":
                let command = which == "approval" ? "npm test" : "rm -rf build"
                let why = SidekickExplain.explain(agent: "integration_claude", tool: "Bash", input: ["command": command], cwd: "/Users/me/proj", home: "/Users/me")
                state.pendingApproval = ApprovalInfo(sessionId: "measure", tool: "Bash", command: command, inputKey: "", pillId: task.id, risk: why.risk, line: why.line)
                state.view = .approval; state.mode = .expanded
            case "question":
                state.pendingQuestion = AskQuestion.parse(toolInput: ["questions": [["question": "Which one?", "header": "Pick", "options": [["label": "A", "description": "first"], ["label": "B", "description": "second"]], "multiSelect": false]]])
                state.view = .question; state.mode = .expanded
            default: return false
            }
            return true
        }
        let states = which == "all" ? ["compact", "overview", "approval", "approval-high", "question"] : [which]
        // The app's own loop, NSApp.run(), drives the run: RunLoop.run(until:) without it spins the display cycle at a full core by itself (an empty Canvas on a 120 Hz timeline read 110 % that way and 4 % under NSApp.run).
        let secs = seconds
        Task { @MainActor in
            for name in states {
                guard configure(name) else { FileHandle.standardError.write(Data("unknown state \(name)\n".utf8)); exit(2) }
                try? await Task.sleep(for: .seconds(2))   // warm up: the spring that opens the island, the first frames
                let c0 = cpuSeconds(), t0 = Date()
                try? await Task.sleep(for: .seconds(secs))
                let share = (cpuSeconds() - c0) / Date().timeIntervalSince(t0) * 100
                print(String(format: "state=%@ cpu=%.1f%% of one core over %.0f s", name, share, secs))
            }
            win.orderOut(nil)
            exit(0)
        }
        app.run()
    }
}
