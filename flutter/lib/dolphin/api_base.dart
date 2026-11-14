import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Plan 19: what the technician's App API client (tech/api.dart) and the customer's (customer_api/api.dart) share: the
/// errors, the strict JSON readers and one HTTP transport. Pure Dart, no widgets.
///
/// Rules kept here:
/// - the Bearer token and the password are never logged, put in an exception's text or in a URL;
/// - every error the person sees is the portal's own Persian `message` (`{error, message}`), or a Persian fallback when
///   the portal could not be reached or answered something unreadable;
/// - connect timeout 8 s, read timeout 15 s; GETs (idempotent) are tried once more after a network failure or a
///   502/503/504, nothing else is ever repeated (a repeated POST could open a second call or send a message twice);
/// - 401 `expired` (or `unauthorized`, `signed_out`) means the sign-in is over: [SignInExpired] is thrown and
///   [ApiTransport.signInExpired] fires, so the session store can show the sign-in screen.

const kApiConnectTimeout = Duration(seconds: 8);
const kApiReadTimeout = Duration(seconds: 15);
const kApiPrefix = '/api/app/v1';

// Persian texts for failures the portal could not word itself.
const kMsgNoInternet = 'اینترنت این رایانه وصل نیست؛ اتصال شبکه را بررسی کنید.';
const kMsgPortalDown = 'پورتال دلفین در دسترس نیست؛ چند لحظه بعد دوباره امتحان کنید.';
const kMsgPortalSlow = 'پورتال دلفین دیر جواب می‌دهد؛ چند لحظه بعد دوباره امتحان کنید.';
const kMsgBadAnswer = 'پاسخ پورتال دلفین خوانا نبود؛ چند لحظه بعد دوباره امتحان کنید.';
const kMsgSignInExpired = 'ورود شما تمام شده است؛ دوباره وارد شوید.';
const kMsgServer = 'خطای سرور؛ چند لحظه بعد دوباره امتحان کنید.';
const kMsgInvalid = 'درخواست نامعتبر است.';
const kMsgNotFound = 'پیدا نشد.';

// ---------------------------------------------------------------------------------------------------------------
// Errors

/// The portal answered with an error: [status] is the HTTP status, [code] the portal's `error` (e.g. `not_found`,
/// `in_session_other`, `taken`), [message] the Persian text to show. [extra] holds any other fields (e.g. `holderName`).
class ApiError implements Exception {
  final int status;
  final String code;
  final String message;
  final Map<String, dynamic> extra;
  const ApiError(this.status, this.code, this.message, [this.extra = const {}]);

  @override
  String toString() => 'ApiError($status, $code)'; // never the body or a header
}

/// 401 `expired` / `unauthorized` / `signed_out`: the session is over (its expiry, revoked, or the account deactivated).
class SignInExpired extends ApiError {
  const SignInExpired([String code = 'expired', String message = kMsgSignInExpired]) : super(401, code, message);

  @override
  String toString() => 'SignInExpired($code)';
}

/// Why the portal could not be reached (TD-1): the screen says which.
enum OfflineReason {
  /// No network on this PC, or names do not resolve.
  noInternet,

  /// The network is up but the portal refused, reset, or its proxy answered 502/503/504.
  portalDown,

  /// No answer within the timeouts.
  slow,
}

String offlineMessage(OfflineReason r) => switch (r) {
      OfflineReason.noInternet => kMsgNoInternet,
      OfflineReason.portalDown => kMsgPortalDown,
      OfflineReason.slow => kMsgPortalSlow,
    };

/// The portal could not be reached at all (no HTTP answer, or a gateway error after the retry).
class PortalUnreachable implements Exception {
  final OfflineReason reason;
  const PortalUnreachable(this.reason);
  String get message => offlineMessage(reason);

  @override
  String toString() => 'PortalUnreachable(${reason.name})';
}

/// The Persian text of any failure a call can end in.
String apiErrorText(Object error) => switch (error) {
      ApiError e => e.message,
      PortalUnreachable e => e.message,
      _ => kMsgServer,
    };

/// Is there any network on this PC? Injected so tests can say no.
abstract class NetworkProbe {
  Future<bool> hasNetwork();
}

/// Any non-loopback interface with an address. Unverified on every Windows setup: a disconnected adapter that keeps
/// an APIPA address would still count, which then reads as "portal down" rather than "no internet".
class InterfaceNetworkProbe implements NetworkProbe {
  const InterfaceNetworkProbe();
  @override
  Future<bool> hasNetwork() async {
    try {
      final list = await NetworkInterface.list(includeLoopback: false).timeout(const Duration(seconds: 2));
      return list.any((i) => i.addresses.isNotEmpty);
    } catch (_) {
      return true; // cannot tell: do not claim "no internet"
    }
  }
}

/// TD-1: the reason behind a failure to reach the portal.
Future<OfflineReason> classifyFailure(Object error, NetworkProbe probe) async {
  if (error is TimeoutException) return OfflineReason.slow;
  if (!await probe.hasNetwork()) return OfflineReason.noInternet;
  if (isDnsFailure(error)) return OfflineReason.noInternet;
  return OfflineReason.portalDown;
}

/// A name lookup failure: Dart's "Failed host lookup", or WSAHOST_NOT_FOUND / WSATRY_AGAIN / WSANO_DATA on Windows,
/// EAI_* on others.
bool isDnsFailure(Object error) {
  final text = error.toString();
  if (text.contains('Failed host lookup')) return true;
  if (error is SocketException) {
    final code = error.osError?.errorCode;
    if (code == 11001 || code == 11002 || code == 11004) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------------------------------------------
// Strict JSON reading: a field of the wrong type is a FormatException, which the transport turns into [kMsgBadAnswer].

Map<String, dynamic> jsonMap(Object? v, String what) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  throw FormatException('$what: not an object');
}

String jsonStr(Map<String, dynamic> m, String k) {
  final v = m[k];
  if (v is String) return v;
  throw FormatException('$k: not a string');
}

String? jsonStrN(Map<String, dynamic> m, String k) {
  final v = m[k];
  if (v == null) return null;
  if (v is String) return v;
  throw FormatException('$k: not a string');
}

bool jsonBool(Map<String, dynamic> m, String k, {bool? missing}) {
  final v = m[k];
  if (v is bool) return v;
  if (v == null && missing != null) return missing;
  throw FormatException('$k: not a bool');
}

int jsonInt(Map<String, dynamic> m, String k) {
  final v = m[k];
  if (v is int) return v;
  if (v is double && v == v.roundToDouble()) return v.toInt();
  throw FormatException('$k: not an int');
}

DateTime jsonDate(Map<String, dynamic> m, String k) {
  final d = jsonDateN(m, k);
  if (d == null) throw FormatException('$k: missing date');
  return d;
}

DateTime? jsonDateN(Map<String, dynamic> m, String k) {
  final v = m[k];
  if (v == null) return null;
  if (v is String) {
    final d = DateTime.tryParse(v);
    if (d != null) return d;
  }
  throw FormatException('$k: not a date');
}

List<String> jsonStrList(Map<String, dynamic> m, String k) {
  final v = m[k];
  if (v == null) return const [];
  if (v is List && v.every((e) => e is String)) return List<String>.unmodifiable(v.cast<String>());
  throw FormatException('$k: not a list of strings');
}

List<T> jsonList<T>(Object? v, String what, T Function(Map<String, dynamic>) one) {
  if (v is! List) throw FormatException('$what: not a list');
  return List<T>.unmodifiable(v.map((e) => one(jsonMap(e, what))));
}

/// `{ok: true}`, or an empty object: the answer of an action.
bool jsonOk(Map<String, dynamic> m) => jsonBool(m, 'ok', missing: true);

// ---------------------------------------------------------------------------------------------------------------
// The transport

typedef TokenSource = String? Function();

/// The production HTTP client: 8 s to connect; the read timeout is applied per request.
http.Client defaultHttpClient() => IOClient(HttpClient()
  ..connectionTimeout = kApiConnectTimeout
  ..idleTimeout = const Duration(seconds: 15));

/// One portal, one token, the rules above. The technician's and the customer's clients extend it with their endpoints.
class ApiTransport {
  final Uri portal;
  final http.Client httpClient;
  final NetworkProbe probe;
  final Duration readTimeout;

  /// The Persian text of a 403 the portal did not word.
  final String forbiddenMessage;

  /// Reads the current token; null when signed out.
  TokenSource token;

  final _expired = StreamController<SignInExpired>.broadcast();

  ApiTransport(
      {required String portalUrl,
      http.Client? client,
      TokenSource? token,
      this.probe = const InterfaceNetworkProbe(),
      this.readTimeout = kApiReadTimeout,
      this.forbiddenMessage = kMsgInvalid})
      : portal = Uri.parse(portalUrl),
        httpClient = client ?? defaultHttpClient(),
        token = token ?? (() => null);

  /// Fires on every 401 `expired`/`unauthorized`/`signed_out` from a signed-in call.
  Stream<SignInExpired> get signInExpired => _expired.stream;

  void close() {
    httpClient.close();
    _expired.close();
  }

  /// [path] under the portal's origin (with its leading slash).
  Uri portalUri(String path, [Map<String, String>? query]) {
    final base = portal.toString().replaceAll(RegExp(r'/+$'), '');
    final u = Uri.parse('$base$path');
    return query == null || query.isEmpty ? u : u.replace(queryParameters: query);
  }

  /// One path segment, encoded (an ID from an answer never changes the path).
  static String seg(String id) => Uri.encodeComponent(id);

  /// The Bearer token, or [SignInExpired] without asking the portal.
  String bearer() {
    final t = token();
    if (t == null || t.isEmpty) throw const SignInExpired('unauthorized');
    return t;
  }

  /// One call to `kApiPrefix + path` (or [path] itself when [prefixed] is false: the attachment routes). [retry]: GETs
  /// only, once, after a network failure or a gateway error. [bytes] is a raw body (an upload chunk), [body] a JSON one.
  Future<dynamic> apiSend(String method, String path,
      {Map<String, String>? query,
      Object? body,
      List<int>? bytes,
      Map<String, String> headers = const {},
      bool auth = true,
      bool retry = false,
      bool prefixed = true}) async {
    final uri = portalUri(prefixed ? '$kApiPrefix$path' : path, query);
    for (var attempt = 0;; attempt++) {
      final again = retry && attempt == 0;
      http.Response res;
      try {
        final req = http.Request(method, uri)..headers['Accept'] = 'application/json';
        req.headers.addAll(headers);
        if (auth) req.headers['Authorization'] = 'Bearer ${bearer()}';
        if (bytes != null) {
          req.headers['Content-Type'] = 'application/octet-stream';
          req.bodyBytes = bytes;
        } else if (body != null) {
          req.headers['Content-Type'] = 'application/json; charset=utf-8';
          req.bodyBytes = utf8.encode(jsonEncode(body));
        }
        final streamed = await httpClient.send(req).timeout(readTimeout);
        res = await http.Response.fromStream(streamed).timeout(readTimeout);
      } on ApiError {
        rethrow;
      } catch (e) {
        if (again) continue;
        throw PortalUnreachable(await classifyFailure(e, probe));
      }
      if (res.statusCode == 502 || res.statusCode == 503 || res.statusCode == 504) {
        if (again) continue;
        throw const PortalUnreachable(OfflineReason.portalDown);
      }
      return apiDecode(res, auth);
    }
  }

  /// A 2xx answer's JSON, or the portal's error as [ApiError] / [SignInExpired].
  dynamic apiDecode(http.Response res, bool auth) {
    Object? data;
    var readable = true;
    try {
      final text = utf8.decode(res.bodyBytes);
      data = text.trim().isEmpty ? null : jsonDecode(text);
    } catch (_) {
      readable = false;
    }
    final s = res.statusCode;
    if (s >= 200 && s < 300) {
      if (!readable) throw ApiError(s, 'bad_answer', kMsgBadAnswer);
      return data;
    }
    var code = '';
    var message = '';
    final extra = <String, dynamic>{};
    if (readable && data is Map) {
      final e = data['error'], msg = data['message'];
      if (e is String) code = e;
      if (msg is String) message = msg.trim();
      data.forEach((k, v) {
        if (k != 'error' && k != 'message') extra[k.toString()] = v;
      });
    }
    if (s == 401 &&
        auth &&
        (code == 'expired' || code == 'unauthorized' || code == 'signed_out' || code.isEmpty)) {
      final err = SignInExpired(code.isEmpty ? 'expired' : code, message.isEmpty ? kMsgSignInExpired : message);
      if (!_expired.isClosed) _expired.add(err);
      throw err;
    }
    if (code.isEmpty) {
      code = switch (s) { 400 => 'invalid', 403 => 'forbidden', 404 => 'not_found', 429 => 'rate_limited', _ => 'server' };
    }
    if (message.isEmpty) {
      message = switch (s) { 400 => kMsgInvalid, 403 => forbiddenMessage, 404 => kMsgNotFound, _ => kMsgServer };
    }
    throw ApiError(s, code, message, Map.unmodifiable(extra));
  }

  /// Runs [parse] on the answer; an answer of the wrong shape is [kMsgBadAnswer], never a crash.
  Future<T> apiParse<T>(Future<dynamic> answer, T Function(dynamic) parse) async {
    final data = await answer;
    try {
      return parse(data);
    } on FormatException {
      throw const ApiError(200, 'bad_answer', kMsgBadAnswer);
    } on TypeError {
      throw const ApiError(200, 'bad_answer', kMsgBadAnswer);
    }
  }

  Future<T> apiGet<T>(String path, T Function(Map<String, dynamic>) parse, [Map<String, String>? query]) =>
      apiParse(apiSend('GET', path, query: query, retry: true), (d) => parse(jsonMap(d, 'answer')));

  Future<T> apiPost<T>(String path, Object? body, T Function(Map<String, dynamic>) parse, {bool auth = true}) =>
      apiParse(apiSend('POST', path, body: body ?? const <String, dynamic>{}, auth: auth),
          (d) => parse(jsonMap(d, 'answer')));

  /// Streams a portal file into [target] with the Bearer token: [uri] must be one this client built for its own
  /// portal. Returns the bytes written. The file is removed when the download fails or [expectedSize] does not match.
  Future<int> downloadTo(Uri uri, File target, {int? expectedSize}) async {
    final req = http.Request('GET', uri)..headers['Authorization'] = 'Bearer ${bearer()}';
    http.StreamedResponse res;
    try {
      res = await httpClient.send(req).timeout(readTimeout);
    } catch (e) {
      throw PortalUnreachable(await classifyFailure(e, probe));
    }
    if (res.statusCode != 200) {
      apiDecode(await http.Response.fromStream(res), true);
      throw ApiError(res.statusCode, 'server', kMsgServer);
    }
    final sink = target.openWrite();
    var written = 0;
    try {
      await for (final chunk in res.stream.timeout(readTimeout)) {
        written += chunk.length;
        sink.add(chunk);
      }
      await sink.close();
    } catch (e) {
      await sink.close().catchError((_) {});
      if (await target.exists()) await target.delete();
      throw PortalUnreachable(await classifyFailure(e, probe));
    }
    if (expectedSize != null && written != expectedSize) {
      if (await target.exists()) await target.delete();
      throw const ApiError(200, 'bad_answer', kMsgBadAnswer);
    }
    return written;
  }
}
