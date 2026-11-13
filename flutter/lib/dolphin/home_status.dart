import 'tech_card.dart';
import 'verify.dart';

/// What the coloured bar at the top of the customer window says (DD-43, merged review page `ui-c-state`), with the
/// status dot (DD-33). The wording matches the portal's.
enum HomeBar { ready, coming, connected, connecting, offline, stopped }

const kBarReady = 'آماده برای پشتیبانی';

/// Under «آماده برای پشتیبانی» (design C1).
const kBarReadyHint = 'کارشناس دلفین فقط وقتی این پنجره باز است وصل می‌شود.';
const kBarComing = 'کارشناس در راه است';
const kBarConnected = 'کارشناس وصل است';
const kBarConnecting = 'در حال اتصال به سرور دلفین…';

/// DD-33: the app cannot reach Dolphin's server. The second line says what to do.
const kBarOffline = 'بدون اینترنت';
const kBarOfflineHint = 'به سرور دلفین وصل نیست. اینترنت را بررسی کنید؛ برنامه خودش دوباره تلاش می‌کند.';

/// DD-33, during a live session: one quiet line instead of the red bar (the session may still be running).
const kBarOfflineQuiet = 'ارتباط با سرور دلفین قطع است.';

/// What the stopped state says (BL-SVC).
const kServiceStoppedLabel = 'سرویس دلفین خاموش است';

enum DolphinServerState { ready, connecting, offline, stopped }

/// The rendezvous status the client reports: 1 connected, 0 connecting, -1 not ready. A stopped service (the
/// `stop-service` option) wins: the app then never signs in to the server and the status would stay "connecting"
/// for ever (BL-SVC, 2026-10-29).
DolphinServerState serverStateFromStatus(int statusNum, {bool serviceStopped = false}) => serviceStopped
    ? DolphinServerState.stopped
    : statusNum > 0
        ? DolphinServerState.ready
        : statusNum == 0
            ? DolphinServerState.connecting
            : DolphinServerState.offline;

class HomeStatus {
  final HomeBar bar;

  final TechComing? tech;

  /// DD-33: a session is live but the server is not reachable; the bar stays «کارشناس وصل است» with a quiet line.
  final bool quietOffline;

  /// True while the server knows this PC (the dot is aqua, as the portal's «در دسترس»).
  final bool online;

  const HomeStatus(this.bar, {this.tech, this.quietOffline = false, this.online = false});

  /// The technician the portal named, '' when it did not (the bar then says «کارشناس دلفین»).
  String get techName => tech?.name ?? '';
}

/// The technician the portal has authorized for this PC right now (options pushed with the heartbeat), whether or not
/// they are connected. Null for "-", nothing, or an authorization that ended (same clock margin as the prompt).
TechComing? authorizedTech(
    {required String techId,
    required String techName,
    required int until,
    required int nowSeconds,
    required String photo}) {
  if (techId.isEmpty || techId == '-') return null;
  if (nowSeconds >= until + kDolphinClockSkewSeconds) return null;
  return TechComing(techName == '-' ? '' : techName, techPhoto(photo));
}

/// Which bar to show. A stopped service wins; then a live session (with a quiet line if the server is gone); then
/// no server («بدون اینترنت»); then connecting; then a technician on the way; otherwise ready.
/// [connected] is the server's session count, null until the first read (no session assumed, no technician card).
HomeStatus homeStatus({required DolphinServerState server, required int? connected, TechComing? tech}) {
  final online = server == DolphinServerState.ready;
  if (server == DolphinServerState.stopped) return const HomeStatus(HomeBar.stopped);
  if ((connected ?? 0) > 0) {
    return HomeStatus(HomeBar.connected, tech: tech, quietOffline: server == DolphinServerState.offline, online: online);
  }
  if (server == DolphinServerState.offline) return const HomeStatus(HomeBar.offline);
  if (server == DolphinServerState.connecting) return const HomeStatus(HomeBar.connecting);
  if (connected != null && tech != null) return HomeStatus(HomeBar.coming, tech: tech, online: true);
  return const HomeStatus(HomeBar.ready, online: true);
}

/// The card's title (design C1): «آماده برای پشتیبانی», «کارشناس در راه است», «علی رضایی وصل است» (or «کارشناس وصل
/// است» when the portal named nobody), «بدون اینترنت».
String homeBarTitle(HomeStatus s) => switch (s.bar) {
      HomeBar.ready => kBarReady,
      HomeBar.coming => kBarComing,
      HomeBar.connected => s.techName.isEmpty ? kBarConnected : '${s.techName} وصل است',
      HomeBar.connecting => kBarConnecting,
      HomeBar.offline => kBarOffline,
      HomeBar.stopped => kServiceStoppedLabel,
    };

/// The card's second line, or '' for none.
String homeBarDetail(HomeStatus s) {
  final who = s.techName.isEmpty ? 'کارشناس دلفین' : s.techName;
  switch (s.bar) {
    case HomeBar.ready:
      return kBarReadyHint;
    case HomeBar.coming:
      return '$who اجازه‌ی اتصال دارد؛ اگر پیام اتصال آمد، «پذیرفتن» را بزنید.';
    case HomeBar.connected:
      return 'هر وقت خواستید، «پایان» را در پنجره‌ی جلسه بزنید.';
    case HomeBar.offline:
      return kBarOfflineHint;
    case HomeBar.connecting:
    case HomeBar.stopped:
      return '';
  }
}
