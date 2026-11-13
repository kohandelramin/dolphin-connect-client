import 'dart:async';
import 'dart:convert';

import 'package:flutter_hbb/dolphin/tech/api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A scripted portal for the tech/ tests: answers by "METHOD /path" (the part after /api/app/v1), records every
/// request. A handler may return a `http.Response`, a JSON-able value (200), or throw (a network failure).
class FakePortal {
  final Map<String, List<Object? Function(http.Request)>> _routes = {};
  final List<http.Request> requests = [];

  /// Every answer the same: e.g. `on('GET /computers', (_) => {...})`.
  void on(String route, Object? Function(http.Request req) handler) => _routes[route] = [handler];

  /// One answer per call, the last repeated: e.g. a failure, then success.
  void onSeq(String route, List<Object? Function(http.Request req)> handlers) => _routes[route] = [...handlers];

  static String routeOf(http.Request r) {
    var path = r.url.path;
    if (path.startsWith(kApiPrefix)) path = path.substring(kApiPrefix.length);
    return '${r.method} $path';
  }

  List<http.Request> sent(String route) => requests.where((r) => routeOf(r) == route).toList();

  Map<String, dynamic> body(http.Request r) => r.body.isEmpty ? {} : jsonDecode(r.body) as Map<String, dynamic>;

  late final http.Client client = MockClient((req) async {
    requests.add(req);
    final list = _routes[routeOf(req)];
    if (list == null || list.isEmpty) {
      return json({'error': 'not_found', 'message': 'پیدا نشد.'}, 404);
    }
    final h = list.length > 1 ? list.removeAt(0) : list.first;
    final out = h(req);
    final value = out is Future ? await out : out;
    if (value is http.Response) return value;
    return json(value, 200);
  });

  static http.Response json(Object? body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status,
      headers: {'content-type': 'application/json; charset=utf-8'});

  static http.Response error(int status, String code, String message, [Map<String, dynamic> extra = const {}]) =>
      json({'error': code, 'message': message, ...extra}, status);
}

class FixedProbe implements NetworkProbe {
  bool up;
  FixedProbe([this.up = true]);
  @override
  Future<bool> hasNetwork() async => up;
}

/// An API client on [portal] with a token already set.
ApiClient apiOn(FakePortal portal, {String? token = 'tok-secret-123', NetworkProbe? probe, Duration? readTimeout}) =>
    ApiClient(
        portalUrl: 'http://portal.test',
        client: portal.client,
        token: () => token,
        probe: probe ?? FixedProbe(),
        readTimeout: readTimeout ?? kApiReadTimeout);

const orgA = {'id': '11111111-1111-4111-8111-111111111111', 'name': 'گردش‌کار', 'color': '#1d4ed8'};

Map<String, dynamic> pcJson(String id,
        {String rustdeskId = '123456789',
        String? label = 'پذیرش',
        String? hostname = 'PC-1',
        bool online = true,
        bool favorite = false,
        List<String> tags = const ['حسابداری'],
        Map<String, dynamic>? session}) =>
    {
      'id': id,
      'rustdeskId': rustdeskId,
      'hostname': hostname,
      'label': label,
      'organization': orgA,
      'tags': tags,
      'online': online,
      'lastSeenAt': '2026-11-14T10:00:00.000Z',
      'favorite': favorite,
      'shareStopped': false,
      'os': 'Windows 11',
      'dolphinVersion': '2.1.0',
      'session': session,
    };

Map<String, dynamic> pageJson(List<Map<String, dynamic>> rows, {String? next, int online = 1, int favorite = 0}) => {
      'rows': rows,
      'next': next,
      'counts': {'matching': rows.length, 'online': online, 'favorite': favorite},
    };

const callJson = {
  'requestId': '22222222-2222-4222-8222-222222222222',
  'authorizedUntil': '2026-11-14T12:00:00.000Z',
  'resumed': false,
  'consentMode': 'click',
  'waiting': false,
};

/// Lets pending futures and microtasks run.
Future<void> settle() => Future<void>.delayed(Duration.zero);
