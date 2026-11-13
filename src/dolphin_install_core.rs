//! Dolphin Connect (DD-21): what an earlier install of the same app left behind, removed when this one installs.
//! Standard library only, so CI tests it alone (`rustc --edition 2021 --test src/dolphin_install_core.rs`);
//! `src/platform/windows.rs` (`dolphin_leftover_cleanup`, called from `install_me`) feeds it and runs the commands in
//! the elevated install script, right after upstream's own uninstall of the install it can see.
//!
//! Upstream's uninstall already removes an install of the same name that it can find through the registry view of
//! its own process: the folder in `InstallLocation`, the service (named after the app), the shortcuts in the shared
//! Start Menu, Public Desktop and Startup folders, the firewall rules and the uninstall key. What it cannot see is an
//! install of the other architecture: a 32-bit installer on 64-bit Windows reads only the 32-bit registry view and
//! never finds the 64-bit `Program Files\<app>` (and the reverse when that key is gone), so the old folder and its
//! entry in «Programs and Features» stay. This removes exactly these, and nothing else:
//!
//! 1. `<64-bit Program Files>\<app>` and `<Program Files (x86)>\<app>`, and the other view's recorded
//!    `InstallLocation` when its last part is the app's name. Each only when `<app>.exe` is in it, never the folder
//!    this install writes to, and never the folder the running exe is in.
//! 2. The other registry view's `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\<app>` key, unless it
//!    records a folder of another name (left alone, with its key).
//!
//! User data is never touched: the config and logs live under the user's profile (`%APPDATA%\<app>`), not here.

pub const UNINSTALL_SUBKEY: &str = r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RegView {
    Bit64,
    Bit32,
}

impl RegView {
    fn flag(self) -> &'static str {
        match self {
            RegView::Bit64 => "/reg:64",
            RegView::Bit32 => "/reg:32",
        }
    }
}

/// The registry view this process does not write its own uninstall key to. A 64-bit process writes the 64-bit
/// view; a 32-bit one on 64-bit Windows the 32-bit view; 32-bit Windows has one view only.
pub fn other_view(process_64bit: bool, windows_64bit: bool) -> Option<RegView> {
    if process_64bit {
        Some(RegView::Bit32)
    } else if windows_64bit {
        Some(RegView::Bit64)
    } else {
        None
    }
}

pub struct OldInstall<'a> {
    /// `crate::get_app_name()`: letters, digits and hyphens (dolphin/gen_profile.py checks it).
    pub app_name: &'a str,
    /// Where this install goes.
    pub target_dir: &'a str,
    /// The folder of the running exe.
    pub current_dir: &'a str,
    /// The two Program Files folders joined with the app's name, as this process sees them (missing ones left out).
    pub default_dirs: &'a [String],
    pub other_view: Option<RegView>,
    /// `InstallLocation` of the other view's uninstall key: None when there is no key, Some("") when it has none.
    pub other_location: Option<&'a str>,
}

fn app_name_ok(name: &str) -> bool {
    !name.is_empty() && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
}

fn norm(path: &str) -> String {
    path.trim().replace('/', "\\").trim_end_matches('\\').to_lowercase()
}

/// An absolute `X:\...` folder whose last part is the app's name, with nothing cmd.exe would read as syntax.
fn own_folder(dir: &str, app_name: &str) -> Option<String> {
    let dir = dir.trim().replace('/', "\\");
    let dir = dir.trim_end_matches('\\');
    let b = dir.as_bytes();
    if b.len() < 4 || !b[0].is_ascii_alphabetic() || b[1] != b':' || b[2] != b'\\' {
        return None;
    }
    if dir.chars().any(|c| "\"%&^|<>!\r\n\t*?".contains(c)) {
        return None;
    }
    let parts: Vec<&str> = dir[3..].split('\\').collect();
    if parts.iter().any(|p| p.is_empty() || *p == "." || *p == "..") {
        return None;
    }
    if !parts.last()?.eq_ignore_ascii_case(app_name) {
        return None;
    }
    Some(dir.to_owned())
}

/// Lines for the elevated install script (cmd.exe), in order. Empty when there is nothing to remove.
pub fn leftover_cleanup(i: &OldInstall) -> Vec<String> {
    let app = i.app_name;
    if !app_name_ok(app) {
        return Vec::new();
    }
    let target = norm(i.target_dir);
    let current = norm(i.current_dir);
    let keep = |d: &str| {
        let n = norm(d);
        n == target || n == current || current.starts_with(&format!("{n}\\"))
    };
    let mut seen: Vec<String> = Vec::new();
    let mut out = Vec::new();
    let mut add = |dir: &str, out: &mut Vec<String>| {
        if keep(dir) || seen.contains(&norm(dir)) {
            return;
        }
        seen.push(norm(dir));
        out.push(format!("if exist \"{dir}\\{app}.exe\" rd /s /q \"{dir}\""));
    };
    for d in i.default_dirs {
        if let Some(d) = own_folder(d, app) {
            add(&d, &mut out);
        }
    }
    let mut delete_key = false;
    if let (Some(view), Some(loc)) = (i.other_view, i.other_location) {
        if loc.trim().is_empty() {
            delete_key = true;
        } else if let Some(d) = own_folder(loc, app) {
            add(&d, &mut out);
            delete_key = true; // removed now, or ours and kept because this install reuses it
        }
        if delete_key {
            out.push(format!("reg delete \"HKLM\\{UNINSTALL_SUBKEY}\\{app}\" /f {}", view.flag()));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const APP: &str = "DolphinConnect";

    fn dirs() -> Vec<String> {
        vec![r"C:\Program Files\DolphinConnect".into(), r"C:\Program Files (x86)\DolphinConnect".into()]
    }

    fn run(target: &str, current: &str, view: Option<RegView>, loc: Option<&str>) -> Vec<String> {
        let d = dirs();
        leftover_cleanup(&OldInstall {
            app_name: APP,
            target_dir: target,
            current_dir: current,
            default_dirs: &d,
            other_view: view,
            other_location: loc,
        })
    }

    const TMP: &str = r"C:\Users\a\AppData\Local\Temp\DolphinConnect-2.1.0-x64-install";

    #[test]
    fn views() {
        assert_eq!(other_view(true, true), Some(RegView::Bit32));
        assert_eq!(other_view(false, true), Some(RegView::Bit64));
        assert_eq!(other_view(false, false), None);
    }

    #[test]
    fn a_32_bit_install_over_a_64_bit_one_removes_its_folder_and_its_key() {
        let out = run(r"C:\Program Files (x86)\DolphinConnect", TMP, Some(RegView::Bit64), Some(r"C:\Program Files\DolphinConnect\"));
        assert_eq!(
            out,
            vec![
                r#"if exist "C:\Program Files\DolphinConnect\DolphinConnect.exe" rd /s /q "C:\Program Files\DolphinConnect""#.to_owned(),
                r#"reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\DolphinConnect" /f /reg:64"#.to_owned(),
            ]
        );
    }

    #[test]
    fn a_64_bit_install_removes_a_32_bit_folder_whose_key_is_gone() {
        let out = run(r"C:\Program Files\DolphinConnect", TMP, Some(RegView::Bit32), None);
        assert_eq!(
            out,
            vec![r#"if exist "C:\Program Files (x86)\DolphinConnect\DolphinConnect.exe" rd /s /q "C:\Program Files (x86)\DolphinConnect""#.to_owned()]
        );
    }

    #[test]
    fn never_the_target_folder_nor_the_folder_of_the_running_exe() {
        let out = run(r"c:\program files\dolphinconnect\", r"C:\Program Files (x86)\DolphinConnect", Some(RegView::Bit32), None);
        assert!(out.is_empty(), "{out:?}");
        let out = run(r"C:\Program Files\DolphinConnect", r"C:\Program Files (x86)\DolphinConnect\sub", Some(RegView::Bit32), None);
        assert!(out.is_empty(), "{out:?}");
    }

    #[test]
    fn a_key_without_a_location_is_removed_and_a_folder_of_another_name_is_left_with_its_key() {
        let out = run(r"C:\Program Files\DolphinConnect", TMP, Some(RegView::Bit32), Some(""));
        assert_eq!(out.last().unwrap(), r#"reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\DolphinConnect" /f /reg:32"#);
        let out = run(r"C:\Program Files\DolphinConnect", TMP, Some(RegView::Bit32), Some(r"D:\Tools\Remote"));
        assert!(out.iter().all(|l| !l.starts_with("reg delete") && !l.contains(r"D:\Tools")), "{out:?}");
    }

    #[test]
    fn a_recorded_custom_folder_named_after_the_app_is_removed_once() {
        let out = run(r"C:\Program Files (x86)\DolphinConnect", TMP, Some(RegView::Bit64), Some(r"D:\Apps\DolphinConnect"));
        assert_eq!(out.len(), 3);
        assert_eq!(out[1], r#"if exist "D:\Apps\DolphinConnect\DolphinConnect.exe" rd /s /q "D:\Apps\DolphinConnect""#);
        let out = run(r"C:\Program Files (x86)\DolphinConnect", TMP, Some(RegView::Bit64), Some(r"C:\PROGRAM FILES\DolphinConnect"));
        assert_eq!(out.iter().filter(|l| l.starts_with("if exist")).count(), 1);
    }

    #[test]
    fn the_reused_target_keeps_its_folder_but_a_stale_other_view_key_goes() {
        let out = run(r"C:\Program Files\DolphinConnect", TMP, Some(RegView::Bit32), Some(r"C:\Program Files\DolphinConnect"));
        assert_eq!(out.len(), 2);
        assert!(out[1].ends_with("/reg:32"));
    }

    #[test]
    fn only_a_32_bit_windows_has_no_other_view() {
        let d = vec![r"C:\Program Files\DolphinConnect".to_owned()];
        let out = leftover_cleanup(&OldInstall {
            app_name: APP,
            target_dir: r"C:\Program Files\DolphinConnect",
            current_dir: TMP,
            default_dirs: &d,
            other_view: None,
            other_location: Some(""),
        });
        assert!(out.is_empty());
    }

    #[test]
    fn refuses_unsafe_or_foreign_paths_and_bad_names() {
        for bad in [
            r"C:\Program Files\Other",
            r"Program Files\DolphinConnect",
            r"\\server\share\DolphinConnect",
            r"C:\x\..\DolphinConnect",
            r"C:\x\%TEMP%\DolphinConnect",
            "C:\\x\" & del C:\\ & \"\\DolphinConnect",
            r"C:\DolphinConnect.exe",
            "",
        ] {
            assert_eq!(own_folder(bad, APP), None, "{bad}");
        }
        assert_eq!(own_folder(r"D:/Apps/DolphinConnect/", APP).as_deref(), Some(r"D:\Apps\DolphinConnect"));
        let d = dirs();
        let out = leftover_cleanup(&OldInstall {
            app_name: "Dolphin Connect",
            target_dir: "",
            current_dir: "",
            default_dirs: &d,
            other_view: Some(RegView::Bit64),
            other_location: Some(""),
        });
        assert!(out.is_empty());
    }

    #[test]
    fn the_technician_app_cleans_only_its_own_name() {
        let d = vec![r"C:\Program Files\DolphinConnectTech".to_owned(), r"C:\Program Files (x86)\DolphinConnect".to_owned()];
        let out = leftover_cleanup(&OldInstall {
            app_name: "DolphinConnectTech",
            target_dir: r"D:\Elsewhere\DolphinConnectTech",
            current_dir: TMP,
            default_dirs: &d,
            other_view: Some(RegView::Bit32),
            other_location: None,
        });
        assert_eq!(out, vec![r#"if exist "C:\Program Files\DolphinConnectTech\DolphinConnectTech.exe" rd /s /q "C:\Program Files\DolphinConnectTech""#.to_owned()]);
    }
}
