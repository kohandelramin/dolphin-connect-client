import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

import 'health.dart';

/// DD-38, DD-19: the facts behind «بررسی سلامت», read from Windows and the network. Nothing here changes a setting or
/// a connection: it reads the service's state, looks up the server's name, opens and closes one TCP connection per
/// port, and writes and removes a small file.

/// The Windows service's state through the service manager (no console window, no admin rights needed to read it).
ServiceState readServiceState(String name) {
  if (!Platform.isWindows || name.isEmpty) return ServiceState.unknown;
  final scm = win32.OpenSCManager(nullptr, nullptr, win32.SC_MANAGER_CONNECT);
  if (scm == 0) return ServiceState.unknown;
  final n = name.toNativeUtf16();
  final status = calloc<win32.SERVICE_STATUS>();
  // Resolve GetLastError before OpenService: its first call loads the symbol, which would overwrite the error.
  win32.GetLastError();
  try {
    final svc = win32.OpenService(scm, n, win32.SERVICE_QUERY_STATUS);
    if (svc == 0) return serviceStateFromError(win32.GetLastError());
    try {
      if (win32.QueryServiceStatus(svc, status) == 0) return ServiceState.unknown;
      return serviceStateFrom(status.ref.dwCurrentState);
    } finally {
      win32.CloseServiceHandle(svc);
    }
  } finally {
    calloc.free(status);
    calloc.free(n);
    win32.CloseServiceHandle(scm);
  }
}

/// The desktop folder (it may be moved, e.g. to OneDrive), or `%USERPROFILE%\Desktop`.
String desktopDir() {
  if (Platform.isWindows) {
    final id = win32.GUIDFromString(win32.FOLDERID_Desktop);
    final out = calloc<Pointer<Utf16>>();
    try {
      if (win32.SHGetKnownFolderPath(id, win32.KNOWN_FOLDER_FLAG.KF_FLAG_DEFAULT, 0, out) == 0) {
        final p = out.value.toDartString();
        win32.CoTaskMemFree(out.value);
        if (p.isNotEmpty) return p;
      }
    } catch (_) {
    } finally {
      calloc.free(out);
      calloc.free(id);
    }
  }
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
  return '$home${Platform.pathSeparator}Desktop';
}

/// `host[:port]` → (host, port); [defaultPort] when none is given. IPv6 in brackets is understood.
(String, int) hostPort(String raw, int defaultPort) {
  var s = raw.trim();
  if (s.contains(',')) s = s.split(',').first.trim();
  final v6 = RegExp(r'^\[([^\]]+)\](?::(\d+))?$').firstMatch(s);
  if (v6 != null) return (v6.group(1)!, int.tryParse(v6.group(2) ?? '') ?? defaultPort);
  final hp = RegExp(r'^([^:]+):(\d+)$').firstMatch(s);
  if (hp != null) return (hp.group(1)!, int.tryParse(hp.group(2)!) ?? defaultPort);
  return (s, defaultPort);
}

Future<List<String>?> lookup(String host) async {
  try {
    final a = await InternetAddress.lookup(host).timeout(const Duration(seconds: 5));
    return a.map((e) => e.address).toList();
  } catch (_) {
    return null;
  }
}

/// Opens one TCP connection and closes it at once.
Future<bool> canReach(String host, int port) async {
  if (host.isEmpty) return false;
  try {
    final s = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// Writes, reads back and removes a small file in each folder; returns the folders that refused.
List<String> unwritable(List<String> dirs) {
  final failed = <String>[];
  for (final d in dirs) {
    try {
      Directory(d).createSync(recursive: true);
      final f = File('$d${Platform.pathSeparator}.dolphin-write-test');
      f.writeAsStringSync('ok', flush: true);
      final ok = f.readAsStringSync() == 'ok';
      f.deleteSync();
      if (!ok) failed.add(d);
    } catch (_) {
      failed.add(d);
    }
  }
  return failed;
}

/// What the probes need from the app.
class HealthInputs {
  final bool installed;
  final String serviceName;
  final bool stopOption;
  final bool registered;
  final String rendezvous;
  final String relay;
  final String portal;
  final List<String> appDirs;
  final bool headless;
  final int windowsBuild;
  const HealthInputs(
      {required this.installed,
      required this.serviceName,
      required this.stopOption,
      required this.registered,
      required this.rendezvous,
      required this.relay,
      required this.portal,
      required this.appDirs,
      required this.headless,
      required this.windowsBuild});
}

/// Runs every check (the network ones side by side, about 5 s at worst).
Future<List<HealthItem>> runHealthChecks(HealthInputs i) async {
  final (rvHost, rvPort) = hostPort(i.rendezvous, 21116);
  final relayRaw = i.relay.trim().isEmpty ? rvHost : i.relay;
  final (relayHost, relayPort) = hostPort(relayRaw, 21117);
  final portalUri = Uri.tryParse(i.portal);
  final portalHost = portalUri?.host ?? '';
  final portalPort = portalUri == null ? 443 : (portalUri.hasPort ? portalUri.port : (portalUri.scheme == 'http' ? 80 : 443));
  final isIp = InternetAddress.tryParse(rvHost) != null;
  final results = await Future.wait([
    isIp || rvHost.isEmpty ? Future.value(null) : lookup(rvHost),
    canReach(rvHost, rvPort),
    canReach(relayHost, relayPort),
    canReach(portalHost, portalPort),
  ]);
  final addresses = results[0] as List<String>?;
  return [
    serviceItem(installed: i.installed, state: readServiceState(i.serviceName), stopOption: i.stopOption),
    registeredItem(i.registered),
    dnsItem(rvHost, isIp: isIp, addresses: addresses),
    portItem('سرور دلفین', rvPort, results[1] as bool),
    portItem('رله‌ی دلفین', relayPort, results[2] as bool),
    portItem('پورتال دلفین', portalPort, results[3] as bool),
    diskItem(unwritable(i.appDirs)),
    displayItem(headless: i.headless, installed: i.installed, windowsBuild: i.windowsBuild),
  ];
}
