//! Dolphin Connect, Plan 18 Phase 3 (DD-50 paste, DD-6 keyboard language): the app side of
//! `src/dolphin_panel_core.rs`, which holds the rules and their tests. Here: the messages both apps exchange, and on a
//! Windows customer PC the paste and the layout switch themselves. Not compiled on the maintainer's PC; written
//! against winapi 0.3 (`winuser`, already a dependency) and upstream's own helpers.

use crate::dolphin_panel_core as rules;
use base::message_proto::*;

/// Technician's app: the `Misc::PluginRequest` for this session only (built from `session_set_common`).
pub fn plugin_request_message(id: &str, content: Vec<u8>) -> Message {
    let mut misc = Misc::new();
    misc.set_plugin_request(PluginRequest {
        id: id.to_owned(),
        content: content.into(),
        ..Default::default()
    });
    let mut msg = Message::new();
    msg.set_misc(misc);
    msg
}

/// Customer's PC: the answer, an existing `MessageBox` the Dolphin technician app shows as one line.
pub fn result_message(outcome: rules::Outcome) -> Message {
    let mut msg = Message::new();
    msg.set_message_box(MessageBox {
        msgtype: rules::RESULT_MSGTYPE.to_owned(),
        title: outcome.code().to_owned(),
        text: outcome.text(),
        link: "".to_owned(),
        ..Default::default()
    });
    msg
}

/// Customer's PC, off the connection's loop (the paste waits for the clipboard): do it and say how it went.
/// `input` and `clipboard` are the connection's own checks at the moment the request came (switches and pause).
pub fn apply(request: rules::Request, input: bool, clipboard: bool) -> rules::Outcome {
    #[cfg(windows)]
    {
        win::apply(request, input, clipboard)
    }
    #[cfg(not(windows))]
    {
        let _ = (request, input, clipboard);
        rules::Outcome::Unsupported
    }
}

#[cfg(windows)]
mod win {
    use super::rules::{self, Outcome, Request, Scene};
    use base::message_proto::{Clipboard, ClipboardFormat};
    use winapi::shared::minwindef::{HKL, LPARAM};
    use winapi::shared::windef::HWND;
    use winapi::um::winuser::{
        GetForegroundWindow, GetGUIThreadInfo, GetKeyboardLayoutList, GetWindowThreadProcessId,
        MapVirtualKeyW, PostMessageW, SendInput, GUITHREADINFO, INPUT, INPUT_KEYBOARD,
        KEYEVENTF_KEYUP, VK_CONTROL, WM_INPUTLANGCHANGEREQUEST,
    };

    fn last_error() -> i32 {
        std::io::Error::last_os_error().raw_os_error().unwrap_or(0)
    }

    pub fn apply(request: Request, input: bool, clipboard: bool) -> Outcome {
        // The connection's tasks may sit on another desktop after a lock or UAC; input does the same (input_service).
        crate::platform::windows::try_change_desktop();
        let foreground = unsafe { GetForegroundWindow() };
        let has_window = !foreground.is_null();
        let scene = Scene {
            input,
            clipboard,
            has_window,
            self_elevated: crate::platform::is_root()
                || crate::platform::is_elevated(None).unwrap_or(false),
            foreground_elevated: has_window
                && crate::platform::is_foreground_window_elevated().unwrap_or(false),
        };
        match request {
            Request::Keyboard(lang) => match rules::plan_layout(&scene, &installed_layouts(), lang) {
                Err(no) => no,
                Ok(hkl) => {
                    // WM_INPUTLANGCHANGEREQUEST asks the window itself; its thread activates the layout (no
                    // ActivateKeyboardLayout from here, which would change only our own thread).
                    let target = focused_window(foreground);
                    let ok = unsafe { PostMessageW(target, WM_INPUTLANGCHANGEREQUEST, 0, hkl as LPARAM) } != 0;
                    rules::sent_outcome(ok, last_error(), Outcome::Switched(lang))
                }
            },
            Request::Paste(text) => {
                if let Some(no) = rules::plan_paste(&scene) {
                    return no;
                }
                // The same road as a clipboard message from the technician (Connection, Union::Clipboard).
                let clip = Clipboard {
                    compress: false,
                    content: text.into_bytes().into(),
                    format: ClipboardFormat::Text.into(),
                    ..Default::default()
                };
                crate::clipboard::update_clipboard(vec![clip], crate::clipboard::ClipboardSide::Host);
                std::thread::sleep(std::time::Duration::from_millis(rules::PASTE_DELAY_MS));
                crate::platform::windows::try_change_desktop();
                let (ok, err) = ctrl_v();
                rules::sent_outcome(ok, err, Outcome::Pasted)
            }
        }
    }

    /// The layouts loaded in the customer's session (the language bar's list).
    fn installed_layouts() -> Vec<usize> {
        unsafe {
            let n = GetKeyboardLayoutList(0, std::ptr::null_mut());
            if n <= 0 {
                return vec![];
            }
            let mut list: Vec<HKL> = vec![std::ptr::null_mut(); n as usize];
            let got = GetKeyboardLayoutList(n, list.as_mut_ptr());
            list.truncate(got.max(0) as usize);
            list.into_iter().map(|h| h as usize).collect()
        }
    }

    /// The control with the keyboard focus inside the foreground window, or the window itself.
    fn focused_window(foreground: HWND) -> HWND {
        unsafe {
            let thread = GetWindowThreadProcessId(foreground, std::ptr::null_mut());
            let mut info: GUITHREADINFO = std::mem::zeroed();
            info.cbSize = std::mem::size_of::<GUITHREADINFO>() as _;
            if thread != 0 && GetGUIThreadInfo(thread, &mut info) != 0 && !info.hwndFocus.is_null() {
                info.hwndFocus
            } else {
                foreground
            }
        }
    }

    /// Ctrl+V by virtual-key code: VK 'V' (0x56) is the same key on a Persian layout, where upstream's legacy
    /// character keys would not find a 'v'. Marked like upstream's injected input (enigo).
    fn ctrl_v() -> (bool, i32) {
        const VK_V: u16 = 0x56;
        let key = |vk: u16, up: bool| -> INPUT {
            let mut input: INPUT = unsafe { std::mem::zeroed() };
            input.type_ = INPUT_KEYBOARD;
            unsafe {
                let ki = input.u.ki_mut();
                ki.wVk = vk;
                ki.wScan = MapVirtualKeyW(vk as _, 0) as _;
                ki.dwFlags = if up { KEYEVENTF_KEYUP } else { 0 };
                ki.time = 0;
                ki.dwExtraInfo = enigo::ENIGO_INPUT_EXTRA_VALUE;
            }
            input
        };
        let mut inputs = [
            key(VK_CONTROL as u16, false),
            key(VK_V, false),
            key(VK_V, true),
            key(VK_CONTROL as u16, true),
        ];
        let sent = unsafe {
            SendInput(inputs.len() as _, inputs.as_mut_ptr(), std::mem::size_of::<INPUT>() as _)
        };
        (sent as usize == inputs.len(), last_error())
    }
}
