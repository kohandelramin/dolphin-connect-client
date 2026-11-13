//! Dolphin Connect, Plan 18 Phase 5 (DD-10): Wake-on-LAN through another online PC of the same organization. The
//! rules, standard library only, so CI tests them alone (`rustc --edition 2021 --test src/dolphin_wake_core.rs`); the app
//! side is src/dolphin_wake.rs, hooked in src/hbbs_http/sync.rs (marked `Dolphin Connect (DD-10)`).
//!
//! Contract (2026-11-13, portal app/src/lib/wake.ts): every app reports in sysinfo `dolphin_macs` (up to 8 MACs of its
//! physical Ethernet / Wi-Fi adapters, `AA:BB:CC:DD:EE:FF`, wired first) and `dolphin_lan` (up to 8 IPv4
//! `address/prefix`). A helper's heartbeat answer carries the option `dolphin-wake` =
//! `{"n": nonce, "macs": [...], "bcast": [...], "until": unix}`; while `until` is ahead and the nonce is new, the helper
//! sends the magic packet (6 × FF + 16 × MAC) by UDP to each `bcast` and 255.255.255.255, port 9, three times a second
//! apart, once per nonce, then reports `dolphin_wake: nonce` in its heartbeats until one is acknowledged. Only when the
//! helper's own `wake-on-lan` switch is not hidden.
//!
//! A few UDP packets on the helper's own LAN: never session traffic, no change to any connection.

use std::net::Ipv4Addr;

/// The option the portal pushes to the helper.
pub const WAKE_OPTION: &str = "dolphin-wake";
/// The portal's feature switch (DD-4); hidden by default, like every key the app does not list.
pub const SWITCH_WAKE_ON_LAN: &str = "wake-on-lan";
/// Heartbeat field: the nonce whose packets went out.
pub const HEARTBEAT_FIELD: &str = "dolphin_wake";
/// Sysinfo fields.
pub const SYSINFO_MACS: &str = "dolphin_macs";
pub const SYSINFO_LAN: &str = "dolphin_lan";

/// At most this many MACs, broadcast addresses, LAN entries.
pub const MAX_ITEMS: usize = 8;
/// The portal's nonce is a UUID (36 characters); the heartbeat field takes at most 64.
pub const NONCE_MIN: usize = 8;
pub const NONCE_MAX: usize = 64;
/// The Wake-on-LAN "discard" port.
pub const PORT: u16 = 9;
pub const ROUNDS: usize = 3;
pub const ROUND_GAP_MS: u64 = 1000;
/// The portal keeps a request 2 minutes; an `until` further ahead than this is refused (a wrong clock or a bad push).
pub const UNTIL_MAX_AHEAD_SECS: i64 = 600;
/// How often the app looks again whether its adapters changed (then sysinfo is sent again).
pub const LAN_RECHECK_SECS: u64 = 600;

pub const MAGIC_LEN: usize = 102;

/// `AA:BB:CC:DD:EE:FF` (either case, colons only). Not all zero, not a group (multicast or broadcast) address.
pub fn parse_mac(s: &str) -> Option<[u8; 6]> {
    let parts: Vec<&str> = s.split(':').collect();
    if parts.len() != 6 {
        return None;
    }
    let mut mac = [0u8; 6];
    for (i, p) in parts.iter().enumerate() {
        if p.len() != 2 || !p.chars().all(|c| c.is_ascii_hexdigit()) {
            return None;
        }
        mac[i] = u8::from_str_radix(p, 16).ok()?;
    }
    if mac == [0; 6] || mac[0] & 0x01 != 0 {
        return None;
    }
    Some(mac)
}

/// Upper case with colons, as the portal stores it.
pub fn format_mac(mac: &[u8; 6]) -> String {
    mac.iter().map(|b| format!("{:02X}", b)).collect::<Vec<_>>().join(":")
}

/// 6 × 0xFF, then the MAC 16 times.
pub fn magic_packet(mac: &[u8; 6]) -> [u8; MAGIC_LEN] {
    let mut p = [0xFFu8; MAGIC_LEN];
    for i in 0..16 {
        p[6 + i * 6..12 + i * 6].copy_from_slice(mac);
    }
    p
}

/// Printable ASCII without spaces, quotes or backslashes, [`NONCE_MIN`]..=[`NONCE_MAX`] long.
pub fn valid_nonce(s: &str) -> bool {
    (NONCE_MIN..=NONCE_MAX).contains(&s.len()) && s.chars().all(|c| c.is_ascii_graphic() && c != '"' && c != '\\')
}

/// The directed broadcast address of `addr/prefix`; `None` for a /31 or /32 (no broadcast to use) or a bad prefix.
pub fn directed_broadcast(addr: Ipv4Addr, prefix: u8) -> Option<Ipv4Addr> {
    if prefix > 30 {
        return None;
    }
    let host = if prefix == 0 { u32::MAX } else { u32::MAX >> prefix };
    Some(Ipv4Addr::from(u32::from(addr) | host))
}

/// A `bcast` entry the helper may send to: an IPv4 address that is the broadcast address of one of its own subnets
/// (the portal picks the helper by a subnet in common, so it is always one). Never a host, a public or another
/// network's address.
pub fn parse_bcast(s: &str, local: &[(Ipv4Addr, u8)]) -> Option<Ipv4Addr> {
    let addr: Ipv4Addr = s.trim().parse().ok()?;
    if addr == Ipv4Addr::BROADCAST {
        return Some(addr);
    }
    local
        .iter()
        .any(|&(a, p)| directed_broadcast(a, p) == Some(addr))
        .then_some(addr)
}

/// What the helper sends.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Job {
    pub nonce: String,
    pub macs: Vec<[u8; 6]>,
    /// Each `bcast`, then 255.255.255.255; no repeats.
    pub targets: Vec<Ipv4Addr>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Reject {
    Nonce,
    Macs,
    Bcast,
    Expired,
    TooFar,
}

/// The pushed request, checked whole: any bad part refuses it all (nothing is sent, nothing reported).
pub fn job(nonce: &str, macs: &[String], bcast: &[String], until: i64, now: i64, local: &[(Ipv4Addr, u8)]) -> Result<Job, Reject> {
    if !valid_nonce(nonce) {
        return Err(Reject::Nonce);
    }
    if until <= now {
        return Err(Reject::Expired);
    }
    if until - now > UNTIL_MAX_AHEAD_SECS {
        return Err(Reject::TooFar);
    }
    if macs.is_empty() || macs.len() > MAX_ITEMS {
        return Err(Reject::Macs);
    }
    let mut parsed = Vec::new();
    for m in macs {
        let mac = parse_mac(m.trim()).ok_or(Reject::Macs)?;
        if !parsed.contains(&mac) {
            parsed.push(mac);
        }
    }
    if bcast.len() > MAX_ITEMS {
        return Err(Reject::Bcast);
    }
    let mut targets = Vec::new();
    for b in bcast {
        let addr = parse_bcast(b, local).ok_or(Reject::Bcast)?;
        if !targets.contains(&addr) {
            targets.push(addr);
        }
    }
    if !targets.contains(&Ipv4Addr::BROADCAST) {
        targets.push(Ipv4Addr::BROADCAST);
    }
    Ok(Job { nonce: nonce.to_owned(), macs: parsed, targets })
}

// ---- what this PC reports in sysinfo ----

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Medium {
    Wired,
    Wireless,
}

/// Windows' interface type (IANA ifType, `IP_ADAPTER_ADDRESSES.IfType`): the Ethernet kinds and 802.11. Tunnels (131),
/// PPP (23), loopback (24), mobile broadband and the rest are not adapters a magic packet can wake.
pub fn medium(if_type: u32) -> Option<Medium> {
    match if_type {
        6 | 26 | 62 | 69 | 117 => Some(Medium::Wired),
        71 => Some(Medium::Wireless),
        _ => None,
    }
}

/// Virtual adapters that report the Ethernet type (Hyper-V, VMware, VirtualBox, VPN TAP / Wintun drivers, Bluetooth
/// PAN, ...), by their description.
pub fn looks_virtual(description: &str) -> bool {
    const WORDS: &[&str] = &[
        "virtual", "vpn", "tap-", "tap ", "tunnel", "hyper-v", "vmware", "virtualbox", "vbox", "loopback",
        "bluetooth", "wan miniport", "npcap", "wireguard", "wintun", "zerotier", "tailscale", "openvpn", "fortinet",
        "anyconnect", "pangp", "teredo", "isatap", "6to4", "kernel debug", "hamachi", "docker", "wsl", "pseudo",
        "wi-fi direct", "sstp", "l2tp", "pptp", "ikev2", "parallels", "qemu", "kvm",
    ];
    let d = description.to_lowercase();
    WORDS.iter().any(|w| d.contains(w))
}

/// MAC prefixes of virtual machines' adapters (VMware, VirtualBox, Hyper-V, Parallels, QEMU).
pub fn virtual_mac(mac: &[u8; 6]) -> bool {
    const OUIS: &[[u8; 3]] = &[
        [0x00, 0x05, 0x69],
        [0x00, 0x0C, 0x29],
        [0x00, 0x1C, 0x14],
        [0x00, 0x50, 0x56],
        [0x08, 0x00, 0x27],
        [0x0A, 0x00, 0x27],
        [0x00, 0x15, 0x5D],
        [0x00, 0x1C, 0x42],
        [0x52, 0x54, 0x00],
    ];
    OUIS.iter().any(|o| mac[..3] == o[..])
}

/// One adapter as Windows lists it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Adapter {
    pub if_type: u32,
    pub description: String,
    pub mac: Option<[u8; 6]>,
    pub ipv4: Vec<(Ipv4Addr, u8)>,
}

/// A physical Ethernet or Wi-Fi adapter with a real, burned-in address: not virtual by description or prefix, not a
/// locally administered address (set by software: VPNs, VMs, random Wi-Fi addresses, which a sleeping card does not
/// answer to).
pub fn physical(a: &Adapter) -> Option<Medium> {
    let m = medium(a.if_type)?;
    let mac = a.mac?;
    if mac == [0; 6] || mac[0] & 0x03 != 0 || virtual_mac(&mac) || looks_virtual(&a.description) {
        return None;
    }
    Some(m)
}

fn ordered(adapters: &[Adapter]) -> Vec<&Adapter> {
    let mut wired: Vec<&Adapter> = adapters.iter().filter(|a| physical(a) == Some(Medium::Wired)).collect();
    wired.extend(adapters.iter().filter(|a| physical(a) == Some(Medium::Wireless)));
    wired
}

/// `dolphin_macs`: wired first, no repeats, at most [`MAX_ITEMS`].
pub fn report_macs(adapters: &[Adapter]) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for a in ordered(adapters) {
        let s = format_mac(&a.mac.unwrap_or_default());
        if !out.contains(&s) {
            out.push(s);
        }
        if out.len() == MAX_ITEMS {
            break;
        }
    }
    out
}

/// `dolphin_lan`: `address/prefix` of the physical adapters' usable IPv4 addresses (no loopback, link-local or
/// unspecified address, prefix 1..=32), wired first, at most [`MAX_ITEMS`]. VPN addresses are left out with their
/// adapters, so the portal never takes a VPN for a shared LAN.
pub fn report_lan(adapters: &[Adapter]) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for a in ordered(adapters) {
        for &(addr, prefix) in &a.ipv4 {
            if addr.is_loopback() || addr.is_link_local() || addr.is_unspecified() || !(1..=32).contains(&prefix) {
                continue;
            }
            let s = format!("{}/{}", addr, prefix);
            if !out.contains(&s) {
                out.push(s);
            }
            if out.len() == MAX_ITEMS {
                return out;
            }
        }
    }
    out
}

/// This PC's own subnets, for [`parse_bcast`].
pub fn local_subnets(adapters: &[Adapter]) -> Vec<(Ipv4Addr, u8)> {
    ordered(adapters).iter().flat_map(|a| a.ipv4.iter().copied()).collect()
}

// ---- once per nonce, reported until acknowledged ----

/// The helper's memory of what it did (in memory only: after a restart within the 2 minutes a request could go out
/// again, which wakes nothing twice).
#[derive(Debug, Default)]
pub struct WakeBook {
    seen: Vec<String>,
    report: Option<String>,
}

impl WakeBook {
    pub const fn new() -> Self {
        Self { seen: Vec::new(), report: None }
    }

    /// True the first time a nonce comes (then it is taken); false for one already handled.
    pub fn take(&mut self, nonce: &str) -> bool {
        if self.seen.iter().any(|n| n == nonce) {
            return false;
        }
        self.seen.push(nonce.to_owned());
        if self.seen.len() > 16 {
            self.seen.remove(0);
        }
        true
    }

    /// The packets of `nonce` went out (at least one was sent): report it from the next heartbeat on.
    pub fn sent(&mut self, nonce: &str) {
        self.report = Some(nonce.to_owned());
    }

    /// The heartbeat's `dolphin_wake`, while there is one to report.
    pub fn report(&self) -> Option<&str> {
        self.report.as_deref()
    }

    /// A heartbeat that carried `nonce` was answered by the portal: stop reporting it (a newer one stays).
    pub fn acknowledged(&mut self, nonce: &str) {
        if self.report.as_deref() == Some(nonce) {
            self.report = None;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(v: &[&str]) -> Vec<String> {
        v.iter().map(|x| x.to_string()).collect()
    }

    const NONCE: &str = "0b9f6a2e-4c1d-4e8a-9d3b-7f2a1c5e8d40";
    const LAN: [(Ipv4Addr, u8); 1] = [(Ipv4Addr::new(192, 168, 1, 24), 24)];

    #[test]
    fn the_magic_packet_for_a_known_mac() {
        let mac = parse_mac("00:1A:2B:3C:4D:5E").unwrap();
        let p = magic_packet(&mac);
        assert_eq!(p.len(), 102);
        assert_eq!(&p[..6], &[0xFF; 6]);
        for i in 0..16 {
            assert_eq!(&p[6 + i * 6..12 + i * 6], &[0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E]);
        }
        let hex: String = p[..18].iter().map(|b| format!("{:02x}", b)).collect();
        assert_eq!(hex, "ffffffffffff001a2b3c4d5e001a2b3c4d5e");
    }

    #[test]
    fn macs_are_colon_hex_and_never_zero_or_group() {
        assert_eq!(parse_mac("aa:bb:cc:dd:ee:f0"), Some([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xF0]));
        for bad in ["", "AA:BB:CC:DD:EE", "AA:BB:CC:DD:EE:FF:00", "AA-BB-CC-DD-EE-F0", "AA:BB:CC:DD:EE:G0",
            "A:BB:CC:DD:EE:F0", "00:00:00:00:00:00", "FF:FF:FF:FF:FF:FF", "01:00:5E:00:00:01", "+A:BB:CC:DD:EE:F0"] {
            assert_eq!(parse_mac(bad), None, "{}", bad);
        }
        assert_eq!(format_mac(&[0x0a, 0x1b, 0x2c, 0x3d, 0x4e, 0x5f]), "0A:1B:2C:3D:4E:5F");
    }

    #[test]
    fn nonces_are_short_plain_text() {
        assert!(valid_nonce(NONCE));
        assert!(!valid_nonce("short"));
        assert!(!valid_nonce(&"x".repeat(65)));
        assert!(valid_nonce(&"x".repeat(64)));
        assert!(!valid_nonce("has space in it"));
        assert!(!valid_nonce("quote\"inside1"));
        assert!(!valid_nonce("نانس‌فارسی‌است"));
    }

    #[test]
    fn broadcasts_are_only_this_pcs_own_subnets() {
        assert_eq!(directed_broadcast(Ipv4Addr::new(192, 168, 1, 24), 24), Some(Ipv4Addr::new(192, 168, 1, 255)));
        assert_eq!(directed_broadcast(Ipv4Addr::new(10, 1, 2, 3), 8), Some(Ipv4Addr::new(10, 255, 255, 255)));
        assert_eq!(directed_broadcast(Ipv4Addr::new(10, 1, 2, 3), 31), None);
        assert_eq!(parse_bcast("192.168.1.255", &LAN), Some(Ipv4Addr::new(192, 168, 1, 255)));
        assert_eq!(parse_bcast("255.255.255.255", &[]), Some(Ipv4Addr::BROADCAST));
        for bad in ["192.168.2.255", "192.168.1.24", "8.8.8.8", "fe80::1", "::ffff:192.168.1.255", "192.168.1", ""] {
            assert_eq!(parse_bcast(bad, &LAN), None, "{}", bad);
        }
    }

    #[test]
    fn a_good_request_becomes_a_job_with_the_limited_broadcast_last() {
        let j = job(NONCE, &s(&["AA:BB:CC:DD:EE:01", "aa:bb:cc:dd:ee:01"]), &s(&["192.168.1.255"]), 1_100, 1_000, &LAN).unwrap();
        assert_eq!(j.nonce, NONCE);
        assert_eq!(j.macs, vec![[0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x01]]);
        assert_eq!(j.targets, vec![Ipv4Addr::new(192, 168, 1, 255), Ipv4Addr::BROADCAST]);
        let j = job(NONCE, &s(&["AA:BB:CC:DD:EE:01"]), &[], 1_100, 1_000, &LAN).unwrap();
        assert_eq!(j.targets, vec![Ipv4Addr::BROADCAST]);
    }

    #[test]
    fn a_bad_part_refuses_the_whole_request() {
        let m = s(&["AA:BB:CC:DD:EE:01"]);
        let b = s(&["192.168.1.255"]);
        assert_eq!(job("bad", &m, &b, 1_100, 1_000, &LAN), Err(Reject::Nonce));
        assert_eq!(job(NONCE, &m, &b, 1_000, 1_000, &LAN), Err(Reject::Expired));
        assert_eq!(job(NONCE, &m, &b, 900, 1_000, &LAN), Err(Reject::Expired));
        assert_eq!(job(NONCE, &m, &b, 1_601, 1_000, &LAN), Err(Reject::TooFar));
        assert_eq!(job(NONCE, &[], &b, 1_100, 1_000, &LAN), Err(Reject::Macs));
        assert_eq!(job(NONCE, &s(&["AA:BB:CC:DD:EE:01", "nope"]), &b, 1_100, 1_000, &LAN), Err(Reject::Macs));
        let nine: Vec<String> = (0..9).map(|i| format!("AA:BB:CC:DD:EE:{:02X}", i + 1)).collect();
        assert_eq!(job(NONCE, &nine, &b, 1_100, 1_000, &LAN), Err(Reject::Macs));
        assert_eq!(job(NONCE, &m, &s(&["8.8.8.8"]), 1_100, 1_000, &LAN), Err(Reject::Bcast));
        let many = vec!["192.168.1.255".to_string(); 9];
        assert_eq!(job(NONCE, &m, &many, 1_100, 1_000, &LAN), Err(Reject::Bcast));
    }

    fn adapter(if_type: u32, description: &str, mac: &str, ipv4: &[(Ipv4Addr, u8)]) -> Adapter {
        Adapter { if_type, description: description.to_owned(), mac: parse_mac(mac), ipv4: ipv4.to_vec() }
    }

    #[test]
    fn sysinfo_lists_physical_adapters_wired_first() {
        let list = vec![
            adapter(71, "Intel(R) Wi-Fi 6 AX201 160MHz", "3C:A9:F4:11:22:33", &[(Ipv4Addr::new(192, 168, 1, 30), 24)]),
            adapter(6, "Hyper-V Virtual Ethernet Adapter", "00:15:5D:01:02:03", &[(Ipv4Addr::new(172, 20, 0, 1), 20)]),
            adapter(6, "TAP-Windows Adapter V9", "00:FF:AA:BB:CC:DD", &[(Ipv4Addr::new(10, 8, 0, 6), 24)]),
            adapter(53, "WireGuard Tunnel", "00:00:00:00:00:00", &[(Ipv4Addr::new(10, 66, 0, 2), 32)]),
            adapter(24, "Software Loopback Interface 1", "00:00:00:00:00:00", &[(Ipv4Addr::LOCALHOST, 8)]),
            adapter(6, "Bluetooth Device (Personal Area Network)", "3C:A9:F4:11:22:34", &[]),
            adapter(6, "Realtek PCIe GbE Family Controller", "D8:BB:C1:44:55:66",
                &[(Ipv4Addr::new(192, 168, 1, 24), 24), (Ipv4Addr::new(169, 254, 3, 4), 16)]),
            adapter(6, "Some NIC with a software address", "02:11:22:33:44:55", &[(Ipv4Addr::new(192, 168, 9, 9), 24)]),
            adapter(6, "VMware Network Adapter VMnet8", "00:50:56:C0:00:08", &[(Ipv4Addr::new(192, 168, 50, 1), 24)]),
        ];
        assert_eq!(report_macs(&list), vec!["D8:BB:C1:44:55:66", "3C:A9:F4:11:22:33"]);
        assert_eq!(report_lan(&list), vec!["192.168.1.24/24", "192.168.1.30/24"]);
        assert_eq!(local_subnets(&list).len(), 3);
    }

    #[test]
    fn at_most_eight_of_each() {
        let list: Vec<Adapter> = (0..10u8)
            .map(|i| {
                adapter(6, "Intel(R) Ethernet", &format!("D8:BB:C1:44:55:{:02X}", i),
                    &[(Ipv4Addr::new(192, 168, i, 2), 24), (Ipv4Addr::new(10, i, 0, 2), 16)])
            })
            .collect();
        assert_eq!(report_macs(&list).len(), 8);
        assert_eq!(report_lan(&list).len(), 8);
    }

    #[test]
    fn types_and_names_decide_what_is_physical() {
        assert_eq!(medium(6), Some(Medium::Wired));
        assert_eq!(medium(71), Some(Medium::Wireless));
        assert_eq!(medium(131), None);
        assert_eq!(medium(23), None);
        assert!(looks_virtual("Npcap Loopback Adapter"));
        assert!(looks_virtual("Microsoft Wi-Fi Direct Virtual Adapter #2"));
        assert!(!looks_virtual("Intel(R) Ethernet Connection (7) I219-V"));
        assert!(virtual_mac(&[0x08, 0x00, 0x27, 1, 2, 3]));
        assert!(!virtual_mac(&[0xD8, 0xBB, 0xC1, 1, 2, 3]));
    }

    #[test]
    fn once_per_nonce_and_reported_until_acknowledged() {
        let mut book = WakeBook::new();
        assert!(book.take("nonce-one-1"));
        assert!(!book.take("nonce-one-1"));
        assert_eq!(book.report(), None);
        book.sent("nonce-one-1");
        assert_eq!(book.report(), Some("nonce-one-1"));
        // a newer request lands before the answer to the heartbeat that carried the first
        assert!(book.take("nonce-two-2"));
        book.sent("nonce-two-2");
        book.acknowledged("nonce-one-1");
        assert_eq!(book.report(), Some("nonce-two-2"));
        book.acknowledged("nonce-two-2");
        assert_eq!(book.report(), None);
        assert!(!book.take("nonce-two-2"));
    }

    #[test]
    fn the_book_forgets_only_old_nonces() {
        let mut book = WakeBook::new();
        for i in 0..17 {
            assert!(book.take(&format!("nonce-{:04}", i)));
        }
        assert!(!book.take("nonce-0016"));
        assert!(book.take("nonce-0000")); // the oldest of 17 was dropped
    }
}
