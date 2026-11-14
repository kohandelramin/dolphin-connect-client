import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../api_base.dart';
import '../brand.dart';

export '../api_base.dart';

/// Plan 19 C4: a typed client for the portal's customer App API (app/src/app/api/app/v1/customer in the portal repo),
/// for the customer app's own «درخواست‌ها و پیام‌ها». Pure Dart, no widgets; the transport and its rules (no token or
/// password in a log, an error's text or a URL; Persian errors; one retry for GETs only) are api_base.dart's.
///
/// The one-time password: [CustomerApi.allowConnect] puts it in that one request's body and nowhere else. It is never
/// a field of this client, never in a URL, and never in an error's text.

const kMsgCustomerForbidden = 'این کار برای حساب شما مجاز نیست.';

/// UN-11, the portal's limits (src/lib/attachments.ts): 500 MB a file, 4 MB a chunk.
const kAttachmentMaxBytes = 500 * 1024 * 1024;
const kAttachmentChunkBytes = 4 * 1024 * 1024;

/// The header the attachment routes ask for on writes (src/lib/upload-guard.ts UPLOAD_HEADER).
const kUploadHeader = 'x-dolphin-upload';

// The web portal's own texts for attachment failures (src/components/attachments.tsx).
const kMsgFileClosed = 'این درخواست بسته شده است.';
const kMsgFileTooMany = 'به این درخواست بیش از این نمی‌شود فایل فرستاد.';
const kMsgFileOff = 'فرستادن فایل روی این سرور فعال نیست.';
const kMsgFileFailed = 'فایل فرستاده نشد.';
const kMsgFileTooBig = 'حداکثر اندازه‌ی هر فایل ۵۰۰ مگابایت است.';
const kMsgFileEmpty = 'این فایل خالی است.';
const kMsgFileOffline =
    'اتصال اینترنت قطع است. بعداً همان فایل را دوباره انتخاب کنید؛ از جایی که مانده ادامه پیدا می‌کند.';

/// What a customer must do before anything else (403 `password_change`, UN-10).
const kErrPasswordChange = 'password_change';

// ---------------------------------------------------------------------------------------------------------------
// Models

class CustomerInfo {
  final String id;
  final String name;
  final String username;
  final String organizationId;
  final String organizationName;
  const CustomerInfo(
      {required this.id,
      required this.name,
      required this.username,
      required this.organizationId,
      required this.organizationName});

  factory CustomerInfo.fromJson(Map<String, dynamic> m) {
    final org = jsonMap(m['organization'], 'organization');
    return CustomerInfo(
        id: jsonStr(m, 'id'),
        name: jsonStr(m, 'name'),
        username: jsonStr(m, 'username'),
        organizationId: jsonStr(org, 'id'),
        organizationName: jsonStr(org, 'name'));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'organization': {'id': organizationId, 'name': organizationName},
      };

  @override
  String toString() => 'CustomerInfo($id)';
}

class CustomerLogin {
  /// Secret: kept only through the session store's DPAPI box, never logged.
  final String token;
  final DateTime expiresAt;
  final bool mustChangePassword;
  final CustomerInfo customer;
  const CustomerLogin(this.token, this.expiresAt, this.mustChangePassword, this.customer);

  factory CustomerLogin.fromJson(Map<String, dynamic> m) => CustomerLogin(
      jsonStr(m, 'token'),
      jsonDate(m, 'expiresAt'),
      jsonBool(m, 'mustChangePassword', missing: false),
      CustomerInfo.fromJson(jsonMap(m['customer'], 'customer')));

  @override
  String toString() => 'CustomerLogin(${customer.id})'; // never the token
}

class CustomerMe {
  final CustomerInfo customer;
  final bool mustChangePassword;
  const CustomerMe(this.customer, this.mustChangePassword);

  /// `{customer: {...}, mustChangePassword}`, or the customer's fields at the top level.
  factory CustomerMe.fromJson(Map<String, dynamic> m) => CustomerMe(
      CustomerInfo.fromJson(m['customer'] == null ? m : jsonMap(m['customer'], 'customer')),
      jsonBool(m, 'mustChangePassword', missing: false));
}

class Product {
  final String id;
  final String name;
  const Product(this.id, this.name);
  factory Product.fromJson(Map<String, dynamic> m) => Product(jsonStr(m, 'id'), jsonStr(m, 'name'));
}

enum CustomerScope { open, closed }

/// The request statuses (the portal's `request_status`).
const kOpenStatuses = {'submitted', 'claimed', 'in_session'};

class LastMessage {
  final bool fromStaff;
  final String authorName;
  final String body;
  final DateTime at;
  const LastMessage(this.fromStaff, this.authorName, this.body, this.at);

  factory LastMessage.fromJson(Map<String, dynamic> m) => LastMessage(
      _staff(m), jsonStrN(m, 'authorName') ?? '', jsonStr(m, 'body'), jsonDate(m, 'at'));
}

bool _staff(Map<String, dynamic> m) => switch (jsonStr(m, 'authorKind')) {
      'staff' => true,
      'customer' => false,
      final k => throw FormatException('authorKind: $k'),
    };

/// `product` is the product's name, or `{id, name}`, or null.
String? _product(Map<String, dynamic> m) {
  final v = m['product'];
  if (v == null) return null;
  if (v is String) return v;
  return jsonStrN(jsonMap(v, 'product'), 'name');
}

/// `unread` is a flag, or a count.
bool _unread(Map<String, dynamic> m) {
  final v = m['unread'];
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v > 0;
  throw const FormatException('unread: not a bool');
}

class CustomerRequestRow {
  final String id;
  final int number;
  final String subject;
  final String? product;
  final String status;
  final String priority;
  final DateTime updatedAt;
  final LastMessage? lastMessage;
  final bool unread;
  const CustomerRequestRow(
      {required this.id,
      required this.number,
      required this.subject,
      this.product,
      required this.status,
      this.priority = 'normal',
      required this.updatedAt,
      this.lastMessage,
      this.unread = false});

  bool get open => kOpenStatuses.contains(status);
  bool get urgent => priority == 'urgent';

  /// «لغو درخواست»: the web offers it while nobody is connected (submitted or claimed).
  bool get cancellable => status == 'submitted' || status == 'claimed';

  factory CustomerRequestRow.fromJson(Map<String, dynamic> m) => CustomerRequestRow(
        id: jsonStr(m, 'id'),
        number: jsonInt(m, 'number'),
        subject: jsonStr(m, 'subject'),
        product: _product(m),
        status: jsonStr(m, 'status'),
        priority: jsonStrN(m, 'priority') ?? 'normal',
        updatedAt: jsonDate(m, 'updatedAt'),
        lastMessage: m['lastMessage'] == null ? null : LastMessage.fromJson(jsonMap(m['lastMessage'], 'lastMessage')),
        unread: _unread(m),
      );
}

/// Where a code-mode request stands with its one-time code (the portal's src/lib/code-state.ts).
enum CodeState { notNeeded, waiting, ready, used }

CodeState _codeState(String? v) => switch (v) {
      'waiting' => CodeState.waiting,
      'ready' => CodeState.ready,
      'used' => CodeState.used,
      _ => CodeState.notNeeded,
    };

/// The connect box of one request.
class ConnectInfo {
  /// The portal shows the box: the request is open and a technician waits for this PC.
  final bool show;
  final String? technicianName;

  /// The organization's consent mode is the one-time code; otherwise click (the customer presses «پذیرفتن»).
  final bool codeMode;
  final CodeState codeState;
  final bool codeSubmitted;
  final DateTime? codeExpiresAt;
  final bool sessionLive;
  final String? deviceRustdeskId;
  const ConnectInfo(
      {this.show = false,
      this.technicianName,
      this.codeMode = false,
      this.codeState = CodeState.notNeeded,
      this.codeSubmitted = false,
      this.codeExpiresAt,
      this.sessionLive = false,
      this.deviceRustdeskId});

  static const none = ConnectInfo();

  factory ConnectInfo.fromJson(Map<String, dynamic> m) => ConnectInfo(
        show: jsonBool(m, 'show', missing: false),
        technicianName: jsonStrN(m, 'technicianName'),
        codeMode: switch (jsonStrN(m, 'consentMode') ?? 'click') {
          'code' => true,
          'click' => false,
          final c => throw FormatException('consentMode: $c'),
        },
        codeState: _codeState(jsonStrN(m, 'codeState')),
        codeSubmitted: jsonBool(m, 'codeSubmitted', missing: false),
        codeExpiresAt: jsonDateN(m, 'codeExpiresAt'),
        sessionLive: jsonBool(m, 'sessionLive', missing: false),
        deviceRustdeskId: jsonStrN(m, 'deviceRustdeskId'),
      );
}

class RequestMessage {
  final String id;
  final bool fromStaff;
  final String authorName;
  final String body;
  final DateTime at;
  const RequestMessage(this.id, this.fromStaff, this.authorName, this.body, this.at);

  factory RequestMessage.fromJson(Map<String, dynamic> m) =>
      RequestMessage(jsonStr(m, 'id'), _staff(m), jsonStrN(m, 'authorName') ?? '', jsonStr(m, 'body'), jsonDate(m, 'at'));
}

class RequestFile {
  final String id;
  final String name;
  final int size;
  final DateTime at;
  final bool mine;
  const RequestFile(this.id, this.name, this.size, this.at, this.mine);

  factory RequestFile.fromJson(Map<String, dynamic> m) => RequestFile(
      jsonStr(m, 'id'), jsonStr(m, 'name'), jsonInt(m, 'size'), jsonDate(m, 'at'), jsonBool(m, 'mine', missing: false));
}

class CustomerRequestDetail {
  final CustomerRequestRow row;
  final String description;

  /// The resolution note of a resolved request.
  final String? result;
  final ConnectInfo connect;
  final List<RequestMessage> messages;

  /// Null when the server has no attachments volume (UN-11): no files section.
  final List<RequestFile>? files;
  const CustomerRequestDetail(
      {required this.row,
      this.description = '',
      this.result,
      this.connect = ConnectInfo.none,
      this.messages = const [],
      this.files});

  factory CustomerRequestDetail.fromJson(Map<String, dynamic> m) {
    final r = jsonMap(m['request'], 'request');
    return CustomerRequestDetail(
      row: CustomerRequestRow.fromJson(r),
      description: jsonStrN(r, 'description') ?? '',
      result: jsonStrN(r, 'result'),
      connect: m['connect'] == null ? ConnectInfo.none : ConnectInfo.fromJson(jsonMap(m['connect'], 'connect')),
      messages: m['messages'] == null ? const [] : jsonList(m['messages'], 'messages', RequestMessage.fromJson),
      files: m['attachments'] == null ? null : jsonList(m['attachments'], 'attachments', RequestFile.fromJson),
    );
  }
}

class CreatedRequest {
  final String id;
  final int number;
  const CreatedRequest(this.id, this.number);
  factory CreatedRequest.fromJson(Map<String, dynamic> m) => CreatedRequest(jsonStr(m, 'id'), jsonInt(m, 'number'));
}

/// Reads [length] bytes of the file being sent, from [offset].
typedef ChunkReader = Future<List<int>> Function(int offset, int length);

/// The Persian text of an attachment route's error code.
String uploadErrorText(String code) => switch (code) {
      'closed' => kMsgFileClosed,
      'too_many' => kMsgFileTooMany,
      'off' => kMsgFileOff,
      _ => kMsgFileFailed,
    };

// ---------------------------------------------------------------------------------------------------------------
// The client

class CustomerApi extends ApiTransport {
  CustomerApi(
      {String? portalUrl,
      http.Client? client,
      TokenSource? token,
      NetworkProbe probe = const InterfaceNetworkProbe(),
      Duration readTimeout = kApiReadTimeout})
      : super(
            portalUrl: portalUrl ?? DolphinBrand.portalUrl,
            client: client,
            token: token,
            probe: probe,
            readTimeout: readTimeout,
            forbiddenMessage: kMsgCustomerForbidden);

  final _passwordChange = StreamController<void>.broadcast();

  /// Fires on every 403 `password_change`: the customer must change the password before anything else.
  Stream<void> get passwordChangeNeeded => _passwordChange.stream;

  @override
  dynamic apiDecode(http.Response res, bool auth) {
    try {
      return super.apiDecode(res, auth);
    } on ApiError catch (e) {
      if (e.status == 403 && e.code == kErrPasswordChange && !_passwordChange.isClosed) _passwordChange.add(null);
      rethrow;
    }
  }

  @override
  void close() {
    _passwordChange.close();
    super.close();
  }

  static String _seg(String id) => ApiTransport.seg(id);
  static const _c = '/customer';

  // -- sign-in and account

  /// POST /customer/login (ADR-0008: username and password only). A wrong password is [ApiError] 401 `invalid`, too
  /// many tries 429 `rate_limited`, both with the portal's Persian text.
  Future<CustomerLogin> login(String username, String password) =>
      apiPost('$_c/login', {'username': username.trim(), 'password': password}, CustomerLogin.fromJson, auth: false);

  Future<void> logout() => apiPost('$_c/logout', null, jsonOk);

  Future<CustomerMe> me() => apiGet('$_c/me', CustomerMe.fromJson);

  /// The web's rules and messages (too short, wrong current, rate limited) come back as [ApiError].
  Future<void> changePassword(String current, String next) =>
      apiPost('$_c/password', {'current': current, 'next': next}, jsonOk);

  // -- requests

  /// What the new-request form offers: a list, or `{rows: [...]}`.
  Future<List<Product>> products() => apiParse(apiSend('GET', '$_c/products', retry: true), (d) {
        final list = d is List ? d : jsonMap(d, 'answer')['rows'];
        return jsonList(list, 'products', Product.fromJson);
      });

  Future<List<CustomerRequestRow>> requests(CustomerScope scope) => apiGet(
      '$_c/requests', (m) => jsonList(m['rows'], 'rows', CustomerRequestRow.fromJson), {'scope': scope.name});

  /// Requests with a staff message newer than the customer's last view.
  Future<int> unread() => apiGet('$_c/unread', (m) => jsonInt(m, 'count'));

  /// Viewing marks the request read.
  Future<CustomerRequestDetail> request(String id) =>
      apiGet('$_c/requests/${_seg(id)}', CustomerRequestDetail.fromJson);

  /// [rustdeskId]: this PC's own ID, sent with every request the app opens (the customer never types it).
  Future<CreatedRequest> createRequest(
          {String? productId, required String subject, required String description, String? rustdeskId}) =>
      apiPost(
          '$_c/requests',
          {
            'productId': productId ?? '',
            'subject': subject.trim(),
            'description': description.trim(),
            if (rustdeskId != null && rustdeskId.isNotEmpty) 'rustdeskId': rustdeskId,
          },
          CreatedRequest.fromJson);

  Future<void> sendMessage(String requestId, String body) =>
      apiPost('$_c/requests/${_seg(requestId)}/messages', {'body': body.trim()}, jsonOk);

  /// «اجازه‌ی اتصال به این رایانه» (the web's `submitDevice`): this PC's ID, and in code mode its current one-time
  /// password. Called only from the customer's own press; [code] lives in this request's body and nowhere else.
  Future<void> allowConnect(String requestId, {required String rustdeskId, String? code}) => apiPost(
      '$_c/requests/${_seg(requestId)}/device',
      {'rustdeskId': rustdeskId, if (code != null && code.isNotEmpty) 'code': code},
      jsonOk);

  Future<void> endSession(String requestId) => apiPost('$_c/requests/${_seg(requestId)}/end-session', null, jsonOk);

  Future<void> cancel(String requestId) => apiPost('$_c/requests/${_seg(requestId)}/cancel', null, jsonOk);

  // -- attachments (UN-11's routes, with the customer's Bearer token)

  /// Sends a file of [size] bytes in 4 MB chunks: POST /api/requests/{id}/attachments starts (or resumes, by name and
  /// size), then PUT /api/attachments/{aid}?offset=… until the server has it all. A dropped link waits and goes on from
  /// where the server stopped, up to [maxFailures] times in a row. Errors are [ApiError] with the web's Persian texts.
  Future<void> upload(String requestId,
      {required String name,
      required int size,
      required ChunkReader read,
      void Function(int received)? onProgress,
      int maxFailures = 8,
      Future<void> Function(Duration) wait = _wait}) async {
    if (size <= 0) throw const ApiError(400, 'empty', kMsgFileEmpty);
    if (size > kAttachmentMaxBytes) throw const ApiError(400, 'too_big', kMsgFileTooBig);
    const headers = {kUploadHeader: '1'};
    final String fileId;
    int received;
    try {
      final start = await apiParse(
          apiSend('POST', '/api/requests/${_seg(requestId)}/attachments',
              body: {'name': name, 'size': size}, headers: headers, prefixed: false),
          (d) => jsonMap(d, 'answer'));
      fileId = jsonStr(start, 'id');
      received = jsonInt(start, 'received');
    } on SignInExpired {
      rethrow;
    } on ApiError catch (e) {
      throw ApiError(e.status, e.code, uploadErrorText(e.code));
    } on FormatException {
      throw const ApiError(200, 'bad_answer', kMsgBadAnswer);
    }
    onProgress?.call(received);
    var failures = 0;
    while (received < size) {
      try {
        final bytes = await read(received, (size - received).clamp(0, kAttachmentChunkBytes));
        final answer = await apiSend('PUT', '/api/attachments/${_seg(fileId)}',
            query: {'offset': '$received'}, bytes: bytes, headers: headers, prefixed: false);
        final r = jsonMap(answer, 'answer')['received'];
        if (r is int) received = r;
        failures = 0;
        onProgress?.call(received);
        continue;
      } on SignInExpired {
        rethrow;
      } on ApiError catch (e) {
        // 409: the server has a different amount (an earlier try did land); go on from there.
        final r = e.extra['received'];
        if (e.status == 409 && r is int) {
          received = r;
          failures = 0;
          onProgress?.call(received);
          continue;
        }
        if (e.status < 500) throw ApiError(e.status, e.code, kMsgFileFailed);
      } on PortalUnreachable {
        // The link dropped: wait below.
      }
      failures += 1;
      if (failures > maxFailures) throw const ApiError(0, 'offline', kMsgFileOffline);
      await wait(Duration(seconds: (2 * failures).clamp(2, 30)));
    }
  }

  static Future<void> _wait(Duration d) => Future<void>.delayed(d);

  /// «دریافت»: the file into [target] (the place the customer chose), checked against [size].
  Future<int> downloadFile(String fileId, File target, {int? size}) =>
      downloadTo(portalUri('/api/attachments/${_seg(fileId)}'), target, expectedSize: size);
}
