//! Dolphin Connect, Plan 19 C3: «کادر رنگی دور صفحه». While a technician is connected and the customer turned it on,
//! the session window (`--cm`, flutter/lib/dolphin/connection.dart) asks for a coloured frame around every screen with
//! `main_set_common("dolphin-frame", "#rrggbb")` and removes it with "". The rules are src/dolphin_frame_core.rs.
//!
//! The frame is four thin windows per monitor, owned by one thread of the session window's process:
//! - always on top (`WS_EX_TOPMOST`), borderless (`WS_POPUP`), never in the taskbar or Alt+Tab (`WS_EX_TOOLWINDOW`),
//!   never activated (`WS_EX_NOACTIVATE`);
//! - click-through: layered and transparent to the mouse (`WS_EX_LAYERED | WS_EX_TRANSPARENT`, and `HTTRANSPARENT`),
//!   so every click lands on what is under it;
//! - left out of screen capture where Windows can (`WDA_EXCLUDEFROMCAPTURE`, Windows 10 2004 and later), so the
//!   technician's picture and the customer's screenshots do not show it. Older Windows draw it in the picture too.
//! It belongs to the session window's process, so it can never outlive the session window; nothing here touches the
//! connection, the capture or the input.

use crate::dolphin_frame_core as rules;
use hbb_common::log;
use std::sync::Mutex;
use winapi::{
    shared::{
        minwindef::{BOOL, LPARAM, LRESULT, TRUE, UINT, WPARAM},
        windef::{HBRUSH, HDC, HMONITOR, HWND, LPRECT},
    },
    um::{
        libloaderapi::GetModuleHandleW,
        processthreadsapi::GetCurrentThreadId,
        wingdi::{CreateSolidBrush, DeleteObject},
        winuser::*,
    },
};

/// Windows 10 2004+: the window is left out of every capture (not in winapi 0.3).
const WDA_EXCLUDEFROMCAPTURE: u32 = 0x11;
/// The screens changed (WM_DISPLAYCHANGE): draw the frame again for the new layout.
const WM_DOLPHIN_FRAME_REBUILD: UINT = WM_APP + 0x51;
const CLASS: &str = "DolphinConnectSessionFrame";

/// The drawing thread and the colour it shows.
struct Running {
    thread_id: u32,
    colour: (u8, u8, u8),
}

static RUNNING: Mutex<Option<Running>> = Mutex::new(None);

thread_local! {
    static BRUSH: std::cell::Cell<HBRUSH> = std::cell::Cell::new(std::ptr::null_mut());
}

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

/// `main_set_common("dolphin-frame", value)`.
pub fn set(value: &str) {
    let wanted = rules::parse_colour(value);
    let mut running = RUNNING.lock().unwrap_or_else(|e| e.into_inner());
    let current = running.as_ref().map(|r| r.colour);
    match rules::frame_change(current, wanted) {
        rules::FrameChange::Keep => {}
        rules::FrameChange::Hide => stop(running.take()),
        rules::FrameChange::Show | rules::FrameChange::Recolour => {
            stop(running.take());
            if let Some(colour) = wanted {
                *running = start(colour);
            }
        }
    }
}

fn stop(running: Option<Running>) {
    if let Some(r) = running {
        unsafe { PostThreadMessageW(r.thread_id, WM_QUIT, 0, 0) };
    }
}

/// Starts the thread and waits (at most 2 s) until its windows exist and it can take messages.
fn start(colour: (u8, u8, u8)) -> Option<Running> {
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || run(colour, tx));
    match rx.recv_timeout(std::time::Duration::from_secs(2)) {
        Ok(thread_id) => Some(Running { thread_id, colour }),
        Err(_) => {
            log::warn!("Dolphin frame: the drawing thread did not start");
            None
        }
    }
}

unsafe extern "system" fn wnd_proc(hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_NCHITTEST => HTTRANSPARENT as LRESULT,
        WM_MOUSEACTIVATE => MA_NOACTIVATE as LRESULT,
        WM_ERASEBKGND => 1,
        WM_PAINT => {
            let mut ps: PAINTSTRUCT = std::mem::zeroed();
            let hdc = BeginPaint(hwnd, &mut ps);
            BRUSH.with(|b| FillRect(hdc, &ps.rcPaint, b.get()));
            EndPaint(hwnd, &ps);
            0
        }
        WM_DISPLAYCHANGE => {
            PostThreadMessageW(GetCurrentThreadId(), WM_DOLPHIN_FRAME_REBUILD, 0, 0);
            0
        }
        _ => DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

unsafe extern "system" fn add_monitor(_: HMONITOR, _: HDC, rect: LPRECT, data: LPARAM) -> BOOL {
    let list = &mut *(data as *mut Vec<rules::Rect>);
    let r = &*rect;
    list.push(rules::Rect { left: r.left, top: r.top, right: r.right, bottom: r.bottom });
    TRUE
}

fn monitors() -> Vec<rules::Rect> {
    let mut list: Vec<rules::Rect> = vec![];
    unsafe {
        EnumDisplayMonitors(
            std::ptr::null_mut(),
            std::ptr::null(),
            Some(add_monitor),
            &mut list as *mut Vec<rules::Rect> as LPARAM,
        );
    }
    list
}

unsafe fn create_windows(class: &[u16]) -> Vec<HWND> {
    let hinstance = GetModuleHandleW(std::ptr::null());
    let mut out = vec![];
    for m in monitors() {
        for e in rules::edge_rects(m, rules::FRAME_THICKNESS) {
            let hwnd = CreateWindowExW(
                WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED | WS_EX_TRANSPARENT,
                class.as_ptr(),
                class.as_ptr(),
                WS_POPUP,
                e.left,
                e.top,
                e.width(),
                e.height(),
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                hinstance,
                std::ptr::null_mut(),
            );
            if hwnd.is_null() {
                continue;
            }
            SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);
            // Fails quietly before Windows 10 2004: the frame then shows in the picture too.
            SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE);
            ShowWindow(hwnd, SW_SHOWNOACTIVATE);
            out.push(hwnd);
        }
    }
    out
}

unsafe fn destroy_windows(windows: &mut Vec<HWND>) {
    for hwnd in windows.drain(..) {
        DestroyWindow(hwnd);
    }
}

fn run(colour: (u8, u8, u8), started: std::sync::mpsc::Sender<u32>) {
    unsafe {
        let class = wide(CLASS);
        let hinstance = GetModuleHandleW(std::ptr::null());
        let brush = CreateSolidBrush(rules::colorref(colour));
        BRUSH.with(|b| b.set(brush));
        let wc = WNDCLASSW {
            style: 0,
            lpfnWndProc: Some(wnd_proc),
            cbClsExtra: 0,
            cbWndExtra: 0,
            hInstance: hinstance,
            hIcon: std::ptr::null_mut(),
            hCursor: std::ptr::null_mut(),
            hbrBackground: std::ptr::null_mut(),
            lpszMenuName: std::ptr::null(),
            lpszClassName: class.as_ptr(),
        };
        // A second start in the same process finds the class registered already; that is fine.
        RegisterClassW(&wc);
        let mut windows = create_windows(&class);
        // The windows gave this thread its message queue: it can take WM_QUIT now. Nobody waiting any more (the start
        // timed out) means nobody would ever stop this frame: end at once instead.
        if started.send(GetCurrentThreadId()).is_err() {
            destroy_windows(&mut windows);
            DeleteObject(brush as _);
            return;
        }
        let mut msg: MSG = std::mem::zeroed();
        while GetMessageW(&mut msg, std::ptr::null_mut(), 0, 0) > 0 {
            if msg.hwnd.is_null() && msg.message == WM_DOLPHIN_FRAME_REBUILD {
                destroy_windows(&mut windows);
                windows = create_windows(&class);
                continue;
            }
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        destroy_windows(&mut windows);
        DeleteObject(brush as _);
    }
}
