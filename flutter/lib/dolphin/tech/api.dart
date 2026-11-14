import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../api_base.dart';
import '../brand.dart';
import '../switches.dart';

export '../api_base.dart';

/// Plan 19, the native technician app: a typed client for the portal's App API v1 (app/src/app/api/app/v1 in the
/// portal repo). Pure Dart, no widgets, so every endpoint's parsing and errors are unit-tested with a fake client.
/// The transport, the errors and the JSON readers are shared with the customer app (api_base.dart, Plan 19 C4).

const kMsgForbidden = 'این بخش فقط برای کارشناسان دلفین است.';

// The shared readers under the short names this file has always used.
Map<String, dynamic> _map(Object? v, String what) => jsonMap(v, what);
String _str(Map<String, dynamic> m, String k) => jsonStr(m, k);
String? _strN(Map<String, dynamic> m, String k) => jsonStrN(m, k);
bool _bool(Map<String, dynamic> m, String k, {bool? missing}) => jsonBool(m, k, missing: missing);
int _int(Map<String, dynamic> m, String k) => jsonInt(m, k);
DateTime _date(Map<String, dynamic> m, String k) => jsonDate(m, k);
DateTime? _dateN(Map<String, dynamic> m, String k) => jsonDateN(m, k);
List<String> _strList(Map<String, dynamic> m, String k) => jsonStrList(m, k);
List<T> _list<T>(Object? v, String what, T Function(Map<String, dynamic>) one) => jsonList(v, what, one);

/// `#rrggbb` → 0xFFrrggbb; anything else the brand's azure, so a tile is never transparent.
int parseHexColor(String? hex) {
  if (hex != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) {
    return 0xFF000000 | int.parse(hex.substring(1), radix: 16);
  }
  return 0xFF1462E0;
}

// ---------------------------------------------------------------------------------------------------------------
// Models

enum StaffRole { admin, technician }

class StaffInfo {
  final String id;
  final String name;
  final StaffRole role;

  /// The technician's registered Dolphin Connect ID, null until one is registered.
  final String? rustdeskId;
  const StaffInfo({required this.id, required this.name, required this.role, this.rustdeskId});

  factory StaffInfo.fromJson(Map<String, dynamic> m) => StaffInfo(
        id: _str(m, 'id'),
        name: _str(m, 'name'),
        role: switch (_str(m, 'role')) {
          'admin' => StaffRole.admin,
          'technician' => StaffRole.technician,
          final r => throw FormatException('role: $r'),
        },
        rustdeskId: _strN(m, 'rustdeskId'),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'role': role.name, 'rustdeskId': rustdeskId};
}

class LoginResult {
  /// Secret: kept only through the session store's protected storage, never logged.
  final String token;
  final DateTime expiresAt;
  final StaffInfo staff;
  const LoginResult(this.token, this.expiresAt, this.staff);

  factory LoginResult.fromJson(Map<String, dynamic> m) =>
      LoginResult(_str(m, 'token'), _date(m, 'expiresAt'), StaffInfo.fromJson(_map(m['staff'], 'staff')));

  @override
  String toString() => 'LoginResult(${staff.name})';
}

/// An organization as a PC or a request names it: `color` is its stable tile colour (`#rrggbb`).
class OrgRef {
  final String id;
  final String name;
  final String color;
  const OrgRef(this.id, this.name, this.color);
  int get colorValue => parseHexColor(color);

  factory OrgRef.fromJson(Map<String, dynamic> m) => OrgRef(_str(m, 'id'), _str(m, 'name'), _str(m, 'color'));
}

/// Who holds the PC's live session.
class PcSession {
  final String staffName;
  final bool mine;
  final String? requestId;
  const PcSession(this.staffName, this.mine, this.requestId);

  factory PcSession.fromJson(Map<String, dynamic> m) =>
      PcSession(_str(m, 'staffName'), _bool(m, 'mine'), _strN(m, 'requestId'));
}

/// One PC of «رایانه‌ها» (a tile or a row).
class Computer {
  final String id;
  final String rustdeskId;
  final String? hostname;
  final String? label;
  final OrgRef organization;
  final List<String> tags;
  final bool online;

  /// Null only for a row read from the offline cache.
  final DateTime? lastSeenAt;
  final bool favorite;
  final bool shareStopped;
  final String? os;
  final String? dolphinVersion;
  final PcSession? session;

  /// True when this row comes from the offline cache (TD-2): read-only, `online` unknown.
  final bool fromCache;

  const Computer({
    required this.id,
    required this.rustdeskId,
    this.hostname,
    this.label,
    required this.organization,
    this.tags = const [],
    this.online = false,
    this.lastSeenAt,
    this.favorite = false,
    this.shareStopped = false,
    this.os,
    this.dolphinVersion,
    this.session,
    this.fromCache = false,
  });

  /// What a tile shows as the name: the label, else the hostname, else the ID.
  String get displayName {
    final l = label?.trim() ?? '';
    if (l.isNotEmpty) return l;
    final h = hostname?.trim() ?? '';
    if (h.isNotEmpty) return h;
    return rustdeskId;
  }

  factory Computer.fromJson(Map<String, dynamic> m) => Computer(
        id: _str(m, 'id'),
        rustdeskId: _str(m, 'rustdeskId'),
        hostname: _strN(m, 'hostname'),
        label: _strN(m, 'label'),
        organization: OrgRef.fromJson(_map(m['organization'], 'organization')),
        tags: _strList(m, 'tags'),
        online: _bool(m, 'online'),
        lastSeenAt: _date(m, 'lastSeenAt'),
        favorite: _bool(m, 'favorite'),
        shareStopped: _bool(m, 'shareStopped', missing: false),
        os: _strN(m, 'os'),
        dolphinVersion: _strN(m, 'dolphinVersion'),
        session: m['session'] == null ? null : PcSession.fromJson(_map(m['session'], 'session')),
      );

  Computer copyWith({bool? favorite}) => Computer(
        id: id,
        rustdeskId: rustdeskId,
        hostname: hostname,
        label: label,
        organization: organization,
        tags: tags,
        online: online,
        lastSeenAt: lastSeenAt,
        favorite: favorite ?? this.favorite,
        shareStopped: shareStopped,
        os: os,
        dolphinVersion: dolphinVersion,
        session: session,
        fromCache: fromCache,
      );
}

/// For the filter chips: PCs matching the search/tag/organization, of which online and starred.
class ComputerCounts {
  final int matching;
  final int online;
  final int favorite;
  const ComputerCounts(this.matching, this.online, this.favorite);
  static const zero = ComputerCounts(0, 0, 0);

  factory ComputerCounts.fromJson(Map<String, dynamic> m) =>
      ComputerCounts(_int(m, 'matching'), _int(m, 'online'), _int(m, 'favorite'));
}

class ComputerPage {
  final List<Computer> rows;

  /// Opaque; null on the last page.
  final String? next;
  final ComputerCounts counts;
  const ComputerPage(this.rows, this.next, this.counts);

  factory ComputerPage.fromJson(Map<String, dynamic> m) => ComputerPage(
        _list(m['rows'], 'rows', Computer.fromJson),
        _strN(m, 'next'),
        m['counts'] == null ? ComputerCounts.zero : ComputerCounts.fromJson(_map(m['counts'], 'counts')),
      );
}

/// The list's exclusive views (the portal refuses online and favourite together).
enum PcView { all, online, favorite }

enum PcSort { seen, name, label, org }

/// The query behind «رایانه‌ها»: search, view, tag, organization, sort.
class ComputerQuery {
  final String q;
  final PcView view;
  final String? tag;
  final String? orgId;
  final PcSort sort;

  /// null: the portal's default for the sort.
  final bool? ascending;
  const ComputerQuery(
      {this.q = '', this.view = PcView.all, this.tag, this.orgId, this.sort = PcSort.seen, this.ascending});

  /// No search, tag or organization filter, all PCs: the list the offline cache keeps.
  bool get isUnfiltered => q.trim().isEmpty && view == PcView.all && (tag ?? '').isEmpty && (orgId ?? '').isEmpty;

  ComputerQuery copyWith(
          {String? q, PcView? view, String? Function()? tag, String? Function()? orgId, PcSort? sort, bool? Function()? ascending}) =>
      ComputerQuery(
        q: q ?? this.q,
        view: view ?? this.view,
        tag: tag != null ? tag() : this.tag,
        orgId: orgId != null ? orgId() : this.orgId,
        sort: sort ?? this.sort,
        ascending: ascending != null ? ascending() : this.ascending,
      );

  Map<String, String> toParams({String? cursor}) => {
        if (q.trim().isNotEmpty) 'q': q.trim().length > 100 ? q.trim().substring(0, 100) : q.trim(),
        if (view == PcView.online) 'online': '1',
        if (view == PcView.favorite) 'favorite': '1',
        if ((tag ?? '').isNotEmpty) 'tag': tag!,
        if ((orgId ?? '').isNotEmpty) 'org': orgId!,
        'sort': sort.name,
        if (ascending != null) 'dir': ascending! ? 'asc' : 'desc',
        if (cursor != null) 'cursor': cursor,
      };

  @override
  bool operator ==(Object other) =>
      other is ComputerQuery &&
      other.q == q &&
      other.view == view &&
      other.tag == tag &&
      other.orgId == orgId &&
      other.sort == sort &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(q, view, tag, orgId, sort, ascending);
}

enum ConsentMode { click, code }

ConsentMode _consent(Map<String, dynamic> m, String k) => switch (_str(m, k)) {
      'click' => ConsentMode.click,
      'code' => ConsentMode.code,
      final v => throw FormatException('$k: $v'),
    };

/// This technician's open call on a PC (the card's call box).
class OpenCall {
  final String requestId;
  final ConsentMode consentMode;
  final bool sessionLive;
  final DateTime? connectedSince;
  final bool hadConnection;
  final String? reasonId;
  final String? contactName;
  final String? contactPhone;

  /// Code mode: the customer's live one-time code, given through the portal (only to the assignee, by RLS); null while
  /// none is live and always in click mode. Secret: never logged; used once to open the session.
  final String? code;

  /// Code mode: the call waits for the customer's code (no live session, no code yet).
  final bool waitingForCode;
  const OpenCall({
    required this.requestId,
    required this.consentMode,
    required this.sessionLive,
    this.connectedSince,
    required this.hadConnection,
    this.reasonId,
    this.contactName,
    this.contactPhone,
    this.code,
    this.waitingForCode = false,
  });

  factory OpenCall.fromJson(Map<String, dynamic> m) => OpenCall(
        requestId: _str(m, 'requestId'),
        consentMode: _consent(m, 'consentMode'),
        sessionLive: _bool(m, 'sessionLive'),
        connectedSince: _dateN(m, 'connectedSince'),
        hadConnection: _bool(m, 'hadConnection'),
        reasonId: _strN(m, 'reasonId'),
        contactName: _strN(m, 'contactName'),
        contactPhone: _strN(m, 'contactPhone'),
        code: _strN(m, 'code'),
        waitingForCode: _bool(m, 'waitingForCode', missing: false),
      );

  @override
  String toString() => 'OpenCall($requestId)'; // never the code
}

/// One line of the last contacts: a request/call, or a connection.
sealed class HistoryEntry {
  final DateTime at;
  final String? pcName;
  const HistoryEntry(this.at, this.pcName);

  factory HistoryEntry.fromJson(Map<String, dynamic> m) => switch (_str(m, 'kind')) {
        'request' => HistoryRequest.fromJson(m),
        'connection' => HistoryConnection.fromJson(m),
        final k => throw FormatException('history kind: $k'),
      };
}

class HistoryRequest extends HistoryEntry {
  final String id;
  final int number;
  final String subject;

  /// customer | staff | app
  final String openedBy;
  final String status;
  final String? assigneeName;
  final DateTime? resolvedAt;
  final String? resolutionNote;
  const HistoryRequest(super.at, super.pcName,
      {required this.id,
      required this.number,
      required this.subject,
      required this.openedBy,
      required this.status,
      this.assigneeName,
      this.resolvedAt,
      this.resolutionNote});

  factory HistoryRequest.fromJson(Map<String, dynamic> m) => HistoryRequest(_date(m, 'at'), _strN(m, 'pcName'),
      id: _str(m, 'id'),
      number: _int(m, 'number'),
      subject: _str(m, 'subject'),
      openedBy: _str(m, 'openedBy'),
      status: _str(m, 'status'),
      assigneeName: _strN(m, 'assigneeName'),
      resolvedAt: _dateN(m, 'resolvedAt'),
      resolutionNote: _strN(m, 'resolutionNote'));
}

class HistoryConnection extends HistoryEntry {
  final int id;
  final String? technician;
  final bool verified;
  final int? connType;
  final DateTime? closedAt;
  final String? closeReason;
  final int files;
  const HistoryConnection(super.at, super.pcName,
      {required this.id,
      this.technician,
      required this.verified,
      this.connType,
      this.closedAt,
      this.closeReason,
      this.files = 0});

  factory HistoryConnection.fromJson(Map<String, dynamic> m) => HistoryConnection(_date(m, 'at'), _strN(m, 'pcName'),
      id: _int(m, 'id'),
      technician: _strN(m, 'technician'),
      verified: _bool(m, 'verified', missing: false),
      connType: m['connType'] == null ? null : _int(m, 'connType'),
      closedAt: _dateN(m, 'closedAt'),
      closeReason: _strN(m, 'closeReason'),
      files: m['files'] == null ? 0 : _int(m, 'files'));
}

/// What the customer sent from the app in the last day (a report or a screenshot). [url] is relative to the portal
/// and needs the Bearer token ([ApiClient.download]).
class SentItem {
  final String id;
  final String kind;
  final int size;
  final String? note;
  final DateTime createdAt;
  final String url;
  const SentItem(this.id, this.kind, this.size, this.note, this.createdAt, this.url);

  factory SentItem.fromJson(Map<String, dynamic> m) =>
      SentItem(_str(m, 'id'), _str(m, 'kind'), _int(m, 'size'), _strN(m, 'note'), _date(m, 'createdAt'), _str(m, 'url'));
}

/// GET /computers/{id}: the card (T2).
class ComputerDetail {
  final Computer computer;
  final String? customerName;
  final String? ownerName;
  final ConsentMode? consentMode;
  final String? clientVersion;
  final OpenCall? call;
  final List<HistoryEntry> history;
  final List<SentItem> sentToday;
  final List<String> tags;
  const ComputerDetail({
    required this.computer,
    this.customerName,
    this.ownerName,
    this.consentMode,
    this.clientVersion,
    this.call,
    this.history = const [],
    this.sentToday = const [],
    this.tags = const [],
  });

  factory ComputerDetail.fromJson(Map<String, dynamic> m) {
    final c = _map(m['computer'], 'computer');
    return ComputerDetail(
      computer: Computer.fromJson(c),
      customerName: _strN(c, 'customerName'),
      ownerName: _strN(c, 'ownerName'),
      consentMode: c['consentMode'] == null ? null : _consent(c, 'consentMode'),
      clientVersion: _strN(c, 'clientVersion'),
      call: m['call'] == null ? null : OpenCall.fromJson(_map(m['call'], 'call')),
      history: m['history'] == null ? const [] : _list(m['history'], 'history', HistoryEntry.fromJson),
      sentToday: m['sentToday'] == null ? const [] : _list(m['sentToday'], 'sentToday', SentItem.fromJson),
      tags: _strList(m, 'tags'),
    );
  }
}

/// POST /calls and POST /demo.
class CallStart {
  final String requestId;

  /// When the authorization ends; null while a code-mode call waits for the customer's code.
  final DateTime? authorizedUntil;

  /// The technician's own call was already open on this PC.
  final bool resumed;
  final ConsentMode consentMode;

  /// A code-mode call still waiting for the customer's code (TB-21): do not open the session yet.
  final bool waiting;
  const CallStart(
      {required this.requestId, this.authorizedUntil, this.resumed = false, required this.consentMode, this.waiting = false});

  factory CallStart.fromJson(Map<String, dynamic> m) => CallStart(
        requestId: _str(m, 'requestId'),
        authorizedUntil: _dateN(m, 'authorizedUntil'),
        resumed: _bool(m, 'resumed', missing: false),
        consentMode: _consent(m, 'consentMode'),
        waiting: _bool(m, 'waiting', missing: false),
      );
}

enum RequestScope { queue, mine, closed }

/// One row of the requests queue (T4).
class RequestRow {
  final String id;
  final int number;
  final String subject;
  final String status;

  /// normal | urgent
  final String priority;

  /// customer | staff | app («با من تماس بگیرید»)
  final String openedBy;

  /// support | demo
  final String kind;
  final OrgRef organization;
  final String? customerName;
  final String? contactName;
  final String? contactPhone;
  final String? deviceId;
  final String? pcName;
  final String? rustdeskId;
  final String? assigneeName;
  final bool mine;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  const RequestRow({
    required this.id,
    required this.number,
    required this.subject,
    required this.status,
    required this.priority,
    required this.openedBy,
    required this.kind,
    required this.organization,
    this.customerName,
    this.contactName,
    this.contactPhone,
    this.deviceId,
    this.pcName,
    this.rustdeskId,
    this.assigneeName,
    required this.mine,
    required this.createdAt,
    this.resolvedAt,
  });

  bool get urgent => priority == 'urgent';
  bool get isCallback => openedBy == 'app';

  factory RequestRow.fromJson(Map<String, dynamic> m) => RequestRow(
        id: _str(m, 'id'),
        number: _int(m, 'number'),
        subject: _str(m, 'subject'),
        status: _str(m, 'status'),
        priority: _str(m, 'priority'),
        openedBy: _str(m, 'openedBy'),
        kind: _strN(m, 'kind') ?? 'support',
        organization: OrgRef.fromJson(_map(m['organization'], 'organization')),
        customerName: _strN(m, 'customerName'),
        contactName: _strN(m, 'contactName'),
        contactPhone: _strN(m, 'contactPhone'),
        deviceId: _strN(m, 'deviceId'),
        pcName: _strN(m, 'pcName'),
        rustdeskId: _strN(m, 'rustdeskId'),
        assigneeName: _strN(m, 'assigneeName'),
        mine: _bool(m, 'mine', missing: false),
        createdAt: _date(m, 'createdAt'),
        resolvedAt: _dateN(m, 'resolvedAt'),
      );
}

class RequestPage {
  final List<RequestRow> rows;
  final String? next;

  /// Waiting in the queue, and assigned to me.
  final int queueCount;
  final int mineCount;
  const RequestPage(this.rows, this.next, this.queueCount, this.mineCount);

  factory RequestPage.fromJson(Map<String, dynamic> m) {
    final c = m['counts'] == null ? const <String, dynamic>{} : _map(m['counts'], 'counts');
    return RequestPage(_list(m['rows'], 'rows', RequestRow.fromJson), _strN(m, 'next'),
        c['queue'] == null ? 0 : _int(c, 'queue'), c['mine'] == null ? 0 : _int(c, 'mine'));
  }
}

class OrganizationRow {
  final String id;
  final String name;
  final String color;
  final String? dealerCode;
  final ConsentMode consentMode;
  final bool active;
  final String? city;

  /// Landlines as one text, as stored.
  final String? phones;
  final bool training;
  const OrganizationRow({
    required this.id,
    required this.name,
    required this.color,
    this.dealerCode,
    required this.consentMode,
    required this.active,
    this.city,
    this.phones,
    this.training = false,
  });
  int get colorValue => parseHexColor(color);

  factory OrganizationRow.fromJson(Map<String, dynamic> m) => OrganizationRow(
        id: _str(m, 'id'),
        name: _str(m, 'name'),
        color: _str(m, 'color'),
        dealerCode: _strN(m, 'dealerCode'),
        consentMode: _consent(m, 'consentMode'),
        active: _bool(m, 'active', missing: true),
        city: _strN(m, 'city'),
        phones: _strN(m, 'phones'),
        training: _bool(m, 'training', missing: false),
      );
}

class OrganizationPage {
  final List<OrganizationRow> rows;
  final String? next;
  const OrganizationPage(this.rows, this.next);

  factory OrganizationPage.fromJson(Map<String, dynamic> m) =>
      OrganizationPage(_list(m['rows'], 'rows', OrganizationRow.fromJson), _strN(m, 'next'));
}

class CustomerAccount {
  final String id;
  final String name;
  final String? phone;
  final bool active;
  const CustomerAccount(this.id, this.name, this.phone, this.active);

  factory CustomerAccount.fromJson(Map<String, dynamic> m) =>
      CustomerAccount(_str(m, 'id'), _str(m, 'name'), _strN(m, 'phone'), _bool(m, 'active', missing: true));
}

/// GET /organizations/{id}: read only.
class OrganizationDetail {
  final OrganizationRow organization;

  /// «اتصال بدون پذیرفتن» (ADR-0015) is on for this organization. A flag, not a password.
  final bool fixedPassword;
  final String? contactName;
  final String? contractNote;
  final List<CustomerAccount> customers;
  const OrganizationDetail(this.organization,
      {this.fixedPassword = false, this.contactName, this.contractNote, this.customers = const []});

  factory OrganizationDetail.fromJson(Map<String, dynamic> m) {
    final o = _map(m['organization'], 'organization');
    return OrganizationDetail(
      OrganizationRow.fromJson(o),
      fixedPassword: _bool(o, 'fixedPassword', missing: false),
      contactName: _strN(o, 'contactName'),
      contractNote: _strN(o, 'contractNote'),
      customers: m['customers'] == null ? const [] : _list(m['customers'], 'customers', CustomerAccount.fromJson),
    );
  }
}

/// A ready-made text (DD-50).
class Snippet {
  final String id;
  final String title;
  final String body;
  const Snippet(this.id, this.title, this.body);

  factory Snippet.fromJson(Map<String, dynamic> m) => Snippet(_str(m, 'id'), _str(m, 'title'), _str(m, 'body'));
}

enum NotificationKind { callback, request, authExpiring }

/// GET /notifications (TD-6). [id] is stable per event.
class AppNotification {
  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final String? deviceId;
  final String? requestId;
  final DateTime at;
  const AppNotification(
      {required this.id, required this.kind, required this.title, required this.body, this.deviceId, this.requestId, required this.at});

  /// Null for a kind this app does not know (a newer portal): skipped, never shown wrong.
  static AppNotification? tryParse(Map<String, dynamic> m) {
    final kind = switch (_str(m, 'kind')) {
      'callback' => NotificationKind.callback,
      'request' => NotificationKind.request,
      'auth_expiring' => NotificationKind.authExpiring,
      _ => null,
    };
    if (kind == null) return null;
    return AppNotification(
      id: _str(m, 'id'),
      kind: kind,
      title: _str(m, 'title'),
      body: _str(m, 'body'),
      deviceId: _strN(m, 'deviceId'),
      requestId: _strN(m, 'requestId'),
      at: _date(m, 'at'),
    );
  }
}

class CallReason {
  final String id;
  final String name;
  const CallReason(this.id, this.name);

  factory CallReason.fromJson(Map<String, dynamic> m) => CallReason(_str(m, 'id'), _str(m, 'name'));
}

/// The technician build the portal serves. [url] is relative to the portal and needs the Bearer token.
class LatestRelease {
  final String version;
  final String url;
  final String sha256;
  final int size;
  const LatestRelease(this.version, this.url, this.sha256, this.size);

  factory LatestRelease.fromJson(Map<String, dynamic> m) {
    final t = _map(m['technician'], 'technician');
    return LatestRelease(_str(m, 'version'), _str(t, 'url'), _str(t, 'sha256'), _int(t, 'size'));
  }
}

/// GET /config.
class AppConfig {
  /// Technician-side switches (TD-8), as [DolphinSwitches] reads them; unknown keys or modes fall back key by key.
  final DolphinSwitches switches;

  /// The theme overrides exactly as the portal sent them (decoded JSON, or null): handed untouched to the theme code
  /// (p19-base's `applyThemeOverrides`), which validates them.
  final Object? theme;

  /// [theme] as a JSON string, or null when the portal sent none.
  final String? themeJson;
  final LatestRelease? latest;
  final List<CallReason> callReasons;
  const AppConfig(
      {this.switches = const DolphinSwitches(kSwitchDefaults),
      this.theme,
      this.themeJson,
      this.latest,
      this.callReasons = const []});

  factory AppConfig.fromJson(Map<String, dynamic> m) {
    final sw = m['switches'];
    final theme = m['theme'];
    return AppConfig(
      switches: DolphinSwitches.parse(sw is Map ? jsonEncode(sw) : ''),
      theme: theme,
      themeJson: theme == null ? null : jsonEncode(theme),
      latest: m['latest'] == null ? null : LatestRelease.fromJson(_map(m['latest'], 'latest')),
      callReasons: m['callReasons'] == null ? const [] : _list(m['callReasons'], 'callReasons', CallReason.fromJson),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// The client

class ApiClient extends ApiTransport {
  ApiClient(
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
            forbiddenMessage: kMsgForbidden);

  static String _seg(String id) => ApiTransport.seg(id);
  Future<dynamic> _send(String method, String path, {Map<String, String>? query, bool retry = false}) =>
      apiSend(method, path, query: query, retry: retry);
  Future<T> _call<T>(Future<dynamic> answer, T Function(dynamic) parse) => apiParse(answer, parse);
  Future<T> _get<T>(String path, T Function(Map<String, dynamic>) parse, [Map<String, String>? query]) =>
      apiGet(path, parse, query);
  Future<T> _post<T>(String path, Object? body, T Function(Map<String, dynamic>) parse, {bool auth = true}) =>
      apiPost(path, body, parse, auth: auth);

  static bool _ok(Map<String, dynamic> m) => _bool(m, 'ok', missing: true);

  // -- sign-in

  /// POST /login. A wrong password is [ApiError] 401 `invalid`; too many tries 429 `rate_limited`.
  Future<LoginResult> login(String username, String password) =>
      _post('/login', {'username': username.trim(), 'password': password}, LoginResult.fromJson, auth: false);

  /// POST /logout: ends this session on the portal.
  Future<void> logout() => _post('/logout', null, _ok);

  /// POST /me/rustdesk-id: registers this app's own Dolphin Connect ID (WF-7).
  Future<void> setMyRustdeskId(String rustdeskId) => _post('/me/rustdesk-id', {'rustdeskId': rustdeskId}, _ok);

  // -- computers

  Future<ComputerPage> computers(ComputerQuery query, {String? cursor}) =>
      _get('/computers', ComputerPage.fromJson, query.toParams(cursor: cursor));

  Future<ComputerDetail> computer(String id) => _get('/computers/${_seg(id)}', ComputerDetail.fromJson);

  /// Returns the favourite state the portal saved.
  Future<bool> setFavorite(String id, bool on) =>
      _post('/computers/${_seg(id)}/favorite', {'on': on}, (m) => _bool(m, 'favorite'));

  // -- calls

  /// POST /calls. Another technician's session: [ApiError] 409 `in_session_other` with `extra['holderName']`; send
  /// again with [takeover] to take it over.
  Future<CallStart> startCall(String deviceId, {bool takeover = false}) =>
      _post('/calls', {'deviceId': deviceId, if (takeover) 'takeover': true}, CallStart.fromJson);

  /// POST /demo: «ارائه دمو», authorized as a call of kind demo.
  Future<CallStart> startDemo(String deviceId, {bool takeover = false}) =>
      _post('/demo', {'deviceId': deviceId, if (takeover) 'takeover': true}, CallStart.fromJson);

  Future<void> endCall(String requestId, {String? reasonId, String? note}) => _post(
      '/calls/${_seg(requestId)}/end',
      {if (reasonId != null) 'reasonId': reasonId, if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
      _ok);

  /// [reasonId] null clears the reason.
  Future<void> setReason(String requestId, String? reasonId) =>
      _post('/calls/${_seg(requestId)}/reason', {'reasonId': reasonId}, _ok);

  /// An internal note (staff only).
  Future<void> addNote(String requestId, String text) =>
      _post('/calls/${_seg(requestId)}/note', {'text': text.trim()}, _ok);

  /// A message the customer reads.
  Future<void> sendMessage(String requestId, String text) =>
      _post('/calls/${_seg(requestId)}/message', {'text': text.trim()}, _ok);

  // -- requests, organizations, history, snippets

  Future<RequestPage> requests(RequestScope scope, {String? cursor}) =>
      _get('/requests', RequestPage.fromJson, {'scope': scope.name, if (cursor != null) 'cursor': cursor});

  /// POST /requests/{id}/take. A colleague was quicker: [ApiError] 409 `taken`.
  Future<void> takeRequest(String id) => _post('/requests/${_seg(id)}/take', null, _ok);

  Future<OrganizationPage> organizations({String q = '', String? cursor}) => _get('/organizations',
      OrganizationPage.fromJson, {if (q.trim().isNotEmpty) 'q': q.trim(), if (cursor != null) 'cursor': cursor});

  Future<OrganizationDetail> organization(String id) =>
      _get('/organizations/${_seg(id)}', OrganizationDetail.fromJson);

  /// The last contacts with one PC, or with one organization. Exactly one of the two.
  Future<List<HistoryEntry>> history({String? deviceId, String? organizationId}) {
    assert((deviceId == null) != (organizationId == null), 'one of deviceId or organizationId');
    return _get('/history', (m) => _list(m['rows'], 'rows', HistoryEntry.fromJson),
        {if (deviceId != null) 'deviceId': deviceId, if (organizationId != null) 'organizationId': organizationId});
  }

  Future<List<Snippet>> snippets() => _get('/snippets', (m) => _list(m['rows'], 'rows', Snippet.fromJson));

  /// Audits that a ready-made text was pasted into a PC (never the text). One of the two IDs.
  Future<void> snippetUsed(String id, {String? rustdeskId, String? deviceId}) => _post('/snippets/${_seg(id)}/used',
      {if (rustdeskId != null) 'rustdeskId': rustdeskId, if (deviceId != null) 'deviceId': deviceId}, _ok);

  // -- notifications, config

  /// Oldest first. Pass the last item's `at` as [since]; without it the waiting requests of the last day.
  /// Kinds this app does not know are dropped.
  Future<List<AppNotification>> notifications({DateTime? since}) => _call(
        _send('GET', '/notifications', query: {if (since != null) 'since': since.toUtc().toIso8601String()}, retry: true),
        (d) {
          if (d is! List) throw const FormatException('notifications: not a list');
          final out = <AppNotification>[];
          for (final e in d) {
            final n = AppNotification.tryParse(_map(e, 'notification'));
            if (n != null) out.add(n);
          }
          return out;
        },
      );

  Future<AppConfig> config() => _get('/config', AppConfig.fromJson);

  // -- downloads

  /// A portal-relative download path (`SentItem.url`, `LatestRelease.url`) as a full URL. Only paths under the App
  /// API: the token is never sent anywhere else.
  Uri downloadUri(String relative) {
    if (!relative.startsWith('$kApiPrefix/') || relative.contains('..') || relative.contains('//')) {
      throw const ApiError(400, 'invalid', kMsgInvalid);
    }
    return portalUri(relative);
  }

  /// Streams a portal file (a report, a screenshot, the technician build) into [target] with the Bearer token.
  /// Returns the bytes written. The file is removed when the download fails or [expectedSize] does not match.
  Future<int> download(String relative, File target, {int? expectedSize}) =>
      downloadTo(downloadUri(relative), target, expectedSize: expectedSize);
}
