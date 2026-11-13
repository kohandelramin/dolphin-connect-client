//! Dolphin Connect, Plan 18 Phase 2 (ADR-0016): the app side of `src/dolphin_system_core.rs`, which holds the rules
//! and their tests. Here: reading the options, the receive folder on disk, and the customer app's tray.
//!
//! What "the window is open" means (verified in the source, 2026-11-13, for ADR-0016's open question):
//! `allow-only-conn-window-open` is checked only in `Connection::on_open` (src/server/connection.rs), and only in the
//! `--server` process of an installed app. It calls `crate::check_process("", ..)` (src/common.rs), which asks whether
//! another process of the same exe runs whose first argument does not start with `--`: the main window's process. It
//! never looks at the window itself, so a main window hidden in the tray counts as open, and the `--tray`, `--cm` and
//! `--server` processes never do. A portable app hosts the server inside its main process, so there the check is not
//! made at all: the server lives exactly as long as that process. Upstream's close hides the window and drops it from
//! the active windows (`onWindowClose` in flutter/lib/desktop/widgets/tabbar_widget.dart); with none left,
//! `onActiveWindowChanged` (flutter/lib/common.dart) really closes it and the process ends. That is «بستن کامل».
//! «در دسترس بماند» only hides the window and keeps it active (flutter/lib/dolphin/presence.dart), so the process, and
//! with it `check_process`, stays. No minimal window is needed.

use crate::dolphin_system_core as rules;
pub use rules::{RECEIVE_ONLY_ERROR, SHARE_OFF_LOGIN_ERROR};
#[cfg(all(windows, feature = "flutter"))]
use hbb_common::tokio;
use hbb_common::{config::Config, log};
use std::path::{Path, PathBuf};

fn switch(raw: &str, key: &str) -> rules::SwitchMode {
    rules::switch_mode(raw, key)
}

/// Server process (the config the heartbeat writes): has the customer stopped sharing (DD-34)?
pub fn sharing_stopped() -> bool {
    rules::sharing_stopped(
        switch(&Config::get_option(rules::SWITCHES_OPTION), rules::SWITCH_SHARE_TOGGLE),
        &Config::get_option(rules::SHARE_OFF_OPTION),
    )
}

/// Main window (`main_set_common("dolphin-share-off")`): one key written on the server. `ipc::set_option` reads the
/// server's options right before it writes them back; upstream's `set_option` would send the window's copy, up to a
/// second old, and could put back a value the portal had just changed (`dolphin-tech-id`). Off the caller's thread:
/// it runs its own small runtime.
pub fn set_share_off(stop: bool) {
    std::thread::spawn(move || crate::ipc::set_option(rules::SHARE_OFF_OPTION, if stop { "Y" } else { "" }));
}

/// Main window, once per run: a stop left from an earlier run is cleared (opening the app is consent, ADR-0015).
/// Written only when it is "Y".
pub fn reset_share_at_start() {
    std::thread::spawn(|| {
        if crate::ipc::get_options().get(rules::SHARE_OFF_OPTION).map_or(false, |v| v == "Y") {
            crate::ipc::set_option(rules::SHARE_OFF_OPTION, "");
        }
    });
}

/// The heartbeat's `dolphin_share` value («رایانه‌ها» can show «اشتراک متوقف»).
pub fn heartbeat_share() -> &'static str {
    rules::heartbeat_share(sharing_stopped())
}

/// Server process, at a file-transfer login: the folder the file manager opens first (DD-12).
pub fn login_dir(client_dir: String) -> String {
    let mode = switch(&Config::get_option(rules::SWITCHES_OPTION), rules::SWITCH_RECEIVE_FOLDER);
    rules::login_dir(mode, &client_dir).to_owned()
}

/// Main window (`main_get_common("dolphin-receive-dir")`): the receive folder's path, or "" when the switch hides it.
pub fn receive_dir_for_ui() -> String {
    let mode = switch(&crate::ui_interface::get_option(rules::SWITCHES_OPTION), rules::SWITCH_RECEIVE_FOLDER);
    if rules::opens_receive_dir(mode) {
        rules::receive_dir(&Config::get_home()).to_string_lossy().to_string()
    } else {
        "".to_owned()
    }
}

// ---- The `--cm` process: it runs as the signed-in customer, so `Config::get_home()` is their own folder. ----

/// The switches as the server holds them, read over IPC and kept 5 s (one read per file would be wasteful).
#[cfg(not(any(target_os = "android", target_os = "ios")))]
async fn cm_switches() -> String {
    use std::sync::Mutex;
    use std::time::{Duration, Instant};
    lazy_static::lazy_static! {
        static ref CACHE: Mutex<Option<(Instant, String)>> = Mutex::new(None);
    }
    let cached = CACHE
        .lock()
        .unwrap()
        .as_ref()
        .filter(|(at, _)| at.elapsed() < Duration::from_secs(5))
        .map(|(_, v)| v.clone());
    if let Some(v) = cached {
        return v;
    }
    let v = crate::ipc::get_option_async(rules::SWITCHES_OPTION).await;
    *CACHE.lock().unwrap() = Some((Instant::now(), v.clone()));
    v
}

/// What an empty ReadDir opens (the technician has no saved folder for this PC): the receive folder, made if needed,
/// unless the switch hides it. If it cannot be made, upstream's home folder.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub async fn cm_home() -> PathBuf {
    let home = Config::get_home();
    if !rules::opens_receive_dir(switch(&cm_switches().await, rules::SWITCH_RECEIVE_FOLDER)) {
        return home;
    }
    let dir = rules::receive_dir(&home);
    match std::fs::create_dir_all(&dir) {
        Ok(()) => dir,
        Err(err) => {
            log::warn!("Dolphin receive folder not available, using home: {err}");
            home
        }
    }
}

/// The path with its deepest existing ancestor made canonical (symlinks and junctions resolved), the rest appended.
fn resolve(path: &Path) -> PathBuf {
    let mut tail: Vec<std::ffi::OsString> = Vec::new();
    let mut base = path.to_path_buf();
    loop {
        if let Ok(mut resolved) = base.canonicalize() {
            while let Some(c) = tail.pop() {
                resolved.push(c);
            }
            return resolved;
        }
        match base.file_name() {
            Some(name) => tail.push(name.to_os_string()),
            None => return path.to_path_buf(),
        }
        if !base.pop() {
            return path.to_path_buf();
        }
    }
}

/// With the folder forced, a new file or folder from the technician outside the receive folder is refused: the job's
/// (id, file number) to answer with RECEIVE_ONLY_ERROR. `None` lets it through.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub async fn cm_refused_write(fs: &crate::ipc::FS) -> Option<(i32, i32)> {
    use crate::ipc::FS;
    let (path, id, file_num, names): (&str, i32, i32, Vec<&str>) = match fs {
        FS::NewWrite {
            path, id, file_num, files, ..
        } => (path.as_str(), *id, *file_num, files.iter().map(|(n, _)| n.as_str()).collect()),
        FS::CreateDir { path, id } => (path.as_str(), *id, 0, vec![]),
        _ => return None,
    };
    let mode = switch(&cm_switches().await, rules::SWITCH_RECEIVE_FOLDER);
    if mode != rules::SwitchMode::Forced {
        return None;
    }
    let receive = rules::receive_dir(&Config::get_home());
    std::fs::create_dir_all(&receive).ok();
    let receive = resolve(&receive);
    let base = resolve(Path::new(path));
    let targets: Vec<PathBuf> = if names.is_empty() {
        vec![base]
    } else {
        names
            .iter()
            .map(|n| if n.is_empty() { base.clone() } else { base.join(n) })
            .collect()
    };
    if targets
        .iter()
        .all(|t| rules::write_allowed(mode, &receive, t, cfg!(windows)))
    {
        None
    } else {
        log::warn!("Dolphin: refused a write outside the receive folder: {path}");
        Some((id, file_num))
    }
}

// ---- The customer app's tray (x64 Flutter build): DD-35, DD-47 ----

/// The main window asks for the tray when it hides into it. An installed app already has one (upstream starts it at
/// sign-in); a portable app gets it here. The tray itself refuses a second copy in the session.
#[cfg(all(windows, feature = "flutter"))]
pub fn start_tray() {
    if !crate::check_process("--tray", true) {
        hbb_common::allow_err!(crate::run_me(vec!["--tray"]));
    }
}

/// The main window processes of this exe for this user: the same rule as `check_process("", true)` (64-bit), so the
/// tray shows exactly what `allow-only-conn-window-open` will decide.
#[cfg(all(windows, feature = "flutter"))]
fn main_window_processes(sys: &hbb_common::sysinfo::System) -> Vec<hbb_common::sysinfo::Pid> {
    let mut path = std::env::current_exe().unwrap_or_default();
    if let Ok(linked) = path.read_link() {
        path = linked;
    }
    let path = path.to_string_lossy().to_lowercase();
    let me = std::process::id().to_string();
    let my_uid = sys
        .process((std::process::id() as usize).into())
        .map(|x| x.user_id())
        .unwrap_or_default();
    sys.processes()
        .iter()
        .filter(|(_, p)| {
            let mut cur = p.exe().to_path_buf();
            if let Ok(linked) = cur.read_link() {
                cur = linked;
            }
            let arg = if p.cmd().len() <= 1 { "" } else { &p.cmd()[1] };
            cur.to_string_lossy().to_lowercase() == path
                && p.pid().to_string() != me
                && p.user_id() == my_uid
                && !arg.starts_with("--")
        })
        .map(|(pid, _)| *pid)
        .collect()
}

#[cfg(all(windows, feature = "flutter"))]
fn window_open() -> bool {
    let mut sys = hbb_common::sysinfo::System::new();
    sys.refresh_processes();
    !main_window_processes(&sys).is_empty()
}

/// «بستن کامل» from the tray: the main window processes end, so nobody can connect (a portable app's server ends with
/// them; an installed app's server then refuses, `allow-only-conn-window-open`).
#[cfg(all(windows, feature = "flutter"))]
fn quit_main_windows() {
    let mut sys = hbb_common::sysinfo::System::new();
    sys.refresh_processes();
    for pid in main_window_processes(&sys) {
        if let Some(p) = sys.process(pid) {
            if !p.kill() {
                log::warn!("Dolphin tray: could not end the window process {pid}");
            }
        }
    }
}

/// One look at the server over IPC: (online, sessions, options).
#[cfg(all(windows, feature = "flutter"))]
async fn query_server() -> hbb_common::ResultType<(bool, usize, std::collections::HashMap<String, String>)> {
    use crate::ipc::Data;
    let mut c = crate::ipc::connect(1000, "").await?;
    c.send(&Data::OnlineStatus(None)).await?;
    c.send(&Data::ControlledSessionCount(0)).await?;
    c.send(&Data::Options(None)).await?;
    let (mut online, mut sessions, mut options) = (None, None, None);
    while online.is_none() || sessions.is_none() || options.is_none() {
        // A missing answer leaves that part at its default; the next look in 3 s tries again.
        match c.next_timeout(1000).await {
            Ok(Some(Data::OnlineStatus(Some((x, _))))) => online = Some(x > 0),
            Ok(Some(Data::ControlledSessionCount(n))) => sessions = Some(n),
            Ok(Some(Data::Options(Some(m)))) => options = Some(m),
            Ok(Some(_)) => {}
            Ok(None) | Err(_) => break,
        }
    }
    Ok((online.unwrap_or(false), sessions.unwrap_or(0), options.unwrap_or_default()))
}

/// Every 3 s: the tray's state and whether the share item shows (the portal's `share-toggle`), sent when either
/// changes; `None` tells the tray to end (a portable app was closed).
#[cfg(all(windows, feature = "flutter"))]
#[tokio::main(flavor = "current_thread")]
async fn watch_state(sender: std::sync::mpsc::Sender<Option<(rules::TrayState, bool)>>) {
    let installed = crate::platform::is_installed();
    let mut last = None;
    loop {
        let open = window_open();
        if rules::tray_should_exit(installed, open) {
            sender.send(None).ok();
            return;
        }
        let (online, sessions, options) = query_server().await.unwrap_or_default();
        let get = |k: &str| options.get(k).map(String::as_str).unwrap_or("");
        let share_toggle = switch(get(rules::SWITCHES_OPTION), rules::SWITCH_SHARE_TOGGLE);
        let stopped = rules::sharing_stopped(share_toggle, get(rules::SHARE_OFF_OPTION));
        let state = rules::tray_state(open, online, sessions, stopped);
        let view = (state, share_toggle != rules::SwitchMode::Hidden);
        if last != Some(view) {
            last = Some(view);
            if sender.send(Some(view)).is_err() {
                return;
            }
        }
        hbb_common::sleep(3.).await;
    }
}

/// The tray icon at the size Windows draws it (SM_CXSMICON follows the display scaling), from the .ico's own frame for
/// that size (rules::ico_frame). None leaves upstream's decoded image.
#[cfg(all(windows, feature = "flutter"))]
pub fn tray_icon_rgba(ico: &[u8]) -> Option<(Vec<u8>, u32, u32)> {
    let want = unsafe { winapi::um::winuser::GetSystemMetrics(winapi::um::winuser::SM_CXSMICON) };
    let (off, len) = rules::ico_frame(ico, want.max(16) as u32)?;
    let image = image::load_from_memory(&ico[off..off + len]).ok()?.into_rgba8();
    let (width, height) = image.dimensions();
    Some((image.into_raw(), width, height))
}

/// The customer app's tray, in place of upstream's (src/tray.rs hands over after its single-instance check): a dot
/// in the state's colour, the state as the tooltip, and the short menu of Plan 19 C7: the state line, «باز کردن دلفین
/// کانکت», «توقف اشتراک» / «شروع اشتراک» (not while the portal hides the share switch), a line, «بستن کامل». Hidden
/// while nobody could connect.
#[cfg(all(windows, feature = "flutter"))]
pub fn run_customer_tray(rgba: Vec<u8>, width: u32, height: u32) -> hbb_common::ResultType<()> {
    use std::time::{Duration, Instant};
    use tao::event_loop::{ControlFlow, EventLoopBuilder};
    use tray_icon::{
        menu::{Menu, MenuEvent, MenuItem, PredefinedMenuItem},
        MouseButton, MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent,
    };

    let icon_for = move |state: rules::TrayState| {
        let mut px = rgba.clone();
        if let Some(colour) = rules::tray_colour(state) {
            rules::badge(&mut px, width, height, colour);
        }
        tray_icon::Icon::from_rgba(px, width, height).ok()
    };
    let open_window = || {
        // As upstream: `run_me` with no arguments shows the running (hidden) window (flutter/windows/runner/main.cpp).
        crate::run_me::<&str>(vec![]).ok();
    };

    let menu = Menu::new();
    let state_i = MenuItem::new(rules::tray_state_line(rules::TrayState::Closed), false, None);
    let open_i = MenuItem::new(rules::TRAY_OPEN, true, None);
    let share_i = MenuItem::new(rules::TRAY_SHARE_STOP, true, None);
    let quit_i = MenuItem::new(rules::TRAY_QUIT, true, None);
    menu.append_items(&[&state_i, &open_i, &PredefinedMenuItem::separator(), &quit_i]).ok();
    // The share item sits after «باز کردن دلفین کانکت» while it shows.
    const SHARE_POSITION: usize = 2;
    let mut share_shown = false;
    let mut shown_state = rules::TrayState::Closed;

    let (tx, rx) = std::sync::mpsc::channel::<Option<(rules::TrayState, bool)>>();
    std::thread::spawn(move || watch_state(tx));

    let mut tray: Option<TrayIcon> = None;
    let mut last_click: Option<Instant> = None;
    let event_loop = EventLoopBuilder::new().build();
    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::WaitUntil(Instant::now() + Duration::from_millis(100));
        if let tao::event::Event::NewEvents(tao::event::StartCause::Init) = event {
            let mut builder = TrayIconBuilder::new()
                .with_id(crate::get_app_name().to_lowercase())
                .with_menu(Box::new(menu.clone()))
                .with_tooltip(rules::tray_tooltip(rules::TrayState::Closed))
                .with_menu_on_left_click(false);
            if let Some(icon) = icon_for(rules::TrayState::Closed) {
                builder = builder.with_icon(icon);
            }
            match builder.build() {
                Ok(t) => {
                    // Hidden until the first look says somebody could connect.
                    t.set_visible(false).ok();
                    tray = Some(t);
                }
                Err(err) => log::error!("Failed to create the Dolphin tray icon: {err}"),
            }
        }
        if let Ok(event) = MenuEvent::receiver().try_recv() {
            if event.id == open_i.id() {
                open_window();
            } else if event.id == share_i.id() {
                // The same option the home's «اشتراک‌گذاری» switch writes; the next look (3 s) shows the new state.
                set_share_off(rules::tray_share_press_stops(shown_state));
            } else if event.id == quit_i.id() {
                quit_main_windows();
            }
        }
        if let Ok(TrayIconEvent::Click {
            button: MouseButton::Left,
            button_state: MouseButtonState::Up,
            ..
        }) = TrayIconEvent::receiver().try_recv()
        {
            if last_click.map_or(true, |t| t.elapsed() >= Duration::from_secs(1)) {
                open_window();
                last_click = Some(Instant::now());
            }
        }
        if let Ok(update) = rx.try_recv() {
            match update {
                Some((state, share_toggle)) => {
                    shown_state = state;
                    state_i.set_text(rules::tray_state_line(state));
                    match rules::tray_share_item(state, share_toggle) {
                        Some(text) => {
                            share_i.set_text(text);
                            if !share_shown {
                                share_shown = menu.insert(&share_i, SHARE_POSITION).is_ok();
                            }
                        }
                        None => {
                            if share_shown {
                                menu.remove(&share_i).ok();
                                share_shown = false;
                            }
                        }
                    }
                    if let Some(t) = &tray {
                        t.set_icon(icon_for(state)).ok();
                        t.set_tooltip(Some(rules::tray_tooltip(state))).ok();
                        t.set_visible(rules::tray_visible(state)).ok();
                    }
                }
                None => {
                    // `Exit` ends the process without running destructors: remove the icon first (no ghost icon).
                    if let Some(t) = &tray {
                        t.set_visible(false).ok();
                    }
                    *control_flow = ControlFlow::Exit;
                }
            }
        }
    });
}
