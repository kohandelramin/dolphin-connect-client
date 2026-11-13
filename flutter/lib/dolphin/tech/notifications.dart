import 'dart:async';

import 'api.dart';

/// Plan 19 (TD-6): new notifications from the portal, polled every 15 s with `since` (the last item's `at`), each id
/// reported once. The Windows toast and the notifications screen listen to [items]; this file draws nothing.
const kNotificationPoll = Duration(seconds: 15);

/// Ids remembered for dedupe; older ones are forgotten (their `at` is long behind `since` by then).
const kNotificationSeenMax = 500;

class NotificationPoller {
  final ApiClient _api;
  final Duration interval;
  NotificationPoller(this._api, {this.interval = kNotificationPoll});

  final _out = StreamController<AppNotification>.broadcast();
  final _seen = <String>{}; // insertion-ordered (LinkedHashSet), oldest first
  DateTime? _since;
  Timer? _timer;
  bool _polling = false;

  /// Every notification not seen before, oldest first within one poll.
  Stream<AppNotification> get items => _out.stream;

  /// The `since` the next poll sends (null before the first answer).
  DateTime? get since => _since;

  bool get running => _timer != null;

  /// Polls now, then every [interval].
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => poll());
    poll();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Forgets what was seen (sign-out), so the next technician starts fresh.
  void reset() {
    stop();
    _seen.clear();
    _since = null;
  }

  /// One poll. Returns the new items. Network trouble is quiet (the next poll tries again); a finished sign-in stops
  /// polling (the session store shows the sign-in screen).
  Future<List<AppNotification>> poll() async {
    if (_polling) return const [];
    _polling = true;
    try {
      final list = await _api.notifications(since: _since);
      final fresh = <AppNotification>[];
      for (final n in list) {
        if (_since == null || n.at.isAfter(_since!)) _since = n.at;
        if (!_seen.add(n.id)) continue;
        fresh.add(n);
      }
      while (_seen.length > kNotificationSeenMax) {
        _seen.remove(_seen.first);
      }
      for (final n in fresh) {
        if (!_out.isClosed) _out.add(n);
      }
      return fresh;
    } on SignInExpired {
      stop();
      return const [];
    } catch (_) {
      return const [];
    } finally {
      _polling = false;
    }
  }

  void dispose() {
    stop();
    _out.close();
  }
}
