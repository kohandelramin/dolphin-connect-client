//! Dolphin Connect, Plan 18 Phase 5 (DD-5): the same ID after a reinstall. The installed app keeps a copy of its ID and
//! key pair in `%ProgramData%\<app>\identity.dat` (DPAPI, machine scope), tied to a fingerprint of the PC's SMBIOS system
//! UUID (not Windows' MachineGuid, which a cloned disk copies). This file holds the rules: reading the UUID out of the
//! raw SMBIOS table, the file format, and what to do when the server process starts. `src/dolphin_identity.rs` makes
//! the Windows calls. Standard library only, so CI tests it alone
//! (`rustc --edition 2021 --test src/dolphin_identity_core.rs`).
//!
//! The rule at start (`at_start`), with the fingerprint of this PC's hardware:
//! - no fingerprint (no SMBIOS UUID, or one of the placeholder values all 00 / all FF): do nothing at all;
//! - no usable backup: back up the current identity (once it has a key pair);
//! - a backup made on this hardware: if the config holds another identity, restore the backup. While the server runs
//!   the backup follows every change of the live identity (`needs_backup`, checked every few seconds), so a difference
//!   at start means the identity was replaced while our server was not running: the config was deleted and generated
//!   again, or an install imported a portable copy's fresh identity;
//! - a backup made on other hardware: if the config holds that very identity, the disk was cloned (the config came
//!   along with the backup), so a new ID and key pair are made, or two PCs would answer to one ID; otherwise the
//!   backup is replaced by this PC's own identity.

pub const FILE_NAME: &str = "identity.dat";
const MAGIC: &[u8; 4] = b"DCID";
pub const FORMAT_VERSION: u8 = 1;
/// SHA-256 of the UUID, made by the caller.
pub const FINGERPRINT_LEN: usize = 32;
/// libsodium's Ed25519 secret key (seed then public key) and public key, as hbb_common's config keeps them.
pub const SECRET_KEY_LEN: usize = 64;
pub const PUBLIC_KEY_LEN: usize = 32;

#[derive(Clone, PartialEq, Eq)]
pub struct Identity {
    pub id: String,
    pub sk: Vec<u8>,
    pub pk: Vec<u8>,
}

// The secret key never reaches a log, even through a `{:?}` by mistake.
impl std::fmt::Debug for Identity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Identity").field("id", &self.id).finish_non_exhaustive()
    }
}

impl Identity {
    /// A complete identity: an ID the server accepts (letters, digits, `-` and `_`, as the portal requires, at most
    /// 64) and a matching Ed25519 pair (libsodium's secret key ends with its public key).
    pub fn valid(&self) -> bool {
        !self.id.is_empty()
            && self.id.len() <= 64
            && self.id.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-' || c == b'_')
            && self.sk.len() == SECRET_KEY_LEN
            && self.pk.len() == PUBLIC_KEY_LEN
            && self.sk[32..] == self.pk[..]
    }

    /// The same PC identity as far as the rendezvous server is concerned: ID and public key.
    pub fn same_as(&self, other: &Identity) -> bool {
        self.id == other.id && self.pk == other.pk
    }
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Backup {
    pub fingerprint: Vec<u8>,
    pub identity: Identity,
}

/// The plain bytes DPAPI protects: `DCID`, the version byte, then fingerprint, ID, secret key and public key, each
/// with a one-byte length.
pub fn encode(b: &Backup) -> Vec<u8> {
    let mut out = Vec::with_capacity(5 + 4 + b.fingerprint.len() + b.identity.id.len() + 96);
    out.extend_from_slice(MAGIC);
    out.push(FORMAT_VERSION);
    for field in [&b.fingerprint[..], b.identity.id.as_bytes(), &b.identity.sk, &b.identity.pk] {
        out.push(field.len() as u8);
        out.extend_from_slice(field);
    }
    out
}

/// `None` for anything that is not exactly a version-1 file with a valid identity: an unknown version is treated as
/// no backup (the caller writes its own), never guessed at.
pub fn decode(bytes: &[u8]) -> Option<Backup> {
    let rest = bytes.strip_prefix(&MAGIC[..])?;
    let (&version, mut rest) = rest.split_first()?;
    if version != FORMAT_VERSION {
        return None;
    }
    let mut fields = Vec::with_capacity(4);
    for _ in 0..4 {
        let (&len, tail) = rest.split_first()?;
        let len = len as usize;
        if tail.len() < len {
            return None;
        }
        fields.push(tail[..len].to_vec());
        rest = &tail[len..];
    }
    if !rest.is_empty() {
        return None;
    }
    let pk = fields.pop()?;
    let sk = fields.pop()?;
    let id = String::from_utf8(fields.pop()?).ok()?;
    let fingerprint = fields.pop()?;
    let identity = Identity { id, sk, pk };
    (fingerprint.len() == FINGERPRINT_LEN && identity.valid()).then_some(Backup { fingerprint, identity })
}

/// The SMBIOS system UUID (structure type 1, bytes 8..24) from what `GetSystemFirmwareTable('RSMB', 0)` returns: a
/// `RawSMBIOSData` header (calling method, major, minor, DMI revision, then the table length as u32) and the table.
/// `None` when it is missing or a placeholder (all 00: not present; all FF: not set), so such PCs are never matched.
pub fn system_uuid(raw: &[u8]) -> Option<[u8; 16]> {
    let header = raw.get(..8)?;
    let len = u32::from_le_bytes([header[4], header[5], header[6], header[7]]) as usize;
    let table = raw.get(8..8usize.checked_add(len)?)?;
    let mut i = 0usize;
    while i + 4 <= table.len() {
        let kind = table[i];
        let formatted = table[i + 1] as usize;
        if formatted < 4 || i + formatted > table.len() {
            return None;
        }
        if kind == 1 && formatted >= 0x19 {
            let uuid: [u8; 16] = table[i + 8..i + 24].try_into().ok()?;
            if uuid.iter().all(|&b| b == 0) || uuid.iter().all(|&b| b == 0xff) {
                return None;
            }
            return Some(uuid);
        }
        if kind == 127 {
            return None; // end of table
        }
        // The strings follow the formatted area and end with two zero bytes.
        let mut j = i + formatted;
        while j + 1 < table.len() && !(table[j] == 0 && table[j + 1] == 0) {
            j += 1;
        }
        i = j + 2;
    }
    None
}

#[derive(Debug, PartialEq, Eq)]
pub enum Start {
    /// No fingerprint, or nothing to write yet (no key pair): touch nothing.
    Skip,
    /// The config already holds the backed-up identity.
    Keep,
    /// Write the current identity as the backup.
    BackUp,
    /// Put the backed-up identity into the config before the app registers with the server.
    Restore(Identity),
    /// A cloned disk: make a new ID and key pair (the backup follows once the key pair exists).
    Reset,
}

/// What to do when the server process starts. `current` is the config's identity, `None` while it has no key pair
/// yet (a config just generated).
pub fn at_start(fingerprint: Option<&[u8]>, current: Option<&Identity>, backup: Option<&Backup>) -> Start {
    let Some(fingerprint) = fingerprint else {
        return Start::Skip;
    };
    let current = current.filter(|c| c.valid());
    let Some(backup) = backup else {
        return if current.is_some() { Start::BackUp } else { Start::Skip };
    };
    if backup.fingerprint == fingerprint {
        return match current {
            Some(c) if c.same_as(&backup.identity) && c.sk == backup.identity.sk => Start::Keep,
            _ => Start::Restore(backup.identity.clone()),
        };
    }
    match current {
        Some(c) if c.same_as(&backup.identity) => Start::Reset,
        Some(_) => Start::BackUp,
        None => Start::Skip,
    }
}

/// While the server runs: write the backup when the live identity is complete and differs from the last one written
/// (an ID changed by the server, a key pair just generated). `last` is `None` until this run wrote or confirmed one.
pub fn needs_backup(fingerprint: Option<&[u8]>, current: Option<&Identity>, last: Option<&Identity>) -> bool {
    match (fingerprint, current) {
        (Some(_), Some(c)) if c.valid() => last != Some(c),
        _ => false,
    }
}

/// The backup this run starts from, for `needs_backup`: the file's identity when it was made on this hardware (and so
/// is now the config's too), otherwise none, so the first complete identity replaces a foreign backup.
pub fn last_after_start(fingerprint: Option<&[u8]>, backup: Option<&Backup>, decision: &Start) -> Option<Identity> {
    match (fingerprint, backup, decision) {
        (Some(f), Some(b), Start::Keep | Start::Restore(_)) if b.fingerprint == f => Some(b.identity.clone()),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn identity(id: &str, seed: u8) -> Identity {
        let pk = vec![seed.wrapping_add(1); 32];
        let mut sk = vec![seed; 32];
        sk.extend_from_slice(&pk);
        Identity { id: id.to_owned(), sk, pk }
    }

    const FP: [u8; 32] = [7; 32];
    const OTHER_FP: [u8; 32] = [8; 32];

    fn backup(fp: [u8; 32], id: &Identity) -> Backup {
        Backup { fingerprint: fp.to_vec(), identity: id.clone() }
    }

    #[test]
    fn the_file_round_trips_with_its_version_byte() {
        let b = backup(FP, &identity("123456789", 3));
        let bytes = encode(&b);
        assert_eq!(&bytes[..5], b"DCID\x01");
        assert_eq!(bytes.len(), 5 + 1 + 32 + 1 + 9 + 1 + 64 + 1 + 32);
        assert_eq!(decode(&bytes), Some(b));
    }

    #[test]
    fn a_damaged_or_unknown_file_is_no_backup() {
        let bytes = encode(&backup(FP, &identity("123456789", 3)));
        assert_eq!(decode(&[]), None);
        assert_eq!(decode(&bytes[..bytes.len() - 1]), None); // cut short
        let mut longer = bytes.clone();
        longer.push(0);
        assert_eq!(decode(&longer), None); // trailing bytes
        let mut v2 = bytes.clone();
        v2[4] = 2;
        assert_eq!(decode(&v2), None); // a later format is not guessed at
        let mut magic = bytes.clone();
        magic[0] = b'X';
        assert_eq!(decode(&magic), None);
        let mut key = bytes.clone();
        let last = key.len() - 1;
        key[last] ^= 1; // the public key no longer matches the secret key
        assert_eq!(decode(&key), None);
        let short_fp = Backup { fingerprint: vec![1; 16], identity: identity("123456789", 3) };
        assert_eq!(decode(&encode(&short_fp)), None);
        assert_eq!(decode(&encode(&backup(FP, &identity("12 34", 3)))), None);
    }

    #[test]
    fn identities_must_be_complete() {
        assert!(identity("123456789", 1).valid());
        assert!(identity("abc_DEF-1", 1).valid());
        assert!(!identity("", 1).valid());
        assert!(!identity("123 456", 1).valid());
        assert!(!identity(&"9".repeat(65), 1).valid());
        let mut no_key = identity("123456789", 1);
        no_key.sk.clear();
        no_key.pk.clear();
        assert!(!no_key.valid());
    }

    #[test]
    fn the_debug_form_never_shows_the_key() {
        let shown = format!("{:?}", identity("123456789", 0xAB));
        assert!(shown.contains("123456789"));
        assert!(!shown.contains("171")); // 0xAB
        assert!(!shown.contains("sk"));
    }

    #[test]
    fn without_a_fingerprint_nothing_happens() {
        let id = identity("123456789", 1);
        assert_eq!(at_start(None, Some(&id), None), Start::Skip);
        assert_eq!(at_start(None, Some(&id), Some(&backup(FP, &identity("222333444", 2)))), Start::Skip);
        assert!(!needs_backup(None, Some(&id), None));
    }

    #[test]
    fn the_first_run_backs_up_once_the_key_pair_exists() {
        let id = identity("123456789", 1);
        assert_eq!(at_start(Some(&FP), Some(&id), None), Start::BackUp);
        let mut fresh = id.clone();
        fresh.sk.clear();
        fresh.pk.clear();
        assert_eq!(at_start(Some(&FP), Some(&fresh), None), Start::Skip);
        assert_eq!(at_start(Some(&FP), None, None), Start::Skip);
        assert!(needs_backup(Some(&FP), Some(&id), None));
    }

    #[test]
    fn a_reinstall_on_the_same_hardware_gets_its_identity_back() {
        let old = identity("123456789", 1);
        let b = backup(FP, &old);
        // The config was deleted: a new ID, no key pair yet.
        assert_eq!(at_start(Some(&FP), None, Some(&b)), Start::Restore(old.clone()));
        // An install imported a portable copy's fresh identity (same MAC-made ID, new keys, or a new ID).
        assert_eq!(at_start(Some(&FP), Some(&identity("123456789", 9)), Some(&b)), Start::Restore(old.clone()));
        assert_eq!(at_start(Some(&FP), Some(&identity("1987654321", 9)), Some(&b)), Start::Restore(old.clone()));
        // Same ID and public key but another secret key cannot happen honestly; the backup wins.
        let mut odd = old.clone();
        odd.sk[0] ^= 1;
        assert_eq!(at_start(Some(&FP), Some(&odd), Some(&b)), Start::Restore(old.clone()));
        assert_eq!(at_start(Some(&FP), Some(&old), Some(&b)), Start::Keep);
    }

    #[test]
    fn other_hardware_never_takes_the_backup() {
        let old = identity("123456789", 1);
        let b = backup(OTHER_FP, &old);
        let own = identity("555666777", 5);
        assert_eq!(at_start(Some(&FP), Some(&own), Some(&b)), Start::BackUp);
        assert_eq!(at_start(Some(&FP), None, Some(&b)), Start::Skip);
        // The watcher then replaces the foreign backup with this PC's own identity.
        assert_eq!(last_after_start(Some(&FP), Some(&b), &Start::BackUp), None);
        assert!(needs_backup(Some(&FP), Some(&own), None));
    }

    #[test]
    fn a_cloned_disk_gets_a_new_identity() {
        let old = identity("123456789", 1);
        let b = backup(OTHER_FP, &old);
        assert_eq!(at_start(Some(&FP), Some(&old), Some(&b)), Start::Reset);
        // Only the ID and public key matter: the same pair under another ID is this PC's own identity.
        assert_eq!(at_start(Some(&FP), Some(&identity("999888777", 1)), Some(&b)), Start::BackUp);
    }

    #[test]
    fn the_backup_follows_the_live_identity() {
        let old = identity("123456789", 1);
        let b = backup(FP, &old);
        let last = last_after_start(Some(&FP), Some(&b), &Start::Restore(old.clone()));
        assert_eq!(last.as_ref(), Some(&old));
        assert_eq!(last_after_start(Some(&FP), Some(&b), &Start::Keep).as_ref(), Some(&old));
        assert!(!needs_backup(Some(&FP), Some(&old), last.as_ref()));
        // The server refused the ID (UUID_MISMATCH) and the app took a new one: written within one check.
        let changed = Identity { id: "1555666777".to_owned(), ..old.clone() };
        assert!(needs_backup(Some(&FP), Some(&changed), last.as_ref()));
        // A config without a key pair is never written over a good backup.
        assert!(!needs_backup(Some(&FP), None, last.as_ref()));
        let mut incomplete = old.clone();
        incomplete.pk.clear();
        assert!(!needs_backup(Some(&FP), Some(&incomplete), last.as_ref()));
    }

    fn smbios(structures: &[Vec<u8>]) -> Vec<u8> {
        let table: Vec<u8> = structures.concat();
        let mut raw = vec![0, 3, 4, 0];
        raw.extend_from_slice(&(table.len() as u32).to_le_bytes());
        raw.extend_from_slice(&table);
        raw
    }

    fn structure(kind: u8, formatted: &[u8], strings: &[&str]) -> Vec<u8> {
        let mut s = vec![kind, (4 + formatted.len()) as u8, 0x00, 0x01];
        s.extend_from_slice(formatted);
        if strings.is_empty() {
            s.extend_from_slice(&[0, 0]);
        } else {
            for t in strings {
                s.extend_from_slice(t.as_bytes());
                s.push(0);
            }
            s.push(0);
        }
        s
    }

    fn system_info(uuid: [u8; 16]) -> Vec<u8> {
        // Type 1, SMBIOS 2.4 layout: manufacturer, product, version, serial (string numbers), UUID, wake-up type,
        // SKU, family: 0x1B bytes in all.
        let mut f = vec![1, 2, 3, 4];
        f.extend_from_slice(&uuid);
        f.extend_from_slice(&[6, 5, 6]);
        structure(1, &f, &["Maker", "Model", "1.0", "SN123", "SKU", "Family"])
    }

    #[test]
    fn the_uuid_is_read_from_the_system_structure() {
        let uuid: [u8; 16] = core::array::from_fn(|i| i as u8 + 1);
        let bios = structure(0, &[1, 2, 0, 0xf0, 3, 0x7f, 0, 0, 0, 0, 0, 0, 0, 0], &["Vendor", "1.2", "01/01/2024"]);
        let raw = smbios(&[bios.clone(), system_info(uuid), structure(127, &[], &[])]);
        assert_eq!(system_uuid(&raw), Some(uuid));
        // A structure with no strings ends in two zero bytes too.
        let raw = smbios(&[structure(3, &[0; 9], &[]), system_info(uuid)]);
        assert_eq!(system_uuid(&raw), Some(uuid));
    }

    #[test]
    fn placeholder_or_missing_uuids_are_no_fingerprint() {
        assert_eq!(system_uuid(&smbios(&[system_info([0; 16])])), None);
        assert_eq!(system_uuid(&smbios(&[system_info([0xff; 16])])), None);
        assert_eq!(system_uuid(&smbios(&[structure(127, &[], &[]), system_info([5; 16])])), None);
        // SMBIOS 2.0's type 1 is 8 bytes long: no UUID in it.
        assert_eq!(system_uuid(&smbios(&[structure(1, &[1, 2, 3, 4], &["a", "b", "c", "d"])])), None);
        assert_eq!(system_uuid(&[]), None);
        assert_eq!(system_uuid(&[0, 3, 4, 0, 0xff, 0, 0, 0]), None); // length past the end
        let mut bad = smbios(&[system_info([5; 16])]);
        bad[9] = 2; // a formatted length under the 4-byte header
        assert_eq!(system_uuid(&bad), None);
    }
}
