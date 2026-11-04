// Finding the Claude desktop app on Windows, for the pill's Open action (the Mac opens it by its bundle ID). Pure and platform-neutral so the Linux container tests it: the Windows
// side (platform/windows.rs `open_claude_app`) supplies the folders, the "does it exist" test and the Start-menu listing, and starts what this module picks. Anthropic ships no
// desktop app for Linux, so there `platform::open_claude_app` finds nothing and the page hides the button.

use std::path::{Path, PathBuf};

/// How to start the app.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Launch {
    /// A program or a Start-menu shortcut that exists on disk: started by the shell, which also brings an already-running instance forward.
    Path(PathBuf),
    /// A packaged (MSIX) app, started through the shell by its AppUserModelID: `explorer.exe shell:AppsFolder\<id>`.
    Aumid(String),
}

/// The places a classic (non-packaged) install and its Start-menu shortcut live, most likely first. `local` is %LOCALAPPDATA%, `roaming` is %APPDATA%, `programs` is %ProgramFiles%.
pub fn candidates(local: Option<&Path>, roaming: Option<&Path>, programs: Option<&Path>) -> Vec<PathBuf> {
    let mut out = Vec::new();
    if let Some(l) = local {
        out.push(l.join("AnthropicClaude").join("claude.exe"));
        out.push(l.join("Programs").join("Claude").join("Claude.exe"));
    }
    if let Some(p) = programs {
        out.push(p.join("Claude").join("Claude.exe"));
    }
    if let Some(r) = roaming {
        out.push(r.join("Microsoft").join("Windows").join("Start Menu").join("Programs").join("Claude.lnk"));
    }
    out
}

/// An AppUserModelID of a packaged app: `<package family name>!<app id>`, letters, digits, dot, dash and underscore only. Anything else (a path, a GUID, a space, a quote, an
/// ampersand) is not started: the text comes from the system's own list, but it is still put on a command line.
pub fn valid_aumid(s: &str) -> bool {
    let Some((family, app)) = s.split_once('!') else { return false };
    let ok = |part: &str| !part.is_empty() && part.len() <= 128 && part.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_'));
    ok(family) && ok(app) && !app.contains('!')
}

/// The AppID of the Start-menu entry named exactly "Claude", from the lines `Get-StartApps` printed as `Name<TAB>AppID` (the caller asks PowerShell to print them that way).
pub fn start_app_id(listing: &str) -> Option<String> {
    listing
        .lines()
        .filter_map(|line| line.split_once('\t'))
        .find(|(name, id)| name.trim() == "Claude" && valid_aumid(id.trim()))
        .map(|(_, id)| id.trim().to_string())
}

/// Picks how to start the app: the first candidate that exists, else the packaged app the Start menu lists. `listing` is asked for only when no file was found (it starts PowerShell).
pub fn pick(candidates: &[PathBuf], exists: impl Fn(&Path) -> bool, listing: impl FnOnce() -> Option<String>) -> Option<Launch> {
    if let Some(found) = candidates.iter().find(|p| exists(p)) {
        return Some(Launch::Path(found.clone()));
    }
    listing().and_then(|text| start_app_id(&text)).map(Launch::Aumid)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dirs() -> Vec<PathBuf> {
        candidates(Some(Path::new("L")), Some(Path::new("R")), Some(Path::new("P")))
    }

    #[test]
    fn candidates_come_in_order_and_skip_missing_folders() {
        let all = dirs();
        assert_eq!(all.len(), 4);
        assert_eq!(all[0], Path::new("L").join("AnthropicClaude").join("claude.exe"));
        assert!(all[3].ends_with("Claude.lnk"));
        assert_eq!(candidates(None, None, None), Vec::<PathBuf>::new());
        assert_eq!(candidates(Some(Path::new("L")), None, None).len(), 2);
    }

    #[test]
    fn the_first_file_that_exists_wins_and_the_listing_is_never_asked() {
        let all = dirs();
        let second = all[1].clone();
        let got = pick(&all, |p| p == second || p == all[3], || panic!("PowerShell must not start when a file was found"));
        assert_eq!(got, Some(Launch::Path(second)));
    }

    #[test]
    fn with_no_file_the_packaged_app_is_found_in_the_start_menu_listing() {
        let all = dirs();
        let listing = "Calculator\tMicrosoft.WindowsCalculator_8wekyb3d8bbwe!App\nClaude\tClaude_pzs8sxrjxfjjc!Claude\n";
        let got = pick(&all, |_| false, || Some(listing.to_string()));
        assert_eq!(got, Some(Launch::Aumid("Claude_pzs8sxrjxfjjc!Claude".into())));
    }

    #[test]
    fn nothing_found_is_none_and_a_failed_listing_is_none() {
        assert_eq!(pick(&dirs(), |_| false, || None), None);
        assert_eq!(pick(&dirs(), |_| false, || Some(String::new())), None);
        assert_eq!(pick(&[], |_| true, || None), None);
    }

    #[test]
    fn only_an_entry_named_exactly_claude_with_a_well_formed_id_counts() {
        assert_eq!(start_app_id("Claude Code\tFoo_abc!App\n"), None, "a similar name is not Claude");
        assert_eq!(start_app_id("claude\tFoo_abc!App\n"), None);
        assert_eq!(start_app_id("Claude\tC:\\Program Files\\Claude\\Claude.exe\n"), None, "a path is not an AUMID");
        assert_eq!(start_app_id("Claude\tFoo & calc!App\n"), None);
        assert_eq!(start_app_id("Claude\tFoo\"bar!App\n"), None);
        assert_eq!(start_app_id("Claude\tFoo!App!Extra\n"), None);
        assert_eq!(start_app_id("Claude Foo_abc!App\n"), None, "no tab, no entry");
        assert_eq!(start_app_id("Claude\t Foo_abc!App \r\n"), Some("Foo_abc!App".into()), "padding and a CRLF are trimmed");
    }

    #[test]
    fn aumid_rules() {
        assert!(valid_aumid("Claude_pzs8sxrjxfjjc!Claude"));
        assert!(!valid_aumid(""));
        assert!(!valid_aumid("!App"));
        assert!(!valid_aumid("Foo!"));
        assert!(!valid_aumid("Foo bar!App"));
        assert!(!valid_aumid(&format!("{}!App", "a".repeat(129))));
    }
}
