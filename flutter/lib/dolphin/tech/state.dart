import 'dart:async';

import 'package:flutter/foundation.dart';

import 'actions.dart';
import 'api.dart';
import 'notifications.dart';
import 'repository.dart';

/// Plan 19: the controllers the native technician screens bind to (T1–T7). Plain ChangeNotifier / ValueNotifier, no
/// state-management package. No widgets here: each controller is unit-tested with a fake API.

/// The Persian text for any failure a controller catches.
String errorText(Object e) => switch (e) {
      ApiError(:final message) => message,
      PortalUnreachable(:final message) => message,
      _ => kMsgServer,
    };

/// Small UI choices kept between starts (tiles or list). The app's implementation is LocalOptionPrefs (launcher.dart).
abstract class Prefs {
  String? get(String key);
  Future<void> set(String key, String? value);
}

class MemoryPrefs implements Prefs {
  final Map<String, String> values;
  MemoryPrefs([Map<String, String>? values]) : values = values ?? {};
  @override
  String? get(String key) => values[key];
  @override
  Future<void> set(String key, String? value) async {
    if (value == null || value.isEmpty) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Connection status (TD-1)

class PortalStatus {
  final bool reachable;

  /// Why the portal is away; null while reachable.
  final OfflineReason? reason;

  /// Since when it is away.
  final DateTime? since;
  const PortalStatus.online()
      : reachable = true,
        reason = null,
        since = null;
  const PortalStatus.offline(OfflineReason this.reason, DateTime this.since) : reachable = false;

  /// «پورتال دلفین در دسترس نیست» with the reason, or null while reachable.
  String? get message => reason == null ? null : offlineMessage(reason!);
}

/// Whether the portal answers. Every controller reports to it; the header and the offline screen listen.
class ConnectionController extends ValueNotifier<PortalStatus> {
  final DateTime Function() _now;
  ConnectionController({DateTime Function()? now})
      : _now = now ?? DateTime.now,
        super(const PortalStatus.online());

  bool get offline => !value.reachable;

  void reachable() {
    if (!value.reachable) value = const PortalStatus.online();
  }

  void unreachable(PortalUnreachable e) {
    final since = value.since ?? _now();
    if (value.reason != e.reason || value.reachable) value = PortalStatus.offline(e.reason, since);
  }

  /// Runs [call] and reports the result: any HTTP answer (even an error) means the portal is reachable.
  Future<T> track<T>(Future<T> Function() call) async {
    try {
      final r = await call();
      reachable();
      return r;
    } on PortalUnreachable catch (e) {
      unreachable(e);
      rethrow;
    } on ApiError {
      reachable();
      rethrow;
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Dashboard (T1): the PC list

enum PcViewMode { tiles, list }

/// The local option that keeps tiles or list.
const kTechViewModeOption = 'dolphin-tech-view';

/// While the portal is away the list is retried this often (TD-1).
const kOfflineRetry = Duration(seconds: 15);

class DashboardController extends ChangeNotifier {
  final TechRepository repo;
  final ConnectionController connection;
  final Prefs prefs;
  final TechActions? actions;
  final Debouncer _debounce;
  final Duration retryEvery;

  DashboardController(this.repo, this.connection, this.prefs,
      {this.actions, Duration debounce = const Duration(milliseconds: 350), this.retryEvery = kOfflineRetry})
      : _debounce = Debouncer(debounce),
        _viewMode = prefs.get(kTechViewModeOption) == PcViewMode.list.name ? PcViewMode.list : PcViewMode.tiles;

  ComputerQuery _query = const ComputerQuery();
  PcViewMode _viewMode;
  List<Computer> _items = const [];
  ComputerCounts _counts = ComputerCounts.zero;
  String? _next;
  bool _loading = false;
  bool _loadingMore = false;
  bool _offline = false;
  DateTime? _lastUpdated;
  String? _error;
  List<RecentPc> _recent = const [];
  Timer? _retry;
  int _generation = 0;
  bool _disposed = false;

  ComputerQuery get query => _query;
  PcViewMode get viewMode => _viewMode;
  List<Computer> get items => _items;
  ComputerCounts get counts => _counts;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => !_offline && _next != null;

  /// Showing the cached list read-only (TD-2).
  bool get offline => _offline;

  /// When the shown offline list was saved; null online.
  DateTime? get lastUpdated => _lastUpdated;

  /// The last failure in Persian (portal away without a cache, a refusal), null otherwise.
  String? get error => _error;

  /// The recent strip (TD-5).
  List<RecentPc> get recent => _recent;

  /// Every tag on the shown PCs, for the tag filter.
  List<String> get tags {
    final s = <String>{};
    for (final c in _items) {
      s.addAll(c.tags);
    }
    return s.toList()..sort();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// The first page for the current query (or the cached list when the portal is away).
  Future<void> load() async {
    _debounce.cancel();
    final gen = ++_generation;
    _loading = true;
    _changed();
    try {
      final page = await connection.track(() => repo.computers(_query));
      if (gen != _generation || _disposed) return;
      _items = page.rows;
      _counts = page.counts;
      _next = page.next;
      _offline = false;
      _lastUpdated = null;
      _error = null;
      _retry?.cancel();
      _retry = null;
    } on PortalUnreachable catch (e) {
      if (gen != _generation || _disposed) return;
      await _showOffline(e, gen);
    } catch (e) {
      if (gen != _generation || _disposed) return;
      _error = errorText(e);
    } finally {
      if (gen == _generation) {
        _loading = false;
        _changed();
      }
    }
  }

  Future<void> _showOffline(PortalUnreachable e, int gen) async {
    final snap = await repo.offlineComputers(_query);
    if (gen != _generation || _disposed) return;
    _offline = true;
    _next = null;
    _error = snap == null ? e.message : null;
    _lastUpdated = snap?.lastUpdated;
    _items = snap == null ? const [] : snap.items.map((c) => c.toComputer()).toList(growable: false);
    _counts = ComputerCounts(_items.length, 0, _items.where((c) => c.favorite).length);
    _retry ??= Timer.periodic(retryEvery, (_) {
      if (!_loading) load();
    });
  }

  /// The next page (online only).
  Future<void> loadMore() async {
    final cursor = _next;
    if (cursor == null || _loadingMore || _loading || _offline) return;
    final gen = _generation;
    _loadingMore = true;
    _changed();
    try {
      final page = await connection.track(() => repo.computers(_query, cursor: cursor));
      if (gen != _generation || _disposed) return;
      final known = _items.map((c) => c.id).toSet();
      _items = [..._items, ...page.rows.where((c) => !known.contains(c.id))];
      _counts = page.counts;
      _next = page.next;
    } catch (e) {
      if (gen == _generation) _error = errorText(e);
    } finally {
      _loadingMore = false;
      _changed();
    }
  }

  void _requery(ComputerQuery q, {bool debounced = false}) {
    if (q == _query) return;
    _query = q;
    _changed();
    if (debounced) {
      _debounce(load);
    } else {
      load();
    }
  }

  /// The search field: asks the portal once typing pauses.
  void search(String text) => _requery(_query.copyWith(q: text), debounced: true);

  void setView(PcView view) => _requery(_query.copyWith(view: view));
  void setTag(String? tag) => _requery(_query.copyWith(tag: () => tag));
  void setOrganization(String? orgId) => _requery(_query.copyWith(orgId: () => orgId));
  void setSort(PcSort sort, {bool? ascending}) => _requery(_query.copyWith(sort: sort, ascending: () => ascending));

  /// Tiles or list, kept between starts.
  Future<void> setViewMode(PcViewMode mode) async {
    if (mode == _viewMode) return;
    _viewMode = mode;
    _changed();
    await prefs.set(kTechViewModeOption, mode.name);
  }

  /// The star, shown at once and put back if the portal refuses. Read-only while offline.
  Future<bool> toggleFavorite(Computer pc) async {
    if (_offline || pc.fromCache) {
      _error = 'تا وقتی پورتال در دسترس نیست، نشان‌گذاری ممکن نیست.';
      _changed();
      return false;
    }
    final want = !pc.favorite;
    _replace(pc.id, (c) => c.copyWith(favorite: want));
    try {
      final saved = await connection.track(() => repo.setFavorite(pc.id, want));
      _replace(pc.id, (c) => c.copyWith(favorite: saved));
      if (_query.view == PcView.favorite && !saved) {
        _items = _items.where((c) => c.id != pc.id).toList(growable: false);
      }
      _counts = ComputerCounts(_counts.matching, _counts.online, _counts.favorite + (saved == pc.favorite ? 0 : (saved ? 1 : -1)));
      _changed();
      return true;
    } catch (e) {
      _replace(pc.id, (c) => c.copyWith(favorite: pc.favorite));
      _error = errorText(e);
      _changed();
      return false;
    }
  }

  void _replace(String id, Computer Function(Computer) f) {
    _items = [for (final c in _items) c.id == id ? f(c) : c];
    _changed();
  }

  /// The recent strip from the app's own history, joined with the shown PCs (online or cached).
  Future<void> loadRecent() async {
    final a = actions;
    if (a == null) return;
    final known = <Computer>[..._items];
    if (_offline || _items.isEmpty) {
      final snap = await repo.offlineComputers();
      if (snap != null) known.addAll(snap.items.map((c) => c.toComputer()));
    }
    _recent = await a.recent(known);
    _changed();
  }

  void clearError() {
    _error = null;
    _changed();
  }

  /// Sign-out: back to an empty list with the default query.
  void reset() {
    _generation++;
    _debounce.cancel();
    _retry?.cancel();
    _retry = null;
    _query = const ComputerQuery();
    _items = const [];
    _counts = ComputerCounts.zero;
    _next = null;
    _offline = false;
    _lastUpdated = null;
    _error = null;
    _recent = const [];
    _loading = false;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce.cancel();
    _retry?.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------------------------------------------
// PC card (T2)

class PcCardController extends ChangeNotifier {
  final TechRepository repo;
  final TechActions actions;
  final ConnectionController connection;
  final String deviceId;
  PcCardController(this.repo, this.actions, this.connection, this.deviceId);

  ComputerDetail? _detail;
  bool _loading = false;
  bool _busy = false;
  String? _error;
  String? _notice;
  CallStart? _waiting;
  bool _disposed = false;

  ComputerDetail? get detail => _detail;
  OpenCall? get call => _detail?.call;
  bool get loading => _loading;

  /// An action is running (buttons disabled).
  bool get busy => _busy;
  String? get error => _error;

  /// A short success line («تماس بسته شد»).
  String? get notice => _notice;

  /// A code-mode call waiting for the customer's code (show the code field).
  CallStart? get waitingForCode => _waiting;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    _loading = true;
    _changed();
    try {
      _detail = await connection.track(() => repo.computer(deviceId));
      _error = null;
    } catch (e) {
      _error = errorText(e);
    } finally {
      _loading = false;
      _changed();
    }
  }

  PcRef? get _ref => _detail == null ? null : PcRef.of(_detail!.computer);

  Future<ConnectOutcome?> _run(Future<ConnectOutcome> Function(PcRef pc) f) async {
    final pc = _ref;
    if (pc == null || _busy) return null;
    _busy = true;
    _error = null;
    _notice = null;
    _changed();
    try {
      final o = await f(pc);
      switch (o) {
        case PortalAway(:final error):
          connection.unreachable(error);
          _error = error.message;
        case Refused(:final error):
          connection.reachable();
          _error = error.message;
        case LaunchFailed():
          connection.reachable();
          _error = kMsgLaunchFailed;
        case WaitingForCode(:final call):
          connection.reachable();
          _waiting = call;
        case Connected():
          connection.reachable();
          _waiting = null;
        case HeldByOther():
          connection.reachable();
      }
      if (o is! PortalAway && o is! HeldByOther) unawaited(load());
      return o;
    } finally {
      _busy = false;
      _changed();
    }
  }

  /// «اتصال». A [HeldByOther] result: ask, then call again with [takeover].
  Future<ConnectOutcome?> connect({bool takeover = false, String? password}) =>
      _run((pc) => actions.connect(pc, takeover: takeover, password: password));

  /// «ارائه دمو».
  Future<ConnectOutcome?> demo({bool takeover = false}) => _run((pc) => actions.demo(pc, takeover: takeover));

  /// The customer's code for a waiting code-mode call.
  Future<ConnectOutcome?> openWithCode(String typed) {
    final call = _waiting;
    if (call == null) return Future.value(null);
    return _run((pc) => actions.openWithCode(pc, call, typed));
  }

  Future<bool> _act(Future<void> Function(String requestId) f, String done) async {
    final requestId = call?.requestId;
    if (requestId == null || _busy) return false;
    _busy = true;
    _error = null;
    _notice = null;
    _changed();
    try {
      await connection.track(() => f(requestId));
      _notice = done;
      unawaited(load());
      return true;
    } catch (e) {
      _error = errorText(e);
      return false;
    } finally {
      _busy = false;
      _changed();
    }
  }

  /// RO-8: «پایان تماس» with the tapped reason and an optional note.
  Future<bool> endCall({String? reasonId, String? note}) =>
      _act((id) => actions.endCall(id, reasonId: reasonId, note: note), 'تماس بسته شد.');
  Future<bool> setReason(String? reasonId) => _act((id) => actions.setReason(id, reasonId), 'دلیل تماس ثبت شد.');
  Future<bool> addNote(String text) => _act((id) => actions.addNote(id, text), 'یادداشت ثبت شد.');
  Future<bool> sendMessage(String text) => _act((id) => actions.sendMessage(id, text), 'پیام برای مشتری فرستاده شد.');

  Future<void> toggleFavorite() async {
    final d = _detail;
    if (d == null || _busy) return;
    try {
      final saved = await connection.track(() => repo.setFavorite(d.computer.id, !d.computer.favorite));
      _detail = ComputerDetail(
        computer: d.computer.copyWith(favorite: saved),
        customerName: d.customerName,
        ownerName: d.ownerName,
        consentMode: d.consentMode,
        clientVersion: d.clientVersion,
        call: d.call,
        history: d.history,
        sentToday: d.sentToday,
        tags: d.tags,
      );
    } catch (e) {
      _error = errorText(e);
    }
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Requests (T4)

class RequestsController extends ChangeNotifier {
  final TechRepository repo;
  final ConnectionController connection;

  /// [scope]: the tab shown first (the queue; «تماس‌های من» starts on mine).
  RequestsController(this.repo, this.connection, {RequestScope scope = RequestScope.queue}) : _scope = scope;

  RequestScope _scope;
  List<RequestRow> _rows = const [];
  String? _next;
  int _queueCount = 0;
  int _mineCount = 0;
  bool _loading = false;
  String? _error;
  String? _notice;
  int _generation = 0;
  bool _disposed = false;

  RequestScope get scope => _scope;
  List<RequestRow> get rows => _rows;
  bool get hasMore => _next != null;
  int get queueCount => _queueCount;
  int get mineCount => _mineCount;
  bool get loading => _loading;
  String? get error => _error;
  String? get notice => _notice;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final gen = ++_generation;
    _loading = true;
    _changed();
    try {
      final page = await connection.track(() => repo.requests(_scope));
      if (gen != _generation) return;
      _rows = page.rows;
      _next = page.next;
      _queueCount = page.queueCount;
      _mineCount = page.mineCount;
      _error = null;
    } catch (e) {
      if (gen == _generation) _error = errorText(e);
    } finally {
      if (gen == _generation) {
        _loading = false;
        _changed();
      }
    }
  }

  Future<void> loadMore() async {
    final cursor = _next;
    if (cursor == null || _loading) return;
    final gen = _generation;
    try {
      final page = await connection.track(() => repo.requests(_scope, cursor: cursor));
      if (gen != _generation) return;
      _rows = [..._rows, ...page.rows];
      _next = page.next;
      _queueCount = page.queueCount;
      _mineCount = page.mineCount;
    } catch (e) {
      _error = errorText(e);
    }
    _changed();
  }

  void setScope(RequestScope scope) {
    if (scope == _scope) return;
    _scope = scope;
    _rows = const [];
    _next = null;
    load();
  }

  /// «برداشتن». A colleague who was quicker (409 `taken`) is said in Persian; the list is read again either way.
  Future<bool> take(String requestId) async {
    _error = null;
    _notice = null;
    try {
      await connection.track(() => repo.takeRequest(requestId));
      _notice = 'درخواست برداشته شد.';
      return true;
    } catch (e) {
      _error = errorText(e);
      return false;
    } finally {
      _changed();
      unawaited(load());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Notifications

/// The notifications screen and the unread badge, fed by [NotificationPoller.items].
class NotificationsController extends ChangeNotifier {
  final NotificationPoller poller;
  final int max;
  StreamSubscription<AppNotification>? _sub;
  NotificationsController(this.poller, {this.max = 100}) {
    _sub = poller.items.listen(_add);
  }

  final List<AppNotification> _items = [];
  int _unread = 0;

  /// Newest first.
  List<AppNotification> get items => List.unmodifiable(_items);
  int get unread => _unread;

  void _add(AppNotification n) {
    _items.insert(0, n);
    if (_items.length > max) _items.removeRange(max, _items.length);
    _unread = (_unread + 1).clamp(0, max);
    notifyListeners();
  }

  void markAllRead() {
    if (_unread == 0) return;
    _unread = 0;
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _unread = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Config

/// GET /config once per sign-in: switches, theme overrides (passed through untouched), latest build, call reasons.
class ConfigController extends ValueNotifier<AppConfig?> {
  final TechRepository repo;
  final ConnectionController connection;
  ConfigController(this.repo, this.connection) : super(null);

  String? error;

  Future<AppConfig?> load() async {
    try {
      value = await connection.track(repo.loadConfig);
      error = null;
    } catch (e) {
      error = errorText(e);
      notifyListeners();
    }
    return value;
  }

  List<CallReason> get callReasons => value?.callReasons ?? const [];
}
