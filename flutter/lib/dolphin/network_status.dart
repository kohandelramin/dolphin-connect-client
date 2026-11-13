import 'dart:io' show InternetAddress;

import 'digits.dart';
import 'home_status.dart';

/// The server address this app uses: the build's `custom-rendezvous-server` (compiled into the override settings by
/// dolphin/gen_profile.py, read through the synced options like any other option).
const kRendezvousServerOption = 'custom-rendezvous-server';

/// Written by upstream's NAT test (src/common.rs test_nat_type_): the local address of the socket that reached our
/// server, i.e. this PC's IP on the network it uses to reach Dolphin. Missing until that test has run.
const kLocalIpOption = 'local-ip-addr';

enum NetTone { good, neutral, bad }

/// What a line is, so the box can draw its icon: the connection state (Wi-Fi, glowing when connected), an address, or
/// a plain line (the diagnostic report's).
enum NetKind { status, address, plain }

/// One line of the network box (DD-8): «وضعیت شبکه: متصل», read out on the phone.
class NetRow {
  final String label;
  final String value;
  final NetTone tone;

  /// Addresses read left to right.
  final bool ltr;
  final NetKind kind;
  const NetRow(this.label, this.value, {this.tone = NetTone.neutral, this.ltr = false, this.kind = NetKind.plain});

  @override
  String toString() => '$label: $value';
}

/// This PC's IP, or '' when there is none worth showing: missing, not an address, unspecified or loopback.
String localIpFrom(String raw) {
  final a = InternetAddress.tryParse(raw.trim());
  if (a == null || a.isLoopback) return '';
  if (a.address == '0.0.0.0' || a.address == '::') return '';
  return a.address;
}

bool _isIp(String s) => InternetAddress.tryParse(s) != null;

/// The server as shown: the host without the port; an IP in Persian digits, a name as it is.
String serverLabel(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  if (s.contains(',')) s = s.split(',').first.trim();
  final v4Port = RegExp(r'^([^:\[\]]+):\d+$').firstMatch(s);
  if (v4Port != null) s = v4Port.group(1)!;
  final v6Port = RegExp(r'^\[([^\]]+)\](?::\d+)?$').firstMatch(s);
  if (v6Port != null) s = v6Port.group(1)!;
  return _isIp(s) ? faDigits(s) : s;
}

/// The customer's network box under the ID (DD-8). Owner 2026-11-13: only the connection state and this PC's IP; no
/// server name, address or relay (the diagnostic report keeps those, [diagnosticNetworkRows]).
const kNetStatusLabel = 'وضعیت شبکه';
const kNetIpLabel = 'IP رایانه';
const kNetIpUnknown = 'نامشخص';

List<NetRow> networkRows({required DolphinServerState server, required String localIp}) {
  final (value, tone) = switch (server) {
    DolphinServerState.ready => ('متصل', NetTone.good),
    DolphinServerState.connecting => ('در حال اتصال…', NetTone.neutral),
    DolphinServerState.offline => ('وصل نیست', NetTone.bad),
    DolphinServerState.stopped => ('سرویس خاموش است', NetTone.bad),
  };
  final ip = localIpFrom(localIp);
  return [
    NetRow(kNetStatusLabel, value, tone: tone, kind: NetKind.status),
    NetRow(kNetIpLabel, ip.isEmpty ? kNetIpUnknown : faDigits(ip), ltr: ip.isNotEmpty, kind: NetKind.address),
  ];
}

/// The network lines of the diagnostic report (DD-7, DD-38): the server, its address, this PC's IP and a changed ID.
/// [idChanged] is the visible trace of an ID clash: on a clash the server answers UUID_MISMATCH and the client picks a
/// new ID by itself (src/rendezvous_mediator.rs handle_uuid_mismatch), without telling the window.
///
/// [extra] is where later phases add their lines (Phase 6: the VPN line, DD-1); nothing is shown for a feature that
/// does not exist yet.
List<NetRow> diagnosticNetworkRows(
    {required DolphinServerState server,
    required String serverAddress,
    required String localIp,
    bool idChanged = false,
    List<NetRow> extra = const []}) {
  final (value, tone) = switch (server) {
    DolphinServerState.ready => ('وصل و ثبت‌شده', NetTone.good),
    DolphinServerState.connecting => ('در حال اتصال…', NetTone.neutral),
    DolphinServerState.offline => ('وصل نیست', NetTone.bad),
    DolphinServerState.stopped => ('سرویس خاموش است', NetTone.bad),
  };
  final host = serverLabel(serverAddress);
  final ip = localIpFrom(localIp);
  return [
    NetRow('سرور دلفین', value, tone: tone),
    if (host.isNotEmpty) NetRow('نشانی سرور', host, ltr: true),
    if (ip.isNotEmpty) NetRow('IP این رایانه', faDigits(ip), ltr: true),
    if (idChanged) const NetRow('شناسه', 'تازه عوض شد', tone: NetTone.bad),
    ...extra,
  ];
}
