#[cfg(any(test, not(target_os = "linux")))]
mod audio_resampler;
mod keyboard;
/// cbindgen:ignore
pub mod platform;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub use platform::{
    clip_cursor, get_cursor, get_cursor_data, get_cursor_pos, get_focused_display,
    set_cursor_pos, start_os_service,
};
#[cfg(not(any(target_os = "ios")))]
/// cbindgen:ignore
mod server;
#[cfg(not(any(target_os = "ios")))]
pub use self::server::*;
mod client;
mod lan;
#[cfg(not(any(target_os = "ios")))]
mod rendezvous_mediator;
#[cfg(not(any(target_os = "ios")))]
pub use self::rendezvous_mediator::*;
/// cbindgen:ignore
pub mod common;
mod dolphin;
mod dolphin_portal;
mod dolphin_fixed_core;
mod dolphin_fixed;
mod dolphin_update_core;
mod dolphin_update;
mod dolphin_callback_core;
mod dolphin_callback;
mod dolphin_session_core;
#[cfg(windows)]
mod dolphin_install_core;
mod dolphin_system_core;
mod dolphin_panel_core;
mod dolphin_panel;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod dolphin_system;
// Dolphin Connect, Plan 18 Phase 5: signed settings (DD-24), the ID kept across a reinstall (DD-5).
mod dolphin_strategy_core;
mod dolphin_strategy;
#[cfg(windows)]
mod dolphin_identity_core;
#[cfg(windows)]
mod dolphin_identity;
// Dolphin Connect, Plan 18 Phase 5: DD-11 Safe Mode restart and return, DD-10 Wake-on-LAN.
mod dolphin_safe_mode_core;
mod dolphin_safe_mode;
mod dolphin_wake_core;
mod dolphin_wake;
// Dolphin Connect, Plan 18 Phase 6: DD-1 network-change listener and the physical adapter.
mod dolphin_net_core;
mod dolphin_net;
#[cfg(not(any(target_os = "ios")))]
pub mod ipc;
#[cfg(not(any(
    target_os = "android",
    target_os = "ios",
    feature = "flutter"
)))]
pub mod ui;
mod version;
pub use version::*;
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
mod bridge_generated;
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
pub mod flutter;
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
pub mod flutter_ffi;
use common::*;
mod auth_2fa;
#[cfg(not(target_os = "ios"))]
mod clipboard;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub mod core_main;
mod custom_server;
mod lang;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod port_forward;
mod port_forward_mux;

#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod tray;

#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod whiteboard;

#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod updater;

mod ui_cm_interface;
mod ui_interface;
mod ui_session_interface;

mod hbbs_http;

#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
pub mod clipboard_file;

pub mod privacy_mode;

#[cfg(windows)]
pub mod virtual_display_manager;

mod kcp_stream;
