//! Dolphin Connect (DD-5): the Windows side of `src/dolphin_identity_core.rs`, which holds the rules and their tests.
//!
//! Where it runs: only in the installed app's `--server` process (started by the service as SYSTEM in the user's
//! session), the process that owns the service's config and registers the ID with the rendezvous server; called from
//! `src/core_main.rs` before `start_server`. A portable app (a normal user's process, its config in that user's
//! profile) never reads or writes the backup: the file is readable by SYSTEM and Administrators only.
//!
//! `libs/hbb_common` stays upstream's. Only its public API is used: `Config::get()` / `Config::set()` (the config is
//! serde-serialisable, which upstream itself uses to copy it between processes), `Config::get_id()`,
//! `Config::update_id()` and `Config::get_cached_pk()`. The ID is not a secret and may be logged; key bytes never are.

use crate::dolphin_identity_core::{self as rules, Backup, Identity, Start};
use hbb_common::{config::Config, log};
use std::path::{Path, PathBuf};
use std::time::Duration;

/// DPAPI's optional entropy: a backup is not a generic machine-scope blob another program would open by accident.
const ENTROPY: &[u8] = b"dolphin-connect identity v1";
/// SYSTEM and Administrators only, not inherited from %ProgramData% (where Users may read).
const SDDL: &str = "D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)";
const WATCH_EVERY: Duration = Duration::from_secs(5);

/// Called once at the start of the installed app's `--server` process, before the ID is registered. Restores, resets
/// or backs up per `rules::at_start`, then keeps the backup in step with the live identity in a small thread.
pub fn start() {
    if !crate::platform::is_installed() || !crate::is_server() || !crate::platform::is_root() {
        return;
    }
    if hbb_common::config::is_outgoing_only() {
        return;
    }
    let fingerprint = fingerprint();
    if fingerprint.is_none() {
        log::info!("identity backup (DD-5): this PC has no SMBIOS system UUID; not used");
        return;
    }
    let Some(dir) = backup_dir() else {
        return;
    };
    let fp = fingerprint.as_deref();
    let backup = read_backup(&dir);
    let decision = rules::at_start(fp, current().as_ref(), backup.as_ref());
    let mut last = rules::last_after_start(fp, backup.as_ref(), &decision);
    match &decision {
        Start::Skip | Start::Keep => {}
        Start::BackUp => {
            if let Some(c) = current() {
                if write_backup(&dir, fp, &c) {
                    last = Some(c);
                }
            }
        }
        Start::Restore(identity) => restore(identity),
        Start::Reset => reset(),
    }
    let fingerprint = fingerprint.unwrap_or_default();
    std::thread::spawn(move || watch(dir, fingerprint, last));
}

/// Every few seconds: back up the live identity when it changed (a key pair just generated, an ID the server made the
/// app change). Only string compares until something changed.
fn watch(dir: PathBuf, fingerprint: Vec<u8>, mut last: Option<Identity>) {
    loop {
        std::thread::sleep(WATCH_EVERY);
        let now = current();
        if rules::needs_backup(Some(&fingerprint), now.as_ref(), last.as_ref()) {
            if let Some(now) = now {
                if write_backup(&dir, Some(&fingerprint), &now) {
                    last = Some(now);
                }
            }
        }
    }
}

/// The config's identity, read without generating anything or touching the key-pair cache (upstream's
/// `get_existing_key_pair` would fill it). `None` while the config has no complete identity.
fn current() -> Option<Identity> {
    let v = serde_json::to_value(Config::get()).ok()?;
    let id = v.get("id").and_then(|x| x.as_str()).unwrap_or_default().to_owned();
    let (sk, pk): (Vec<u8>, Vec<u8>) = serde_json::from_value(v.get("key_pair")?.clone()).ok()?;
    let identity = Identity { id, sk, pk };
    identity.valid().then_some(identity)
}

/// The config with another ID and key pair, through its public serde form (`Config::set` stores it, encrypting the
/// ID as upstream does).
fn set_identity(id: Option<&str>, sk: Vec<u8>, pk: Vec<u8>) -> bool {
    let Ok(mut v) = serde_json::to_value(Config::get()) else {
        return false;
    };
    if let Some(id) = id {
        v["id"] = serde_json::json!(id);
    }
    v["key_pair"] = serde_json::json!([sk, pk]);
    match serde_json::from_value::<Config>(v) {
        Ok(cfg) => {
            Config::set(cfg);
            true
        }
        Err(_) => false,
    }
}

/// hbb_common caches the key pair once read and `Config::set` refreshes that cache only on macOS. Nothing in this
/// process reads it before `start()`, but if something ever did, a fresh process is the only way to use the new pair:
/// the service starts `--server` again, and then the config already matches.
fn restart_if_key_cached(expected_pk: Option<&[u8]>) {
    if let Some(cached) = Config::get_cached_pk() {
        if Some(&cached[..]) != expected_pk {
            log::warn!("identity (DD-5): the old key pair was already in use in this process; restarting --server");
            std::process::exit(0);
        }
    }
}

fn restore(identity: &Identity) {
    let before = Config::get_id();
    if set_identity(Some(&identity.id), identity.sk.clone(), identity.pk.clone()) {
        log::info!("identity (DD-5): restored the ID {} from the backup on this hardware (was {})", identity.id, before);
        restart_if_key_cached(Some(&identity.pk));
    } else {
        log::error!("identity (DD-5): could not restore the backup");
    }
}

/// A cloned disk on other hardware: a new ID and key pair, as upstream makes them (`update_id`, and the key pair the
/// next `get_key_pair` generates for an empty one).
fn reset() {
    log::warn!("identity (DD-5): this config and its backup came from other hardware (a cloned disk); making a new ID");
    if set_identity(None, Vec::new(), Vec::new()) {
        Config::update_id();
        restart_if_key_cached(None);
    } else {
        log::error!("identity (DD-5): could not reset the cloned identity");
    }
}

// ---- Windows calls ----

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

fn wide_path(p: &Path) -> Vec<u16> {
    use std::os::windows::ffi::OsStrExt;
    p.as_os_str().encode_wide().chain(std::iter::once(0)).collect()
}

/// SHA-256 of a context string and the SMBIOS system UUID.
fn fingerprint() -> Option<Vec<u8>> {
    use windows::Win32::System::SystemInformation::{GetSystemFirmwareTable, FIRMWARE_TABLE_PROVIDER};
    let rsmb = FIRMWARE_TABLE_PROVIDER(u32::from_be_bytes(*b"RSMB"));
    let size = unsafe { GetSystemFirmwareTable(rsmb, 0, None) } as usize;
    if size == 0 || size > 1 << 20 {
        return None;
    }
    let mut raw = vec![0u8; size];
    let got = unsafe { GetSystemFirmwareTable(rsmb, 0, Some(&mut raw)) } as usize;
    if got == 0 || got > raw.len() {
        return None;
    }
    let uuid = rules::system_uuid(&raw[..got])?;
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(b"dolphin-connect smbios uuid v1\0");
    h.update(uuid);
    Some(h.finalize().to_vec())
}

/// `%ProgramData%\<app>`, created SYSTEM/Administrators-only when missing. `None` (and nothing written) when the
/// folder is a link or belongs to someone else, which a normal user could have prepared.
fn backup_dir() -> Option<PathBuf> {
    let base = std::env::var_os("ProgramData").map(PathBuf::from).filter(|p| p.is_absolute())?;
    let dir = base.join(crate::get_app_name());
    match std::fs::symlink_metadata(&dir) {
        Ok(m) => {
            if m.file_type().is_symlink() || !m.is_dir() || !owned_by_system_or_admins(&dir) {
                log::warn!("identity backup (DD-5): {} is not a folder of SYSTEM or Administrators; not used", dir.display());
                return None;
            }
        }
        Err(_) => {
            if !with_security(|sa| unsafe {
                windows::Win32::Storage::FileSystem::CreateDirectoryW(
                    windows::core::PCWSTR(wide_path(&dir).as_ptr()),
                    Some(sa),
                )
                .is_ok()
            }) {
                log::warn!("identity backup (DD-5): could not create {}", dir.display());
                return None;
            }
        }
    }
    Some(dir)
}

/// Runs `f` with SECURITY_ATTRIBUTES for `SDDL`.
fn with_security(f: impl FnOnce(*const windows::Win32::Security::SECURITY_ATTRIBUTES) -> bool) -> bool {
    use windows::Win32::Foundation::{LocalFree, HLOCAL};
    use windows::Win32::Security::Authorization::{ConvertStringSecurityDescriptorToSecurityDescriptorW, SDDL_REVISION_1};
    use windows::Win32::Security::{PSECURITY_DESCRIPTOR, SECURITY_ATTRIBUTES};
    let sddl = wide(SDDL);
    let mut sd = PSECURITY_DESCRIPTOR::default();
    if unsafe {
        ConvertStringSecurityDescriptorToSecurityDescriptorW(windows::core::PCWSTR(sddl.as_ptr()), SDDL_REVISION_1, &mut sd, None)
    }
    .is_err()
    {
        return false;
    }
    let sa = SECURITY_ATTRIBUTES {
        nLength: std::mem::size_of::<SECURITY_ATTRIBUTES>() as u32,
        lpSecurityDescriptor: sd.0,
        bInheritHandle: false.into(),
    };
    let ok = f(&sa);
    unsafe {
        LocalFree(Some(HLOCAL(sd.0)));
    }
    ok
}

fn owned_by_system_or_admins(path: &Path) -> bool {
    use windows::Win32::Foundation::{LocalFree, ERROR_SUCCESS, HLOCAL};
    use windows::Win32::Security::Authorization::{GetNamedSecurityInfoW, SE_FILE_OBJECT};
    use windows::Win32::Security::{
        IsWellKnownSid, WinBuiltinAdministratorsSid, WinLocalSystemSid, OWNER_SECURITY_INFORMATION, PSECURITY_DESCRIPTOR,
        PSID,
    };
    let name = wide_path(path);
    let mut owner = PSID::default();
    let mut sd = PSECURITY_DESCRIPTOR::default();
    let err = unsafe {
        GetNamedSecurityInfoW(
            windows::core::PCWSTR(name.as_ptr()),
            SE_FILE_OBJECT,
            OWNER_SECURITY_INFORMATION,
            Some(&mut owner),
            None,
            None,
            None,
            &mut sd,
        )
    };
    if err != ERROR_SUCCESS {
        return false;
    }
    let ok = unsafe {
        IsWellKnownSid(owner, WinLocalSystemSid).as_bool() || IsWellKnownSid(owner, WinBuiltinAdministratorsSid).as_bool()
    };
    unsafe {
        LocalFree(Some(HLOCAL(sd.0)));
    }
    ok
}

/// The backup, if there is one this process can trust: owned by SYSTEM or Administrators (a user cannot plant one),
/// decrypted, and a version-1 file. Anything else counts as no backup.
fn read_backup(dir: &Path) -> Option<Backup> {
    let path = dir.join(rules::FILE_NAME);
    let meta = std::fs::symlink_metadata(&path).ok()?;
    if meta.file_type().is_symlink() || !meta.is_file() || meta.len() > 64 * 1024 || !owned_by_system_or_admins(&path) {
        return None;
    }
    let sealed = std::fs::read(&path).ok()?;
    let mut plain = dpapi::unprotect(&sealed)?;
    let backup = rules::decode(&plain);
    plain.iter_mut().for_each(|b| *b = 0);
    if backup.is_none() {
        log::warn!("identity backup (DD-5): {} is not a backup this version reads; it will be replaced", path.display());
    }
    backup
}

/// Writes a new file with the SYSTEM/Administrators-only DACL, then moves it over the old one, so a reader never sees
/// half a file and an existing file's looser rights never carry over.
fn write_backup(dir: &Path, fingerprint: Option<&[u8]>, identity: &Identity) -> bool {
    let Some(fingerprint) = fingerprint else {
        return false;
    };
    let mut plain = rules::encode(&Backup { fingerprint: fingerprint.to_vec(), identity: identity.clone() });
    let sealed = dpapi::protect(&plain);
    plain.iter_mut().for_each(|b| *b = 0);
    let Some(sealed) = sealed else {
        log::warn!("identity backup (DD-5): DPAPI refused to protect the backup");
        return false;
    };
    let tmp = dir.join(format!("{}.tmp", rules::FILE_NAME));
    let path = dir.join(rules::FILE_NAME);
    std::fs::remove_file(&tmp).ok();
    let written = with_security(|sa| create_new_with(&tmp, sa, &sealed));
    let moved = written
        && unsafe {
            use windows::Win32::Storage::FileSystem::{MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH};
            MoveFileExW(
                windows::core::PCWSTR(wide_path(&tmp).as_ptr()),
                windows::core::PCWSTR(wide_path(&path).as_ptr()),
                MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
            )
            .is_ok()
        };
    if moved {
        log::info!("identity backup (DD-5): saved the ID {}", identity.id);
    } else {
        std::fs::remove_file(&tmp).ok();
        log::warn!("identity backup (DD-5): could not write {}", path.display());
    }
    moved
}

fn create_new_with(path: &Path, sa: *const windows::Win32::Security::SECURITY_ATTRIBUTES, data: &[u8]) -> bool {
    use std::io::Write;
    use std::os::windows::io::FromRawHandle;
    use windows::Win32::Storage::FileSystem::{CreateFileW, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, FILE_GENERIC_WRITE, FILE_SHARE_MODE};
    let handle = unsafe {
        CreateFileW(
            windows::core::PCWSTR(wide_path(path).as_ptr()),
            FILE_GENERIC_WRITE.0,
            FILE_SHARE_MODE(0),
            Some(sa),
            CREATE_NEW,
            FILE_ATTRIBUTE_NORMAL,
            None,
        )
    };
    let Ok(handle) = handle else {
        return false;
    };
    let mut file = unsafe { std::fs::File::from_raw_handle(handle.0 as _) };
    file.write_all(data).is_ok() && file.sync_all().is_ok()
}

/// DPAPI, machine scope (`CRYPTPROTECT_LOCAL_MACHINE`): any account on this PC could decrypt it, so the file's DACL is
/// what keeps it to SYSTEM and Administrators; DPAPI keeps it to this Windows installation.
mod dpapi {
    use std::ffi::c_void;

    #[repr(C)]
    struct Blob {
        cb: u32,
        pb: *mut u8,
    }

    const CRYPTPROTECT_UI_FORBIDDEN: u32 = 0x1;
    const CRYPTPROTECT_LOCAL_MACHINE: u32 = 0x4;

    #[link(name = "crypt32")]
    extern "system" {
        fn CryptProtectData(
            data_in: *const Blob,
            description: *const u16,
            entropy: *const Blob,
            reserved: *mut c_void,
            prompt: *mut c_void,
            flags: u32,
            data_out: *mut Blob,
        ) -> i32;
        fn CryptUnprotectData(
            data_in: *const Blob,
            description: *mut *mut u16,
            entropy: *const Blob,
            reserved: *mut c_void,
            prompt: *mut c_void,
            flags: u32,
            data_out: *mut Blob,
        ) -> i32;
    }

    #[link(name = "kernel32")]
    extern "system" {
        fn LocalFree(mem: *mut c_void) -> *mut c_void;
    }

    fn blob(data: &[u8]) -> Blob {
        Blob { cb: data.len() as u32, pb: data.as_ptr() as *mut u8 }
    }

    fn take(out: Blob) -> Vec<u8> {
        let v = unsafe { std::slice::from_raw_parts(out.pb, out.cb as usize) }.to_vec();
        unsafe {
            std::ptr::write_bytes(out.pb, 0, out.cb as usize);
            LocalFree(out.pb as *mut c_void);
        }
        v
    }

    pub fn protect(plain: &[u8]) -> Option<Vec<u8>> {
        let (input, entropy) = (blob(plain), blob(super::ENTROPY));
        let mut out = Blob { cb: 0, pb: std::ptr::null_mut() };
        let ok = unsafe {
            CryptProtectData(
                &input,
                std::ptr::null(),
                &entropy,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                CRYPTPROTECT_UI_FORBIDDEN | CRYPTPROTECT_LOCAL_MACHINE,
                &mut out,
            )
        };
        (ok != 0 && !out.pb.is_null()).then(|| take(out))
    }

    pub fn unprotect(sealed: &[u8]) -> Option<Vec<u8>> {
        let (input, entropy) = (blob(sealed), blob(super::ENTROPY));
        let mut out = Blob { cb: 0, pb: std::ptr::null_mut() };
        let ok = unsafe {
            CryptUnprotectData(
                &input,
                std::ptr::null_mut(),
                &entropy,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut out,
            )
        };
        (ok != 0 && !out.pb.is_null()).then(|| take(out))
    }
}
