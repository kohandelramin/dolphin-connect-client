//! Dolphin Connect, Plan 18 Phase 6 (DD-1): the app side of `src/dolphin_net_core.rs`, which holds the rules and their
//! tests. Here: Windows' tables and change notifications (iphlpapi), `IP_UNICAST_IF` on the app's own sockets, and the
//! reaction to a change. `libs/hbb_common` stays upstream's: its sockets are taken from its public API and pinned
//! through their raw handles, or, for TCP (where the option must come before `connect`), built here the way
//! `FramedStream::new` builds them and handed back as its `Stream`.
//!
//! Hooks in upstream files (each marked `Dolphin Connect (DD-1)`, each guarded in dolphin/test_workflows.py):
//! - src/rendezvous_mediator.rs: `start_all` calls [`mediator_started`]; its socket imports and the rebind, TCP punch
//!   and UDP punch calls come from here (rendezvous, punch, relay request, intranet, WebRTC signalling).
//! - src/server.rs: the customer's relay connection.
//! - src/common.rs: the NAT test and the HTTP-over-rendezvous fallback.
//! - src/client.rs: the technician's rendezvous, relay, punch and UDP NAT test, via its socket imports.
//! - src/client/io_loop.rs: a session whose link left from an address this PC no longer has ends at once
//!   ([`session_path_gone`]), so the quiet retry of flutter/lib/dolphin/reconnect.dart (ADR-0015) starts now.
//!
//! The portal's `direct-route` switch hidden: nothing here acts (no pin, no reaction); each wrapper is then upstream's
//! own call. The technician app runs no heartbeat, so it keeps the default (forced: on).

use crate::dolphin_net_core as net;
use hbb_common::{
    config::{self, Config},
    log,
    socket_client::{self, IsResolvedSocketAddr},
    tokio::{
        self,
        net::{TcpSocket, ToSocketAddrs, UdpSocket},
    },
    udp::FramedSocket,
    IntoTargetAddr, ResultType, Stream, TargetAddr,
};
use std::{
    net::SocketAddr,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Mutex, Once, OnceLock, RwLock,
    },
    time::{Duration, Instant},
};

/// Bumped by Windows' callbacks; the listener's thread debounces it.
static EVENTS: AtomicU64 = AtomicU64::new(0);
/// Bumped by each reaction to a real change; sessions compare it before they look at their own address.
static GENERATION: AtomicU64 = AtomicU64::new(0);
/// This process runs the rendezvous mediator (the customer's server process, a portable customer app).
static MEDIATOR: AtomicBool = AtomicBool::new(false);
/// Windows' notifications are on, so the snapshot is kept current by them.
static WATCHING: AtomicBool = AtomicBool::new(false);
/// The rendezvous UDP socket in use is pinned (see [`rebind_udp_for`]).
static UDP_PINNED: AtomicBool = AtomicBool::new(false);
static WATCH: Once = Once::new();
static HOLD: Mutex<net::PinHold> = Mutex::new(net::PinHold::new());
static SNAP: RwLock<Option<Snapshot>> = RwLock::new(None);
static START: OnceLock<Instant> = OnceLock::new();

#[derive(Clone)]
struct Snapshot {
    at: Instant,
    choices: net::Choices,
    state: net::NetState,
}

fn mono() -> Duration {
    START.get_or_init(Instant::now).elapsed()
}

/// The portal's `direct-route` switch for this PC (default forced; the technician app always has the default).
fn on() -> bool {
    use crate::dolphin_system_core as sys;
    sys::switch_mode(&Config::get_option(sys::SWITCHES_OPTION), net::SWITCH_DIRECT_ROUTE) != sys::SwitchMode::Hidden
}

fn read() -> Option<Snapshot> {
    let (nics, routes, addrs) = sys::read()?;
    Some(Snapshot {
        at: Instant::now(),
        choices: net::choose(&nics, &routes),
        state: net::net_state(&routes, &addrs),
    })
}

/// The current adapter choice: kept by the listener, or read again when it is older than [`net::STALE_SECS`] without
/// one.
fn snapshot() -> Option<Snapshot> {
    start_watch();
    if let Some(s) = SNAP.read().unwrap().as_ref() {
        if WATCHING.load(Ordering::SeqCst) || s.at.elapsed().as_secs() < net::STALE_SECS {
            return Some(s.clone());
        }
    }
    let s = read()?;
    *SNAP.write().unwrap() = Some(s.clone());
    Some(s)
}

/// Whether sockets may be pinned right now, and the choice to pin them by.
fn pinning() -> Option<net::Choices> {
    if !on() || Config::get_socks().is_some() || config::use_ws() {
        return None;
    }
    if !HOLD.lock().unwrap().allowed(mono().as_secs()) {
        return None;
    }
    let c = snapshot()?.choices;
    (c.v4.is_some() || c.v6.is_some()).then_some(c)
}

/// Called from `RendezvousMediator::start_all` once it is past upstream's outgoing-only stop: this process registers
/// with the rendezvous server, so a network change restarts that registration.
pub fn mediator_started() {
    MEDIATOR.store(true, Ordering::SeqCst);
    start_watch();
}

/// Starts the listener once per process (the first socket or session starts it too).
pub fn start_watch() {
    WATCH.call_once(|| {
        if let Err(err) = std::thread::Builder::new().name("dolphin-net".into()).spawn(watch) {
            log::warn!("DD-1: the network listener did not start: {err}");
        }
    });
}

fn watch() {
    if !sys::subscribe() {
        return;
    }
    if let Some(s) = read() {
        *SNAP.write().unwrap() = Some(s);
    }
    WATCHING.store(true, Ordering::SeqCst);
    let mut debounce = net::Debounce::new();
    loop {
        std::thread::sleep(Duration::from_millis(net::POLL_MS));
        if debounce.observe(EVENTS.load(Ordering::SeqCst), mono().as_millis() as u64) {
            react();
        }
    }
}

/// One debounced burst: when the routes or addresses really changed, keep the new choice, lift a held pin, tell the
/// sessions, and (switch on, mediator here) register again at once through upstream's own restart, and test the NAT
/// again as upstream does at start.
fn react() {
    let Some(new) = read() else {
        return;
    };
    let changed = {
        let mut snap = SNAP.write().unwrap();
        let changed = snap.as_ref().map_or(true, |old| old.state != new.state);
        *snap = Some(new.clone());
        changed
    };
    if !changed {
        return;
    }
    HOLD.lock().unwrap().clear();
    GENERATION.fetch_add(1, Ordering::SeqCst);
    let enabled = on();
    log::info!(
        "DD-1: network changed; physical adapter v4 {:?}, v6 {:?}; direct-route {}",
        new.choices.v4.as_ref().map(|p| p.index),
        new.choices.v6.as_ref().map(|p| p.index),
        if enabled { "on" } else { "off" }
    );
    if enabled && MEDIATOR.load(Ordering::SeqCst) {
        crate::RendezvousMediator::restart();
        crate::test_nat_type();
    }
}

/// The current reaction count, taken by a session as it starts.
pub fn generation() -> u64 {
    start_watch();
    GENERATION.load(Ordering::SeqCst)
}

/// Checked every second by a session (src/client/io_loop.rs): after a network change, true when the address its link
/// left from is no longer this PC's. Never while the switch is hidden.
pub fn session_path_gone(local: SocketAddr, seen: &mut u64) -> bool {
    let now = GENERATION.load(Ordering::SeqCst);
    if now == *seen {
        return false;
    }
    *seen = now;
    if !on() {
        return false;
    }
    let Some(state) = SNAP.read().unwrap().as_ref().map(|s| s.state.clone()) else {
        return false;
    };
    let gone = net::path_gone(&local.ip(), &state.addrs);
    if gone {
        log::info!("DD-1: the session's address is gone after a network change; reconnecting at once");
    }
    gone
}

/// `socket_client::connect_tcp` with the pin. WebSocket, WebRTC and proxied targets go to upstream's call unchanged.
pub async fn connect_tcp<'t, T>(target: T, ms_timeout: u64) -> ResultType<Stream>
where
    T: IntoTargetAddr<'t> + ToSocketAddrs + IsResolvedSocketAddr + std::fmt::Display,
{
    if target.to_string().contains("://") || config::use_ws() {
        return socket_client::connect_tcp(target, ms_timeout).await;
    }
    connect_tcp_local(target, None, ms_timeout).await
}

/// `socket_client::connect_tcp_local` with the pin.
///
/// From any address (`local` none or unspecified): a pinned connect that fails is tried once more upstream's way; when
/// that one works (a VPN's kill switch, a firewall), pinning holds off for [`net::PIN_HOLD_SECS`] or until the next
/// network change.
///
/// From a given address (a punch, the NAT test's second leg): pinned only when the address is the chosen adapter's
/// (then Windows would send it there anyway), and the pinned attempt stands in for upstream's one for one, so a punch
/// keeps its timing: a failure is returned as upstream's would be, and never sets the hold.
pub async fn connect_tcp_local<'t, T>(target: T, local: Option<SocketAddr>, ms_timeout: u64) -> ResultType<Stream>
where
    T: IntoTargetAddr<'t> + ToSocketAddrs + IsResolvedSocketAddr + std::fmt::Display,
{
    let given = local.map_or(false, |l| !l.ip().is_unspecified());
    let mut tried = false;
    if let Some(choices) = pinning() {
        if let Ok(addrs) = tokio::net::lookup_host(&target).await {
            for remote in addrs {
                if local.map_or(false, |l| l.is_ipv6() != remote.is_ipv6()) {
                    continue;
                }
                let local_ip = local.map(|l| l.ip());
                let Some(index) = net::pin_index(&choices, &remote.ip(), local_ip.as_ref()) else {
                    continue;
                };
                match connect_pinned(remote, local, index, ms_timeout).await {
                    None => continue,
                    Some(Ok(stream)) => return Ok(stream),
                    Some(Err(err)) if given => return Err(err),
                    Some(Err(err)) => {
                        tried = true;
                        log::debug!("DD-1: pinned connect to {remote} failed: {err}");
                    }
                }
            }
        }
    }
    let res = socket_client::connect_tcp_local(target, local, ms_timeout).await;
    if tried && res.is_ok() {
        HOLD.lock().unwrap().fail(mono().as_secs());
        log::warn!("DD-1: the physical adapter refused a connection the normal route took; not pinning for a while");
    }
    res
}

/// Upstream's `FramedStream::new` for one address (reused address, no delay), with `IP_UNICAST_IF` set before
/// `connect`. `None` when the option did not take (nothing was sent).
async fn connect_pinned(remote: SocketAddr, local: Option<SocketAddr>, index: u32, ms: u64) -> Option<ResultType<Stream>> {
    let socket = if remote.is_ipv4() { TcpSocket::new_v4() } else { TcpSocket::new_v6() }.ok()?;
    socket.set_reuseaddr(true).ok();
    if !sys::pin_tcp(&socket, index, remote.is_ipv6()) {
        return None;
    }
    Some(
        async move {
            socket.bind(local.unwrap_or_else(|| Config::get_any_listen_addr(remote.is_ipv4())))?;
            let stream = hbb_common::timeout(ms, socket.connect(remote)).await??;
            stream.set_nodelay(true).ok();
            let addr = stream.local_addr()?;
            Ok(Stream::from(stream, addr))
        }
        .await,
    )
}

/// Pins a UDP socket bound to every address for its server. True when the option took.
fn pin_udp(socket: &UdpSocket, target: &SocketAddr) -> bool {
    let Some(choices) = pinning() else {
        return false;
    };
    let Ok(local) = socket.local_addr() else {
        return false;
    };
    match net::pin_index(&choices, &target.ip(), Some(&local.ip())) {
        Some(index) => sys::pin_udp(socket, index, local.is_ipv6()),
        None => false,
    }
}

/// `socket_client::new_udp_for` (the rendezvous registration), pinned.
pub async fn new_udp_for(target: &str, ms_timeout: u64) -> ResultType<(FramedSocket, TargetAddr<'static>)> {
    let (socket, addr) = socket_client::new_udp_for(target, ms_timeout).await?;
    let pinned = match (&socket, &addr) {
        (FramedSocket::Direct(f), TargetAddr::Ip(ip)) => pin_udp(f.get_ref(), ip),
        _ => false,
    };
    UDP_PINNED.store(pinned, Ordering::SeqCst);
    Ok((socket, addr))
}

/// `socket_client::rebind_udp_for`: upstream rebinds after four unanswered registrations. When the socket that went
/// unanswered was pinned, the pin may be what is blocked, so pinning holds off (the next network change lifts it).
pub async fn rebind_udp_for(target: &str) -> ResultType<Option<(FramedSocket, TargetAddr<'static>)>> {
    if UDP_PINNED.swap(false, Ordering::SeqCst) {
        HOLD.lock().unwrap().fail(mono().as_secs());
        log::warn!("DD-1: registrations over the physical adapter went unanswered; not pinning for a while");
    }
    let res = socket_client::rebind_udp_for(target).await?;
    Ok(res.map(|(socket, addr)| {
        let pinned = match (&socket, &addr) {
            (FramedSocket::Direct(f), TargetAddr::Ip(ip)) => pin_udp(f.get_ref(), ip),
            _ => false,
        };
        UDP_PINNED.store(pinned, Ordering::SeqCst);
        (socket, addr)
    }))
}

/// `socket_client::new_direct_udp_for` (the customer's UDP punch), pinned.
pub async fn new_direct_udp_for(target: &str) -> ResultType<(Arc<UdpSocket>, SocketAddr)> {
    let (socket, addr) = socket_client::new_direct_udp_for(target).await?;
    pin_udp(&socket, &addr);
    Ok((socket, addr))
}

/// `socket_client::new_direct_udp_for_unverified` (the technician's UDP NAT test and punch socket), pinned.
pub async fn new_direct_udp_for_unverified(target: &str) -> ResultType<(Arc<UdpSocket>, SocketAddr)> {
    let (socket, addr) = socket_client::new_direct_udp_for_unverified(target).await?;
    pin_udp(&socket, &addr);
    Ok((socket, addr))
}

#[cfg(windows)]
mod sys {
    use super::net::{self, Nic, Route};
    use hbb_common::log;
    use std::{
        collections::HashMap,
        ffi::c_void,
        net::{IpAddr, Ipv4Addr, Ipv6Addr},
        os::windows::io::AsRawSocket,
        sync::atomic::Ordering,
    };
    use windows::Win32::{
        Foundation::HANDLE,
        NetworkManagement::IpHelper::{
            FreeMibTable, GetIfTable2, GetIpForwardTable2, GetIpInterfaceTable, GetUnicastIpAddressTable,
            NotifyRouteChange2, NotifyUnicastIpAddressChange, MIB_IF_TABLE2, MIB_IPFORWARD_ROW2,
            MIB_IPFORWARD_TABLE2, MIB_IPINTERFACE_TABLE, MIB_NOTIFICATION_TYPE, MIB_UNICASTIPADDRESS_ROW,
            MIB_UNICASTIPADDRESS_TABLE,
        },
        Networking::WinSock::{
            setsockopt, AF_INET, AF_INET6, AF_UNSPEC, IPPROTO_IP, IPPROTO_IPV6, IPV6_UNICAST_IF, IP_UNICAST_IF,
            SOCKADDR_INET, SOCKET,
        },
    };

    /// `MIB_IF_ROW2.InterfaceAndOperStatusFlags` bits (netioapi.h).
    const HARDWARE_INTERFACE: u8 = 0x01;
    const FILTER_INTERFACE: u8 = 0x02;

    unsafe extern "system" fn on_route(_: *const c_void, _: *const MIB_IPFORWARD_ROW2, _: MIB_NOTIFICATION_TYPE) {
        super::EVENTS.fetch_add(1, Ordering::SeqCst);
    }

    unsafe extern "system" fn on_address(
        _: *const c_void,
        _: *const MIB_UNICASTIPADDRESS_ROW,
        _: MIB_NOTIFICATION_TYPE,
    ) {
        super::EVENTS.fetch_add(1, Ordering::SeqCst);
    }

    /// Route and address change notifications, IPv4 and IPv6, for the life of the process (never cancelled: the
    /// callbacks only bump a counter).
    pub fn subscribe() -> bool {
        let mut routes = HANDLE::default();
        let mut addrs = HANDLE::default();
        let (r, a) = unsafe {
            (
                NotifyRouteChange2(AF_UNSPEC, Some(on_route), std::ptr::null(), false, &mut routes),
                NotifyUnicastIpAddressChange(AF_UNSPEC, Some(on_address), None, false, &mut addrs),
            )
        };
        if r.0 != 0 || a.0 != 0 {
            log::warn!("DD-1: network change notifications: routes {}, addresses {}", r.0, a.0);
        }
        r.0 == 0 || a.0 == 0
    }

    fn wide(s: &[u16]) -> String {
        let end = s.iter().position(|&c| c == 0).unwrap_or(s.len());
        String::from_utf16_lossy(&s[..end])
    }

    unsafe fn ip_of(sa: &SOCKADDR_INET) -> Option<IpAddr> {
        if sa.si_family == AF_INET {
            Some(IpAddr::V4(Ipv4Addr::from(sa.Ipv4.sin_addr.S_un.S_addr.to_ne_bytes())))
        } else if sa.si_family == AF_INET6 {
            Some(IpAddr::V6(Ipv6Addr::from(sa.Ipv6.sin6_addr.u.Byte)))
        } else {
            None
        }
    }

    /// Adapters (`GetIfTable2`), every unicast address (`GetUnicastIpAddressTable`), and the default routes
    /// (`GetIpForwardTable2`) with their interfaces' metric and media state (`GetIpInterfaceTable`).
    pub fn read() -> Option<(Vec<Nic>, Vec<Route>, Vec<IpAddr>)> {
        unsafe {
            let mut nics = Vec::new();
            let mut t: *mut MIB_IF_TABLE2 = std::ptr::null_mut();
            if GetIfTable2(&mut t).0 != 0 || t.is_null() {
                return None;
            }
            for r in std::slice::from_raw_parts((*t).Table.as_ptr(), (*t).NumEntries as usize) {
                let flags = r.InterfaceAndOperStatusFlags._bitfield;
                if flags & FILTER_INTERFACE != 0 {
                    continue; // the same adapter again under a filter driver
                }
                let mac = (r.PhysicalAddressLength == 6).then(|| {
                    let mut m = [0u8; 6];
                    m.copy_from_slice(&r.PhysicalAddress[..6]);
                    m
                });
                nics.push(Nic {
                    index: r.InterfaceIndex,
                    if_type: r.Type,
                    name: format!("{} {}", wide(&r.Description), wide(&r.Alias)),
                    mac,
                    hardware: flags & HARDWARE_INTERFACE != 0,
                    addrs: Vec::new(),
                });
            }
            FreeMibTable(t as *const c_void);

            let mut all = Vec::new();
            let mut t: *mut MIB_UNICASTIPADDRESS_TABLE = std::ptr::null_mut();
            if GetUnicastIpAddressTable(AF_UNSPEC, &mut t).0 != 0 || t.is_null() {
                return None;
            }
            for r in std::slice::from_raw_parts((*t).Table.as_ptr(), (*t).NumEntries as usize) {
                if let Some(ip) = ip_of(&r.Address) {
                    all.push(ip);
                    if let Some(n) = nics.iter_mut().find(|n| n.index == r.InterfaceIndex) {
                        n.addrs.push(ip);
                    }
                }
            }
            FreeMibTable(t as *const c_void);

            let mut interfaces: HashMap<(u32, bool), (u32, bool)> = HashMap::new();
            let mut t: *mut MIB_IPINTERFACE_TABLE = std::ptr::null_mut();
            if GetIpInterfaceTable(AF_UNSPEC, &mut t).0 != 0 || t.is_null() {
                return None;
            }
            for r in std::slice::from_raw_parts((*t).Table.as_ptr(), (*t).NumEntries as usize) {
                interfaces.insert((r.InterfaceIndex, r.Family == AF_INET6), (r.Metric, r.Connected));
            }
            FreeMibTable(t as *const c_void);

            let mut routes = Vec::new();
            let mut t: *mut MIB_IPFORWARD_TABLE2 = std::ptr::null_mut();
            if GetIpForwardTable2(AF_UNSPEC, &mut t).0 != 0 || t.is_null() {
                return None;
            }
            for r in std::slice::from_raw_parts((*t).Table.as_ptr(), (*t).NumEntries as usize) {
                if r.DestinationPrefix.PrefixLength != 0 {
                    continue;
                }
                let family = r.DestinationPrefix.Prefix.si_family;
                if family != AF_INET && family != AF_INET6 {
                    continue;
                }
                let v6 = family == AF_INET6;
                let Some(&(if_metric, connected)) = interfaces.get(&(r.InterfaceIndex, v6)) else {
                    continue;
                };
                routes.push(Route {
                    index: r.InterfaceIndex,
                    v6,
                    metric: r.Metric.saturating_add(if_metric),
                    connected,
                });
            }
            FreeMibTable(t as *const c_void);
            Some((nics, routes, all))
        }
    }

    fn pin_raw(raw: u64, index: u32, v6: bool) -> bool {
        let (level, name) = if v6 { (IPPROTO_IPV6.0, IPV6_UNICAST_IF) } else { (IPPROTO_IP.0, IP_UNICAST_IF) };
        let value = net::unicast_if_value(index, v6);
        let ok = unsafe { setsockopt(SOCKET(raw as usize), level, name, Some(&value)) } == 0;
        if !ok {
            log::debug!("DD-1: IP_UNICAST_IF {index} refused: {}", std::io::Error::last_os_error());
        }
        ok
    }

    pub fn pin_tcp(socket: &hbb_common::tokio::net::TcpSocket, index: u32, v6: bool) -> bool {
        pin_raw(socket.as_raw_socket(), index, v6)
    }

    pub fn pin_udp(socket: &hbb_common::tokio::net::UdpSocket, index: u32, v6: bool) -> bool {
        pin_raw(socket.as_raw_socket(), index, v6)
    }
}

/// Elsewhere (the apps are Windows apps): no adapter is ever chosen, so nothing is pinned and nothing reacts.
#[cfg(not(windows))]
mod sys {
    use super::net::{Nic, Route};
    use std::net::IpAddr;

    pub fn subscribe() -> bool {
        false
    }
    pub fn read() -> Option<(Vec<Nic>, Vec<Route>, Vec<IpAddr>)> {
        None
    }
    pub fn pin_tcp(_: &hbb_common::tokio::net::TcpSocket, _: u32, _: bool) -> bool {
        false
    }
    pub fn pin_udp(_: &hbb_common::tokio::net::UdpSocket, _: u32, _: bool) -> bool {
        false
    }
}
