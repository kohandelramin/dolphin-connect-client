import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../brand.dart';
import '../panel_bridge.dart' show panelIdPattern;
import '../theme_tokens.dart';
import '../tech/actions.dart';
import '../tech/api.dart';
import '../tech/services.dart';
import '../tech/state.dart';
import 'platform.dart';
import 'sections_state.dart';
import 'settings_model.dart';

/// Plan 19: the native technician window's own state (T1–T7), over the data layer's controllers (tech/state.dart).
/// No widgets: the shell (shell.dart) draws it; tests drive it with the data layer's fakes. Every connection goes
/// through [TechActions], which opens the call on the portal first (authorization and audit as the web's «اتصال»).

enum TechSection { computers, requests, myCalls, organizations, history, snippets, settings }

String techSectionTitle(TechSection s) => switch (s) {
      TechSection.computers => 'رایانه‌ها',
      TechSection.requests => 'درخواست‌ها',
      TechSection.myCalls => 'تماس‌های من',
      TechSection.organizations => 'سازمان‌ها',
      TechSection.history => 'تاریخچه',
      TechSection.snippets => 'متن‌های آماده',
      TechSection.settings => 'تنظیمات',
    };

const kMsgDemoNotOpened = 'اجازه‌ی دمو گرفته شد ولی پنجره‌ی دمو باز نشد؛ دوباره «ارائه دمو» را بزنید.';
const kMsgIdNotInList = 'این شناسه در فهرست رایانه‌های دلفین نیست؛ شناسه را دوباره بپرسید.';
const kMsgIdFormat = 'شناسه‌ی رایانه ۹ تا ۱۰ رقم است.';
const kMsgOfflineOpened = 'پورتال در دسترس نیست؛ پنجره‌ی اتصال بدون تماس تازه باز شد. اگر اجازه‌ی قبلی تمام شده باشد، سرور اجازه نمی‌دهد.';
const kMsgTakeoverQuestion = 'این رایانه در جلسه با «{name}» است. جلسه را از او بگیرید؟';

/// The PC's page on the portal, where «روشن کن» (Wake-on-LAN through another PC of the organization) lives.
String wakePageUrl(String deviceId) => '${DolphinBrand.portalUrl}/staff/computers/${Uri.encodeComponent(deviceId)}';

/// The ID as the technician typed it, or null when it is not one (spaces and Persian digits allowed).
String? cleanTypedId(String typed) {
  const fa = '۰۱۲۳۴۵۶۷۸۹', ar = '٠١٢٣٤٥٦٧٨٩';
  final latin = typed.replaceAllMapped(RegExp('[۰-۹٠-٩]'), (m) {
    final i = fa.indexOf(m[0]!);
    return '${i >= 0 ? i : ar.indexOf(m[0]!)}';
  }).replaceAll(RegExp(r'[\s-]'), '');
  return panelIdPattern.hasMatch(latin) ? latin : null;
}

/// What the shell asks the person (dialogs need a context; tests answer directly).
abstract class TechPrompts {
  /// Another technician holds the PC: take the session over?
  Future<bool> confirmTakeover(String holderName, PcRef pc);

  /// RO-8: a session ended on a PC with this technician's open call: the end-of-call step.
  Future<void> endOfCall(PcRef pc, OpenCall call);
}

class TechShellModel extends ChangeNotifier {
  final TechServices services;
  final TechPlatform platform;
  TechPrompts? prompts;
  final DateTime Function() now;

  late final DashboardController dashboard = services.dashboard();
  late final RequestsController requests = services.requests();
  late final RequestsController myCalls = RequestsController(services.repo, services.connection, scope: RequestScope.mine);

  /// Made at once (not lazily): it must hear the first poll's items.
  late final NotificationsController notifications;
  late final ConfigController config = services.config();
  late final OrganizationsController organizations = OrganizationsController(services.repo, services.connection);
  late final HistoryController history = HistoryController(services.repo, services.connection);
  late final SnippetsController snippets = SnippetsController(services.repo, services.connection);
  late final TechSettingsModel settings = TechSettingsModel(platform.settings);

  TechShellModel(this.services, this.platform, {this.prompts, DateTime Function()? now}) : now = now ?? DateTime.now {
    notifications = services.notifications();
  }

  TechSection _section = TechSection.computers;
  String _myId = '';
  String? _notice;
  bool _noticeOk = false;
  Timer? _noticeTimer;
  String? _cardId;
  PcCardController? _card;
  bool _bellOpen = false;
  int _bellUnread = 0;
  AppNotification? _toast;
  Timer? _toastTimer;
  bool _busy = false;
  bool _started = false;
  bool _disposed = false;
  StreamSubscription<AppNotification>? _noteSub;
  List<OpenSession> _lastSessions = const [];

  /// PCs this window opened a session to (their portal IDs), for RO-8 when the session window closes.
  final Map<String, PcRef> _launched = {};

  TechSection get section => _section;
  String get myId => _myId;
  String? get notice => _notice;
  bool get noticeOk => _noticeOk;
  String? get cardId => _cardId;
  PcCardController? get card => _card;
  bool get bellOpen => _bellOpen;

  /// How many items were unread when the bell opened (the list marks them ●).
  int get bellUnread => _bellUnread;
  AppNotification? get toast => _toast;

  /// A connect or demo is running (the header's buttons are disabled).
  bool get busy => _busy;
  bool get offline => services.connection.offline;
  StaffInfo? get staff => services.session.staff;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// After a sign-in (or a start with a stored one): register this app's ID, start polling, read the config (theme),
  /// the list, the queue and the recent strip.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _noteSub = services.poller.items.listen(_onNotification);
    platform.sessions.addListener(_onSessions);
    try {
      _myId = await platform.myId();
    } catch (_) {}
    _changed();
    final idProblem = await services.afterSignIn();
    if (idProblem != null) say(idProblem);
    unawaited(config.load().then((c) {
      if (c != null) applyThemeOverrides(c.themeJson);
    }));
    await dashboard.load();
    unawaited(dashboard.loadRecent());
    unawaited(requests.load());
    unawaited(myCalls.load());
  }

  /// «خروج»: the portal session ends, the token, offline list and memory go; the built-in theme comes back.
  Future<void> signOut() async {
    _stop();
    await services.signOut();
    applyThemeOverrides(null);
    _changed();
  }

  /// The sign-in expired (the session store says so): forget the screens' state; the sign-in form shows.
  void expired() {
    _stop();
    services.poller.reset();
    services.repo.reset();
    _changed();
  }

  void _stop() {
    _started = false;
    _noteSub?.cancel();
    _noteSub = null;
    platform.sessions.removeListener(_onSessions);
    closeCard();
    dashboard.reset();
    notifications.clear();
    _toast = null;
    _bellOpen = false;
    _launched.clear();
    _section = TechSection.computers;
  }

  void go(TechSection s) {
    if (_section == s) return;
    _section = s;
    _bellOpen = false;
    switch (s) {
      case TechSection.requests:
        unawaited(requests.load());
      case TechSection.myCalls:
        unawaited(myCalls.load());
      case TechSection.organizations:
        if (organizations.rows.isEmpty) unawaited(organizations.load());
      case TechSection.history:
        if (organizations.rows.isEmpty) unawaited(organizations.load());
      case TechSection.snippets:
        unawaited(snippets.load());
      default:
        break;
    }
    _changed();
  }

  /// A short line under the header (green for done, amber for a problem); gone after a while.
  void say(String text, {bool ok = false}) {
    _notice = text;
    _noticeOk = ok;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 10), clearNotice);
    _changed();
  }

  void clearNotice() {
    _noticeTimer?.cancel();
    _notice = null;
    _changed();
  }

  // -- the card (T2)

  void openCard(String deviceId) {
    if (_cardId == deviceId && _card != null) return;
    _card?.dispose();
    _cardId = deviceId;
    _card = services.card(deviceId)..load();
    _changed();
  }

  void closeCard() {
    _card?.dispose();
    _card = null;
    _cardId = null;
    _changed();
  }

  // -- connecting

  /// «اتصال» or «ارائه دمو» for a PC of the list, a request, the recent strip or the card's own buttons.
  Future<ConnectOutcome?> connect(PcRef pc, {bool demo = false}) async {
    if (_busy) return null;
    if (offline && !demo) return _connectOffline(pc.rustdeskId, name: pc.name);
    _busy = true;
    _changed();
    try {
      var o = demo ? await services.actions.demo(pc) : await services.actions.connect(pc);
      if (o is HeldByOther) {
        final yes = await (prompts?.confirmTakeover(o.holderName, pc) ?? Future.value(false));
        if (!yes) return o;
        o = demo ? await services.actions.demo(pc, takeover: true) : await services.actions.connect(pc, takeover: true);
      }
      _report(o, pc, demo: demo);
      return o;
    } finally {
      _busy = false;
      _changed();
    }
  }

  void _report(ConnectOutcome o, PcRef pc, {required bool demo}) {
    final name = pc.name ?? pc.rustdeskId;
    switch (o) {
      case Connected():
        services.connection.reachable();
        if (!demo) _launched[pc.rustdeskId] = pc;
        say(demo ? 'ارائه‌ی دمو به «$name» شروع شد.' : 'پنجره‌ی اتصال به «$name» باز شد.', ok: true);
      case WaitingForCode():
        services.connection.reachable();
        _launched[pc.rustdeskId] = pc;
        openCard(pc.deviceId);
        say('این سازمان با کد کار می‌کند؛ در انتظار کد مشتری… کد که برسد، خودکار وصل می‌شود.', ok: true);
      case HeldByOther(:final holderName):
        say(kMsgTakeoverQuestion.replaceFirst('{name}', holderName));
      case Refused(:final error):
        services.connection.reachable();
        say(error.message);
      case PortalAway(:final error):
        services.connection.unreachable(error);
        say(error.message);
        unawaited(dashboard.load());
      case LaunchFailed():
        services.connection.reachable();
        say(demo ? kMsgDemoNotOpened : kMsgLaunchFailed);
    }
  }

  /// TD-2: the portal is away, the window opens without a new call (the engine decides whether it lets it in).
  Future<ConnectOutcome?> _connectOffline(String rustdeskId, {String? name}) async {
    final ok = await services.actions.connectOffline(rustdeskId);
    say(ok ? kMsgOfflineOpened : kMsgLaunchFailed, ok: ok);
    return null;
  }

  /// The header's ID field: finds the PC on the portal (the same authorization as any «اتصال»), or, with the portal
  /// away, opens the window without a call (T5: «اتصال با شناسه کار می‌کند»).
  Future<void> connectTyped(String typed, {bool demo = false}) async {
    final id = cleanTypedId(typed);
    if (id == null) {
      say(kMsgIdFormat);
      return;
    }
    if (offline) {
      if (demo) {
        say('برای «ارائه دمو» پورتال باید در دسترس باشد.');
        return;
      }
      await _connectOffline(id);
      return;
    }
    Computer? pc;
    try {
      final page = await services.connection.track(() => services.repo.computers(ComputerQuery(q: id)));
      pc = page.rows.where((c) => c.rustdeskId == id).firstOrNull;
    } on PortalUnreachable catch (e) {
      say(e.message);
      if (!demo) await _connectOffline(id);
      return;
    } catch (e) {
      say(errorText(e));
      return;
    }
    if (pc == null) {
      say(kMsgIdNotInList);
      return;
    }
    await connect(PcRef.of(pc), demo: demo);
  }

  /// «برداشتن و تماس»: the request becomes this technician's, then «اتصال» to its PC (when it has one).
  Future<void> takeAndCall(RequestRow r) async {
    final ok = await requests.take(r.id);
    unawaited(myCalls.load());
    if (!ok) {
      if (requests.error != null) say(requests.error!);
      return;
    }
    final device = r.deviceId, rid = r.rustdeskId;
    if (device == null || rid == null) {
      say('درخواست برداشته شد. این درخواست رایانه ندارد؛ با مشتری تماس بگیرید.', ok: true);
      return;
    }
    await connect(PcRef(device, rid, r.pcName));
  }

  Future<void> wake(String deviceId) => platform.openUrl(wakePageUrl(deviceId));

  /// A session this window opened another way (the card's code-mode connect): remembered for RO-8.
  void noteLaunched(PcRef pc) => _launched[pc.rustdeskId] = pc;

  /// RO-8 «پایان تماس» with the tapped reason and note. Null when it worked, else the Persian reason.
  Future<String?> endCall(String requestId, {String? reasonId, String? note}) async {
    try {
      await services.connection.track(() => services.actions.endCall(requestId, reasonId: reasonId, note: note));
      say('تماس بسته شد.', ok: true);
      unawaited(myCalls.load());
      _card?.load();
      return null;
    } catch (e) {
      return errorText(e);
    }
  }

  /// «دریافت» in «فرستاده‌ی مشتری»: the file with the staff token into the downloads folder, then the folder opens.
  Future<void> downloadSent(SentItem item) async {
    try {
      final dir = await platform.downloadsDir();
      final ext = item.kind == 'screenshot' ? 'png' : (item.kind == 'report' ? 'zip' : 'bin');
      final safeId = item.id.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '');
      final file = File('${dir.path}${Platform.pathSeparator}dolphin-${item.kind == 'screenshot' ? 'screenshot' : 'report'}-$safeId.$ext');
      await services.connection.track(() => services.api.download(item.url, file, expectedSize: item.size));
      say('فایل در پوشه‌ی دریافت ذخیره شد.', ok: true);
      unawaited(platform.openFolder(dir.path));
    } catch (e) {
      say(errorText(e));
    }
  }

  Future<void> copyId(String rustdeskId) async {
    await platform.copy(rustdeskId);
    say('شناسه کپی شد.', ok: true);
  }

  // -- notifications (T4)

  void toggleBell() {
    _bellOpen = !_bellOpen;
    if (_bellOpen) {
      _bellUnread = notifications.unread;
      notifications.markAllRead();
    }
    _changed();
  }

  void closeBell() {
    if (!_bellOpen) return;
    _bellOpen = false;
    _changed();
  }

  /// Opens what a notification is about: the PC's card, else the queue.
  void openNotification(AppNotification n) {
    _bellOpen = false;
    dismissToast();
    final d = n.deviceId;
    if (d != null) {
      go(TechSection.computers);
      openCard(d);
    } else {
      go(TechSection.requests);
    }
    _changed();
  }

  void dismissToast() {
    _toastTimer?.cancel();
    if (_toast == null) return;
    _toast = null;
    _changed();
  }

  bool get toastsOn => services.prefs.get(kTechToastsPref) != 'N';
  Future<void> setToasts(bool on) async {
    await services.prefs.set(kTechToastsPref, on ? null : 'N');
    _changed();
  }

  Future<void> _onNotification(AppNotification n) async {
    if (n.kind != NotificationKind.authExpiring) {
      unawaited(requests.load());
    }
    // The first answer is the backlog of the last day: listed under the bell, never a toast (it would ring for old news).
    if (services.poller.answeredPolls <= 1) return;
    _toast = n;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 12), dismissToast);
    _changed();
    if (!toastsOn) return;
    bool front = true;
    try {
      front = await platform.appInFront();
    } catch (_) {}
    if (!front) {
      final line = n.body.trim().isEmpty ? n.title : '${n.title} — ${n.body}';
      unawaited(platform.systemToast(line));
    }
  }

  // -- open sessions (TD-9) and RO-8

  void _onSessions() {
    final now = platform.sessions.open;
    final gone = TechSessions.ended(_lastSessions, now);
    _lastSessions = now;
    for (final id in gone) {
      final pc = _launched.remove(id);
      if (pc != null) unawaited(_afterSession(pc));
    }
    _changed();
  }

  /// RO-8: the session window closed; when this technician still has an open call on that PC, offer the end step.
  Future<void> _afterSession(PcRef pc) async {
    try {
      final d = await services.connection.track(() => services.repo.computer(pc.deviceId));
      final call = d.call;
      if (call == null || call.sessionLive) return;
      await prompts?.endOfCall(PcRef(pc.deviceId, pc.rustdeskId, d.computer.displayName), call);
    } catch (_) {
      // No answer: the call stays open on the portal; the card still offers «پایان تماس».
    }
  }

  /// The name the bottom bar shows for an open session: the PC's name when the list knows it.
  String sessionName(String rustdeskId) {
    final known = _launched[rustdeskId]?.name ??
        dashboard.items.where((c) => c.rustdeskId == rustdeskId).firstOrNull?.displayName;
    return known ?? rustdeskId;
  }

  @override
  void dispose() {
    _disposed = true;
    _noteSub?.cancel();
    platform.sessions.removeListener(_onSessions);
    _noticeTimer?.cancel();
    _toastTimer?.cancel();
    _card?.dispose();
    dashboard.dispose();
    requests.dispose();
    myCalls.dispose();
    notifications.dispose();
    config.dispose();
    organizations.dispose();
    history.dispose();
    snippets.dispose();
    settings.dispose();
    super.dispose();
  }
}
