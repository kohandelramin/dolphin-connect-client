//! Dolphin Connect, Plan 18 Phase 6 (DD-1, owner approved 2026-11-13): the network-change listener and the physical
//! adapter, the root fix for sessions that drop when a VPN goes on or off (OR-3). The rules, standard library only, so
//! CI tests them alone (`rustc --edition 2021 --test src/dolphin_net_core.rs`); the app side is src/dolphin_net.rs.
//!
//! 1. Listener: Windows tells the app about address and route changes (`NotifyUnicastIpAddressChange`,
//!    `NotifyRouteChange2`). A VPN toggle fires a burst, so the app reacts once the burst is quiet for [`QUIET_MS`], and
//!    at least every [`MAX_WAIT_MS`] while it lasts ([`Debounce`]), and only when the routes or addresses really changed
//!    ([`NetState`]). The reaction: upstream's own `RendezvousMediator::restart()` (registers again at once) and
//!    `test_nat_type()`, and a session whose link left from an address this PC no longer has ends at once
//!    ([`path_gone`]), so the technician app's quiet retry (ADR-0015) starts now instead of after the 30 s timeout.
//! 2. Physical adapter: the app's own sockets to our servers (rendezvous, relay, punch, NAT test) carry
//!    `IP_UNICAST_IF` / `IPV6_UNICAST_IF` for the interface of the default route that is a physical Ethernet, Wi-Fi or
//!    mobile-broadband adapter ([`choose`]), so a VPN going on or off does not move them. No qualifying adapter: nothing
//!    is set (normal routing). Never for a loopback, private or link-local target ([`pin_target`]).
//! 3. The portal's `direct-route` switch: hidden turns both parts off (upstream's behaviour). The technician app has
//!    no heartbeat, so it keeps the default (forced: on).
//!
//! No codec, quality or relay-timing change; consent is untouched (ADR-0015).

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

/// The portal's feature switch (app/src/lib/switches.ts, DD-4); default forced (src/dolphin_system_core.rs).
pub const SWITCH_DIRECT_ROUTE: &str = "direct-route";

/// A burst of change events ends when none came for this long...
pub const QUIET_MS: u64 = 1_000;
/// ...but while events keep coming the app reacts at least this often.
pub const MAX_WAIT_MS: u64 = 2_000;
/// How often the listener's thread looks at the event counter.
pub const POLL_MS: u64 = 250;
/// A pinned connect that failed where the normal route worked (a VPN's kill switch, a firewall): no pinning for this
/// long, or until the next network change.
pub const PIN_HOLD_SECS: u64 = 600;
/// Without a working listener, the adapter choice is read again when it is older than this.
pub const STALE_SECS: u64 = 5;

/// The adapter kinds that reach the internet themselves.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Kind {
    Wired,
    Wireless,
    Mobile,
}

/// Windows' interface type (IANA ifType, `IP_ADAPTER_ADDRESSES.IfType`): the Ethernet kinds, 802.11, and mobile
/// broadband (USB 4G modems). Tunnels (131), PPP (23: VPN dial-ups, and PPPoE, which this leaves to normal routing),
/// loopback (24) and `propVirtual` (53: WireGuard, Wintun, TUN-mode VPN apps) are not.
pub fn kind(if_type: u32) -> Option<Kind> {
    match if_type {
        6 | 26 | 62 | 69 | 117 => Some(Kind::Wired),
        71 => Some(Kind::Wireless),
        243 | 244 => Some(Kind::Mobile),
        _ => None,
    }
}

/// Virtual adapters that report an Ethernet type (VPN TAP drivers, Hyper-V, VMware, VirtualBox, Bluetooth PAN, ...),
/// by their description or name. The list of src/dolphin_wake_core.rs plus the VPN apps common in Iran.
pub fn looks_virtual(name: &str) -> bool {
    const WORDS: &[&str] = &[
        "virtual", "vpn", "tap-", "tap ", "tunnel", "hyper-v", "vmware", "virtualbox", "vbox", "loopback",
        "bluetooth", "wan miniport", "npcap", "wireguard", "wintun", "zerotier", "tailscale", "openvpn", "fortinet",
        "anyconnect", "pangp", "teredo", "isatap", "6to4", "kernel debug", "hamachi", "docker", "wsl", "pseudo",
        "wi-fi direct", "sstp", "l2tp", "pptp", "ikev2", "parallels", "qemu", "kvm", "vethernet", "sing-tun",
        "sing-box", "clash", "v2ray", "xray", "hiddify", "nekoray", "outline", "softether", "radmin", "warp",
        "cloudflare", "proton", "nordlynx", "expressvpn", "mullvad", "psiphon", "tun2socks", "meta tunnel",
    ];
    let d = name.to_lowercase();
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

/// One adapter as Windows lists it (`GetIfTable2`, `GetUnicastIpAddressTable`). `name` is its description and alias
/// together; `hardware` is Windows' own `HardwareInterface` flag, which TAP, Wintun, WireGuard and Hyper-V adapters do
/// not have.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Nic {
    pub index: u32,
    pub if_type: u32,
    pub name: String,
    pub mac: Option<[u8; 6]>,
    pub hardware: bool,
    pub addrs: Vec<IpAddr>,
}

/// A physical adapter by Windows' hardware flag, its type, name and MAC prefix: each one alone may be wrong for some
/// driver, so all must agree. Unlike Wake-on-LAN, a software-set (random) Wi-Fi MAC is fine: the adapter still reaches
/// the internet.
pub fn physical(n: &Nic) -> Option<Kind> {
    let k = kind(n.if_type)?;
    if !n.hardware || looks_virtual(&n.name) || n.mac.map_or(false, |m| virtual_mac(&m)) {
        return None;
    }
    Some(k)
}

/// An address an adapter can reach the internet from: not loopback, unspecified or link-local (169.254/16, fe80::/10).
pub fn usable(ip: &IpAddr) -> bool {
    match ip {
        IpAddr::V4(a) => !a.is_loopback() && !a.is_unspecified() && !a.is_link_local() && !a.is_broadcast(),
        IpAddr::V6(a) => !a.is_loopback() && !a.is_unspecified() && !v6_link_local(a) && !a.is_multicast(),
    }
}

fn v6_link_local(a: &Ipv6Addr) -> bool {
    a.segments()[0] & 0xffc0 == 0xfe80
}

/// One default route (destination prefix length 0). `metric` is the route's metric plus its interface's, as Windows
/// ranks them; `connected` is the interface's media state.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct Route {
    pub index: u32,
    pub v6: bool,
    pub metric: u32,
    pub connected: bool,
}

/// The interface the app's sockets of one address family are pinned to, and that interface's addresses of the family.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Pin {
    pub index: u32,
    pub kind: Kind,
    pub addrs: Vec<IpAddr>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Choices {
    pub v4: Option<Pin>,
    pub v6: Option<Pin>,
}

/// Per family: among the connected default routes whose interface is a physical adapter with a usable address of that
/// family, the lowest metric; on a tie wired before Wi-Fi before mobile, then the lower index. A VPN's own default
/// route (or its 0.0.0.0/1 + 128.0.0.0/1 pair, which is not a default route) never qualifies; the physical one it
/// outranks stays in the table and is the one chosen.
pub fn choose(nics: &[Nic], routes: &[Route]) -> Choices {
    let pick = |v6: bool| -> Option<Pin> {
        let mut best: Option<(u32, Kind, u32, Vec<IpAddr>)> = None;
        for r in routes.iter().filter(|r| r.v6 == v6 && r.connected) {
            let Some(nic) = nics.iter().find(|n| n.index == r.index) else { continue };
            let Some(k) = physical(nic) else { continue };
            let addrs: Vec<IpAddr> = nic.addrs.iter().filter(|a| a.is_ipv6() == v6 && usable(a)).copied().collect();
            if addrs.is_empty() {
                continue;
            }
            let better = match &best {
                None => true,
                Some((m, bk, bi, _)) => (r.metric, k, r.index) < (*m, *bk, *bi),
            };
            if better {
                best = Some((r.metric, k, r.index, addrs));
            }
        }
        best.map(|(_, kind, index, addrs)| Pin { index, kind, addrs })
    };
    Choices { v4: pick(false), v6: pick(true) }
}

/// A target worth pinning: a public internet address. Loopback, private (10/8, 172.16/12, 192.168/16, fc00::/7),
/// shared (100.64/10, also Tailscale's), link-local, multicast and unspecified targets keep normal routing: a LAN
/// peer is reached on its own link, and a VPN-only address only through the VPN.
pub fn pin_target(ip: &IpAddr) -> bool {
    match ip {
        IpAddr::V4(a) => {
            let o = a.octets();
            !(a.is_loopback()
                || a.is_private()
                || a.is_link_local()
                || a.is_unspecified()
                || a.is_multicast()
                || a.is_broadcast()
                || (o[0] == 100 && o[1] & 0xc0 == 64)
                || o[0] == 0)
        }
        IpAddr::V6(a) => {
            if let Some(v4) = a.to_ipv4_mapped() {
                return pin_target(&IpAddr::V4(v4));
            }
            let s0 = a.segments()[0];
            !(a.is_loopback() || a.is_unspecified() || a.is_multicast() || v6_link_local(a) || s0 & 0xfe00 == 0xfc00)
        }
    }
}

/// The interface index to pin a socket to, or `None` for normal routing. `local` is the address the socket is bound to:
/// unspecified (or none) takes the pin; a specific one (a punch reusing the address of its link to the server) takes it
/// only when it belongs to the chosen adapter, so a socket never leaves from one adapter with another's address.
pub fn pin_index(c: &Choices, target: &IpAddr, local: Option<&IpAddr>) -> Option<u32> {
    if !pin_target(target) {
        return None;
    }
    let pin = if target.is_ipv6() && target_v4_mapped(target).is_none() { c.v6.as_ref() } else { c.v4.as_ref() }?;
    match local {
        None => Some(pin.index),
        Some(l) if l.is_unspecified() => Some(pin.index),
        Some(l) => pin.addrs.contains(&canonical(l)).then_some(pin.index),
    }
}

fn target_v4_mapped(ip: &IpAddr) -> Option<Ipv4Addr> {
    match ip {
        IpAddr::V6(a) => a.to_ipv4_mapped(),
        _ => None,
    }
}

fn canonical(ip: &IpAddr) -> IpAddr {
    target_v4_mapped(ip).map(IpAddr::V4).unwrap_or(*ip)
}

/// The option value for `setsockopt`: `IP_UNICAST_IF` takes the index in network byte order, `IPV6_UNICAST_IF` in host
/// byte order (Microsoft's documentation of both options).
pub fn unicast_if_value(index: u32, v6: bool) -> [u8; 4] {
    if v6 {
        index.to_ne_bytes()
    } else {
        index.to_be_bytes()
    }
}

/// A live link left from `local`; true when this PC no longer has that address (the VPN that carried it went off, the
/// Wi-Fi changed): nothing will ever arrive on it again. A wildcard or loopback address (UDP-based links, tests) is
/// never gone.
pub fn path_gone(local: &IpAddr, addrs: &[IpAddr]) -> bool {
    let local = canonical(local);
    if local.is_unspecified() || local.is_loopback() {
        return false;
    }
    !addrs.iter().any(|a| canonical(a) == local)
}

/// What a change is measured against: the default routes and every unicast address of this PC (every interface, VPNs
/// included, so [`path_gone`] knows a link over a VPN that is still up), sorted.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct NetState {
    pub routes: Vec<Route>,
    pub addrs: Vec<IpAddr>,
}

pub fn net_state(routes: &[Route], addrs: &[IpAddr]) -> NetState {
    let mut r: Vec<Route> = routes.to_vec();
    r.sort();
    r.dedup();
    let mut a: Vec<IpAddr> = addrs.to_vec();
    a.sort();
    a.dedup();
    NetState { routes: r, addrs: a }
}

/// Bursts of change events into one reaction: `observe` gets the running event count and the time, and says when to
/// react.
#[derive(Debug, Default)]
pub struct Debounce {
    seen: u64,
    first: Option<u64>,
    last: Option<u64>,
}

impl Debounce {
    pub const fn new() -> Self {
        Self { seen: 0, first: None, last: None }
    }

    pub fn observe(&mut self, count: u64, now_ms: u64) -> bool {
        if count != self.seen {
            self.seen = count;
            self.first.get_or_insert(now_ms);
            self.last = Some(now_ms);
        }
        match (self.first, self.last) {
            (Some(f), Some(l))
                if now_ms.saturating_sub(l) >= QUIET_MS || now_ms.saturating_sub(f) >= MAX_WAIT_MS =>
            {
                self.first = None;
                self.last = None;
                true
            }
            _ => false,
        }
    }
}

/// Pinning stops for [`PIN_HOLD_SECS`] after a pinned connect failed where the normal route worked; a network change
/// clears it.
#[derive(Debug, Default)]
pub struct PinHold {
    failed_at: Option<u64>,
}

impl PinHold {
    pub const fn new() -> Self {
        Self { failed_at: None }
    }
    pub fn allowed(&self, now_secs: u64) -> bool {
        self.failed_at.map_or(true, |t| now_secs.saturating_sub(t) >= PIN_HOLD_SECS)
    }
    pub fn fail(&mut self, now_secs: u64) {
        self.failed_at = Some(now_secs);
    }
    pub fn clear(&mut self) {
        self.failed_at = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v4(s: &str) -> IpAddr {
        IpAddr::V4(s.parse().unwrap())
    }
    fn v6(s: &str) -> IpAddr {
        IpAddr::V6(s.parse().unwrap())
    }
    fn nic(index: u32, if_type: u32, name: &str, addrs: &[IpAddr]) -> Nic {
        let hardware = if_type != 53;
        Nic { index, if_type, name: name.into(), mac: Some([0x3c, 0x52, 0x82, 1, 2, 3]), hardware, addrs: addrs.to_vec() }
    }
    fn route(index: u32, metric: u32) -> Route {
        Route { index, v6: false, metric, connected: true }
    }

    fn ethernet() -> Nic {
        nic(11, 6, "Intel(R) Ethernet Connection I219-V Ethernet", &[v4("192.168.1.24"), v6("fe80::1")])
    }
    fn wifi() -> Nic {
        nic(14, 71, "Intel(R) Wi-Fi 6 AX201 160MHz Wi-Fi", &[v4("192.168.43.10"), v6("2a01:5ec0::10")])
    }
    fn wireguard() -> Nic {
        nic(30, 53, "WireGuard Tunnel wg0", &[v4("10.66.0.2")])
    }
    fn tap() -> Nic {
        nic(31, 6, "TAP-Windows Adapter V9 Local Area Connection", &[v4("10.8.0.6")])
    }

    #[test]
    fn the_physical_default_route_wins_over_a_vpns_lower_metric() {
        // WireGuard (type 53) and an OpenVPN TAP adapter (type 6) both outrank the Ethernet; the Ethernet is chosen.
        let nics = [ethernet(), wireguard(), tap()];
        let routes = [route(11, 35), route(30, 5), route(31, 1)];
        let c = choose(&nics, &routes);
        assert_eq!(c.v4, Some(Pin { index: 11, kind: Kind::Wired, addrs: vec![v4("192.168.1.24")] }));
        assert_eq!(c.v6, None, "the Ethernet has only a link-local IPv6 address and no IPv6 default route");
    }

    #[test]
    fn the_lowest_metric_among_physical_adapters_and_wired_on_a_tie() {
        let nics = [ethernet(), wifi()];
        assert_eq!(choose(&nics, &[route(11, 50), route(14, 30)]).v4.unwrap().index, 14);
        assert_eq!(choose(&nics, &[route(11, 30), route(14, 30)]).v4.unwrap().index, 11);
        assert_eq!(choose(&nics, &[route(14, 30), route(11, 30)]).v4.unwrap().index, 11, "order of the table");
    }

    #[test]
    fn no_physical_default_route_means_no_pin() {
        // A VPN that removed the physical default route, a PPPoE dial-up, a Hyper-V external switch: normal routing.
        let pppoe = nic(40, 23, "WAN Miniport (PPPOE) Broadband Connection", &[v4("5.120.33.4")]);
        let vswitch = nic(41, 6, "Hyper-V Virtual Ethernet Adapter vEthernet (External)", &[v4("192.168.1.30")]);
        let nics = [ethernet(), wireguard(), pppoe, vswitch];
        assert_eq!(choose(&nics, &[route(30, 5), route(40, 10), route(41, 15)]), Choices::default());
        assert_eq!(choose(&nics, &[]), Choices::default());
    }

    #[test]
    fn a_disconnected_or_addressless_adapter_is_skipped() {
        let mut down = route(11, 1);
        down.connected = false;
        let apipa = nic(12, 6, "Realtek PCIe GbE Family Controller Ethernet 2", &[v4("169.254.10.3")]);
        let nics = [ethernet(), wifi(), apipa];
        assert_eq!(choose(&nics, &[down, route(12, 2), route(14, 40)]).v4.unwrap().index, 14);
        assert_eq!(choose(&nics, &[route(99, 1)]), Choices::default(), "a route of an unknown interface");
    }

    #[test]
    fn ipv6_is_chosen_on_its_own() {
        let nics = [ethernet(), wifi()];
        let routes = [route(11, 10), Route { index: 14, v6: true, metric: 40, connected: true }];
        let c = choose(&nics, &routes);
        assert_eq!(c.v4.unwrap().index, 11);
        assert_eq!(c.v6, Some(Pin { index: 14, kind: Kind::Wireless, addrs: vec![v6("2a01:5ec0::10")] }));
    }

    #[test]
    fn mobile_broadband_qualifies_and_vm_or_vpn_adapters_do_not() {
        let lte = nic(50, 243, "Generic Mobile Broadband Adapter Cellular", &[v4("10.140.2.9")]);
        assert_eq!(physical(&lte), Some(Kind::Mobile));
        let mut vm = ethernet();
        vm.name = "Intel(R) PRO/1000 MT Network Connection Ethernet0".into();
        vm.mac = Some([0x00, 0x0C, 0x29, 1, 2, 3]);
        assert_eq!(physical(&vm), None);
        let mut software = ethernet();
        software.hardware = false;
        assert_eq!(physical(&software), None, "a driver with an innocent name but no hardware behind it");
        for name in ["TAP-Windows Adapter V9", "Hiddify Tunnel", "sing-tun", "Clash Meta", "Cloudflare WARP Interface",
                     "Cisco AnyConnect Secure Mobility Client Virtual Miniport Adapter", "OpenVPN Data Channel Offload",
                     "vEthernet (Default Switch)"] {
            assert_eq!(physical(&nic(1, 6, name, &[])), None, "{name}");
        }
        let mut random_mac = wifi();
        random_mac.mac = Some([0x02 | 0x40, 0x11, 0x22, 0x33, 0x44, 0x55]);
        assert_eq!(physical(&random_mac), Some(Kind::Wireless), "Windows' random Wi-Fi address is still the Wi-Fi");
        assert_eq!(physical(&nic(1, 24, "Software Loopback Interface 1", &[])), None);
        assert_eq!(physical(&nic(1, 131, "Microsoft Teredo Tunneling Adapter", &[])), None);
    }

    #[test]
    fn only_public_targets_are_pinned() {
        for t in ["185.143.233.120", "2.144.0.1", "2a01:5ec0::1", "::ffff:185.143.233.120"] {
            let ip: IpAddr = t.parse().unwrap();
            assert!(pin_target(&ip), "{t}");
        }
        for t in ["127.0.0.1", "10.0.0.5", "172.16.3.4", "192.168.1.1", "100.64.0.1", "100.127.255.1", "169.254.1.1",
                  "0.0.0.0", "224.0.0.1", "255.255.255.255", "::1", "::", "fe80::1", "fd00::5", "ff02::1",
                  "::ffff:192.168.1.1"] {
            let ip: IpAddr = t.parse().unwrap();
            assert!(!pin_target(&ip), "{t}");
        }
    }

    #[test]
    fn a_socket_is_pinned_for_its_family_and_only_with_a_matching_local_address() {
        let c = choose(&[ethernet(), wifi()], &[route(11, 10), Route { index: 14, v6: true, metric: 40, connected: true }]);
        let server = v4("185.143.233.120");
        assert_eq!(pin_index(&c, &server, None), Some(11));
        assert_eq!(pin_index(&c, &server, Some(&v4("0.0.0.0"))), Some(11));
        assert_eq!(pin_index(&c, &server, Some(&v4("192.168.1.24"))), Some(11), "a punch from the pinned link's address");
        assert_eq!(pin_index(&c, &server, Some(&v4("10.8.0.6"))), None, "a punch from the VPN's address stays as it is");
        assert_eq!(pin_index(&c, &v6("2a01:5ec0::1"), None), Some(14));
        assert_eq!(pin_index(&c, &v6("::ffff:185.143.233.120"), None), Some(11));
        assert_eq!(pin_index(&c, &v4("192.168.1.1"), None), None);
        assert_eq!(pin_index(&Choices::default(), &server, None), None);
    }

    #[test]
    fn the_option_value_byte_order() {
        assert_eq!(unicast_if_value(11, false), [0, 0, 0, 11]);
        assert_eq!(unicast_if_value(0x0102, false), [0, 0, 1, 2]);
        assert_eq!(unicast_if_value(11, true), 11u32.to_ne_bytes());
        assert_eq!(u32::from_ne_bytes(unicast_if_value(0x0102, true)), 0x0102);
    }

    #[test]
    fn a_link_is_gone_only_when_its_address_is() {
        let now = [v4("192.168.1.24"), v6("2a01:5ec0::10")];
        assert!(path_gone(&v4("10.8.0.6"), &now), "the VPN went off");
        assert!(!path_gone(&v4("192.168.1.24"), &now), "pinned to the Ethernet: the VPN toggle does not touch it");
        assert!(!path_gone(&v6("::ffff:192.168.1.24"), &now));
        assert!(!path_gone(&v4("0.0.0.0"), &now), "a UDP link bound to every address");
        assert!(!path_gone(&v4("127.0.0.1"), &now));
        assert!(path_gone(&v4("192.168.1.24"), &[]), "every adapter gone");
    }

    #[test]
    fn the_state_ignores_order_and_repeats() {
        let addrs = |nics: &[Nic]| -> Vec<IpAddr> { nics.iter().flat_map(|n| n.addrs.clone()).collect() };
        let a = net_state(&[route(11, 10), route(14, 40)], &addrs(&[ethernet(), wifi()]));
        let b = net_state(&[route(14, 40), route(11, 10), route(11, 10)], &addrs(&[wifi(), ethernet(), wifi()]));
        assert_eq!(a, b);
        let c = net_state(&[route(11, 10), route(14, 40), route(30, 5)], &addrs(&[ethernet(), wifi(), wireguard()]));
        assert_ne!(a, c, "a VPN came up");
        let d = net_state(&[route(11, 10), route(14, 45)], &addrs(&[ethernet(), wifi()]));
        assert_ne!(a, d, "a metric changed");
        let e = net_state(&[route(11, 10), route(14, 40)], &addrs(&[ethernet()]));
        assert_ne!(a, e, "the Wi-Fi's addresses went");
    }

    #[test]
    fn a_burst_gives_one_reaction_after_a_quiet_second() {
        let mut d = Debounce::new();
        assert!(!d.observe(0, 0), "no event yet");
        assert!(!d.observe(1, 100));
        assert!(!d.observe(2, 400));
        assert!(!d.observe(5, 900));
        assert!(!d.observe(5, 1_800));
        assert!(d.observe(5, 1_900), "quiet for a second");
        assert!(!d.observe(5, 2_500), "only once");
        assert!(!d.observe(5, 10_000));
    }

    #[test]
    fn a_long_burst_still_reacts_every_two_seconds() {
        let mut d = Debounce::new();
        let mut reactions = Vec::new();
        for i in 0..24u64 {
            let now = i * POLL_MS;
            if d.observe(i + 1, now) {
                reactions.push(now);
            }
        }
        assert_eq!(reactions, vec![2_000, 4_250]);
    }

    #[test]
    fn a_failed_pin_holds_for_ten_minutes_or_until_cleared() {
        let mut h = PinHold::new();
        assert!(h.allowed(100));
        h.fail(100);
        assert!(!h.allowed(100));
        assert!(!h.allowed(100 + PIN_HOLD_SECS - 1));
        assert!(h.allowed(100 + PIN_HOLD_SECS));
        h.fail(2_000);
        h.clear();
        assert!(h.allowed(2_001));
    }
}
