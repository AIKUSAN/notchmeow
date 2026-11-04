import AppKit

#if !APPSTORE

/// The buttons that open something outside NotchMeow: Terminal for signing in, Anthropic's install page.
@MainActor
enum ClaudeCodeActions {
    /// "Sign in": Terminal runs `claude auth login`, which finishes in the browser. NotchMeow never sees the login.
    /// With no Claude Code to run, the install page opens instead.
    static func signIn() {
        guard let executable = AppState.shared.claudeCodeStatus.executable,
              let script = ClaudeCodeSignIn.write(executable: executable, into: HookServer.supportDir.path) else {
            return openInstallGuide()
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: script))
    }

    static func openInstallGuide() {
        if let url = URL(string: ClaudeCodeLocator.installGuide) { NSWorkspace.shared.open(url) }
    }
}

#endif
