import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/tech/actions.dart';
import 'package:flutter_hbb/dolphin/tech/api.dart';
import 'package:flutter_hbb/dolphin/tech/secret_box.dart';
import 'package:flutter_hbb/dolphin/tech/services.dart';
import 'package:flutter_hbb/dolphin/tech/state.dart';
import 'package:flutter_hbb/dolphin/tech_ui/platform.dart';
import 'package:flutter_hbb/dolphin/tech_ui/shell_model.dart';

import '../tech/fake_portal.dart';

export '../tech/fake_portal.dart';

/// Shared fakes for the native technician screens' tests and previews: a scripted portal with realistic Persian
/// sample data, a launcher that records what it opened, and a platform without the native bridge.

class RecLauncher implements SessionLauncher {
  final opened = <(String, String?)>[];
  List<String> recent;
  bool fail;
  RecLauncher({this.recent = const [], this.fail = false});
  @override
  Future<void> open(String rustdeskId, {String? password}) async {
    if (fail) throw StateError('no window');
    opened.add((rustdeskId, password));
  }

  @override
  Future<String> myId() async => '287654321';
  @override
  Future<List<String>> recentIds({int limit = 5}) async => recent.take(limit).toList();
}

class FakePlatform implements TechPlatform {
  final toasts = <String>[];
  final urls = <String>[];
  final copies = <String>[];
  final focused = <String>[];
  bool inFront;
  ThemeMode mode;
  FakePlatform({this.inFront = true, this.mode = ThemeMode.light, bool? server = true}) {
    serverOnline.value = server;
  }

  @override
  final ValueNotifier<bool?> serverOnline = ValueNotifier(true);
  @override
  final TechSessions sessions = TechSessions();
  @override
  final MemorySettingsStore settings = MemorySettingsStore();

  @override
  Future<String> myId() async => '287654321';
  @override
  ThemeMode get themeMode => mode;
  @override
  Future<void> setThemeMode(ThemeMode m) async => mode = m;
  @override
  Future<void> openUrl(String url) async => urls.add(url);
  @override
  Future<void> copy(String text) async => copies.add(text);
  @override
  Future<bool> appInFront() async => inFront;
  @override
  Future<void> systemToast(String text) async => toasts.add(text);
  @override
  Future<Directory> downloadsDir() async => Directory.systemTemp;
  @override
  Future<void> openFolder(String path) async {}
  @override
  Future<bool> focusSession(String rustdeskId) async {
    focused.add(rustdeskId);
    return true;
  }

  @override
  String get version => '2.1.0';
}

class AnswerPrompts implements TechPrompts {
  bool takeover;
  final takeoverAsked = <String>[];
  final endAsked = <(PcRef, OpenCall)>[];
  bool? demoAnswer;
  final demoAsked = <String>[];
  AnswerPrompts({this.takeover = true, this.demoAnswer = false});
  @override
  Future<bool?> confirmDemo(PcRef pc) async {
    demoAsked.add(pc.name ?? pc.rustdeskId);
    return demoAnswer;
  }

  @override
  Future<bool> confirmTakeover(String holderName, PcRef pc) async {
    takeoverAsked.add(holderName);
    return takeover;
  }

  @override
  Future<void> endOfCall(PcRef pc, OpenCall call) async => endAsked.add((pc, call));
}

// -- sample data (realistic, Persian; the support phone is 021-44280505 only)

const orgGardesh = {'id': '11111111-1111-4111-8111-111111111111', 'name': 'نمایندگی گردش‌کار', 'color': '#1d4ed8'};
const orgPars = {'id': '22222222-2222-4222-8222-222222222222', 'name': 'پارس‌کار', 'color': '#0f766e'};
const orgNik = {'id': '33333333-3333-4333-8333-333333333333', 'name': 'نیک‌خودرو', 'color': '#c2410c'};
const orgTabriz = {'id': '44444444-4444-4444-8444-444444444444', 'name': 'بازرگانی تبریز', 'color': '#7c3aed'};

final _now = DateTime.now().toUtc();
String _ago(Duration d) => _now.subtract(d).toIso8601String();

Map<String, dynamic> pc(String id, String rid, String? host, String? label, Map<String, String> org,
        {bool online = true,
        bool favorite = false,
        List<String> tags = const [],
        Duration seen = const Duration(minutes: 10),
        Map<String, dynamic>? session,
        bool shareStopped = false}) =>
    {
      'id': id,
      'rustdeskId': rid,
      'hostname': host,
      'label': label,
      'organization': org,
      'tags': tags,
      'online': online,
      'lastSeenAt': _ago(seen),
      'favorite': favorite,
      'shareStopped': shareStopped,
      'os': 'Windows 11 Pro',
      'dolphinVersion': '2.1.0',
      'session': session,
    };

final samplePcs = [
  pc('pc-1', '194052361', 'PC-RECEPTION', 'پذیرش', orgGardesh, favorite: true, tags: ['پذیرش']),
  pc('pc-2', '305118742', 'ACC-02', 'حسابداری', orgPars,
      tags: ['حسابداری'], session: {'staffName': 'مریم احمدی', 'mine': false, 'requestId': 'r-x'}),
  pc('pc-3', '412700913', 'WAREHOUSE', null, orgNik, tags: ['انبار', 'سرور'], seen: const Duration(days: 1)),
  pc('pc-4', '520334108', 'SALES-PC', null, orgGardesh,
      online: false, favorite: true, seen: const Duration(days: 3), shareStopped: true),
  pc('pc-5', '631209874', 'MANAGER', 'آقای محمدی', orgPars, tags: ['مدیر'], seen: const Duration(days: 8)),
  pc('pc-6', '742118305', 'TBZ-FRONT', 'صندوق', orgTabriz, tags: ['صندوق'], seen: const Duration(hours: 2)),
  pc('pc-7', '853004117', 'TBZ-OFFICE', null, orgTabriz, online: false, seen: const Duration(days: 12)),
  pc('pc-8', '964551230', 'GARDESH-03', 'انبار مرکزی', orgGardesh, tags: ['انبار'], seen: const Duration(hours: 5)),
];

Map<String, dynamic> computersPage([List<Map<String, dynamic>>? rows]) {
  final r = rows ?? samplePcs;
  return {
    'rows': r,
    'next': null,
    'counts': {
      'matching': r.length,
      'online': r.where((p) => p['online'] == true).length,
      'favorite': r.where((p) => p['favorite'] == true).length,
    },
  };
}

const reasons = [
  {'id': 'install', 'name': 'نصب برنامه'},
  {'id': 'error', 'name': 'رفع خطا'},
  {'id': 'training', 'name': 'آموزش'},
  {'id': 'update', 'name': 'به‌روزرسانی'},
];

Map<String, dynamic> configJson({Object? theme}) => {
      'switches': <String, dynamic>{},
      'theme': theme,
      'latest': {
        'version': '2.2.0',
        'technician': {'url': '/api/app/v1/download/technician', 'sha256': 'a' * 64, 'size': 12},
      },
      'callReasons': reasons,
    };

Map<String, dynamic> request(String id, int number, String subject, Map<String, String> org,
        {String openedBy = 'customer',
        Duration waited = const Duration(minutes: 5),
        String? deviceId,
        String? rid,
        String? pcName,
        bool urgent = false,
        bool mine = false,
        String? contact,
        String? phone}) =>
    {
      'id': id,
      'number': number,
      'subject': subject,
      'status': 'open',
      'priority': urgent ? 'urgent' : 'normal',
      'openedBy': openedBy,
      'kind': 'support',
      'organization': org,
      'customerName': null,
      'contactName': contact,
      'contactPhone': phone,
      'deviceId': deviceId,
      'pcName': pcName,
      'rustdeskId': rid,
      'assigneeName': mine ? 'علی رضایی' : null,
      'mine': mine,
      'createdAt': _ago(waited),
      'resolvedAt': null,
    };

final sampleRequests = [
  request('q-1', 1042, 'برنامه باز نمی‌شود', orgPars,
      openedBy: 'app', waited: const Duration(minutes: 12), deviceId: 'pc-2', rid: '305118742', pcName: 'ACC-02',
      contact: 'خانم کریمی', phone: '021-88776655'),
  request('q-2', 1043, 'چاپگر فاکتور چاپ نمی‌کند', orgGardesh, waited: const Duration(minutes: 4), urgent: true),
  request('q-3', 1044, 'نصب نسخه‌ی تازه', orgNik, waited: const Duration(hours: 2)),
];

Map<String, dynamic> requestsPage(List<Map<String, dynamic>> rows, {int queue = 3, int mine = 1}) =>
    {'rows': rows, 'next': null, 'counts': {'queue': queue, 'mine': mine}};

Map<String, dynamic> callJson2({String consent = 'click', String? code, bool waitingForCode = false, bool live = false}) => {
      'requestId': 'call-1',
      'consentMode': consent,
      'sessionLive': live,
      'connectedSince': live ? _ago(const Duration(minutes: 7)) : null,
      'hadConnection': live,
      'reasonId': 'install',
      'contactName': 'آقای رضوی',
      'contactPhone': '0912 345 6789',
      'code': code,
      'waitingForCode': waitingForCode,
    };

Map<String, dynamic> detailJson(Map<String, dynamic> pcJson, {Map<String, dynamic>? call}) => {
      'computer': {...pcJson, 'customerName': 'گردش‌کار مرکزی', 'ownerName': 'خانم صالحی', 'consentMode': 'click', 'clientVersion': '2.1.0'},
      'call': call,
      'history': [
        {
          'kind': 'request',
          'at': _ago(const Duration(days: 8)),
          'id': 'h1',
          'number': 998,
          'subject': 'تماس تلفنی',
          'openedBy': 'staff',
          'status': 'resolved',
          'assigneeName': 'مدیر',
          'resolvedAt': _ago(const Duration(days: 8)),
          'resolutionNote': null,
          'pcName': 'PC-RECEPTION',
        },
        {
          'kind': 'connection',
          'at': _ago(const Duration(days: 1, minutes: 20)),
          'id': 71,
          'pcName': 'PC-RECEPTION',
          'technician': 'علی رضایی',
          'verified': true,
          'connType': 0,
          'closedAt': _ago(const Duration(days: 1, minutes: 8)),
          'closeReason': null,
          'files': 1,
        },
      ],
      'sentToday': [
        {
          'id': 'sent-1',
          'kind': 'screenshot',
          'size': 284000,
          'note': 'این پیام خطا می‌آید',
          'createdAt': _ago(const Duration(minutes: 40)),
          'url': '/api/app/v1/reports/sent-1',
        },
      ],
      'tags': pcJson['tags'],
    };

Map<String, dynamic> note(String id, String kind, String title, String body,
        {String? deviceId, String? requestId, Duration ago = const Duration(minutes: 2)}) =>
    {'id': id, 'kind': kind, 'title': title, 'body': body, 'deviceId': deviceId, 'requestId': requestId, 'at': _ago(ago)};

/// A portal that answers everything the shell reads at start with the sample data.
FakePortal samplePortal() {
  final p = FakePortal();
  p.on('POST /login', (_) => {
        'token': 'tok-secret-123',
        'expiresAt': DateTime.now().add(const Duration(hours: 8)).toUtc().toIso8601String(),
        'staff': {'id': 's1', 'name': 'علی رضایی', 'role': 'technician', 'rustdeskId': '287654321'},
      });
  p.on('POST /logout', (_) => {'ok': true});
  p.on('GET /computers', (_) => computersPage());
  p.on('GET /config', (_) => configJson());
  p.on('GET /notifications', (_) => <Object>[]);
  p.on('GET /requests', (req) {
    final scope = req.url.queryParameters['scope'];
    if (scope == 'mine') {
      return requestsPage([request('m-1', 1039, 'آموزش گزارش فروش', orgGardesh, mine: true, deviceId: 'pc-1', rid: '194052361', pcName: 'PC-RECEPTION')]);
    }
    if (scope == 'closed') return requestsPage([]);
    return requestsPage(sampleRequests);
  });
  for (final row in samplePcs) {
    p.on('GET /computers/${row['id']}', (_) => detailJson(row));
  }
  p.on('POST /calls', (_) => callJson);
  p.on('POST /demo', (_) => callJson);
  p.on('GET /snippets', (_) => {
        'rows': [
          {'id': 'sn1', 'title': 'شماره‌ی پشتیبانی', 'body': 'پشتیبانی دلفین: ۰۲۱-۴۴۲۸۰۵۰۵'},
          {'id': 'sn2', 'title': 'مسیر پشتیبان‌گیری', 'body': r'D:\Backup\Dolphin'},
        ]
      });
  p.on('GET /organizations', (_) => {
        'rows': [
          {...orgGardesh, 'dealerCode': '1201', 'consentMode': 'click', 'active': true, 'city': 'تهران', 'phones': '021-88001122'},
          {...orgPars, 'dealerCode': '1305', 'consentMode': 'code', 'active': true, 'city': 'اصفهان', 'phones': null},
        ],
        'next': null,
      });
  return p;
}

TechServices servicesOn(FakePortal portal, {SessionLauncher? launcher, Prefs? prefs, DemoStarter? demo}) => TechServices(
      api: ApiClient(portalUrl: 'http://portal.test', client: portal.client, probe: FixedProbe()),
      sessionBox: MemoryBox(),
      offlineBox: MemoryBox(),
      launcher: launcher ?? RecLauncher(),
      prefs: prefs ?? MemoryPrefs(),
      demoStarter: demo,
    );

/// Signs in through the fake portal (the session store's real path).
Future<void> signIn(TechServices s) async {
  await s.session.signIn('ali.rezaei', 'a-long-password-1');
}

/// Lets the fake portal's answers and the controllers' notifications run.
Future<void> drain([int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Stops every timer the shell's model started (polling, notices), so a widget test ends clean.
Future<void> shutDown(TechShellModel m) async {
  m.services.poller.stop();
  m.dispose();
  m.services.dispose();
}
